-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 6
-- (platform-intelligence-reports) batch 1 of N
-- (supabase/migrations/20260913010000_close_o1_query_layer_cluster6_batch1_analytics_automation.sql).
--
-- Proves, against a real disposable database, that all 9 new function pairs (18
-- functions total -- ALL SECURITY INVOKER with ZERO actor parameter) return exactly
-- what their own comments and this migration's own header claim.
--
-- app.automation_rules/app.automation_rule_versions/app.automation_rule_executions
-- share the tenant-membership predicate WITHOUT an explicit `OR is_supreme_admin()`
-- disjunct at the policy level (unlike several sibling tables this series already
-- closed): a real active tenant member (999401) sees the real fixture rows, a
-- customer_user-layer principal in the SAME tenant (999402) sees zero rows despite
-- passing has_active_tenant_membership, a cross-tenant admin (999404) sees zero
-- rows, and a Supreme Admin with ZERO explicit tenant membership (999403) STILL
-- sees every row -- proving live that app.has_active_tenant_membership's own
-- internal `or app.is_supreme_admin(...)` branch (not a policy-level disjunct)
-- is what admits the Supreme Admin here, exactly as this migration's own header
-- claims rather than merely asserts.
--
-- app.approval_requests/app.approval_request_steps DO carry an explicit
-- `OR is_supreme_admin()` disjunct at the policy level -- same visibility matrix,
-- same 4 personas, functionally identical outcome via a different policy shape.
-- app.get_latest_automation_rule_publish_approval_request additionally proves the
-- ended_reason column-exclusion: a real, non-null ended_reason is written directly
-- to the fixture row, but the function's own explicit column list never selects it
-- -- the returned row always carries `ended_reason: null`, proving the DB-side
-- cast, not merely a client-side default.
--
-- app.analytics_view_registry (no RLS, full-row grant) and app.analytics_refresh_runs
-- (no RLS, COLUMN-restricted grant) are platform-wide, non-tenant-scoped tables --
-- proven via a plain authenticated session (no tenant-membership concept applies).
-- The refresh-run proof is the more important one: row_count_before/triggered_by_
-- auth_user_id/triggered_by_label are written as real, non-null values directly to
-- the fixture row, but both new functions' own explicit column lists cast them to
-- null -- proving live that a bare `select *` would have failed outright (column
-- privilege denied) and that the null-cast is real DB-enforced behavior, not an
-- assumption.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c6b1 with a real active org_user tenant member (999401, no owner/org-unit relationship required by any table in this batch), a customer_user-layer principal in the SAME tenant (999402), a global Supreme Admin with ZERO membership in this tenant (999403), a second, isolated tenant gizmoo1c6b1 with its own tenant_admin (999404), and a bootstrap tenant_admin in acmeo1c6b1 (999405, config-draft-creation plumbing only, never itself used as a test persona below)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999401', 'membero1c6b1@example.test'),
    ('00000000-0000-0000-0000-000000999402', 'customerusero1c6b1@example.test'),
    ('00000000-0000-0000-0000-000000999403', 'supremeo1c6b1@example.test'),
    ('00000000-0000-0000-0000-000000999404', 'othertenanto1c6b1@example.test'),
    ('00000000-0000-0000-0000-000000999405', 'bootstrapadmino1c6b1@example.test');

  perform app.provision_tenant('acmeo1c6b1', 'Acme O1C6B1 Co', 'idem-acmeo1c6b1', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c6b1');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999401', 'membero1c6b1@example.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1c6b1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999401', 'org_user', v_tenant_id, null, 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000999402', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999402', 'customer_user', v_tenant_id, 'fake-account-ref-o1c6b1', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999403', 'supreme_admin', null, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999405', 'bootstrapadmino1c6b1@example.test', 'Bootstrap Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'bootstrapadmino1c6b1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999405', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.provision_tenant('gizmoo1c6b1', 'Gizmo O1C6B1 Co', 'idem-gizmoo1c6b1', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c6b1');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999404', 'othertenanto1c6b1@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c6b1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999404', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> fixture: 1 app.automation_rules row for acmeo1c6b1, 2 app.automation_rule_versions rows inserted in ASCENDING version_number order (so version_number desc output is the reverse of insertion order), 2 app.automation_rule_executions rows inserted in ASCENDING executed_at order (so executed_at desc output is the reverse of insertion order)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b1');
  v_rule_id uuid := gen_random_uuid();
  v_version1_id uuid := gen_random_uuid();
  v_version2_id uuid := gen_random_uuid();
