-- ROLLBACK for supabase_migration_donation_sandbox.sql
--
-- *** DO NOT RUN THIS UNLESS YOU HAVE DECIDED TO UNDO THE MIGRATION. ***
-- It stops by itself until the settings in step 0 are edited.
-- Tested on a disposable local PostgreSQL database; NOT executed against live Supabase.
--
-- Use it only AFTER the sandbox migration has been applied. It puts the
-- donation schema back to how it was in the 2026-11-05 backup, while keeping
-- everything else that happened since (new patients, schedules, legacy
-- donations, purchase logs, fund distributions).
--
-- Run it as one script in the Supabase SQL Editor. It is one transaction:
-- if any step fails, nothing is changed.
--
-- WARNING: this deliberately REOPENS the security problems the migration
-- closed: public read of donor details, public update of donations, and any
-- signed-in user editing any profile, including their own role.
--
-- Function bodies and policies in steps 2 and 3 are copied verbatim from
-- database-backups/cure_nurture_before_donation_migration.dump.
--
-- No statement drops objects with CASCADE: if something unexpected depends on
-- an object, the script stops instead of silently removing that too.

begin;

-- =====================================================================
-- 0. Safety checks and removal of the guards
-- =====================================================================

do $$
declare
  -- EDIT 1: change to 'I_UNDERSTAND_THIS_REOPENS_SECURITY_HOLES' to run.
  c_confirm constant text := 'NOT_CONFIRMED';

  -- EDIT 2: what to do with donations made through the new checkout.
  --   false: stop if any exist (default, nothing is removed).
  --   true:  copy them to donation_sandbox_rollback_archive, then delete them.
  -- They cannot simply stay: once the payment columns are gone a simulated
  -- donation looks like an ordinary pending donation, and a Super Admin
  -- could then approve it as real money.
  c_remove_workflow_rows constant boolean := false;

  v_workflow_rows bigint;
begin
  if c_confirm <> 'I_UNDERSTAND_THIS_REOPENS_SECURITY_HOLES' then
    raise exception 'ROLLBACK NOT CONFIRMED: edit step 0 first. Nothing was changed.';
  end if;

  if to_regclass('public.donation_payment_settings') is null then
    raise exception 'The sandbox migration is not applied; there is nothing to roll back.';
  end if;

  if exists (select 1 from public.donations where payment_environment = 'production') then
    raise exception 'Production payment rows exist. This script must not touch them. Nothing was changed.';
  end if;

  select count(*) into v_workflow_rows
  from public.donations where payment_environment is not null;

  if v_workflow_rows > 0 and not c_remove_workflow_rows then
    raise exception '% checkout donation(s) exist. Review them, then set c_remove_workflow_rows to true. Nothing was changed.',
      v_workflow_rows;
  end if;

  -- The allocation-total trigger must go before any delete, so that no
  -- deferred check is left pending when the columns are dropped below.
  drop trigger if exists donations_guard_payment_columns on public.donations;
  drop trigger if exists donations_guard_truncate on public.donations;
  drop trigger if exists donation_allocations_guard_rows on public.donation_allocations;
  drop trigger if exists donation_allocations_guard_truncate on public.donation_allocations;
  drop trigger if exists donation_allocations_total_check on public.donation_allocations;
  drop trigger if exists profiles_guard_privileges on public.profiles;

  if v_workflow_rows > 0 then
    create table if not exists public.donation_sandbox_rollback_archive (
      source_table text not null,
      row_data jsonb not null,
      archived_at timestamptz not null default now()
    );
    alter table public.donation_sandbox_rollback_archive enable row level security;
    revoke all on public.donation_sandbox_rollback_archive from anon, authenticated, public;

    insert into public.donation_sandbox_rollback_archive (source_table, row_data)
    select 'donations', to_jsonb(d) - 'client_secret_hash'
    from public.donations d
    where d.payment_environment is not null;

    insert into public.donation_sandbox_rollback_archive (source_table, row_data)
    select 'donation_allocations', to_jsonb(a)
    from public.donation_allocations a
    join public.donations d on d.id = a.donation_id
    where d.payment_environment is not null;

    insert into public.donation_sandbox_rollback_archive (source_table, row_data)
    select 'donation_audit_logs', to_jsonb(l)
    from public.donation_audit_logs l
    join public.donations d on d.id = l.donation_id
    where d.payment_environment is not null;

    -- Allocations and audit rows follow through their foreign keys.
    delete from public.donations where payment_environment is not null;
  end if;
end;
$$;

set constraints all immediate;

-- =====================================================================
-- 1. Remove the policies that use the new role helpers
-- =====================================================================

