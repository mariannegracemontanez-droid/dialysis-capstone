-- Feature 5: GCash donation sandbox (demo mode) with server-side checkout.
--
-- Run this ONCE in the Supabase SQL Editor, AFTER
--   1. supabase_migration_donation_allocations.sql
--   2. supabase_migration_donation_confirmation.sql
-- have been applied. It is safe to re-run (every statement is idempotent).
--
-- WHAT THIS DOES
--
-- Until now the Donation app inserted rows straight into `donations` with
-- status 'verified' (and its equal-distribution shares straight into
-- `donation_allocations`), from the browser, with no payment at all. Anyone
-- holding the public anon key could therefore create a "verified" donation.
-- This migration moves the whole donation workflow server-side:
--
--   * create_donation_checkout()   validates the amount and mode, checks
--                                  centre eligibility, picks the random
--                                  centre, splits "Donate to All" in integer
--                                  centavos and saves a recipient snapshot --
--                                  all inside the database.
--   * simulate_donation_payment()  the clearly-labelled internal demo
--                                  simulator. Works ONLY while the server
--                                  setting says sandbox + simulator enabled.
--   * paymongo_* functions         callable only by the PayMongo Edge
--                                  Functions (service role), never by a
--                                  browser.
--
-- SANDBOX ISOLATION -- why sandbox rows can never be counted as real money
--
-- Every money total in all three apps (landing page, Super Admin dashboard
-- and donations page, Center Admin dashboard) counts ONLY
-- donations.status = 'verified'. A check constraint below makes it
-- impossible for a row with payment_environment = 'sandbox' to ever hold
-- status 'verified', so sandbox rows are excluded from every existing total
-- at the database level, without touching those queries.
--
-- Status mapping for rows created by this workflow:
--   payment_status   pending | processing | paid | simulated_paid | failed | cancelled
--   donations.status pending (awaiting / sandbox-settled) | rejected (failed / cancelled)
--                    'verified' only for a provider-confirmed PRODUCTION payment.
--
-- NOTHING IS DELETED. No table, column, bank-account data, or existing
-- donation row is dropped or rewritten. What IS removed (section 12):
--   * RLS policies that let anon / authenticated / public INSERT, UPDATE or
--     DELETE donations or donation_allocations (e.g. "Allow update
--     donations", "Allow donation allocation inserts"), and
--   * the INSERT/UPDATE/DELETE/TRUNCATE table grants those API roles hold on
--     the donation tables.
-- SELECT policies and grants are kept, so the landing page and the
-- dashboards read exactly as before. No app writes these tables directly
-- any more; all writes go through the functions below.

-- =====================================================================
-- 1. Server-side payment settings (single row)
-- =====================================================================

create table if not exists public.donation_payment_settings (
  id boolean primary key default true check (id),
  environment text not null default 'sandbox'
    check (environment in ('sandbox', 'production')),
  -- Internal demo simulator (no external provider involved).
  simulator_enabled boolean not null default true,
  -- PayMongo TEST-mode checkout. Flip to true only after the Edge Function
  -- secrets are set (see DONATION_SANDBOX_GUIDE.md).
  paymongo_test_enabled boolean not null default false,
  min_amount_centavos bigint not null default 2000,       -- PHP 20.00
  max_amount_centavos bigint not null default 10000000,   -- PHP 100,000.00
  updated_at timestamptz not null default now(),
  -- The simulator and PayMongo test mode are sandbox-only features.
  constraint donation_payment_settings_sandbox_only check (
    environment = 'sandbox'
    or (not simulator_enabled and not paymongo_test_enabled)
  ),
  constraint donation_payment_settings_limits check (
    min_amount_centavos > 0 and max_amount_centavos >= min_amount_centavos
  )
);

insert into public.donation_payment_settings (id) values (true)
on conflict (id) do nothing;

alter table public.donation_payment_settings enable row level security;

-- Nothing secret lives here; the donor page reads it to show the demo
-- banner and amount limits. No write policy: change it from the SQL Editor.
drop policy if exists "Anyone can read donation payment settings"
  on public.donation_payment_settings;
create policy "Anyone can read donation payment settings"
  on public.donation_payment_settings
  for select
  to anon, authenticated
  using (true);

-- =====================================================================
-- 2. Extend donations (parent transaction)
-- =====================================================================

do $$
begin
  -- payment_page.dart (unused) once wrote a payment_status column. If such
  -- a column already exists with a non-text type, stop instead of guessing.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'donations'
      and column_name = 'payment_status' and data_type <> 'text'
  ) then
    raise exception
      'donations.payment_status already exists with a non-text type; review it before running this migration.';
  end if;
end;
$$;

alter table public.donations
  add column if not exists amount_centavos bigint,
  add column if not exists currency text,
  add column if not exists payment_provider text,
  add column if not exists payment_environment text,
  add column if not exists payment_status text,
  add column if not exists status_reason text,
  add column if not exists reference_code text,
  add column if not exists provider_checkout_id text,
  add column if not exists provider_checkout_url text,
  add column if not exists provider_payment_id text,
  add column if not exists payment_confirmed_at timestamptz,
  add column if not exists updated_at timestamptz,
  add column if not exists idempotency_key text,
  add column if not exists client_secret_hash text;

-- NOT VALID: enforced for every new/updated row, without re-checking
-- historical rows written before these columns existed.
alter table public.donations drop constraint if exists donations_payment_environment_check;
alter table public.donations add constraint donations_payment_environment_check
  check (payment_environment is null or payment_environment in ('sandbox', 'production')) not valid;

alter table public.donations drop constraint if exists donations_payment_status_check;
alter table public.donations add constraint donations_payment_status_check
  check (payment_status is null or payment_status in (
    'pending', 'processing', 'paid', 'simulated_paid', 'failed', 'cancelled'
  )) not valid;

alter table public.donations drop constraint if exists donations_payment_provider_check;
alter table public.donations add constraint donations_payment_provider_check
  check (payment_provider is null or payment_provider in ('internal_simulator', 'paymongo')) not valid;

-- THE key isolation rule: a sandbox donation can never be 'verified', so it
-- can never enter any "collected funds" total.
alter table public.donations drop constraint if exists donations_sandbox_never_verified;
alter table public.donations add constraint donations_sandbox_never_verified
  check (payment_environment is distinct from 'sandbox' or status is distinct from 'verified') not valid;

alter table public.donations drop constraint if exists donations_simulated_is_sandbox;
alter table public.donations add constraint donations_simulated_is_sandbox
  check (
    (payment_status is distinct from 'simulated_paid' and payment_provider is distinct from 'internal_simulator')
    or payment_environment = 'sandbox'
  ) not valid;

alter table public.donations drop constraint if exists donations_amount_centavos_check;
alter table public.donations add constraint donations_amount_centavos_check
  check (amount_centavos is null or (amount_centavos > 0 and amount = amount_centavos / 100.0)) not valid;

create unique index if not exists donations_idempotency_key_uidx
  on public.donations (idempotency_key) where idempotency_key is not null;
create unique index if not exists donations_reference_code_uidx
  on public.donations (reference_code) where reference_code is not null;
