--
-- PostgreSQL database dump
--


-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: donations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.donations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    donor_id uuid,
    name text,
    email text,
    amount numeric NOT NULL,
    payment_method text,
    proof_url text,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    clinic_id uuid,
    allocation_type text,
    CONSTRAINT donations_allocation_type_check CHECK (((allocation_type IS NULL) OR (allocation_type = ANY (ARRAY['specific_center'::text, 'random_center'::text, 'equal_distribution'::text])))),
    CONSTRAINT status_check CHECK ((status = ANY (ARRAY['pending'::text, 'verified'::text, 'rejected'::text])))
);


--
-- Name: approve_donation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.approve_donation(p_donation_id uuid) RETURNS public.donations
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_donation public.donations;
  v_allocation record;
  v_clinic_name text;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'superadmin'
  ) then
    raise exception 'Only a superadmin can approve donations.';
  end if;

  select * into v_donation
  from public.donations
  where id = p_donation_id
  for update;

  if not found then
    raise exception 'Donation % was not found.', p_donation_id;
  end if;

  if v_donation.status <> 'pending' then
    raise exception 'Donation % has already been processed (status: %).',
      p_donation_id, v_donation.status;
  end if;

  update public.donations
  set status = 'verified'
  where id = p_donation_id;

  insert into public.donation_audit_logs (
    donation_id, action, amount, from_entity, to_entity, performed_by, metadata
  ) values (
    p_donation_id,
    'DONATION_APPROVED',
    v_donation.amount,
    'superadmin',
    'donation_system',
    auth.uid(),
    jsonb_build_object('allocation_type', v_donation.allocation_type)
  );

  if v_donation.clinic_id is not null then
    -- Specific / random center: single recipient, already resolved.
    select name into v_clinic_name from public.clinics where id = v_donation.clinic_id;

    insert into public.donation_audit_logs (
      donation_id, clinic_id, action, amount, from_entity, to_entity, performed_by, metadata
    ) values (
      p_donation_id,
      v_donation.clinic_id,
      'DONATION_SENT_TO_CENTER',
      v_donation.amount,
      'superadmin',
      coalesce(v_clinic_name, v_donation.clinic_id::text),
      auth.uid(),
      jsonb_build_object('allocation_type', v_donation.allocation_type)
    );
  else
    -- Equal distribution: one recipient per existing allocation row.
    -- These rows were already computed and persisted at submission time
    -- (see the migration header note above) -- not recalculated here.
    for v_allocation in
      select da.id, da.clinic_id, da.amount, c.name as clinic_name
      from public.donation_allocations da
      join public.clinics c on c.id = da.clinic_id
      where da.donation_id = p_donation_id
    loop
      insert into public.donation_audit_logs (
        donation_id, allocation_id, clinic_id, action, amount,
        from_entity, to_entity, performed_by, metadata
      ) values (
        p_donation_id,
        v_allocation.id,
        v_allocation.clinic_id,
        'DONATION_SENT_TO_CENTER',
        v_allocation.amount,
        'superadmin',
        coalesce(v_allocation.clinic_name, v_allocation.clinic_id::text),
        auth.uid(),
        jsonb_build_object('allocation_type', 'equal_distribution')
      );
    end loop;
  end if;

  select * into v_donation from public.donations where id = p_donation_id;
  return v_donation;
end;
$$;


--
-- Name: handle_patient_acceptance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_patient_acceptance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if NEW.status = 'no_sched' then
    update patients
    set status = 'declined'
    where profile_id = NEW.profile_id
      and id <> NEW.id
      and status = 'pending';
  end if;
  return NEW;
end;
$$;


