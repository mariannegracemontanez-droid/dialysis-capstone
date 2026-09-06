-- Run this manually in the Supabase SQL editor.
--
-- Foundation for the Center Scheduling System phase. Adds the minimum new
-- structures needed to represent:
--   1. The center's configurable weekly operating days + shifts (name,
--      start/end time, configured capacity) -- previously the app assumed
--      every clinic is open Monday-Saturday with a hardcoded AM 08:00-12:00
--      / PM 13:00-17:00 split and used the raw machine count as capacity.
--   2. A patient's recurring schedule now carrying a DEFAULT SHIFT per day,
--      not just a bare day name.
-- It deliberately does NOT touch daily_schedules' meaning (still the real,
-- per-date session record) or weekly_schedules.scheduled_days (a jsonb
-- array of day names -- mobile-app, patients_page.dart, and the existing
-- schedule-recommendation/today-schedule services all read that shape
-- directly, so changing it would ripple into apps outside this phase's
-- scope). Shift-per-day is added as a new, separate table instead.

-- ---------------------------------------------------------------------
-- 1. Center weekly operating days
-- ---------------------------------------------------------------------
-- One row per clinic. Kept out of the `clinics` table itself so this
-- phase doesn't need to grant center admins a broad UPDATE policy on a
-- table that also holds fields (machine, reserved_machines, name, ...)
-- that may be superadmin-managed elsewhere.
create table if not exists clinic_schedule_settings (
  clinic_id uuid primary key references clinics(id) on delete cascade,
  operating_days text[] not null default array[
    'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'
  ],
  updated_at timestamptz not null default now()
);

alter table clinic_schedule_settings enable row level security;

drop policy if exists "Admins can view own clinic schedule settings" on clinic_schedule_settings;
create policy "Admins can view own clinic schedule settings"
on clinic_schedule_settings
for select
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = clinic_schedule_settings.clinic_id
  )
);

drop policy if exists "Admins can upsert own clinic schedule settings" on clinic_schedule_settings;
create policy "Admins can upsert own clinic schedule settings"
on clinic_schedule_settings
for insert
to authenticated
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = clinic_schedule_settings.clinic_id
  )
);

drop policy if exists "Admins can update own clinic schedule settings" on clinic_schedule_settings;
create policy "Admins can update own clinic schedule settings"
on clinic_schedule_settings
for update
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = clinic_schedule_settings.clinic_id
  )
)
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = clinic_schedule_settings.clinic_id
  )
);

-- ---------------------------------------------------------------------
-- 2. Center shifts (name/label, start/end time, configured capacity)
-- ---------------------------------------------------------------------
-- shift_code stays fixed to AM/PM -- daily_schedules.shift, the mobile
-- app, and every existing admin_panel query already key off that exact
-- two-value string. What becomes configurable per clinic is the label,
-- the times, and the capacity (never derived from machine count alone).
create table if not exists clinic_shifts (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  shift_code text not null check (shift_code in ('AM', 'PM')),
  shift_label text not null default '',
  start_time time not null,
  end_time time not null,
  capacity integer not null check (capacity >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (clinic_id, shift_code)
);

alter table clinic_shifts enable row level security;

drop policy if exists "Admins can view own clinic shifts" on clinic_shifts;
create policy "Admins can view own clinic shifts"
on clinic_shifts
for select
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = clinic_shifts.clinic_id
  )
);

drop policy if exists "Admins can insert own clinic shifts" on clinic_shifts;
create policy "Admins can insert own clinic shifts"
on clinic_shifts
for insert
to authenticated
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = clinic_shifts.clinic_id
  )
);

drop policy if exists "Admins can update own clinic shifts" on clinic_shifts;
create policy "Admins can update own clinic shifts"
on clinic_shifts
for update
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = clinic_shifts.clinic_id
  )
)
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = clinic_shifts.clinic_id
  )
);

-- Seed AM/PM for every existing clinic using exactly the values that were
-- previously hardcoded in ScheduleService.assignDailySchedule, and the
-- clinic's current machine count as the starting capacity -- so nothing
-- changes behaviorally the moment this migration runs. Admins can then
-- tune label/times/capacity independently per shift going forward.
insert into clinic_shifts (clinic_id, shift_code, shift_label, start_time, end_time, capacity, is_active)
select
  c.id,
  v.shift_code,
  v.shift_label,
  v.start_time,
  v.end_time,
  greatest(coalesce(c.machine, 0), 0),
  true
from clinics c
cross join (
  values
    ('AM', 'Morning', time '08:00', time '12:00'),
    ('PM', 'Afternoon', time '13:00', time '17:00')
) as v(shift_code, shift_label, start_time, end_time)
on conflict (clinic_id, shift_code) do nothing;

