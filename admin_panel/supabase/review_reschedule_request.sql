-- Run this manually in the Supabase SQL editor, AFTER
-- today_schedule_overrides_and_reschedule_requests.sql.
--
-- The Center Admin decision on a patient's reschedule request, applied as
-- one transaction so a half-applied reschedule (original day cancelled but
-- the new day never created, or vice versa) is impossible.
--
-- What it deliberately does NOT do -- ever:
--   * touch weekly_schedules.scheduled_days
--   * touch patient_schedule_days (day or shift_id)
--   * touch patients.preferred_shift
-- An accepted request is a ONE-TIME change: the original date's occurrence
-- is cancelled in daily_schedules and a new occurrence is created for the
-- granted date. The patient's recurring weekly schedule is untouched, so
-- they keep appearing on every other scheduled day exactly as before.
--
-- security invoker: the admin's own RLS policies apply to every read and
-- write below, so this function can never be used to reach another
-- center's data.
--
-- Capacity note: the authoritative, admin-facing capacity figure is the
-- one CenterScheduleService.getCapacitySnapshot produces (it also applies
-- clinics.target_daily_capacity as a day-level cap). The check here is the
-- database's independent last line of defense against a race, using the
-- shift's own configured capacity -- it is intentionally not a second
-- implementation of the day-cap rule.

