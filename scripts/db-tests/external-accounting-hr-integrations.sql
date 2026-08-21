-- Real, executable test evidence for IAE-018 (External Accounting and HR
-- Integrations, Prompt 346) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/
-- 20260805050000_create_intelligence_external_accounting_hr_integrations.sql).
-- Fresh, distinctive tenant fixture (iaeexthr), fixture id range
-- 00000000-0000-0000-0000-000020xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaeexthr with one real activated employee (HRIS Employee Master lifecycle), one real activated GL account, 2 real integration connections (external_hr_system, external_accounting_system); a second tenant (iaeexthr2) for cross-tenant isolation; a HRS+FIN View-only viewer for authority-denial tests'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000020000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000020000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000020000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000020000004';
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_employee app.employees;
  v_cash_account app.finance_accounts;
  v_company uuid;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaeexthr.test'),
    (v_rep1, 'rep@iaeexthr.test'),
    (v_viewer1, 'viewer@iaeexthr.test'),
    (v_admin2, 'admin@iaeexthr2.test');

  perform app.provision_tenant('iaeexthr', 'IaeExtHr Co', 'idem-iaeexthr', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeexthr');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaeexthr2', 'IaeExtHr Co 2', 'idem-iaeexthr2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeexthr2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeexthr.test', 'IaeExtHr Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeexthr.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaeexthr.test', 'IaeExtHr Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaeexthr.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeexthr.test', 'IaeExtHr Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeexthr.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'ExtHr Rep', 'HRS + FIN + INTHUB full grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'View'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))
      or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep1, v_admin1, 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'ExtHr Viewer', 'HRS:View + FIN:View only, no Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where (resource_module_code = 'HRS' and action = 'View') or (resource_module_code = 'FIN' and action = 'View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeexthr2.test', 'IaeExtHr2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeexthr2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'IAEEXTHR-CO', 'IaeExtHr Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'IAEEXTHR-CO');

  -- Real employee, full lifecycle: draft -> submit -> approve -> activate.
  v_employee := app.create_employee_draft(v_tenant1, 'Budi Santoso', 'full_time', null, null, null, null, null, null, '2026-01-01'::date, v_company, null, null, null, null, null, null, 'hr_created', 'idem-iaeexthr-emp1', v_rep1, 'rep');
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Ibu Santoso', 'Mother', '+62-811-1', null, true, v_rep1, 'rep');
  v_employee := app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_rep1, 'rep');
  v_employee := app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'approve', null, v_rep1, 'rep');
  v_employee := app.activate_employee(v_employee.master_record_id, v_employee.record_version, v_rep1, 'rep');

  -- Real GL account.
  select * into v_cash_account from app.create_finance_account_draft(v_tenant1, null, 'CASH-EXTHR', 'Cash', 'asset', 'debit', null, false, null, v_rep1, 'rep');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, v_rep1, 'rep');

  -- Real integration connections, one per adapter.
  perform app.create_integration_connection(v_tenant1, 'external_hr_system', 'Legacy HRIS', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://hris.iaeexthr-provider.test/poll'), 'test-hr-secret', v_rep1, 'rep');
  perform app.create_integration_connection(v_tenant1, 'external_accounting_system', 'Legacy ERP', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://erp.iaeexthr-provider.test/poll'), 'test-erp-secret', v_rep1, 'rep');
end $$;

\echo '>> schema-privilege defense in depth: anon holds EXECUTE on ZERO new IAE-018 functions -- this capability is entirely poll/RPC-driven, no inbound webhook receiver'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'external_sync_adapter_codes', 'check_external_sync_entity_authority', 'set_external_sync_entity_mapping',
    'get_external_sync_entity_mapping', 'link_external_sync_entity', 'record_external_sync_snapshot',
    'review_external_sync_conflict', 'list_external_sync_records_for_tenant', 'trigger_external_sync',
    'get_external_sync_connection_for_sync', 'get_external_sync_credential'
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

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-018 function';
end;
$$;

\echo '>> app.record_external_sync_snapshot: refuses to run without an active ownership-direction mapping (the hard gate, business rule "ownership must be explicit before sync")'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeexthr');
  v_rep1 uuid := '00000000-0000-0000-0000-000020000002';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'external_hr_system');
begin
  begin
    perform app.record_external_sync_snapshot(v_tenant1, v_connection_id, 'external_hr_system', 'employee', 'EXT-EMP-1', jsonb_build_object('fullName', 'Budi S.'), v_rep1, 'rep');
    raise exception 'assertion failed: expected external_sync_mapping_not_configured before any mapping exists';
  exception when check_violation then
    if sqlerrm !~ 'external_sync_mapping_not_configured' then raise; end if;
  end;

  raise notice 'PASS: record_external_sync_snapshot refuses to run for an entity_type with no active mapping';
end;
$$;

\echo '>> app.set_external_sync_entity_mapping: INTHUB:Configure-gated, idempotent upsert; app.link_external_sync_entity: explicit-only, requires the mapping and the internal record to exist'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeexthr');
  v_rep1 uuid := '00000000-0000-0000-0000-000020000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000020000003';
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1);
  v_gl_account_id uuid := (select id from app.finance_accounts where tenant_id = v_tenant1);
  v_mapping app.external_sync_entity_mappings;
  v_link app.external_sync_entity_links;
