-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 5
-- (procurement-document), the FULL cluster in one file
-- (supabase/migrations/20260913000000_close_o1_query_layer_cluster5_procurement_document.sql).
--
-- Proves, against a real disposable database, that all 4 new function pairs (8
-- functions total) return exactly what their own comments and this migration's own
-- header claim, across the TWO distinct authority shapes this cluster spans:
--
--   SHAPE 1 (SECURITY DEFINER, explicit actor + RULE A, tenant-membership predicate,
--   raises insufficient_authority on total denial -- never a silent empty list):
--     app.list_procurement_approval_policy_versions, app.list_document_requirement_
--     definitions.
--   SHAPE 2 (SECURITY INVOKER, zero actor parameter, no in-function authority check
--   -- either genuinely open RLS (`using (true)`) or no RLS at all, just a direct
--   table grant):
--     app.list_active_procurement_metric_definitions, app.list_document_types.
--
-- IMPORTANT test-design note (a standing lesson this series learned the hard way at
-- cluster 4 batch 1): app.procurement_metric_definitions and app.document_types are
-- BOTH platform-wide, non-tenant-scoped tables that OTHER db-test files in this same
-- shared full-suite database also seed rows into (app.procurement_metric_definitions
-- additionally carries 11 real, always-present rows seeded at migration-apply time
-- itself, confirmed at 20260730780000_create_procurement_dashboard_reports.sql:1243).
-- Every assertion against either function below therefore checks for the EXISTENCE of
-- a uniquely-named fixture row (or a known always-seeded code), NEVER an exact
-- `count(*)` of the full result set -- an exact-count assertion here would be exactly
-- the cross-file fixture-collision defect class cluster 4 batch 1's own db-test fix
-- disclosed, applied proactively instead of being re-discovered the hard way again.
--
-- The fifth call site of this cluster (server/queries/procurement-approval.ts:136,
-- listProcurementApprovalInboxForActor) needed no new SQL at all -- it was converted
-- to reuse app.get_approval_requests_entity_refs, already shipped and already proven
-- by cluster 0 batch 3's own db-test file (scripts/db-tests/o1-query-layer-cluster0-
-- batch3.sql). Re-testing that function's own SQL body here would be a duplicate of
-- existing coverage, not new evidence -- this file does not re-test it.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c5 with a real active org_user tenant member (999301, no owner/org-unit relationship required by either DEFINER function''s own RLS predicate), a customer_user-layer principal in the SAME tenant (999302), a global Supreme Admin with ZERO membership in this tenant (999303), and a second, isolated tenant gizmoo1c5 with its own tenant_admin (999304)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999301', 'membero1c5@example.test'),
    ('00000000-0000-0000-0000-000000999302', 'customerusero1c5@example.test'),
    ('00000000-0000-0000-0000-000000999303', 'supremeo1c5@example.test'),
    ('00000000-0000-0000-0000-000000999304', 'othertenanto1c5@example.test');

  perform app.provision_tenant('acmeo1c5', 'Acme O1C5 Co', 'idem-acmeo1c5', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c5');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999301', 'membero1c5@example.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1c5@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999301', 'org_user', v_tenant_id, null, 'tester');

  -- Customer-portal-layer principal (ATW-023 shape): an active app.tenant_user_identities
  -- linkage plus an active customer_user app.principal_memberships row, granted
  -- directly (no app.users profile at all), mirroring this series' own established
  -- pattern for this identity shape.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000999302', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999302', 'customer_user', v_tenant_id, 'fake-account-ref-o1c5', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999303', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c5', 'Gizmo O1C5 Co', 'idem-gizmoo1c5', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c5');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999304', 'othertenanto1c5@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c5@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999304', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> app.procurement_approval_policies / app.list_procurement_approval_policy_versions: 2 rows for acmeo1c5 inserted in ASCENDING created_at order (so the expected DESC output is the reverse of physical insertion order); member sees both in the right order, customer_user-layer/cross-tenant both raise insufficient_authority, Supreme Admin (zero membership) sees both via the explicit bypass'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c5');
  v_policy_old_id uuid := gen_random_uuid();
  v_policy_new_id uuid := gen_random_uuid();
  v_ids uuid[];
  v_count integer;