--
-- Name: initialize_patient_default_shifts(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.initialize_patient_default_shifts(p_clinic_id uuid DEFAULT NULL::uuid, p_apply boolean DEFAULT true) RETURNS TABLE(patient_id uuid, patient_name text, day_of_week text, shift_code text, action text, note text)
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
      -- of scheduled days at the same clinic.
      row_number() over (
        partition by ws.clinic_id, array_to_string(ws.scheduled_days, ',')
        order by ws.created_at, ws.id
      ) as day_group_rank,
      count(*) over (
        partition by ws.clinic_id, array_to_string(ws.scheduled_days, ',')
      ) as day_group_size
    from weekly_schedules ws
    left join patients p on p.id = ws.patient_id
    where ws.is_active
      and ws.scheduled_days is not null
      and array_length(ws.scheduled_days, 1) is not null
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

    foreach v_day in array v_schedule.scheduled_days
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


--
-- Name: jwt_custom_claims(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jwt_custom_claims() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select jsonb_build_object(
    'role', (select role from public.profiles where id = auth.uid())
  );
$$;


--
-- Name: log_donation_allocated(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_donation_allocated() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.donation_audit_logs (
    donation_id, allocation_id, clinic_id, action, amount, from_entity, to_entity, metadata
  ) values (
    new.donation_id,
    new.id,
    new.clinic_id,
    'DONATION_ALLOCATED',
    new.amount,
    'donation_system',
    new.clinic_id::text,
    jsonb_build_object('allocation_type', 'equal_distribution')
  );

  return new;
end;
$$;


--
-- Name: log_donation_received(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_donation_received() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.donation_audit_logs (
    donation_id, clinic_id, action, amount, from_entity, to_entity, metadata
  ) values (
    new.id,
    new.clinic_id,
    'DONATION_RECEIVED',
    new.amount,
    'donor',
    'donation_system',
    jsonb_build_object('allocation_type', new.allocation_type)
  );

  -- Specific/random already resolve to exactly one center at submission
  -- time (equal distribution's per-center rows are logged separately by
  -- log_donation_allocated below, since they land in donation_allocations
  -- instead of donations.clinic_id).
  if new.clinic_id is not null then
    insert into public.donation_audit_logs (
      donation_id, clinic_id, action, amount, from_entity, to_entity, metadata
    ) values (
      new.id,
      new.clinic_id,
      'DONATION_ALLOCATED',
      new.amount,
      'donation_system',
      new.clinic_id::text,
      jsonb_build_object('allocation_type', new.allocation_type)
    );
  end if;

  return new;
end;
$$;


--
-- Name: log_patient_medical_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_patient_medical_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_actor uuid := auth.uid();
begin
  if new.blood_type is distinct from old.blood_type then
    insert into patient_medical_updates
      (patient_id, clinic_id, field, old_value, new_value, updated_by)
    values
      (new.id, new.clinic_id, 'Blood Type', old.blood_type, new.blood_type, v_actor);
  end if;

  if new.dialysis_stage is distinct from old.dialysis_stage then
    insert into patient_medical_updates
      (patient_id, clinic_id, field, old_value, new_value, updated_by)
    values
      (new.id, new.clinic_id, 'Dialysis Stage', old.dialysis_stage, new.dialysis_stage, v_actor);
  end if;

  if new.existing_condition is distinct from old.existing_condition then
    insert into patient_medical_updates
      (patient_id, clinic_id, field, old_value, new_value, updated_by)
    values
      (new.id, new.clinic_id, 'Existing Condition', old.existing_condition, new.existing_condition, v_actor);
  end if;

  if new.sessions_per_week is distinct from old.sessions_per_week then
    insert into patient_medical_updates
      (patient_id, clinic_id, field, old_value, new_value, updated_by)
    values
      (new.id, new.clinic_id, 'Required Sessions / Week',
       old.sessions_per_week::text, new.sessions_per_week::text, v_actor);
  end if;

  return new;
end;
$$;


--
-- Name: monthly_patient_growth(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.monthly_patient_growth() RETURNS TABLE(month text, count integer)
    LANGUAGE sql
    AS $$
  select to_char(created_at, 'Mon YYYY') as month,
         count(*) as count
  from patients
  where created_at >= date_trunc('month', now()) - interval '4 months'
  group by month
  order by min(created_at);
$$;


--
-- Name: notifications_client_update_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notifications_client_update_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if auth.role() = 'authenticated' and (
       new.recipient_id is distinct from old.recipient_id
    or new.sender_id    is distinct from old.sender_id
    or new.title        is distinct from old.title
    or new.message      is distinct from old.message
    or new.type         is distinct from old.type
    or new.created_at   is distinct from old.created_at
  ) then
    raise exception 'Only is_read can be changed on a notification.';
  end if;
  return new;
end;
$$;


--
-- Name: notify_daily_schedule_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_daily_schedule_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_profile uuid := (select profile_id from patients where id = new.patient_id);
begin
  if new.status = 'cancelled' and new.reschedule_request_id is null then
    perform notify_profile(
      v_profile, 'session_cancelled', 'Session Cancelled',
      'Your dialysis session has been cancelled. Open the app for details.',
      'daily_schedule', new.id, 'session_cancelled:' || new.id
    );
  elsif new.status = 'completed' then
    perform notify_profile(
      v_profile, 'session_completed', 'Session Completed',
      'Your dialysis session has been marked as completed.',
      'daily_schedule', new.id, 'session_completed:' || new.id
    );
  end if;
  return new;
end;
$$;


--
-- Name: notify_new_announcement(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_new_announcement() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_type text := case when new.color = 'red' then 'center_closure'
                      else 'announcement_new' end;
  v_patient record;
begin
  for v_patient in
    select distinct pt.profile_id
    from patients pt
    where pt.clinic_id = new.clinic_id
      and pt.status in ('no_sched', 'active', 'approved')
      and pt.profile_id is not null
  loop
    perform notify_profile(
      v_patient.profile_id, v_type, 'New Announcement',
      'Your dialysis center has posted a new announcement.',
      'announcement', new.id, 'announcement:' || new.id
    );
  end loop;
  return new;
end;
$$;


--
-- Name: notify_patient_status_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_patient_status_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if old.status = 'pending' and new.status = 'no_sched' then
    perform notify_profile(
      new.profile_id, 'application_accepted', 'Application Accepted',
      'Your application has been accepted. Your dialysis schedule will be assigned soon.',
      'patient', new.id, 'application_accepted:' || new.id
    );
  elsif old.status = 'pending' and new.status = 'declined' then
    perform notify_profile(
      new.profile_id, 'application_declined', 'Application Declined',
      'Your application was declined. Open your application details to review the reason.',
      'patient', new.id, 'application_declined:' || new.id
    );
  end if;
  return new;
end;
$$;


--
-- Name: notify_profile(uuid, text, text, text, text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_profile(p_recipient uuid, p_type text, p_title text, p_message text, p_related_type text, p_related_id uuid, p_dedupe_key text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if p_recipient is null then
    return;
  end if;

  insert into notifications (
    recipient_id, sender_id, title, message, type,
    related_type, related_id, dedupe_key
  ) values (
    p_recipient, auth.uid(), p_title, p_message, p_type,
    p_related_type, p_related_id, p_dedupe_key
  )
  on conflict (recipient_id, dedupe_key) where dedupe_key is not null
  do nothing;
end;
$$;


--
-- Name: notify_reschedule_decision(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_reschedule_decision() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_profile uuid := (select profile_id from patients where id = new.patient_id);
begin
  if old.status <> 'pending' then
    return new;
  end if;

  if new.status = 'approved' then
    perform notify_profile(
      v_profile, 'reschedule_approved', 'Reschedule Approved',
      'Your reschedule request has been approved. Check your updated schedule.',
      'reschedule_request', new.id, 'reschedule_decision:' || new.id
    );
  elsif new.status = 'changed_date' then
    perform notify_profile(
      v_profile, 'reschedule_changed_date', 'Reschedule Approved',
      'Your reschedule request was approved for a different date. Check your updated schedule.',
      'reschedule_request', new.id, 'reschedule_decision:' || new.id
    );
  elsif new.status = 'declined' then
    perform notify_profile(
      v_profile, 'reschedule_declined', 'Reschedule Declined',
      'Your reschedule request was declined. Open the app for details.',
      'reschedule_request', new.id, 'reschedule_decision:' || new.id
    );
  end if;
  return new;
end;
$$;


--
-- Name: notify_schedule_assigned(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_schedule_assigned() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  perform notify_profile(
    (select profile_id from patients where id = new.patient_id),
    'schedule_assigned', 'Dialysis Schedule Ready',
    'Your dialysis schedule is ready. Open the app to view your assigned days and shifts.',
    'weekly_schedule', new.id, 'schedule_assigned:' || new.id
  );
  return new;
end;
$$;


--
-- Name: patient_announcements_set_owner(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.patient_announcements_set_owner() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: patient_announcements_touch_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.patient_announcements_touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: queue_session_reminders(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_session_reminders(p_days_ahead integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_date date := (now() at time zone 'Asia/Manila')::date + p_days_ahead;
  v_day text := trim(to_char(v_date, 'FMDay'));
  v_type text := case when p_days_ahead = 0 then 'schedule_today'
                      else 'schedule_tomorrow' end;
  v_title text := case when p_days_ahead = 0 then 'Dialysis Today'
                       else 'Dialysis Tomorrow' end;
  v_message text := case when p_days_ahead = 0
    then 'You have a dialysis session scheduled for today. Open the app for details.'
    else 'You have a dialysis session scheduled for tomorrow. Open the app for details.' end;
  v_row record;
begin
  for v_row in
    select pt.profile_id, pt.id as patient_id
    from patients pt
    join weekly_schedules ws on ws.patient_id = pt.id
                            and coalesce(ws.is_active, true)
    join patient_schedule_days psd on psd.weekly_schedule_id = ws.id
                                  and psd.day_of_week = v_day
    where pt.status = 'active'
      and ws.created_at::date <= v_date
      and not exists (
        select 1 from daily_schedules ds
        where ds.patient_id = pt.id
          and ds.schedule_date = v_date
          and ds.status <> 'pending'
      )
    union
    select pt.profile_id, pt.id
    from daily_schedules ds
    join patients pt on pt.id = ds.patient_id
    where ds.schedule_date = v_date
      and ds.status = 'pending'
      and pt.status = 'active'
  loop
    perform notify_profile(
      v_row.profile_id, v_type, v_title, v_message,
      'session_date', null,
      v_type || ':' || v_row.patient_id || ':' || v_date
    );
  end loop;
end;
$$;


--
-- Name: register_device_token(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_device_token(p_token text, p_platform text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;

  insert into device_tokens (token, user_id, platform)
  values (p_token, auth.uid(), p_platform)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;


--
-- Name: reject_donation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_donation(p_donation_id uuid) RETURNS public.donations
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_donation public.donations;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'superadmin'
  ) then
    raise exception 'Only a superadmin can reject donations.';
  end if;

  select * into v_donation
  from public.donations
  where id = p_donation_id
  for update;

  if not found then
    raise exception 'Donation % was not found.', p_donation_id;
  end if;

  if v_donation.status <> 'pending' then
    raise exception 'Donation % has already been processed (status: %).',
      p_donation_id, v_donation.status;
  end if;

  update public.donations
  set status = 'rejected'
  where id = p_donation_id;

  insert into public.donation_audit_logs (
    donation_id, action, amount, from_entity, to_entity, performed_by, metadata
  ) values (
    p_donation_id,
    'DONATION_REJECTED',
    v_donation.amount,
    'superadmin',
    'donor',
    auth.uid(),
    jsonb_build_object('allocation_type', v_donation.allocation_type)
  );

  select * into v_donation from public.donations where id = p_donation_id;
  return v_donation;
end;
$$;


--
-- Name: reschedule_requests_set_clinic(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reschedule_requests_set_clinic() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  select p.clinic_id into new.clinic_id
  from patients p
  where p.id = new.patient_id;

  return new;
end;
$$;


--
-- Name: review_reschedule_request(uuid, text, date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.review_reschedule_request(p_request_id uuid, p_decision text, p_target_date date DEFAULT NULL::date, p_shift_code text DEFAULT NULL::text, p_admin_notes text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: set_patient_recurring_schedule(uuid, uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_patient_recurring_schedule(p_patient_id uuid, p_clinic_id uuid, p_created_by uuid, p_day_shifts jsonb) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
  -- the duplicate check below. The status is read under the same lock so
  -- the acceptance check below is race-free too.
  select status into v_status
    from patients
    where id = p_patient_id and clinic_id = p_clinic_id
    for update;

  if not found then
    raise exception 'Patient not found for this clinic.';
  end if;

  -- Only an ACCEPTED patient may be given a recurring schedule.
  -- 'no_sched' is the accepted-but-unscheduled state. Without this, a
  -- patient still at 'pending' could be taken straight to 'active',
  -- skipping the accepted/reserved step the Super Admin capacity estimate
  -- counts. See supabase/patient_acceptance_status_guard.sql.
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
  -- "this patient has a recurring schedule that was actually saved" -- and
  -- if any insert above fails, this rolls back with it and the patient
  -- stays 'no_sched'. clinic_id is deliberately left untouched.
  update patients
    set status = 'active'
    where id = p_patient_id and clinic_id = p_clinic_id;
end;
$$;


--
-- Name: sync_profile_to_patient(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_profile_to_patient() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.role = 'patient' THEN
    -- Check muna kung wala pang patient record para sa profile
    IF NOT EXISTS (
      SELECT 1 FROM patients WHERE profile_id = NEW.id
    ) THEN
      INSERT INTO patients (
        profile_id,
        clinic_id,
        full_name,
        email,
        phone,
        status
      )
      VALUES (
        NEW.id,
        NEW.clinic_id,
        NEW.full_name,
        NEW.email,
        NEW.phone,
        'pending'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: update_center_profile(uuid, integer, text[], text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_center_profile(p_clinic_id uuid, p_machine integer, p_requirements text[], p_operating_hours text, p_house_rules text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: appointment_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointment_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    appointment_id uuid DEFAULT gen_random_uuid(),
    patient_id uuid DEFAULT gen_random_uuid(),
    action text,
    previous_status text,
    new_status text,
    changed_by uuid DEFAULT gen_random_uuid(),
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid DEFAULT auth.uid(),
    appointment_date date,
    time_slot text,
    status text DEFAULT 'pending, approved, rejected, rescheduled,'::text,
    approved_by uuid DEFAULT gen_random_uuid(),
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    slot_id uuid,
    CONSTRAINT appointments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'rescheduled'::text])))
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    action text,
    actor_id uuid,
    actor_name text,
    target_id uuid,
    target_name text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: blood_pressure_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blood_pressure_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    clinic_id uuid NOT NULL,
    session_date date DEFAULT CURRENT_DATE NOT NULL,
    systolic integer NOT NULL,
    diastolic integer NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: clinic_schedule_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clinic_schedule_settings (
    clinic_id uuid NOT NULL,
    operating_days text[] DEFAULT ARRAY['Monday'::text, 'Tuesday'::text, 'Wednesday'::text, 'Thursday'::text, 'Friday'::text, 'Saturday'::text] NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: clinic_shifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clinic_shifts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    clinic_id uuid NOT NULL,
    shift_code text NOT NULL,
    shift_label text DEFAULT ''::text NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    capacity integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT clinic_shifts_capacity_check CHECK ((capacity >= 0)),
    CONSTRAINT clinic_shifts_shift_code_check CHECK ((shift_code = ANY (ARRAY['AM'::text, 'PM'::text])))
);


--
-- Name: clinics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clinics (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    address text,
    city text,
    latitude double precision,
    longitude double precision,
    slots_available integer,
    operating_hours text,
    requirements text[],
    created_at timestamp with time zone DEFAULT now(),
    contact_number text,
    machine integer DEFAULT 10,
    shifts integer DEFAULT 2,
    status text,
    shift_schedule text[],
    reserved_machines integer DEFAULT 0 NOT NULL,
    target_patients_per_shift integer,
    target_daily_capacity integer,
    house_rules text,
    CONSTRAINT clinics_machine_check CHECK (((machine >= 0) AND (machine <= 100))),
    CONSTRAINT clinics_reserved_machines_check CHECK ((reserved_machines >= 0)),
    CONSTRAINT clinics_status_check CHECK ((status = ANY (ARRAY['open'::text, 'full'::text, 'busy'::text, 'closed'::text, 'maintenance'::text]))),
    CONSTRAINT clinics_target_daily_capacity_check CHECK (((target_daily_capacity IS NULL) OR (target_daily_capacity >= 0))),
    CONSTRAINT clinics_target_patients_per_shift_check CHECK (((target_patients_per_shift IS NULL) OR (target_patients_per_shift >= 0)))
);


--
-- Name: daily_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    weekly_schedule_id uuid NOT NULL,
    patient_id uuid NOT NULL,
    clinic_id uuid NOT NULL,
    schedule_date date NOT NULL,
    shift text NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    completed_at timestamp with time zone,
    before_weight numeric,
    before_systolic integer,
    before_diastolic integer,
    after_weight numeric,
    duration_hours integer,
    duration_minutes integer,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    cancel_reason text,
    reschedule_request_id uuid,
    CONSTRAINT daily_schedules_duration_hours_check CHECK (((duration_hours IS NULL) OR ((duration_hours >= 0) AND (duration_hours <= 8)))),
    CONSTRAINT daily_schedules_duration_minutes_check CHECK (((duration_minutes IS NULL) OR ((duration_minutes >= 0) AND (duration_minutes <= 59)))),
    CONSTRAINT daily_schedules_shift_check CHECK ((shift = ANY (ARRAY['AM'::text, 'PM'::text]))),
    CONSTRAINT daily_schedules_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'cancelled'::text]))),
    CONSTRAINT daily_schedules_time_check CHECK ((start_time < end_time))
);


--
-- Name: device_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    fcm_token text NOT NULL,
    platform text DEFAULT 'android'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: dialysis_slots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dialysis_slots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slot_date date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    max_patients bigint NOT NULL,
    created_by uuid NOT NULL
);


--
-- Name: distributions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.distributions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    donation_id uuid,
    clinic_id uuid,
    amount numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: donation_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.donation_allocations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    donation_id uuid NOT NULL,
    clinic_id uuid NOT NULL,
    amount numeric(12,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: donation_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.donation_audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    donation_id uuid NOT NULL,
    allocation_id uuid,
    clinic_id uuid,
    action text NOT NULL,
    amount numeric(12,2),
    from_entity text,
    to_entity text,
    performed_by uuid,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: donation_purchase_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.donation_purchase_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    clinic_name text NOT NULL,
    item_name text NOT NULL,
    amount numeric DEFAULT 0 NOT NULL,
    purchase_date date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: donors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.donors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    email text,
    phone text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: fund_distributions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fund_distributions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    distributed_by uuid,
    distribution_date timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    center_name text,
    amount numeric,
    remarks text,
    status text DEFAULT 'Distributed'::text,
    clinic_id uuid
);


--
-- Name: fund_pool; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fund_pool (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    total_amount numeric,
    last_updated timestamp with time zone NOT NULL
);


--
-- Name: login_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    login_time timestamp with time zone DEFAULT now() NOT NULL,
    ip_address text,
    device_info text
);


--
-- Name: medical_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medical_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    referral_letter_url text,
    medical_abstract_url text,
    hd_treatment_sheets_url text,
    lab_results_url text,
    hepatitis_profile_url text,
    xray_url text,
    government_id_url text,
    philhealth_mdr_url text,
    pdd_certificate_url text,
    phic_consumption_url text,
    phic_contribution_url text,
    status text DEFAULT 'pending'::text NOT NULL,
    reviewed_by uuid,
    remarks text,
    uploaded_at timestamp with time zone DEFAULT now(),
    clinic_id uuid NOT NULL,
    CONSTRAINT medical_documents_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recipient_id uuid NOT NULL,
    sender_id uuid,
    title text NOT NULL,
    message text NOT NULL,
    type text DEFAULT 'general'::text NOT NULL,
    is_read boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    related_type text,
    related_id uuid,
    data jsonb,
    dedupe_key text
);


--
-- Name: patient_announcements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patient_announcements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    clinic_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    announcement_date date,
    color text DEFAULT 'blue'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT patient_announcements_body_not_blank CHECK ((length(btrim(body)) > 0)),
    CONSTRAINT patient_announcements_color_check CHECK ((color = ANY (ARRAY['blue'::text, 'light_blue'::text, 'green'::text, 'orange'::text, 'purple'::text, 'red'::text]))),
    CONSTRAINT patient_announcements_title_not_blank CHECK ((length(btrim(title)) > 0))
);


--
-- Name: patient_fund_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patient_fund_receipts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    distribution_id uuid DEFAULT gen_random_uuid(),
    patient_id uuid DEFAULT gen_random_uuid(),
    amount_received numeric,
    status text DEFAULT 'received, pending'::text,
    CONSTRAINT patient_fund_receipts_status_check CHECK ((status = ANY (ARRAY['received'::text, 'pending'::text])))
);


--
-- Name: patient_medical_updates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patient_medical_updates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    clinic_id uuid,
    field text NOT NULL,
    old_value text,
    new_value text,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: patient_requirements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patient_requirements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid,
    requirement_name text,
    requirement_type text,
    status text DEFAULT 'pending'::text,
    submitted_at timestamp with time zone
);


--
-- Name: patient_schedule_days; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patient_schedule_days (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    weekly_schedule_id uuid NOT NULL,
    clinic_id uuid NOT NULL,
    day_of_week text NOT NULL,
    shift_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT patient_schedule_days_day_of_week_check CHECK ((day_of_week = ANY (ARRAY['Monday'::text, 'Tuesday'::text, 'Wednesday'::text, 'Thursday'::text, 'Friday'::text, 'Saturday'::text])))
);


--
-- Name: patients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    profile_id uuid,
    clinic_id uuid,
    full_name text,
    date_of_birth date,
    home_address text,
    blood_type text,
    emergency_contact_name text,
    emergency_contact_number text,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    dialysis_stage text,
    existing_condition text,
    email text,
    budget text,
    insurance text,
    user_location text,
    phone text,
    financial_support text,
    preferred_clinic text,
    profile_image_url text,
    weight numeric,
    height numeric,
    last_dialysis_date date,
    decline_reason text,
    delete_reason text,
    deleted_at timestamp without time zone,
    declined_at timestamp with time zone,
    sessions_per_week integer,
    preferred_shift text,
    first_name text,
    middle_name text,
    last_name text,
    CONSTRAINT patients_dialysis_stage_check CHECK ((dialysis_stage = ANY (ARRAY['Stage 1'::text, 'Stage 2'::text, 'Stage 3'::text, 'Stage 4'::text, 'Stage 5'::text]))),
    CONSTRAINT patients_existing_condition_check CHECK ((existing_condition = ANY (ARRAY['Diabetes'::text, 'Hypertension'::text, 'Heart Disease'::text, 'None'::text]))),
    CONSTRAINT patients_name_parts_check CHECK (((((first_name IS NULL) AND (last_name IS NULL)) OR ((first_name IS NOT NULL) AND (last_name IS NOT NULL) AND (btrim(first_name) <> ''::text) AND (btrim(last_name) <> ''::text))) AND ((middle_name IS NULL) OR (btrim(middle_name) <> ''::text)))),
    CONSTRAINT patients_preferred_shift_check CHECK (((preferred_shift IS NULL) OR (preferred_shift = ANY (ARRAY['AM'::text, 'PM'::text])))),
    CONSTRAINT patients_sessions_per_week_check CHECK (((sessions_per_week IS NULL) OR ((sessions_per_week >= 1) AND (sessions_per_week <= 6)))),
    CONSTRAINT patients_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'declined'::text, 'no_sched'::text, 'deleted'::text])))
);


--
-- Name: COLUMN patients.first_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.patients.first_name IS 'Patient first name as submitted to this clinic. NULL on legacy rows (see full_name).';


--
-- Name: COLUMN patients.middle_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.patients.middle_name IS 'Patient middle name; NULL when the patient has no middle name or on legacy rows.';


--
-- Name: COLUMN patients.last_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.patients.last_name IS 'Patient last name as submitted to this clinic. NULL on legacy rows (see full_name).';


--
-- Name: patients_backup_before_multi_inquiry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patients_backup_before_multi_inquiry (
    id uuid,
    profile_id uuid,
    clinic_id uuid,
    full_name text,
    date_of_birth date,
    home_address text,
    blood_type text,
    emergency_contact_name text,
    emergency_contact_number text,
    status text,
    created_at timestamp with time zone,
    dialysis_stage text,
    existing_condition text,
    email text,
    budget text,
    insurance text,
    user_location text,
    phone text,
    financial_support text,
    preferred_clinic text
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name text,
    email text,
    role text,
    phone text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_location text,
    clinic_id uuid,
    is_active boolean DEFAULT true,
    status text DEFAULT 'pending'::text,
    first_name text,
    middle_name text,
    last_name text,
    CONSTRAINT profiles_name_parts_check CHECK (((((first_name IS NULL) AND (last_name IS NULL)) OR ((first_name IS NOT NULL) AND (last_name IS NOT NULL) AND (btrim(first_name) <> ''::text) AND (btrim(last_name) <> ''::text))) AND ((middle_name IS NULL) OR (btrim(middle_name) <> ''::text)))),
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['patient'::text, 'admin'::text, 'superadmin'::text, 'donor'::text]))),
    CONSTRAINT profiles_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'pending'::text])))
);