-- ---------------------------------------------------------------------
-- 3. Patient recurring schedule gains an active flag + a default shift
--    per day
-- ---------------------------------------------------------------------
alter table weekly_schedules
  add column if not exists is_active boolean not null default true;

-- One row per (recurring schedule, day). scheduled_days on
-- weekly_schedules stays the flat day-name array every existing reader
-- already expects; this table is the new, additive source of "which
-- shift is the default for this day" that only the new scheduling code
-- reads.
create table if not exists patient_schedule_days (
  id uuid primary key default gen_random_uuid(),
  weekly_schedule_id uuid not null references weekly_schedules(id) on delete cascade,
  clinic_id uuid not null references clinics(id) on delete cascade,
  day_of_week text not null check (
    day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')
  ),
  shift_id uuid not null references clinic_shifts(id),
  created_at timestamptz not null default now(),
  unique (weekly_schedule_id, day_of_week)
);

alter table patient_schedule_days enable row level security;

drop policy if exists "Admins can view own clinic patient schedule days" on patient_schedule_days;
create policy "Admins can view own clinic patient schedule days"
on patient_schedule_days
for select
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_schedule_days.clinic_id
  )
);

drop policy if exists "Admins can manage own clinic patient schedule days" on patient_schedule_days;
create policy "Admins can manage own clinic patient schedule days"
on patient_schedule_days
for all
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_schedule_days.clinic_id
  )
)
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_schedule_days.clinic_id
  )
);

-- ---------------------------------------------------------------------
-- 4. A daily session can't be duplicated -- enforce it as a real
--    constraint, not just the app's isPatientAlreadyAssigned check.
-- ---------------------------------------------------------------------
-- If this fails with a uniqueness violation, the clinic already has
-- duplicate daily_schedules rows for the same patient/date that need to
-- be cleaned up manually first.
create unique index if not exists daily_schedules_patient_date_unique
  on daily_schedules (patient_id, schedule_date);

-- ---------------------------------------------------------------------
-- 5. Recurring schedule save -- now day + default shift, atomically
-- ---------------------------------------------------------------------
-- Supersedes set_patient_weekly_schedule (days-only, added for the
-- previous phase) now that a schedule always carries a shift per day.
drop function if exists public.set_patient_weekly_schedule(uuid, uuid, text[], uuid);

-- p_day_shifts shape: '[{"day":"Monday","shift_id":"<uuid>"}, ...]'
create or replace function public.set_patient_recurring_schedule(
  p_patient_id uuid,
  p_clinic_id uuid,
  p_created_by uuid,
  p_day_shifts jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_weekly_schedule_id uuid;
  -- weekly_schedules.scheduled_days is a jsonb array of day names (e.g.
  -- ["Monday","Wednesday"]), which is what the mobile app, the Patients
  -- page and the day-level queries all already read -- so build jsonb
  -- here, not a text[].
  v_scheduled_days jsonb;
  v_entry jsonb;
begin
  if p_day_shifts is null or jsonb_typeof(p_day_shifts) <> 'array'
     or jsonb_array_length(p_day_shifts) = 0 then
    raise exception 'Please select at least one day and shift.';
  end if;

  -- Row-lock the patient for the rest of this transaction so a
  -- concurrent scheduling attempt on the same patient can't race past
  -- the duplicate check below.
  perform 1 from patients
    where id = p_patient_id and clinic_id = p_clinic_id
    for update;

  if not found then
    raise exception 'Patient not found for this clinic.';
  end if;

  if exists (select 1 from weekly_schedules where patient_id = p_patient_id) then
    raise exception 'This patient already has an active weekly schedule.';
  end if;

  select jsonb_agg(elem ->> 'day') into v_scheduled_days
  from jsonb_array_elements(p_day_shifts) elem;

  insert into weekly_schedules (patient_id, clinic_id, created_by, scheduled_days, is_active)
  values (p_patient_id, p_clinic_id, p_created_by, v_scheduled_days, true)
  returning id into v_weekly_schedule_id;

  for v_entry in select * from jsonb_array_elements(p_day_shifts)
  loop
    insert into patient_schedule_days (weekly_schedule_id, clinic_id, day_of_week, shift_id)
    values (
      v_weekly_schedule_id,
      p_clinic_id,
      v_entry ->> 'day',
      (v_entry ->> 'shift_id')::uuid
    );
  end loop;

  update patients
    set status = 'active'
    where id = p_patient_id and clinic_id = p_clinic_id;
end;
$$;

grant execute on function public.set_patient_recurring_schedule(uuid, uuid, uuid, jsonb) to authenticated;
