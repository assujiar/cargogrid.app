-- Real, executable test evidence for IAE-002 (Reporting Engine, Prompt 330,
-- CG-S14-IAE-002) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Tests only the NEW governance layer this capability adds
-- (definition versioning, parameter-schema validation, cancel) on top of the
-- already-`VERIFIED` COM-159 report_types/report_runs catalog, which
-- scripts/db-tests/commercial-reports.sql (and operations-reports.sql,
-- finance-dashboard.sql, procurement-vendor-dashboard-reports.sql) already
-- cover for the original catalogue behavior -- not re-tested here.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000004000001..006.
-- Tier C fix pass (Batch 1 IAE-002..006 review): 000004000006 added -- a
-- REP:Export-only (no COM:Export) holder in iaereportco, feeding the new
-- regression block this Tier C pass added after the original
-- cancel_report_run test.
-- A first draft picked 00000000-0000-0000-0000-000000033001..005, which
-- collided with the already-claimed range scripts/db-tests/finance-idempotent-posting.sql
-- uses -- caught only by a full cumulative `db:test` run (every file shares one
-- disposable database), not by this file running alone. Re-verified this range
-- against every *.sql fixture in this directory before use.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (iaereportco), a global Supreme Admin, a tenant_admin, a plain member (COM:View only, no Export), an exporter (COM:View+Export), and a second tenant (iaereportco2) with one lone member for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_member_role uuid;
  v_member_draft app.role_versions;
  v_exporter_role uuid;
  v_exporter_draft app.role_versions;
  v_t2_role uuid;
  v_t2_draft app.role_versions;
  v_rep_exporter_role uuid;
  v_rep_exporter_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000004000001', 'supreme@iaereportco.test'),
    ('00000000-0000-0000-0000-000004000002', 'tenantadmin@iaereportco.test'),
    ('00000000-0000-0000-0000-000004000003', 'member@iaereportco.test'),
    ('00000000-0000-0000-0000-000004000004', 'exporter@iaereportco.test'),
    ('00000000-0000-0000-0000-000004000005', 'member@iaereportco2.test'),
    ('00000000-0000-0000-0000-000004000006', 'repexporter@iaereportco.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000004000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaereportco', 'IAE Report Co', 'idem-iaereportco', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaereportco');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaereportco2', 'IAE Report Co 2', 'idem-iaereportco2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaereportco2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000004000002', 'tenantadmin@iaereportco.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@iaereportco.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000004000002', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000004000003', 'member@iaereportco.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaereportco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000004000004', 'exporter@iaereportco.test', 'Exporter', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'exporter@iaereportco.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000004000005', 'member@iaereportco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaereportco2.test'), 'active', 'onboarded', 'tester');

  -- Tier C fix regression fixture: REP:Export-only, deliberately NO
  -- COM:Export -- proves app.cancel_report_run's widened override authority
  -- (finding 12) without depending on the legacy COM:Export path at all.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000004000006', 'repexporter@iaereportco.test', 'REP Exporter', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repexporter@iaereportco.test'), 'active', 'onboarded', 'tester');

  v_member_role := (app.create_role(v_tenant1, 'Report Member', 'view only, no export', 'tester')).id;
  v_member_draft := app.create_role_version(v_member_role, 'tester');
  perform app.set_role_version_permissions(
    v_member_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action = 'View'),
    'tester'
  );
  perform app.publish_role_version(v_member_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_member_role and status = 'published'),
    '00000000-0000-0000-0000-000004000003', '00000000-0000-0000-0000-000004000002', 'tester');

  v_exporter_role := (app.create_role(v_tenant1, 'Report Exporter', 'view + export', 'tester')).id;
  v_exporter_draft := app.create_role_version(v_exporter_role, 'tester');
  perform app.set_role_version_permissions(
    v_exporter_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('View', 'Export')),
    'tester'
  );
  perform app.publish_role_version(v_exporter_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_exporter_role and status = 'published'),
    '00000000-0000-0000-0000-000004000004', '00000000-0000-0000-0000-000004000002', 'tester');

  -- Tier C fix regression fixture role: REP:Export only, deliberately NO
  -- COM:Export at all -- proves app.cancel_report_run's widened OR-fallback
  -- (finding 12) actually reaches the new REP:Export branch, not merely a
  -- re-exercise of the pre-existing COM:Export path.
  v_rep_exporter_role := (app.create_role(v_tenant1, 'REP Exporter', 'REP:Export only, no COM:Export -- Tier C regression fixture', 'tester')).id;
  v_rep_exporter_draft := app.create_role_version(v_rep_exporter_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_exporter_draft.id,
    array(select id from app.permissions where resource_module_code = 'REP' and action = 'Export'),
    'tester'
  );
  perform app.publish_role_version(v_rep_exporter_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_exporter_role and status = 'published'),
    '00000000-0000-0000-0000-000004000006', '00000000-0000-0000-0000-000004000002', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'Beta Role', 'cross-tenant isolation fixture', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(
    v_t2_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('View', 'Export')),
    'tester'
  );
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'),
    '00000000-0000-0000-0000-000004000005', '00000000-0000-0000-0000-000004000005', 'tester');