--
-- Name: TABLE profiles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.profiles IS 'stores system users (patients, admins, super admin)';


--
-- Name: COLUMN profiles.first_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.first_name IS 'Account first name. NULL on legacy profiles (see full_name).';


--
-- Name: COLUMN profiles.middle_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.middle_name IS 'Account middle name; NULL when there is none or on legacy profiles.';


--
-- Name: COLUMN profiles.last_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.last_name IS 'Account last name. NULL on legacy profiles (see full_name).';


--
-- Name: reschedule_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reschedule_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    original_date date,
    requested_date date,
    reason text,
    notes text,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    clinic_id uuid,
    reviewed_at timestamp with time zone,
    reviewed_by uuid,
    admin_notes text,
    resolved_date date,
    resolved_shift text,
    applied_daily_schedule_id uuid,
    CONSTRAINT reschedule_requests_resolved_shift_check CHECK (((resolved_shift IS NULL) OR (resolved_shift = ANY (ARRAY['AM'::text, 'PM'::text])))),
    CONSTRAINT reschedule_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text, 'changed_date'::text, 'cancelled'::text])))
);


--
-- Name: urgency_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.urgency_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid DEFAULT gen_random_uuid(),
    document_id uuid DEFAULT gen_random_uuid(),
    urgency_level text DEFAULT 'urgent, non_urgent'::text,
    reviewed_by uuid DEFAULT gen_random_uuid(),
    review_date timestamp without time zone
);


