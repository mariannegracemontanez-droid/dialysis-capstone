-- READ-ONLY checks for a CureNurture handoff database. Changes nothing.
-- Run (repository root, after import + create_dev_credentials):
--   docker exec -i supabase_db_curenurture psql -U postgres -d postgres -f - < tools\handoff\verify_handoff.sql
-- (PowerShell: cmd /c "docker exec -i supabase_db_curenurture psql -U postgres -d postgres -f - < tools\handoff\verify_handoff.sql")
\pset footer off
begin transaction read only;

with checks(n, check_name, result, detail) as (
  select 1, 'migrations applied (7)',
         case when (select count(*) from supabase_migrations.schema_migrations where version between '20261110000001' and '20261110000007') = 7 then 'PASS' else 'FAIL' end,
         (select string_agg(version, ' ' order by version) from supabase_migrations.schema_migrations)
  union all
  select 2, 'payments: sandbox, simulator on, PayMongo off',
         case when (select environment = 'sandbox' and simulator_enabled and not paymongo_test_enabled from public.donation_payment_settings) then 'PASS' else 'FAIL' end,
         (select environment || ' / simulator=' || simulator_enabled || ' / paymongo=' || paymongo_test_enabled from public.donation_payment_settings)
  union all
  select 3, 'storage: 3 private buckets',
         case when (select count(*) from storage.buckets where id in ('medical_docs','patient_profiles','donation_receipts') and not public) = 3 then 'PASS' else 'FAIL' end,
         (select string_agg(id || (case when public then ' (PUBLIC!)' else ' (private)' end), ', ' order by id) from storage.buckets)
  union all
  select 4, 'storage: no CureNurture policy open to anon',
         case when not exists (select 1 from pg_policies where schemaname = 'storage' and roles && array['anon','public']::name[]) then 'PASS' else 'FAIL' end,
         (select count(*)::text || ' storage policies' from pg_policies where schemaname = 'storage')
  union all
  select 5, 'centres loaded',
         case when (select count(*) from public.clinics) > 0 then 'PASS' else 'FAIL' end,
         (select count(*)::text || ' total; ' || count(*) filter (where id::text not like '00000000-0000-4000-8000-0000000c1a0%')::text || ' original (expected 23 with the full package)' from public.clinics)
  union all
  select 6, 'donation-selectable centres (v6 rule)',
         case when (select count(*) from public.donation_eligible_centers()) > 0 then 'PASS' else 'FAIL' end,
         (select count(*)::text || ' selectable' || case when bool_or(c.name = 'Valenzuela Dialysis Center') then '; Valenzuela Dialysis Center included' else '' end
            from public.donation_eligible_centers() e join public.clinics c on c.id = e.id)
  union all
  select 7, 'one admin per centre at most',
         case when coalesce((select max(n) from (select count(*) n from public.profiles where role = 'admin' and clinic_id is not null group by clinic_id) s), 0) <= 1 then 'PASS' else 'FAIL' end,
         (select count(*)::text || ' active admins linked to centres' from public.profiles where role = 'admin' and status = 'active' and is_active and clinic_id is not null)
  union all
  select 8, 'every profile has an account',
         case when not exists (select 1 from public.profiles p where not exists (select 1 from auth.users u where u.id = p.id)) then 'PASS' else 'FAIL' end,
         (select count(*)::text || ' profiles, ' || (select count(*) from auth.users)::text || ' accounts' from public.profiles)
  union all
  select 9, 'no imported passwords (only local dev credentials)',
         'INFO',
         (select count(*) filter (where coalesce(encrypted_password, '') <> '')::text || ' accounts have a local password; '
                 || count(*) filter (where coalesce(encrypted_password, '') = '')::text || ' have none' from auth.users)
  union all
  select 10, 'simulated payments are never verified',
         case when not exists (select 1 from public.donations where payment_environment = 'sandbox' and status = 'verified') then 'PASS' else 'FAIL' end,
         (select count(*) filter (where payment_environment is not null)::text || ' checkout records; '
                 || count(*) filter (where payment_status = 'simulated_paid')::text || ' completed (simulated)' from public.donations)
  union all
  select 11, 'received funds = verified only (website totals agree)',
         case when (select coalesce(sum(amount), 0) from public.donations where status = 'verified' and payment_environment is distinct from 'sandbox')
                   = (select total_amount from public.public_donation_totals()) then 'PASS' else 'FAIL' end,
         (select 'verified total ' || coalesce(sum(amount), 0)::text from public.donations where status = 'verified' and payment_environment is distinct from 'sandbox')
  union all
  select 12, 'no hosted Supabase links in data',
         case when not exists (select 1 from public.medical_documents m where m::text like '%supabase.co%')
               and not exists (select 1 from public.donations d where d.proof_url like '%supabase.co%')
               and not exists (select 1 from public.patients p where p.profile_image_url like '%supabase.co%') then 'PASS' else 'FAIL' end,
         'medical_documents, donations.proof_url, patients.profile_image_url'
  union all
  select 13, 'no synthetic test centres or accounts',
         case when not exists (select 1 from public.clinics where id::text like '00000000-0000-4000-8000-0000000c1a0%')
               and not exists (select 1 from auth.users where email ilike '%@example.invalid') then 'PASS' else 'FAIL' end,
         (select count(*)::text || ' synthetic centres; ' from public.clinics where id::text like '00000000-0000-4000-8000-0000000c1a0%')
           || (select count(*)::text || ' synthetic accounts' from auth.users where email ilike '%@example.invalid')
  union all
  select 14, 'no checkout secret hashes',
         case when not exists (select 1 from public.donations where client_secret_hash is not null) then 'PASS' else 'FAIL' end,
         (select count(*)::text || ' donations with a secret hash' from public.donations where client_secret_hash is not null)
  union all
  select 15, 'backup tables empty',
         case when coalesce((select sum((xpath('/row/c/text()', query_to_xml('select count(*) as c from public.' || quote_ident(tablename), false, true, '')))[1]::text::int)
                             from pg_tables where schemaname = 'public' and tablename like '%backup%'), 0) = 0 then 'PASS' else 'FAIL' end,
         (select coalesce(string_agg(tablename, ', '), 'none') from pg_tables where schemaname = 'public' and tablename like '%backup%')
)
select n as "#", check_name as "check", result, detail from checks order by n;

