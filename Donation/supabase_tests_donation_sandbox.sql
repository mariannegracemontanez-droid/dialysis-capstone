-- Tests for supabase_migration_donation_sandbox.sql
--
-- Run in the Supabase SQL Editor AFTER the migration. Everything runs in one
-- transaction that is ROLLED BACK at the end, so no test data is left
-- behind and settings return to what they were.
--
-- Requires at least 2 dialysis centres that are not closed. Success prints
-- "ALL DONATION SANDBOX TESTS PASSED"; any failure stops with an error
-- naming the failing check.

begin;

-- ---------------------------------------------------------------- helpers

create or replace function pg_temp.expect_error(p_sql text, p_pattern text)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'EXPECTED ERROR "%" BUT SUCCEEDED: %', p_pattern, p_sql;
exception when others then
  if sqlerrm like 'EXPECTED ERROR%' then raise; end if;
  if sqlerrm not like p_pattern then
    raise exception 'WRONG ERROR for %: got "%", expected "%"', p_sql, sqlerrm, p_pattern;
  end if;
end;
$$;

create or replace function pg_temp.secret(p_n int) returns text language sql as $$
  select 'test-secret-' || p_n || '-' || repeat('x', 40);
$$;

-- Runs p_sql as an API role (anon / authenticated) signed in as p_uid, the
-- way PostgREST would, and returns its single result as text -- or
-- 'ERROR: <message>' if it was refused. p_app_role sets app_metadata.role.
create or replace function pg_temp.as_user(p_role text, p_uid uuid, p_sql text, p_app_role text default null)
returns text language plpgsql as $$
declare
  v_result text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then ''
         else json_build_object('sub', p_uid, 'role', p_role,
                                'app_metadata', json_build_object('role', p_app_role))::text end,
    true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v_result;
  exception when others then
    reset role;
    perform set_config('request.jwt.claims', '', true);
    return 'ERROR: ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return coalesce(v_result, 'OK');
end;
$$;

create or replace function pg_temp.new_checkout(p_mode text, p_amount bigint, p_clinic uuid, p_n int)
returns jsonb language sql as $$
  select public.create_donation_checkout(
    p_mode, p_amount, p_clinic, 'test-key-' || p_n || '-0123456789', pg_temp.secret(p_n), true, null);
$$;

update public.donation_payment_settings
set environment = 'sandbox', simulator_enabled = true, paymongo_test_enabled = false;

do $$
begin
  if (select count(*) from public.donation_eligible_centers()) < 2 then
    raise exception 'SETUP: need at least 2 eligible (not closed) centres to run these tests.';
  end if;
end $$;

-- ------------------------------------------------------ allocation maths

do $$
begin
  assert public.donation_equal_split(100000, 1) = array[100000]::bigint[], 'one centre';
  assert public.donation_equal_split(100000, 4) = array[25000, 25000, 25000, 25000]::bigint[], 'PHP 1000 / 4';
  assert public.donation_equal_split(100000, 3) = array[33334, 33333, 33333]::bigint[], 'PHP 1000 / 3 remainder';
  assert (select sum(x) from unnest(public.donation_equal_split(123457, 7)) x) = 123457, 'uneven sum';
  assert public.donation_equal_split(10, 3) = array[4, 3, 3]::bigint[], 'remainder deterministic';
  perform pg_temp.expect_error('select public.donation_equal_split(2, 3)', 'AMOUNT_TOO_SMALL_TO_SPLIT%');
  perform pg_temp.expect_error('select public.donation_equal_split(100, 0)', 'NO_ELIGIBLE_CENTERS%');
  perform pg_temp.expect_error('select public.donation_equal_split(0, 2)', 'INVALID_AMOUNT%');
  raise notice 'ok: allocation maths';
end $$;

-- ------------------------------------------------------ amount validation

do $$
declare
  v_clinic uuid := (select id from public.donation_eligible_centers() limit 1);
begin
  perform pg_temp.expect_error(format('select pg_temp.new_checkout(%L, 0, %L, 900)', 'specific_center', v_clinic), 'INVALID_AMOUNT%');
  perform pg_temp.expect_error(format('select pg_temp.new_checkout(%L, -500, %L, 901)', 'specific_center', v_clinic), 'INVALID_AMOUNT%');
  perform pg_temp.expect_error(format('select pg_temp.new_checkout(%L, 1999, %L, 902)', 'specific_center', v_clinic), 'INVALID_AMOUNT%');
  perform pg_temp.expect_error(format('select pg_temp.new_checkout(%L, 10000001, %L, 903)', 'specific_center', v_clinic), 'INVALID_AMOUNT%');
  perform pg_temp.expect_error(format('select pg_temp.new_checkout(%L, null, %L, 904)', 'specific_center', v_clinic), 'INVALID_AMOUNT%');
  perform pg_temp.expect_error('select pg_temp.new_checkout(''bogus_mode'', 5000, null, 905)', 'INVALID_REQUEST%');
  raise notice 'ok: amount and mode validation';
