-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 6
-- (platform-intelligence-reports) batch 3 of N
-- (supabase/migrations/20260913030000_close_o1_query_layer_cluster6_batch3_reports.sql).
--
-- Proves, against a real disposable database, that all 5 new function pairs (10
-- functions total -- ALL SECURITY INVOKER with ZERO actor parameter) return exactly
-- what their own comments and this migration's own header claim.
--
-- app.report_types/app.report_type_versions are no-RLS, platform-wide tables --
-- proven via existence checks against uniquely-named fixture rows (never an exact
-- count, since other db-test files in the shared full-suite database also register
-- their own report types), plus the get-by-code-vs-list-active distinction:
-- app.get_report_type_by_code resolves a RETIRED fixture type that app.list_
-- active_report_types correctly excludes.
--
-- app.report_runs shares the tenant-membership-with-explicit-supreme-admin-disjunct
-- predicate this series has closed many times before; app.list_report_runs' own
-- optional p_report_type_code filter is proven to narrow correctly against 2
-- distinct fixture types.
--
-- app.saved_report_views is this batch's most important proof: a genuinely
-- 3-branch predicate (supreme-admin bypass, owner-row-plus-membership, or
-- tenant-shared-row-plus-membership) is exercised with a SECOND real tenant
-- member (999602, NOT the owner of either fixture row) who must see the
-- tenant-shared view but NOT the private one -- the specific distinction a
-- hand-rolled reproduction of this predicate could easily get wrong, which is
-- exactly why the new function relies entirely on live RLS instead.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c6b3 with two real active org_user tenant members (999601 the eventual view owner, 999602 a non-owner member in the SAME tenant), a customer_user-layer principal in the SAME tenant (999603), a global Supreme Admin with ZERO membership in this tenant (999604), and a second, isolated tenant gizmoo1c6b3 with its own tenant_admin (999605)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999601', 'ownero1c6b3@example.test'),
    ('00000000-0000-0000-0000-000000999602', 'membero1c6b3@example.test'),
    ('00000000-0000-0000-0000-000000999603', 'customerusero1c6b3@example.test'),
    ('00000000-0000-0000-0000-000000999604', 'supremeo1c6b3@example.test'),
    ('00000000-0000-0000-0000-000000999605', 'othertenanto1c6b3@example.test');

  perform app.provision_tenant('acmeo1c6b3', 'Acme O1C6B3 Co', 'idem-acmeo1c6b3', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c6b3');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999601', 'ownero1c6b3@example.test', 'Owner', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownero1c6b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999601', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999602', 'membero1c6b3@example.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1c6b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999602', 'org_user', v_tenant_id, null, 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000999603', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999603', 'customer_user', v_tenant_id, 'fake-account-ref-o1c6b3', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999604', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c6b3', 'Gizmo O1C6B3 Co', 'idem-gizmoo1c6b3', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c6b3');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999605', 'othertenanto1c6b3@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c6b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999605', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> fixture: 2 uniquely-named app.report_types rows (o1c6b3_active, status=active; o1c6b3_retired, status=retired) and 3 app.report_type_versions rows -- o1c6b3_active gets version 2 inserted BEFORE version 1 (so version_number desc output is the reverse of insertion order), o1c6b3_retired gets its own version 1 row too, mirroring the CURRENT app.register_report_type''s own invariant (confirmed live at 20260802010000_create_intelligence_reporting_engine.sql:182-183 and its own comment: "every report type ... always has a real version history from the moment it exists") -- scripts/db-tests/reporting-engine.sql asserts this invariant holds for every row in the shared table, so a fixture report_types row with no matching version would break that sibling test under the full db:test suite'
do $$
begin
  insert into app.report_types (code, name, description, source_function, registered_by)
  values
    ('o1c6b3_active', 'O1C6B3 Active Type', 'a test report type', 'get_dashboard_o1c6b3', 'tester'),
    ('o1c6b3_retired', 'O1C6B3 Retired Type', 'a test retired report type', 'get_dashboard_o1c6b3_retired', 'tester');
  update app.report_types set status = 'retired' where code = 'o1c6b3_retired';

  insert into app.report_type_versions (report_type_code, version_number, source_function, description, published_by, published_at)
  values
    ('o1c6b3_active', 2, 'get_dashboard_o1c6b3', 'v2 description', 'tester', now() - interval '1 day'),
    ('o1c6b3_active', 1, 'get_dashboard_o1c6b3', 'v1 description', 'tester', now() - interval '2 days'),
    ('o1c6b3_retired', 1, 'get_dashboard_o1c6b3_retired', 'v1 description', 'tester', now() - interval '2 days');
end $$;

\echo '>> app.list_active_report_types / app.get_report_type_by_code: the active fixture type is present in the active list; the retired fixture type is EXCLUDED from the active list but still resolves by code (no status filter) -- both checked by existence, never an exact count, since this table is platform-wide'
do $$
declare
  v_row record;
begin
  if not exists (select 1 from app.list_active_report_types() where code = 'o1c6b3_active') then
    raise exception 'assertion failed: the active fixture type o1c6b3_active must be present in app.list_active_report_types()';
  end if;
  if exists (select 1 from app.list_active_report_types() where code = 'o1c6b3_retired') then
    raise exception 'assertion failed: the retired fixture type o1c6b3_retired must be EXCLUDED from app.list_active_report_types()';
  end if;

  select * into v_row from app.get_report_type_by_code('o1c6b3_retired');
  if v_row.code is null or v_row.status <> 'retired' then
    raise exception 'assertion failed: get_report_type_by_code must resolve the retired type despite no status filter, got %', v_row;
  end if;
end $$;

\echo '>> app.get_report_type_by_code: a nonexistent code returns a GENUINELY EMPTY result'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.get_report_type_by_code('o1c6b3_nonexistent');
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent code must return a genuinely empty result, got %', v_count; end if;
  if exists (select 1 from app.get_report_type_by_code('o1c6b3_nonexistent')) then
    raise exception 'assertion failed: a nonexistent code must be a genuinely empty row set, found at least one row';
  end if;

  raise notice 'app.report_types proof: active fixture present in active list, retired fixture excluded from active list but resolves by code, nonexistent code genuinely empty';
end $$;

\echo '>> app.list_report_type_versions: ordering fidelity (version_number desc) against fixture rows inserted with version 2 BEFORE version 1'
do $$
declare
  v_versions integer[];
begin
  select array_agg(version_number) into v_versions from app.list_report_type_versions('o1c6b3_active');
  if v_versions <> array[2, 1] then
    raise exception 'assertion failed: list_report_type_versions must return [2, 1] (version_number desc), got %', v_versions;
  end if;

  raise notice 'app.report_type_versions proof: ordering fidelity correct regardless of physical insertion order';
end $$;

\echo '>> fixture: 2 app.report_runs rows for acmeo1c6b3 against o1c6b3_active inserted in ASCENDING requested_at order (so requested_at desc output is the reverse of insertion order), plus 1 row against o1c6b3_retired (a real, distinct report_type_code) -- proving app.list_report_runs'' own optional p_report_type_code filter narrows correctly'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b3');
  v_run_a1_id uuid := gen_random_uuid();
  v_run_a2_id uuid := gen_random_uuid();
  v_run_b_id uuid := gen_random_uuid();
begin
  insert into app.report_runs (id, tenant_id, report_type_code, run_type, status, requested_by_auth_user_id, created_by, requested_at, completed_at)
  values
    (v_run_a1_id, v_tenant_id, 'o1c6b3_active', 'preview', 'completed', '00000000-0000-0000-0000-000000999601', 'tester', now() - interval '2 hours', now() - interval '2 hours' + interval '1 minute'),
    (v_run_a2_id, v_tenant_id, 'o1c6b3_active', 'preview', 'completed', '00000000-0000-0000-0000-000000999601', 'tester', now() - interval '1 hour', now() - interval '1 hour' + interval '1 minute'),
    (v_run_b_id, v_tenant_id, 'o1c6b3_retired', 'preview', 'completed', '00000000-0000-0000-0000-000000999601', 'tester', now() - interval '30 minutes', now() - interval '29 minutes');
end $$;

\echo '>> app.list_report_runs: unfiltered call returns all 3 runs (requested_at desc); p_report_type_code filter narrows to exactly the 2 o1c6b3_active runs in the right order; a real active tenant member (999602, not the requester) sees them too; customer_user-layer/cross-tenant both denied; Supreme Admin (zero membership) bypasses via the policy''s own explicit OR is_supreme_admin() disjunct'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b3');
  v_run_a1_id uuid := (select id from app.report_runs where tenant_id = v_tenant_id and report_type_code = 'o1c6b3_active' and requested_at = (select min(requested_at) from app.report_runs where tenant_id = v_tenant_id and report_type_code = 'o1c6b3_active'));
  v_run_a2_id uuid := (select id from app.report_runs where tenant_id = v_tenant_id and report_type_code = 'o1c6b3_active' and requested_at = (select max(requested_at) from app.report_runs where tenant_id = v_tenant_id and report_type_code = 'o1c6b3_active'));
  v_ids uuid[];
  v_count integer;
begin
  select count(*) into v_count from app.list_report_runs(v_tenant_id);
  if v_count <> 3 then raise exception 'assertion failed: the unfiltered call must return all 3 runs, got %', v_count; end if;

  select array_agg(id) into v_ids from app.list_report_runs(v_tenant_id, 'o1c6b3_active');
  if v_ids <> array[v_run_a2_id, v_run_a1_id] then
    raise exception 'assertion failed: list_report_runs(tenant, o1c6b3_active) must return [a2, a1] (requested_at desc), got %', v_ids;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999602", "role": "authenticated"}';
  select count(*) into v_count from app.list_report_runs(v_tenant_id);
  if v_count <> 3 then raise exception 'assertion failed: a real, non-requester tenant member must see all 3 runs, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999603", "role": "authenticated"}';
  select count(*) into v_count from app.list_report_runs(v_tenant_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero runs, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999605", "role": "authenticated"}';
  select count(*) into v_count from app.list_report_runs(v_tenant_id);
  if v_count <> 0 then raise exception 'assertion failed: a cross-tenant admin must see zero runs, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999604", "role": "authenticated"}';
  select count(*) into v_count from app.list_report_runs(v_tenant_id);
  if v_count <> 3 then raise exception 'assertion failed: Supreme Admin (zero membership) must see all 3 runs via the policy''s own explicit OR is_supreme_admin(), got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  raise notice 'app.report_runs proof: unfiltered/filtered calls both correct, real tenant member sees all runs, customer_user-layer/cross-tenant both denied, Supreme Admin bypasses via the explicit policy-level disjunct';
end $$;

\echo '>> fixture: 2 app.saved_report_views rows owned by 999601 -- one private, one tenant-shared'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b3');
begin
  insert into app.saved_report_views (id, tenant_id, report_type_code, owner_auth_user_id, owner_label, name, sharing_scope, created_by)
  values
    (gen_random_uuid(), v_tenant_id, 'o1c6b3_active', '00000000-0000-0000-0000-000000999601', 'tester', 'O1C6B3 Private View', 'private', 'tester'),
    (gen_random_uuid(), v_tenant_id, 'o1c6b3_active', '00000000-0000-0000-0000-000000999601', 'tester', 'O1C6B3 Shared View', 'tenant', 'tester');
end $$;

\echo '>> app.get_saved_report_view_by_id -- the 3-branch predicate, exercised precisely: the OWNER (999601) sees both the private and the tenant-shared view; a DIFFERENT real tenant member (999602, not the owner) sees the tenant-shared view but is DENIED the private one; a customer_user-layer principal (999603) sees NEITHER despite an active tenant membership; a cross-tenant admin (999605) sees neither; a Supreme Admin (999604, zero membership) sees both via the policy''s own explicit is_supreme_admin() branch'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b3');
  v_private_id uuid := (select id from app.saved_report_views where tenant_id = v_tenant_id and name = 'O1C6B3 Private View');
  v_shared_id uuid := (select id from app.saved_report_views where tenant_id = v_tenant_id and name = 'O1C6B3 Shared View');
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999601", "role": "authenticated"}';
  select count(*) into v_count from app.get_saved_report_view_by_id(v_private_id);
  if v_count <> 1 then raise exception 'assertion failed: the owner must see their own private view, got %', v_count; end if;
  select count(*) into v_count from app.get_saved_report_view_by_id(v_shared_id);
  if v_count <> 1 then raise exception 'assertion failed: the owner must see their own tenant-shared view, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999602", "role": "authenticated"}';
  select count(*) into v_count from app.get_saved_report_view_by_id(v_private_id);
  if v_count <> 0 then raise exception 'assertion failed: a real, non-owner tenant member must NOT see the owner''s private view, got %', v_count; end if;
  select count(*) into v_count from app.get_saved_report_view_by_id(v_shared_id);
  if v_count <> 1 then raise exception 'assertion failed: a real, non-owner tenant member MUST see the tenant-shared view, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999603", "role": "authenticated"}';
  select count(*) into v_count from app.get_saved_report_view_by_id(v_private_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must NOT see the private view, got %', v_count; end if;
  select count(*) into v_count from app.get_saved_report_view_by_id(v_shared_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must NOT see the tenant-shared view either (despite an active tenant membership), got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999605", "role": "authenticated"}';
  select count(*) into v_count from app.get_saved_report_view_by_id(v_shared_id);
  if v_count <> 0 then raise exception 'assertion failed: a cross-tenant admin must not see the tenant-shared view, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999604", "role": "authenticated"}';
  select count(*) into v_count from app.get_saved_report_view_by_id(v_private_id);
  if v_count <> 1 then raise exception 'assertion failed: Supreme Admin (zero membership) must see the private view via the explicit is_supreme_admin() branch, got %', v_count; end if;
  select count(*) into v_count from app.get_saved_report_view_by_id(v_shared_id);
  if v_count <> 1 then raise exception 'assertion failed: Supreme Admin (zero membership) must see the tenant-shared view too, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  raise notice 'app.saved_report_views proof: the full 3-branch predicate holds precisely -- owner sees both, a real non-owner tenant member sees ONLY the shared one, customer_user-layer sees neither despite membership, cross-tenant sees neither, Supreme Admin sees both regardless of membership';
end $$;

\echo '>> anon defense in depth: all 5 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.list_active_report_types();
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_active_report_types';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_active_report_types correctly rejected anon';
    end;

    begin
      perform public.get_report_type_by_code('x');
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_report_type_by_code';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.get_report_type_by_code correctly rejected anon';
    end;

    begin
      perform public.list_report_runs(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_report_runs';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_report_runs correctly rejected anon';
    end;

    begin
      perform public.list_report_type_versions('x');
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_report_type_versions';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_report_type_versions correctly rejected anon';
    end;

    begin
      perform public.get_saved_report_view_by_id(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_saved_report_view_by_id';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.get_saved_report_view_by_id correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: all 5 SECURITY INVOKER functions succeed via service_role''s own direct grant / BYPASSRLS regardless of membership, under a session that carries no request.jwt.claims at all'
begin;
  set local role service_role;
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b3');
    v_private_id uuid := (select id from app.saved_report_views where tenant_id = v_tenant_id and name = 'O1C6B3 Private View');
    v_count integer;
  begin
    if not exists (select 1 from app.list_active_report_types() where code = 'o1c6b3_active') then
      raise exception 'assertion failed: service_role must see the fixture type via app.list_active_report_types';
    end if;
    select count(*) into v_count from app.get_report_type_by_code('o1c6b3_retired');
    if v_count <> 1 then raise exception 'assertion failed: service_role must resolve the retired type via app.get_report_type_by_code, got %', v_count; end if;
    select count(*) into v_count from app.list_report_runs(v_tenant_id);
    if v_count <> 3 then raise exception 'assertion failed: service_role must see all 3 runs via app.list_report_runs (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.list_report_type_versions('o1c6b3_active');
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both versions via app.list_report_type_versions, got %', v_count; end if;
    select count(*) into v_count from app.get_saved_report_view_by_id(v_private_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the private view via app.get_saved_report_view_by_id (BYPASSRLS), got %', v_count; end if;

    raise notice 'service_role proof: all 5 SECURITY INVOKER functions succeed regardless of membership';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 5 new cluster-6-batch-3 function pairs (10 functions) in EITHER schema; authenticated/service_role hold EXECUTE on both the app.* function and its public.* wrapper for all 5 pairs, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_active_report_types', 'get_report_type_by_code', 'list_report_runs',
      'list_report_type_versions', 'get_saved_report_view_by_id'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 5 cluster-6-batch-3 function pairs (10 functions, either schema), found % grants', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_active_report_types', 'get_report_type_by_code', 'list_report_runs',
      'list_report_type_versions', 'get_saved_report_view_by_id'
    )
    and grantee in ('authenticated', 'service_role');
  if v_count <> 5 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 20 grants (5 functions x 2 schemas x 2 grantees), found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 10 new cluster-6-batch-3 functions; authenticated/service_role hold the declared grant on both the app.* and public.* function in every one of the 5 pairs';
end $$;

\echo '>> o1-query-layer-cluster6-batch3.sql test suite passed -- cluster 6 batch 3 (report types/runs/type-versions, saved report view by id -- 6/30 call sites, 20/30 cumulative) is now fully DONE'
