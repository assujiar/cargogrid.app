-- Real, executable test evidence for OPS-183 (Operations Reports, CG-S8-OPS-017) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.
--
-- app.report_types/app.report_runs/app.record_report_run/app.enqueue_job are reused
-- directly from COM-159 (already `VERIFIED`, already exercised by
-- commercial-reports.sql) -- this file proves only what OPS-183 itself adds: the six
-- new report-type registrations and the one new OPS:Export-gated
-- app.enqueue_ops_report_export function.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a global Supreme Admin, a rep (OPS:Create/Edit/View, no Export) and an exporter (OPS:Create/Edit/View/Export)'
do $$
declare
  v_tenant1 uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_exporter_role uuid;
  v_exporter_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023801', 'supreme@acmeopsreport.test'),
    ('00000000-0000-0000-0000-000000023802', 'tenantadmin@acmeopsreport.test'),
    ('00000000-0000-0000-0000-000000023803', 'rep@acmeopsreport.test'),
    ('00000000-0000-0000-0000-000000023804', 'exporter@acmeopsreport.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023801', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeopsreport', 'Acme Ops Report Co', 'idem-acmeopsreport', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeopsreport');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023802', 'tenantadmin@acmeopsreport.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmeopsreport.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023802', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023803', 'rep@acmeopsreport.test', 'Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeopsreport.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023804', 'exporter@acmeopsreport.test', 'Exporter', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'exporter@acmeopsreport.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Ops Report Rep', 'no export', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000023803', '00000000-0000-0000-0000-000000023802', 'tester');

  v_exporter_role := (app.create_role(v_tenant1, 'Ops Report Exporter', 'export-gated', 'tester')).id;
  v_exporter_draft := app.create_role_version(v_exporter_role, 'tester');
  perform app.set_role_version_permissions(
    v_exporter_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Export')),
    'tester'
  );
  perform app.publish_role_version(v_exporter_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_exporter_role and status = 'published'),
    '00000000-0000-0000-0000-000000023804', '00000000-0000-0000-0000-000000023802', 'tester');
end;
$$;

\echo '>> app.report_types: the six OPS-183 report types are seeded at status=active, each naming its exact OPS-182 source_function'
do $$
declare
  v_active_count integer;
begin
  select count(*) into v_active_count from app.report_types
  where status = 'active'
    and code in ('shipment_status_summary', 'milestone_sla_summary', 'exception_queue_summary', 'epod_completion_summary', 'cost_variance_summary', 'billing_readiness_summary');
  if v_active_count <> 6 then
    raise exception 'assertion failed: expected 6 active OPS-183 report types, got %', v_active_count;
  end if;

  if not exists (select 1 from app.report_types where code = 'cost_variance_summary' and source_function = 'get_ops_dashboard_cost_variance') then
    raise exception 'assertion failed: expected cost_variance_summary to name get_ops_dashboard_cost_variance as its source_function';
  end if;
  if not exists (select 1 from app.report_types where code = 'billing_readiness_summary' and source_function = 'get_ops_dashboard_billing_readiness') then
    raise exception 'assertion failed: expected billing_readiness_summary to name get_ops_dashboard_billing_readiness as its source_function';
  end if;
end;
$$;

\echo '>> app.record_report_run (reused directly from COM-159): a successful OPS preview run against one of the newly-registered report types is recorded and audited -- no OPS-specific gate beyond tenant membership, the same "ordinary view" posture already established'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsreport');
  v_run app.report_runs;
  v_audit_count integer;
begin
  select * into v_run from app.record_report_run(
    v_tenant1, 'shipment_status_summary', jsonb_build_object('orgUnitId', null, 'ownerUserId', null), 2, array[]::text[],
    '00000000-0000-0000-0000-000000023803', 'tester'
  );
  if v_run.run_type <> 'preview' or v_run.status <> 'completed' or v_run.row_count <> 2 then
    raise exception 'assertion failed: expected run_type=preview status=completed row_count=2, got run_type=% status=% row_count=%', v_run.run_type, v_run.status, v_run.row_count;
  end if;

  select count(*) into v_audit_count from app.audit_logs where tenant_id = v_tenant1 and action = 'record_report_run' and resource_id = v_run.id;
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 audit_logs entry for this report run, got %', v_audit_count;
  end if;
end;
$$;

\echo '>> app.enqueue_ops_report_export: OPS:Export-gated (rep denied, exporter allowed), unknown/retired report types rejected, enqueues a real report_generation job and links it on the shared app.report_runs row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsreport');
  v_run app.report_runs;
  v_job app.jobs;
begin
  begin
    perform app.enqueue_ops_report_export(v_tenant1, 'cost_variance_summary', '{}'::jsonb, '00000000-0000-0000-0000-000000023803', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the rep lacks OPS:Export';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.enqueue_ops_report_export(v_tenant1, 'not_a_real_report', '{}'::jsonb, '00000000-0000-0000-0000-000000023804', 'tester');
    raise exception 'assertion failed: expected no_data_found -- unknown report_type_code';
  exception
    when no_data_found then
      null; -- expected
  end;

  select * into v_run from app.enqueue_ops_report_export(
    v_tenant1, 'cost_variance_summary', jsonb_build_object('orgUnitId', null), '00000000-0000-0000-0000-000000023804', 'tester'
  );
  if v_run.run_type <> 'export' or v_run.status <> 'queued' or v_run.job_id is null then
    raise exception 'assertion failed: expected run_type=export status=queued with a real job_id, got run_type=% status=% job_id=%', v_run.run_type, v_run.status, v_run.job_id;
  end if;

  select * into v_job from app.jobs where job_id = v_run.job_id;
  if v_job.job_type <> 'report_generation' or v_job.status <> 'pending' or (v_job.payload ->> 'report_type_code') <> 'cost_variance_summary' then
    raise exception 'assertion failed: expected a real pending report_generation job carrying report_type_code=cost_variance_summary, got type=% status=% payload=%', v_job.job_type, v_job.status, v_job.payload;
  end if;

  perform app.retire_report_type('epod_completion_summary', '00000000-0000-0000-0000-000000023801', 'tester');
  begin
    perform app.enqueue_ops_report_export(v_tenant1, 'epod_completion_summary', '{}'::jsonb, '00000000-0000-0000-0000-000000023804', 'tester');
    raise exception 'assertion failed: expected check_violation -- epod_completion_summary was just retired';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> app.report_runs: tenant-wide RLS visibility carries over unchanged from COM-159 (the rep, who did not request the export, still sees it -- management visibility, not per-owner privacy)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsreport');
  v_rep_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023803", "role": "authenticated"}';
  select count(*) into v_rep_count from app.report_runs where tenant_id = v_tenant1 and report_type_code = 'cost_variance_summary';
  if v_rep_count <> 1 then
    raise exception 'assertion failed: expected the rep to see the exporter''s own export run (tenant-wide visibility), got %', v_rep_count;
  end if;
  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on app.enqueue_ops_report_export (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and routine_name = 'enqueue_ops_report_export' and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on app.enqueue_ops_report_export, found %', v_count;
  end if;
end;
$$;

\echo '>> audit trail: app.enqueue_ops_report_export self-captures a canonical app.audit_logs entry'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where action = 'enqueue_ops_report_export';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 enqueue_ops_report_export audit event, found %', v_count;
  end if;
end;
$$;