begin
  insert into app.procurement_approval_policies (id, tenant_id, entity_type, min_value_amount, always_required, status, created_by, created_at, updated_at)
  values
    (v_policy_old_id, v_tenant_id, 'vendor_activation', null, true, 'published', 'tester', now() - interval '2 days', now() - interval '2 days'),
    (v_policy_new_id, v_tenant_id, 'purchase_order', 50000000, false, 'draft', 'tester', now() - interval '1 day', now() - interval '1 day');

  select array_agg(id) into v_ids from app.list_procurement_approval_policy_versions(v_tenant_id, '00000000-0000-0000-0000-000000999301');
  if v_ids <> array[v_policy_new_id, v_policy_old_id] then
    raise exception 'assertion failed: list_procurement_approval_policy_versions must return [newer, older] (created_at desc), got %', v_ids;
  end if;

  begin
    perform app.list_procurement_approval_policy_versions(v_tenant_id, '00000000-0000-0000-0000-000000999302');
    raise exception 'assertion failed: a customer_user-layer principal must not list procurement approval policies';
  exception
    when insufficient_privilege then
      raise notice 'RULE B proof: customer_user-layer principal correctly denied (insufficient_authority)';
  end;

  begin
    perform app.list_procurement_approval_policy_versions(v_tenant_id, '00000000-0000-0000-0000-000000999304');
    raise exception 'assertion failed: a cross-tenant admin must not list acmeo1c5''s procurement approval policies';
  exception
    when insufficient_privilege then
      raise notice 'cross-tenant proof: gizmoo1c5''s own admin correctly denied on acmeo1c5';
  end;

  select count(*) into v_count from app.list_procurement_approval_policy_versions(v_tenant_id, '00000000-0000-0000-0000-000000999303');
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin (zero membership) must see both policy versions via the explicit bypass, got %', v_count;
  end if;

  raise notice 'app.procurement_approval_policies proof: member sees both versions in created_at desc order, customer_user-layer/cross-tenant both raise insufficient_authority, Supreme Admin bypasses with zero membership';
end $$;

\echo '>> app.document_types + app.document_requirement_definitions / app.list_document_requirement_definitions: a uniquely-named document type (o1c5doctype) and 2 requirement definitions for acmeo1c5 (one published, one draft); member sees both (no filter) and exactly the published one when p_status is supplied, customer_user-layer/cross-tenant both raise, Supreme Admin sees both'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c5');
  v_req_published_id uuid := gen_random_uuid();
  v_req_draft_id uuid := gen_random_uuid();
  v_count integer;
