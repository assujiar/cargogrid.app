-- Real, executable test evidence for COM-159 (Commercial Reports, CG-S7-COM-018) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a global Supreme Admin, a rep (COM:Create/Edit/View, no Export) and an exporter (COM:Create/Edit/View/Export) in tenant 1, a lone member in tenant 2'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_exporter_role uuid;
  v_exporter_draft app.role_versions;
  v_t2_role uuid;
  v_t2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009501', 'supreme@cargogrid.test'),
    ('00000000-0000-0000-0000-000000009502', 'tenantadmin@acmereport.test'),
    ('00000000-0000-0000-0000-000000009503', 'rep@acmereport.test'),
    ('00000000-0000-0000-0000-000000009504', 'exporter@acmereport.test'),
    ('00000000-0000-0000-0000-000000009505', 'member@betareport.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009501', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmereport', 'Acme Report Co', 'idem-acmereport', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmereport');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betareport', 'Beta Report Co', 'idem-betareport', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betareport');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009502', 'tenantadmin@acmereport.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmereport.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009502', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009503', 'rep@acmereport.test', 'Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmereport.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009504', 'exporter@acmereport.test', 'Exporter', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'exporter@acmereport.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009505', 'member@betareport.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@betareport.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Report Rep', 'no export', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009503', '00000000-0000-0000-0000-000000009502', 'tester');

  v_exporter_role := (app.create_role(v_tenant1, 'Report Exporter', 'export-gated', 'tester')).id;
  v_exporter_draft := app.create_role_version(v_exporter_role, 'tester');
  perform app.set_role_version_permissions(
    v_exporter_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'Export')),
    'tester'
  );
  perform app.publish_role_version(v_exporter_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_exporter_role and status = 'published'),
    '00000000-0000-0000-0000-000000009504', '00000000-0000-0000-0000-000000009502', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'Beta Role', 'cross-tenant isolation fixture', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(
    v_t2_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'Export')),
    'tester'
  );
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'),
    '00000000-0000-0000-0000-000000009505', '00000000-0000-0000-0000-000000009505', 'tester');
end;
$$;

\echo '>> app.report_types: seven report types seeded at status=active, code-shipped catalogue (not tenant-scoped)'
do $$
declare
  v_active_count integer;
begin
  select count(*) into v_active_count from app.report_types where status = 'active';
  if v_active_count <> 7 then
    raise exception 'assertion failed: expected 7 active report types, got %', v_active_count;
  end if;

  if not exists (select 1 from app.report_types where code = 'lead_aging' and source_function = 'get_dashboard_lead_aging') then
    raise exception 'assertion failed: expected lead_aging to name get_dashboard_lead_aging as its source_function';
  end if;
end;
$$;

\echo '>> app.register_report_type: idempotent and Supreme-Admin-only'
do $$
declare
  v_first app.report_types;
  v_second app.report_types;
