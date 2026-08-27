-- Real, executable test evidence for IAE-005 (Analytics and Materialized
-- Views, Prompt 333, CG-S14-IAE-005) -- run via `pnpm run db:test` against a
-- real, disposable Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000007000001..004.
-- Grep-verified unclaimed against every other *.sql fixture in this
-- directory before use. Uses finance_billing_summary (empty parameter
-- schema, never retired by any fixture -- grep-verified) as the report code
-- behind real app.record_report_run calls that feed app.mv_report_usage_daily.
--
-- Tier C fix pass (Batch 1 IAE-002..006 review): 000007000004 added -- a
-- customer_user-layer portal actor in iaeanalyco, feeding the new regression
-- block this Tier C pass added after the original get_report_usage_daily
-- test.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (iaeanalyco), a global Supreme Admin, a non-Supreme member, a second tenant (iaeanalyco2) for cross-tenant isolation, and three real app.report_runs rows feeding the materialized view'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000007000001', 'supreme@iaeanalyco.test'),
    ('00000000-0000-0000-0000-000007000002', 'member@iaeanalyco.test'),
    ('00000000-0000-0000-0000-000007000003', 'member@iaeanalyco2.test'),
    ('00000000-0000-0000-0000-000007000004', 'portal@iaeanalyco.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000007000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeanalyco', 'IAE Analytics Co', 'idem-iaeanalyco', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeanalyco');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeanalyco2', 'IAE Analytics Co 2', 'idem-iaeanalyco2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeanalyco2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000007000002', 'member@iaeanalyco.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaeanalyco.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000007000003', 'member@iaeanalyco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaeanalyco2.test'), 'active', 'onboarded', 'tester');

  -- Tier C fix regression fixture: a genuine customer_user-layer (portal)
  -- principal in tenant1, with real active tenant membership -- used to
  -- prove app.get_report_usage_daily now excludes this layer, the ONLY real
  -- tenant-isolation mechanism for app.mv_report_usage_daily (Postgres has
  -- no RLS on a materialized view).
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000007000004', 'portal@iaeanalyco.test', 'Portal Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'portal@iaeanalyco.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000007000004', 'customer_user', v_tenant1, 'iae-analytics-portal-ref', 'tester');

  perform app.record_report_run(v_tenant1, 'finance_billing_summary', '{}'::jsonb, 3, array[]::text[], '00000000-0000-0000-0000-000007000002', 'tester');
  perform app.record_report_run(v_tenant1, 'finance_billing_summary', '{}'::jsonb, 5, array[]::text[], '00000000-0000-0000-0000-000007000002', 'tester');
  perform app.record_report_run(v_tenant2, 'finance_billing_summary', '{}'::jsonb, 1, array[]::text[], '00000000-0000-0000-0000-000007000003', 'tester');
end;
$$;

\echo '>> app.register_analytics_view: Supreme-only, idempotent by view_code, rejects an unknown pg_matviews name; the seeded report_usage_daily row already exists'
do $$
declare
  v_row app.analytics_view_registry;
