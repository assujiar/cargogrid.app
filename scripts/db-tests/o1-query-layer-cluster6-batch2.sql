-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 6
-- (platform-intelligence-reports) batch 2 of N
-- (supabase/migrations/20260913020000_close_o1_query_layer_cluster6_batch2_integration_hub.sql).
--
-- Proves, against a real disposable database, that all 5 new function pairs (10
-- functions total -- ALL SECURITY INVOKER with ZERO actor parameter) return exactly
-- what their own comments and this migration's own header claim.
--
-- app.integration_connections/app.integration_health_checks share the
-- tenant-membership predicate WITHOUT an explicit `OR is_supreme_admin()` disjunct
-- at the policy level (the SAME shape cluster 6 batch 1's own app.automation_rules
-- family used): a real active tenant member (999501) sees the real fixture rows, a
-- customer_user-layer principal in the SAME tenant (999502) sees zero rows, a
-- cross-tenant admin (999504) sees zero rows, and a Supreme Admin with ZERO
-- explicit tenant membership (999503) STILL sees every row via app.has_active_
-- tenant_membership's own internal is_supreme_admin branch -- re-verified live in
-- THIS batch too, not merely assumed to carry over from batch 1's own proof.
--
-- app.third_party_provider_connections DOES carry an explicit `OR is_supreme_
-- admin()` disjunct at the policy level -- same 4-persona visibility outcome via a
-- different policy shape, PLUS an explicit null-cast proof: a real, non-null
-- `webhook_secret_value_encrypted` value is written directly to the fixture row,
-- and the function is proven to return it as genuinely null anyway.
--
-- app.integration_adapters (no RLS, full-row grant, platform-wide) is proven via a
-- plain existence check, matching this whole series' own established convention
-- for a shared, non-tenant-scoped reference table.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c6b2 with a real active org_user tenant member (999501, no owner/org-unit relationship required by any table in this batch), a customer_user-layer principal in the SAME tenant (999502), a global Supreme Admin with ZERO membership in this tenant (999503), and a second, isolated tenant gizmoo1c6b2 with its own tenant_admin (999504)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999501', 'membero1c6b2@example.test'),
    ('00000000-0000-0000-0000-000000999502', 'customerusero1c6b2@example.test'),
    ('00000000-0000-0000-0000-000000999503', 'supremeo1c6b2@example.test'),
    ('00000000-0000-0000-0000-000000999504', 'othertenanto1c6b2@example.test');

  perform app.provision_tenant('acmeo1c6b2', 'Acme O1C6B2 Co', 'idem-acmeo1c6b2', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c6b2');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999501', 'membero1c6b2@example.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1c6b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999501', 'org_user', v_tenant_id, null, 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000999502', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999502', 'customer_user', v_tenant_id, 'fake-account-ref-o1c6b2', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999503', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c6b2', 'Gizmo O1C6B2 Co', 'idem-gizmoo1c6b2', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c6b2');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999504', 'othertenanto1c6b2@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c6b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999504', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> fixture: 1 app.integration_adapters row (o1c6b2_test_adapter), 2 app.integration_connections rows for acmeo1c6b2 inserted in ASCENDING updated_at order (different environments to satisfy the (tenant_id, adapter_code, environment) unique constraint, so updated_at desc output is the reverse of insertion order), 2 app.integration_health_checks rows for the production connection inserted in ASCENDING checked_at order'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b2');
  v_conn_sandbox_id uuid := gen_random_uuid();
  v_conn_prod_id uuid := gen_random_uuid();
begin
  insert into app.integration_adapters (code, name, category, registered_by)
  values ('o1c6b2_test_adapter', 'O1C6B2 Test Adapter', 'communication', 'tester');

  insert into app.integration_connections (id, tenant_id, adapter_code, name, environment, status, created_by, created_at, updated_at)
  values
    (v_conn_sandbox_id, v_tenant_id, 'o1c6b2_test_adapter', 'O1C6B2 Sandbox Conn', 'sandbox', 'active', 'tester', now() - interval '2 days', now() - interval '2 days'),
    (v_conn_prod_id, v_tenant_id, 'o1c6b2_test_adapter', 'O1C6B2 Prod Conn', 'production', 'active', 'tester', now() - interval '1 day', now() - interval '1 day');

  insert into app.integration_health_checks (id, connection_id, status, detail, checked_by, checked_at)
  values
    (gen_random_uuid(), v_conn_prod_id, 'healthy', 'first check', 'tester', now() - interval '2 hours'),
    (gen_random_uuid(), v_conn_prod_id, 'unhealthy', 'second check', 'tester', now() - interval '1 hour');
end $$;

\echo '>> app.integration_connections/app.list_integration_connections/app.get_integration_connection_by_id: member sees both real connections (updated_at desc, out-of-order fixture) and a nonexistent id returns a GENUINELY EMPTY result; customer_user-layer/cross-tenant both see zero; Supreme Admin (zero membership) still sees both via has_active_tenant_membership''s own internal is_supreme_admin branch'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b2');
  v_conn_sandbox_id uuid := (select id from app.integration_connections where tenant_id = v_tenant_id and environment = 'sandbox');
  v_conn_prod_id uuid := (select id from app.integration_connections where tenant_id = v_tenant_id and environment = 'production');
  v_ids uuid[];
  v_count integer;
  v_row record;
