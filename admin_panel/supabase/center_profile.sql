-- Run this manually in the Supabase SQL editor.
-- Run AFTER center_scheduling_foundation.sql.
--
-- Backing for the Center Admin's new "Center Profile" page.
--
-- WHAT THIS DOES NOT DO
-- ---------------------
-- It creates no new capacity field, no second requirements store and no
-- second shift system. Every value the page edits already exists:
--
--   capacity           -> clinics.machine        (dialysis machines)
--                      -> clinic_shifts.capacity (per-shift scheduling cap,
--                         the figure CenterScheduleService.getCapacitySnapshot
--                         actually schedules against -- already editable by
--                         admins through the clinic_shifts RLS policies)
--   requirements       -> clinics.requirements   (text[], the SAME column the
--                         Super Admin Add/Edit Center form writes)
--   operating hours    -> clinics.operating_hours (text, the SAME column the
--                         mobile app displays)
--   shift times        -> clinic_shifts.start_time / end_time
--
-- The one genuinely new field is house_rules, which had no home anywhere in
-- the schema.

-- ---------------------------------------------------------------------
-- 1. House rules
-- ---------------------------------------------------------------------
-- One free-form multiline block per center, deliberately NOT a list table:
-- the requirement is a single text area the admin types into, and a center's
-- house rules are prose, not enumerable records.
alter table clinics
  add column if not exists house_rules text;

-- ---------------------------------------------------------------------
-- 2. Center-admin write path for their OWN clinic row
-- ---------------------------------------------------------------------
-- center_scheduling_foundation.sql deliberately kept clinic-level settings
-- out of `clinics` rather than grant center admins a broad UPDATE policy on
-- a table that also holds Super-Admin-managed columns (name, address,
-- latitude/longitude, slots_available, status, contact_number, ...).
--
-- That reasoning still holds, so this does NOT add such a policy. Instead a
-- single security-definer function updates exactly the four columns the
-- Center Profile page owns, for exactly the caller's own clinic, after
-- re-checking the caller's role and clinic_id server-side. Everything else
-- on the row stays unreachable from the admin panel.
--
-- security definer + a pinned search_path is what lets it write past RLS
-- without loosening RLS for anything else.
create or replace function public.update_center_profile(
  p_clinic_id uuid,
  p_machine integer,
  p_requirements text[],
  p_operating_hours text,
  p_house_rules text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
begin
  -- Authorization, re-derived from the session rather than trusted from the
  -- client: the caller must be an `admin` profile whose clinic_id IS the
  -- clinic being edited. A center admin can therefore never reach another
  -- center's row, whatever p_clinic_id they pass.
  select exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = p_clinic_id
  ) into v_is_admin;

  if not v_is_admin then
    raise exception
      'You can only edit the center your account is assigned to.';
  end if;

  -- The same rules the UI validates, enforced again here so an invalid
  -- value can never be written by a client that skipped the form.
  if p_machine is null or p_machine < 0 then
    raise exception 'Please enter a valid number of dialysis machines.';
  end if;

  if p_machine > 500 then
    raise exception 'The number of dialysis machines looks too large. '
                    'Please enter 500 or fewer.';
  end if;

  update clinics
     set machine          = p_machine,
         requirements     = coalesce(p_requirements, array[]::text[]),
         operating_hours  = p_operating_hours,
         house_rules      = p_house_rules
   where id = p_clinic_id;
end;
$$;

revoke all on function public.update_center_profile(uuid, integer, text[], text, text) from public;
grant execute on function public.update_center_profile(uuid, integer, text[], text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Session history read path
-- ---------------------------------------------------------------------
-- The Patients page's new "View Session History" reads completed sessions
-- straight out of daily_schedules (dialysis_session_duration.sql already put
-- before/after weight, before blood pressure and session duration there --
-- one row IS one session). No new table.
--
-- Center admins already hold a SELECT policy on daily_schedules for their
-- own clinic, and every query in SessionHistoryService additionally filters
-- `.eq('clinic_id', <the admin's own clinic>)`, so nothing here widens
-- access. This index just keeps the per-patient history query cheap as the
-- table grows.
create index if not exists daily_schedules_patient_history_idx
  on daily_schedules (patient_id, clinic_id, schedule_date desc);
