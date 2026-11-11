-- MIGRATION v6 -- forward fix on top of the applied v3 (v3 itself is not modified).
--
-- supabase_migration_donation_eligibility_v6.sql
--
-- Restores the ORIGINAL clinic-status rule of the sandbox migration (v1):
--   a centre is selectable unless it is marked 'closed'
--   (status NULL, 'open', 'full', 'busy', 'maintenance' are all selectable).
-- v3 had narrowed this to status = 'open', which hid Valenzuela Dialysis Center
-- (status 'full'), the main centre.
--
-- KEPT from v3 (approved separately): the centre must be run by an ACTIVE
-- centre admin linked to it --
--     lower(btrim(profiles.role)) = 'admin' and profiles.status = 'active'
--     and profiles.is_active = true and profiles.clinic_id = clinics.id
-- and SECURITY DEFINER, returning only id, name, address, city.
--
-- One function, every path: the donation form, the server-side Specific check,
-- the Random pick and the Equal split (create_donation_checkout), and the
-- "recipient became ineligible" re-checks (simulate_donation_payment,
-- paymongo_record_payment) all call donation_eligible_centers(), so the page
-- and the server cannot disagree. No clinic row is changed.
--
-- Rollback: supabase_rollback_donation_eligibility_v6.sql (restores v3 exactly)
-- Tests:    supabase_tests_donation_eligibility_v6.sql


do $$
begin
  if to_regprocedure('public.donation_eligible_centers()') is null then
    raise exception 'STOP: donation_eligible_centers() is missing. Nothing changed.';
  end if;
  if md5(pg_get_functiondef('public.donation_eligible_centers()'::regprocedure)) <> '573597212f4e86333154c7fd85737b4f' then
    raise exception 'STOP: donation_eligible_centers() is not the applied v3 definition. Nothing changed.';
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
  where (c.status is null or c.status <> 'closed')
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
    raise exception 'POST-CHECK FAILED: function must stay SECURITY DEFINER';
  end if;
  if exists (select 1 from public.donation_eligible_centers() e join public.clinics c on c.id = e.id
             where c.status = 'closed') then
    raise exception 'POST-CHECK FAILED: a closed clinic is eligible';
  end if;
  if exists (select 1 from public.donation_eligible_centers() e
             where not exists (select 1 from public.profiles p where p.clinic_id = e.id
                               and lower(btrim(p.role)) = 'admin' and p.status = 'active' and p.is_active)) then
    raise exception 'POST-CHECK FAILED: a clinic without an active admin is eligible';
  end if;
end $$;

