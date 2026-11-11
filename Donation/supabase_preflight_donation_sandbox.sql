-- READ-ONLY preflight for supabase_migration_donation_sandbox.sql.
--
-- Run it in the Supabase SQL Editor BEFORE the migration, and again AFTER
-- it as a verification. It changes nothing: it only reads the catalog and
-- returns one table.
--
-- Read the `assessment` column:
--   OK                 nothing to do
--   FIXED BY MIGRATION a direct-write path that the migration removes
--                      (after the migration these rows disappear)
--   BLOCKER            fix before running the migration
--   REVIEW             not changed by the migration; decide whether it is
--                      acceptable (details in the row)
--   info               context only

with
targets(tbl) as (
  values ('donations'), ('donation_allocations'), ('donation_audit_logs'),
         ('payment_provider_events'), ('donation_payment_settings'), ('clinics'), ('profiles')
),
donation_tables(tbl) as (
  values ('donations'), ('donation_allocations'), ('donation_audit_logs'),
         ('payment_provider_events'), ('donation_payment_settings')
),
-- Roles reachable through the Supabase API: anon, authenticated, public,
-- plus any custom role the `authenticator` gateway can switch into
-- (service_role excluded: it is server-side only).
api_roles(r) as (
  select unnest(array['anon', 'authenticated', 'public']::name[])
  union
  select ro.rolname from pg_roles ro
  where to_regrole('authenticator') is not null
    and ro.rolname not in ('authenticator', 'service_role')
    and ro.rolname not like 'pg\_%' escape '\'
    and pg_has_role('authenticator', ro.oid, 'MEMBER')
),
-- Columns create_donation_checkout() writes; any other NOT NULL column
-- without a default would make every new donation fail.
written_donation_cols(c) as (
  values ('id'), ('donor_id'), ('name'), ('email'), ('amount'), ('amount_centavos'), ('currency'),
         ('payment_method'), ('payment_provider'), ('payment_environment'), ('payment_status'),
         ('status'), ('clinic_id'), ('allocation_type'), ('reference_code'), ('idempotency_key'),
         ('client_secret_hash'), ('updated_at')
),
written_allocation_cols(c) as (
  values ('id'), ('donation_id'), ('clinic_id'), ('amount'), ('amount_centavos'),
         ('clinic_name_snapshot'), ('allocation_status'), ('sort_order'), ('updated_at')
),
-- Functions this migration (and the two earlier donation migrations) own.
known_functions(f) as (
  values ('approve_donation'), ('reject_donation'), ('log_donation_received'), ('log_donation_allocated'),
         ('create_donation_checkout'), ('get_donation_checkout'), ('cancel_donation_checkout'),
         ('simulate_donation_payment'), ('donation_checkout_json'), ('donation_lock_owned'),
         ('donation_finalize'), ('paymongo_attach_checkout'), ('paymongo_record_payment'),
         ('paymongo_get_owned_donation'), ('check_donation_allocation_total'),
         ('guard_donation_payment_columns'), ('guard_donation_allocation_rows'),
         ('guard_donation_truncate'), ('donation_is_api_role'), ('donation_eligible_centers'),
         ('donation_equal_split'), ('donation_secret_hash'), ('curenurture_is_superadmin'),
         ('curenurture_admin_clinic_id'), ('public_donation_feed'), ('public_donation_totals'),
         ('guard_profile_privileges')
)
select ord, "check", item, detail, assessment from (

  -- 1. Prerequisites ---------------------------------------------------
  select 1 as ord, 'prerequisite' as "check", 'donations table' as item,
         case when to_regclass('public.donations') is not null then 'present' else 'missing' end as detail,
         case when to_regclass('public.donations') is not null then 'OK' else 'BLOCKER' end as assessment
  union all
  select 1, 'prerequisite', 'donation_allocations table (allocations migration)',
         case when to_regclass('public.donation_allocations') is not null then 'present'
              else 'missing - run supabase_migration_donation_allocations.sql' end,
         case when to_regclass('public.donation_allocations') is not null then 'OK' else 'BLOCKER' end
  union all
  select 1, 'prerequisite', 'donation_audit_logs table (confirmation migration)',
         case when to_regclass('public.donation_audit_logs') is not null then 'present'
              else 'missing - run supabase_migration_donation_confirmation.sql' end,
         case when to_regclass('public.donation_audit_logs') is not null then 'OK' else 'BLOCKER' end
  union all
  select 1, 'prerequisite', 'donations.allocation_type column',
         case when exists (select 1 from information_schema.columns where table_schema = 'public'
                           and table_name = 'donations' and column_name = 'allocation_type')
              then 'present' else 'missing - run supabase_migration_donation_confirmation.sql' end,
         case when exists (select 1 from information_schema.columns where table_schema = 'public'
                           and table_name = 'donations' and column_name = 'allocation_type')
              then 'OK' else 'BLOCKER' end
  union all
  select 1, 'prerequisite', 'approve_donation(uuid) function',
         case when to_regprocedure('public.approve_donation(uuid)') is not null then 'present' else 'missing' end,
         case when to_regprocedure('public.approve_donation(uuid)') is not null then 'OK' else 'BLOCKER' end
  union all
  select 1, 'prerequisite', 'auth.uid() and auth.jwt() (Supabase built-ins)',
         case when to_regprocedure('auth.uid()') is not null and to_regprocedure('auth.jwt()') is not null
              then 'present' else 'missing' end,
         case when to_regprocedure('auth.uid()') is not null and to_regprocedure('auth.jwt()') is not null
              then 'OK' else 'BLOCKER' end
  union all
  select 1, 'prerequisite', 'at least 3 profiles (privacy tests borrow 3, rolled back)',
         (select count(*)::text from public.profiles),
         (select case when count(*) >= 3 then 'OK' else 'REVIEW - tests need at least 3' end from public.profiles)
  union all
  select 1, 'prerequisite', 'eligible centres (status not closed)',
         (select count(*)::text from public.clinics where status is null or status <> 'closed'),
         (select case when count(*) >= 2 then 'OK' else 'REVIEW - tests need at least 2' end
          from public.clinics where status is null or status <> 'closed')
  union all
  select 1, 'prerequisite', 'sandbox migration already applied?',
         case when to_regclass('public.donation_payment_settings') is not null
              then 'yes (re-running is safe)' else 'no' end,
         'info'
  union all
  -- Payment mode, once the migration exists: must stay sandbox. The table
  -- is read dynamically (query_to_xml) only if it exists, so this query
  -- also works before the migration.
  select 1, 'payment mode', 'donation_payment_settings', m.mode,
         case when m.mode is null then 'info'
              when m.mode like 'sandbox%' then 'OK'
              else 'REVIEW - not sandbox' end
  from (
    select case when to_regclass('public.donation_payment_settings') is not null then
      (xpath('/row/m/text()', query_to_xml(
        'select environment || '' / simulator='' || simulator_enabled
                || '' / paymongo_test='' || paymongo_test_enabled as m
         from public.donation_payment_settings', false, true, '')))[1]::text
    end as mode
  ) m
  union all
  select 1, 'payment mode', 'live PayMongo secret configured?',
         'not visible from SQL - Edge Function secrets must only ever hold sk_test_ keys',
         'info'

  -- 2. Required columns the migration will not fill ---------------------
  union all
  select 2, 'column', col.table_name || '.' || col.column_name,
         col.data_type || ' NOT NULL without default',
         'BLOCKER - new donations would fail; add a default or make it nullable'
  from information_schema.columns col
  where col.table_schema = 'public'
    and col.is_nullable = 'NO' and col.column_default is null
    and ((col.table_name = 'donations' and col.column_name not in (select c from written_donation_cols))
      or (col.table_name = 'donation_allocations' and col.column_name not in (select c from written_allocation_cols)))
  union all
  select 2, 'column', 'donations.' || col.column_name,
         col.data_type
         || coalesce('(' || col.numeric_precision || ',' || col.numeric_scale || ')', '')
         || case when col.is_nullable = 'NO' then ' not null' else '' end
         || coalesce(' default ' || col.column_default, ''),
         case when col.column_name = 'amount' and col.data_type <> 'numeric'
              then 'BLOCKER - amount must be numeric'
              else 'info' end
  from information_schema.columns col
  where col.table_schema = 'public' and col.table_name = 'donations'

  -- 3. RLS switches -------------------------------------------------------
  union all
  select 3, 'rls', t.tbl,
         case when c.oid is null then 'table missing (created by the migration)'
              when c.relrowsecurity then 'RLS enabled'
              else 'RLS DISABLED' end,
         case when c.oid is null then 'info'
              when c.relrowsecurity then 'OK'
              when t.tbl in ('donations', 'donation_allocations')
                then 'REVIEW - anyone with a SELECT grant can read every row; writes are still blocked by the migration'
              else 'REVIEW - RLS disabled' end
  from targets t
  left join pg_class c on c.relname = t.tbl and c.relnamespace = 'public'::regnamespace

  -- 4. Policies on the donation tables -------------------------------------
  union all
  select 4, 'policy', p.tablename || ': ' || p.policyname,
         p.cmd || ' to ' || array_to_string(p.roles, ',')
         || ' | using: ' || coalesce(p.qual, '-') || ' | check: ' || coalesce(p.with_check, '-'),
         case
           when p.cmd in ('INSERT', 'UPDATE', 'DELETE')
                and p.tablename in ('donations', 'donation_allocations')
                and p.roles && array['anon', 'authenticated', 'public']::name[]
             then 'FIXED BY MIGRATION - write policy for API roles is dropped'
           when p.cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL') and p.roles && (select array_agg(r) from api_roles)
             then 'REVIEW - kept; on donations/donation_allocations its writes are refused by the guard triggers'
           when p.cmd = 'SELECT' and p.tablename = 'donations'
                and (p.roles && array['anon', 'public']::name[] or btrim(coalesce(p.qual, '')) in ('true', '(true)'))
             then 'FIXED BY MIGRATION - everyone could read every donation incl. donor email; replaced by public_donation_feed()'
           when p.policyname like 'Center admins can view their own%'
                and coalesce(p.qual, '') not ilike '%curenurture_admin_clinic_id%'
             then 'FIXED BY MIGRATION - checks only profiles.clinic_id, which patients also have; replaced with a role-checked policy'
           when p.policyname like 'Superadmins can%'
                and coalesce(p.qual, '') not ilike '%curenurture_is_superadmin%'
             then 'FIXED BY MIGRATION - replaced so app_metadata superadmins are recognised too'
           else 'OK'
         end
  from pg_policies p
  where p.schemaname = 'public' and p.tablename in (select tbl from donation_tables)

  -- 5. Table write grants held by API roles --------------------------------
  union all
  select 5, 'grant', g.table_name || ' -> ' || g.grantee,
         string_agg(g.privilege_type, ', ' order by g.privilege_type),
         case when bool_or(g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'))
              then 'FIXED BY MIGRATION - write privileges are revoked'
              when g.grantee in ('anon', 'PUBLIC') and g.table_name <> 'donation_payment_settings'
                   and bool_or(g.privilege_type = 'SELECT')
              then 'FIXED BY MIGRATION - anonymous direct read is revoked (landing page uses public_donation_feed)'
              else 'OK' end
  from information_schema.role_table_grants g
  where g.table_schema = 'public'
    and g.table_name in (select tbl from donation_tables)
    and g.grantee in ('anon', 'authenticated', 'PUBLIC')
  group by g.table_name, g.grantee

  -- 6. Who is "superadmin"? profiles policies that let users write rows -----
  union all
  select 6, 'profiles policy', p.policyname,
         p.cmd || ' to ' || array_to_string(p.roles, ',')
         || ' | using: ' || coalesce(p.qual, '-') || ' | check: ' || coalesce(p.with_check, '-'),
         case when p.cmd in ('INSERT', 'UPDATE', 'ALL', 'DELETE')
                   and p.roles && (select array_agg(r) from api_roles)
              then case when exists (select 1 from pg_trigger t
                                     where t.tgrelid = to_regclass('public.profiles')
                                       and t.tgname = 'profiles_guard_privileges' and t.tgenabled <> 'D')
                        then 'OK - role / center / status changes are restricted by the profiles_guard_privileges trigger'
                        else 'FIXED BY MIGRATION - this policy alone may let users set their own role; the migration adds a guard trigger' end
              else 'info' end
  from pg_policies p
  where p.schemaname = 'public' and p.tablename = 'profiles'

  union all
  select 6, 'profiles column', 'profiles.' || col.column_name,
         col.data_type || coalesce(' default ' || col.column_default, ''),
         case when col.column_name = 'role' and col.data_type not in ('text', 'character varying')
                then 'BLOCKER - role helpers expect a text role column'
              when col.column_name = 'role' and lower(coalesce(col.column_default, '')) ~ '(admin|superadmin)'
                then 'BLOCKER - role defaults to a privileged value'
              else 'info' end
  from information_schema.columns col
  where col.table_schema = 'public' and col.table_name = 'profiles'
    and col.column_name in ('id', 'role', 'clinic_id', 'status', 'is_active')

  union all
  select 6, 'profiles role', coalesce(nullif(pr.role, ''), '(empty)'),
         count(*)::text || ' profile(s)',
         case when lower(btrim(pr.role)) in ('superadmin', 'admin', 'patient', 'donor', '')
                   or pr.role is null
                then 'info'
              when lower(pr.role) ~ 'super|admin'
                then 'REVIEW - looks privileged but is not exactly ''superadmin''/''admin'' (case and spaces ignored); it gets no admin rights'
              else 'info' end
  from public.profiles pr
  group by pr.role

  union all
  select 6, 'superadmins', 'via auth app_metadata.role',
         (select count(*)::text from auth.users u where u.raw_app_meta_data ->> 'role' = 'superadmin') || ' account(s)',
         'info'

  union all
  select 6, 'function name', 'public.' || pr.proname,
         'already exists before the migration',
         'REVIEW - the migration will REPLACE this function; check nothing else depends on it'
  from pg_proc pr
  where pr.pronamespace = 'public'::regnamespace
    and pr.proname in ('curenurture_is_superadmin', 'curenurture_admin_clinic_id',
                       'public_donation_feed', 'public_donation_totals', 'guard_profile_privileges')
    and to_regclass('public.donation_payment_settings') is null

  -- 7. Other SECURITY DEFINER functions that touch donation tables ----------
  union all
  select 7, 'definer function', n.nspname || '.' || pr.proname || '(' || pg_get_function_identity_arguments(pr.oid) || ')',
         'owner=' || pg_get_userbyid(pr.proowner)
         || ' | anon can execute=' || has_function_privilege('anon', pr.oid, 'EXECUTE')
         || ' | authenticated can execute=' || has_function_privilege('authenticated', pr.oid, 'EXECUTE'),
         case when has_function_privilege('anon', pr.oid, 'EXECUTE')
                or has_function_privilege('authenticated', pr.oid, 'EXECUTE')
              then 'REVIEW - not part of the donation migrations; runs as its owner, so it bypasses the guards'
              else 'info' end
  from pg_proc pr
  join pg_namespace n on n.oid = pr.pronamespace
  where pr.prosecdef
    and n.nspname = 'public'
    and pr.proname not in (select f from known_functions)
    and pr.prosrc ~* '(donations|donation_allocations|donation_payment_settings)'

  -- 8. Triggers on the donation tables --------------------------------------
  union all
  select 8, 'trigger', tg.tgrelid::regclass::text || ': ' || tg.tgname,
         pg_get_triggerdef(tg.oid),
         case when tg.tgenabled = 'D' then 'REVIEW - trigger is DISABLED'
              when tg.tgname in ('donations_guard_payment_columns', 'donation_allocations_guard_rows',
                                 'donations_guard_truncate', 'donation_allocations_guard_truncate',
                                 'donation_allocations_total_check', 'donations_log_received',
                                 'donation_allocations_log_allocated')
                then 'OK'
              else 'REVIEW - trigger not created by the donation migrations' end
  from pg_trigger tg
  where tg.tgrelid in (to_regclass('public.donations'), to_regclass('public.donation_allocations'))
    and not tg.tgisinternal

  -- 9. Constraints on donations ---------------------------------------------
  union all
  select 9, 'constraint', con.conname, pg_get_constraintdef(con.oid),
         case when con.contype = 'c' and pg_get_constraintdef(con.oid) ilike '%status%'
                   and pg_get_constraintdef(con.oid) not ilike '%rejected%'
                   and con.conname not in (
                     'donations_allocation_type_check', 'donations_payment_environment_check',
                     'donations_payment_status_check', 'donations_payment_provider_check',
                     'donations_sandbox_never_verified', 'donations_simulated_is_sandbox',
                     'donations_amount_centavos_check')
              then 'REVIEW - status check may not allow ''rejected'' (used for failed/cancelled)'
              else 'info' end
  from pg_constraint con
  where con.conrelid = to_regclass('public.donations') and con.contype in ('c', 'u', 'f')

  -- 10. Roles the API gateway can switch into -------------------------------
  union all
  select 10, 'api role', r.rolname,
         'authenticator can switch to this role',
         case when r.rolname in ('anon', 'authenticated', 'service_role') then 'info'
              else 'info - custom API role; the guards treat it as an API role too' end
  from pg_roles r
  where to_regrole('authenticator') is not null
    and r.rolname <> 'authenticator'
    and pg_has_role('authenticator', r.oid, 'MEMBER')
    and r.rolname not like 'pg\_%' escape '\'
) report
order by ord, item;
