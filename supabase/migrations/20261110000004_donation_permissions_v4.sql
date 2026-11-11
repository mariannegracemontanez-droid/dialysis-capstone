-- PROPOSED MIGRATION -- NOT APPLIED. Review before use.
--
-- supabase_migration_donation_permissions_v4.sql
-- Follow-up to supabase_migration_donation_sandbox.sql (not modified).
--
-- Closes the permission and privacy gaps found in the local review:
--   1. Anonymous privacy: donation_finalize() stored auth.uid() as performed_by
--      in donation_audit_logs, so an anonymous donation made while signed in
--      recorded that donor's Auth user id. It is now NULL whenever the donation
--      is anonymous (donor_id is null). Registered donations are unchanged.
--   2. Center-admin donation access uses the existing ACTIVE admin rule
--      (role admin + status 'active' + is_active = true), the same rule as
--      curenurture_active_admin_clinic_id() in supabase_security/00. Before, an
--      inactive or deactivated admin kept reading their clinic donations,
--      allocations and audit logs. Only those three policies use this helper.
--   3. donation_purchase_logs: readable and writable by EVERY signed-in user
--      (and fully granted to anon). Now superadmins read all; an active center
--      admin reads and adds only rows for their own clinic (matched by
--      clinic_name; the table has no clinic_id). No update or delete for API
--      roles (the apps never update or delete these rows).
--   4. fund_distributions: anyone, including anon, could read and insert. Now
--      superadmins read and record; an active center admin reads only rows for
--      their own clinic (clinic_id or center_name). No update or delete for API
--      roles.
--   5. donors: no SELECT policy existed (the Super Admin donor count always saw
--      0) and anon held full grants. Now a donor reads their own row and
--      superadmins read all; anon has no access.
--
-- Not changed: donations / allocations access for superadmins and donors, the
-- donation workflow, settings, Storage, roles or ownership.
-- Rollback: supabase_rollback_donation_permissions_v4.sql
-- Tests:    supabase_tests_donation_permissions_v4.sql (rolled back)


do $$
begin
  if md5(pg_get_functiondef('public.donation_finalize(uuid,text,text,text,text)'::regprocedure)) <> '99bc1ac5b26566c29a24c72e5f0be195'
     or md5(pg_get_functiondef('public.curenurture_admin_clinic_id()'::regprocedure)) <> 'd05648bed496a88f1d47a6bed980c6f3' then
    raise exception 'STOP: donation_finalize / curenurture_admin_clinic_id are not the reviewed v1 definitions. Nothing changed.';
  end if;
  if to_regprocedure('public.curenurture_is_superadmin()') is null then
    raise exception 'STOP: curenurture_is_superadmin() missing. Nothing changed.';
  end if;
end $$;

-- 1. ------------------------------------------------ anonymous audit privacy
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
    case when v_donation.donor_id is null then null else auth.uid() end,  -- v4: anonymous donations never record who was signed in
    jsonb_build_object(
      'payment_environment', v_donation.payment_environment,
      'payment_provider', v_donation.payment_provider,
      'reason', p_reason
    )
  );
end;
$$;

-- 2. ------------------------------------------------ active center admins only
create or replace function public.curenurture_admin_clinic_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select nullif(p.clinic_id::text, '')::uuid
  from public.profiles p
  where p.id = auth.uid()
    and lower(btrim(p.role)) = 'admin'
    and p.status = 'active'
    and p.is_active = true;
$$;

-- The calling active admin's own clinic name (purchase logs and fund
-- distributions are keyed by name). Returns nothing for anyone else.
create function public.curenurture_admin_clinic_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select c.name from public.clinics c where c.id = public.curenurture_admin_clinic_id();
$$;
revoke execute on function public.curenurture_admin_clinic_name() from public, anon;
grant execute on function public.curenurture_admin_clinic_name() to authenticated;

-- 3. ------------------------------------------------ purchase logs
drop policy "Allow authenticated users to insert purchase logs" on public.donation_purchase_logs;
drop policy "Allow authenticated users to view purchase logs" on public.donation_purchase_logs;
create policy "Superadmins can view all purchase logs" on public.donation_purchase_logs
  for select to authenticated using ((select public.curenurture_is_superadmin()));
create policy "Center admins can view own purchase logs" on public.donation_purchase_logs
  for select to authenticated using (clinic_name = (select public.curenurture_admin_clinic_name()));
create policy "Center admins can add own purchase logs" on public.donation_purchase_logs
  for insert to authenticated with check (clinic_name = (select public.curenurture_admin_clinic_name()));
revoke all on table public.donation_purchase_logs from anon;
revoke update, delete, truncate, references, trigger on table public.donation_purchase_logs from authenticated;

-- 4. ------------------------------------------------ fund distributions
drop policy "Allow insert for everyone" on public.fund_distributions;
drop policy "Allow insert fund distributions" on public.fund_distributions;
drop policy "Allow read fund distributions" on public.fund_distributions;
create policy "Superadmins can view all fund distributions" on public.fund_distributions
  for select to authenticated using ((select public.curenurture_is_superadmin()));
create policy "Superadmins can record fund distributions" on public.fund_distributions
  for insert to authenticated with check ((select public.curenurture_is_superadmin()));
create policy "Center admins can view own fund distributions" on public.fund_distributions
  for select to authenticated using (
    clinic_id = (select public.curenurture_admin_clinic_id())
    or center_name = (select public.curenurture_admin_clinic_name()));
revoke all on table public.fund_distributions from anon;
revoke update, delete, truncate, references, trigger on table public.fund_distributions from authenticated;

-- 5. ------------------------------------------------ donors
create policy "Donors can view own donor record" on public.donors
  for select to authenticated using (id = auth.uid());
create policy "Superadmins can view all donors" on public.donors
  for select to authenticated using ((select public.curenurture_is_superadmin()));
revoke all on table public.donors from anon;
revoke update, delete, truncate, references, trigger on table public.donors from authenticated;

do $$
begin
  if has_table_privilege('anon', 'public.donation_purchase_logs', 'SELECT')
     or has_table_privilege('anon', 'public.fund_distributions', 'SELECT')
     or has_table_privilege('anon', 'public.donors', 'SELECT')
     or has_table_privilege('authenticated', 'public.fund_distributions', 'UPDATE')
     or has_table_privilege('authenticated', 'public.donation_purchase_logs', 'DELETE') then
    raise exception 'POST-CHECK FAILED: unexpected privileges remain.';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public'
             and tablename in ('donation_purchase_logs', 'fund_distributions')
             and (qual = 'true' or with_check = 'true')) then
    raise exception 'POST-CHECK FAILED: an open (true) policy remains.';
  end if;
end $$;