--
-- Name: water_intake_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.water_intake_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    amount_ml integer NOT NULL,
    log_date date DEFAULT CURRENT_DATE NOT NULL,
    logged_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    CONSTRAINT water_intake_logs_amount_check CHECK ((amount_ml > 0))
);


--
-- Name: weekly_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weekly_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    clinic_id uuid NOT NULL,
    slot_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    scheduled_days jsonb DEFAULT '[]'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: weight_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weight_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    clinic_id uuid NOT NULL,
    session_date date DEFAULT CURRENT_DATE NOT NULL,
    before_weight numeric NOT NULL,
    after_weight numeric,
    notes text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: appointments appointment scheduling_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT "appointment scheduling_pkey" PRIMARY KEY (id);


--
-- Name: appointment_history appointment_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_history
    ADD CONSTRAINT appointment_history_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: blood_pressure_logs blood_pressure_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blood_pressure_logs
    ADD CONSTRAINT blood_pressure_logs_pkey PRIMARY KEY (id);


--
-- Name: clinic_schedule_settings clinic_schedule_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinic_schedule_settings
    ADD CONSTRAINT clinic_schedule_settings_pkey PRIMARY KEY (clinic_id);


--
-- Name: clinic_shifts clinic_shifts_clinic_id_shift_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinic_shifts
    ADD CONSTRAINT clinic_shifts_clinic_id_shift_code_key UNIQUE (clinic_id, shift_code);


--
-- Name: clinic_shifts clinic_shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinic_shifts
    ADD CONSTRAINT clinic_shifts_pkey PRIMARY KEY (id);


--
-- Name: clinics clinics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinics
    ADD CONSTRAINT clinics_pkey PRIMARY KEY (id);


--
-- Name: daily_schedules daily_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_schedules
    ADD CONSTRAINT daily_schedules_pkey PRIMARY KEY (id);


--
-- Name: device_tokens device_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (id);


--
-- Name: device_tokens device_tokens_user_id_fcm_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_user_id_fcm_token_key UNIQUE (user_id, fcm_token);


--
-- Name: dialysis_slots dialysis_slots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dialysis_slots
    ADD CONSTRAINT dialysis_slots_pkey PRIMARY KEY (id);


--
-- Name: distributions distributions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distributions
    ADD CONSTRAINT distributions_pkey PRIMARY KEY (id);


--
-- Name: donation_allocations donation_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_allocations
    ADD CONSTRAINT donation_allocations_pkey PRIMARY KEY (id);


--
-- Name: donation_audit_logs donation_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_audit_logs
    ADD CONSTRAINT donation_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: donation_purchase_logs donation_purchase_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_purchase_logs
    ADD CONSTRAINT donation_purchase_logs_pkey PRIMARY KEY (id);


--
-- Name: donors donation_system_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donors
    ADD CONSTRAINT donation_system_pkey PRIMARY KEY (id);


--
-- Name: donations donations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_pkey PRIMARY KEY (id);


--
-- Name: fund_distributions fund_distributions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fund_distributions
    ADD CONSTRAINT fund_distributions_pkey PRIMARY KEY (id);


--
-- Name: fund_pool fund_pool_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fund_pool
    ADD CONSTRAINT fund_pool_pkey PRIMARY KEY (id);


--
-- Name: login_history login_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_history
    ADD CONSTRAINT login_history_pkey PRIMARY KEY (id);


--
-- Name: medical_documents medical_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: patient_announcements patient_announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_announcements
    ADD CONSTRAINT patient_announcements_pkey PRIMARY KEY (id);


--
-- Name: patient_fund_receipts patient_fund_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_fund_receipts
    ADD CONSTRAINT patient_fund_receipts_pkey PRIMARY KEY (id);


--
-- Name: patient_medical_updates patient_medical_updates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_medical_updates
    ADD CONSTRAINT patient_medical_updates_pkey PRIMARY KEY (id);


--
-- Name: patient_requirements patient_requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_requirements
    ADD CONSTRAINT patient_requirements_pkey PRIMARY KEY (id);


--
-- Name: patient_schedule_days patient_schedule_days_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_schedule_days
    ADD CONSTRAINT patient_schedule_days_pkey PRIMARY KEY (id);


--
-- Name: patient_schedule_days patient_schedule_days_weekly_schedule_id_day_of_week_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_schedule_days
    ADD CONSTRAINT patient_schedule_days_weekly_schedule_id_day_of_week_key UNIQUE (weekly_schedule_id, day_of_week);