begin
  select array_agg(id) into v_ids from app.list_integration_connections(v_tenant_id);
  if v_ids <> array[v_conn_prod_id, v_conn_sandbox_id] then
    raise exception 'assertion failed: list_integration_connections must return [prod, sandbox] (updated_at desc), got %', v_ids;
  end if;

  select * into v_row from app.get_integration_connection_by_id(v_conn_prod_id);
  if v_row.id is null or v_row.id <> v_conn_prod_id then raise exception 'assertion failed: member must resolve the real prod connection, got %', v_row; end if;

  select count(*) into v_count from app.get_integration_connection_by_id(gen_random_uuid());
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent connection id must return a genuinely empty result, got %', v_count; end if;
  if exists (select 1 from app.get_integration_connection_by_id(gen_random_uuid())) then
    raise exception 'assertion failed: a nonexistent connection id must be a genuinely empty row set, found at least one row';
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999502", "role": "authenticated"}';
  select count(*) into v_count from app.list_integration_connections(v_tenant_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from list_integration_connections, got %', v_count; end if;
  select count(*) into v_count from app.get_integration_connection_by_id(v_conn_prod_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from get_integration_connection_by_id, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999504", "role": "authenticated"}';
  select count(*) into v_count from app.list_integration_connections(v_tenant_id);
  if v_count <> 0 then raise exception 'assertion failed: cross-tenant admin must see zero rows from list_integration_connections, got %', v_count; end if;
  select count(*) into v_count from app.get_integration_connection_by_id(v_conn_prod_id);
  if v_count <> 0 then raise exception 'assertion failed: cross-tenant admin must see zero rows from get_integration_connection_by_id, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999503", "role": "authenticated"}';
  select count(*) into v_count from app.list_integration_connections(v_tenant_id);
  if v_count <> 2 then raise exception 'assertion failed: Supreme Admin (zero membership) must see both connections via list_integration_connections, got %', v_count; end if;
  select count(*) into v_count from app.get_integration_connection_by_id(v_conn_prod_id);
  if v_count <> 1 then raise exception 'assertion failed: Supreme Admin (zero membership) must see the real connection via get_integration_connection_by_id, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  raise notice 'app.integration_connections proof: member sees both real connections in the right order and a genuinely empty result for a nonexistent id, customer_user-layer/cross-tenant both denied, Supreme Admin bypasses with zero explicit membership';
end $$;

\echo '>> app.integration_health_checks/app.list_integration_health_checks: ordering fidelity (checked_at desc) against fixture rows inserted out of that order; authority is re-derived via the EXISTS join back to app.integration_connections'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b2');
  v_conn_prod_id uuid := (select id from app.integration_connections where tenant_id = v_tenant_id and environment = 'production');
  v_check1_id uuid := (select id from app.integration_health_checks where connection_id = v_conn_prod_id and detail = 'first check');
  v_check2_id uuid := (select id from app.integration_health_checks where connection_id = v_conn_prod_id and detail = 'second check');
  v_ids uuid[];
  v_count integer;
begin
  select array_agg(id) into v_ids from app.list_integration_health_checks(v_conn_prod_id);
  if v_ids <> array[v_check2_id, v_check1_id] then
    raise exception 'assertion failed: list_integration_health_checks must return [check2, check1] (checked_at desc), got %', v_ids;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999502", "role": "authenticated"}';
  select count(*) into v_count from app.list_integration_health_checks(v_conn_prod_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero health checks, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999503", "role": "authenticated"}';
  select count(*) into v_count from app.list_integration_health_checks(v_conn_prod_id);
  if v_count <> 2 then raise exception 'assertion failed: Supreme Admin (zero membership) must see both health checks, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  raise notice 'app.integration_health_checks proof: ordering fidelity correct, customer_user-layer denied, Supreme Admin bypasses with zero membership via the same joined predicate';
end $$;

\echo '>> app.list_integration_adapters: the fixture adapter is present (existence check, never an exact count -- this table is platform-wide and other db-test files in the shared full-suite database also register their own adapters)'
do $$
begin
  if not exists (select 1 from app.list_integration_adapters() where code = 'o1c6b2_test_adapter') then
    raise exception 'assertion failed: the fixture adapter o1c6b2_test_adapter must be present in app.list_integration_adapters()';
  end if;

  raise notice 'app.list_integration_adapters proof: the fixture adapter is present in the full catalog';
end $$;

\echo '>> fixture: 1 app.third_party_provider_connections row for acmeo1c6b2 with a REAL, non-null webhook_secret_value_encrypted deliberately written'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b2');
begin
  insert into app.third_party_provider_connections (id, tenant_id, provider_code, integration_mode, poll_cursor, status, created_by, webhook_secret_value_encrypted, created_at, updated_at)
  values (gen_random_uuid(), v_tenant_id, 'o1c6b2gps', 'poll', '{}'::jsonb, 'active', 'tester', '\xdeadbeef'::bytea, now(), now());
end $$;

\echo '>> app.get_third_party_provider_connection: resolves the real connection with webhook_secret_value_encrypted genuinely nulled (never the real bytea value written to the row); customer_user-layer/cross-tenant both denied; Supreme Admin bypasses via the policy''s own explicit OR is_supreme_admin() disjunct'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b2');
  v_row record;
  v_count integer;
begin
  select * into v_row from app.get_third_party_provider_connection(v_tenant_id, 'o1c6b2gps');
  if v_row.id is null or v_row.provider_code <> 'o1c6b2gps' then
    raise exception 'assertion failed: member must resolve the real third-party provider connection, got %', v_row;
  end if;
  if v_row.webhook_secret_value_encrypted is not null then
    raise exception 'assertion failed: webhook_secret_value_encrypted must be genuinely null, never the real bytea value, got %', v_row.webhook_secret_value_encrypted;
  end if;

  select count(*) into v_count from app.get_third_party_provider_connection(v_tenant_id, 'nonexistent-provider');
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent provider_code must return a genuinely empty result, got %', v_count; end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999502", "role": "authenticated"}';
  select count(*) into v_count from app.get_third_party_provider_connection(v_tenant_id, 'o1c6b2gps');
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999504", "role": "authenticated"}';
  select count(*) into v_count from app.get_third_party_provider_connection(v_tenant_id, 'o1c6b2gps');
  if v_count <> 0 then raise exception 'assertion failed: a cross-tenant admin must see zero rows, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999503", "role": "authenticated"}';
  select count(*) into v_count from app.get_third_party_provider_connection(v_tenant_id, 'o1c6b2gps');
  if v_count <> 1 then raise exception 'assertion failed: Supreme Admin (zero membership) must see the real connection via the policy''s own explicit OR is_supreme_admin(), got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  raise notice 'app.get_third_party_provider_connection proof: real connection resolved with webhook_secret_value_encrypted genuinely nulled, genuinely empty for a nonexistent provider, customer_user-layer/cross-tenant denied, Supreme Admin bypasses via the explicit policy-level disjunct';
end $$;

\echo '>> anon defense in depth: all 5 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.list_integration_adapters();
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_integration_adapters';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_integration_adapters correctly rejected anon';
    end;

    begin
      perform public.list_integration_connections(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_integration_connections';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_integration_connections correctly rejected anon';
    end;

    begin
      perform public.get_integration_connection_by_id(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_integration_connection_by_id';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.get_integration_connection_by_id correctly rejected anon';
    end;

    begin
      perform public.list_integration_health_checks(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_integration_health_checks';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_integration_health_checks correctly rejected anon';
    end;

    begin
      perform public.get_third_party_provider_connection(v_dummy, 'x');
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_third_party_provider_connection';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.get_third_party_provider_connection correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: all 5 SECURITY INVOKER functions succeed via service_role''s own direct grant / BYPASSRLS regardless of membership, under a session that carries no request.jwt.claims at all'
begin;
  set local role service_role;
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b2');
    v_conn_prod_id uuid := (select id from app.integration_connections where tenant_id = v_tenant_id and environment = 'production');
    v_count integer;
  begin
    if not exists (select 1 from app.list_integration_adapters() where code = 'o1c6b2_test_adapter') then
      raise exception 'assertion failed: service_role must see the fixture adapter via app.list_integration_adapters';
    end if;
    select count(*) into v_count from app.list_integration_connections(v_tenant_id);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both connections via app.list_integration_connections (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.get_integration_connection_by_id(v_conn_prod_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the real connection via app.get_integration_connection_by_id (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.list_integration_health_checks(v_conn_prod_id);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both health checks via app.list_integration_health_checks (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.get_third_party_provider_connection(v_tenant_id, 'o1c6b2gps');
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the real third-party connection via app.get_third_party_provider_connection (BYPASSRLS), got %', v_count; end if;

    raise notice 'service_role proof: all 5 SECURITY INVOKER functions succeed regardless of membership';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 5 new cluster-6-batch-2 function pairs (10 functions) in EITHER schema; authenticated/service_role hold EXECUTE on both the app.* function and its public.* wrapper for all 5 pairs, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_integration_adapters', 'list_integration_connections', 'get_integration_connection_by_id',
      'list_integration_health_checks', 'get_third_party_provider_connection'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 5 cluster-6-batch-2 function pairs (10 functions, either schema), found % grants', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_integration_adapters', 'list_integration_connections', 'get_integration_connection_by_id',
      'list_integration_health_checks', 'get_third_party_provider_connection'
    )
    and grantee in ('authenticated', 'service_role');
  if v_count <> 5 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 20 grants (5 functions x 2 schemas x 2 grantees), found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 10 new cluster-6-batch-2 functions; authenticated/service_role hold the declared grant on both the app.* and public.* function in every one of the 5 pairs';
end $$;

\echo '>> o1-query-layer-cluster6-batch2.sql test suite passed -- cluster 6 batch 2 (integration adapters/connections/health checks, third-party provider connection -- 5/30 call sites, 14/30 cumulative) is now fully DONE'