create unique index if not exists donations_provider_checkout_id_uidx
  on public.donations (provider_checkout_id) where provider_checkout_id is not null;
create index if not exists donations_payment_environment_idx
  on public.donations (payment_environment, created_at desc);

-- =====================================================================
-- 3. Extend donation_allocations (child rows)
-- =====================================================================
--
-- Rows created by the new workflow exist for ALL three modes (one row for
-- specific/random, one per centre for Donate to All) and carry their own
-- amount_centavos, a name snapshot and an allocation_status. Legacy rows
-- (amount_centavos null) are untouched.
--
-- Specific/random donations ALSO keep donations.clinic_id set, exactly as
-- before, so the Center Admin's existing read policy keeps working. Code
-- that sums allocation rows therefore skips rows whose parent has a
-- clinic_id (updated in admin_panel and super_admin_app alongside this
-- migration) so a single-centre donation is never counted twice.

alter table public.donation_allocations
  add column if not exists amount_centavos bigint,
  add column if not exists clinic_name_snapshot text,
  add column if not exists allocation_status text,
  add column if not exists provider_transfer_ref text,
  add column if not exists sort_order integer,
  add column if not exists updated_at timestamptz;

alter table public.donation_allocations drop constraint if exists donation_allocations_status_check;
alter table public.donation_allocations add constraint donation_allocations_status_check
  check (allocation_status is null or allocation_status in (
    'awaiting_payment',  -- parent not yet paid
    'simulated',         -- sandbox: intended share of a simulated/test payment. NO funds moved.
    'pending_payout',    -- production: paid, real payout not yet made
    'paid_out',          -- production: payout confirmed by a provider integration
    'void'               -- parent failed or was cancelled
  )) not valid;

-- "paid_out" may only exist with a provider transfer reference.
alter table public.donation_allocations drop constraint if exists donation_allocations_paid_out_ref;
alter table public.donation_allocations add constraint donation_allocations_paid_out_ref
  check (allocation_status is distinct from 'paid_out' or provider_transfer_ref is not null) not valid;

alter table public.donation_allocations drop constraint if exists donation_allocations_amount_centavos_check;
alter table public.donation_allocations add constraint donation_allocations_amount_centavos_check
  check (amount_centavos is null or (amount_centavos > 0 and amount = amount_centavos / 100.0)) not valid;

create unique index if not exists donation_allocations_donation_clinic_uidx
  on public.donation_allocations (donation_id, clinic_id)
  where amount_centavos is not null;

-- Allocations of a new-workflow donation must add up EXACTLY to the parent
-- amount. Checked at commit time (deferred), so a whole set can be inserted.
create or replace function public.check_donation_allocation_total()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_total bigint;
  v_sum bigint;
  v_donation_id uuid := coalesce(new.donation_id, old.donation_id);
begin
  select amount_centavos into v_parent_total
  from public.donations where id = v_donation_id;

  if v_parent_total is null then
    return null; -- legacy donation, not part of this workflow
  end if;

  select coalesce(sum(amount_centavos), 0) into v_sum
  from public.donation_allocations where donation_id = v_donation_id;

  if v_sum <> v_parent_total then
    raise exception 'ALLOCATION_TOTAL_MISMATCH: allocations (% centavos) do not equal donation total (% centavos)',
      v_sum, v_parent_total;
  end if;

  return null;
end;
$$;

drop trigger if exists donation_allocations_total_check on public.donation_allocations;
create constraint trigger donation_allocations_total_check
  after insert or update or delete on public.donation_allocations
  deferrable initially deferred
  for each row execute function public.check_donation_allocation_total();

-- =====================================================================
-- 4. Provider webhook events (duplicate-delivery protection)
-- =====================================================================

create table if not exists public.payment_provider_events (
  provider text not null,
  event_id text not null,
  event_type text,
  donation_id uuid references public.donations(id) on delete set null,
  livemode boolean,
  result text,
  received_at timestamptz not null default now(),
  primary key (provider, event_id)
);

alter table public.payment_provider_events enable row level security;

drop policy if exists "Superadmins can view provider events" on public.payment_provider_events;
create policy "Superadmins can view provider events"
  on public.payment_provider_events
  for select
  to authenticated
  using (exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'superadmin'
  ));

-- =====================================================================
-- 5. Write guards: the API cannot write donation tables at all
-- =====================================================================
--
-- No app writes donations or donation_allocations directly any more (the
-- donor site uses create_donation_checkout(); payment_page.dart and
-- DonationService.createDonation are unused; nothing updates or deletes
-- donations). So every direct INSERT / UPDATE / DELETE that arrives through
-- the Supabase API is refused here, whatever RLS policies or grants exist --
-- including a superadmin signed in to a dashboard, and including permissive
-- legacy policies such as "Allow update donations ... using (true)".
--
-- "API role" = anon, authenticated, or any other role the API gateway
-- (`authenticator`) can switch into, e.g. a custom JWT role -- except
-- service_role (server-side only; Edge Functions use it).
--
-- Not affected: the SECURITY DEFINER functions in this migration and in
-- supabase_migration_donation_confirmation.sql (they run as their owner),
-- the SQL Editor, and service_role.

create or replace function public.donation_is_api_role()
returns boolean
language sql
stable
set search_path = public
as $$
  select current_user in ('anon', 'authenticated')
    or (
      current_user <> 'service_role'
      and to_regrole('authenticator') is not null
      and pg_has_role('authenticator', current_user, 'MEMBER')
    );
$$;

create or replace function public.guard_donation_payment_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.donation_is_api_role() then
    raise exception 'DIRECT_WRITE_BLOCKED: donations can only be written by the server (% via API refused).', tg_op;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists donations_guard_payment_columns on public.donations;
create trigger donations_guard_payment_columns
  before insert or update or delete on public.donations
  for each row execute function public.guard_donation_payment_columns();

create or replace function public.guard_donation_allocation_rows()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.donation_is_api_role() then
    raise exception 'DIRECT_WRITE_BLOCKED: donation allocations can only be written by the server (% via API refused).', tg_op;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists donation_allocations_guard_rows on public.donation_allocations;
create trigger donation_allocations_guard_rows
  before insert or update or delete on public.donation_allocations
  for each row execute function public.guard_donation_allocation_rows();

-- TRUNCATE skips row triggers; block it too (the grant is also revoked in
-- section 12).
create or replace function public.guard_donation_truncate()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.donation_is_api_role() then
    raise exception 'DIRECT_WRITE_BLOCKED: TRUNCATE via API refused.';
  end if;
  return null;
end;
$$;

drop trigger if exists donations_guard_truncate on public.donations;
create trigger donations_guard_truncate
  before truncate on public.donations
  for each statement execute function public.guard_donation_truncate();

drop trigger if exists donation_allocations_guard_truncate on public.donation_allocations;
create trigger donation_allocations_guard_truncate
  before truncate on public.donation_allocations
  for each statement execute function public.guard_donation_truncate();

-- =====================================================================
-- 6. Audit triggers: label workflow rows by environment
-- =====================================================================
-- Same functions as supabase_migration_donation_confirmation.sql; legacy
-- rows (payment_environment null) are logged exactly as before.