--
-- Name: patients patients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: reschedule_requests reschedule_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reschedule_requests
    ADD CONSTRAINT reschedule_requests_pkey PRIMARY KEY (id);


--
-- Name: medical_documents unique_patient_clinic; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT unique_patient_clinic UNIQUE (patient_id, clinic_id);


--
-- Name: urgency_reviews urgency_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urgency_reviews
    ADD CONSTRAINT urgency_reviews_pkey PRIMARY KEY (id);


--
-- Name: water_intake_logs water_intake_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_intake_logs
    ADD CONSTRAINT water_intake_logs_pkey PRIMARY KEY (id);


--
-- Name: weekly_schedules weekly_schedules_patient_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT weekly_schedules_patient_unique UNIQUE (patient_id);


--
-- Name: weekly_schedules weekly_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT weekly_schedules_pkey PRIMARY KEY (id);


--
-- Name: weight_logs weight_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weight_logs
    ADD CONSTRAINT weight_logs_pkey PRIMARY KEY (id);


--
-- Name: daily_schedules_clinic_date_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_schedules_clinic_date_status_idx ON public.daily_schedules USING btree (clinic_id, schedule_date, status);


--
-- Name: daily_schedules_patient_date_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX daily_schedules_patient_date_unique ON public.daily_schedules USING btree (patient_id, schedule_date);


--
-- Name: daily_schedules_patient_history_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_schedules_patient_history_idx ON public.daily_schedules USING btree (patient_id, clinic_id, schedule_date DESC);


--
-- Name: donation_allocations_clinic_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX donation_allocations_clinic_id_idx ON public.donation_allocations USING btree (clinic_id);


--
-- Name: donation_allocations_donation_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX donation_allocations_donation_id_idx ON public.donation_allocations USING btree (donation_id);


--
-- Name: donation_audit_logs_clinic_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX donation_audit_logs_clinic_id_idx ON public.donation_audit_logs USING btree (clinic_id);


--
-- Name: donation_audit_logs_donation_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX donation_audit_logs_donation_id_idx ON public.donation_audit_logs USING btree (donation_id);


--
-- Name: notifications_recipient_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_recipient_created_idx ON public.notifications USING btree (recipient_id, created_at DESC);


--
-- Name: notifications_recipient_dedupe_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notifications_recipient_dedupe_unique ON public.notifications USING btree (recipient_id, dedupe_key) WHERE (dedupe_key IS NOT NULL);


--
-- Name: patient_announcements_clinic_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX patient_announcements_clinic_created_idx ON public.patient_announcements USING btree (clinic_id, created_at DESC);


--
-- Name: patient_announcements_clinic_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX patient_announcements_clinic_date_idx ON public.patient_announcements USING btree (clinic_id, announcement_date) WHERE (announcement_date IS NOT NULL);


--
-- Name: patient_medical_updates_patient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX patient_medical_updates_patient_idx ON public.patient_medical_updates USING btree (patient_id, created_at DESC);


--
-- Name: patients_clinic_name_sort_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX patients_clinic_name_sort_idx ON public.patients USING btree (clinic_id, lower(last_name), lower(first_name));


--
-- Name: profiles_name_sort_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX profiles_name_sort_idx ON public.profiles USING btree (lower(last_name), lower(first_name));


--
-- Name: reschedule_requests_clinic_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reschedule_requests_clinic_status_idx ON public.reschedule_requests USING btree (clinic_id, status, created_at DESC);


--
-- Name: reschedule_requests_patient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reschedule_requests_patient_idx ON public.reschedule_requests USING btree (patient_id, created_at DESC);


--
-- Name: reschedule_requests_pending_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reschedule_requests_pending_unique ON public.reschedule_requests USING btree (patient_id, original_date) WHERE (status = 'pending'::text);


--
-- Name: unique_admin_per_clinic; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_admin_per_clinic ON public.profiles USING btree (clinic_id) WHERE (role = 'admin'::text);


--
-- Name: unique_patient_clinic_application; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_patient_clinic_application ON public.patients USING btree (profile_id, clinic_id) WHERE ((profile_id IS NOT NULL) AND (clinic_id IS NOT NULL));


--
-- Name: donation_allocations donation_allocations_log_allocated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER donation_allocations_log_allocated AFTER INSERT ON public.donation_allocations FOR EACH ROW EXECUTE FUNCTION public.log_donation_allocated();


--
-- Name: donations donations_log_received; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER donations_log_received AFTER INSERT ON public.donations FOR EACH ROW EXECUTE FUNCTION public.log_donation_received();


--
-- Name: notifications notifications_client_update_guard_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notifications_client_update_guard_trg BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.notifications_client_update_guard();


--
-- Name: daily_schedules notify_daily_schedule_change_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notify_daily_schedule_change_trg AFTER UPDATE OF status ON public.daily_schedules FOR EACH ROW WHEN ((old.status IS DISTINCT FROM new.status)) EXECUTE FUNCTION public.notify_daily_schedule_change();


--
-- Name: patient_announcements notify_new_announcement_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notify_new_announcement_trg AFTER INSERT ON public.patient_announcements FOR EACH ROW EXECUTE FUNCTION public.notify_new_announcement();


--
-- Name: patients notify_patient_status_change_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notify_patient_status_change_trg AFTER UPDATE OF status ON public.patients FOR EACH ROW WHEN ((old.status IS DISTINCT FROM new.status)) EXECUTE FUNCTION public.notify_patient_status_change();


--
-- Name: reschedule_requests notify_reschedule_decision_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notify_reschedule_decision_trg AFTER UPDATE OF status ON public.reschedule_requests FOR EACH ROW WHEN ((old.status IS DISTINCT FROM new.status)) EXECUTE FUNCTION public.notify_reschedule_decision();


--
-- Name: weekly_schedules notify_schedule_assigned_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notify_schedule_assigned_trg AFTER INSERT ON public.weekly_schedules FOR EACH ROW EXECUTE FUNCTION public.notify_schedule_assigned();


--
-- Name: patient_announcements patient_announcements_set_owner_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER patient_announcements_set_owner_trg BEFORE INSERT ON public.patient_announcements FOR EACH ROW EXECUTE FUNCTION public.patient_announcements_set_owner();


--
-- Name: patient_announcements patient_announcements_touch_updated_at_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER patient_announcements_touch_updated_at_trg BEFORE UPDATE ON public.patient_announcements FOR EACH ROW EXECUTE FUNCTION public.patient_announcements_touch_updated_at();


--
-- Name: reschedule_requests reschedule_requests_set_clinic_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reschedule_requests_set_clinic_trg BEFORE INSERT ON public.reschedule_requests FOR EACH ROW EXECUTE FUNCTION public.reschedule_requests_set_clinic();


--
-- Name: patients trg_log_patient_medical_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_log_patient_medical_update AFTER UPDATE ON public.patients FOR EACH ROW EXECUTE FUNCTION public.log_patient_medical_update();


--
-- Name: patients trg_patient_acceptance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_patient_acceptance AFTER UPDATE OF status ON public.patients FOR EACH ROW EXECUTE FUNCTION public.handle_patient_acceptance();


--
-- Name: appointment_history appointment_history_appointment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_history
    ADD CONSTRAINT appointment_history_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES public.appointments(id) ON DELETE CASCADE;


--
-- Name: appointment_history appointment_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_history
    ADD CONSTRAINT appointment_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.profiles(id);


--
-- Name: appointments appointments_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id);


--
-- Name: blood_pressure_logs blood_pressure_logs_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blood_pressure_logs
    ADD CONSTRAINT blood_pressure_logs_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: blood_pressure_logs blood_pressure_logs_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blood_pressure_logs
    ADD CONSTRAINT blood_pressure_logs_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: clinic_schedule_settings clinic_schedule_settings_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinic_schedule_settings
    ADD CONSTRAINT clinic_schedule_settings_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: clinic_shifts clinic_shifts_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clinic_shifts
    ADD CONSTRAINT clinic_shifts_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: daily_schedules daily_schedules_cancelled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_schedules
    ADD CONSTRAINT daily_schedules_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES auth.users(id);


--
-- Name: daily_schedules daily_schedules_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_schedules
    ADD CONSTRAINT daily_schedules_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: daily_schedules daily_schedules_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_schedules
    ADD CONSTRAINT daily_schedules_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: daily_schedules daily_schedules_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_schedules
    ADD CONSTRAINT daily_schedules_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: daily_schedules daily_schedules_weekly_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_schedules
    ADD CONSTRAINT daily_schedules_weekly_schedule_id_fkey FOREIGN KEY (weekly_schedule_id) REFERENCES public.weekly_schedules(id) ON DELETE CASCADE;


--
-- Name: device_tokens device_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: dialysis_slots dialysis_slots_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dialysis_slots
    ADD CONSTRAINT dialysis_slots_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: distributions distributions_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distributions
    ADD CONSTRAINT distributions_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: distributions distributions_donation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distributions
    ADD CONSTRAINT distributions_donation_id_fkey FOREIGN KEY (donation_id) REFERENCES public.donations(id) ON DELETE CASCADE;