end;
$$;

\echo '>> app.report_type_versions: every pre-existing report_types row was backfilled to exactly one version_number=1 row copying its own current column values'
do $$
declare
  v_orphan_count integer;
  v_lead_v1 app.report_type_versions;
begin
  select count(*) into v_orphan_count from app.report_types t
  where not exists (select 1 from app.report_type_versions v where v.report_type_code = t.code and v.version_number = 1);
  if v_orphan_count <> 0 then
    raise exception 'assertion failed: expected every report_types row to have a backfilled version 1, % row(s) missing one', v_orphan_count;
  end if;

  select * into v_lead_v1 from app.report_type_versions where report_type_code = 'lead_aging' and version_number = 1;
  if v_lead_v1.source_function <> 'get_dashboard_lead_aging' then
    raise exception 'assertion failed: expected lead_aging version 1 to copy its own source_function, got %', v_lead_v1.source_function;
  end if;
  if v_lead_v1.parameter_schema <> '{}'::jsonb then
    raise exception 'assertion failed: expected every pre-existing report to backfill an empty parameter_schema, got %', v_lead_v1.parameter_schema;
  end if;
end;
$$;

\echo '>> app.register_report_type + app.publish_report_type_version: a fresh test report type, versioned with a real parameter_schema; Supreme-only; prior evidence (an already-recorded v1 run) is never rewritten to point at the new version'
do $$
declare
  v_type app.report_types;
  v_v1_run app.report_runs;
  v_v2 app.report_type_versions;
  v_version_count integer;
begin
  select * into v_type from app.register_report_type(
    'iae_test_report', 'IAE Test Report', 'a synthetic report for IAE-002 testing only',
    'get_dashboard_lead_aging', '00000000-0000-0000-0000-000004000001', 'tester'
  );

  -- a v1 run recorded before any version is ever published (empty schema, no contract yet)
  select * into v_v1_run from app.record_report_run(
    (select id from app.tenants where slug = 'iaereportco'), 'iae_test_report', '{}'::jsonb, 3, array[]::text[],
    '00000000-0000-0000-0000-000004000003', 'tester'
  );

  begin
    perform app.publish_report_type_version(
      'iae_test_report', 'get_dashboard_lead_aging',
      jsonb_build_object('currency', jsonb_build_object('type', 'string', 'required', true)),
      'v2: requires a currency parameter', '00000000-0000-0000-0000-000004000002', 'tester'
    );
    raise exception 'assertion failed: expected insufficient_privilege -- a tenant_admin is not Supreme Admin';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_v2 from app.publish_report_type_version(
    'iae_test_report', 'get_dashboard_lead_aging',
    jsonb_build_object('currency', jsonb_build_object('type', 'string', 'required', true)),
    'v2: requires a currency parameter', '00000000-0000-0000-0000-000004000001', 'tester'
  );
  if v_v2.version_number <> 2 then
    raise exception 'assertion failed: expected the published version to be 2, got %', v_v2.version_number;
  end if;

  select count(*) into v_version_count from app.report_type_versions where report_type_code = 'iae_test_report';
  if v_version_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 report_type_versions rows (backfilled v1 + published v2), got %', v_version_count;
  end if;

  select * into v_type from app.report_types where code = 'iae_test_report';
  if v_type.parameter_schema -> 'currency' ->> 'required' <> 'true' then
    raise exception 'assertion failed: expected app.report_types.parameter_schema to reflect the newly published v2 schema';
  end if;
  if v_type.version <> 2 then
    raise exception 'assertion failed: expected app.report_types.version to advance to 2, got %', v_type.version;
  end if;

  -- the run recorded BEFORE v2 was published must still cite v1 -- never rewritten
  if (select report_type_version_id from app.report_runs where id = v_v1_run.id)
     <> (select id from app.report_type_versions where report_type_code = 'iae_test_report' and version_number = 1) then
    raise exception 'assertion failed: expected the pre-v2 run to still cite version 1 -- prior evidence must never be rewritten by a later publish';
  end if;
end;
$$;