begin
  v_mapping := app.set_external_sync_entity_mapping(v_tenant1, 'external_hr_system', 'employee', 'external_source', 'legacy HRIS is source during transition', v_rep1, 'rep');
  if v_mapping.ownership_direction <> 'external_source' then
    raise exception 'assertion failed: expected ownership_direction = external_source, got %', to_jsonb(v_mapping);
  end if;

  -- Idempotent upsert: re-setting with a different direction updates in place, no duplicate row.
  v_mapping := app.set_external_sync_entity_mapping(v_tenant1, 'external_hr_system', 'employee', 'bidirectional', 'transition complete', v_rep1, 'rep');
  if v_mapping.ownership_direction <> 'bidirectional' then
    raise exception 'assertion failed: expected the upsert to update ownership_direction to bidirectional, got %', to_jsonb(v_mapping);
  end if;
  if (select count(*) from app.external_sync_entity_mappings where tenant_id = v_tenant1 and adapter_code = 'external_hr_system' and entity_type = 'employee') <> 1 then
    raise exception 'assertion failed: expected exactly one mapping row after the idempotent upsert';
  end if;

  perform app.set_external_sync_entity_mapping(v_tenant1, 'external_accounting_system', 'gl_account', 'cargogrid_source', 'CargoGrid chart of accounts is authoritative', v_rep1, 'rep');

  begin
    perform app.set_external_sync_entity_mapping(v_tenant1, 'external_hr_system', 'employee', 'bidirectional', null, v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a non-INTHUB:Configure actor';
  exception when insufficient_privilege then null;
  end;

  v_link := app.link_external_sync_entity(v_tenant1, 'external_hr_system', 'employee', 'EXT-EMP-1', v_employee_id, v_rep1, 'rep');
  if v_link.internal_record_id <> v_employee_id then
    raise exception 'assertion failed: expected the link to point at the real employee, got %', to_jsonb(v_link);
  end if;

  perform app.link_external_sync_entity(v_tenant1, 'external_accounting_system', 'gl_account', 'EXT-ACCT-1', v_gl_account_id, v_rep1, 'rep');

  begin
    perform app.link_external_sync_entity(v_tenant1, 'external_hr_system', 'employee', 'EXT-EMP-999', gen_random_uuid(), v_rep1, 'rep');
    raise exception 'assertion failed: expected external_sync_internal_record_not_found for an unknown employee id';
  exception when no_data_found then null;
  end;

  raise notice 'PASS: set_external_sync_entity_mapping is INTHUB:Configure-gated and idempotent; link_external_sync_entity requires the mapping and a real internal record, and is explicit-only';
end;
$$;

\echo '>> app.record_external_sync_snapshot: an unmatched external_entity_id records evidence with no diff; a matched external_source-owned field diverges without ever being flagged a conflict (read-only reference, per this prompt''s own Alternative flow); a matched cargogrid_source-owned field diverging IS flagged conflicts_detected; NEVER mutates app.employees/app.finance_accounts'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeexthr');
  v_rep1 uuid := '00000000-0000-0000-0000-000020000002';
  v_hr_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'external_hr_system');
  v_erp_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'external_accounting_system');
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1);
  v_gl_account_id uuid := (select id from app.finance_accounts where tenant_id = v_tenant1);
  v_employee_record_version_before integer := (select record_version from app.employees where master_record_id = v_employee_id);
  v_gl_account_record_version_before integer := (select record_version from app.finance_accounts where id = v_gl_account_id);
  v_record app.external_sync_records;