end $$;

-- ------------------------------------------------- A. specific centre

do $$
declare
  v_clinic uuid := (select id from public.donation_eligible_centers() limit 1);
  v jsonb;
  v_again jsonb;
  v_row public.donations;
begin
  v := pg_temp.new_checkout('specific_center', 50000, v_clinic, 1);
  select * into v_row from public.donations where id = (v->>'donation_id')::uuid;

  assert v_row.clinic_id = v_clinic, 'specific: clinic saved';
  assert v_row.amount_centavos = 50000 and v_row.amount = 500.00, 'specific: amount';
  assert v_row.payment_environment = 'sandbox' and v_row.payment_provider = 'internal_simulator', 'specific: env';
  assert v_row.payment_status = 'pending' and v_row.status = 'pending', 'specific: pending before payment';
  assert v_row.payment_method = 'GCASH', 'specific: GCash';
  assert v_row.donor_id is null and v_row.name is null and v_row.email is null, 'anonymous: no donor data';
  assert v_row.client_secret_hash <> pg_temp.secret(1), 'secret stored hashed';
  assert jsonb_array_length(v->'allocations') = 1, 'specific: one allocation';
  assert (v->'allocations'->0->>'amount_centavos')::bigint = 50000, 'specific: allocation amount';
  assert v->'allocations'->0->>'allocation_status' = 'awaiting_payment', 'specific: allocation awaiting';

  -- Duplicate submission returns the same donation, no second row.
  v_again := pg_temp.new_checkout('specific_center', 50000, v_clinic, 1);
  assert v_again->>'donation_id' = v->>'donation_id', 'idempotent retry';
  assert (select count(*) from public.donations where idempotency_key = 'test-key-1-0123456789') = 1, 'one row per key';
  assert (select count(*) from public.donation_allocations where donation_id = v_row.id) = 1, 'no duplicate allocations';

  -- Same key with another secret is refused.
  perform pg_temp.expect_error(format(
    'select public.create_donation_checkout(%L, 50000, %L, %L, %L, true, null)',
    'specific_center', v_clinic, 'test-key-1-0123456789', pg_temp.secret(999)), 'INVALID_REQUEST%');

  -- Specific mode requires a centre; unknown centre is not eligible.
  perform pg_temp.expect_error('select pg_temp.new_checkout(''specific_center'', 5000, null, 2)', 'INVALID_REQUEST%');
  perform pg_temp.expect_error(format('select pg_temp.new_checkout(%L, 5000, %L, 3)', 'specific_center', gen_random_uuid()), 'CENTER_NOT_ELIGIBLE%');
  raise notice 'ok: specific centre, idempotency';
end $$;

-- ------------------------------------------------------ B. random centre

do $$
declare
  v jsonb;
  v_reload jsonb;
  v_clinic uuid;
begin
  -- The client cannot choose the "random" centre.
  perform pg_temp.expect_error(format('select pg_temp.new_checkout(%L, 5000, %L, 10)', 'random_center',
    (select id from public.donation_eligible_centers() limit 1)), 'INVALID_REQUEST%');

  v := pg_temp.new_checkout('random_center', 7500, null, 11);
  v_clinic := (v->'allocations'->0->>'clinic_id')::uuid;
  assert jsonb_array_length(v->'allocations') = 1, 'random: one allocation';
  assert exists (select 1 from public.donation_eligible_centers() e where e.id = v_clinic), 'random: eligible';
  assert (select clinic_id from public.donations where id = (v->>'donation_id')::uuid) = v_clinic, 'random: saved';
  assert v->>'mode' = 'random_center', 'random: mode';

  -- "Refresh": reloading never changes the recipient.
  for i in 1..5 loop
    v_reload := public.get_donation_checkout((v->>'donation_id')::uuid, pg_temp.secret(11));
    assert (v_reload->'allocations'->0->>'clinic_id')::uuid = v_clinic, 'random: fixed after refresh';
  end loop;
  raise notice 'ok: random centre';
end $$;

-- ---------------------------------------------------- C. donate to all

do $$
declare
  v jsonb;
  v_n int := (select count(*) from public.donation_eligible_centers());
  v_sum bigint;