--
-- Name: donation_allocations donation_allocations_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_allocations
    ADD CONSTRAINT donation_allocations_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id);


--
-- Name: donation_allocations donation_allocations_donation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_allocations
    ADD CONSTRAINT donation_allocations_donation_id_fkey FOREIGN KEY (donation_id) REFERENCES public.donations(id) ON DELETE CASCADE;


--
-- Name: donation_audit_logs donation_audit_logs_allocation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_audit_logs
    ADD CONSTRAINT donation_audit_logs_allocation_id_fkey FOREIGN KEY (allocation_id) REFERENCES public.donation_allocations(id) ON DELETE SET NULL;


--
-- Name: donation_audit_logs donation_audit_logs_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_audit_logs
    ADD CONSTRAINT donation_audit_logs_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id);


--
-- Name: donation_audit_logs donation_audit_logs_donation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_audit_logs
    ADD CONSTRAINT donation_audit_logs_donation_id_fkey FOREIGN KEY (donation_id) REFERENCES public.donations(id) ON DELETE CASCADE;


--
-- Name: donation_audit_logs donation_audit_logs_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donation_audit_logs
    ADD CONSTRAINT donation_audit_logs_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES auth.users(id);


--
-- Name: donations donations_donor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_donor_id_fkey FOREIGN KEY (donor_id) REFERENCES public.donors(id) ON DELETE SET NULL;


--
-- Name: donations fk_clinic; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT fk_clinic FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE SET NULL;


--
-- Name: fund_distributions fund_distributions_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fund_distributions
    ADD CONSTRAINT fund_distributions_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id);


--
-- Name: login_history login_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_history
    ADD CONSTRAINT login_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medical_documents medical_documents_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: medical_documents medical_documents_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: medical_documents medical_documents_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id);


--
-- Name: notifications notifications_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: patient_announcements patient_announcements_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_announcements
    ADD CONSTRAINT patient_announcements_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: patient_announcements patient_announcements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_announcements
    ADD CONSTRAINT patient_announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: patient_fund_receipts patient_fund_receipts_distribution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_fund_receipts
    ADD CONSTRAINT patient_fund_receipts_distribution_id_fkey FOREIGN KEY (distribution_id) REFERENCES public.fund_distributions(id);


--
-- Name: patient_medical_updates patient_medical_updates_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_medical_updates
    ADD CONSTRAINT patient_medical_updates_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE SET NULL;


--
-- Name: patient_medical_updates patient_medical_updates_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_medical_updates
    ADD CONSTRAINT patient_medical_updates_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: patient_medical_updates patient_medical_updates_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_medical_updates
    ADD CONSTRAINT patient_medical_updates_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: patient_requirements patient_requirements_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_requirements
    ADD CONSTRAINT patient_requirements_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: patient_schedule_days patient_schedule_days_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_schedule_days
    ADD CONSTRAINT patient_schedule_days_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: patient_schedule_days patient_schedule_days_shift_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_schedule_days
    ADD CONSTRAINT patient_schedule_days_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES public.clinic_shifts(id);


--
-- Name: patient_schedule_days patient_schedule_days_weekly_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_schedule_days
    ADD CONSTRAINT patient_schedule_days_weekly_schedule_id_fkey FOREIGN KEY (weekly_schedule_id) REFERENCES public.weekly_schedules(id) ON DELETE CASCADE;


--
-- Name: patients patients_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: patients patients_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE SET NULL;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id);


--
-- Name: reschedule_requests reschedule_requests_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reschedule_requests
    ADD CONSTRAINT reschedule_requests_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: reschedule_requests reschedule_requests_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reschedule_requests
    ADD CONSTRAINT reschedule_requests_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: reschedule_requests reschedule_requests_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reschedule_requests
    ADD CONSTRAINT reschedule_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id);


--
-- Name: urgency_reviews urgency_reviews_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.urgency_reviews
    ADD CONSTRAINT urgency_reviews_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id);


--
-- Name: water_intake_logs water_intake_logs_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_intake_logs
    ADD CONSTRAINT water_intake_logs_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: weekly_schedules weekly_schedules_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT weekly_schedules_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: weekly_schedules weekly_schedules_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT weekly_schedules_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: weekly_schedules weekly_schedules_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT weekly_schedules_slot_id_fkey FOREIGN KEY (slot_id) REFERENCES public.dialysis_slots(id) ON DELETE SET NULL;


--
-- Name: weight_logs weight_logs_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weight_logs
    ADD CONSTRAINT weight_logs_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(id) ON DELETE CASCADE;


--
-- Name: weight_logs weight_logs_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weight_logs
    ADD CONSTRAINT weight_logs_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: profiles Admin Update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin Update" ON public.profiles FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: patients Admins can also view patients in their clinic; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can also view patients in their clinic" ON public.patients FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.clinic_id = patients.clinic_id)))) AND (status = ANY (ARRAY['pending'::text, 'no_sched'::text, 'active'::text, 'declined'::text]))));


--
-- Name: patient_announcements Admins can create own clinic announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can create own clinic announcements" ON public.patient_announcements FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_announcements.clinic_id)))));


--
-- Name: patients Admins can decline own clinic patients; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can decline own clinic patients" ON public.patients FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND (profiles.status = 'active'::text) AND (profiles.is_active = true) AND (profiles.clinic_id = patients.clinic_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND (profiles.status = 'active'::text) AND (profiles.is_active = true) AND (profiles.clinic_id = patients.clinic_id)))));


--
-- Name: blood_pressure_logs Admins can delete clinic blood pressure logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can delete clinic blood pressure logs" ON public.blood_pressure_logs FOR DELETE TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: daily_schedules Admins can delete clinic daily schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can delete clinic daily schedules" ON public.daily_schedules FOR DELETE TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: weight_logs Admins can delete clinic weight logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can delete clinic weight logs" ON public.weight_logs FOR DELETE TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: patient_announcements Admins can delete own clinic announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can delete own clinic announcements" ON public.patient_announcements FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_announcements.clinic_id)))));


--
-- Name: patients Admins can delete own clinic patients; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can delete own clinic patients" ON public.patients FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND (profiles.status = 'active'::text) AND (profiles.is_active = true) AND (profiles.clinic_id = patients.clinic_id)))));


--
-- Name: blood_pressure_logs Admins can insert clinic blood pressure logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert clinic blood pressure logs" ON public.blood_pressure_logs FOR INSERT TO authenticated WITH CHECK ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: weight_logs Admins can insert clinic weight logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert clinic weight logs" ON public.weight_logs FOR INSERT TO authenticated WITH CHECK ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: daily_schedules Admins can insert daily schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert daily schedules" ON public.daily_schedules FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = daily_schedules.clinic_id)))));


--
-- Name: clinic_shifts Admins can insert own clinic shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert own clinic shifts" ON public.clinic_shifts FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = clinic_shifts.clinic_id)))));


--
-- Name: weekly_schedules Admins can insert weekly schedules for their clinic; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert weekly schedules for their clinic" ON public.weekly_schedules FOR INSERT TO authenticated WITH CHECK (((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))) AND (created_by = auth.uid())));


--
-- Name: patient_schedule_days Admins can manage own clinic patient schedule days; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage own clinic patient schedule days" ON public.patient_schedule_days TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_schedule_days.clinic_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_schedule_days.clinic_id)))));


--
-- Name: weekly_schedules Admins can manage schedules in their clinic; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage schedules in their clinic" ON public.weekly_schedules USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND ((profiles.user_location)::uuid = weekly_schedules.clinic_id)))));


--
-- Name: reschedule_requests Admins can review own clinic reschedule requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can review own clinic reschedule requests" ON public.reschedule_requests FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = reschedule_requests.clinic_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = reschedule_requests.clinic_id)))));


--
-- Name: daily_schedules Admins can update clinic daily schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update clinic daily schedules" ON public.daily_schedules FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = daily_schedules.clinic_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = daily_schedules.clinic_id)))));


--
-- Name: patient_announcements Admins can update own clinic announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update own clinic announcements" ON public.patient_announcements FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_announcements.clinic_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_announcements.clinic_id)))));


--
-- Name: clinic_schedule_settings Admins can update own clinic schedule settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update own clinic schedule settings" ON public.clinic_schedule_settings FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = clinic_schedule_settings.clinic_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = clinic_schedule_settings.clinic_id)))));


--
-- Name: clinic_shifts Admins can update own clinic shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update own clinic shifts" ON public.clinic_shifts FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = clinic_shifts.clinic_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = clinic_shifts.clinic_id)))));


