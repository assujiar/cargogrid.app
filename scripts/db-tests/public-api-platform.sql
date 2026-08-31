-- Real, executable test evidence for IAE-009 (Public API Platform, Prompt
-- 337, CG-S14-IAE-009) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000011000001..006.
-- Grep-verified unclaimed against every other *.sql fixture in this
-- directory before use.
--
-- Applies Batch 1/2's own hard-won Tier C lessons from the start (not
-- discovered after the fact this time): live RLS-as-a-forged-session
-- testing (request.jwt.claims + set role authenticated, section 8 below,
-- the same technique scripts/db-tests/ticketing-internal.sql section 5
-- already established) and a REAL two-OS-process concurrency proof for the
-- rate-limit counter's own atomic upsert (section 4), not merely a
-- sequential simulation.
--
-- Does NOT re-test app.create_api_key/app.rotate_api_key/app.revoke_api_key/
-- app.authenticate_api_key/app.api_key_has_scope/app.register_webhook_endpoint
-- etc -- those are PLT-129's own already-covered surface
-- (scripts/db-tests/api-key-webhook.sql). This file covers only what
-- 20260804010000_create_intelligence_public_api_platform.sql actually adds.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: one tenant (iaepubapi) with a Supreme Admin, a tenant_admin (key-management authority), a plain member (no admin authority), a customer_user portal principal, and a second tenant (iaepubapi2) with one lone member for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000011000001', 'supreme@iaepubapi.test'),
    ('00000000-0000-0000-0000-000011000002', 'admin@iaepubapi.test'),
    ('00000000-0000-0000-0000-000011000003', 'member@iaepubapi.test'),
    ('00000000-0000-0000-0000-000011000004', 'portal@iaepubapi.test'),
    ('00000000-0000-0000-0000-000011000005', 'member@iaepubapi2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000011000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaepubapi', 'IAE PubAPI Co', 'idem-iaepubapi', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaepubapi');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaepubapi2', 'IAE PubAPI Co 2', 'idem-iaepubapi2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaepubapi2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000011000002', 'admin@iaepubapi.test', 'Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaepubapi.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000011000002', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000011000003', 'member@iaepubapi.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaepubapi.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000011000004', 'portal@iaepubapi.test', 'Portal Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'portal@iaepubapi.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000011000004', 'customer_user', v_tenant1, 'iae-pubapi-portal-ref', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000011000005', 'member@iaepubapi2.test', 'Member2', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaepubapi2.test'), 'active', 'onboarded', 'tester');
end;
$$;

\echo '>> app.list_api_versions: the real v1 seed is present out of the box'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.list_api_versions() where code = 'v1' and status = 'active';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 seeded active v1 version, got %', v_count;
  end if;
  raise notice 'PASS: v1 is seeded active out of the box';
end;
$$;

\echo '>> app.register_api_version / app.set_api_version_status: Supreme-only, idempotent by code, real audited deprecate/sunset transition, structural validation'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000011000001';
  v_admin uuid := '00000000-0000-0000-0000-000011000002';
  v_v2 app.api_versions;
  v_v2_again app.api_versions;
