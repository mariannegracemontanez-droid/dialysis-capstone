-- Run this manually in the Supabase SQL editor.
-- Run AFTER center_scheduling_foundation.sql.
--
-- Fixes the EXISTING set_patient_recurring_schedule function (create or
-- replace -- no new function, no new trigger, no second status system).
--
-- The patient lifecycle the database already defines is:
--
--   pending   -> applied, not yet reviewed by the center
--   no_sched  -> ACCEPTED/reserved by the center, no recurring schedule yet
--   active    -> accepted AND holds an active recurring schedule
--   declined / deleted -> not reserved
--
-- `no_sched` + `active` are exactly the two statuses the Super Admin
-- capacity estimate counts as reserved for a clinic (see
-- super_admin_app/lib/services/dashboard_service.dart), so `active` must
-- never be reachable except by actually saving a recurring schedule.
--
-- What changed: the function used to row-lock the patient and then set
-- status = 'active' without ever looking at what the status WAS. A patient
-- still sitting at 'pending' -- never accepted by anyone -- could be taken
-- straight to 'active', skipping the accepted/reserved step entirely. The
-- lock now also reads the status and refuses anything that has not been
-- accepted.
--
-- What did NOT change: this function remains the ONE place a patient
-- becomes 'active', and it is a single plpgsql body, so it is already one
-- transaction -- if either the weekly_schedules insert or any
-- patient_schedule_days insert fails, the status update rolls back with it
-- and the patient stays 'no_sched'. That behaviour is relied on, not
-- replaced.

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
as $fn$
declare
  v_weekly_schedule_id uuid;
  -- weekly_schedules.scheduled_days is a jsonb array of day names (e.g.
  -- ["Monday","Wednesday"]), which is what the mobile app, the Patients
  -- page and the day-level queries all already read -- so build jsonb
  -- here, not a text[].
  v_scheduled_days jsonb;
  v_entry jsonb;
  v_status text;
begin
  if p_day_shifts is null or jsonb_typeof(p_day_shifts) <> 'array'
     or jsonb_array_length(p_day_shifts) = 0 then
    raise exception 'Please select at least one day and shift.';
  end if;

  -- Row-lock the patient for the rest of this transaction so a
  -- concurrent scheduling attempt on the same patient can't race past
  -- the duplicate check below. Reading the status under the same lock is
  -- what makes the acceptance check below race-free too.
  select status into v_status
    from patients
    where id = p_patient_id and clinic_id = p_clinic_id
    for update;

  if not found then
    raise exception 'Patient not found for this clinic.';
  end if;

  -- Only an ACCEPTED patient may be given a recurring schedule.
  -- 'no_sched' is the accepted-but-unscheduled state; 'active' and
  -- 'approved' are tolerated so an existing patient is never locked out
  -- by older data (the duplicate-schedule check below still applies).
  if v_status is null or v_status not in ('no_sched', 'active', 'approved') then
    raise exception
      'This patient has not been accepted by the center yet (current status: '
      '%). Accept the patient first, then assign their schedule.',
      coalesce(v_status, 'unknown');
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

  -- THE one place a patient becomes 'active'. It runs last, in the same
  -- transaction as the two inserts above, so 'active' can only ever mean
  -- "this patient has a recurring schedule that was actually saved".
  -- clinic_id is left exactly as it is -- the patient stays with the
  -- clinic that accepted them, which is what the Super Admin capacity
  -- estimate groups by.
  update patients
    set status = 'active'
    where id = p_patient_id and clinic_id = p_clinic_id;
end;
$fn$;

grant execute on function public.set_patient_recurring_schedule(uuid, uuid, uuid, jsonb) to authenticated;