create or replace function public.log_donation_received()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.payment_environment is not null then
    insert into public.donation_audit_logs (
      donation_id, clinic_id, action, amount, from_entity, to_entity, metadata
    ) values (
      new.id, new.clinic_id, 'CHECKOUT_CREATED', new.amount, 'donor', 'donation_system',
      jsonb_build_object(
        'allocation_type', new.allocation_type,
        'payment_environment', new.payment_environment,
        'payment_provider', new.payment_provider
      )
    );
    -- Per-centre rows are logged by log_donation_allocated.
    return new;
  end if;

  insert into public.donation_audit_logs (
    donation_id, clinic_id, action, amount, from_entity, to_entity, metadata
  ) values (
    new.id, new.clinic_id, 'DONATION_RECEIVED', new.amount, 'donor', 'donation_system',
    jsonb_build_object('allocation_type', new.allocation_type)
  );

  if new.clinic_id is not null then
    insert into public.donation_audit_logs (
      donation_id, clinic_id, action, amount, from_entity, to_entity, metadata
    ) values (
      new.id, new.clinic_id, 'DONATION_ALLOCATED', new.amount, 'donation_system',
      new.clinic_id::text, jsonb_build_object('allocation_type', new.allocation_type)
    );
  end if;

  return new;
end;
$$;

create or replace function public.log_donation_allocated()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent public.donations;
begin
  select * into v_parent from public.donations where id = new.donation_id;

  insert into public.donation_audit_logs (
    donation_id, allocation_id, clinic_id, action, amount, from_entity, to_entity, metadata
  ) values (
    new.donation_id,
    new.id,
    new.clinic_id,
    case when v_parent.payment_environment is not null
      then 'ALLOCATION_PLANNED' else 'DONATION_ALLOCATED' end,
    new.amount,
    'donation_system',
    new.clinic_id::text,
    jsonb_build_object(
      'allocation_type', coalesce(v_parent.allocation_type, 'equal_distribution'),
      'payment_environment', v_parent.payment_environment
    )
  );

  return new;
end;
$$;

-- =====================================================================
-- 7. Eligibility and allocation helpers
-- =====================================================================

-- The EXISTING recipient rule, unchanged: every centre whose clinics.status
-- is not 'closed' (the same filter the Donation app has always used).
-- Clinics carry no payout/bank-account columns, so there is no account
-- detail to verify; hiding Bank Transfer does not change who is eligible.
create or replace function public.donation_eligible_centers()
returns table (id uuid, name text, address text, city text)
language sql
stable
set search_path = public
as $$
  select c.id, c.name::text, c.address::text, c.city::text
  from public.clinics c
  where c.status is null or c.status <> 'closed'
  order by c.name asc, c.id asc;
$$;

-- Splits p_total centavos into p_count integer shares. The first
-- (p_total % p_count) shares get one extra centavo, in the order the
-- centres are listed (name, then id), so the result is deterministic and
-- always sums exactly to p_total. Mirrored in Dart by
-- splitCentavosEqually() for the donor-side preview.
create or replace function public.donation_equal_split(p_total bigint, p_count integer)
returns bigint[]
language plpgsql
immutable
as $$
declare
  v_base bigint;
  v_remainder bigint;
  v_result bigint[] := '{}';
begin
  if p_count is null or p_count <= 0 then
    raise exception 'NO_ELIGIBLE_CENTERS: there are no eligible centres to allocate to.';
  end if;
  if p_total is null or p_total <= 0 then
    raise exception 'INVALID_AMOUNT: amount must be positive.';
  end if;
  if p_total < p_count then
    raise exception 'AMOUNT_TOO_SMALL_TO_SPLIT: each centre must receive at least one centavo.';
  end if;

  v_base := p_total / p_count;
  v_remainder := p_total % p_count;

  for i in 1..p_count loop
    v_result := v_result || (v_base + case when i <= v_remainder then 1 else 0 end);
  end loop;

  return v_result;
end;
$$;

create or replace function public.donation_secret_hash(p_secret text)
returns text
language sql
immutable
as $$
  select encode(sha256(convert_to(p_secret, 'UTF8')), 'hex');
$$;

-- The donor-facing view of one checkout (no donor PII, no secret hash).
create or replace function public.donation_checkout_json(p_donation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'donation_id', d.id,
    'reference', d.reference_code,
    'mode', d.allocation_type,
    'amount_centavos', d.amount_centavos,
    'currency', d.currency,
    'payment_method', d.payment_method,
    'payment_provider', d.payment_provider,
    'payment_environment', d.payment_environment,
    'payment_status', d.payment_status,
    'status_reason', d.status_reason,
    'checkout_url', d.provider_checkout_url,
    'created_at', d.created_at,
    'payment_confirmed_at', d.payment_confirmed_at,
    'allocations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'clinic_id', a.clinic_id,
        'clinic_name', a.clinic_name_snapshot,
        'amount_centavos', a.amount_centavos,
        'allocation_status', a.allocation_status
      ) order by a.sort_order)
      from public.donation_allocations a
      where a.donation_id = d.id
    ), '[]'::jsonb)
  )
  from public.donations d
  where d.id = p_donation_id;
$$;

-- Loads and row-locks a workflow donation after checking the caller holds
-- its client secret (the secret is generated in the donor's browser; only
-- its SHA-256 is stored). Works for anonymous and registered donors alike.
create or replace function public.donation_lock_owned(p_donation_id uuid, p_client_secret text)
returns public.donations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_donation public.donations;
begin
  select * into v_donation from public.donations
  where id = p_donation_id and payment_environment is not null
  for update;

  if not found or p_client_secret is null
     or v_donation.client_secret_hash is distinct from public.donation_secret_hash(p_client_secret) then
    raise exception 'DONATION_NOT_FOUND: this donation does not exist or does not belong to you.';
  end if;

  return v_donation;
end;
$$;