begin
  begin
    perform app.register_api_version('v2', 'active', null, 'preview', v_admin, 'tester');
    raise exception 'assertion failed: expected insufficient_authority -- a non-Supreme actor must not register an API version';
  exception
    when insufficient_privilege then null;
  end;

  select * into v_v2 from app.register_api_version('v2', 'active', null, 'preview', v_supreme, 'tester');
  if v_v2.status <> 'active' then raise exception 'assertion failed: expected v2 to register active, got %', v_v2.status; end if;

  select * into v_v2_again from app.register_api_version('v2', 'deprecated', null, 'ignored -- already exists', v_supreme, 'tester');
  if v_v2_again.status <> 'active' then
    raise exception 'assertion failed: a repeated register for an already-registered code must return the EXISTING row unchanged, got status=%', v_v2_again.status;
  end if;

  begin
    perform app.set_api_version_status('v2', 'sunset', null, v_supreme, 'tester');
    raise exception 'assertion failed: expected api_version_missing_sunset_at -- a sunset status requires a real sunset_at';
  exception
    when check_violation then
      if sqlerrm !~ 'api_version_missing_sunset_at' then raise; end if;
  end;

  perform app.set_api_version_status('v2', 'deprecated', null, v_supreme, 'tester');
  perform app.set_api_version_status('v2', 'sunset', now() + interval '90 days', v_supreme, 'tester');
  if (select status from app.api_versions where code = 'v2') <> 'sunset' then
    raise exception 'assertion failed: v2 should now be sunset';
  end if;
  if (select sunset_at from app.api_versions where code = 'v2') is null then
    raise exception 'assertion failed: a sunset version must carry a real sunset_at';
  end if;

  begin
    perform app.set_api_version_status('v404', 'deprecated', null, v_supreme, 'tester');
    raise exception 'assertion failed: expected api_version_not_found for a genuinely nonexistent code';
  exception
    when no_data_found then null;
  end;

  raise notice 'PASS: register/set_api_version_status -- Supreme-only, idempotent register, real audited active->deprecated->sunset transition, structural validation';
end;
$$;

\echo '>> setup: a real API key for the rate-limit and gateway tests below (INTHUB:View scope, rate_limit_per_minute=3)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaepubapi');
  v_supreme uuid := '00000000-0000-0000-0000-000011000001';
  v_created record;
begin
  select * into v_created from app.create_api_key(v_tenant1, 'Rate Limit Test Key', '["INTHUB:View"]'::jsonb, null, 3, v_supreme, 'tester');
  create temporary table tmp_pubapi_key (raw_key text, key_id uuid, tenant_id uuid);
  insert into tmp_pubapi_key values (v_created.raw_key, v_created.id, v_tenant1);
end;
$$;

\echo '>> app.check_and_increment_api_key_rate_limit: sequential proof -- exactly 3 allowed, the 4th within the same minute denied, remaining decrements correctly; a null rate_limit_per_minute is always unlimited'
do $$
declare
  -- psql does not interpolate :variables inside a dollar-quoted do-block body --
  -- re-derive by business key from the temp table instead (the more common
  -- convention this repository's own db-tests already established for this exact
  -- limitation).
  v_key_id uuid := (select key_id from tmp_pubapi_key);
  v_r record;
  v_unlimited_key uuid;
  v_i integer;
begin
  select * into v_r from app.check_and_increment_api_key_rate_limit(v_key_id);
  if not v_r.allowed or v_r.remaining <> 2 then raise exception 'assertion failed: call 1/3 expected allowed=true remaining=2, got allowed=% remaining=%', v_r.allowed, v_r.remaining; end if;

  select * into v_r from app.check_and_increment_api_key_rate_limit(v_key_id);
  if not v_r.allowed or v_r.remaining <> 1 then raise exception 'assertion failed: call 2/3 expected allowed=true remaining=1, got allowed=% remaining=%', v_r.allowed, v_r.remaining; end if;

  select * into v_r from app.check_and_increment_api_key_rate_limit(v_key_id);
  if not v_r.allowed or v_r.remaining <> 0 then raise exception 'assertion failed: call 3/3 expected allowed=true remaining=0, got allowed=% remaining=%', v_r.allowed, v_r.remaining; end if;

  select * into v_r from app.check_and_increment_api_key_rate_limit(v_key_id);
  if v_r.allowed then raise exception 'assertion failed: call 4/3 (over the limit) expected allowed=false, got true'; end if;

  select id into v_unlimited_key from app.api_keys where id <> v_key_id and rate_limit_per_minute is null limit 1;
  if v_unlimited_key is null then
    -- No pre-existing unlimited key in this fixture -- create one directly to prove the null-limit path.
    select id into v_unlimited_key from app.create_api_key((select tenant_id from app.api_keys where id = v_key_id), 'Unlimited Key', '["INTHUB:View"]'::jsonb, null, null, '00000000-0000-0000-0000-000011000001', 'tester');
  end if;
  for v_i in 1..20 loop
    select * into v_r from app.check_and_increment_api_key_rate_limit(v_unlimited_key);
    if not v_r.allowed or v_r.limit_per_minute is not null or v_r.remaining is not null then
      raise exception 'assertion failed: a null rate_limit_per_minute must always be allowed with limit_per_minute/remaining both null, got allowed=% limit=% remaining=% (iteration %)', v_r.allowed, v_r.limit_per_minute, v_r.remaining, v_i;
    end if;
  end loop;

  raise notice 'PASS: sequential rate-limit enforcement is exact (3 allowed, 4th denied, remaining decrements correctly); a null rate_limit_per_minute is genuinely unlimited';