--
-- Name: patients Admins can update patient status in their clinic; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update patient status in their clinic" ON public.patients FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND (profiles.clinic_id = patients.clinic_id))))) WITH CHECK ((status = ANY (ARRAY['pending'::text, 'no_sched'::text, 'active'::text, 'declined'::text])));


--
-- Name: patients Admins can update patients in their clinic; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update patients in their clinic" ON public.patients FOR UPDATE TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND (profiles.status = 'active'::text) AND (profiles.is_active = true))))) WITH CHECK ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND (profiles.status = 'active'::text) AND (profiles.is_active = true)))));


--
-- Name: weekly_schedules Admins can update weekly schedules for their clinic; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update weekly schedules for their clinic" ON public.weekly_schedules FOR UPDATE TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: clinic_schedule_settings Admins can upsert own clinic schedule settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can upsert own clinic schedule settings" ON public.clinic_schedule_settings FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = clinic_schedule_settings.clinic_id)))));


--
-- Name: blood_pressure_logs Admins can view clinic blood pressure logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view clinic blood pressure logs" ON public.blood_pressure_logs FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: weight_logs Admins can view clinic weight logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view clinic weight logs" ON public.weight_logs FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: daily_schedules Admins can view daily schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view daily schedules" ON public.daily_schedules FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = daily_schedules.clinic_id)))));


--
-- Name: patient_announcements Admins can view own clinic announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view own clinic announcements" ON public.patient_announcements FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_announcements.clinic_id)))));


--
-- Name: patient_medical_updates Admins can view own clinic medical history; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view own clinic medical history" ON public.patient_medical_updates FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_medical_updates.clinic_id)))));


--
-- Name: patient_schedule_days Admins can view own clinic patient schedule days; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view own clinic patient schedule days" ON public.patient_schedule_days FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = patient_schedule_days.clinic_id)))));


--
-- Name: reschedule_requests Admins can view own clinic reschedule requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view own clinic reschedule requests" ON public.reschedule_requests FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = reschedule_requests.clinic_id)))));


--
-- Name: clinic_schedule_settings Admins can view own clinic schedule settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view own clinic schedule settings" ON public.clinic_schedule_settings FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = clinic_schedule_settings.clinic_id)))));


--
-- Name: clinic_shifts Admins can view own clinic shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view own clinic shifts" ON public.clinic_shifts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text) AND (p.clinic_id = clinic_shifts.clinic_id)))));


--
-- Name: weekly_schedules Admins can view weekly schedules for their clinic; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view weekly schedules for their clinic" ON public.weekly_schedules FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: profiles Admins limited access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins limited access" ON public.profiles FOR SELECT TO authenticated USING (((auth.jwt() ->> 'role'::text) = 'admin'::text));


--
-- Name: donations Allow anonymous donation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow anonymous donation" ON public.donations FOR INSERT TO anon WITH CHECK ((donor_id IS NULL));


--
-- Name: donation_purchase_logs Allow authenticated users to insert purchase logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated users to insert purchase logs" ON public.donation_purchase_logs FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: donation_purchase_logs Allow authenticated users to view purchase logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated users to view purchase logs" ON public.donation_purchase_logs FOR SELECT TO authenticated USING (true);


--
-- Name: clinics Allow delete for all users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow delete for all users" ON public.clinics FOR DELETE TO authenticated, anon USING (true);


--
-- Name: donation_allocations Allow donation allocation inserts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow donation allocation inserts" ON public.donation_allocations FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: donors Allow insert for authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow insert for authenticated users" ON public.donors FOR INSERT TO authenticated WITH CHECK ((auth.uid() = id));


--
-- Name: medical_documents Allow insert for authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow insert for authenticated users" ON public.medical_documents FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: fund_distributions Allow insert for everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow insert for everyone" ON public.fund_distributions FOR INSERT WITH CHECK (true);


--
-- Name: fund_distributions Allow insert fund distributions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow insert fund distributions" ON public.fund_distributions FOR INSERT WITH CHECK (true);


--
-- Name: audit_logs Allow insert logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow insert logs" ON public.audit_logs FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: donations Allow read donations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow read donations" ON public.donations FOR SELECT USING (true);


--
-- Name: fund_distributions Allow read fund distributions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow read fund distributions" ON public.fund_distributions FOR SELECT USING (true);


--
-- Name: audit_logs Allow read logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow read logs" ON public.audit_logs FOR SELECT TO authenticated USING (true);


--
-- Name: profiles Allow select own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow select own profile" ON public.profiles FOR SELECT TO authenticated USING ((id = auth.uid()));


--
-- Name: donations Allow update donations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow update donations" ON public.donations FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: clinics Allow update for all users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow update for all users" ON public.clinics FOR UPDATE TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: profiles Authenticated users can create profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can create profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK ((id = auth.uid()));


--
-- Name: donation_allocations Center admins can view their own allocations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Center admins can view their own allocations" ON public.donation_allocations FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: donation_audit_logs Center admins can view their own audit logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Center admins can view their own audit logs" ON public.donation_audit_logs FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: donations Center admins can view their own center's donations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Center admins can view their own center's donations" ON public.donations FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: notifications Clinic admins can create notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clinic admins can create notifications" ON public.notifications FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM (public.profiles admin_profile
     JOIN public.patients p ON ((p.profile_id = notifications.recipient_id)))
  WHERE ((admin_profile.id = auth.uid()) AND (admin_profile.role = 'admin'::text) AND (admin_profile.clinic_id = p.clinic_id)))));


--
-- Name: medical_documents Clinic users can delete medical documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clinic users can delete medical documents" ON public.medical_documents FOR DELETE TO authenticated USING ((clinic_id = ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: medical_documents Clinic users can insert medical documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clinic users can insert medical documents" ON public.medical_documents FOR INSERT TO authenticated WITH CHECK ((clinic_id = ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: medical_documents Clinic users can update medical documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clinic users can update medical documents" ON public.medical_documents FOR UPDATE TO authenticated USING ((clinic_id = ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid())))) WITH CHECK ((clinic_id = ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: medical_documents Clinic users can view medical documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clinic users can view medical documents" ON public.medical_documents FOR SELECT TO authenticated USING ((clinic_id = ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


--
-- Name: profiles Delete Admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Delete Admin" ON public.profiles FOR DELETE TO authenticated USING (true);


--
-- Name: clinics Enable Insert access for all users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Enable Insert access for all users" ON public.clinics FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: clinics Enable read access for all users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Enable read access for all users" ON public.clinics FOR SELECT TO authenticated, anon USING (true);


--
-- Name: patients Enable read access for all users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Enable read access for all users" ON public.patients FOR SELECT TO authenticated, anon USING (true);


--
-- Name: profiles Enable read access for all users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Enable read access for all users" ON public.profiles FOR SELECT TO authenticated USING (true);


--
-- Name: donations Insert donation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Insert donation" ON public.donations FOR INSERT TO authenticated WITH CHECK ((auth.uid() = donor_id));


--
-- Name: patients Insert patient with clinic; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Insert patient with clinic" ON public.patients FOR INSERT TO authenticated WITH CHECK ((auth.uid() = id));


--
-- Name: reschedule_requests Patients can cancel own pending reschedule requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can cancel own pending reschedule requests" ON public.reschedule_requests FOR UPDATE TO authenticated USING (((status = 'pending'::text) AND (EXISTS ( SELECT 1
   FROM public.patients pt
  WHERE ((pt.id = reschedule_requests.patient_id) AND (pt.profile_id = auth.uid())))))) WITH CHECK (((status = ANY (ARRAY['pending'::text, 'cancelled'::text])) AND (EXISTS ( SELECT 1
   FROM public.patients pt
  WHERE ((pt.id = reschedule_requests.patient_id) AND (pt.profile_id = auth.uid()))))));


--
-- Name: water_intake_logs Patients can delete own water intake logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can delete own water intake logs" ON public.water_intake_logs FOR DELETE TO authenticated USING ((patient_id IN ( SELECT patients.id
   FROM public.patients
  WHERE (patients.profile_id = auth.uid()))));


--
-- Name: patients Patients can insert own record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can insert own record" ON public.patients FOR INSERT TO authenticated WITH CHECK (((auth.uid() = profile_id) AND (status = 'pending'::text)));


--
-- Name: water_intake_logs Patients can insert own water intake logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can insert own water intake logs" ON public.water_intake_logs FOR INSERT TO authenticated WITH CHECK ((patient_id IN ( SELECT patients.id
   FROM public.patients
  WHERE (patients.profile_id = auth.uid()))));


--
-- Name: profiles Patients can only see themselves; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can only see themselves" ON public.profiles FOR SELECT TO authenticated USING (((auth.uid() = id) AND (role = 'patient'::text)));