\echo '>> app.validate_report_parameters: empty schema passes anything structurally valid; a declared schema enforces required keys, type match, and rejects undeclared keys'
do $$
begin
  if not app.validate_report_parameters('{}'::jsonb, jsonb_build_object('anything', 'goes', 'nested', jsonb_build_object('a', 1))) then
    raise exception 'assertion failed: expected an empty schema to accept any structurally-valid parameters object';
  end if;

  if not app.validate_report_parameters(
    jsonb_build_object('currency', jsonb_build_object('type', 'string', 'required', true)),
    jsonb_build_object('currency', 'USD')
  ) then
    raise exception 'assertion failed: expected a valid required-string parameter to pass';
  end if;

  if app.validate_report_parameters(
    jsonb_build_object('currency', jsonb_build_object('type', 'string', 'required', true)),
    '{}'::jsonb
  ) then
    raise exception 'assertion failed: expected a missing required key to fail';
  end if;

  if app.validate_report_parameters(
    jsonb_build_object('currency', jsonb_build_object('type', 'string', 'required', true)),
    jsonb_build_object('currency', 123)
  ) then
    raise exception 'assertion failed: expected a wrong-typed value (number, not string) to fail';
  end if;

  if app.validate_report_parameters(
    jsonb_build_object('currency', jsonb_build_object('type', 'string', 'required', true)),
    jsonb_build_object('currency', 'USD', 'undeclared_key', 'x')
  ) then
    raise exception 'assertion failed: expected an undeclared parameter key to fail once a schema is declared';
  end if;
end;
$$;

\echo '>> app.record_report_run enforces the report''s own current parameter_schema: valid parameters succeed and stamp the current (v2) version, invalid parameters are rejected; a pre-existing report with an empty schema is unaffected (zero regression)'
do $$
declare
  v_tenant1 uuid;
  v_run app.report_runs;
  v_v2_id uuid;
  v_legacy_run app.report_runs;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaereportco');
  v_v2_id := (select id from app.report_type_versions where report_type_code = 'iae_test_report' and version_number = 2);

  begin
    perform app.record_report_run(v_tenant1, 'iae_test_report', '{}'::jsonb, 0, array[]::text[], '00000000-0000-0000-0000-000004000003', 'tester');
    raise exception 'assertion failed: expected report_unsafe_parameters -- currency is required by the now-published v2 schema';
  exception
    when check_violation then
      null; -- expected
  end;

  select * into v_run from app.record_report_run(
    v_tenant1, 'iae_test_report', jsonb_build_object('currency', 'IDR'), 5, array[]::text[],
    '00000000-0000-0000-0000-000004000003', 'tester'
  );
  if v_run.report_type_version_id is distinct from v_v2_id then
    raise exception 'assertion failed: expected a fresh run to stamp the current v2 report_type_version_id';
  end if;

  -- zero regression: a pre-existing report (empty schema, never versioned by this checkpoint) still accepts arbitrary parameters unchanged.
  -- Uses finance_billing_summary, not lead_aging -- scripts/db-tests/commercial-reports.sql's own
  -- retire_report_type coverage permanently retires lead_aging in the shared cumulative database,
  -- so a standalone run of this file (migrations only, lead_aging still active) would pass while a
  -- full db:test run (commercial-reports.sql runs first, alphabetically) would not -- confirmed live,
  -- not merely reasoned about. finance_billing_summary is never retired by any *.sql fixture in this
  -- directory (grep-verified against every retire_report_type call before use).
  select * into v_legacy_run from app.record_report_run(
    v_tenant1, 'finance_billing_summary', jsonb_build_object('anything', 'goes'), 2, array[]::text[],
    '00000000-0000-0000-0000-000004000003', 'tester'
  );
  if v_legacy_run.status <> 'completed' then
    raise exception 'assertion failed: expected the pre-existing finance_billing_summary report to keep accepting arbitrary parameters unchanged';
  end if;
end;
$$;

