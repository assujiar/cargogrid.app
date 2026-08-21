-- Real, executable test evidence for IAE-003 (Dashboard Builder, Prompt 331,
-- CG-S14-IAE-003) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000005000001..004.
-- Grep-verified unclaimed against every other *.sql fixture in this directory
-- before use (the exact discipline IAE-002's own reporting-engine.sql fixture
-- collision, found only by a full cumulative db:test run, taught this
-- checkpoint to apply up front). Uses finance_billing_summary/
-- finance_cash_summary as widget bindings -- neither is ever retired by any
-- *.sql fixture in this directory (grep-verified against every
-- retire_report_type call), unlike lead_aging (retired by
-- commercial-reports.sql).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (iaedashco), a global Supreme Admin, a configurer (REP:Configure), a viewer (tenant member, no REP:Configure), and a second tenant (iaedashco2) with one lone member for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
  v_t2_role uuid;
  v_t2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000005000001', 'supreme@iaedashco.test'),
    ('00000000-0000-0000-0000-000005000002', 'configurer@iaedashco.test'),
    ('00000000-0000-0000-0000-000005000003', 'viewer@iaedashco.test'),
    ('00000000-0000-0000-0000-000005000004', 'member@iaedashco2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000005000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaedashco', 'IAE Dashboard Co', 'idem-iaedashco', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaedashco');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaedashco2', 'IAE Dashboard Co 2', 'idem-iaedashco2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaedashco2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000005000002', 'configurer@iaedashco.test', 'Configurer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configurer@iaedashco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000005000003', 'viewer@iaedashco.test', 'Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaedashco.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000005000004', 'member@iaedashco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaedashco2.test'), 'active', 'onboarded', 'tester');

  v_configurer_role := (app.create_role(v_tenant1, 'Dashboard Configurer', 'REP:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(
    v_configurer_draft.id,
    array(select id from app.permissions where resource_module_code = 'REP' and action = 'Configure'),
    'tester'
  );
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'),
    '00000000-0000-0000-0000-000005000002', '00000000-0000-0000-0000-000005000001', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'Beta Configurer', 'REP:Configure, tenant 2', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(
    v_t2_draft.id,
    array(select id from app.permissions where resource_module_code = 'REP' and action = 'Configure'),
    'tester'
  );
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'),
    '00000000-0000-0000-0000-000005000004', '00000000-0000-0000-0000-000005000004', 'tester');
end;
$$;