begin
  perform pg_temp.expect_error(format('select pg_temp.new_checkout(%L, 5000, %L, 20)', 'equal_distribution',
    (select id from public.donation_eligible_centers() limit 1)), 'INVALID_REQUEST%');

  v := pg_temp.new_checkout('equal_distribution', 100000, null, 21);
  assert jsonb_array_length(v->'allocations') = v_n, 'all: one allocation per eligible centre';
  select sum((a->>'amount_centavos')::bigint) into v_sum from jsonb_array_elements(v->'allocations') a;
  assert v_sum = 100000, 'all: allocations sum exactly to total';
  assert (select clinic_id from public.donations where id = (v->>'donation_id')::uuid) is null, 'all: no single clinic';
  assert (select array_agg((a->>'amount_centavos')::bigint) from jsonb_array_elements(v->'allocations') a)
         = public.donation_equal_split(100000, v_n), 'all: matches split order';

  -- Snapshot: renaming a centre later does not alter this donation.
  update public.clinics set name = name || ' (renamed)'
  where id = (v->'allocations'->0->>'clinic_id')::uuid;
  assert (select clinic_name_snapshot from public.donation_allocations
          where donation_id = (v->>'donation_id')::uuid and sort_order = 1) not like '%(renamed)', 'snapshot kept';
  raise notice 'ok: donate to all (% centres)', v_n;
end $$;

-- ------------------------------------------------------ no eligible centres

savepoint no_centres;
update public.clinics set status = 'closed';
do $$
begin
  perform pg_temp.expect_error('select pg_temp.new_checkout(''random_center'', 5000, null, 30)', 'NO_ELIGIBLE_CENTERS%');
  perform pg_temp.expect_error('select pg_temp.new_checkout(''equal_distribution'', 5000, null, 31)', 'NO_ELIGIBLE_CENTERS%');
  raise notice 'ok: no eligible centres';
end $$;
rollback to savepoint no_centres;

-- ------------------------------------------------------- simulator

do $$
declare
  v jsonb;
  v_id uuid;
  v_row public.donations;
begin
  v := pg_temp.new_checkout('equal_distribution', 100000, null, 40);
  v_id := (v->>'donation_id')::uuid;

  perform pg_temp.expect_error(format('select public.simulate_donation_payment(%L, %L, %L)', v_id, pg_temp.secret(999), 'success'), 'DONATION_NOT_FOUND%');
  perform pg_temp.expect_error(format('select public.simulate_donation_payment(%L, %L, %L)', v_id, pg_temp.secret(40), 'refund'), 'INVALID_REQUEST%');

  v := public.simulate_donation_payment(v_id, pg_temp.secret(40), 'success');
  select * into v_row from public.donations where id = v_id;
  assert v_row.payment_status = 'simulated_paid', 'success: simulated_paid';
  assert v_row.status = 'pending', 'success: never verified';
  assert v_row.payment_confirmed_at is not null, 'success: timestamp';
  assert not exists (select 1 from public.donation_allocations where donation_id = v_id
                     and allocation_status <> 'simulated'), 'success: allocations simulated';

  -- Idempotent repeat; conflicting outcome refused.
  v := public.simulate_donation_payment(v_id, pg_temp.secret(40), 'success');
  perform pg_temp.expect_error(format('select public.simulate_donation_payment(%L, %L, %L)', v_id, pg_temp.secret(40), 'failure'), 'ALREADY_FINALIZED%');
  perform pg_temp.expect_error(format('select public.cancel_donation_checkout(%L, %L)', v_id, pg_temp.secret(40)), 'ALREADY_FINALIZED%');

  -- Failure
  v := pg_temp.new_checkout('random_center', 5000, null, 41);
  v := public.simulate_donation_payment((v->>'donation_id')::uuid, pg_temp.secret(41), 'failure');
  assert v->>'payment_status' = 'failed', 'failure: failed';
  assert (select status from public.donations where id = (v->>'donation_id')::uuid) = 'rejected', 'failure: rejected';
  assert v->'allocations'->0->>'allocation_status' = 'void', 'failure: void allocation';

  -- Cancel (simulator) and donor cancel
  v := pg_temp.new_checkout('random_center', 5000, null, 42);
  v := public.simulate_donation_payment((v->>'donation_id')::uuid, pg_temp.secret(42), 'cancel');
  assert v->>'payment_status' = 'cancelled', 'cancel: cancelled';
  v := pg_temp.new_checkout('random_center', 5000, null, 43);
  v := public.cancel_donation_checkout((v->>'donation_id')::uuid, pg_temp.secret(43));
  assert v->>'payment_status' = 'cancelled', 'donor cancel';
  raise notice 'ok: simulator success / failure / cancel';
end $$;

-- ------------------------------------- eligibility changes during checkout

savepoint eligibility;
do $$
declare
  v_clinic uuid := (select id from public.donation_eligible_centers() limit 1);
  v jsonb;
begin
  v := pg_temp.new_checkout('specific_center', 5000, v_clinic, 50);
  update public.clinics set status = 'closed' where id = v_clinic;
  v := public.simulate_donation_payment((v->>'donation_id')::uuid, pg_temp.secret(50), 'success');
  assert v->>'payment_status' = 'cancelled', 'ineligible: not completed';
  assert v->>'status_reason' like 'Recipient no longer eligible%', 'ineligible: reason';
  raise notice 'ok: recipient became ineligible during checkout';
end $$;
rollback to savepoint eligibility;

-- ------------------------------------------- settings / environments