-- Foreign keys (orphan rows) -- every public/auth FK
do $$
declare r record; cnt bigint; cond text; nn text; total int := 0; bad int := 0;
begin
  for r in select k.conname, k.conrelid::regclass child, k.confrelid::regclass parent, k.conkey, k.confkey
           from pg_constraint k join pg_class c on c.oid = k.conrelid
           where k.contype = 'f' and c.relnamespace::regnamespace::text in ('public', 'auth')
  loop
    select string_agg(format('p.%I = c.%I', pa.attname, ca.attname), ' and '),
           string_agg(format('c.%I is not null', ca.attname), ' and ') into cond, nn
    from unnest(r.conkey, r.confkey) as u(ck, pk)
    join pg_attribute ca on ca.attrelid = r.child and ca.attnum = u.ck
    join pg_attribute pa on pa.attrelid = r.parent and pa.attnum = u.pk;
    execute format('select count(*) from %s c where %s and not exists (select 1 from %s p where %s)', r.child, nn, r.parent, cond) into cnt;
    total := total + 1;
    if cnt > 0 then bad := bad + 1; raise notice 'FAIL  FK % on %: % orphan rows', r.conname, r.child, cnt; end if;
  end loop;
  raise notice '%  foreign keys: % checked, % with orphan rows', case when bad = 0 then 'PASS' else 'FAIL' end, total, bad;
end $$;

rollback;