\echo '>> app.create_tenant_dashboard_draft: REP:Configure-gated; creates the dashboard plus a real version-1 draft in one transaction'
do $$
declare
  v_tenant1 uuid;
  v_dashboard app.tenant_dashboards;
  v_draft app.tenant_dashboard_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaedashco');

  begin
    perform app.create_tenant_dashboard_draft(v_tenant1, 'Should be denied', 'x', '00000000-0000-0000-0000-000005000003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks REP:Configure';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_dashboard from app.create_tenant_dashboard_draft(
    v_tenant1, 'Ops Overview', 'a real test dashboard', '00000000-0000-0000-0000-000005000002', 'tester'
  );
  if v_dashboard.status <> 'draft' or v_dashboard.current_version_id is not null then
    raise exception 'assertion failed: expected a fresh dashboard to be draft with no current_version_id yet';
  end if;

  select * into v_draft from app.tenant_dashboard_versions where dashboard_id = v_dashboard.id and version_number = 1;
  if v_draft.status <> 'draft' then
    raise exception 'assertion failed: expected version 1 to exist and be draft';
  end if;
end;
$$;

\echo '>> app.add_dashboard_widget: rejects unknown/retired codes and unsafe parameters; validates against the report''s own parameter_schema; draft-only'
do $$
declare
  v_tenant1 uuid;
  v_dashboard app.tenant_dashboards;
  v_draft_id uuid;
  v_widget app.tenant_dashboard_widgets;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaedashco');
  select * into v_dashboard from app.tenant_dashboards where tenant_id = v_tenant1 and name = 'Ops Overview';
  v_draft_id := (select id from app.tenant_dashboard_versions where dashboard_id = v_dashboard.id and version_number = 1);

  begin
    perform app.add_dashboard_widget(v_draft_id, 'not_a_real_report', 'x', '{}'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000005000002', 'tester');
    raise exception 'assertion failed: expected report_type_unknown';
  exception
    when no_data_found then
      null; -- expected
  end;

  select * into v_widget from app.add_dashboard_widget(
    v_draft_id, 'finance_billing_summary', 'Billing Summary', jsonb_build_object('x', 0, 'y', 0), '{}'::jsonb,
    '00000000-0000-0000-0000-000005000002', 'tester'
  );
  if v_widget.report_type_code <> 'finance_billing_summary' or v_widget.display_order <> 0 then
    raise exception 'assertion failed: expected the first widget to bind finance_billing_summary at display_order 0';
  end if;

  select * into v_widget from app.add_dashboard_widget(
    v_draft_id, 'finance_cash_summary', 'Cash Summary', jsonb_build_object('x', 1, 'y', 0), '{}'::jsonb,
    '00000000-0000-0000-0000-000005000002', 'tester'
  );
  if v_widget.display_order <> 1 then
    raise exception 'assertion failed: expected the second widget to auto-increment display_order to 1, got %', v_widget.display_order;
  end if;
end;
$$;

\echo '>> app.publish_tenant_dashboard_version: rejects an empty version; publishes, points current_version_id at it, and opens a fresh draft copying the published widgets'
do $$
declare
  v_tenant1 uuid;
  v_dashboard app.tenant_dashboards;
  v_empty_dashboard app.tenant_dashboards;
  v_published app.tenant_dashboard_versions;
  v_new_draft_count integer;
  v_new_draft_widget_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaedashco');

  select * into v_empty_dashboard from app.create_tenant_dashboard_draft(
    v_tenant1, 'Empty Dashboard', '', '00000000-0000-0000-0000-000005000002', 'tester'
  );
  begin
    perform app.publish_tenant_dashboard_version(v_empty_dashboard.id, '00000000-0000-0000-0000-000005000002', 'tester');
    raise exception 'assertion failed: expected dashboard_empty_version -- a version with zero widgets cannot be published';
  exception
    when check_violation then
      null; -- expected
  end;

  select * into v_dashboard from app.tenant_dashboards where tenant_id = v_tenant1 and name = 'Ops Overview';

  select * into v_published from app.publish_tenant_dashboard_version(v_dashboard.id, '00000000-0000-0000-0000-000005000002', 'tester');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the published version to carry status=published';
  end if;

  select * into v_dashboard from app.tenant_dashboards where id = v_dashboard.id;
  if v_dashboard.current_version_id <> v_published.id or v_dashboard.status <> 'published' then
    raise exception 'assertion failed: expected the dashboard to now point current_version_id at the published version';
  end if;

  select count(*) into v_new_draft_count from app.tenant_dashboard_versions
  where dashboard_id = v_dashboard.id and status = 'draft' and version_number = 2;
  if v_new_draft_count <> 1 then
    raise exception 'assertion failed: expected exactly one new draft version (version 2) opened automatically at publish time';
  end if;

  select count(*) into v_new_draft_widget_count from app.tenant_dashboard_widgets w
  join app.tenant_dashboard_versions v on v.id = w.dashboard_version_id
  where v.dashboard_id = v_dashboard.id and v.version_number = 2;
  if v_new_draft_widget_count <> 2 then
    raise exception 'assertion failed: expected the new draft version to carry a copy of both widgets from the published version, got %', v_new_draft_widget_count;
  end if;
end;
$$;

\echo '>> app.remove_dashboard_widget: draft-only, denied against a published version''s own widgets'
do $$
declare
  v_tenant1 uuid;
  v_dashboard app.tenant_dashboards;
  v_published_widget_id uuid;
  v_draft2_widget_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaedashco');
  select * into v_dashboard from app.tenant_dashboards where tenant_id = v_tenant1 and name = 'Ops Overview';

  select w.id into v_published_widget_id from app.tenant_dashboard_widgets w
  join app.tenant_dashboard_versions v on v.id = w.dashboard_version_id
  where v.id = v_dashboard.current_version_id limit 1;

  begin
    perform app.remove_dashboard_widget(v_published_widget_id, '00000000-0000-0000-0000-000005000002', 'tester');
    raise exception 'assertion failed: expected dashboard_version_not_editable -- the published version''s own widgets are immutable';
  exception
    when check_violation then
      null; -- expected
  end;

  select w.id into v_draft2_widget_id from app.tenant_dashboard_widgets w
  join app.tenant_dashboard_versions v on v.id = w.dashboard_version_id
  where v.dashboard_id = v_dashboard.id and v.version_number = 2 limit 1;

  perform app.remove_dashboard_widget(v_draft2_widget_id, '00000000-0000-0000-0000-000005000002', 'tester');
  if exists (select 1 from app.tenant_dashboard_widgets where id = v_draft2_widget_id) then
    raise exception 'assertion failed: expected the draft-version widget to be genuinely removed';
  end if;
end;
$$;

\echo '>> app.rollback_tenant_dashboard: points current_version_id at an older published version only, never a draft; cross-tenant isolation holds'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_dashboard app.tenant_dashboards;
  v_v1_id uuid;
  v_draft2_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaedashco');
  v_tenant2 := (select id from app.tenants where slug = 'iaedashco2');
  select * into v_dashboard from app.tenant_dashboards where tenant_id = v_tenant1 and name = 'Ops Overview';
  v_v1_id := v_dashboard.current_version_id;
  v_draft2_id := (select id from app.tenant_dashboard_versions where dashboard_id = v_dashboard.id and version_number = 2);

  begin
    perform app.rollback_tenant_dashboard(v_dashboard.id, v_draft2_id, '00000000-0000-0000-0000-000005000002', 'tester');
    raise exception 'assertion failed: expected dashboard_target_version_invalid -- version 2 is still a draft, never published';
  exception
    when check_violation then
      null; -- expected
  end;

  -- Tier C fix (C-05 discipline): a tenant-2 actor has ZERO relationship to
  -- tenant-1's own dashboard, so this now raises the SAME dashboard_not_found
  -- a genuinely missing id would produce, never a tenant-id-disclosing
  -- insufficient_authority. (Before the Tier C fix this raised
  -- insufficient_privilege, which is exactly the oracle the fix closes.)
  begin
    perform app.rollback_tenant_dashboard(v_dashboard.id, v_v1_id, '00000000-0000-0000-0000-000005000004', 'tester');
    raise exception 'assertion failed: expected no_data_found -- a tenant-2 actor with zero relationship to tenant-1 must see the same not_found a missing id would produce, never a disclosing insufficient_authority';
  exception
    when no_data_found then
      null; -- expected
  end;

  -- publish the draft (version 2) so we have a real second published version to roll back FROM
  perform app.publish_tenant_dashboard_version(v_dashboard.id, '00000000-0000-0000-0000-000005000002', 'tester');

  select * into v_dashboard from app.tenant_dashboards where id = v_dashboard.id;
  if v_dashboard.current_version_id = v_v1_id then
    raise exception 'assertion failed: expected current_version_id to have moved to the newly published version 2';
  end if;

  perform app.rollback_tenant_dashboard(v_dashboard.id, v_v1_id, '00000000-0000-0000-0000-000005000002', 'tester');
  select * into v_dashboard from app.tenant_dashboards where id = v_dashboard.id;
  if v_dashboard.current_version_id <> v_v1_id then
    raise exception 'assertion failed: expected rollback to point current_version_id back at version 1';
  end if;
end;
$$;

\echo '>> Tier C fix regression (C-05 discipline): app.add_dashboard_widget/app.remove_dashboard_widget/app.publish_tenant_dashboard_version all now fold a cross-tenant caller into the SAME not_found a genuinely missing id would produce, never a tenant-id-disclosing insufficient_authority (mirrors app.rollback_tenant_dashboard, fixed above)'
do $$
declare
  v_tenant1 uuid;
  v_dashboard app.tenant_dashboards;
  v_draft_version_id uuid;
  v_widget_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaedashco');
  select * into v_dashboard from app.tenant_dashboards where tenant_id = v_tenant1 and name = 'Ops Overview';
  v_draft_version_id := (select id from app.tenant_dashboard_versions where dashboard_id = v_dashboard.id and version_number = 2);
  select w.id into v_widget_id from app.tenant_dashboard_widgets w where w.dashboard_version_id = v_draft_version_id limit 1;

  begin
    perform app.add_dashboard_widget(v_draft_version_id, 'finance_billing_summary', 'x', '{}'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000005000004', 'tester');
    raise exception 'assertion failed: expected no_data_found -- a tenant-2 actor with zero relationship to tenant-1''s own dashboard version must see the same not_found a missing id would produce';
  exception
    when no_data_found then null;
  end;

  begin
    perform app.remove_dashboard_widget(v_widget_id, '00000000-0000-0000-0000-000005000004', 'tester');
    raise exception 'assertion failed: expected no_data_found -- a tenant-2 actor with zero relationship to tenant-1''s own widget must see the same not_found a missing id would produce';
  exception
    when no_data_found then null;
  end;

  begin
    perform app.publish_tenant_dashboard_version(v_dashboard.id, '00000000-0000-0000-0000-000005000004', 'tester');
    raise exception 'assertion failed: expected no_data_found -- a tenant-2 actor with zero relationship to tenant-1''s own dashboard must see the same not_found a missing id would produce';
  exception
    when no_data_found then null;
  end;

  -- a genuinely missing id produces the IDENTICAL error class for all four functions -- the oracle is closed, not merely relabelled
  begin
    perform app.add_dashboard_widget('00000000-0000-0000-0000-0000000000ff', 'finance_billing_summary', 'x', '{}'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000005000002', 'tester');
    raise exception 'assertion failed: expected no_data_found for a genuinely nonexistent dashboard_version_id';
  exception
    when no_data_found then null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-003 function; authenticated has no direct INSERT/UPDATE/DELETE on any new table'
do $$
declare
  v_leak_count integer;
begin
  select count(*) into v_leak_count
  from information_schema.role_routine_grants
  where grantee = 'anon'
    and routine_schema = 'app'
    and routine_name in ('create_tenant_dashboard_draft', 'add_dashboard_widget', 'remove_dashboard_widget', 'publish_tenant_dashboard_version', 'rollback_tenant_dashboard');
  if v_leak_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grant on any new IAE-003 function, found %', v_leak_count;
  end if;

  select count(*) into v_leak_count
  from information_schema.role_table_grants
  where grantee = 'authenticated'
    and table_schema = 'app'
    and table_name in ('tenant_dashboards', 'tenant_dashboard_versions', 'tenant_dashboard_widgets')
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE');
  if v_leak_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grant on any new IAE-003 table, found %', v_leak_count;
  end if;
end;
$$;

\echo '>> audit trail: create/publish/rollback each recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where action = 'create_tenant_dashboard_draft' and resource_type = 'app.tenant_dashboards';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least one create_tenant_dashboard_draft audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where action = 'publish_tenant_dashboard_version' and resource_type = 'app.tenant_dashboard_versions';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least one publish_tenant_dashboard_version audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where action = 'rollback_tenant_dashboard' and resource_type = 'app.tenant_dashboards';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least one rollback_tenant_dashboard audit event, found %', v_count;
  end if;
end;
$$;

\echo 'ALL IAE-003 (Dashboard Builder) db-test assertions passed.'