--
-- Name: reschedule_requests Patients can submit own reschedule requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can submit own reschedule requests" ON public.reschedule_requests FOR INSERT TO authenticated WITH CHECK (((status = 'pending'::text) AND (EXISTS ( SELECT 1
   FROM public.patients pt
  WHERE ((pt.id = reschedule_requests.patient_id) AND (pt.profile_id = auth.uid()))))));


--
-- Name: patients Patients can update own patient record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can update own patient record" ON public.patients FOR UPDATE TO authenticated USING ((profile_id = auth.uid())) WITH CHECK ((profile_id = auth.uid()));


--
-- Name: water_intake_logs Patients can update own water intake logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can update own water intake logs" ON public.water_intake_logs FOR UPDATE TO authenticated USING ((patient_id IN ( SELECT patients.id
   FROM public.patients
  WHERE (patients.profile_id = auth.uid())))) WITH CHECK ((patient_id IN ( SELECT patients.id
   FROM public.patients
  WHERE (patients.profile_id = auth.uid()))));


--
-- Name: medical_documents Patients can view own application documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own application documents" ON public.medical_documents FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.patients pt
  WHERE ((pt.id = medical_documents.patient_id) AND (pt.profile_id = auth.uid())))));


--
-- Name: patients Patients can view own approved active profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own approved active profile" ON public.patients FOR SELECT TO authenticated USING (((profile_id = auth.uid()) AND (status = 'active'::text)));


--
-- Name: patients Patients can view own approved record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own approved record" ON public.patients FOR SELECT TO authenticated USING (((auth.uid() = id) AND (status = 'approved'::text)));


--
-- Name: blood_pressure_logs Patients can view own blood pressure logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own blood pressure logs" ON public.blood_pressure_logs FOR SELECT TO authenticated USING ((patient_id IN ( SELECT patients.id
   FROM public.patients
  WHERE (patients.profile_id = auth.uid()))));


--
-- Name: patient_announcements Patients can view own center announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own center announcements" ON public.patient_announcements FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.patients pt
  WHERE ((pt.profile_id = auth.uid()) AND (pt.clinic_id = patient_announcements.clinic_id)))));


--
-- Name: daily_schedules Patients can view own daily schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own daily schedules" ON public.daily_schedules FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.patients pt
  WHERE ((pt.id = daily_schedules.patient_id) AND (pt.profile_id = auth.uid())))));


--
-- Name: patients Patients can view own record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own record" ON public.patients FOR SELECT TO authenticated USING ((auth.uid() = profile_id));


--
-- Name: reschedule_requests Patients can view own reschedule requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own reschedule requests" ON public.reschedule_requests FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.patients pt
  WHERE ((pt.id = reschedule_requests.patient_id) AND (pt.profile_id = auth.uid())))));


--
-- Name: water_intake_logs Patients can view own water intake logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own water intake logs" ON public.water_intake_logs FOR SELECT TO authenticated USING ((patient_id IN ( SELECT patients.id
   FROM public.patients
  WHERE (patients.profile_id = auth.uid()))));


--
-- Name: weekly_schedules Patients can view own weekly schedule; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own weekly schedule" ON public.weekly_schedules FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.patients p
  WHERE ((p.id = weekly_schedules.patient_id) AND (p.profile_id = auth.uid())))));


--
-- Name: weight_logs Patients can view own weight logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients can view own weight logs" ON public.weight_logs FOR SELECT TO authenticated USING ((patient_id IN ( SELECT patients.id
   FROM public.patients
  WHERE (patients.profile_id = auth.uid()))));


--
-- Name: patients Patients cannot update status; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Patients cannot update status" ON public.patients FOR UPDATE TO authenticated USING (false);


--
-- Name: donations Select donation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Select donation" ON public.donations FOR SELECT TO authenticated USING (true);


--
-- Name: profiles Super Admin full access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Super Admin full access" ON public.profiles FOR SELECT TO authenticated USING (((auth.jwt() ->> 'role'::text) = 'superadmin'::text));


--
-- Name: donation_allocations Superadmins can view all allocations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Superadmins can view all allocations" ON public.donation_allocations FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'superadmin'::text)))));


--
-- Name: donation_audit_logs Superadmins can view all audit logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Superadmins can view all audit logs" ON public.donation_audit_logs FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'superadmin'::text)))));


--
-- Name: weekly_schedules TEMP allow all weekly; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "TEMP allow all weekly" ON public.weekly_schedules FOR SELECT TO authenticated USING (true);


--
-- Name: donations Update donation proof; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Update donation proof" ON public.donations FOR UPDATE TO authenticated USING ((auth.uid() = donor_id));


--
-- Name: notifications Users can create own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can create own notifications" ON public.notifications FOR INSERT TO authenticated WITH CHECK ((recipient_id = auth.uid()));


--
-- Name: device_tokens Users can insert own device tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own device tokens" ON public.device_tokens FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: device_tokens Users can update own device tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own device tokens" ON public.device_tokens FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: notifications Users can update own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own notifications" ON public.notifications FOR UPDATE TO authenticated USING ((recipient_id = auth.uid())) WITH CHECK ((recipient_id = auth.uid()));


--
-- Name: device_tokens Users can view own device tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own device tokens" ON public.device_tokens FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: notifications Users can view own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own notifications" ON public.notifications FOR SELECT TO authenticated USING ((recipient_id = auth.uid()));


--
-- Name: notifications Users create own client notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users create own client notifications" ON public.notifications FOR INSERT TO authenticated WITH CHECK (((recipient_id = auth.uid()) AND (sender_id IS NULL) AND (type = ANY (ARRAY['schedule_today'::text, 'schedule_tomorrow'::text, 'water_alert'::text, 'security'::text]))));


--
-- Name: device_tokens Users manage own device tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users manage own device tokens" ON public.device_tokens TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: notifications Users mark own notifications read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users mark own notifications read" ON public.notifications FOR UPDATE TO authenticated USING ((recipient_id = auth.uid())) WITH CHECK ((recipient_id = auth.uid()));


--
-- Name: notifications Users read own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users read own notifications" ON public.notifications FOR SELECT TO authenticated USING ((recipient_id = auth.uid()));


--
-- Name: profiles allow all insert profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "allow all insert profiles" ON public.profiles FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: appointment_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appointment_history ENABLE ROW LEVEL SECURITY;

--
-- Name: appointments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: blood_pressure_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.blood_pressure_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: clinic_schedule_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clinic_schedule_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: clinic_shifts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clinic_shifts ENABLE ROW LEVEL SECURITY;

--
-- Name: clinics; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clinics ENABLE ROW LEVEL SECURITY;

--
-- Name: daily_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_schedules ENABLE ROW LEVEL SECURITY;

--
-- Name: device_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: dialysis_slots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dialysis_slots ENABLE ROW LEVEL SECURITY;

--
-- Name: distributions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.distributions ENABLE ROW LEVEL SECURITY;

--
-- Name: donation_allocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.donation_allocations ENABLE ROW LEVEL SECURITY;

--
-- Name: donation_audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.donation_audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: donation_purchase_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.donation_purchase_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: donations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.donations ENABLE ROW LEVEL SECURITY;

--
-- Name: donors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.donors ENABLE ROW LEVEL SECURITY;

--
-- Name: fund_distributions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fund_distributions ENABLE ROW LEVEL SECURITY;

--
-- Name: fund_pool; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fund_pool ENABLE ROW LEVEL SECURITY;

--
-- Name: login_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;

--
-- Name: medical_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medical_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: patient_announcements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patient_announcements ENABLE ROW LEVEL SECURITY;

--
-- Name: patient_fund_receipts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patient_fund_receipts ENABLE ROW LEVEL SECURITY;

--
-- Name: patient_medical_updates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patient_medical_updates ENABLE ROW LEVEL SECURITY;

--
-- Name: patient_requirements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patient_requirements ENABLE ROW LEVEL SECURITY;

--
-- Name: patient_schedule_days; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patient_schedule_days ENABLE ROW LEVEL SECURITY;

--
-- Name: patients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;

--
-- Name: patients_backup_before_multi_inquiry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patients_backup_before_multi_inquiry ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: reschedule_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reschedule_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: urgency_reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.urgency_reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: water_intake_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.water_intake_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: weekly_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.weekly_schedules ENABLE ROW LEVEL SECURITY;

--
-- Name: weight_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.weight_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime blood_pressure_logs; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.blood_pressure_logs;


--
-- Name: supabase_realtime clinics; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.clinics;


--
-- Name: supabase_realtime daily_schedules; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.daily_schedules;


--
-- Name: supabase_realtime notifications; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.notifications;


--
-- Name: supabase_realtime patients; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.patients;


--
-- Name: supabase_realtime profiles; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.profiles;


--
-- Name: supabase_realtime weekly_schedules; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.weekly_schedules;


--
-- Name: supabase_realtime weight_logs; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.weight_logs;


--
-- PostgreSQL database dump complete
--