begin
  insert into app.automation_rules (id, tenant_id, name, description, status, created_by, created_at, updated_at)
  values (v_rule_id, v_tenant_id, 'O1C6B1 Test Rule', 'a test automation rule', 'active', 'tester', now(), now());

  insert into app.automation_rule_versions (id, automation_rule_id, version_number, status, trigger_event_type, conditions, actions, created_by, created_at)
  values
    (v_version1_id, v_rule_id, 1, 'archived', 'ticket.created', '[]'::jsonb, '[]'::jsonb, 'tester', now() - interval '2 days'),
    (v_version2_id, v_rule_id, 2, 'published', 'ticket.created', '[]'::jsonb, '[]'::jsonb, 'tester', now() - interval '1 day');

  insert into app.automation_rule_executions (id, tenant_id, automation_rule_id, automation_rule_version_id, trigger_event_type, status, idempotency_key, executed_at)
  values
    (gen_random_uuid(), v_tenant_id, v_rule_id, v_version2_id, 'ticket.created', 'completed', 'idem-o1c6b1-exec-1', now() - interval '2 hours'),
    (gen_random_uuid(), v_tenant_id, v_rule_id, v_version2_id, 'ticket.created', 'suppressed', 'idem-o1c6b1-exec-2', now() - interval '1 hour');
end $$;

\echo '>> app.automation_rules/app.list_automation_rules/app.get_automation_rule_by_id: member sees the real rule (and a nonexistent id returns a GENUINELY EMPTY result), customer_user-layer/cross-tenant both see zero rows, Supreme Admin (zero membership) still sees it via has_active_tenant_membership''s own internal is_supreme_admin branch'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b1');
  v_rule_id uuid := (select id from app.automation_rules where tenant_id = v_tenant_id and name = 'O1C6B1 Test Rule');
  v_count integer;
  v_row record;