create or replace function public.review_reschedule_request(
  p_request_id uuid,
  p_decision text,
  p_target_date date default null,
  p_shift_code text default null,
  p_admin_notes text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_admin uuid := auth.uid();
  v_admin_clinic uuid;
  v_req record;
  v_patient record;
  v_weekly record;
  v_shift record;
  v_orig_shift record;
  v_existing record;
  v_target date;
  v_day text;
  v_orig_day text;
  v_operating text[];
  v_taken int;
  v_daily_id uuid;
  v_status text;
begin
  if v_admin is null then
    raise exception 'You are not signed in.';
  end if;

  select p.clinic_id into v_admin_clinic
  from profiles p
  where p.id = v_admin and p.role = 'admin';

  if v_admin_clinic is null then
    raise exception 'Only a center admin can review reschedule requests.';
  end if;

  if p_decision not in ('approved', 'declined', 'changed_date') then
    raise exception 'Unknown decision "%".', p_decision;
  end if;

  -- Row-lock the request so two admins can't decide it at the same time.
  select * into v_req
  from reschedule_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    raise exception 'Reschedule request not found.';
  end if;

  if v_req.clinic_id is distinct from v_admin_clinic then
    raise exception 'This request belongs to another center.';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'This request has already been reviewed (%).', v_req.status;
  end if;

  -- -------------------------------------------------------------------
  -- Reject: status only. No session is created, nothing is cancelled,
  -- and the recurring schedule is untouched.
  -- -------------------------------------------------------------------
  if p_decision = 'declined' then
    update reschedule_requests
      set status = 'declined',
          reviewed_at = now(),
          reviewed_by = v_admin,
          admin_notes = p_admin_notes
      where id = p_request_id;

    return jsonb_build_object('status', 'declined');
  end if;

  -- -------------------------------------------------------------------
  -- Accept / Change Date
  -- -------------------------------------------------------------------
  v_target := coalesce(p_target_date, v_req.requested_date);

  if v_target is null then
    raise exception
      'This patient did not pick a date. Use Change Date to set one.';
  end if;

  if v_target < current_date then
    raise exception 'That dialysis date has already passed.';
  end if;

  select * into v_patient
  from patients
  where id = v_req.patient_id and clinic_id = v_admin_clinic
  for update;

  if v_patient.id is null then
    raise exception 'Patient not found for this center.';
  end if;

  if coalesce(v_patient.status, '') not in ('active', 'approved') then
    raise exception 'This patient is not active at the center.';
  end if;

  select * into v_weekly
  from weekly_schedules
  where patient_id = v_req.patient_id
    and clinic_id = v_admin_clinic
    and coalesce(is_active, true)
  order by created_at desc
  limit 1;

  if v_weekly.id is null then
    raise exception
      'This patient has no active weekly schedule to reschedule from.';
  end if;

  -- Clinic operating day -------------------------------------------------
  if extract(isodow from v_target) = 7 then
    raise exception 'The center is closed on Sunday.';
  end if;

  v_day := trim(to_char(v_target, 'Day'));

  select operating_days into v_operating
  from clinic_schedule_settings
  where clinic_id = v_admin_clinic;

  if v_operating is null then
    -- Same default the foundation migration seeds.
    v_operating := array[
      'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'
    ];
  end if;

  if not (v_day = any(v_operating)) then
    raise exception 'The center does not operate on %.', v_day;
  end if;

  -- Shift ----------------------------------------------------------------
  -- An explicit shift wins; otherwise fall back to the patient's own
  -- recurring default for that weekday, then to their usual shift. This
  -- READS patient_schedule_days -- it never writes to it.
  if p_shift_code is not null then
    select * into v_shift
    from clinic_shifts
    where clinic_id = v_admin_clinic and shift_code = p_shift_code;
  else
    select cs.* into v_shift
    from patient_schedule_days psd
    join clinic_shifts cs on cs.id = psd.shift_id
    where psd.weekly_schedule_id = v_weekly.id
      and psd.day_of_week = v_day;

    if v_shift.id is null then
      select cs.* into v_shift
      from patient_schedule_days psd
      join clinic_shifts cs on cs.id = psd.shift_id
      where psd.weekly_schedule_id = v_weekly.id
      order by cs.start_time
      limit 1;
    end if;
  end if;

  if v_shift.id is null then
    raise exception
      'No shift could be resolved for %. Use Change Date and pick a shift.',
      v_day;
  end if;

  if not coalesce(v_shift.is_active, false) then
    raise exception 'The % shift is not active at this center.',
      v_shift.shift_code;
  end if;

  -- Capacity (database backstop -- see the header note) -------------------
  select count(*) into v_taken
  from daily_schedules
  where clinic_id = v_admin_clinic
    and schedule_date = v_target
    and shift = v_shift.shift_code
    and status <> 'cancelled'
    and patient_id <> v_req.patient_id;

  if v_taken >= v_shift.capacity then
    raise exception 'The % shift on % is already full (%/%).',
      v_shift.shift_code,
      to_char(v_target, 'Mon FMDD'),
      v_taken,
      v_shift.capacity;
  end if;

  -- Patient conflict on the target date ----------------------------------
  select * into v_existing
  from daily_schedules
  where patient_id = v_req.patient_id and schedule_date = v_target;

  if v_existing.id is not null and v_existing.status = 'completed' then
    raise exception
      'This patient already completed a dialysis session on %.',
      to_char(v_target, 'Mon FMDD');
  end if;

  if v_existing.id is not null and v_existing.status = 'pending' then
    raise exception
      'This patient already has a dialysis session scheduled on % (% shift).',
      to_char(v_target, 'Mon FMDD'), v_existing.shift;
  end if;

  -- Cancel the original occurrence ---------------------------------------
  -- One date only. patient_schedule_days keeps the recurring day.
  if v_req.original_date is not null and v_req.original_date <> v_target then
    update daily_schedules
      set status = 'cancelled',
          cancelled_at = now(),
          cancelled_by = v_admin,
          cancel_reason =
            'Rescheduled to ' || to_char(v_target, 'YYYY-MM-DD'),
          reschedule_request_id = p_request_id
      where patient_id = v_req.patient_id
        and schedule_date = v_req.original_date
        and status = 'pending';

    if not found then
      -- The original day hasn't been materialized yet (nobody has opened
      -- it in the dashboard). Leave a cancelled tombstone, but only if the
      -- patient actually recurs on that weekday -- otherwise there is
      -- nothing that would ever regenerate them for that date.
      v_orig_day := trim(to_char(v_req.original_date, 'Day'));

      select cs.* into v_orig_shift
      from patient_schedule_days psd
      join clinic_shifts cs on cs.id = psd.shift_id
      where psd.weekly_schedule_id = v_weekly.id
        and psd.day_of_week = v_orig_day;

      if v_orig_shift.id is not null
         and not exists (
           select 1 from daily_schedules
           where patient_id = v_req.patient_id
             and schedule_date = v_req.original_date
         ) then
        insert into daily_schedules (
          weekly_schedule_id, patient_id, clinic_id, schedule_date, shift,
          start_time, end_time, created_by, status,
          cancelled_at, cancelled_by, cancel_reason, reschedule_request_id
        ) values (
          v_weekly.id, v_req.patient_id, v_admin_clinic, v_req.original_date,
          v_orig_shift.shift_code, v_orig_shift.start_time,
          v_orig_shift.end_time, v_admin, 'cancelled',
          now(), v_admin,
          'Rescheduled to ' || to_char(v_target, 'YYYY-MM-DD'),
          p_request_id
        );
      end if;
    end if;
  end if;

  -- Create (or revive) the one-time occurrence on the granted date -------
  if v_existing.id is not null then
    -- A cancelled row for that date already exists: reuse it rather than
    -- inserting a duplicate (daily_schedules_patient_date_unique).
    update daily_schedules
      set status = 'pending',
          shift = v_shift.shift_code,
          start_time = v_shift.start_time,
          end_time = v_shift.end_time,
          weekly_schedule_id = v_weekly.id,
          cancelled_at = null,
          cancelled_by = null,
          cancel_reason = null,
          reschedule_request_id = p_request_id
      where id = v_existing.id;

    v_daily_id := v_existing.id;
  else
    insert into daily_schedules (
      weekly_schedule_id, patient_id, clinic_id, schedule_date, shift,
      start_time, end_time, created_by, status, reschedule_request_id
    ) values (
      v_weekly.id, v_req.patient_id, v_admin_clinic, v_target,
      v_shift.shift_code, v_shift.start_time, v_shift.end_time,
      v_admin, 'pending', p_request_id
    )
    returning id into v_daily_id;
  end if;

  -- Granting a date the patient didn't ask for is recorded as
  -- 'changed_date' so both sides can tell the two outcomes apart.
  v_status := case
    when v_req.requested_date is null or v_target <> v_req.requested_date
      then 'changed_date'
    else 'approved'
  end;

  update reschedule_requests
    set status = v_status,
        resolved_date = v_target,
        resolved_shift = v_shift.shift_code,
        reviewed_at = now(),
        reviewed_by = v_admin,
        admin_notes = p_admin_notes,
        applied_daily_schedule_id = v_daily_id
    where id = p_request_id;

  return jsonb_build_object(
    'status', v_status,
    'daily_schedule_id', v_daily_id,
    'scheduled_date', v_target,
    'shift', v_shift.shift_code
  );
end;
$fn$;

grant execute on function public.review_reschedule_request(
  uuid, text, date, text, text
) to authenticated;
