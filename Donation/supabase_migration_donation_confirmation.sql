-- Feature 4: Superadmin donation confirmation, center allocation visibility,
-- and an append-only audit trail.
--
-- Run this ONCE in the Supabase SQL Editor, AFTER
-- supabase_migration_donation_allocations.sql has already been applied.
--
-- This migration only ADDS things (one column, one missing RLS policy, one
-- new table, two trigger functions, two RPC functions). It does not alter
-- the donor-facing flow in donation_page.dart / proof_page.dart, and does
-- not touch fund_distributions, donation_purchase_logs, or any existing
-- Super Admin / Center Admin feature that isn't donation-allocation related.
--
-- WHY EACH PIECE IS HERE:
--
-- 1. donations.allocation_type
--    "Specific Dialysis Center" and "Randomly Assign a Dialysis Center" both
--    resolve to donations.clinic_id, so from stored data alone there is no
--    way to tell Super Admin *how* that center was chosen -- donor pick vs.
--    system random pick look identical. This column records which of the
--    three donor-selected allocation methods produced the row, so the
--    Super Admin review UI can show it truthfully. It is nullable so
--    historical rows created before this migration are simply "unknown"
--    rather than wrongly labeled.
--
-- 2. Missing Super Admin SELECT policy on donation_allocations
--    donation_allocations currently only grants SELECT to the center admin
--    who owns the allocation's clinic_id (see
--    supabase_migration_donation_allocations.sql). Super Admin has no way
--    to read equal-distribution breakdowns at all today. This adds that.
--
-- 3. donation_audit_logs
--    Nothing like this exists. fund_distributions' "Distribution Audit Log"
--    in the Super Admin UI is a different, unrelated manual ledger (cash
--    pushed to a center outside of any specific donation). This table is
--    intentionally append-only: no INSERT/UPDATE/DELETE policy is granted
--    to anon/authenticated at all, so normal Super Admin or Center Admin
--    UI users cannot edit history -- only the SECURITY DEFINER trigger
--    functions and RPC functions below (which run as the function owner,
--    bypassing RLS) can write to it.
--
-- 4. Triggers: log_donation_received, log_donation_allocated
--    Fire automatically on INSERT into donations / donation_allocations, so
--    the audit trail reflects what actually happened at the database level
--    regardless of what the calling UI remembers to do.
--
-- 5. RPCs: approve_donation, reject_donation
--    Replace the Super Admin app's direct
--    `donations.update({status: 'verified'})` call with a single atomic,
--    idempotent operation: it row-locks the donation, refuses to run twice
--    (raises an exception if the donation isn't still 'pending' -- so a
--    double-click or duplicate request cannot double-process it), flips
--    status, and writes the DONATION_APPROVED / DONATION_SENT_TO_CENTER (one
--    per recipient center) audit rows in the same transaction. Only a
--    profile with role = 'superadmin' may call these.
--
--    Equal-distribution shares are NOT recalculated here against the
--    then-current center roster. They were already computed and persisted
--    into donation_allocations at donation-submission time (see
--    donation_page.dart), using integer-centavo rounding so they always sum
--    exactly to the donation amount. Recomputing at approval time would
--    silently produce a different split than what the donor saw and what
--    center admins already see pre-approval, so approval instead uses the
--    allocation rows that already exist for this donation.

-- ---------------------------------------------------------------------
-- 1. allocation_type
-- ---------------------------------------------------------------------

alter table public.donations
  add column if not exists allocation_type text;

alter table public.donations
  drop constraint if exists donations_allocation_type_check;

alter table public.donations
  add constraint donations_allocation_type_check
    check (allocation_type is null or allocation_type in (
      'specific_center', 'random_center', 'equal_distribution'
    ));

-- ---------------------------------------------------------------------
-- 1b. Center admins can read their own center's donations
-- ---------------------------------------------------------------------
-- donations has no existing policy granting center admins read access at
-- all (only Super Admin reads it today, in donations_page.dart). The
-- Center Admin dashboard needs this to total up specific/random donations
-- sent directly to its own clinic_id. Mirrors the existing
-- "Center admins can view their own allocations" policy pattern already
-- used on donation_allocations.

drop policy if exists "Center admins can view their own center's donations" on public.donations;
create policy "Center admins can view their own center's donations"
  on public.donations
  for select
  to authenticated
  using (
    clinic_id in (
      select clinic_id from public.profiles where id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
-- 2. Super Admin can read donation_allocations
-- ---------------------------------------------------------------------

drop policy if exists "Superadmins can view all allocations" on public.donation_allocations;
create policy "Superadmins can view all allocations"
  on public.donation_allocations
  for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'superadmin'
    )
  );

-- ---------------------------------------------------------------------
-- 3. donation_audit_logs (append-only)
-- ---------------------------------------------------------------------

create table if not exists public.donation_audit_logs (
  id uuid primary key default gen_random_uuid(),
  donation_id uuid not null references public.donations(id) on delete cascade,
  allocation_id uuid references public.donation_allocations(id) on delete set null,
  clinic_id uuid references public.clinics(id),
  action text not null,
  amount numeric(12, 2),
  from_entity text,
  to_entity text,
  performed_by uuid references auth.users(id),
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index if not exists donation_audit_logs_donation_id_idx
  on public.donation_audit_logs (donation_id);

create index if not exists donation_audit_logs_clinic_id_idx
  on public.donation_audit_logs (clinic_id);

alter table public.donation_audit_logs enable row level security;

-- No insert/update/delete policy is granted to anon/authenticated on
-- purpose -- writes only happen via the SECURITY DEFINER functions below.

drop policy if exists "Superadmins can view all audit logs" on public.donation_audit_logs;
create policy "Superadmins can view all audit logs"
  on public.donation_audit_logs
  for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'superadmin'
    )
  );

drop policy if exists "Center admins can view their own audit logs" on public.donation_audit_logs;
create policy "Center admins can view their own audit logs"
  on public.donation_audit_logs
  for select
  to authenticated
  using (
    clinic_id in (
      select clinic_id from public.profiles where id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
-- 4. Automatic audit triggers
-- ---------------------------------------------------------------------

create or replace function public.log_donation_received()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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

drop trigger if exists donations_log_received on public.donations;
create trigger donations_log_received
  after insert on public.donations
  for each row execute function public.log_donation_received();

create or replace function public.log_donation_allocated()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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

drop trigger if exists donation_allocations_log_allocated on public.donation_allocations;
create trigger donation_allocations_log_allocated
  after insert on public.donation_allocations
  for each row execute function public.log_donation_allocated();

-- ---------------------------------------------------------------------
-- 5. approve_donation / reject_donation RPCs
-- ---------------------------------------------------------------------

create or replace function public.approve_donation(p_donation_id uuid)
returns public.donations
language plpgsql
security definer
set search_path = public
as $$
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

create or replace function public.reject_donation(p_donation_id uuid)
returns public.donations
language plpgsql
security definer
set search_path = public
as $$
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

grant execute on function public.approve_donation(uuid) to authenticated;
grant execute on function public.reject_donation(uuid) to authenticated;