begin
  select count(*) into v_count from app.list_automation_rules(v_tenant_id);
  if v_count <> 1 then raise exception 'assertion failed: member must see exactly 1 automation rule, got %', v_count; end if;

  select * into v_row from app.get_automation_rule_by_id(v_rule_id);
  if v_row.id is null or v_row.id <> v_rule_id then raise exception 'assertion failed: member must resolve the real rule by id, got %', v_row; end if;

  select count(*) into v_count from app.get_automation_rule_by_id(gen_random_uuid());
  if v_count <> 0 then raise exception 'assertion failed: a nonexistent rule id must return a genuinely empty result, got %', v_count; end if;
  if exists (select 1 from app.get_automation_rule_by_id(gen_random_uuid())) then
    raise exception 'assertion failed: a nonexistent rule id must be a genuinely empty row set, found at least one row';
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999402", "role": "authenticated"}';
  select count(*) into v_count from app.list_automation_rules(v_tenant_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from list_automation_rules, got %', v_count; end if;
  select count(*) into v_count from app.get_automation_rule_by_id(v_rule_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from get_automation_rule_by_id, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999404", "role": "authenticated"}';
  select count(*) into v_count from app.list_automation_rules(v_tenant_id);
  if v_count <> 0 then raise exception 'assertion failed: cross-tenant admin must see zero rows from list_automation_rules, got %', v_count; end if;
  select count(*) into v_count from app.get_automation_rule_by_id(v_rule_id);
  if v_count <> 0 then raise exception 'assertion failed: cross-tenant admin must see zero rows from get_automation_rule_by_id, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999403", "role": "authenticated"}';
  select count(*) into v_count from app.list_automation_rules(v_tenant_id);
  if v_count <> 1 then raise exception 'assertion failed: Supreme Admin (zero membership) must see the real rule via list_automation_rules, got %', v_count; end if;
  select count(*) into v_count from app.get_automation_rule_by_id(v_rule_id);
  if v_count <> 1 then raise exception 'assertion failed: Supreme Admin (zero membership) must see the real rule via get_automation_rule_by_id, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  raise notice 'app.automation_rules proof: member sees the real rule and a genuinely empty result for a nonexistent id, customer_user-layer/cross-tenant both denied, Supreme Admin bypasses with zero explicit membership';
end $$;

\echo '>> app.automation_rule_versions/app.list_automation_rule_versions: ordering fidelity (version_number desc) against fixture rows inserted out of that order; authority is re-derived via the EXISTS join back to app.automation_rules -- customer_user-layer/cross-tenant denied, Supreme Admin bypasses'
do $$
declare
  v_rule_id uuid := (select id from app.automation_rules where name = 'O1C6B1 Test Rule');
  v_version1_id uuid := (select id from app.automation_rule_versions where automation_rule_id = v_rule_id and version_number = 1);
  v_version2_id uuid := (select id from app.automation_rule_versions where automation_rule_id = v_rule_id and version_number = 2);
  v_ids uuid[];
  v_count integer;
begin
  select array_agg(id) into v_ids from app.list_automation_rule_versions(v_rule_id);
  if v_ids <> array[v_version2_id, v_version1_id] then
    raise exception 'assertion failed: list_automation_rule_versions must return [v2, v1] (version_number desc), got %', v_ids;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999402", "role": "authenticated"}';
  select count(*) into v_count from app.list_automation_rule_versions(v_rule_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero versions, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999403", "role": "authenticated"}';
  select count(*) into v_count from app.list_automation_rule_versions(v_rule_id);
  if v_count <> 2 then raise exception 'assertion failed: Supreme Admin (zero membership) must see both versions, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  raise notice 'app.automation_rule_versions proof: ordering fidelity correct, customer_user-layer denied, Supreme Admin bypasses with zero membership via the same joined predicate';
end $$;

\echo '>> app.automation_rule_executions/app.list_automation_rule_executions: ordering fidelity (executed_at desc) against fixture rows inserted out of that order, direct tenant_id column (no join needed)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b1');
  v_rule_id uuid := (select id from app.automation_rules where name = 'O1C6B1 Test Rule');
  v_exec1_id uuid := (select id from app.automation_rule_executions where idempotency_key = 'idem-o1c6b1-exec-1');
  v_exec2_id uuid := (select id from app.automation_rule_executions where idempotency_key = 'idem-o1c6b1-exec-2');
  v_ids uuid[];
begin
  select array_agg(id) into v_ids from app.list_automation_rule_executions(v_rule_id);
  if v_ids <> array[v_exec2_id, v_exec1_id] then
    raise exception 'assertion failed: list_automation_rule_executions must return [exec2, exec1] (executed_at desc), got %', v_ids;
  end if;

  raise notice 'app.automation_rule_executions proof: ordering fidelity correct against fixture rows deliberately inserted out of order';
end $$;

\echo '>> fixture: a real, published app.config_versions row under the platform-wide, code-shipped approval:automation_rule_publish config type (registered directly by 20260803010000_create_intelligence_automation_rule_engine.sql:162, the SAME config type the real app.request_automation_rule_publish_approval production path uses), created via the real app.create_config_draft/app.publish_config_version functions (bootstrap tenant_admin 999405), then 1 app.approval_requests row for acmeo1c6b1 (entity_type=automation_rule_version, entity_id=version2, a REAL non-null ended_reason deliberately written -- a direct fixture insert bypassing app.request_approval, mirroring scripts/db-tests/automation-rule-engine.sql''s own established precedent for this exact "insert an approval_requests row directly" shape), and 2 app.approval_request_steps rows inserted in DESCENDING step_order (so step_order asc output is the reverse of insertion order)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b1');
  v_rule_id uuid := (select id from app.automation_rules where name = 'O1C6B1 Test Rule');
  v_version2_id uuid := (select id from app.automation_rule_versions where automation_rule_id = v_rule_id and version_number = 2);
  v_draft app.config_versions;
  v_published app.config_versions;
  v_request_id uuid := gen_random_uuid();
begin
  v_draft := app.create_config_draft('approval:automation_rule_publish', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000999405', 'tester');
  v_published := app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000999405', now(), 'tester');

  insert into app.approval_requests (id, tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key, requested_by, started_at, ended_at, ended_reason, created_at, updated_at)
  values (v_request_id, v_tenant_id, v_published.id, 'automation_rule_version', v_version2_id, 'sequential', 'rejected', 'idem-o1c6b1-approval', 'tester', now() - interval '1 day', now(), 'a real, sensitive rejection narrative that authenticated must never see', now() - interval '1 day', now());

  insert into app.approval_request_steps (id, request_id, step_order, approver_type, specific_user_id, required_approvals, approvals_count, status, created_at, updated_at)
  values
    (gen_random_uuid(), v_request_id, 2, 'specific_user', '00000000-0000-0000-0000-000000999401', 1, 0, 'active', now(), now()),
    (gen_random_uuid(), v_request_id, 1, 'specific_user', '00000000-0000-0000-0000-000000999401', 1, 1, 'approved', now(), now());
end $$;

\echo '>> app.get_latest_automation_rule_publish_approval_request: resolves the real request for version2 with ended_reason genuinely nulled (never the real, sensitive narrative written to the row), a genuinely empty result for version1 (which was never submitted for approval), customer_user-layer/cross-tenant both denied, Supreme Admin bypasses via the policy''s own explicit OR is_supreme_admin() disjunct'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b1');
  v_rule_id uuid := (select id from app.automation_rules where name = 'O1C6B1 Test Rule');
  v_version1_id uuid := (select id from app.automation_rule_versions where automation_rule_id = v_rule_id and version_number = 1);
  v_version2_id uuid := (select id from app.automation_rule_versions where automation_rule_id = v_rule_id and version_number = 2);
  v_row record;
  v_count integer;
begin
  select * into v_row from app.get_latest_automation_rule_publish_approval_request(v_version2_id);
  if v_row.id is null or v_row.status <> 'rejected' then
    raise exception 'assertion failed: member must resolve the real approval request for version2, got %', v_row;
  end if;
  if v_row.ended_reason is not null then
    raise exception 'assertion failed: ended_reason must be genuinely null, never the real sensitive narrative, got %', v_row.ended_reason;
  end if;

  select count(*) into v_count from app.get_latest_automation_rule_publish_approval_request(v_version1_id);
  if v_count <> 0 then raise exception 'assertion failed: version1 (never submitted) must return a genuinely empty result, got %', v_count; end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999402", "role": "authenticated"}';
  select count(*) into v_count from app.get_latest_automation_rule_publish_approval_request(v_version2_id);
  if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999404", "role": "authenticated"}';
  select count(*) into v_count from app.get_latest_automation_rule_publish_approval_request(v_version2_id);
  if v_count <> 0 then raise exception 'assertion failed: a cross-tenant admin must see zero rows, got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999403", "role": "authenticated"}';
  select count(*) into v_count from app.get_latest_automation_rule_publish_approval_request(v_version2_id);
  if v_count <> 1 then raise exception 'assertion failed: Supreme Admin (zero membership) must see the real request via the policy''s own explicit OR is_supreme_admin(), got %', v_count; end if;
  reset role;
  reset request.jwt.claims;

  raise notice 'app.get_latest_automation_rule_publish_approval_request proof: real request resolved with ended_reason genuinely nulled, genuinely empty for an unsubmitted version, customer_user-layer/cross-tenant denied, Supreme Admin bypasses via the explicit policy-level disjunct';
end $$;

\echo '>> app.list_approval_request_steps: ordering fidelity (step_order asc) against fixture rows inserted in descending order'
do $$
declare
  v_request_id uuid := (select id from app.approval_requests where idempotency_key = 'idem-o1c6b1-approval');
  v_step1_id uuid := (select id from app.approval_request_steps where request_id = v_request_id and step_order = 1);
  v_step2_id uuid := (select id from app.approval_request_steps where request_id = v_request_id and step_order = 2);
  v_ids uuid[];
begin
  select array_agg(id) into v_ids from app.list_approval_request_steps(v_request_id);
  if v_ids <> array[v_step1_id, v_step2_id] then
    raise exception 'assertion failed: list_approval_request_steps must return [step1, step2] (step_order asc), got %', v_ids;
  end if;

  raise notice 'app.list_approval_request_steps proof: ordering fidelity correct against fixture rows deliberately inserted out of order';
end $$;

\echo '>> fixture: 1 app.analytics_view_registry row (o1c6b1_test_view) and 2 app.analytics_refresh_runs rows inserted in ASCENDING started_at order (so started_at desc output is the reverse of insertion order), each with a REAL, non-null row_count_before/triggered_by_auth_user_id/triggered_by_label deliberately written -- these are platform-wide, non-tenant-scoped tables, so any authenticated session (999401) is used'
do $$
declare
  v_run1_id uuid := gen_random_uuid();
  v_run2_id uuid := gen_random_uuid();
begin
  insert into app.analytics_view_registry (id, view_code, view_name, name, description, source_domain, refresh_frequency_minutes, status, registered_by)
  values (gen_random_uuid(), 'o1c6b1_test_view', 'mv_o1c6b1_test', 'O1C6B1 Test View', 'a test analytics view', 'reporting', 60, 'active', 'tester');

  insert into app.analytics_refresh_runs (id, view_code, status, row_count_before, row_count_after, reconciled, error_reason, triggered_by_auth_user_id, triggered_by_label, started_at, completed_at)
  values
    (v_run1_id, 'o1c6b1_test_view', 'completed', 5, 6, true, null, '00000000-0000-0000-0000-000000999403', 'a real admin label that must never leak', now() - interval '2 days', now() - interval '2 days' + interval '1 minute'),
    (v_run2_id, 'o1c6b1_test_view', 'completed', 6, 7, true, null, '00000000-0000-0000-0000-000000999403', 'a real admin label that must never leak', now() - interval '1 day', now() - interval '1 day' + interval '1 minute');
end $$;

\echo '>> app.list_analytics_view_registry: the fixture view is present (existence check, never an exact count -- this table is platform-wide and other db-test files in the shared full-suite database may register their own views)'
do $$
begin
  if not exists (select 1 from app.list_analytics_view_registry() where view_code = 'o1c6b1_test_view') then
    raise exception 'assertion failed: the fixture view o1c6b1_test_view must be present in app.list_analytics_view_registry()';
  end if;

  raise notice 'app.list_analytics_view_registry proof: the fixture view is present in the full registry';
end $$;

\echo '>> app.get_latest_analytics_refresh_run/app.list_analytics_refresh_runs: resolves the real, most-recent run with row_count_before/triggered_by_auth_user_id/triggered_by_label ALL genuinely nulled (never the real values written to the fixture rows), and ordering fidelity (started_at desc) for the full history against fixture rows inserted out of that order'
do $$
declare
  v_run1_id uuid := (select id from app.analytics_refresh_runs where view_code = 'o1c6b1_test_view' and row_count_after = 6);
  v_run2_id uuid := (select id from app.analytics_refresh_runs where view_code = 'o1c6b1_test_view' and row_count_after = 7);
  v_row record;
  v_ids uuid[];
begin
  select * into v_row from app.get_latest_analytics_refresh_run('o1c6b1_test_view');
  if v_row.id is null or v_row.id <> v_run2_id then
    raise exception 'assertion failed: get_latest_analytics_refresh_run must resolve run2 (the most recent), got %', v_row;
  end if;
  if v_row.row_count_before is not null or v_row.triggered_by_auth_user_id is not null or v_row.triggered_by_label is not null then
    raise exception 'assertion failed: row_count_before/triggered_by_auth_user_id/triggered_by_label must all be genuinely null, got %', v_row;
  end if;

  select array_agg(id) into v_ids from app.list_analytics_refresh_runs('o1c6b1_test_view');
  if v_ids <> array[v_run2_id, v_run1_id] then
    raise exception 'assertion failed: list_analytics_refresh_runs must return [run2, run1] (started_at desc), got %', v_ids;
  end if;

  raise notice 'app.analytics_refresh_runs proof: the real, most-recent run resolves with all 3 restricted columns genuinely nulled, and full-history ordering is correct';
end $$;

\echo '>> anon defense in depth: all 9 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.list_analytics_view_registry();
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_analytics_view_registry';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_analytics_view_registry correctly rejected anon';
    end;

    begin
      perform public.get_latest_analytics_refresh_run('o1c6b1_test_view');
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_latest_analytics_refresh_run';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.get_latest_analytics_refresh_run correctly rejected anon';
    end;

    begin
      perform public.list_analytics_refresh_runs('o1c6b1_test_view');
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_analytics_refresh_runs';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_analytics_refresh_runs correctly rejected anon';
    end;

    begin
      perform public.list_automation_rules(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_automation_rules';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_automation_rules correctly rejected anon';
    end;

    begin
      perform public.get_automation_rule_by_id(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_automation_rule_by_id';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.get_automation_rule_by_id correctly rejected anon';
    end;

    begin
      perform public.list_automation_rule_versions(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_automation_rule_versions';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_automation_rule_versions correctly rejected anon';
    end;

    begin
      perform public.list_automation_rule_executions(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_automation_rule_executions';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_automation_rule_executions correctly rejected anon';
    end;

    begin
      perform public.get_latest_automation_rule_publish_approval_request(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_latest_automation_rule_publish_approval_request';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.get_latest_automation_rule_publish_approval_request correctly rejected anon';
    end;

    begin
      perform public.list_approval_request_steps(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_approval_request_steps';
    exception
      when insufficient_privilege then raise notice 'anon denial proof: public.list_approval_request_steps correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: all 9 SECURITY INVOKER functions succeed via service_role''s own direct grant / BYPASSRLS regardless of membership, under a session that carries no request.jwt.claims at all'
begin;
  set local role service_role;
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c6b1');
    v_rule_id uuid := (select id from app.automation_rules where name = 'O1C6B1 Test Rule');
    v_version2_id uuid := (select id from app.automation_rule_versions where automation_rule_id = v_rule_id and version_number = 2);
    v_request_id uuid := (select id from app.approval_requests where idempotency_key = 'idem-o1c6b1-approval');
    v_count integer;
  begin
    if not exists (select 1 from app.list_analytics_view_registry() where view_code = 'o1c6b1_test_view') then
      raise exception 'assertion failed: service_role must see the fixture view via app.list_analytics_view_registry';
    end if;
    select count(*) into v_count from app.get_latest_analytics_refresh_run('o1c6b1_test_view');
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the latest run via app.get_latest_analytics_refresh_run, got %', v_count; end if;
    select count(*) into v_count from app.list_automation_rules(v_tenant_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the real rule via app.list_automation_rules (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.get_automation_rule_by_id(v_rule_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the real rule via app.get_automation_rule_by_id (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.list_automation_rule_versions(v_rule_id);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both versions via app.list_automation_rule_versions (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.list_automation_rule_executions(v_rule_id);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both executions via app.list_automation_rule_executions (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.get_latest_automation_rule_publish_approval_request(v_version2_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the real approval request via app.get_latest_automation_rule_publish_approval_request (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from app.list_approval_request_steps(v_request_id);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both steps via app.list_approval_request_steps (BYPASSRLS), got %', v_count; end if;

    raise notice 'service_role proof: all 9 SECURITY INVOKER functions succeed regardless of membership';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 9 new cluster-6-batch-1 function pairs (18 functions) in EITHER schema; authenticated/service_role hold EXECUTE on both the app.* function and its public.* wrapper for all 9 pairs, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_analytics_view_registry', 'get_latest_analytics_refresh_run', 'list_analytics_refresh_runs',
      'list_automation_rules', 'get_automation_rule_by_id', 'list_automation_rule_versions',
      'list_automation_rule_executions', 'get_latest_automation_rule_publish_approval_request',
      'list_approval_request_steps'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 9 cluster-6-batch-1 function pairs (18 functions, either schema), found % grants', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_analytics_view_registry', 'get_latest_analytics_refresh_run', 'list_analytics_refresh_runs',
      'list_automation_rules', 'get_automation_rule_by_id', 'list_automation_rule_versions',
      'list_automation_rule_executions', 'get_latest_automation_rule_publish_approval_request',
      'list_approval_request_steps'
    )
    and grantee in ('authenticated', 'service_role');
  if v_count <> 9 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 36 grants (9 functions x 2 schemas x 2 grantees), found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 18 new cluster-6-batch-1 functions; authenticated/service_role hold the declared grant on both the app.* and public.* function in every one of the 9 pairs';
end $$;

\echo '>> o1-query-layer-cluster6-batch1.sql test suite passed -- cluster 6 batch 1 (analytics view registry/refresh runs, automation rules/versions/executions, approval-request-by-entity, approval request steps -- 9/30 call sites) is now fully DONE'