-- Moves a workflow donation to a final state and updates its allocations.
create or replace function public.donation_finalize(
  p_donation_id uuid,
  p_payment_status text,
  p_reason text,
  p_actor text,
  p_provider_payment_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_donation public.donations;
  v_alloc_status text;
  v_status text;
begin
  select * into v_donation from public.donations where id = p_donation_id for update;

  if p_payment_status in ('failed', 'cancelled') then
    v_status := 'rejected';
    v_alloc_status := 'void';
  elsif p_payment_status = 'simulated_paid' then
    v_status := 'pending';             -- never 'verified' in sandbox
    v_alloc_status := 'simulated';
  elsif p_payment_status = 'paid' then
    if v_donation.payment_environment = 'production' then
      v_status := 'verified';
      v_alloc_status := 'pending_payout';
    else
      v_status := 'pending';           -- PayMongo TEST payment: no real money
      v_alloc_status := 'simulated';
    end if;
  else
    raise exception 'INVALID_STATUS: %', p_payment_status;
  end if;

  update public.donations set
    payment_status = p_payment_status,
    status = v_status,
    status_reason = p_reason,
    provider_payment_id = coalesce(p_provider_payment_id, provider_payment_id),
    payment_confirmed_at = case when p_payment_status in ('paid', 'simulated_paid') then now() else payment_confirmed_at end,
    updated_at = now()
  where id = p_donation_id;

  update public.donation_allocations set
    allocation_status = v_alloc_status,
    updated_at = now()
  where donation_id = p_donation_id;

  insert into public.donation_audit_logs (
    donation_id, action, amount, from_entity, to_entity, performed_by, metadata
  ) values (
    p_donation_id,
    'PAYMENT_' || upper(p_payment_status),
    v_donation.amount,
    p_actor,
    'donation_system',
    auth.uid(),
    jsonb_build_object(
      'payment_environment', v_donation.payment_environment,
      'payment_provider', v_donation.payment_provider,
      'reason', p_reason
    )
  );
end;
$$;

-- =====================================================================
-- 8. Donor-facing RPCs
-- =====================================================================

-- Creates the pending donation + its allocation snapshot. All decisions --
-- eligibility, random pick, equal split, environment and provider -- are
-- made here, never by the client.
--
-- p_mode            'specific_center' | 'random_center' | 'equal_distribution'
-- p_clinic_id       required for specific_center, must be NULL otherwise
-- p_idempotency_key random per donation attempt; a retry with the same key
--                   returns the same donation instead of creating another
-- p_client_secret   random secret from the donor's browser; required to view
--                   or settle this donation later (only its hash is stored)
-- p_anonymous       true: no account details are recorded even if signed in
create or replace function public.create_donation_checkout(
  p_mode text,
  p_amount_centavos bigint,
  p_clinic_id uuid,
  p_idempotency_key text,
  p_client_secret text,
  p_anonymous boolean,
  p_donor_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.donation_payment_settings;
  v_uid uuid := auth.uid();
  v_existing public.donations;
  v_donation_id uuid := gen_random_uuid();
  v_ids uuid[];
  v_names text[];
  v_shares bigint[];
  v_provider text;
  v_donor_id uuid;
  v_name text;
  v_email text;
begin
  select * into v_settings from public.donation_payment_settings where id;

  if v_settings.environment is distinct from 'sandbox' then
    -- No live payment integration exists. Refuse instead of recording an
    -- unpaid donation as if it were real.
    raise exception 'PAYMENTS_UNAVAILABLE: live payments are not enabled.';
  end if;

  if v_settings.paymongo_test_enabled then
    v_provider := 'paymongo';
  elsif v_settings.simulator_enabled then
    v_provider := 'internal_simulator';
  else
    raise exception 'PAYMENTS_UNAVAILABLE: no sandbox payment method is enabled.';
  end if;

  if p_idempotency_key is null or length(p_idempotency_key) not between 16 and 100
     or p_client_secret is null or length(p_client_secret) < 32 then
    raise exception 'INVALID_REQUEST: missing request identifiers.';
  end if;

  -- Duplicate submission: hand back the donation already created.
  select * into v_existing from public.donations where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.client_secret_hash is distinct from public.donation_secret_hash(p_client_secret) then
      raise exception 'INVALID_REQUEST: idempotency key already used.';
    end if;
    return public.donation_checkout_json(v_existing.id);
  end if;

  if p_amount_centavos is null
     or p_amount_centavos < v_settings.min_amount_centavos
     or p_amount_centavos > v_settings.max_amount_centavos then
    raise exception 'INVALID_AMOUNT: amount must be between % and % centavos.',
      v_settings.min_amount_centavos, v_settings.max_amount_centavos;
  end if;

  -- Recipients.
  if p_mode = 'specific_center' then
    if p_clinic_id is null then
      raise exception 'INVALID_REQUEST: choose a centre.';
    end if;
    select array_agg(e.id), array_agg(e.name) into v_ids, v_names
    from public.donation_eligible_centers() e where e.id = p_clinic_id;
    if v_ids is null then
      raise exception 'CENTER_NOT_ELIGIBLE: the selected centre is not currently accepting donations.';
    end if;
  elsif p_mode = 'random_center' then
    if p_clinic_id is not null then
      raise exception 'INVALID_REQUEST: the random centre is chosen by the server.';
    end if;
    select array[e.id], array[e.name] into v_ids, v_names
    from public.donation_eligible_centers() e order by random() limit 1;
    if v_ids is null then
      raise exception 'NO_ELIGIBLE_CENTERS: no centres are currently accepting donations.';
    end if;
  elsif p_mode = 'equal_distribution' then
    if p_clinic_id is not null then
      raise exception 'INVALID_REQUEST: Donate to All does not take a centre.';
    end if;
    select array_agg(e.id order by e.name, e.id), array_agg(e.name order by e.name, e.id)
      into v_ids, v_names
    from public.donation_eligible_centers() e;
    if v_ids is null then
      raise exception 'NO_ELIGIBLE_CENTERS: no centres are currently accepting donations.';
    end if;
  else
    raise exception 'INVALID_REQUEST: unknown donation mode.';
  end if;

  v_shares := public.donation_equal_split(p_amount_centavos, cardinality(v_ids));

  -- Donor. Anonymous records nothing about the account, even if signed in
  -- (same rule as the original donation page).
  if coalesce(p_anonymous, false) then
    v_donor_id := null; v_name := null; v_email := null;
  else
    if v_uid is null then
      raise exception 'LOGIN_REQUIRED: sign in to donate with your account.';
    end if;
    v_donor_id := v_uid;
    select u.email into v_email from auth.users u where u.id = v_uid;
    select nullif(trim(p.full_name), '') into v_name from public.profiles p where p.id = v_uid;
    v_name := left(coalesce(nullif(trim(p_donor_name), ''), v_name, v_email, 'Registered Donor'), 200);
  end if;

  begin
    insert into public.donations (
      id, donor_id, name, email, amount, amount_centavos, currency,
      payment_method, payment_provider, payment_environment, payment_status,
      status, clinic_id, allocation_type, reference_code,
      idempotency_key, client_secret_hash, updated_at
    ) values (
      v_donation_id, v_donor_id, v_name, v_email,
      round(p_amount_centavos / 100.0, 2), p_amount_centavos, 'PHP',
      'GCASH', v_provider, 'sandbox', 'pending',
      'pending',
      case when p_mode = 'equal_distribution' then null else v_ids[1] end,
      p_mode,
      'CN-SBX-' || upper(substr(replace(v_donation_id::text, '-', ''), 1, 10)),
      p_idempotency_key, public.donation_secret_hash(p_client_secret), now()
    );
  exception when unique_violation then
    -- A concurrent retry with the same key won the race.
    select * into v_existing from public.donations where idempotency_key = p_idempotency_key;
    if found and v_existing.client_secret_hash = public.donation_secret_hash(p_client_secret) then
      return public.donation_checkout_json(v_existing.id);
    end if;
    raise;
  end;

  insert into public.donation_allocations (
    donation_id, clinic_id, amount, amount_centavos, clinic_name_snapshot,
    allocation_status, sort_order, updated_at
  )
  select v_donation_id, v_ids[g.i], round(v_shares[g.i] / 100.0, 2), v_shares[g.i], v_names[g.i],
         'awaiting_payment', g.i, now()
  from generate_subscripts(v_ids, 1) as g(i);

  return public.donation_checkout_json(v_donation_id);
end;
$$;

-- Reloads a checkout (e.g. after a page refresh). The recipient(s) always
-- come from the stored snapshot, so a refresh can never change them.
create or replace function public.get_donation_checkout(p_donation_id uuid, p_client_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_donation public.donations;
begin
  select * into v_donation from public.donations
  where id = p_donation_id and payment_environment is not null;

  if not found
     or v_donation.client_secret_hash is distinct from public.donation_secret_hash(p_client_secret) then
    raise exception 'DONATION_NOT_FOUND: this donation does not exist or does not belong to you.';
  end if;

  return public.donation_checkout_json(p_donation_id);
end;
$$;

-- Donor abandons a checkout that has not been paid (any provider).
create or replace function public.cancel_donation_checkout(p_donation_id uuid, p_client_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_donation public.donations;
begin
  v_donation := public.donation_lock_owned(p_donation_id, p_client_secret);

  if v_donation.payment_status = 'cancelled' then
    return public.donation_checkout_json(p_donation_id);
  end if;
  if v_donation.payment_status not in ('pending', 'processing') then
    raise exception 'ALREADY_FINALIZED: this donation is already %.', v_donation.payment_status;
  end if;

  perform public.donation_finalize(p_donation_id, 'cancelled', 'Cancelled by donor', 'donor');
  return public.donation_checkout_json(p_donation_id);
end;
$$;

-- INTERNAL DEMO SIMULATOR. Only for sandbox donations created with the
-- 'internal_simulator' provider, and only while the server setting allows
-- it. A simulated success is recorded as payment_status 'simulated_paid' --
-- never 'paid', never 'verified' -- and its allocations as 'simulated'.
create or replace function public.simulate_donation_payment(
  p_donation_id uuid,
  p_client_secret text,
  p_outcome text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.donation_payment_settings;
  v_donation public.donations;
  v_target text;
  v_ineligible text;
begin
  select * into v_settings from public.donation_payment_settings where id;
  if v_settings.environment is distinct from 'sandbox' or not v_settings.simulator_enabled then
    raise exception 'SIMULATOR_DISABLED: the demo simulator is not enabled.';
  end if;

  v_target := case p_outcome
    when 'success' then 'simulated_paid'
    when 'failure' then 'failed'
    when 'cancel' then 'cancelled'
  end;
  if v_target is null then
    raise exception 'INVALID_REQUEST: outcome must be success, failure or cancel.';
  end if;

  v_donation := public.donation_lock_owned(p_donation_id, p_client_secret);

  if v_donation.payment_environment <> 'sandbox' or v_donation.payment_provider <> 'internal_simulator' then
    raise exception 'SIMULATOR_DISABLED: this donation is not a simulator transaction.';
  end if;

  -- Idempotent: repeating the same action is a no-op.
  if v_donation.payment_status = v_target then
    return public.donation_checkout_json(p_donation_id);
  end if;
  if v_donation.payment_status not in ('pending', 'processing') then
    raise exception 'ALREADY_FINALIZED: this donation is already %.', v_donation.payment_status;
  end if;

  if v_target = 'simulated_paid' then
    -- A recipient that stopped being eligible after checkout started: do not
    -- complete; the donor starts a new donation against current centres.
    select string_agg(a.clinic_name_snapshot, ', ') into v_ineligible
    from public.donation_allocations a
    where a.donation_id = p_donation_id
      and not exists (select 1 from public.donation_eligible_centers() e where e.id = a.clinic_id);

    if v_ineligible is not null then
      perform public.donation_finalize(
        p_donation_id, 'cancelled',
        'Recipient no longer eligible: ' || v_ineligible, 'donation_system');
      return public.donation_checkout_json(p_donation_id);
    end if;

    perform public.donation_finalize(p_donation_id, 'simulated_paid', 'Demo simulator: success', 'demo_simulator');
  elsif v_target = 'failed' then
    perform public.donation_finalize(p_donation_id, 'failed', 'Demo simulator: payment failed', 'demo_simulator');
  else
    perform public.donation_finalize(p_donation_id, 'cancelled', 'Demo simulator: cancelled', 'demo_simulator');
  end if;

  return public.donation_checkout_json(p_donation_id);
end;
$$;

-- =====================================================================
-- 9. PayMongo (service role only -- called by Edge Functions)
-- =====================================================================

create or replace function public.paymongo_attach_checkout(
  p_donation_id uuid,
  p_checkout_id text,
  p_checkout_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_donation public.donations;
begin
  select * into v_donation from public.donations where id = p_donation_id for update;

  if not found or v_donation.payment_provider is distinct from 'paymongo' then
    raise exception 'DONATION_NOT_FOUND: not a PayMongo donation.';
  end if;
  if v_donation.provider_checkout_id is not null then
    return public.donation_checkout_json(p_donation_id); -- keep the first session
  end if;
  if v_donation.payment_status <> 'pending' then
    raise exception 'ALREADY_FINALIZED: this donation is already %.', v_donation.payment_status;
  end if;

  update public.donations set
    provider_checkout_id = p_checkout_id,
    provider_checkout_url = p_checkout_url,
    payment_status = 'processing',
    updated_at = now()
  where id = p_donation_id;

  return public.donation_checkout_json(p_donation_id);
end;
$$;

-- Records a provider-verified payment. The Edge Function calls this only
-- after (1) verifying the webhook signature and (2) re-fetching the
-- checkout session from PayMongo with the secret key and seeing it paid.
-- Duplicate deliveries of the same event are ignored.
create or replace function public.paymongo_record_payment(
  p_event_id text,
  p_event_type text,
  p_checkout_id text,
  p_payment_id text,
  p_livemode boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_donation public.donations;
  v_ineligible text;
begin
  insert into public.payment_provider_events (provider, event_id, event_type, livemode)
  values ('paymongo', p_event_id, p_event_type, p_livemode)
  on conflict do nothing;
  if not found then
    return 'duplicate';
  end if;

  select * into v_donation from public.donations
  where provider_checkout_id = p_checkout_id for update;

  if not found then
    update public.payment_provider_events set result = 'unknown_checkout'
    where provider = 'paymongo' and event_id = p_event_id;
    return 'unknown_checkout';
  end if;

  update public.payment_provider_events set donation_id = v_donation.id
  where provider = 'paymongo' and event_id = p_event_id;

  -- Environment isolation: live events are never applied to sandbox rows.
  if p_livemode is distinct from false or v_donation.payment_environment <> 'sandbox' then
    update public.payment_provider_events set result = 'rejected_environment'
    where provider = 'paymongo' and event_id = p_event_id;
    return 'rejected_environment';
  end if;

  if v_donation.payment_status = 'paid' then
    update public.payment_provider_events set result = 'already_paid'
    where provider = 'paymongo' and event_id = p_event_id;
    return 'already_paid';
  end if;

  -- The provider says money (test money) was captured: record it even if
  -- the donor pressed cancel locally, and flag recipients that became
  -- ineligible meanwhile for Super Admin follow-up.
  select string_agg(a.clinic_name_snapshot, ', ') into v_ineligible
  from public.donation_allocations a
  where a.donation_id = v_donation.id
    and not exists (select 1 from public.donation_eligible_centers() e where e.id = a.clinic_id);

  perform public.donation_finalize(
    v_donation.id, 'paid',
    case when v_ineligible is null then 'PayMongo test payment confirmed'
         else 'PayMongo test payment confirmed; recipient no longer eligible: ' || v_ineligible end,
    'paymongo', p_payment_id);

  update public.payment_provider_events set result = 'applied'
  where provider = 'paymongo' and event_id = p_event_id;
  return 'applied';
end;
$$;

-- Lets the create-checkout Edge Function verify the donor's secret.
create or replace function public.paymongo_get_owned_donation(p_donation_id uuid, p_client_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_donation public.donations;
begin
  v_donation := public.donation_lock_owned(p_donation_id, p_client_secret);
  return jsonb_build_object(
    'donation_id', v_donation.id,
    'reference', v_donation.reference_code,
    'amount_centavos', v_donation.amount_centavos,
    'payment_provider', v_donation.payment_provider,
    'payment_environment', v_donation.payment_environment,
    'payment_status', v_donation.payment_status,
    'checkout_url', v_donation.provider_checkout_url
  );
end;
$$;

-- =====================================================================
-- 10. Superadmin approval cannot settle workflow donations
-- =====================================================================
-- approve_donation / reject_donation are the manual review RPCs from
-- supabase_migration_donation_confirmation.sql. Workflow donations are
-- settled only by the payment workflow, so both now refuse them. (The
-- donations_sandbox_never_verified constraint would block approval of a
-- sandbox row anyway; this gives a clear message and also blocks reject.)

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

  select * into v_donation from public.donations where id = p_donation_id for update;

  if not found then
    raise exception 'Donation % was not found.', p_donation_id;
  end if;

  if v_donation.payment_environment is not null then
    raise exception 'Donation % is settled by the payment workflow and cannot be approved manually.', p_donation_id;
  end if;

  if v_donation.status <> 'pending' then
    raise exception 'Donation % has already been processed (status: %).', p_donation_id, v_donation.status;
  end if;

  update public.donations set status = 'verified' where id = p_donation_id;

  insert into public.donation_audit_logs (
    donation_id, action, amount, from_entity, to_entity, performed_by, metadata
  ) values (
    p_donation_id, 'DONATION_APPROVED', v_donation.amount, 'superadmin', 'donation_system',
    auth.uid(), jsonb_build_object('allocation_type', v_donation.allocation_type)
  );

  if v_donation.clinic_id is not null then
    select name into v_clinic_name from public.clinics where id = v_donation.clinic_id;

    insert into public.donation_audit_logs (
      donation_id, clinic_id, action, amount, from_entity, to_entity, performed_by, metadata
    ) values (
      p_donation_id, v_donation.clinic_id, 'DONATION_SENT_TO_CENTER', v_donation.amount,
      'superadmin', coalesce(v_clinic_name, v_donation.clinic_id::text), auth.uid(),
      jsonb_build_object('allocation_type', v_donation.allocation_type)
    );
  else
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
        p_donation_id, v_allocation.id, v_allocation.clinic_id, 'DONATION_SENT_TO_CENTER',
        v_allocation.amount, 'superadmin',
        coalesce(v_allocation.clinic_name, v_allocation.clinic_id::text), auth.uid(),
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

  select * into v_donation from public.donations where id = p_donation_id for update;

  if not found then
    raise exception 'Donation % was not found.', p_donation_id;
  end if;

  if v_donation.payment_environment is not null then
    raise exception 'Donation % is settled by the payment workflow and cannot be rejected manually.', p_donation_id;
  end if;

  if v_donation.status <> 'pending' then
    raise exception 'Donation % has already been processed (status: %).', p_donation_id, v_donation.status;
  end if;

  update public.donations set status = 'rejected' where id = p_donation_id;

  insert into public.donation_audit_logs (
    donation_id, action, amount, from_entity, to_entity, performed_by, metadata
  ) values (
    p_donation_id, 'DONATION_REJECTED', v_donation.amount, 'superadmin', 'donor',
    auth.uid(), jsonb_build_object('allocation_type', v_donation.allocation_type)
  );

  select * into v_donation from public.donations where id = p_donation_id;
  return v_donation;
end;
$$;

-- =====================================================================
-- 11. Function privileges
-- =====================================================================
-- Postgres grants EXECUTE to PUBLIC by default; revoke it everywhere and
-- grant back only what each caller needs.

revoke execute on function public.check_donation_allocation_total() from public;
revoke execute on function public.guard_donation_payment_columns() from public;
revoke execute on function public.guard_donation_allocation_rows() from public;
revoke execute on function public.guard_donation_truncate() from public;
-- donation_is_api_role() stays executable: the guard triggers call it as
-- the writing role.
revoke execute on function public.donation_checkout_json(uuid) from public, anon, authenticated;
revoke execute on function public.donation_lock_owned(uuid, text) from public, anon, authenticated;
revoke execute on function public.donation_finalize(uuid, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.paymongo_attach_checkout(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.paymongo_record_payment(text, text, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.paymongo_get_owned_donation(uuid, text) from public, anon, authenticated;

grant execute on function public.paymongo_attach_checkout(uuid, text, text) to service_role;
grant execute on function public.paymongo_record_payment(text, text, text, text, boolean) to service_role;
grant execute on function public.paymongo_get_owned_donation(uuid, text) to service_role;

revoke execute on function public.create_donation_checkout(text, bigint, uuid, text, text, boolean, text) from public;
revoke execute on function public.get_donation_checkout(uuid, text) from public;
revoke execute on function public.cancel_donation_checkout(uuid, text) from public;
revoke execute on function public.simulate_donation_payment(uuid, text, text) from public;
grant execute on function public.create_donation_checkout(text, bigint, uuid, text, text, boolean, text) to anon, authenticated;
grant execute on function public.get_donation_checkout(uuid, text) to anon, authenticated;
grant execute on function public.cancel_donation_checkout(uuid, text) to anon, authenticated;
grant execute on function public.simulate_donation_payment(uuid, text, text) to anon, authenticated;
grant execute on function public.donation_eligible_centers() to anon, authenticated;
grant execute on function public.donation_equal_split(bigint, integer) to anon, authenticated;

-- =====================================================================
-- 12. Remove direct-write paths (approved change)
-- =====================================================================
-- The old browser flow inserted donations as 'verified' and inserted
-- allocations itself. Both now happen only inside create_donation_checkout,
-- and nothing in any app updates or deletes these tables directly.
--
-- a) Drop every INSERT / UPDATE / DELETE policy on donations and
--    donation_allocations that applies to anon, authenticated or public
--    (on the live project this includes "Allow update donations" --
--    UPDATE to public using (true) -- and "Allow donation allocation
--    inserts"). SELECT policies are kept: the landing page and the
--    dashboards read through them. Policies covering ALL commands are kept
--    (they may be what a dashboard reads through) and reported as NOTICEs;
--    the guard triggers and the revoked grants below stop their write half.
do $$
declare
  v_policy record;
begin
  for v_policy in
    select tablename, policyname, cmd, roles
    from pg_policies
    where schemaname = 'public'
      and tablename in ('donations', 'donation_allocations')
  loop
    if v_policy.cmd in ('INSERT', 'UPDATE', 'DELETE')
       and (v_policy.roles && array['anon', 'authenticated', 'public']::name[]) then
      execute format('drop policy %I on public.%I', v_policy.policyname, v_policy.tablename);
      raise notice 'Dropped % policy on %: %', v_policy.cmd, v_policy.tablename, v_policy.policyname;
    elsif v_policy.cmd = 'ALL' then
      raise notice 'Kept ALL-command policy on % (writes still blocked by guard trigger + grants): % roles=%',
        v_policy.tablename, v_policy.policyname, v_policy.roles;
    end if;
  end loop;
end;
$$;

-- b) Revoke write privileges from the API roles on every donation table.
--    SELECT stays granted (RLS still decides which rows are visible).
revoke insert, update, delete, truncate, references, trigger
  on public.donations, public.donation_allocations, public.donation_audit_logs,
     public.payment_provider_events, public.donation_payment_settings
  from anon, authenticated, public;

--    SELECT stays for signed-in users (RLS decides which rows -- see section
--    13). Anonymous visitors keep SELECT only on the non-sensitive settings
--    row; section 13 removes their direct read of the donation tables.
grant select
  on public.donations, public.donation_allocations, public.donation_audit_logs,
     public.payment_provider_events, public.donation_payment_settings
  to authenticated;
grant select on public.donation_payment_settings to anon;

-- c) Self-check: abort (and roll back this whole migration) if any write
--    path for the API roles is still open on the donation tables.
do $$
declare
  v_problem text;
begin
  select string_agg(format('%s policy %s on %s', p.cmd, p.policyname, p.tablename), '; ')
    into v_problem
  from pg_policies p
  where p.schemaname = 'public'
    and p.tablename in ('donations', 'donation_allocations')
    and p.cmd in ('INSERT', 'UPDATE', 'DELETE')
    and p.roles && array['anon', 'authenticated', 'public']::name[];
  if v_problem is not null then
    raise exception 'SELF-CHECK FAILED: write policies remain: %', v_problem;
  end if;

  select string_agg(format('%s on %s to %s', g.privilege_type, g.table_name, g.grantee), '; ')
    into v_problem
  from information_schema.role_table_grants g
  where g.table_schema = 'public'
    and g.table_name in ('donations', 'donation_allocations', 'donation_audit_logs',
                         'payment_provider_events', 'donation_payment_settings')
    and g.grantee in ('anon', 'authenticated', 'PUBLIC')
    and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_problem is not null then
    raise exception 'SELF-CHECK FAILED: write grants remain: %', v_problem;
  end if;

  if exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'public.donations'::regclass
      and t.tgname = 'donations_guard_payment_columns' and t.tgenabled <> 'D'
  ) is not true then
    raise exception 'SELF-CHECK FAILED: donations guard trigger missing or disabled';
  end if;

  if exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'public.donation_allocations'::regclass
      and t.tgname = 'donation_allocations_guard_rows' and t.tgenabled <> 'D'
  ) is not true then
    raise exception 'SELF-CHECK FAILED: allocations guard trigger missing or disabled';
  end if;

  if (select environment from public.donation_payment_settings where id) <> 'sandbox' then
    raise notice 'NOTE: donation_payment_settings.environment is not sandbox; checkouts are refused until a live integration exists.';
  end if;

  raise notice 'Self-check passed: no direct write path to donation tables for API roles.';
end;
$$;

-- =====================================================================
-- 13. Donor privacy: who may read donations
-- =====================================================================
--
-- Before: "Allow read donations" (SELECT to public using true) let every
-- visitor read every donation row -- donor names AND emails, amounts,
-- payment references. The Super Admin app and the Center Admin panel were
-- also reading through that policy (there was no superadmin read policy),
-- and the existing "Center admins can view ..." policies only checked
-- profiles.clinic_id, which PATIENTS also have (they pick a clinic in the
-- mobile app) -- so a patient could read their clinic's donor emails.
--
-- After:
--   * anonymous visitors: no direct access to donations, allocations, audit
--     logs or provider events. The landing page instead calls
--     public_donation_feed() / public_donation_totals(), which return only
--     display name ('Anonymous' for anonymous gifts), date and amount of
--     verified donations -- exactly what the page shows. Never email.
--   * superadmins (profiles.role 'superadmin', or app_metadata.role
--     'superadmin' -- the same rule the Super Admin app's login uses): all
--     rows.
--   * center admins (profiles.role 'admin'): donations to their own center,
--     plus Donate-to-All donations their center has a share of (the Admin
--     Panel totals need the parent row's status).
--   * everyone else signed in (donors, patients): nothing directly.

-- Role helpers. SECURITY DEFINER so they can read profiles without
-- tripping over profiles' own RLS. Distinct names so they cannot collide
-- with helpers that may already exist in the project.
create or replace function public.curenurture_is_superadmin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'superadmin'
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and lower(btrim(p.role)) = 'superadmin'
    ),
    false);
$$;

create or replace function public.curenurture_admin_clinic_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select nullif(p.clinic_id::text, '')::uuid
  from public.profiles p
  where p.id = auth.uid() and lower(btrim(p.role)) = 'admin';
$$;

revoke execute on function public.curenurture_is_superadmin() from public;
revoke execute on function public.curenurture_admin_clinic_id() from public;
grant execute on function public.curenurture_is_superadmin() to anon, authenticated, service_role;
grant execute on function public.curenurture_admin_clinic_id() to anon, authenticated, service_role;

-- a) RLS must be on for the read policies below to mean anything (it is on
--    in the live project; this is a no-op there). Then drop broad read
--    policies on donations: any SELECT or ALL policy for anon / public, or
--    whose condition is simply true. (Their write half is already blocked
--    by section 5.)
alter table public.donations enable row level security;
alter table public.donation_allocations enable row level security;
alter table public.donation_audit_logs enable row level security;
alter table public.payment_provider_events enable row level security;
alter table public.donation_payment_settings enable row level security;

do $$
declare
  v_policy record;
begin
  for v_policy in
    select policyname, roles, qual
    from pg_policies
    where schemaname = 'public' and tablename = 'donations' and cmd in ('SELECT', 'ALL')
  loop
    if v_policy.roles && array['anon', 'public']::name[]
       or btrim(coalesce(v_policy.qual, '')) in ('true', '(true)') then
      execute format('drop policy %I on public.donations', v_policy.policyname);
      raise notice 'Dropped broad donations read policy: %', v_policy.policyname;
    end if;
  end loop;
end;
$$;

-- b) Explicit read policies.
drop policy if exists "Superadmins can read all donations" on public.donations;
create policy "Superadmins can read all donations"
  on public.donations
  for select
  to authenticated
  using ((select public.curenurture_is_superadmin()));

drop policy if exists "Center admins can view their own center's donations" on public.donations;
create policy "Center admins can view their own center's donations"
  on public.donations
  for select
  to authenticated
  using (
    clinic_id = (select public.curenurture_admin_clinic_id())
    or exists (
      select 1 from public.donation_allocations a
      where a.donation_id = donations.id
        and a.clinic_id = (select public.curenurture_admin_clinic_id())
    )
  );

drop policy if exists "Center admins can view their own allocations" on public.donation_allocations;
create policy "Center admins can view their own allocations"
  on public.donation_allocations
  for select
  to authenticated
  using (clinic_id = (select public.curenurture_admin_clinic_id()));

drop policy if exists "Superadmins can view all allocations" on public.donation_allocations;
create policy "Superadmins can view all allocations"
  on public.donation_allocations
  for select
  to authenticated
  using ((select public.curenurture_is_superadmin()));

drop policy if exists "Center admins can view their own audit logs" on public.donation_audit_logs;
create policy "Center admins can view their own audit logs"
  on public.donation_audit_logs
  for select
  to authenticated
  using (clinic_id = (select public.curenurture_admin_clinic_id()));

drop policy if exists "Superadmins can view all audit logs" on public.donation_audit_logs;
create policy "Superadmins can view all audit logs"
  on public.donation_audit_logs
  for select
  to authenticated
  using ((select public.curenurture_is_superadmin()));

drop policy if exists "Superadmins can view provider events" on public.payment_provider_events;
create policy "Superadmins can view provider events"
  on public.payment_provider_events
  for select
  to authenticated
  using ((select public.curenurture_is_superadmin()));

-- c) Anonymous visitors lose direct read access to the private tables.
revoke select
  on public.donations, public.donation_allocations, public.donation_audit_logs,
     public.payment_provider_events
  from anon, public;

-- d) What the public landing page needs, and nothing more.
create or replace function public.public_donation_feed(p_limit integer default 50)
returns table (display_name text, donated_at timestamptz, amount numeric)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(btrim(d.name), ''), 'Anonymous')::text,
         d.created_at::timestamptz,
         d.amount::numeric
  from public.donations d
  where d.status = 'verified'
    and d.payment_environment is distinct from 'sandbox'
  order by d.created_at desc nulls last
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

create or replace function public.public_donation_totals()
returns table (donation_count bigint, total_amount numeric)
language sql
stable
security definer
set search_path = public
as $$
  select count(*), coalesce(sum(d.amount), 0)::numeric
  from public.donations d
  where d.status = 'verified'
    and d.payment_environment is distinct from 'sandbox';
$$;

revoke execute on function public.public_donation_feed(integer) from public;
revoke execute on function public.public_donation_totals() from public;
grant execute on function public.public_donation_feed(integer) to anon, authenticated;
grant execute on function public.public_donation_totals() to anon, authenticated;

-- =====================================================================
-- 14. Superadmin access: nobody else can grant themselves a role
-- =====================================================================
--
-- The apps write profiles from the browser:
--   * Donation signup upserts its own row (no role).
--   * Mobile signup inserts its own row with role 'patient'; patients edit
--     their own name and choose a clinic (clinic_id).
--   * The Super Admin app creates 'admin' profiles for new accounts, edits
--     their name / phone / clinic, and (de)activates them.
-- Every superadmin check in the database reads profiles.role, so a user who
-- could set their own role to 'superadmin' (or 'admin' + a clinic) would
-- gain those rights. The profiles RLS policies are not in this repository,
-- so this trigger enforces the rules regardless of them. For writes coming
-- through the Supabase API by anyone who is NOT a superadmin:
--   * INSERT only your own profile, and never with role admin / superadmin;
--   * UPDATE only your own profile, never its id or role;
--   * an admin account cannot change its own clinic_id, status or is_active
--     (that would move it to another center or reactivate it);
--   * DELETE is refused.
-- Superadmins, the SQL Editor, service_role and server-side auth triggers
-- are not restricted. Columns are compared through to_jsonb() so the rules
-- work even if a column such as is_active does not exist.

create or replace function public.guard_profile_privileges()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_uid uuid;
  v_new jsonb;
  v_old jsonb;
  v_privileged constant text[] := array['admin', 'superadmin', 'super_admin'];
begin
  if not public.donation_is_api_role() or public.curenurture_is_superadmin() then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_uid := auth.uid();

  if tg_op = 'DELETE' then
    raise exception 'PROFILE_WRITE_BLOCKED: only a superadmin can delete profiles.';
  end if;

  v_new := to_jsonb(new);

  if tg_op = 'INSERT' then
    if v_uid is null or new.id is distinct from v_uid then
      raise exception 'PROFILE_WRITE_BLOCKED: you can only create your own profile.';
    end if;
    if lower(btrim(coalesce(v_new ->> 'role', ''))) = any (v_privileged) then
      raise exception 'ROLE_CHANGE_BLOCKED: only a superadmin can assign the % role.', v_new ->> 'role';
    end if;
    return new;
  end if;

  -- UPDATE
  v_old := to_jsonb(old);

  if old.id is distinct from v_uid then
    raise exception 'PROFILE_WRITE_BLOCKED: you can only edit your own profile.';
  end if;
  if new.id is distinct from old.id then
    raise exception 'PROFILE_WRITE_BLOCKED: a profile id cannot be changed.';
  end if;
  if (v_new -> 'role') is distinct from (v_old -> 'role') then
    raise exception 'ROLE_CHANGE_BLOCKED: only a superadmin can change roles.';
  end if;
  if lower(btrim(coalesce(v_old ->> 'role', ''))) = any (v_privileged)
     and ((v_new -> 'clinic_id') is distinct from (v_old -> 'clinic_id')
       or (v_new -> 'status') is distinct from (v_old -> 'status')
       or (v_new -> 'is_active') is distinct from (v_old -> 'is_active')) then
    raise exception 'PROFILE_WRITE_BLOCKED: only a superadmin can change an admin account''s center or status.';
  end if;

  return new;
end;
$$;

revoke execute on function public.guard_profile_privileges() from public;

drop trigger if exists profiles_guard_privileges on public.profiles;
create trigger profiles_guard_privileges
  before insert or update or delete on public.profiles
  for each row execute function public.guard_profile_privileges();

-- Final check for sections 13-14.
do $$
begin
  if exists (
    select 1 from pg_policies p
    where p.schemaname = 'public' and p.tablename = 'donations' and p.cmd in ('SELECT', 'ALL')
      and (p.roles && array['anon', 'public']::name[] or btrim(coalesce(p.qual, '')) in ('true', '(true)'))
  ) then
    raise exception 'SELF-CHECK FAILED: a donations read policy for everyone remains.';
  end if;

  if has_table_privilege('anon', 'public.donations', 'SELECT') then
    raise exception 'SELF-CHECK FAILED: anon can still SELECT donations directly.';
  end if;

  if exists (
    select 1 from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relname in ('donations', 'donation_allocations', 'donation_audit_logs',
                        'payment_provider_events', 'donation_payment_settings')
      and not c.relrowsecurity
  ) then
    raise exception 'SELF-CHECK FAILED: RLS is not enabled on every donation table.';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass and tgname = 'profiles_guard_privileges' and tgenabled <> 'D'
  ) then
    raise exception 'SELF-CHECK FAILED: profiles guard trigger missing or disabled.';
  end if;

  raise notice 'Self-check passed: donor details private; roles changeable only by superadmins.';
end;
$$;