begin
  v_record := app.record_external_sync_snapshot(v_tenant1, v_hr_connection_id, 'external_hr_system', 'employee', 'EXT-EMP-UNKNOWN', jsonb_build_object('fullName', 'Someone Else'), v_rep1, 'rep');
  if v_record.match_status <> 'unmatched' or v_record.field_diffs is not null then
    raise exception 'assertion failed: expected an unmatched snapshot with no field_diffs, got %', to_jsonb(v_record);
  end if;

  -- external_hr_system/employee mapping is 'bidirectional' (set above) -- switch it to
  -- external_source to prove the read-only-reference (no-conflict-on-divergence) path.
  perform app.set_external_sync_entity_mapping(v_tenant1, 'external_hr_system', 'employee', 'external_source', 'legacy HRIS leads for this field set', v_rep1, 'rep');
  v_record := app.record_external_sync_snapshot(v_tenant1, v_hr_connection_id, 'external_hr_system', 'employee', 'EXT-EMP-1', jsonb_build_object('fullName', 'Budi Santoso (legacy HRIS spelling)'), v_rep1, 'rep');
  if v_record.match_status <> 'matched' or v_record.field_diffs is null or v_record.conflict_status <> 'no_conflict' then
    raise exception 'assertion failed: expected a matched snapshot with a real diff but conflict_status=no_conflict (external_source ownership), got %', to_jsonb(v_record);
  end if;

  -- gl_account mapping is 'cargogrid_source' -- prove the SAME divergence IS flagged a conflict.
  v_record := app.record_external_sync_snapshot(v_tenant1, v_erp_connection_id, 'external_accounting_system', 'gl_account', 'EXT-ACCT-1', jsonb_build_object('code', 'CASH-EXTHR', 'name', 'Cash (legacy ERP name)', 'accountType', 'asset', 'normalBalance', 'debit', 'status', 'active'), v_rep1, 'rep');
  if v_record.match_status <> 'matched' or v_record.field_diffs is null or v_record.conflict_status <> 'conflicts_detected' then
    raise exception 'assertion failed: expected a matched snapshot with conflict_status=conflicts_detected (cargogrid_source ownership), got %', to_jsonb(v_record);
  end if;

  if (select record_version from app.employees where master_record_id = v_employee_id) <> v_employee_record_version_before then
    raise exception 'assertion failed: recording a sync snapshot must NEVER mutate app.employees';
  end if;
  if (select record_version from app.finance_accounts where id = v_gl_account_id) <> v_gl_account_record_version_before then
    raise exception 'assertion failed: recording a sync snapshot must NEVER mutate app.finance_accounts';
  end if;

  raise notice 'PASS: record_external_sync_snapshot correctly classifies unmatched/matched/conflict states per the entity_type''s own ownership_direction, and never mutates app.employees or app.finance_accounts';
end;
$$;

\echo '>> app.review_external_sync_conflict: entity-dispatched Edit succeeds and is evidence-only; a View-only actor is denied; an invalid decision value is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeexthr');
  v_rep1 uuid := '00000000-0000-0000-0000-000020000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000020000003';
  v_record_id uuid := (select id from app.external_sync_records where tenant_id = v_tenant1 and entity_type = 'gl_account' and conflict_status = 'conflicts_detected');
  v_record app.external_sync_records;