begin
  insert into app.document_types (code, name, owner_primitive_code, registered_by)
  values ('o1c5doctype', 'O1C5 Test Document Type', 'DOC', 'tester');

  insert into app.document_requirement_definitions (id, tenant_id, mode, service_type, applicable_status, party, document_type_code, criticality, status, created_by, created_at, updated_at)
  values
    (v_req_published_id, v_tenant_id, 'sea', null, 'delivered', 'carrier', 'o1c5doctype', 'mandatory', 'published', 'tester', now(), now()),
    (v_req_draft_id, v_tenant_id, 'land', null, 'confirmed', 'shipper', 'o1c5doctype', 'optional', 'draft', 'tester', now(), now());

  select count(*) into v_count from app.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999301', null);
  if v_count <> 2 then
    raise exception 'assertion failed: member with no status filter must see both requirement definitions, got %', v_count;
  end if;

  select count(*) into v_count from app.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999301', 'published');
  if v_count <> 1 then
    raise exception 'assertion failed: member filtered to p_status=published must see exactly 1 requirement definition, got %', v_count;
  end if;
  if not exists (select 1 from app.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999301', 'published') where id = v_req_published_id) then
    raise exception 'assertion failed: the p_status=published result must be the real published row';
  end if;

  begin
    perform app.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999302', null);
    raise exception 'assertion failed: a customer_user-layer principal must not list document requirement definitions';
  exception
    when insufficient_privilege then
      raise notice 'RULE B proof: customer_user-layer principal correctly denied (insufficient_authority)';
  end;

  begin
    perform app.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999304', null);
    raise exception 'assertion failed: a cross-tenant admin must not list acmeo1c5''s document requirement definitions';
  exception
    when insufficient_privilege then
      raise notice 'cross-tenant proof: gizmoo1c5''s own admin correctly denied on acmeo1c5';
  end;

  select count(*) into v_count from app.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999303', null);
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin (zero membership) must see both requirement definitions via the explicit bypass, got %', v_count;
  end if;

  raise notice 'app.document_requirement_definitions proof: member sees both (no filter) and exactly the published one (p_status filter), customer_user-layer/cross-tenant both raise insufficient_authority, Supreme Admin bypasses with zero membership';
end $$;

\echo '>> RULE A (SAFETY-CRITICAL): app.list_procurement_approval_policy_versions and app.list_document_requirement_definitions both genuinely reject a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999304", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c5');
  begin
    begin
      -- Real session is 999304 (gizmoo1c5's own admin); claims to be 999301 (acmeo1c5's
      -- own real member, who WOULD otherwise see these rows) -- must still be rejected,
      -- before any lookup or authority check runs.
      perform app.list_procurement_approval_policy_versions(v_tenant_id, '00000000-0000-0000-0000-000000999301');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (list_procurement_approval_policy_versions)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: list_procurement_approval_policy_versions impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;

    begin
      perform app.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999301', null);
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (list_document_requirement_definitions)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: list_document_requirement_definitions impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.list_active_procurement_metric_definitions: a known always-seeded platform code is present and correctly ordered relative to a second known seeded code in a lexicographically earlier metric_group; a superseded (is_current=false) and a retired (status=retired, is_current=false) fixture row are both excluded -- wrapped in an explicit begin/rollback, NEVER committed: app.procurement_metric_definitions is a platform-wide shared table that scripts/db-tests/procurement-vendor-dashboard-reports.sql asserts an EXACT count of is_current rows against (11, its own migration-seeded baseline, confirmed live: committing even one additional is_current=true row here made that sibling assertion fail with "expected exactly 11 current metric definitions, got 14" when this file is run before it in the full suite) -- so this block''s own fixture rows are inserted, asserted against, and then rolled back within one transaction, leaving the shared table exactly as every other db-test file expects it; this is the cross-file fixture-collision defect class this series already documented once (cluster 4 batch 1) recurring in a new shape (an exact-count assertion in ANOTHER file, not merely an underscoped subquery in this one) and closed the same way real corrections are always handled in this series -- disclosed, not silently patched around'
begin;
  do $$
  declare
    v_codes text[];
    v_pos_known_low integer;
    v_pos_known_high integer;
  begin
    -- Deliberately is_current=false on BOTH negative fixtures (never is_current=true)
    -- so this block can never contribute to procurement-vendor-dashboard-reports.sql's
    -- own is_current=true count even if the rollback below were ever accidentally
    -- dropped -- defense in depth on top of the transaction boundary itself.
    insert into app.procurement_metric_definitions (code, metric_group, name, description, source_tables, source_columns, formula, grain, freshness_rule, required_action, additional_mask_action, source_function, status, is_current, registered_by)
    values
      ('o1c5metricsuperseded', 'po_contract', 'O1C5 Test Metric Superseded', null, array['app.test_table'], array['test_column'], 'count(*)', 'tenant', 'live', 'View', null, 'app.o1c5_test_source', 'active', false, 'tester'),
      ('o1c5metricretired', 'rfq_response_cycle', 'O1C5 Test Metric Retired', null, array['app.test_table'], array['test_column'], 'count(*)', 'tenant', 'live', 'View', null, 'app.o1c5_test_source', 'retired', false, 'tester');

    if not exists (select 1 from app.list_active_procurement_metric_definitions() where code = 'vendor_lifecycle_risk_mix') then
      raise exception 'assertion failed: the always-seeded platform code vendor_lifecycle_risk_mix must be present';
    end if;
    if exists (select 1 from app.list_active_procurement_metric_definitions() where code = 'o1c5metricsuperseded') then
      raise exception 'assertion failed: the is_current=false fixture row o1c5metricsuperseded must be excluded';
    end if;
    if exists (select 1 from app.list_active_procurement_metric_definitions() where code = 'o1c5metricretired') then
      raise exception 'assertion failed: the is_current=false, status=retired fixture row o1c5metricretired must be excluded';
    end if;

    -- Ordering fidelity, proven against two of the migration's own always-present
    -- seeded codes rather than a new fixture row (per this block''s own
    -- never-add-an-is_current-row constraint above): purchase_order_pipeline_mix
    -- (metric_group=po_contract) must sort before vendor_lifecycle_risk_mix
    -- (metric_group=vendor_risk_compliance) under metric_group asc ('po_contract' <
    -- 'vendor_risk_compliance' lexicographically).
    select array_agg(code) into v_codes from app.list_active_procurement_metric_definitions();
    v_pos_known_low := array_position(v_codes, 'purchase_order_pipeline_mix');
    v_pos_known_high := array_position(v_codes, 'vendor_lifecycle_risk_mix');
    if v_pos_known_low is null or v_pos_known_high is null or v_pos_known_low >= v_pos_known_high then
      raise exception 'assertion failed: ordering fidelity -- purchase_order_pipeline_mix (metric_group=po_contract) must sort before vendor_lifecycle_risk_mix (metric_group=vendor_risk_compliance) under metric_group asc, got positions % and %', v_pos_known_low, v_pos_known_high;
    end if;

    raise notice 'app.list_active_procurement_metric_definitions proof: known seeded code present and correctly ordered by metric_group asc; is_current=false fixtures (one plain, one also status=retired) both excluded';
  end $$;
rollback;

