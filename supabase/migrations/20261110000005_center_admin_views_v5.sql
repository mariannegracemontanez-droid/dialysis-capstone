-- MIGRATION v5 (approved: privacy-safe center-admin donation access)
--
-- supabase_migration_donation_center_admin_views_v5.sql
-- Requires v3 and v4 (uses the ACTIVE-admin curenurture_admin_clinic_id()).
--
-- Before v5 an active center admin could read WHOLE rows of their clinic's
-- donations through RLS: for registered donors that included name, email,
-- donor_id (Auth user id), idempotency_key and client_secret_hash, and the
-- audit log carried performed_by (Auth user ids) and metadata.
--
-- After v5 center admins read donations ONLY through two views that expose the
-- fields the admin panel needs, for their own clinic, while active:
--   center_admin_donations    one row per donation that involves their clinic
--   center_admin_allocations  their clinic's allocation rows + parent status
-- Donor identity: "Anonymous" for anonymous donations; for registered donations
-- the donor's display name only (the same information the public feed shows).
-- Never: email, phone, donor_id / Auth ids, idempotency keys, secret hashes,
-- provider ids, audit actors.
--
-- Their direct SELECT policies on donations and donation_audit_logs are dropped.
-- Superadmin policies, donor RPCs and the donation workflow are unchanged; the
-- allocation policy (no donor data) stays.
-- Rollback: supabase_rollback_donation_center_admin_views_v5.sql


do $$
begin
  if to_regprocedure('public.curenurture_admin_clinic_name()') is null then
    raise exception 'STOP: v4 is not applied. Nothing changed.';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'donations'
                 and policyname = 'Center admins can view their own center''s donations') then
    raise exception 'STOP: expected center-admin donations policy not found. Nothing changed.';
  end if;
end $$;

create view public.center_admin_donations with (security_barrier = true) as
select
  d.id,
  d.reference_code,
  d.amount,
  d.amount_centavos,
  d.currency,
  d.clinic_id,
  d.allocation_type,
  d.status,
  d.payment_status,
  d.payment_environment,
  d.payment_confirmed_at,
  d.created_at,
  case when d.donor_id is null then 'Anonymous'
       else coalesce(nullif(btrim(d.name), ''), 'Registered donor') end as donor_display_name
from public.donations d
where public.curenurture_admin_clinic_id() is not null
  and (d.clinic_id = public.curenurture_admin_clinic_id()
       or exists (select 1 from public.donation_allocations a
                  where a.donation_id = d.id
                    and a.clinic_id = public.curenurture_admin_clinic_id()));

comment on view public.center_admin_donations is
  'Center admins: donations involving their own clinic (active admins only). No donor contact details or account identifiers.';

create view public.center_admin_allocations with (security_barrier = true) as
select
  a.id,
  a.donation_id,
  a.clinic_id,
  a.amount,
  a.amount_centavos,
  a.allocation_status,
  a.created_at,
  d.reference_code,
  d.status as donation_status,
  d.clinic_id as donation_clinic_id,
  d.payment_status,
  d.payment_environment
from public.donation_allocations a
join public.donations d on d.id = a.donation_id
where public.curenurture_admin_clinic_id() is not null
  and a.clinic_id = public.curenurture_admin_clinic_id();

comment on view public.center_admin_allocations is
  'Center admins: their own clinic allocation rows with the parent donation status (active admins only).';

-- Views run with their owner's rights; the WHERE clauses above do the scoping.
revoke all on public.center_admin_donations, public.center_admin_allocations from public, anon, authenticated, service_role;
grant select on public.center_admin_donations, public.center_admin_allocations to authenticated;

drop policy "Center admins can view their own center's donations" on public.donations;
drop policy "Center admins can view their own audit logs" on public.donation_audit_logs;

do $$
begin
  if has_table_privilege('anon', 'public.center_admin_donations', 'SELECT')
     or has_table_privilege('anon', 'public.center_admin_allocations', 'SELECT')
     or has_table_privilege('authenticated', 'public.center_admin_donations', 'INSERT') then
    raise exception 'POST-CHECK FAILED: unexpected view privileges.';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name in ('center_admin_donations', 'center_admin_allocations')
               and column_name in ('email', 'name', 'donor_id', 'idempotency_key', 'client_secret_hash',
                                   'provider_payment_id', 'provider_checkout_id', 'performed_by', 'phone')) then
    raise exception 'POST-CHECK FAILED: a view exposes a private column.';
  end if;
end $$;