begin
  v_record := app.review_external_sync_conflict(v_record_id, 'reviewed', 'confirmed with the finance team, no action needed', v_rep1, 'rep');
  if v_record.conflict_status <> 'reviewed' or v_record.review_notes <> 'confirmed with the finance team, no action needed' then
    raise exception 'assertion failed: expected a real review decision, got %', to_jsonb(v_record);
  end if;

  begin
    perform app.review_external_sync_conflict(v_record_id, 'dismissed', null, v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a FIN:View-only actor on a gl_account record';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.review_external_sync_conflict(v_record_id, 'approved', null, v_rep1, 'rep');
    raise exception 'assertion failed: expected external_sync_invalid_decision for an unrecognized decision value';
  exception when check_violation then
    if sqlerrm !~ 'external_sync_invalid_decision' then raise; end if;
  end;

  raise notice 'PASS: review_external_sync_conflict is entity-dispatched Edit-gated, evidence-only, and rejects an invalid decision';
end;
$$;

\echo '>> app.list_external_sync_records_for_tenant: entity-dispatched View sees this tenant''s own real records, optionally filtered by entity_type/conflict_status; a cross-tenant admin is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeexthr');
  v_viewer1 uuid := '00000000-0000-0000-0000-000020000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000020000004';
  v_count integer;
begin
  select count(*) into v_count from app.list_external_sync_records_for_tenant(v_tenant1, v_viewer1);
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 real records for this tenant, got %', v_count;
  end if;

  select count(*) into v_count from app.list_external_sync_records_for_tenant(v_tenant1, v_viewer1, 'gl_account');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 gl_account record, got %', v_count;
  end if;

  select count(*) into v_count from app.list_external_sync_records_for_tenant(v_tenant1, v_viewer1, null, 'reviewed');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 reviewed record, got %', v_count;
  end if;

  begin
    perform app.list_external_sync_records_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant admin';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_external_sync_records_for_tenant supports entity_type/conflict_status filters and denies a cross-tenant admin';
end;
$$;

\echo '>> app.trigger_external_sync: enqueues a real app.jobs row (job_type=external_sync); refuses without an active mapping for the requested entity_type; a repeated trigger within the same minute is idempotent; a non-member is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeexthr');
  v_rep1 uuid := '00000000-0000-0000-0000-000020000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000020000004';
  v_hr_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'external_hr_system');
  v_job1 app.jobs;
  v_job2 app.jobs;
begin
  select * into v_job1 from app.trigger_external_sync(v_tenant1, v_hr_connection_id, 'employee', v_rep1, 'rep');
  if v_job1.job_type <> 'external_sync' or (v_job1.payload->>'entity_type') <> 'employee' then
    raise exception 'assertion failed: expected a real external_sync job carrying entity_type=employee, got %', to_jsonb(v_job1);
  end if;

  select * into v_job2 from app.trigger_external_sync(v_tenant1, v_hr_connection_id, 'employee', v_rep1, 'rep');
  if v_job2.job_id <> v_job1.job_id then
    raise exception 'assertion failed: expected a repeated trigger within the same minute to return the SAME job, got a second job %', v_job2.job_id;
  end if;

  begin
    perform app.trigger_external_sync(v_tenant1, v_hr_connection_id, 'gl_account', v_rep1, 'rep');
    raise exception 'assertion failed: expected external_sync_mapping_not_configured -- this connection is external_hr_system, no gl_account mapping was ever set for it';
  exception when check_violation then
    if sqlerrm !~ 'external_sync_mapping_not_configured' then raise; end if;
  end;

  begin
    perform app.trigger_external_sync(v_tenant1, v_hr_connection_id, 'employee', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant identity with no membership in this tenant';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: trigger_external_sync enqueues a real job, is minute-bucketed idempotent, refuses an entity_type with no configured mapping for that connection''s own adapter, and denies a non-member';
end;
$$;

\echo '>> external-accounting-hr-integrations.sql: ALL PASSED'