drop policy if exists "Superadmins can read all donations" on public.donations;
drop policy if exists "Center admins can view their own center's donations" on public.donations;
drop policy if exists "Center admins can view their own allocations" on public.donation_allocations;
drop policy if exists "Superadmins can view all allocations" on public.donation_allocations;
drop policy if exists "Center admins can view their own audit logs" on public.donation_audit_logs;
drop policy if exists "Superadmins can view all audit logs" on public.donation_audit_logs;

-- =====================================================================
-- 2. Restore the four functions the migration replaced
-- =====================================================================

create or replace function public.approve_donation(p_donation_id uuid) RETURNS public.donations
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

create or replace function public.reject_donation(p_donation_id uuid) RETURNS public.donations
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

create or replace function public.log_donation_received() RETURNS trigger
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

create or replace function public.log_donation_allocated() RETURNS trigger
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

-- =====================================================================
-- 3. Restore the original policies
-- =====================================================================

-- donations
drop policy if exists "Allow anonymous donation" on public.donations;
CREATE POLICY "Allow anonymous donation" ON public.donations FOR INSERT TO anon WITH CHECK ((donor_id IS NULL));

drop policy if exists "Allow read donations" on public.donations;
CREATE POLICY "Allow read donations" ON public.donations FOR SELECT USING (true);

drop policy if exists "Allow update donations" on public.donations;
CREATE POLICY "Allow update donations" ON public.donations FOR UPDATE USING (true) WITH CHECK (true);

drop policy if exists "Center admins can view their own center's donations" on public.donations;
CREATE POLICY "Center admins can view their own center's donations" ON public.donations FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));

drop policy if exists "Insert donation" on public.donations;
CREATE POLICY "Insert donation" ON public.donations FOR INSERT TO authenticated WITH CHECK ((auth.uid() = donor_id));

drop policy if exists "Select donation" on public.donations;
CREATE POLICY "Select donation" ON public.donations FOR SELECT TO authenticated USING (true);

drop policy if exists "Update donation proof" on public.donations;
CREATE POLICY "Update donation proof" ON public.donations FOR UPDATE TO authenticated USING ((auth.uid() = donor_id));

-- donation_allocations
drop policy if exists "Allow donation allocation inserts" on public.donation_allocations;
CREATE POLICY "Allow donation allocation inserts" ON public.donation_allocations FOR INSERT TO authenticated, anon WITH CHECK (true);

drop policy if exists "Center admins can view their own allocations" on public.donation_allocations;
CREATE POLICY "Center admins can view their own allocations" ON public.donation_allocations FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));

drop policy if exists "Superadmins can view all allocations" on public.donation_allocations;
CREATE POLICY "Superadmins can view all allocations" ON public.donation_allocations FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'superadmin'::text)))));

-- donation_audit_logs
drop policy if exists "Center admins can view their own audit logs" on public.donation_audit_logs;
CREATE POLICY "Center admins can view their own audit logs" ON public.donation_audit_logs FOR SELECT TO authenticated USING ((clinic_id IN ( SELECT profiles.clinic_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));

drop policy if exists "Superadmins can view all audit logs" on public.donation_audit_logs;
CREATE POLICY "Superadmins can view all audit logs" ON public.donation_audit_logs FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'superadmin'::text)))));

-- =====================================================================
-- 4. Remove the functions the migration added
-- =====================================================================

drop function if exists public.create_donation_checkout(text, bigint, uuid, text, text, boolean, text);
drop function if exists public.get_donation_checkout(uuid, text);
drop function if exists public.cancel_donation_checkout(uuid, text);
drop function if exists public.simulate_donation_payment(uuid, text, text);
drop function if exists public.paymongo_attach_checkout(uuid, text, text);
drop function if exists public.paymongo_record_payment(text, text, text, text, boolean);
drop function if exists public.paymongo_get_owned_donation(uuid, text);
drop function if exists public.donation_finalize(uuid, text, text, text, text);
drop function if exists public.donation_lock_owned(uuid, text);
drop function if exists public.donation_checkout_json(uuid);
drop function if exists public.donation_secret_hash(text);
drop function if exists public.donation_equal_split(bigint, integer);
drop function if exists public.donation_eligible_centers();
drop function if exists public.public_donation_feed(integer);
drop function if exists public.public_donation_totals();
drop function if exists public.check_donation_allocation_total();
drop function if exists public.guard_donation_payment_columns();
drop function if exists public.guard_donation_allocation_rows();
drop function if exists public.guard_donation_truncate();
drop function if exists public.guard_profile_privileges();
drop function if exists public.donation_is_api_role();
drop policy if exists "Superadmins can view provider events" on public.payment_provider_events;
drop function if exists public.curenurture_is_superadmin();
drop function if exists public.curenurture_admin_clinic_id();