end;
$$;

\echo '>> REAL two-process concurrency proof: a rate_limit_per_minute=1 key raced by two genuinely concurrent OS processes in the SAME window must yield exactly one allowed=true and one allowed=false -- never both true (a lost update) and never both false'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaepubapi');
  v_supreme uuid := '00000000-0000-0000-0000-000011000001';
  v_created record;
begin
  select * into v_created from app.create_api_key(v_tenant1, 'Race Key', '["INTHUB:View"]'::jsonb, null, 1, v_supreme, 'tester');
  create temporary table tmp_pubapi_race_key (key_id uuid);
  insert into tmp_pubapi_race_key values (v_created.id);
end;
$$;

select key_id as pubapi_race_key_id from tmp_pubapi_race_key \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as pubapi_race_bpid \gset

\set race_sql_a 'SELECT allowed FROM app.check_and_increment_api_key_rate_limit(''' :pubapi_race_key_id ''');'
\set race_sql_b 'SELECT allowed FROM app.check_and_increment_api_key_rate_limit(''' :pubapi_race_key_id ''');'
\set race_out_a '/tmp/cargogrid-pubapi-race-a-' :pubapi_race_bpid '.out'
\set race_out_b '/tmp/cargogrid-pubapi-race-b-' :pubapi_race_bpid '.out'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A :race_out_a
\setenv RACE_OUT_B :race_out_b

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

-- RGL-BLK-005 fix: this used to smuggle the two PID-suffixed PATHS and read
-- them with pg_read_file() inside the do block -- but pg_read_file() reads the
-- *server's* filesystem, while the helper above writes its race-output files
-- on the *client's*. Identical locally (same host), genuinely different in CI
-- (Postgres in its own Docker service container). \set's backtick form runs
-- client-side, so it is captured here, before the do block.
\set out_a `cat "$RACE_OUT_A"`
\set out_b `cat "$RACE_OUT_B"`
select set_config('cargogrid.pubapi_race_out_a', :'out_a', false),
       set_config('cargogrid.pubapi_race_out_b', :'out_b', false);

do $$
declare
  v_key_id uuid;
  v_out_a text;
  v_out_b text;
  v_true_count integer := 0;
  v_false_count integer := 0;
  v_total_requests integer;
begin
  select key_id into v_key_id from tmp_pubapi_race_key;

  v_out_a := current_setting('cargogrid.pubapi_race_out_a');
  v_out_b := current_setting('cargogrid.pubapi_race_out_b');

  if trim(both E' \n\r\t' from v_out_a) = 't' then v_true_count := v_true_count + 1; else v_false_count := v_false_count + 1; end if;
  if trim(both E' \n\r\t' from v_out_b) = 't' then v_true_count := v_true_count + 1; else v_false_count := v_false_count + 1; end if;

  if v_true_count <> 1 or v_false_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE allowed=true and ONE allowed=false for a rate_limit_per_minute=1 key raced by two genuinely concurrent processes -- got true_count=% false_count=% (A=[%] B=[%])', v_true_count, v_false_count, v_out_a, v_out_b;
  end if;

  select request_count into v_total_requests from app.api_key_rate_limit_windows where api_key_id = v_key_id and window_start = date_trunc('minute', now());
  if v_total_requests <> 2 then
    raise exception 'assertion failed: expected the shared window''s own request_count to be exactly 2 (both concurrent attempts counted, no lost update) -- got %', v_total_requests;
  end if;

  raise notice 'PASS: genuine two-process concurrent race on the same rate-limited key -- exactly one winner (allowed=true), one loser (allowed=false), zero lost updates (request_count=2)';
end;
$$;

\echo '>> app.authenticate_and_authorize_api_request: all four real outcomes (ok, unauthenticated, forbidden_scope, rate_limited) -- never a raised exception for any of them'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaepubapi');
  v_supreme uuid := '00000000-0000-0000-0000-000011000001';
  v_created record;
  v_result record;
begin
  select * into v_created from app.create_api_key(v_tenant1, 'Gateway Outcome Key', '["INTHUB:View"]'::jsonb, null, 1, v_supreme, 'tester');

  select * into v_result from app.authenticate_and_authorize_api_request(v_created.raw_key, 'INTHUB:View');
  if v_result.outcome <> 'ok' or v_result.api_key_id <> v_created.id or v_result.tenant_id <> v_tenant1 or v_result.created_by_auth_user_id <> v_supreme then
    raise exception 'assertion failed: expected outcome=ok with the real api_key_id/tenant_id/created_by_auth_user_id, got %', row_to_json(v_result);
  end if;

  select * into v_result from app.authenticate_and_authorize_api_request('cgk_totallybogusnonexistentkey', 'INTHUB:View');
  if v_result.outcome <> 'unauthenticated' or v_result.api_key_id is not null then
    raise exception 'assertion failed: expected outcome=unauthenticated with a null api_key_id for a nonexistent raw key, got %', row_to_json(v_result);
  end if;

  select * into v_result from app.authenticate_and_authorize_api_request(v_created.raw_key, 'FIN:Configure');
  if v_result.outcome <> 'forbidden_scope' or v_result.created_by_auth_user_id is not null then
    raise exception 'assertion failed: expected outcome=forbidden_scope with a null created_by_auth_user_id (never dispatched) for a scope the key does not carry, got %', row_to_json(v_result);
  end if;

  -- Limit is 1/minute and the very first call above already consumed it.
  select * into v_result from app.authenticate_and_authorize_api_request(v_created.raw_key, 'INTHUB:View');
  if v_result.outcome <> 'rate_limited' then
    raise exception 'assertion failed: expected outcome=rate_limited on the second call against a 1/minute key, got %', v_result.outcome;
  end if;

  raise notice 'PASS: app.authenticate_and_authorize_api_request reports all four real outcomes correctly, never raising for any of them';
end;
$$;

\echo '>> app.list_webhook_event_types: reads the real, live app.webhook_event_types registry exactly (never a fabricated/cached list) -- this migration seeds no real domain event type of its own (IAE-012/Prompt 340''s own job), but api-key-webhook.sql''s own test event types are real rows this function must also surface when the full suite runs in sequence against one shared database'
do $$
declare
  v_from_function integer;
  v_from_table integer;
  v_new_code text := 'iae009.smoke.event';
begin
  select count(*) into v_from_function from app.list_webhook_event_types();
  select count(*) into v_from_table from app.webhook_event_types;
  if v_from_function <> v_from_table then
    raise exception 'assertion failed: app.list_webhook_event_types returned % rows but app.webhook_event_types itself has % -- must read the real table exactly, not a stale/partial view', v_from_function, v_from_table;
  end if;

  -- Registering one more real event type and re-reading proves this is a live read,
  -- not a value fixed at some earlier point.
  perform app.register_webhook_event_type(v_new_code, 'IAE-009 smoke event', 'INTHUB', '00000000-0000-0000-0000-000011000001', 'tester');
  if not exists (select 1 from app.list_webhook_event_types() where code = v_new_code) then
    raise exception 'assertion failed: a freshly-registered event type must appear in the very next app.list_webhook_event_types() call';
  end if;

  raise notice 'PASS: app.list_webhook_event_types reads the real, live registry exactly (% row(s) at this point), including a freshly-registered code', v_from_table + 1;
end;
$$;

\echo '>> app.list_api_logs_for_tenant: authority-gated (a plain member without admin authority is denied), cross-tenant caller denied, real rows returned for the admin, cursor pagination (before) narrows correctly'
-- created_at defaults to now(), the TRANSACTION timestamp -- identical for every
-- statement inside one transaction, regardless of an intervening pg_sleep(). Each
-- record_api_request call below is therefore its own top-level statement (its own
-- implicit autocommit transaction) so the two log rows get genuinely different
-- created_at values, the real precondition app.list_api_logs_for_tenant's own
-- created_at < p_before cursor comparison needs.
select app.record_api_request(gen_random_uuid(), (select id from app.tenants where slug = 'iaepubapi'), null, 'api_key', (select key_id from tmp_pubapi_key), 'rest', 'test_op_1', 'GET', '/api/v1/status', null, 200, 'success', null, null, 12);
select pg_sleep(1);
select app.record_api_request(gen_random_uuid(), (select id from app.tenants where slug = 'iaepubapi'), null, 'api_key', (select key_id from tmp_pubapi_key), 'rest', 'test_op_2', 'GET', '/api/v1/status', null, 200, 'success', null, null, 8);

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaepubapi');
  v_admin uuid := '00000000-0000-0000-0000-000011000002';
  v_member uuid := '00000000-0000-0000-0000-000011000003';
  v_outsider uuid := '00000000-0000-0000-0000-000011000005';
  v_log2 app.api_logs;
  v_count integer;
begin
  select * into v_log2 from app.api_logs where tenant_id = v_tenant1 and operation = 'test_op_2';

  begin
    perform app.list_api_logs_for_tenant(v_tenant1, v_member, 20, null);
    raise exception 'assertion failed: expected insufficient_authority -- a plain member without Supreme/tenant_admin authority must not read API logs';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.list_api_logs_for_tenant(v_tenant1, v_outsider, 20, null);
    raise exception 'assertion failed: expected insufficient_authority -- a tenant-2 outsider must not read tenant-1''s own API logs';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into v_count from app.list_api_logs_for_tenant(v_tenant1, v_admin, 20, null) where operation in ('test_op_1', 'test_op_2');
  if v_count <> 2 then
    raise exception 'assertion failed: expected the admin to see both real seeded log rows, got %', v_count;
  end if;

  select count(*) into v_count from app.list_api_logs_for_tenant(v_tenant1, v_admin, 20, v_log2.created_at) where operation = 'test_op_1';
  if v_count <> 1 then
    raise exception 'assertion failed: cursor-paginating before log 2''s own created_at should still surface log 1, got % rows', v_count;
  end if;

  raise notice 'PASS: app.list_api_logs_for_tenant is authority-gated (member and cross-tenant outsider both denied), the real admin sees real rows, cursor pagination narrows correctly';
end;
$$;

\echo '>> ISS-2026-147 item 2: the per-connector filter IAE-013 claimed and never built. A second real API key on the same tenant proves p_api_key_id isolates one connector''s history; a key id from ANOTHER tenant raises api_key_not_found rather than returning an empty list, so the filter is not an existence oracle'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaepubapi');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaepubapi2');
  v_supreme uuid := '00000000-0000-0000-0000-000011000001';
begin
  perform app.create_api_key(v_tenant1, 'Second Connector Key', '["INTHUB:View"]'::jsonb, null, null, v_supreme, 'tester');
  perform app.create_api_key(v_tenant2, 'Foreign Tenant Connector Key', '["INTHUB:View"]'::jsonb, null, null, v_supreme, 'tester');
end;
$$;

select app.record_api_request(gen_random_uuid(), (select id from app.tenants where slug = 'iaepubapi'), null, 'api_key', (select id from app.api_keys where tenant_id = (select id from app.tenants where slug = 'iaepubapi') and name = 'Second Connector Key'), 'rest', 'test_op_connector_b', 'GET', '/api/v1/status', null, 200, 'success', null, null, 5);

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaepubapi');
  v_admin uuid := '00000000-0000-0000-0000-000011000002';
  v_key_a uuid := (select key_id from tmp_pubapi_key);
  v_key_b uuid := (select id from app.api_keys where tenant_id = (select id from app.tenants where slug = 'iaepubapi') and name = 'Second Connector Key');
  v_foreign_key uuid;
  v_count integer;
begin
  -- Unfiltered still sees everything -- the filter is opt-in, and this proves the default
  -- behaviour every pre-existing caller relies on did not change.
  select count(*) into v_count from app.list_api_logs_for_tenant(v_tenant1, v_admin, 100, null)
  where operation in ('test_op_1', 'test_op_2', 'test_op_connector_b');
  if v_count <> 3 then
    raise exception 'assertion failed: the unfiltered list must still return all 3 seeded rows, got %', v_count;
  end if;

  -- Key A's history is key A's alone. This is the whole finding: before this fix, a tenant
  -- admin running two connectors could not separate them at all.
  select count(*) into v_count from app.list_api_logs_for_tenant(v_tenant1, v_admin, 100, null, v_key_a)
  where operation in ('test_op_1', 'test_op_2', 'test_op_connector_b');
  if v_count <> 2 then
    raise exception 'assertion failed: filtering to key A must return exactly its own 2 rows, got %', v_count;
  end if;
  if exists (
    select 1 from app.list_api_logs_for_tenant(v_tenant1, v_admin, 100, null, v_key_a) l
    where l.operation = 'test_op_connector_b'
  ) then
    raise exception 'assertion failed: key A''s filtered history must not contain key B''s request';
  end if;

  select count(*) into v_count from app.list_api_logs_for_tenant(v_tenant1, v_admin, 100, null, v_key_b)
  where operation in ('test_op_1', 'test_op_2', 'test_op_connector_b');
  if v_count <> 1 then
    raise exception 'assertion failed: filtering to key B must return exactly its own 1 row, got %', v_count;
  end if;

  -- The filter composes with the existing cursor rather than replacing it.
  select count(*) into v_count from app.list_api_logs_for_tenant(
    v_tenant1, v_admin, 100,
    (select created_at from app.api_logs where tenant_id = v_tenant1 and operation = 'test_op_2'),
    v_key_a
  ) where operation in ('test_op_1', 'test_op_2');
  if v_count <> 1 then
    raise exception 'assertion failed: p_api_key_id and p_before must compose (expected only test_op_1), got % rows', v_count;
  end if;

  -- Not an oracle: a real key belonging to the OTHER tenant raises, rather than returning an
  -- empty list a caller could read as "no such key". A nonexistent id raises identically, so
  -- the two cases are indistinguishable from outside.
  -- The control is a KNOWN foreign key created by this block's own setup, never whichever key
  -- another test file happened to leave in the shared database first.
  select id into v_foreign_key from app.api_keys where tenant_id <> v_tenant1 and name = 'Foreign Tenant Connector Key';
  if v_foreign_key is null then
    raise exception 'assertion failed: the foreign-tenant API key this block created is missing';
  end if;
  begin
    perform app.list_api_logs_for_tenant(v_tenant1, v_admin, 20, null, v_foreign_key);
    raise exception 'assertion failed: expected api_key_not_found for another tenant''s API key';
  exception when no_data_found then
    if sqlerrm not like 'api_key_not_found%' then raise; end if;
  end;
  begin
    perform app.list_api_logs_for_tenant(v_tenant1, v_admin, 20, null, gen_random_uuid());
    raise exception 'assertion failed: expected api_key_not_found for an id that exists nowhere';
  exception when no_data_found then
    if sqlerrm not like 'api_key_not_found%' then raise; end if;
  end;

  raise notice 'PASS: ISS-2026-147 item 2 -- per-connector API-log filtering isolates correctly, composes with the cursor, leaves the unfiltered default unchanged, and refuses another tenant''s key id indistinguishably from a nonexistent one';
end;
$$;

\echo '>> ATW-032 (ISS-2026-032) self-caught regression, live forged-session proof: a genuinely authenticated session may not claim to act as a DIFFERENT identity when calling app.list_api_logs_for_tenant, even one that genuinely holds admin authority for the target tenant'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaepubapi');
  v_member uuid := '00000000-0000-0000-0000-000011000003';
  v_admin uuid := '00000000-0000-0000-0000-000011000002';
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000011000003", "role": "authenticated"}', false);
  set role authenticated;

  begin
    -- The real session identity is v_member; this call CLAIMS to act as v_admin (who
    -- genuinely does hold admin authority) -- must be refused as impersonation, never
    -- silently honored just because the CLAIMED identity would otherwise be allowed.
    perform app.list_api_logs_for_tenant(v_tenant1, v_admin, 20, null);
    raise exception 'assertion failed: expected actor_identity_mismatch -- session % must not be able to claim identity % (ATW-032/ISS-2026-032)', v_member, v_admin;
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: app.list_api_logs_for_tenant refuses a genuine authenticated session claiming a different identity (actor_identity_mismatch), even one that would otherwise pass the admin-authority check -- the self-caught rbac-enforcement.sql finding is now closed';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-009 function; authenticated has no direct INSERT/UPDATE/DELETE on app.api_key_rate_limit_windows or app.api_versions, and zero SELECT on app.api_key_rate_limit_windows'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'check_and_increment_api_key_rate_limit', 'register_api_version', 'set_api_version_status',
    'list_api_versions', 'authenticate_and_authorize_api_request', 'list_webhook_event_types',
    'list_api_logs_for_tenant', 'touch_api_versions_row'
  ];
begin
  foreach v_fn in array v_new_functions loop
    if exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon'
    ) then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  if exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'app' and table_name = 'api_key_rate_limit_windows' and grantee = 'authenticated'
  ) then
    raise exception 'assertion failed: authenticated must hold ZERO privilege of any kind on app.api_key_rate_limit_windows';
  end if;

  if exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'app' and table_name = 'api_versions' and grantee = 'authenticated'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  ) then
    raise exception 'assertion failed: authenticated must hold SELECT-only on app.api_versions, never INSERT/UPDATE/DELETE';
  end if;

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-009 function; authenticated holds zero privilege on app.api_key_rate_limit_windows and SELECT-only on app.api_versions';
end;
$$;

\echo '>> live forged-session RLS probe (request.jwt.claims + set role authenticated): app.api_versions is a deliberately broadly-readable global registry (mirrors app.webhook_event_types'' own precedent, not tenant data) -- even a customer_user-layer portal principal can read it; app.api_key_rate_limit_windows is blocked outright at the grant layer for every authenticated role, customer_user layer included'
do $$
declare
  v_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000011000004", "role": "authenticated"}', false);
  set role authenticated;

  select count(*) into v_count from app.api_versions where code = 'v1';
  if v_count <> 1 then
    raise exception 'assertion failed: expected a customer_user-layer principal to see the real, globally-readable v1 row via raw RLS (this registry is deliberately NOT tenant-scoped or customer_user-excluded), got %', v_count;
  end if;

  begin
    perform count(*) from app.api_key_rate_limit_windows;
    raise exception 'assertion failed: expected a permission-denied error reading app.api_key_rate_limit_windows as authenticated -- it carries zero grant of any kind';
  exception
    when insufficient_privilege then null;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: app.api_versions is genuinely, deliberately readable by every authenticated principal including the customer_user layer (disclosed design, mirrors app.webhook_event_types); app.api_key_rate_limit_windows refuses a raw authenticated read outright';
end;
$$;

\echo '>> public-api-platform.sql: ALL PASSED'
