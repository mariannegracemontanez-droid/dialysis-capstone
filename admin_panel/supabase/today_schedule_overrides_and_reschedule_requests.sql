-- Run this manually in the Supabase SQL editor.
--
-- Two related pieces, both built on the scheduling architecture that
-- already exists (weekly_schedules + patient_schedule_days for the
-- RECURRING schedule, daily_schedules for the ACTUAL per-date session):
--
--   1. A one-day override for daily_schedules, so "remove this patient
--      from TODAY" stops being a DELETE. A deleted row was silently
--      re-created on the next refresh by
--      CenterScheduleService.generateTodayDefaultSchedule (it regenerates
--      today's list from the recurring schedule and only skips patients
--      that already have a daily_schedules row for that date) -- which is
--      exactly why the Remove button appeared to do nothing. The row is
--      now CANCELLED in place instead: it stays as the tombstone that
--      stops regeneration for that one date, while
--      patient_schedule_days / weekly_schedules / patients.preferred_shift
--      are never touched, so the patient still recurs normally on every
--      other scheduled day.
--
--   2. The reschedule_requests table the mobile app already writes to
--      (mobile-app/lib/services/reschedule_service.dart) gets the few
--      columns, constraints and policies the Center Admin review flow
--      needs -- it is NOT replaced, and no second request table is added.
--
-- Everything here is idempotent and safe to re-run.

-- =====================================================================
-- 1. daily_schedules: a cancelled (one-day-off) occurrence
-- =====================================================================

-- 'cancelled' joins the existing 'pending'/'completed' vocabulary from
-- dialysis_session_tracking.sql.
alter table daily_schedules
  drop constraint if exists daily_schedules_status_check;

alter table daily_schedules
  add constraint daily_schedules_status_check
    check (status in ('pending', 'completed', 'cancelled'));

alter table daily_schedules
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references auth.users(id),
  add column if not exists cancel_reason text;

-- Links a one-time occurrence back to the approved patient request that
-- created it. Also how "this approved reschedule has already been used"
-- is detected, so the same request can't be applied twice.
alter table daily_schedules
  add column if not exists reschedule_request_id uuid;

-- Speeds up the per-date reads the dashboard does on every refresh.
create index if not exists daily_schedules_clinic_date_status_idx
  on daily_schedules (clinic_id, schedule_date, status);

-- NOTE: daily_schedules_patient_date_unique (patient_id, schedule_date),
-- created in center_scheduling_foundation.sql, is what guarantees a
-- patient can never appear twice on one date -- including once in AM and
-- once in PM. Moving a patient between shifts is therefore always an
-- UPDATE of that single row, never a second INSERT.

-- =====================================================================
-- 2. reschedule_requests
-- =====================================================================

-- Created only if the mobile app's table isn't there yet; the column
-- list matches exactly what RescheduleService.submitRequest writes.
create table if not exists reschedule_requests (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients(id) on delete cascade,
  original_date date,
  requested_date date,
  reason text,
  notes text,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

-- Columns the Center Admin review flow adds. clinic_id is what scopes a
-- request to one center for both RLS and the dashboard query; it is
-- backfilled from the patient below so existing mobile rows are picked up.
alter table reschedule_requests
  add column if not exists clinic_id uuid references clinics(id) on delete cascade,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists admin_notes text,
  -- The date/shift the admin actually settled on. Equal to requested_date
  -- for a plain accept; different when the admin used "Change Date".
  add column if not exists resolved_date date,
  add column if not exists resolved_shift text,
  add column if not exists applied_daily_schedule_id uuid;

update reschedule_requests r
  set clinic_id = p.clinic_id
  from patients p
  where p.id = r.patient_id
    and r.clinic_id is null;

-- Status vocabulary keeps the mobile app's existing 'approved'/'declined'
-- wording (schedule_tab.dart already renders those) and adds
-- 'changed_date' for an accept on a date other than the one requested.
alter table reschedule_requests
  drop constraint if exists reschedule_requests_status_check;

alter table reschedule_requests
  add constraint reschedule_requests_status_check
    check (status in ('pending', 'approved', 'declined', 'changed_date', 'cancelled'));

alter table reschedule_requests
  drop constraint if exists reschedule_requests_resolved_shift_check;

alter table reschedule_requests
  add constraint reschedule_requests_resolved_shift_check
    check (resolved_shift is null or resolved_shift in ('AM', 'PM'));

create index if not exists reschedule_requests_clinic_status_idx
  on reschedule_requests (clinic_id, status, created_at desc);

create index if not exists reschedule_requests_patient_idx
  on reschedule_requests (patient_id, created_at desc);

-- A patient may not stack several pending requests for the same original
-- date -- the admin would otherwise have to reject duplicates by hand.
create unique index if not exists reschedule_requests_pending_unique
  on reschedule_requests (patient_id, original_date)
  where status = 'pending';

-- ---------------------------------------------------------------------
-- 2b. RLS -- same role/clinic ownership checks already used elsewhere
-- ---------------------------------------------------------------------
alter table reschedule_requests enable row level security;

-- Patient side: a patient can only ever see and create rows tied to one
-- of their own patient records (patients.profile_id = auth.uid()).
drop policy if exists "Patients can view own reschedule requests" on reschedule_requests;
create policy "Patients can view own reschedule requests"
on reschedule_requests
for select
to authenticated
using (
  exists (
    select 1 from patients pt
    where pt.id = reschedule_requests.patient_id
      and pt.profile_id = auth.uid()
  )
);

drop policy if exists "Patients can submit own reschedule requests" on reschedule_requests;
create policy "Patients can submit own reschedule requests"
on reschedule_requests
for insert
to authenticated
with check (
  status = 'pending'
  and exists (
    select 1 from patients pt
    where pt.id = reschedule_requests.patient_id
      and pt.profile_id = auth.uid()
  )
);

-- A patient may withdraw their own request while it is still pending,
-- but can never approve one or touch another patient's row.
drop policy if exists "Patients can cancel own pending reschedule requests" on reschedule_requests;
create policy "Patients can cancel own pending reschedule requests"
on reschedule_requests
for update
to authenticated
using (
  status = 'pending'
  and exists (
    select 1 from patients pt
    where pt.id = reschedule_requests.patient_id
      and pt.profile_id = auth.uid()
  )
)
with check (
  status in ('pending', 'cancelled')
  and exists (
    select 1 from patients pt
    where pt.id = reschedule_requests.patient_id
      and pt.profile_id = auth.uid()
  )
);

-- Center Admin side: scoped to the admin's own clinic, so one center can
-- never read or decide another center's requests.
drop policy if exists "Admins can view own clinic reschedule requests" on reschedule_requests;
create policy "Admins can view own clinic reschedule requests"
on reschedule_requests
for select
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = reschedule_requests.clinic_id
  )
);

drop policy if exists "Admins can review own clinic reschedule requests" on reschedule_requests;
create policy "Admins can review own clinic reschedule requests"
on reschedule_requests
for update
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = reschedule_requests.clinic_id
  )
)
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = reschedule_requests.clinic_id
  )
);

-- Keep clinic_id honest: a client never has to send it, and can't send a
-- different center's id either.
create or replace function public.reschedule_requests_set_clinic()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  select p.clinic_id into new.clinic_id
  from patients p
  where p.id = new.patient_id;

  return new;
end;
$fn$;

drop trigger if exists reschedule_requests_set_clinic_trg on reschedule_requests;
create trigger reschedule_requests_set_clinic_trg
  before insert on reschedule_requests
  for each row execute function public.reschedule_requests_set_clinic();