savepoint settings;
update public.donation_payment_settings set simulator_enabled = false, paymongo_test_enabled = true;
do $$
declare v jsonb;
begin
  v := pg_temp.new_checkout('random_center', 5000, null, 60);
  assert v->>'payment_provider' = 'paymongo', 'paymongo provider when enabled';
  perform pg_temp.expect_error(format('select public.simulate_donation_payment(%L, %L, %L)',
    v->>'donation_id', pg_temp.secret(60), 'success'), 'SIMULATOR_DISABLED%');
  raise notice 'ok: simulator disabled outside simulator mode';
end $$;
update public.donation_payment_settings set environment = 'production', simulator_enabled = false, paymongo_test_enabled = false;
do $$
begin
  perform pg_temp.expect_error('select pg_temp.new_checkout(''random_center'', 5000, null, 61)', 'PAYMENTS_UNAVAILABLE%');
  raise notice 'ok: production refuses checkouts without a live integration';
end $$;
rollback to savepoint settings;

do $$
begin
  perform pg_temp.expect_error(
    'update public.donation_payment_settings set environment = ''production'', simulator_enabled = true',
    '%donation_payment_settings_sandbox_only%');
  raise notice 'ok: simulator cannot be enabled in production';
end $$;

-- ------------------------------------------------- PayMongo webhook path

savepoint paymongo;
update public.donation_payment_settings set simulator_enabled = false, paymongo_test_enabled = true;
do $$
declare
  v jsonb;
  v_id uuid;
  v_row public.donations;
begin
  v := pg_temp.new_checkout('equal_distribution', 100000, null, 70);
  v_id := (v->>'donation_id')::uuid;
  perform public.paymongo_attach_checkout(v_id, 'cs_test_70', 'https://checkout.test/70');
  perform public.paymongo_attach_checkout(v_id, 'cs_test_70b', 'https://checkout.test/70b');
  assert (select provider_checkout_id from public.donations where id = v_id) = 'cs_test_70', 'first session kept';

  assert public.paymongo_record_payment('evt_live', 'checkout_session.payment.paid', 'cs_test_70', 'pay_1', true)
         = 'rejected_environment', 'live event refused';
  assert public.paymongo_record_payment('evt_1', 'checkout_session.payment.paid', 'cs_test_70', 'pay_1', false)
         = 'applied', 'paid applied';
  assert public.paymongo_record_payment('evt_1', 'checkout_session.payment.paid', 'cs_test_70', 'pay_1', false)
         = 'duplicate', 'duplicate event ignored';
  assert public.paymongo_record_payment('evt_2', 'checkout_session.payment.paid', 'cs_test_70', 'pay_1', false)
         = 'already_paid', 'second event no-op';
  assert public.paymongo_record_payment('evt_3', 'checkout_session.payment.paid', 'cs_unknown', 'pay_9', false)
         = 'unknown_checkout', 'unknown checkout';

  select * into v_row from public.donations where id = v_id;
  assert v_row.payment_status = 'paid' and v_row.provider_payment_id = 'pay_1', 'paid recorded';
  assert v_row.status = 'pending', 'PayMongo TEST payment is not verified (not real money)';
  assert not exists (select 1 from public.donation_allocations where donation_id = v_id
                     and allocation_status <> 'simulated'), 'test payment allocations are simulated';
  raise notice 'ok: PayMongo webhook recording';
end $$;
rollback to savepoint paymongo;

-- ------------------------------------------------ integrity guarantees

do $$
declare
  v jsonb := pg_temp.new_checkout('equal_distribution', 100000, null, 80);
  v_id uuid := (v->>'donation_id')::uuid;
begin
  perform pg_temp.expect_error(format('update public.donations set status = ''verified'' where id = %L', v_id),
    '%donations_sandbox_never_verified%');
  raise notice 'ok: sandbox donation can never be verified';
end $$;

savepoint mismatch;
set constraints public.donation_allocations_total_check immediate;
do $$
declare
  v jsonb := pg_temp.new_checkout('equal_distribution', 100000, null, 81);