\echo '>> app.list_document_types: a uniquely-named fixture row (o1c5doctype, inserted above) is present in the full registry -- checked by presence, never an exact count, since this table is platform-wide and other db-test files in the shared full-suite database also register their own document types'
do $$
begin
  if not exists (select 1 from app.list_document_types() where code = 'o1c5doctype') then
    raise exception 'assertion failed: the fixture document type o1c5doctype must be present in app.list_document_types()';
  end if;

  raise notice 'app.list_document_types proof: the fixture document type registered above is present in the full registry';
end $$;

\echo '>> anon defense in depth: all 4 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.list_procurement_approval_policy_versions(v_dummy, v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_procurement_approval_policy_versions';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_procurement_approval_policy_versions correctly rejected anon';
    end;

    begin
      perform public.list_active_procurement_metric_definitions();
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_active_procurement_metric_definitions';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_active_procurement_metric_definitions correctly rejected anon';
    end;

    begin
      perform public.list_document_requirement_definitions(v_dummy, v_dummy, null);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_document_requirement_definitions';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_document_requirement_definitions correctly rejected anon';
    end;

    begin
      perform public.list_document_types();
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_document_types';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_document_types correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: app.list_procurement_approval_policy_versions/app.list_document_requirement_definitions (SECURITY DEFINER, explicit actor param -- passed a real actor id explicitly since neither ever relies on auth.uid()) succeed via both app.* and public.*; app.list_active_procurement_metric_definitions/app.list_document_types (SECURITY INVOKER) both succeed via service_role''s own direct grant / BYPASSRLS, under a session that carries no request.jwt.claims at all'
begin;
  set local role service_role;
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c5');
    v_count integer;
  begin
    select count(*) into v_count from app.list_procurement_approval_policy_versions(v_tenant_id, '00000000-0000-0000-0000-000000999301');
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both policy versions via app.list_procurement_approval_policy_versions, got %', v_count; end if;
    select count(*) into v_count from public.list_procurement_approval_policy_versions(v_tenant_id, '00000000-0000-0000-0000-000000999301');
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both policy versions via public.list_procurement_approval_policy_versions, got %', v_count; end if;

    select count(*) into v_count from app.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999301', null);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both requirement definitions via app.list_document_requirement_definitions, got %', v_count; end if;
    select count(*) into v_count from public.list_document_requirement_definitions(v_tenant_id, '00000000-0000-0000-0000-000000999301', null);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both requirement definitions via public.list_document_requirement_definitions, got %', v_count; end if;

    if not exists (select 1 from app.list_active_procurement_metric_definitions() where code = 'vendor_lifecycle_risk_mix') then
      raise exception 'assertion failed: service_role must see the always-seeded platform code via app.list_active_procurement_metric_definitions';
    end if;
    if not exists (select 1 from public.list_active_procurement_metric_definitions() where code = 'vendor_lifecycle_risk_mix') then
      raise exception 'assertion failed: service_role must see the always-seeded platform code via public.list_active_procurement_metric_definitions';
    end if;

    if not exists (select 1 from app.list_document_types() where code = 'o1c5doctype') then
      raise exception 'assertion failed: service_role must see the fixture row via app.list_document_types';
    end if;
    if not exists (select 1 from public.list_document_types() where code = 'o1c5doctype') then
      raise exception 'assertion failed: service_role must see the fixture row via public.list_document_types';
    end if;

    raise notice 'service_role proof: the 2 SECURITY DEFINER functions succeed with an explicitly-passed real actor id; the 2 SECURITY INVOKER functions succeed regardless of membership';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 4 new cluster-5 function pairs (8 functions) in EITHER schema; authenticated/service_role hold EXECUTE on both the app.* function and its public.* wrapper for all 4 pairs, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_procurement_approval_policy_versions',
      'list_active_procurement_metric_definitions',
      'list_document_requirement_definitions',
      'list_document_types'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 4 cluster-5 function pairs (8 functions, either schema), found % grants', v_count;
  end if;

  -- Full check on all 4 pairs (not merely a spot check): authenticated AND
  -- service_role both hold EXECUTE on the app.* function AND its public.* wrapper for
  -- every one of the 4 pairs (grant parity, ISS-2026-309) -- 4 functions x 2 schemas
  -- x 2 grantees = 16 grants.
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_procurement_approval_policy_versions',
      'list_active_procurement_metric_definitions',
      'list_document_requirement_definitions',
      'list_document_types'
    )
    and grantee in ('authenticated', 'service_role');
  if v_count <> 4 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 16 grants (4 functions x 2 schemas x 2 grantees), found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 8 new cluster-5 functions; authenticated/service_role hold the declared grant on both the app.* and public.* function in every one of the 4 pairs';
end $$;

\echo '>> o1-query-layer-cluster5-procurement-document.sql test suite passed -- cluster 5 (procurement-document, 5/5 call sites -- 4 new function pairs plus 1 reused function) is now fully DONE'