-- =====================================================================
-- 5. Remove the indexes, constraints, columns and tables it added
-- =====================================================================

drop index if exists public.donations_idempotency_key_uidx;
drop index if exists public.donations_reference_code_uidx;
drop index if exists public.donations_provider_checkout_id_uidx;
drop index if exists public.donations_payment_environment_idx;
drop index if exists public.donation_allocations_donation_clinic_uidx;

alter table public.donations
  drop constraint if exists donations_payment_environment_check,
  drop constraint if exists donations_payment_status_check,
  drop constraint if exists donations_payment_provider_check,
  drop constraint if exists donations_sandbox_never_verified,
  drop constraint if exists donations_simulated_is_sandbox,
  drop constraint if exists donations_amount_centavos_check;

alter table public.donation_allocations
  drop constraint if exists donation_allocations_status_check,
  drop constraint if exists donation_allocations_paid_out_ref,
  drop constraint if exists donation_allocations_amount_centavos_check;

alter table public.donations
  drop column if exists amount_centavos,
  drop column if exists currency,
  drop column if exists payment_provider,
  drop column if exists payment_environment,
  drop column if exists payment_status,
  drop column if exists status_reason,
  drop column if exists reference_code,
  drop column if exists provider_checkout_id,
  drop column if exists provider_checkout_url,
  drop column if exists provider_payment_id,
  drop column if exists payment_confirmed_at,
  drop column if exists updated_at,
  drop column if exists idempotency_key,
  drop column if exists client_secret_hash;

alter table public.donation_allocations
  drop column if exists amount_centavos,
  drop column if exists clinic_name_snapshot,
  drop column if exists allocation_status,
  drop column if exists provider_transfer_ref,
  drop column if exists sort_order,
  drop column if exists updated_at;

drop table if exists public.payment_provider_events;
drop table if exists public.donation_payment_settings;

-- =====================================================================
-- 6. Restore table permissions
-- =====================================================================
-- The backup holds NO permissions, so these are the Supabase defaults, not
-- a copy of what existed. BEFORE running, compare them with the "grant" rows
-- of the preflight CSV saved before the migration, and change this section
-- if that CSV shows anything different.

grant all on public.donations, public.donation_allocations, public.donation_audit_logs
  to anon, authenticated;

-- =====================================================================
-- 7. Self-check: any failure undoes the whole rollback
-- =====================================================================

do $$
declare
  v_problem text;
begin
  select string_agg(table_name || '.' || column_name, ', ') into v_problem
  from information_schema.columns
  where table_schema = 'public'
    and ((table_name = 'donations' and column_name not in (
           'id', 'donor_id', 'name', 'email', 'amount', 'payment_method', 'proof_url',
           'status', 'created_at', 'clinic_id', 'allocation_type'))
      or (table_name = 'donation_allocations' and column_name not in (
           'id', 'donation_id', 'clinic_id', 'amount', 'created_at')));
  if v_problem is not null then
    raise exception 'SELF-CHECK FAILED: unexpected columns remain: %', v_problem;
  end if;

  select string_agg(p.proname, ', ') into v_problem
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname in (
      'create_donation_checkout', 'get_donation_checkout', 'cancel_donation_checkout',
      'simulate_donation_payment', 'paymongo_attach_checkout', 'paymongo_record_payment',
      'paymongo_get_owned_donation', 'donation_finalize', 'donation_lock_owned',
      'donation_checkout_json', 'donation_secret_hash', 'donation_equal_split',
      'donation_eligible_centers', 'public_donation_feed', 'public_donation_totals',
      'check_donation_allocation_total', 'guard_donation_payment_columns',
      'guard_donation_allocation_rows', 'guard_donation_truncate',
      'guard_profile_privileges', 'donation_is_api_role',
      'curenurture_is_superadmin', 'curenurture_admin_clinic_id');
  if v_problem is not null then
    raise exception 'SELF-CHECK FAILED: functions remain: %', v_problem;
  end if;

  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'donations') <> 7
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'donation_allocations') <> 3
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'donation_audit_logs') <> 2 then
    raise exception 'SELF-CHECK FAILED: policy counts differ from the backup.';
  end if;

  if to_regclass('public.donation_payment_settings') is not null
     or to_regclass('public.payment_provider_events') is not null then
    raise exception 'SELF-CHECK FAILED: migration tables remain.';
  end if;

  raise notice 'Rollback self-check passed.';
end;
$$;

commit;

notify pgrst, 'reload schema';