begin
  perform pg_temp.expect_error(format(
    'update public.donation_allocations set amount_centavos = amount_centavos + 1, amount = (amount_centavos + 1) / 100.0
     where donation_id = %L and sort_order = 1', v->>'donation_id'), 'ALLOCATION_TOTAL_MISMATCH%');
  raise notice 'ok: allocations must equal donation total';
end $$;
rollback to savepoint mismatch;
-- SET CONSTRAINTS is not undone by ROLLBACK TO SAVEPOINT; restore it.
set constraints public.donation_allocations_total_check deferred;

-- -------------------------------------------- authorization (API roles)
-- Runs each attempt as the anon / authenticated API roles. pg_temp helpers
-- are not used here because those roles may not reach this session's
-- temporary schema; failures are detected inline instead.

-- One workflow donation and one legacy-style donation (written the old
-- way, without payment fields), both created as the SQL Editor role.
create temp table t_fixture as
select (pg_temp.new_checkout('random_center', 5000, null, 90)->>'donation_id')::uuid as id,
       (select e.id from public.donation_eligible_centers() e limit 1) as clinic_id;

create temp table t_legacy (id uuid);
with ins as (
  insert into public.donations (amount, status, payment_method)
  values (100, 'pending', 'GCASH')
  returning id
)
insert into t_legacy select id from ins;

do $$
declare
  v_role text;
  v_id uuid := (select id from t_fixture);
  v_legacy uuid := (select id from t_legacy);
  v_clinic uuid := (select clinic_id from t_fixture);
  v_sql text;
  v_attempts text[] := array[
    'insert into public.donations (amount, status, payment_method) values (100, ''verified'', ''GCASH'')',
    format('insert into public.donation_allocations (donation_id, clinic_id, amount) values (%L, %L, 1)', v_id, v_clinic),
    'select public.paymongo_record_payment(''e'', ''t'', ''c'', ''p'', false)',
    format('select public.donation_finalize(%L, ''simulated_paid'', null, ''x'')', v_id),
    format('select public.paymongo_attach_checkout(%L, ''cs'', ''u'')', v_id),
    format('select public.paymongo_get_owned_donation(%L, ''x'')', v_id),
    format('select public.simulate_donation_payment(%L, %L, ''success'')', v_id, 'wrong-secret-' || repeat('y', 40)),
    format('select public.get_donation_checkout(%L, %L)', v_id, 'wrong-secret-' || repeat('y', 40))
  ];
  v_failed boolean;
begin
  foreach v_role in array array['anon', 'authenticated'] loop
    foreach v_sql in array v_attempts loop
      v_failed := false;
      begin
        execute format('set local role %I', v_role);
        if v_role = 'authenticated' then
          perform set_config('request.jwt.claims',
            json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
        end if;
        execute v_sql;
      exception when others then
        v_failed := true;
      end;
      reset role;
      if not v_failed then
        raise exception 'AUTHZ: % was allowed to run: %', v_role, v_sql;
      end if;
    end loop;

    -- Direct UPDATE / DELETE / TRUNCATE: RLS may silently filter them (no
    -- error), the revoked grants or the guard trigger raise; either way
    -- nothing may change. Includes the live project's "Allow update
    -- donations" case: editing a non-money column (the donor name).
    foreach v_sql in array array[
      format('update public.donations set payment_status = ''simulated_paid'', status = ''verified'' where id = %L', v_id),
      format('update public.donations set status = ''verified'' where id = %L', v_legacy),
      format('update public.donations set amount = 999999 where id = %L', v_legacy),
      format('update public.donations set name = ''HACKED'', email = ''x@x'' where id = %L', v_legacy),
      format('update public.donation_allocations set allocation_status = ''paid_out'', provider_transfer_ref = ''x'' where donation_id = %L', v_id),
      format('delete from public.donation_allocations where donation_id = %L', v_id),
      format('delete from public.donations where id = %L', v_id),
      format('delete from public.donations where id = %L', v_legacy),
      'truncate public.donation_allocations',
      'update public.donation_payment_settings set environment = ''production'', simulator_enabled = false, paymongo_test_enabled = false'
    ] loop
      begin
        execute format('set local role %I', v_role);
        execute v_sql;
      exception when others then null;
      end;
      reset role;
    end loop;

    assert (select payment_status from public.donations where id = v_id) = 'pending',
      format('%s could not change payment status', v_role);
    assert (select status from public.donations where id = v_legacy) = 'pending',
      format('%s could not verify a legacy donation', v_role);
    assert (select amount from public.donations where id = v_legacy) = 100,
      format('%s could not change a donation amount', v_role);
    assert (select name from public.donations where id = v_legacy) is null,
      format('%s could not edit donor details', v_role);
    assert exists (select 1 from public.donations where id = v_legacy),
      format('%s could not delete a donation', v_role);
    assert (select count(*) from public.donation_allocations
            where donation_id = v_id and allocation_status = 'awaiting_payment') = 1,
      format('%s could not change or delete allocations', v_role);
    assert (select environment from public.donation_payment_settings) = 'sandbox',
      format('%s could not change payment settings', v_role);
  end loop;
  raise notice 'ok: anon/authenticated cannot fabricate payments';
end $$;

-- ----------------------------------- no write path left, reads intact

do $$
declare
  v_count bigint;
begin
  assert not exists (
    select 1 from pg_policies p
    where p.schemaname = 'public' and p.tablename in ('donations', 'donation_allocations')
      and p.cmd in ('INSERT', 'UPDATE', 'DELETE')
      and p.roles && array['anon', 'authenticated', 'public']::name[]
  ), 'write policies for API roles remain';

  assert not exists (
    select 1 from information_schema.role_table_grants g
    where g.table_schema = 'public'
      and g.table_name in ('donations', 'donation_allocations', 'donation_audit_logs',
                           'payment_provider_events', 'donation_payment_settings')
      and g.grantee in ('anon', 'authenticated', 'PUBLIC')
      and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
  ), 'write grants for API roles remain';

  -- Landing page path: anon reads the public feed and totals (never the
  -- table), and the settings row the donor page needs.
  set local role anon;
  select count(*) into v_count from public.public_donation_feed(100);
  perform 1 from public.public_donation_totals();
  perform 1 from public.donation_payment_settings;
  reset role;
  raise notice 'ok: no write path left; public feed works for anon (% rows)', v_count;
end $$;

-- ------------------------- superadmin cannot settle workflow donations

do $$
declare
  v_admin uuid := (select id from public.profiles where role = 'superadmin' limit 1);
  v_id uuid := (select id from t_fixture);
  v_failed boolean := false;
begin
  if v_admin is null then
    raise notice 'skipped: no superadmin profile to test approve_donation with';
    return;
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- The superadmin dashboard can still read the workflow donation...
  assert exists (select 1 from public.donations where id = v_id), 'superadmin can read donations';

  -- ...but cannot approve, reject or edit it.
  begin
    perform public.approve_donation(v_id);
  exception when others then
    v_failed := sqlerrm like '%settled by the payment workflow%';
  end;
  assert v_failed, 'approve_donation must refuse workflow donations';

  v_failed := false;
  begin
    perform public.reject_donation(v_id);
  exception when others then
    v_failed := sqlerrm like '%settled by the payment workflow%';
  end;
  assert v_failed, 'reject_donation must refuse workflow donations';

  reset role;
  perform set_config('request.jwt.claims', '', true);
  assert (select status from public.donations where id = v_id) = 'pending', 'status unchanged';
  raise notice 'ok: superadmin cannot approve/reject workflow donations';
end $$;

-- ------------------------------------- donor privacy and role protection
-- Actors are three EXISTING profiles, given test roles inside this rolled-
-- back transaction (nothing about them is kept):
--   patient  -- role 'patient', clinic X (patients pick a clinic in the app)
--   admin    -- role 'admin',   clinic X (center admin of X)
--   super    -- role 'superadmin'
-- Fixtures: a named verified donation to X (with an email), an anonymous
-- verified donation to X, a verified donation to Y, and a Donate-to-All
-- workflow donation that has a share for X.

create temp table t_actor as
select
  (array_agg(id order by id))[1] as patient,
  (array_agg(id order by id))[2] as admin,
  (array_agg(id order by id))[3] as super,
  count(*) as n
from (select id from public.profiles order by id limit 3) p;

create temp table t_clinic as
select (array_agg(id order by name, id))[1] as x,
       (array_agg(id order by name, id))[2] as y
from public.donation_eligible_centers();

do $$
declare
  a record := (select t from t_actor t);
  c record := (select t from t_clinic t);
begin
  if a.n < 3 then
    raise exception 'SETUP: need at least 3 rows in profiles to run the privacy tests.';
  end if;
  execute format('update public.profiles set role = %L, clinic_id = %L where id = %L returning ''changed''', 'patient', c.x, a.patient);
  -- One admin per clinic (unique_admin_per_clinic): detach any other admin of X
  -- inside this rolled-back transaction, then make the borrowed profile X's
  -- active admin.
  update public.profiles set clinic_id = null
   where role = 'admin' and clinic_id = c.x and id <> a.admin;
  execute format('update public.profiles set role = %L, clinic_id = %L, status = %L, is_active = true where id = %L returning ''changed''', 'admin', c.x, 'active', a.admin);
  execute format('update public.profiles set role = %L where id = %L returning ''changed''', 'superadmin', a.super);
end $$;

create temp table t_don (label text, id uuid);
with ins as (
  insert into public.donations (name, email, amount, payment_method, status, clinic_id)
  select 'Privacy Test Named Donor', 'private-donor@example.com', 1234, 'GCASH', 'verified', x from t_clinic
  returning id
) insert into t_don select 'named_x', id from ins;
with ins as (
  insert into public.donations (name, email, amount, payment_method, status, clinic_id)
  select null, null, 777, 'GCASH', 'verified', x from t_clinic
  returning id
) insert into t_don select 'anon_x', id from ins;
with ins as (
  insert into public.donations (name, email, amount, payment_method, status, clinic_id)
  select 'Privacy Test Y Donor', 'y-donor@example.com', 555, 'GCASH', 'verified', y from t_clinic
  returning id
) insert into t_don select 'named_y', id from ins;
insert into t_don
select 'split', (pg_temp.new_checkout('equal_distribution', 300000, null, 95)->>'donation_id')::uuid;

do $$
declare
  a record := (select t from t_actor t);
  v_named_x uuid := (select id from t_don where label = 'named_x');
  v_named_y uuid := (select id from t_don where label = 'named_y');
  v_split uuid := (select id from t_don where label = 'split');
  v_r text;
  v_total numeric;
begin
  -- ---------- anonymous visitor
  v_r := pg_temp.as_user('anon', null, 'select count(*)::text from public.donations');
  assert v_r like 'ERROR:%' or v_r = '0', 'anon must not read donations directly: ' || v_r;
  v_r := pg_temp.as_user('anon', null, 'select count(*)::text from public.donation_allocations');
  assert v_r like 'ERROR:%' or v_r = '0', 'anon must not read allocations: ' || v_r;
  v_r := pg_temp.as_user('anon', null,
    'select string_agg(display_name, ''|'') from public.public_donation_feed(100)');
  assert v_r like '%Privacy Test Named Donor%', 'public feed shows the donor display name';
  assert v_r like '%Anonymous%', 'anonymous donation shown as Anonymous';
  assert v_r not like '%@%', 'public feed never contains an email';
  assert pg_get_function_result('public.public_donation_feed(integer)'::regprocedure) not ilike '%email%',
    'public feed has no email column';
  select coalesce(sum(amount), 0) into v_total from public.donations
  where status = 'verified' and payment_environment is distinct from 'sandbox';
  v_r := pg_temp.as_user('anon', null, 'select total_amount::text from public.public_donation_totals()');
  assert v_r::numeric = v_total, 'public totals = verified total';

  -- ---------- patient with clinic X: no donor data
  v_r := pg_temp.as_user('authenticated', a.patient, 'select count(*)::text from public.donations');
  assert v_r = '0' or v_r like 'ERROR:%', 'patient must not read donations: ' || v_r;
  v_r := pg_temp.as_user('authenticated', a.patient, 'select count(*)::text from public.donation_allocations');
  assert v_r = '0' or v_r like 'ERROR:%', 'patient must not read allocations: ' || v_r;
  v_r := pg_temp.as_user('authenticated', a.patient, 'select public.curenurture_is_superadmin()::text');
  assert v_r = 'false', 'patient is not superadmin';

  -- ---------- center admin of X: own center + its Donate-to-All share only
  -- Since v5 (security-test-reports/donation-center-admin-view-v5) center
  -- admins read donations only through the privacy-safe center_admin_donations
  -- view; direct reads of the donations table return nothing for them.
  v_r := pg_temp.as_user('authenticated', a.admin,
    format('select count(*)::text from public.donations where id = %L', v_named_x));
  assert v_r = '0', 'admin has no direct row access to donations (uses the view)';
  v_r := pg_temp.as_user('authenticated', a.admin,
    format('select count(*)::text from public.center_admin_donations where id = %L', v_named_x));
  assert v_r = '1', 'admin sees own center donation';
  v_r := pg_temp.as_user('authenticated', a.admin,
    format('select count(*)::text from public.center_admin_donations where id = %L', v_split));
  assert v_r = '1', 'admin sees Donate-to-All donation with a share for their center';
  v_r := pg_temp.as_user('authenticated', a.admin,
    format('select count(*)::text from public.center_admin_donations where id = %L', v_named_y));
  assert v_r = '0', 'admin must not see another center''s donation';
  v_r := pg_temp.as_user('authenticated', a.admin,
    format('select count(*)::text from public.donation_allocations where donation_id = %L', v_split));
  assert v_r = '1', 'admin sees only their own center''s share';

  -- ---------- superadmin: everything
  v_r := pg_temp.as_user('authenticated', a.super,
    format('select count(*)::text from public.donations where id in (%L, %L, %L)', v_named_x, v_named_y, v_split));
  assert v_r = '3', 'superadmin sees all donations';
  v_r := pg_temp.as_user('authenticated', a.super,
    format('select count(*)::text from public.donation_allocations where donation_id = %L', v_split));
  assert v_r::int = (select count(*) from public.donation_allocations where donation_id = v_split),
    'superadmin sees all allocations';
  -- Superadmin set only in app_metadata (no profile role), like the
  -- Super Admin app's login rule.
  v_r := pg_temp.as_user('authenticated', gen_random_uuid(),
    format('select count(*)::text from public.donations where id = %L', v_named_y), 'superadmin');
  assert v_r = '1', 'app_metadata superadmin can read donations';

  raise notice 'ok: donor privacy';
end $$;

do $$
declare
  a record := (select t from t_actor t);
  c record := (select t from t_clinic t);
  v_r text;
  v_new uuid := gen_random_uuid();
begin
  -- ---------- ordinary user cannot promote themselves
  foreach v_r in array array['superadmin', 'admin', 'SuperAdmin', ' super_admin '] loop
    v_r := pg_temp.as_user('authenticated', a.patient,
      format('update public.profiles set role = %L where id = %L returning ''changed''', v_r, a.patient));
  end loop;
  assert (select role from public.profiles where id = a.patient) = 'patient', 'patient role unchanged';
  v_r := pg_temp.as_user('authenticated', a.patient,
    format('update public.profiles set role = ''superadmin'' where id = %L returning ''changed''', a.patient));
  assert v_r like 'ERROR:%ROLE_CHANGE_BLOCKED%' or v_r = 'OK', 'self-promotion refused: ' || v_r;

  -- ---------- nor change someone else's role, or delete a profile
  v_r := pg_temp.as_user('authenticated', a.patient,
    format('update public.profiles set role = ''patient'' where id = %L returning ''changed''', a.super));
  v_r := pg_temp.as_user('authenticated', a.patient,
    format('delete from public.profiles where id = %L returning ''changed''', a.super));
  assert (select role from public.profiles where id = a.super) = 'superadmin', 'other user role unchanged';

  -- ---------- nor create a privileged profile (own or someone else's)
  v_r := pg_temp.as_user('authenticated', v_new,
    format('insert into public.profiles (id, role) values (%L, %L) returning ''changed''', v_new, 'superadmin'));
  assert v_r like 'ERROR:%', 'self-insert as superadmin refused: ' || v_r;
  v_r := pg_temp.as_user('authenticated', v_new,
    format('insert into public.profiles (id, role) values (%L, %L) returning ''changed''', v_new, ' Admin'));
  assert v_r like 'ERROR:%', 'self-insert as admin refused: ' || v_r;
  v_r := pg_temp.as_user('authenticated', a.patient,
    format('insert into public.profiles (id, role) values (%L, %L) returning ''changed''', gen_random_uuid(), 'patient'));
  assert v_r like 'ERROR:%', 'creating another user''s profile refused: ' || v_r;
  v_r := pg_temp.as_user('anon', null,
    format('insert into public.profiles (id, role) values (%L, %L) returning ''changed''', gen_random_uuid(), 'superadmin'));
  assert v_r like 'ERROR:%', 'anon cannot create profiles: ' || v_r;

  -- ---------- legitimate self-service still passes the guard
  v_r := pg_temp.as_user('authenticated', a.patient,
    format('update public.profiles set full_name = full_name where id = %L returning ''changed''', a.patient));
  assert v_r not like '%ROLE_CHANGE_BLOCKED%' and v_r not like '%PROFILE_WRITE_BLOCKED%',
    'patient may edit own profile: ' || v_r;
  v_r := pg_temp.as_user('authenticated', a.patient,
    format('update public.profiles set clinic_id = %L where id = %L returning ''changed''', c.y, a.patient));
  assert v_r not like '%ROLE_CHANGE_BLOCKED%' and v_r not like '%PROFILE_WRITE_BLOCKED%',
    'patient may choose a clinic: ' || v_r;

  -- ---------- center admin cannot move itself to another center
  v_r := pg_temp.as_user('authenticated', a.admin,
    format('update public.profiles set clinic_id = %L where id = %L returning ''changed''', c.y, a.admin));
  assert (select clinic_id::text from public.profiles where id = a.admin) = c.x::text,
    'admin center unchanged: ' || v_r;
  v_r := pg_temp.as_user('authenticated', a.admin,
    format('update public.profiles set role = ''superadmin'' where id = %L returning ''changed''', a.admin));
  assert (select role from public.profiles where id = a.admin) = 'admin', 'admin cannot promote itself';

  -- ---------- superadmin workflows are not blocked by the guard
  v_r := pg_temp.as_user('authenticated', a.super,
    format('update public.profiles set clinic_id = %L where id = %L returning ''changed''', c.y, a.admin));
  assert v_r not like '%ROLE_CHANGE_BLOCKED%' and v_r not like '%PROFILE_WRITE_BLOCKED%',
    'superadmin may reassign an admin: ' || v_r;
  v_r := pg_temp.as_user('authenticated', a.super,
    format('update public.profiles set role = ''patient'' where id = %L returning ''changed''', a.patient));
  assert v_r not like '%ROLE_CHANGE_BLOCKED%' and v_r not like '%PROFILE_WRITE_BLOCKED%',
    'superadmin may change roles: ' || v_r;
  v_r := pg_temp.as_user('authenticated', v_new,
    format('update public.profiles set role = ''patient'' where id = %L returning ''changed''', a.admin), 'superadmin');
  assert v_r not like '%ROLE_CHANGE_BLOCKED%' and v_r not like '%PROFILE_WRITE_BLOCKED%',
    'app_metadata superadmin passes the guard: ' || v_r;

  raise notice 'ok: only superadmins can change roles';
end $$;

-- ------------------------------------------ totals exclude sandbox

do $$
begin
  assert not exists (
    select 1 from public.donations where payment_environment = 'sandbox' and status = 'verified'
  ), 'no sandbox row is counted by status = verified totals';
  raise notice 'ALL DONATION SANDBOX TESTS PASSED';
end $$;

rollback;

-- Only reached if every check above passed (any failure stops the script
-- with an error). The SQL Editor shows this as the result row.
select 'ALL DONATION SANDBOX TESTS PASSED - all test data rolled back' as result;
