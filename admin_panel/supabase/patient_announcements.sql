-- Run this manually in the Supabase SQL editor.
--
-- Patient Announcements: short, center-authored notices that the Center
-- Admin writes and the CureNurture mobile app shows to that center's
-- patients (center events, reminders, schedule notices, a sudden day the
-- center cannot operate).
--
-- Deliberately isolated. It adds ONE new table and touches nothing that
-- already exists: no column is added to clinics, patients, profiles,
-- weekly_schedules, daily_schedules or reschedule_requests, and no
-- existing policy, trigger or function is modified. Nothing in the
-- scheduling or donation flows reads or writes it.
--
-- Everything here is idempotent and safe to re-run.

-- =====================================================================
-- 1. patient_announcements
-- =====================================================================
--
-- Column notes, kept to only what the feature needs:
--
--   clinic_id          scopes an announcement to one center, exactly the
--                      way reschedule_requests.clinic_id does. It is what
--                      both RLS and the mobile app's query filter on.
--   title              the headline on the card.
--   body               the announcement text.
--   announcement_date  OPTIONAL. Set only when the notice is about a
--                      specific day (an event, a closure); null for a
--                      general notice. It is NOT the publish date --
--                      created_at already records that.
--   color              a stable theme TOKEN, not a hex value, so the
--                      admin panel and the mobile app can each render it
--                      in their own palette without one hard-coding the
--                      other's colours.
--   created_by         the admin who wrote it (auth.users), matching the
--                      created_by/reviewed_by convention already used on
--                      daily_schedules and reschedule_requests.
--
-- Nothing is duplicated here: the center's name, the admin's name and the
-- patient list all stay where they already live and are joined when
-- needed.

create table if not exists patient_announcements (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references clinics(id) on delete cascade,
  title text not null,
  body text not null,
  announcement_date date,
  color text not null default 'blue',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Re-runnable on a database where the table already exists.
alter table patient_announcements
  add column if not exists announcement_date date,
  add column if not exists color text not null default 'blue',
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_at timestamptz not null default now();

-- The colour vocabulary the admin panel offers. Tokens rather than hex
-- values, so adding a shade later is a one-line change in both clients
-- and never a data migration.
alter table patient_announcements
  drop constraint if exists patient_announcements_color_check;

alter table patient_announcements
  add constraint patient_announcements_color_check
    check (color in (
      'blue',        -- general information
      'light_blue',  -- gentle notice
      'green',       -- positive / confirmed
      'orange',      -- reminder, needs attention
      'purple',      -- administrative
      'red'          -- urgent: closures, emergencies
    ));

-- An empty title or body would render as a blank card in the mobile app.
alter table patient_announcements
  drop constraint if exists patient_announcements_title_not_blank;

alter table patient_announcements
  add constraint patient_announcements_title_not_blank
    check (length(btrim(title)) > 0);

alter table patient_announcements
  drop constraint if exists patient_announcements_body_not_blank;

alter table patient_announcements
  add constraint patient_announcements_body_not_blank
    check (length(btrim(body)) > 0);

-- The one read both clients make: this center's announcements, newest
-- first. Covers the admin list and the mobile app feed alike.
create index if not exists patient_announcements_clinic_created_idx
  on patient_announcements (clinic_id, created_at desc);

-- Supports a mobile-side "what is coming up" filter on the optional date
-- without a sequential scan.
create index if not exists patient_announcements_clinic_date_idx
  on patient_announcements (clinic_id, announcement_date)
  where announcement_date is not null;

-- ---------------------------------------------------------------------
-- 1b. updated_at
-- ---------------------------------------------------------------------
-- Kept honest in the database so an edit always stamps it, no matter
-- which client made the change.

create or replace function public.patient_announcements_touch_updated_at()
returns trigger
language plpgsql
as $fn$
begin
  new.updated_at = now();
  return new;
end;
$fn$;

drop trigger if exists patient_announcements_touch_updated_at_trg
  on patient_announcements;

create trigger patient_announcements_touch_updated_at_trg
  before update on patient_announcements
  for each row
  execute function public.patient_announcements_touch_updated_at();

-- ---------------------------------------------------------------------
-- 1c. clinic_id / created_by integrity
-- ---------------------------------------------------------------------
-- The admin panel never has to send either one, and cannot send another
-- center's id: both are filled from the authenticated profile on insert.
-- Same shape as reschedule_requests_set_clinic().

create or replace function public.patient_announcements_set_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if new.created_by is null then
    new.created_by = auth.uid();
  end if;

  select p.clinic_id into new.clinic_id
  from profiles p
  where p.id = auth.uid()
    and p.role = 'admin';

  return new;
end;
$fn$;

drop trigger if exists patient_announcements_set_owner_trg
  on patient_announcements;

create trigger patient_announcements_set_owner_trg
  before insert on patient_announcements
  for each row
  execute function public.patient_announcements_set_owner();

-- =====================================================================
-- 2. RLS -- the same role/clinic ownership checks used elsewhere
-- =====================================================================

alter table patient_announcements enable row level security;

-- Center Admin: full management of their OWN center's announcements, and
-- no visibility into another center's.
drop policy if exists "Admins can view own clinic announcements" on patient_announcements;
create policy "Admins can view own clinic announcements"
on patient_announcements
for select
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_announcements.clinic_id
  )
);

drop policy if exists "Admins can create own clinic announcements" on patient_announcements;
create policy "Admins can create own clinic announcements"
on patient_announcements
for insert
to authenticated
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_announcements.clinic_id
  )
);

drop policy if exists "Admins can update own clinic announcements" on patient_announcements;
create policy "Admins can update own clinic announcements"
on patient_announcements
for update
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_announcements.clinic_id
  )
)
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_announcements.clinic_id
  )
);

drop policy if exists "Admins can delete own clinic announcements" on patient_announcements;
create policy "Admins can delete own clinic announcements"
on patient_announcements
for delete
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_announcements.clinic_id
  )
);

-- Mobile app: a patient reads the announcements of the center they belong
-- to, and only those. Read-only -- a patient can never write one. Mirrors
-- the patients.profile_id = auth.uid() check the reschedule policies use.
drop policy if exists "Patients can view own center announcements" on patient_announcements;
create policy "Patients can view own center announcements"
on patient_announcements
for select
to authenticated
using (
  exists (
    select 1 from patients pt
    where pt.profile_id = auth.uid()
      and pt.clinic_id = patient_announcements.clinic_id
  )
);

-- =====================================================================
-- 3. Mobile app contract
-- =====================================================================
--
-- The feed the app should read is a single, plain query -- no join, no
-- view, no function:
--
--   select id, title, body, announcement_date, color, created_at
--   from patient_announcements
--   where clinic_id = <the patient's clinic_id>
--   order by created_at desc;
--
-- RLS already restricts the rows to the signed-in patient's own center,
-- so the where clause is an index hint rather than the security boundary.
--
-- `color` is one of the six tokens in the check constraint above; the app
-- maps each token to a soft background from its own palette and should
-- fall back to its neutral style for any token it does not recognise, so
-- adding a shade later never breaks an older app build.