begin
  begin
    perform app.register_report_type('lead_aging', 'Should be denied', 'x', 'get_dashboard_lead_aging', '00000000-0000-0000-0000-000000009503', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the rep is not Supreme Admin';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_first from app.register_report_type('custom_test_report', 'Custom Test Report', 'a synthetic report for this test only', 'get_dashboard_lead_aging', '00000000-0000-0000-0000-000000009501', 'tester');
  select * into v_second from app.register_report_type('custom_test_report', 'Different name -- ignored', 'ignored', 'get_dashboard_lead_aging', '00000000-0000-0000-0000-000000009501', 'tester');
  if v_first.code is distinct from v_second.code or v_second.name <> 'Custom Test Report' then
    raise exception 'assertion failed: expected the second registration to return the identical existing row unchanged, got first.code=% second.code=% second.name=%', v_first.code, v_second.code, v_second.name;
  end if;
end;
$$;

\echo '>> app.record_report_run: authority-gated (no tenant membership denied), unknown/retired report types rejected, a successful preview run is recorded and audited'
do $$
declare
  v_tenant1 uuid;
  v_run app.report_runs;
  v_audit_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmereport');

  begin
    perform app.record_report_run(v_tenant1, 'lead_aging', '{}'::jsonb, 4, array[]::text[], '00000000-0000-0000-0000-000000009505', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the beta member has no membership in acmereport';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.record_report_run(v_tenant1, 'not_a_real_report', '{}'::jsonb, 0, array[]::text[], '00000000-0000-0000-0000-000000009503', 'tester');
    raise exception 'assertion failed: expected no_data_found -- unknown report_type_code';
  exception
    when no_data_found then
      null; -- expected
  end;

  select * into v_run from app.record_report_run(
    v_tenant1, 'lead_aging', jsonb_build_object('orgUnitId', null, 'ownerUserId', null), 4, array[]::text[],
    '00000000-0000-0000-0000-000000009503', 'tester'
  );
  if v_run.run_type <> 'preview' or v_run.status <> 'completed' or v_run.row_count <> 4 then
    raise exception 'assertion failed: expected run_type=preview status=completed row_count=4, got run_type=% status=% row_count=%', v_run.run_type, v_run.status, v_run.row_count;
  end if;

  select count(*) into v_audit_count from app.audit_logs where tenant_id = v_tenant1 and action = 'record_report_run' and resource_id = v_run.id;
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 audit_logs entry for this report run, got %', v_audit_count;
  end if;

  perform app.retire_report_type('lead_aging', '00000000-0000-0000-0000-000000009501', 'tester');
  begin
    perform app.record_report_run(v_tenant1, 'lead_aging', '{}'::jsonb, 0, array[]::text[], '00000000-0000-0000-0000-000000009503', 'tester');
    raise exception 'assertion failed: expected check_violation -- lead_aging was just retired';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> app.enqueue_report_export: COM:Export-gated (rep denied, exporter allowed), enqueues a real report_generation job and links it on the report_runs row'
do $$
declare
  v_tenant1 uuid;
  v_run app.report_runs;
  v_job app.jobs;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmereport');

  begin
    perform app.enqueue_report_export(v_tenant1, 'pipeline_summary', '{}'::jsonb, '00000000-0000-0000-0000-000000009503', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the rep lacks COM:Export';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_run from app.enqueue_report_export(
    v_tenant1, 'pipeline_summary', jsonb_build_object('orgUnitId', null), '00000000-0000-0000-0000-000000009504', 'tester'
  );
  if v_run.run_type <> 'export' or v_run.status <> 'queued' or v_run.job_id is null then
    raise exception 'assertion failed: expected run_type=export status=queued with a real job_id, got run_type=% status=% job_id=%', v_run.run_type, v_run.status, v_run.job_id;
  end if;

  select * into v_job from app.jobs where job_id = v_run.job_id;
  if v_job.job_type <> 'report_generation' or v_job.status <> 'pending' or (v_job.payload ->> 'report_type_code') <> 'pipeline_summary' then
    raise exception 'assertion failed: expected a real pending report_generation job carrying report_type_code=pipeline_summary, got type=% status=% payload=%', v_job.job_type, v_job.status, v_job.payload;
  end if;
end;
$$;

\echo '>> app.report_runs: tenant-wide RLS visibility (the rep, who did not request the export run, still sees it -- management visibility, not per-owner privacy), cross-tenant isolation proven'
do $$
declare
  v_tenant1 uuid;
  v_rep_count integer;
  v_foreign_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmereport');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009503", "role": "authenticated"}';
  select count(*) into v_rep_count from app.report_runs where tenant_id = v_tenant1 and report_type_code = 'pipeline_summary';
  if v_rep_count <> 1 then
    raise exception 'assertion failed: expected the rep to see the exporter''s own export run (tenant-wide visibility), got %', v_rep_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009505", "role": "authenticated"}';
  select count(*) into v_foreign_count from app.report_runs where tenant_id = v_tenant1;
  if v_foreign_count <> 0 then
    raise exception 'assertion failed: expected the beta-tenant member to see 0 rows for a foreign tenant, got %', v_foreign_count;
  end if;
  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any COM-159 report function (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('register_report_type', 'retire_report_type', 'record_report_run', 'enqueue_report_export')
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on any COM-159 report function, found %', v_count;
  end if;
end;
$$;
