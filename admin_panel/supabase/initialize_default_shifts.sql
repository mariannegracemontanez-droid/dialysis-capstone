-- Run this manually in the Supabase SQL editor.
-- Run AFTER center_scheduling_foundation.sql.
--
-- Backfills a DEFAULT SHIFT for patients who already have a recurring
-- schedule (weekly_schedules.scheduled_days) but no per-day shift rows in
-- patient_schedule_days, so Today's Dialysis Schedule can place them into
-- AM/PM automatically without an admin editing every patient by hand.
--
-- Rules:
--   * Deterministic. Patients sharing the same set of scheduled days are
--     ranked by created_at (then id) and split down the middle: the
--     earlier half takes the first shift, the later half the second. Six
--     M/W/F patients therefore become 3 AM + 3 PM, and re-running gives
--     the same answer.
--   * Capacity-aware. A shift that has reached its configured capacity
--     for a day is skipped and the other shift is tried instead.
--   * Non-destructive. Nothing is ever deleted or reassigned: days that
--     already have a shift are left exactly as they are, and when both
--     shifts are full the day is REPORTED as a conflict rather than
--     forced in or silently dropped.
--   * Idempotent. Safe to run repeatedly; already-assigned days are
--     reported as 'already_set' and skipped.
--
-- Returns one row per (patient, day) describing what happened, so the
-- capacity conflicts in existing data are visible instead of hidden.

create or replace function public.initialize_patient_default_shifts(
  p_clinic_id uuid default null,
  p_apply boolean default true
)
returns table (
  patient_id uuid,
  patient_name text,
  day_of_week text,
  shift_code text,
  action text,
  note text
)
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_schedule record;
  v_day text;
  v_rank bigint;
  v_group_size bigint;
  v_preferred record;
  v_alternate record;
  v_chosen uuid;
  v_chosen_code text;
  v_shift_count int;
begin
  -- Ordered shift list per clinic is resolved inside the loop so each
  -- clinic uses its own configuration.
  for v_schedule in
    select
      ws.id as weekly_schedule_id,
      ws.patient_id,
      ws.clinic_id,
      ws.scheduled_days,
      coalesce(p.full_name, 'Unknown patient') as full_name,
      -- Rank within the group of patients that share the exact same set
      -- of scheduled days at the same clinic. scheduled_days is jsonb,
      -- so its text form is the group key.
      row_number() over (
        partition by ws.clinic_id, ws.scheduled_days::text
        order by ws.created_at, ws.id
      ) as day_group_rank,
      count(*) over (
        partition by ws.clinic_id, ws.scheduled_days::text
      ) as day_group_size
    from weekly_schedules ws
    left join patients p on p.id = ws.patient_id
    where ws.is_active
      and ws.scheduled_days is not null
      and jsonb_typeof(ws.scheduled_days) = 'array'
      and jsonb_array_length(ws.scheduled_days) > 0
      and (p_clinic_id is null or ws.clinic_id = p_clinic_id)
    order by ws.clinic_id, ws.created_at, ws.id
  loop
    select count(*) into v_shift_count
    from clinic_shifts cs
    where cs.clinic_id = v_schedule.clinic_id and cs.is_active;

    if v_shift_count = 0 then
      patient_id := v_schedule.patient_id;
      patient_name := v_schedule.full_name;
      day_of_week := null;
      shift_code := null;
      action := 'skipped';
      note := 'This center has no active shifts configured.';
      return next;
      continue;
    end if;

    v_rank := v_schedule.day_group_rank;
    v_group_size := v_schedule.day_group_size;

    for v_day in
      select jsonb_array_elements_text(v_schedule.scheduled_days)
    loop
      -- Leave anything already assigned untouched.
      if exists (
        select 1 from patient_schedule_days psd
        where psd.weekly_schedule_id = v_schedule.weekly_schedule_id
          and psd.day_of_week = v_day
      ) then
        patient_id := v_schedule.patient_id;
        patient_name := v_schedule.full_name;
        day_of_week := v_day;
        shift_code := null;
        action := 'already_set';
        note := 'Existing default shift left unchanged.';
        return next;
        continue;
      end if;

      -- First half of the group prefers the earliest shift, second half
      -- the next one -- an even split rather than filling one shift up.
      select cs.id, cs.shift_code, cs.capacity,
             (select count(*) from patient_schedule_days x
               join weekly_schedules xs on xs.id = x.weekly_schedule_id
              where x.clinic_id = v_schedule.clinic_id
                and x.day_of_week = v_day
                and x.shift_id = cs.id
                and xs.is_active) as assigned
        into v_preferred
      from clinic_shifts cs
      where cs.clinic_id = v_schedule.clinic_id and cs.is_active
      order by cs.start_time, cs.shift_code
      offset case
               when v_rank <= ceil(v_group_size::numeric / 2) then 0
               else least(1, v_shift_count - 1)
             end
      limit 1;

      -- The other shift, used when the preferred one is already full.
      select cs.id, cs.shift_code, cs.capacity,
             (select count(*) from patient_schedule_days x
               join weekly_schedules xs on xs.id = x.weekly_schedule_id
              where x.clinic_id = v_schedule.clinic_id
                and x.day_of_week = v_day
                and x.shift_id = cs.id
                and xs.is_active) as assigned
        into v_alternate
      from clinic_shifts cs
      where cs.clinic_id = v_schedule.clinic_id
        and cs.is_active
        and cs.id <> v_preferred.id
      order by cs.start_time, cs.shift_code
      limit 1;

      v_chosen := null;
      v_chosen_code := null;

      if v_preferred.id is not null and v_preferred.assigned < v_preferred.capacity then
        v_chosen := v_preferred.id;
        v_chosen_code := v_preferred.shift_code;
      elsif v_alternate.id is not null and v_alternate.assigned < v_alternate.capacity then
        v_chosen := v_alternate.id;
        v_chosen_code := v_alternate.shift_code;
      end if;

      if v_chosen is null then
        -- Both shifts are already at capacity for this day. The existing
        -- schedule stays exactly as it is; the conflict is reported so
        -- staff can review capacity rather than losing a patient.
        patient_id := v_schedule.patient_id;
        patient_name := v_schedule.full_name;
        day_of_week := v_day;
        shift_code := null;
        action := 'capacity_conflict';
        note := 'All shifts are at configured capacity for this day. '
             || 'No default shift assigned; existing schedule left intact.';
        return next;
        continue;
      end if;

      if p_apply then
        insert into patient_schedule_days
          (weekly_schedule_id, clinic_id, day_of_week, shift_id)
        values
          (v_schedule.weekly_schedule_id, v_schedule.clinic_id, v_day, v_chosen)
        on conflict (weekly_schedule_id, day_of_week) do nothing;
      end if;

      patient_id := v_schedule.patient_id;
      patient_name := v_schedule.full_name;
      day_of_week := v_day;
      shift_code := v_chosen_code;
      action := case when p_apply then 'assigned' else 'would_assign' end;
      note := null;
      return next;
    end loop;
  end loop;
end;
$$;

grant execute on function public.initialize_patient_default_shifts(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- HOW TO USE
-- ---------------------------------------------------------------------
-- 1. Dry run first -- shows what would happen, changes nothing:
--      select * from initialize_patient_default_shifts(null, false);
--
-- 2. Apply for every clinic:
--      select * from initialize_patient_default_shifts();
--
-- 3. Review any capacity conflicts that were reported:
--      select * from initialize_patient_default_shifts(null, false)
--      where action = 'capacity_conflict';