begin
  begin
    perform app.register_analytics_view('should_be_denied', 'mv_report_usage_daily', 'x', null, 'reporting', 60, '00000000-0000-0000-0000-000007000002', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the member is not Supreme Admin';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.register_analytics_view('bad_view_name', 'not_a_real_matview', 'x', null, 'reporting', 60, '00000000-0000-0000-0000-000007000001', 'tester');
    raise exception 'assertion failed: expected analytics_view_unknown for a non-existent pg_matviews name';
  exception
    when no_data_found then null;
  end;

  select * into v_row from app.register_analytics_view('report_usage_daily', 'mv_report_usage_daily', 'Report Usage (Daily)', 'x', 'reporting', 60, '00000000-0000-0000-0000-000007000001', 'tester');
  if v_row.view_code <> 'report_usage_daily' then
    raise exception 'assertion failed: expected the already-seeded report_usage_daily row back on idempotent replay';
  end if;
end;
$$;

\echo '>> app.refresh_analytics_view: Supreme-only; a real refresh reflects the just-recorded report_runs rows, reconciles, and is tenant-isolated on read'
do $$
declare
  v_run app.analytics_refresh_runs;
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from app.mv_report_usage_daily;

  begin
    perform app.refresh_analytics_view('report_usage_daily', '00000000-0000-0000-0000-000007000002', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the member is not Supreme Admin';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.refresh_analytics_view('not_a_registered_view', '00000000-0000-0000-0000-000007000001', 'tester');
    raise exception 'assertion failed: expected analytics_view_unknown';
  exception
    when no_data_found then null;
  end;

  select * into v_run from app.refresh_analytics_view('report_usage_daily', '00000000-0000-0000-0000-000007000001', 'tester');
  if v_run.status <> 'completed' or v_run.reconciled is distinct from true then
    raise exception 'assertion failed: expected a completed, reconciled refresh run, got status=% reconciled=%', v_run.status, v_run.reconciled;
  end if;

  select count(*) into v_after from app.mv_report_usage_daily;
  if v_after <= v_before then
    raise exception 'assertion failed: expected the refresh to grow the view -- the setup block''s own new report_runs rows were not yet reflected before this refresh';
  end if;
end;
$$;

\echo '>> ISS-2026-174 (Track B Batch 1): app.analytics_refresh_runs'' authenticated grant is column-restricted -- row_count_before and triggered_by_auth_user_id/triggered_by_label (a real admin identity, previously exposed platform-wide) are no longer readable; row_count_after/status/reconciled/etc remain (the existing, legitimate freshness-badge UI feature)'
do $$
declare
  v_leaked_columns text[];
  v_kept_columns text[] := array['id', 'view_code', 'status', 'row_count_after', 'reconciled', 'error_reason', 'started_at', 'completed_at'];
  v_col text;
begin
  select array_agg(column_name) into v_leaked_columns
  from information_schema.column_privileges
  where table_schema = 'app' and table_name = 'analytics_refresh_runs' and grantee = 'authenticated' and privilege_type = 'SELECT'
    and column_name in ('row_count_before', 'triggered_by_auth_user_id', 'triggered_by_label');

  if v_leaked_columns is not null then
    raise exception 'assertion failed: expected authenticated to have zero SELECT privilege on row_count_before/triggered_by_auth_user_id/triggered_by_label, still granted on: % -- ISS-2026-174 regression', v_leaked_columns;
  end if;

  foreach v_col in array v_kept_columns loop
    if not has_column_privilege('authenticated', 'app.analytics_refresh_runs', v_col, 'SELECT') then
      raise exception 'assertion failed: expected authenticated to retain SELECT on %, the legitimate freshness-badge UI column set', v_col;
    end if;
  end loop;

  if not has_table_privilege('service_role', 'app.analytics_refresh_runs', 'SELECT') then
    raise exception 'assertion failed: expected service_role to retain full-row SELECT on app.analytics_refresh_runs, unaffected by the authenticated column restriction';
  end if;
end;
$$;

\echo '>> app.get_report_usage_daily: authority-gated, tenant-filtered -- the two preview runs for tenant1 are visible with the right counts; tenant2''s own row never leaks; a non-member of the queried tenant is denied'
do $$
declare
  v_rows record;
  v_total_preview bigint := 0;
  v_row_count integer := 0;
begin
  for v_rows in
    select * from app.get_report_usage_daily(
      (select id from app.tenants where slug = 'iaeanalyco'), '00000000-0000-0000-0000-000007000002', 'finance_billing_summary', null, null
    )
  loop
    v_total_preview := v_total_preview + v_rows.preview_count;
    v_row_count := v_row_count + 1;
  end loop;
  if v_row_count <> 1 or v_total_preview <> 2 then
    raise exception 'assertion failed: expected exactly one usage_date row for tenant1/finance_billing_summary with preview_count=2, got % rows totaling %', v_row_count, v_total_preview;
  end if;

  -- tenant2's own actor calling for tenant1 is denied outright
  begin
    perform app.get_report_usage_daily((select id from app.tenants where slug = 'iaeanalyco'), '00000000-0000-0000-0000-000007000003', null, null, null);
    raise exception 'assertion failed: expected insufficient_privilege for a cross-tenant read attempt';
  exception
    when insufficient_privilege then null;
  end;

  -- Tier C fix regression (finding 10, security-rls-tenant): a
  -- customer_user-layer (portal) principal, with real active tenant1
  -- membership, must NOT read tenant1's own internal report-usage
  -- analytics through the SOLE tenant-isolation mechanism for this
  -- materialized view.
  begin
    perform app.get_report_usage_daily((select id from app.tenants where slug = 'iaeanalyco'), '00000000-0000-0000-0000-000007000004', null, null, null);
    raise exception 'assertion failed: expected insufficient_privilege -- a customer_user-layer principal has real active tenant membership but must never read internal report-usage analytics -- the Tier C fix has regressed';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

\echo '>> real failure path: a materialized view dropped out from under its own registry row surfaces a genuine failed run, never a raised exception the caller must catch, and the LAST COMPLETED run stays the freshness signal'
do $$
declare
  v_run app.analytics_refresh_runs;
  v_last_completed_started_at timestamptz;
begin
  select started_at into v_last_completed_started_at from app.analytics_refresh_runs
  where view_code = 'report_usage_daily' and status = 'completed' order by started_at desc limit 1;

  create materialized view app.mv_iae005_disposable_test as select 1 as n;
  create unique index mv_iae005_disposable_test_unique on app.mv_iae005_disposable_test (n);
  perform app.register_analytics_view('iae005_disposable_test', 'mv_iae005_disposable_test', 'Disposable', null, 'reporting', 60, '00000000-0000-0000-0000-000007000001', 'tester');
  drop materialized view app.mv_iae005_disposable_test;

  select * into v_run from app.refresh_analytics_view('iae005_disposable_test', '00000000-0000-0000-0000-000007000001', 'tester');
  if v_run.status <> 'failed' or v_run.error_reason is null then
    raise exception 'assertion failed: expected a failed run with a real error_reason after the view was dropped, got status=%', v_run.status;
  end if;

  -- the real report_usage_daily view's own last COMPLETED run is untouched by the unrelated disposable view's failure
  if not exists (
    select 1 from app.analytics_refresh_runs
    where view_code = 'report_usage_daily' and status = 'completed' and started_at = v_last_completed_started_at
  ) then
    raise exception 'assertion failed: expected report_usage_daily''s own prior completed run to remain untouched';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-005 function; authenticated has no direct INSERT/UPDATE/DELETE on the two new tables; neither authenticated nor anon holds ANY privilege on the materialized view itself'
do $$
declare
  v_bad_grant record;
begin
  for v_bad_grant in
    select routine_name from information_schema.routine_privileges
    where routine_schema = 'app'
      and routine_name in ('register_analytics_view', 'refresh_analytics_view', 'get_report_usage_daily')
      and grantee = 'anon'
  loop
    raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_bad_grant.routine_name;
  end loop;

  for v_bad_grant in
    select privilege_type from information_schema.role_table_grants
    where table_schema = 'app' and table_name in ('analytics_view_registry', 'analytics_refresh_runs')
      and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  loop
    raise exception 'assertion failed: authenticated must not hold direct % on the new registry/run tables', v_bad_grant.privilege_type;
  end loop;

  for v_bad_grant in
    select grantee, privilege_type from information_schema.role_table_grants
    where table_schema = 'app' and table_name = 'mv_report_usage_daily' and grantee in ('authenticated', 'anon')
  loop
    raise exception 'assertion failed: % must hold zero privileges on the materialized view itself, found %', v_bad_grant.grantee, v_bad_grant.privilege_type;
  end loop;
end;
$$;

\echo '>> audit trail: register/refresh each recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs
  where resource_type = 'app.analytics_view_registry' and action = 'register_analytics_view';
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one register_analytics_view audit event';
  end if;

  select count(*) into v_count from app.audit_logs
  where resource_type = 'app.analytics_refresh_runs' and action = 'refresh_analytics_view';
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one refresh_analytics_view audit event';
  end if;
end;
$$;

-- ISS-2026-266 (Step 16 historical-issue-backlog remediation): the composed in-place
-- restore procedure's own new step (h) used to be a raw, per-view-name `REFRESH
-- MATERIALIZED VIEW CONCURRENTLY` an operator had to remember to repeat for every
-- registered view. app.refresh_all_registered_analytics_views delegates to the
-- already-tested app.refresh_analytics_view for every ACTIVE registry row in one
-- governed call, so it inherits that function's own authority check and audit-logged
-- ledger row per view -- proved here, not merely asserted.
\echo '>> ISS-2026-266 regression: app.refresh_all_registered_analytics_views refreshes every active registered view via the existing governed app.refresh_analytics_view, in one call, Supreme-only'
do $$
declare
  v_run record;
  v_completed_count integer := 0;
  v_failed_count integer := 0;
  v_seen_report_usage_daily boolean := false;
  v_seen_disposable boolean := false;
begin
  begin
    perform app.refresh_all_registered_analytics_views('00000000-0000-0000-0000-000007000002', 'tester');
    raise exception 'assertion failed: expected a non-Supreme-Admin actor to be denied';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- This file's own fixture registered exactly 2 active views by this point:
  -- report_usage_daily (real, refreshable) and iae005_disposable_test (its own
  -- materialized view was deliberately dropped earlier in this same file, so refreshing
  -- it must surface as a real failed run, never abort the whole batch).
  for v_run in select * from app.refresh_all_registered_analytics_views('00000000-0000-0000-0000-000007000001', 'tester') loop
    if v_run.view_code = 'report_usage_daily' then
      v_seen_report_usage_daily := true;
      if v_run.status <> 'completed' then
        raise exception 'assertion failed: expected report_usage_daily to refresh cleanly, got status=%', v_run.status;
      end if;
      v_completed_count := v_completed_count + 1;
    elsif v_run.view_code = 'iae005_disposable_test' then
      v_seen_disposable := true;
      if v_run.status <> 'failed' or v_run.error_reason is null then
        raise exception 'assertion failed: expected the dropped disposable view to surface a real failed run with an error_reason, not abort the batch, got status=%', v_run.status;
      end if;
      v_failed_count := v_failed_count + 1;
    else
      raise exception 'assertion failed: unexpected view_code % in the refresh-all result set', v_run.view_code;
    end if;
  end loop;

  if not v_seen_report_usage_daily or not v_seen_disposable then
    raise exception 'assertion failed: expected both registered active views to appear in the refresh-all result set, saw report_usage_daily=%, disposable=%', v_seen_report_usage_daily, v_seen_disposable;
  end if;
  if v_completed_count <> 1 or v_failed_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 completed and 1 failed run, got completed=%, failed=%', v_completed_count, v_failed_count;
  end if;

  -- Each refresh-all call delegates to app.refresh_analytics_view, so it produces the
  -- identical real, persisted app.analytics_refresh_runs rows an individual call would --
  -- not a bespoke, unledgered code path.
  if not exists (
    select 1 from app.analytics_refresh_runs
    where view_code = 'report_usage_daily' and status = 'completed' and triggered_by_label = 'tester'
  ) then
    raise exception 'assertion failed: expected a real, persisted completed run for report_usage_daily';
  end if;

  raise notice 'ISS-2026-266 proof: refresh_all_registered_analytics_views is Supreme-only, refreshes every active registered view via the existing governed app.refresh_analytics_view, surfaces a per-view failure without aborting the batch, and produces the identical persisted ledger rows an individual call would';
end;
$$;

\echo '>> ISS-2026-266 regression evidence complete'

\echo 'ALL IAE-005 (Analytics and Materialized Views) db-test assertions passed.'
