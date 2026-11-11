-- PROPOSED MIGRATION -- NOT APPLIED. Review before use.
--
-- supabase_migration_donation_eligibility_v3.sql
-- Follow-up to supabase_migration_donation_sandbox.sql (which it does NOT modify).
--
-- Decision A (option 3): a dialysis centre may receive donations only if it is
--   (1) open:                       clinics.status = 'open'
--   (2) run by an active centre admin linked to it. "Active centre admin" is the
--       EXISTING rule from public.curenurture_active_admin_clinic_id()
--       (supabase_security/00_foundation_apply.sql:470, used by the 07b policies
--       and by the Super Admin accounts page):
--         lower(btrim(profiles.role)) = 'admin'
--         and profiles.status = 'active'
--         and profiles.is_active = true
--         and profiles.clinic_id = clinics.id
--   No new approval concept is introduced.
--
-- Effects:
--   * Clinics with status NULL, 'full', 'busy' or 'maintenance' stop being eligible
--     (before: everything except 'closed').
--   * The server-side random pick and equal split (create_donation_checkout), the
--     "recipient became ineligible" checks (simulate_donation_payment,
--     paymongo_record_payment) and the donation form all use this one function,
--     so the page and the server cannot disagree.
--   * SECURITY DEFINER (owner postgres) so the admin check works for anon and
--     donors without granting them access to profiles; it returns only
--     id, name, address, city -- never anything from profiles.
--   * Privileges are unchanged (EXECUTE stays as it was).
--
-- Rollback: supabase_rollback_donation_eligibility_v3.sql
-- Tests:    supabase_tests_donation_eligibility_v3.sql


do $$
begin
  if to_regprocedure('public.donation_eligible_centers()') is null then
    raise exception 'STOP: donation_eligible_centers() is missing (sandbox migration not applied). Nothing changed.';
  end if;
  if md5(pg_get_functiondef('public.donation_eligible_centers()'::regprocedure)) <> 'f8c8b9048fbcc14766d8600a08336b99' then
    raise exception 'STOP: donation_eligible_centers() is not the reviewed v1 definition. Nothing changed.';
  end if;
end $$;

create or replace function public.donation_eligible_centers()
returns table (id uuid, name text, address text, city text)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.name::text, c.address::text, c.city::text
  from public.clinics c
  where c.status = 'open'
    and exists (
      select 1
      from public.profiles p
      where p.clinic_id = c.id
        and lower(btrim(p.role)) = 'admin'
        and p.status = 'active'
        and p.is_active = true
    )
  order by c.name asc, c.id asc;
$$;

do $$
begin
  if not (select prosecdef from pg_proc where oid = 'public.donation_eligible_centers()'::regprocedure) then
    raise exception 'POST-CHECK FAILED: function is not SECURITY DEFINER.';
  end if;
  if not has_function_privilege('anon', 'public.donation_eligible_centers()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.donation_eligible_centers()', 'EXECUTE') then
    raise exception 'POST-CHECK FAILED: anon/authenticated lost EXECUTE (privileges must be unchanged).';
  end if;
end $$;