\echo '>> app.cancel_report_run: the original requester or an actor holding COM:Export or Supreme Admin may cancel a still-queued export; a non-queued run and an unrelated actor are both rejected; cross-tenant isolation holds'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_export_run app.report_runs;
  v_second_export app.report_runs;
  v_third_export app.report_runs;
  v_cancelled app.report_runs;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaereportco');
  v_tenant2 := (select id from app.tenants where slug = 'iaereportco2');

  select * into v_export_run from app.enqueue_report_export(
    v_tenant1, 'iae_test_report', jsonb_build_object('currency', 'IDR'), '00000000-0000-0000-0000-000004000004', 'tester'
  );
  if v_export_run.status <> 'queued' then
    raise exception 'assertion failed: expected a fresh export to be queued, got %', v_export_run.status;
  end if;

  -- C-05 regression guard: a tenant-2 actor with zero relationship to tenant-1 gets the
  -- SAME report_run_not_found a genuinely missing id would produce, never insufficient_authority
  -- (which would disclose that this run/tenant exists at all)
  begin
    perform app.cancel_report_run(v_export_run.id, '00000000-0000-0000-0000-000004000005', 'tester');
    raise exception 'assertion failed: expected no_data_found -- an unrelated tenant-2 actor must see the same not_found a missing id would produce, never a disclosing insufficient_authority';
  exception
    when no_data_found then
      null; -- expected
  end;

  -- a same-tenant colleague who is neither the requester nor holds COM:Export is denied
  -- with a real insufficient_authority (never the not_found oracle above -- they DO have
  -- a genuine relationship to this tenant, so a clear denial is the correct, non-leaking answer)
  begin
    perform app.cancel_report_run(v_export_run.id, '00000000-0000-0000-0000-000004000003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- a same-tenant colleague with no COM:Export and not the requester may not cancel';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_cancelled from app.cancel_report_run(v_export_run.id, '00000000-0000-0000-0000-000004000004', 'tester');
  if v_cancelled.status <> 'failed' or v_cancelled.error_reason <> 'cancelled_by_requester' then
    raise exception 'assertion failed: expected the requester''s own cancel to mark the run failed/cancelled_by_requester';
  end if;

  begin
    perform app.cancel_report_run(v_export_run.id, '00000000-0000-0000-0000-000004000004', 'tester');
    raise exception 'assertion failed: expected report_run_not_cancellable -- an already-cancelled/failed run cannot be re-cancelled';
  exception
    when check_violation then
      null; -- expected
  end;

  -- Supreme Admin may cancel any tenant's queued run, even without being the requester
  select * into v_second_export from app.enqueue_report_export(
    v_tenant1, 'iae_test_report', jsonb_build_object('currency', 'IDR'), '00000000-0000-0000-0000-000004000004', 'tester'
  );
  select * into v_cancelled from app.cancel_report_run(v_second_export.id, '00000000-0000-0000-0000-000004000001', 'tester');
  if v_cancelled.status <> 'failed' then
    raise exception 'assertion failed: expected Supreme Admin to cancel any tenant''s run regardless of requester';
  end if;

  -- Tier C fix regression (finding 12, cross-prompt-integration): a REP:Export
  -- holder with NO COM:Export at all may also cancel a run it did not
  -- request -- proves the widened COM:Export-OR-REP:Export fallback actually
  -- reaches the new REP:Export branch, not merely a re-exercise of the
  -- pre-existing COM:Export path already covered above.
  select * into v_third_export from app.enqueue_report_export(
    v_tenant1, 'iae_test_report', jsonb_build_object('currency', 'IDR'), '00000000-0000-0000-0000-000004000004', 'tester'
  );
  select * into v_cancelled from app.cancel_report_run(v_third_export.id, '00000000-0000-0000-0000-000004000006', 'tester');
  if v_cancelled.status <> 'failed' or v_cancelled.error_reason <> 'cancelled_by_requester' then
    raise exception 'assertion failed: expected a REP:Export holder (no COM:Export at all, not the requester) to cancel a still-queued run via the widened override authority';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-002 function; authenticated has no direct INSERT/UPDATE/DELETE on app.report_type_versions'
do $$
declare
  v_leak_count integer;
begin
  select count(*) into v_leak_count
  from information_schema.role_routine_grants
  where grantee = 'anon'
    and routine_schema = 'app'
    and routine_name in ('validate_report_parameters', 'publish_report_type_version', 'cancel_report_run');
  if v_leak_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grant on any new IAE-002 function, found %', v_leak_count;
  end if;

  select count(*) into v_leak_count
  from information_schema.role_table_grants
  where grantee = 'authenticated'
    and table_schema = 'app'
    and table_name = 'report_type_versions'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE');
  if v_leak_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grant on app.report_type_versions, found %', v_leak_count;
  end if;
end;
$$;

\echo '>> audit trail: publish_report_type_version and cancel_report_run each recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs
  where action = 'publish_report_type_version' and resource_type = 'app.report_type_versions';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least one publish_report_type_version audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs
  where action = 'cancel_report_run' and resource_type = 'app.report_runs';
  if v_count < 2 then
    raise exception 'assertion failed: expected at least two cancel_report_run audit events (requester cancel + Supreme cancel), found %', v_count;
  end if;
end;
$$;

\echo 'ALL IAE-002 (Reporting Engine) db-test assertions passed.'
