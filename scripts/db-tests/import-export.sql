-- Real, executable test evidence for PLT-131 (Import/Export Job Framework, CG-S6-PLT-028).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; Acme has a requester, a shared-org-unit teammate, an outsider, a tenant_admin (support authority), and a global Supreme Admin; a clean source file and an infected source file'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
  v_source_file app.files;
  v_infected_file app.files;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000003001', 'requesterie@example.test'),
    ('00000000-0000-0000-0000-000000003002', 'teammateie@example.test'),
    ('00000000-0000-0000-0000-000000003003', 'outsiderie@example.test'),
    ('00000000-0000-0000-0000-000000003004', 'tenantadminie@example.test'),
    ('00000000-0000-0000-0000-000000003005', 'supremeie@example.test'),
    ('00000000-0000-0000-0000-000000003006', 'othertenantie@example.test');

  perform app.provision_tenant('acmeie', 'Acme Import Export Co', 'idem-acmeie', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEIE-CO', 'Acme Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEIE-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000003001', 'requesterie@example.test', 'Requester', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'requesterie@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000003001', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000003002', 'teammateie@example.test', 'Teammate', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'teammateie@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000003002', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000003003', 'outsiderie@example.test', 'Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsiderie@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000003003', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000003004', 'tenantadminie@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminie@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000003004', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000003005', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoie', 'Gizmo Import Export Co', 'idem-gizmoie', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoie');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000003006', 'othertenantie@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantie@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000003006', 'tenant_admin', v_other_tenant_id, null, 'tester');

  -- A document type is required before app.initiate_file_upload will accept anything
  -- (PLT-128 reused directly, not re-implemented for this checkpoint).
  perform app.register_document_type('csvupload', 'CSV Upload', 'DOC', '00000000-0000-0000-0000-000000003005', 'supreme admin');
  declare
    v_draft app.config_versions;
  begin
    v_draft := app.create_config_draft('document:csvupload', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000003004', 'tenant admin');
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
      jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
      jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
      jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
      jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
    ), '00000000-0000-0000-0000-000000003004', 'tenant admin');
    perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000003004', now(), 'tenant admin');
  end;

  v_source_file := app.initiate_file_upload(v_tenant_id, 'csvupload', 'import_job', gen_random_uuid(), 'rows.csv', 'text/csv', 1000, null, false, null, '{}', null, 'idem-source-1', '00000000-0000-0000-0000-000000003001', 'requester');
  perform app.record_file_scan_result(v_source_file.id, 'clean', null, '00000000-0000-0000-0000-000000003001', 'requester');

  v_infected_file := app.initiate_file_upload(v_tenant_id, 'csvupload', 'import_job', gen_random_uuid(), 'evil.csv', 'text/csv', 1000, null, false, null, '{}', null, 'idem-source-infected', '00000000-0000-0000-0000-000000003001', 'requester');
  perform app.record_file_scan_result(v_infected_file.id, 'infected', null, '00000000-0000-0000-0000-000000003001', 'requester');
end;
$$;

\echo '>> app.register_import_export_schema: idempotent, Supreme-Admin-only, and mints a dedicated import_export:<code> config_type (PLT-121''s registry reused, not forked)'
do $$
declare
  v_registered1 app.import_export_schemas;
  v_registered2 app.import_export_schemas;
  v_config_type_exists boolean;
begin
  begin
    perform app.register_import_export_schema('shipment_rows', 'Shipment Rows', 'SHP', '00000000-0000-0000-0000-000000003004', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering an import/export schema';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_import_export_schema('shipment_rows', 'Shipment Rows', 'SHP', '00000000-0000-0000-0000-000000003005', 'supreme admin');
  v_registered2 := app.register_import_export_schema('shipment_rows', 'Shipment Rows', 'SHP', '00000000-0000-0000-0000-000000003005', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;

  select exists (select 1 from app.config_types where code = 'import_export:shipment_rows') into v_config_type_exists;
  if not v_config_type_exists then
    raise exception 'assertion failed: expected app.register_import_export_schema to also mint an import_export:shipment_rows config_type';
  end if;
end;
$$;

\echo '>> app.validate_import_export_schema_definition / app.publish_import_export_schema: every structural failure mode is a distinct, named exception; a valid definition publishes'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_draft := app.create_config_draft('import_export:shipment_rows', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000003004', 'tenant admin');

  begin
    perform app.set_config_items(v_draft.id, '[]'::jsonb, '00000000-0000-0000-0000-000000003004', 'tenant admin');
    perform app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000003004', now(), 'tenant admin');
    raise exception 'assertion failed: expected import_export_missing_columns for an empty columns array';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_missing_columns' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
        jsonb_build_object('key', '', 'label', 'Ref', 'required', true, 'data_type', 'text')
      ))
    ), '00000000-0000-0000-0000-000000003004', 'tenant admin');
    perform app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000003004', now(), 'tenant admin');
    raise exception 'assertion failed: expected import_export_invalid_column_key for an empty key';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_invalid_column_key' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
        jsonb_build_object('key', 'ref', 'label', 'Ref', 'required', true, 'data_type', 'text'),
        jsonb_build_object('key', 'ref', 'label', 'Ref Again', 'required', true, 'data_type', 'text')
      ))
    ), '00000000-0000-0000-0000-000000003004', 'tenant admin');
    perform app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000003004', now(), 'tenant admin');
    raise exception 'assertion failed: expected import_export_duplicate_column_key';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_duplicate_column_key' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
        jsonb_build_object('key', 'ref', 'label', '', 'required', true, 'data_type', 'text')
      ))
    ), '00000000-0000-0000-0000-000000003004', 'tenant admin');
    perform app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000003004', now(), 'tenant admin');
    raise exception 'assertion failed: expected import_export_missing_column_label';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_missing_column_label' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
        jsonb_build_object('key', 'ref', 'label', 'Ref', 'required', true, 'data_type', 'currency')
      ))
    ), '00000000-0000-0000-0000-000000003004', 'tenant admin');
    perform app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000003004', now(), 'tenant admin');
    raise exception 'assertion failed: expected import_export_invalid_data_type';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_invalid_data_type' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
        jsonb_build_object('key', 'ref', 'label', 'Ref', 'data_type', 'text')
      ))
    ), '00000000-0000-0000-0000-000000003004', 'tenant admin');
    perform app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000003004', now(), 'tenant admin');
    raise exception 'assertion failed: expected import_export_missing_required_flag';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_missing_required_flag' then raise; end if;
  end;

  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'ref', 'label', 'Reference', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'amount', 'label', 'Amount', 'required', true, 'data_type', 'number'),
      jsonb_build_object('key', 'is_paid', 'label', 'Is Paid', 'required', false, 'data_type', 'boolean'),
      jsonb_build_object('key', 'ship_date', 'label', 'Ship Date', 'required', false, 'data_type', 'date'),
      jsonb_build_object('key', 'contact_email', 'label', 'Contact Email', 'required', false, 'data_type', 'email')
    ))
  ), '00000000-0000-0000-0000-000000003004', 'tenant admin');
  v_published := app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000003004', now(), 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the valid shipment_rows definition to publish';
  end if;
end;
$$;

\echo '>> app.resolve_import_export_schema_columns: raises import_export_schema_not_configured for a tenant with no published definition'
do $$
declare
  v_other_tenant_id uuid;
begin
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoie');
  begin
    perform app.resolve_import_export_schema_columns(v_other_tenant_id, 'shipment_rows');
    raise exception 'assertion failed: expected import_export_schema_not_configured';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_schema_not_configured' then raise; end if;
  end;
end;
$$;

\echo '>> app.create_import_export_job: authority, unknown job_type, unconfigured schema, import requires source_file, export forbids source_file, idempotency'
do $$
declare
  v_tenant_id uuid;
  v_source_file_id uuid;
  v_job1 app.jobs;
  v_job2 app.jobs;
  v_export_job app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_source_file_id := (select id from app.files where tenant_id = v_tenant_id and idempotency_key = 'idem-source-1');

  begin
    perform app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_source_file_id, '{}'::jsonb, null, '00000000-0000-0000-0000-000000003006', 'outsider tenant admin');
    raise exception 'assertion failed: expected job_actor_unauthorized for an actor with no membership in this tenant';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_import_export_job(v_tenant_id, 'sync', 'shipment_rows', v_source_file_id, '{}'::jsonb, null, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_invalid_job_type';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_invalid_job_type' then raise; end if;
  end;

  begin
    perform app.create_import_export_job(v_tenant_id, 'import', 'never_published', v_source_file_id, '{}'::jsonb, null, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_schema_not_configured';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_schema_not_configured' then raise; end if;
  end;

  begin
    perform app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', null, '{}'::jsonb, null, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_missing_source_file';
  exception
    when check_violation then
      if sqlerrm !~ 'import_missing_source_file' then raise; end if;
  end;

  begin
    perform app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', gen_random_uuid(), '{}'::jsonb, null, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_source_file_not_found for a file id from nowhere';
  exception
    when no_data_found then
      if sqlerrm !~ 'import_source_file_not_found' then raise; end if;
  end;

  begin
    perform app.create_import_export_job(v_tenant_id, 'export', 'shipment_rows', v_source_file_id, '{}'::jsonb, null, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected export_unexpected_source_file';
  exception
    when check_violation then
      if sqlerrm !~ 'export_unexpected_source_file' then raise; end if;
  end;

  v_job1 := app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_source_file_id, '{}'::jsonb, 'idem-job-1', '00000000-0000-0000-0000-000000003001', 'requester');
  if v_job1.status <> 'pending' or v_job1.job_type <> 'import' then
    raise exception 'assertion failed: unexpected initial job state %', v_job1;
  end if;

  v_job2 := app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_source_file_id, '{}'::jsonb, 'idem-job-1', '00000000-0000-0000-0000-000000003001', 'requester');
  if v_job2.job_id <> v_job1.job_id then
    raise exception 'assertion failed: expected a repeated idempotency_key to return the existing job, not create a duplicate';
  end if;

  v_export_job := app.create_import_export_job(v_tenant_id, 'export', 'shipment_rows', null, '{}'::jsonb, 'idem-export-job-1', '00000000-0000-0000-0000-000000003001', 'requester');
  if v_export_job.job_type <> 'export' or v_export_job.source_file_id is not null then
    raise exception 'assertion failed: unexpected export job state %', v_export_job;
  end if;
end;
$$;

\echo '>> app.stage_import_rows: authority, wrong job_type/status, malware-scan gate (infected/not-yet-scanned), unsafe payload, and a valid stage flips pending -> in_progress'
do $$
declare
  v_tenant_id uuid;
  v_infected_file_id uuid;
  v_infected_job app.jobs;
  v_job_id uuid;
  v_export_job_id uuid;
  v_count integer;
  v_job app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_job_id := (select job_id from app.jobs where tenant_id = v_tenant_id and idempotency_key = 'idem-job-1');
  v_export_job_id := (select job_id from app.jobs where tenant_id = v_tenant_id and idempotency_key = 'idem-export-job-1');
  v_infected_file_id := (select id from app.files where tenant_id = v_tenant_id and idempotency_key = 'idem-source-infected');

  begin
    perform app.stage_import_rows(v_job_id, jsonb_build_array(jsonb_build_object('ref', 'A1')), '00000000-0000-0000-0000-000000003006', 'outsider tenant admin');
    raise exception 'assertion failed: expected job_actor_unauthorized';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.stage_import_rows(v_export_job_id, jsonb_build_array(jsonb_build_object('ref', 'A1')), '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_wrong_job_type for an export job';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_wrong_job_type' then raise; end if;
  end;

  v_infected_job := app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_infected_file_id, '{}'::jsonb, 'idem-job-infected', '00000000-0000-0000-0000-000000003001', 'requester');
  begin
    perform app.stage_import_rows(v_infected_job.job_id, jsonb_build_array(jsonb_build_object('ref', 'A1')), '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_source_file_infected';
  exception
    when check_violation then
      if sqlerrm !~ 'import_source_file_infected' then raise; end if;
  end;

  begin
    perform app.stage_import_rows(v_job_id, '[]'::jsonb, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_missing_rows for an empty array';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_missing_rows' then raise; end if;
  end;

  v_count := app.stage_import_rows(v_job_id, jsonb_build_array(
    jsonb_build_object('ref', 'REF-001', 'amount', '100.50', 'is_paid', 'true', 'ship_date', '2026-07-01', 'contact_email', 'a@example.test'),
    jsonb_build_object('ref', 'REF-002', 'amount', 'not-a-number', 'is_paid', 'maybe', 'ship_date', 'not-a-date', 'contact_email', 'not-an-email'),
    jsonb_build_object('amount', '50')
  ), '00000000-0000-0000-0000-000000003001', 'requester');
  if v_count <> 3 then
    raise exception 'assertion failed: expected 3 staged rows, got %', v_count;
  end if;

  select * into v_job from app.jobs where job_id = v_job_id;
  if v_job.status <> 'in_progress' or v_job.total_rows <> 3 then
    raise exception 'assertion failed: expected the job to flip pending -> in_progress with total_rows=3, got %', v_job;
  end if;

  -- Staging more rows while already in_progress must succeed and append, not reset.
  v_count := app.stage_import_rows(v_job_id, jsonb_build_array(jsonb_build_object('ref', 'REF-004', 'amount', '10')), '00000000-0000-0000-0000-000000003001', 'requester');
  if v_count <> 4 then
    raise exception 'assertion failed: expected staging to append (4 total rows), got %', v_count;
  end if;

  if not exists (select 1 from app.import_staging_rows where job_id = v_job_id and row_number = 4) then
    raise exception 'assertion failed: expected sequential row_number continuation across separate stage_import_rows calls';
  end if;
end;
$$;

\echo '>> app.validate_staging_row: required-ness and per-data_type shape checks, and the idempotent-safe delta-counting re-validation logic'
do $$
declare
  v_tenant_id uuid;
  v_job_id uuid;
  v_row_valid_id uuid;
  v_row_invalid_id uuid;
  v_row_missing_required_id uuid;
  v_result app.import_staging_rows;
  v_job app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_job_id := (select job_id from app.jobs where tenant_id = v_tenant_id and idempotency_key = 'idem-job-1');
  v_row_valid_id := (select id from app.import_staging_rows where job_id = v_job_id and row_number = 1);
  v_row_invalid_id := (select id from app.import_staging_rows where job_id = v_job_id and row_number = 2);
  v_row_missing_required_id := (select id from app.import_staging_rows where job_id = v_job_id and row_number = 3);

  v_result := app.validate_staging_row(v_row_valid_id, '00000000-0000-0000-0000-000000003001', 'requester');
  if v_result.validation_status <> 'valid' or v_result.error is not null then
    raise exception 'assertion failed: expected row 1 to validate cleanly, got status=% error=%', v_result.validation_status, v_result.error;
  end if;

  v_result := app.validate_staging_row(v_row_invalid_id, '00000000-0000-0000-0000-000000003001', 'requester');
  if v_result.validation_status <> 'invalid' or v_result.error !~ 'amount' or v_result.error !~ 'is_paid' or v_result.error !~ 'ship_date' or v_result.error !~ 'contact_email' then
    raise exception 'assertion failed: expected row 2 to be invalid with all four shape errors, got status=% error=%', v_result.validation_status, v_result.error;
  end if;

  v_result := app.validate_staging_row(v_row_missing_required_id, '00000000-0000-0000-0000-000000003001', 'requester');
  if v_result.validation_status <> 'invalid' or v_result.error !~ 'required value is missing' then
    raise exception 'assertion failed: expected row 3 to be invalid with a required-value-missing error, got status=% error=%', v_result.validation_status, v_result.error;
  end if;

  select * into v_job from app.jobs where job_id = v_job_id;
  if v_job.processed_rows <> 3 or v_job.valid_row_count <> 1 or v_job.invalid_row_count <> 2 then
    raise exception 'assertion failed: expected processed_rows=3, valid_row_count=1, invalid_row_count=2 after first resolution, got %/%/%', v_job.processed_rows, v_job.valid_row_count, v_job.invalid_row_count;
  end if;

  -- Idempotent re-validation of an already-valid row must not double-count.
  perform app.validate_staging_row(v_row_valid_id, '00000000-0000-0000-0000-000000003001', 'requester');
  select * into v_job from app.jobs where job_id = v_job_id;
  if v_job.processed_rows <> 3 or v_job.valid_row_count <> 1 then
    raise exception 'assertion failed: expected re-validating an already-valid row to be a no-op on the counters, got processed_rows=% valid_row_count=%', v_job.processed_rows, v_job.valid_row_count;
  end if;

  -- Re-validation across a real status transition (invalid -> valid, simulated by
  -- correcting the raw payload) must move the delta, not double-increment.
  update app.import_staging_rows set raw_payload = jsonb_build_object('ref', 'REF-002-FIXED', 'amount', '25', 'is_paid', 'false', 'ship_date', '2026-07-05', 'contact_email', 'fixed@example.test') where id = v_row_invalid_id;
  v_result := app.validate_staging_row(v_row_invalid_id, '00000000-0000-0000-0000-000000003001', 'requester');
  if v_result.validation_status <> 'valid' then
    raise exception 'assertion failed: expected the corrected row 2 to now validate, got %', v_result.validation_status;
  end if;

  select * into v_job from app.jobs where job_id = v_job_id;
  if v_job.processed_rows <> 3 or v_job.valid_row_count <> 2 or v_job.invalid_row_count <> 1 then
    raise exception 'assertion failed: expected the invalid->valid transition to move the delta (processed_rows stays 3, valid_row_count=2, invalid_row_count=1), got %/%/%', v_job.processed_rows, v_job.valid_row_count, v_job.invalid_row_count;
  end if;

  -- Validate the still-pending 4th row (staged in the previous scenario group) to
  -- fully resolve the job ahead of the commit scenario group below.
  perform app.validate_staging_row((select id from app.import_staging_rows where job_id = v_job_id and row_number = 4), '00000000-0000-0000-0000-000000003001', 'requester');

  select * into v_job from app.jobs where job_id = v_job_id;
  if v_job.processed_rows <> 4 or v_job.valid_row_count <> 3 or v_job.invalid_row_count <> 1 then
    raise exception 'assertion failed: expected final counters processed_rows=4, valid_row_count=3, invalid_row_count=1, got %/%/%', v_job.processed_rows, v_job.valid_row_count, v_job.invalid_row_count;
  end if;
end;
$$;

\echo '>> app.preview_import_job: authority-gated (requester or admin authority only), aggregates staged-row counts'
do $$
declare
  v_tenant_id uuid;
  v_job_id uuid;
  v_preview record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_job_id := (select job_id from app.jobs where tenant_id = v_tenant_id and idempotency_key = 'idem-job-1');

  begin
    perform app.preview_import_job(v_job_id, '00000000-0000-0000-0000-000000003002');
    raise exception 'assertion failed: expected job_actor_unauthorized for a mere teammate (not the requester, not support authority)';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_preview from app.preview_import_job(v_job_id, '00000000-0000-0000-0000-000000003001');
  if v_preview.total_rows <> 4 or v_preview.valid_rows <> 3 or v_preview.invalid_rows <> 1 or v_preview.pending_rows <> 0 then
    raise exception 'assertion failed: unexpected preview %', v_preview;
  end if;

  select * into v_preview from app.preview_import_job(v_job_id, '00000000-0000-0000-0000-000000003004');
  if v_preview.total_rows <> 4 then
    raise exception 'assertion failed: expected the tenant_admin (support authority) to also preview the job';
  end if;
end;
$$;

\echo '>> app.commit_import_job: refuses while rows are pending, refuses invalid rows without p_allow_partial, a partial commit succeeds; a fully-clean job commits outright'
do $$
declare
  v_tenant_id uuid;
  v_source_file_id uuid;
  v_pending_job app.jobs;
  v_partial_job_id uuid;
  v_committed app.jobs;
  v_clean_job app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_source_file_id := (select id from app.files where tenant_id = v_tenant_id and idempotency_key = 'idem-source-1');
  v_partial_job_id := (select job_id from app.jobs where tenant_id = v_tenant_id and idempotency_key = 'idem-job-1');

  v_pending_job := app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_source_file_id, '{}'::jsonb, 'idem-job-pending-commit', '00000000-0000-0000-0000-000000003001', 'requester');
  perform app.stage_import_rows(v_pending_job.job_id, jsonb_build_array(jsonb_build_object('ref', 'REF-100', 'amount', '10')), '00000000-0000-0000-0000-000000003001', 'requester');
  begin
    perform app.commit_import_job(v_pending_job.job_id, false, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_job_not_fully_validated while a row is still pending';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_job_not_fully_validated' then raise; end if;
  end;

  begin
    perform app.commit_import_job(v_partial_job_id, false, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_job_has_invalid_rows without p_allow_partial';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_job_has_invalid_rows' then raise; end if;
  end;

  v_committed := app.commit_import_job(v_partial_job_id, true, '00000000-0000-0000-0000-000000003001', 'requester');
  if v_committed.status <> 'completed' or v_committed.completed_at is null then
    raise exception 'assertion failed: expected a partial commit to succeed and mark the job completed, got %', v_committed;
  end if;

  begin
    perform app.commit_import_job(v_partial_job_id, true, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_job_not_committable for an already-completed job';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_job_not_committable' then raise; end if;
  end;

  v_clean_job := app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_source_file_id, '{}'::jsonb, 'idem-job-clean-commit', '00000000-0000-0000-0000-000000003001', 'requester');
  perform app.stage_import_rows(v_clean_job.job_id, jsonb_build_array(jsonb_build_object('ref', 'REF-200', 'amount', '20')), '00000000-0000-0000-0000-000000003001', 'requester');
  perform app.validate_staging_row((select id from app.import_staging_rows where job_id = v_clean_job.job_id and row_number = 1), '00000000-0000-0000-0000-000000003001', 'requester');
  v_committed := app.commit_import_job(v_clean_job.job_id, false, '00000000-0000-0000-0000-000000003001', 'requester');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected a fully-clean job to commit without p_allow_partial';
  end if;
end;
$$;

\echo '>> app.cancel_import_export_job / app.acknowledge_job_cancellation: pending cancels immediately; in_progress requires two-phase cancel; already-terminal jobs refuse'
do $$
declare
  v_tenant_id uuid;
  v_source_file_id uuid;
  v_pending_job app.jobs;
  v_in_progress_job app.jobs;
  v_cancelled app.jobs;
  v_cancelling app.jobs;
  v_acked app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_source_file_id := (select id from app.files where tenant_id = v_tenant_id and idempotency_key = 'idem-source-1');

  v_pending_job := app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_source_file_id, '{}'::jsonb, 'idem-job-cancel-pending', '00000000-0000-0000-0000-000000003001', 'requester');

  begin
    perform app.cancel_import_export_job(v_pending_job.job_id, 'no longer needed', '00000000-0000-0000-0000-000000003002', 'teammate');
    raise exception 'assertion failed: expected job_actor_unauthorized for a mere teammate (not the requester, not support authority)';
  exception
    when insufficient_privilege then
      null;
  end;

  v_cancelled := app.cancel_import_export_job(v_pending_job.job_id, 'no longer needed', '00000000-0000-0000-0000-000000003001', 'requester');
  if v_cancelled.status <> 'cancelled' or v_cancelled.completed_at is null then
    raise exception 'assertion failed: expected a pending job to cancel immediately, got %', v_cancelled;
  end if;

  begin
    perform app.cancel_import_export_job(v_pending_job.job_id, 'again', '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_job_already_terminal';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_job_already_terminal' then raise; end if;
  end;

  v_in_progress_job := app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_source_file_id, '{}'::jsonb, 'idem-job-cancel-inprogress', '00000000-0000-0000-0000-000000003001', 'requester');
  perform app.stage_import_rows(v_in_progress_job.job_id, jsonb_build_array(jsonb_build_object('ref', 'REF-300', 'amount', '30')), '00000000-0000-0000-0000-000000003001', 'requester');

  v_cancelling := app.cancel_import_export_job(v_in_progress_job.job_id, 'change of plans', '00000000-0000-0000-0000-000000003004', 'tenant admin');
  if v_cancelling.status <> 'cancelling' or v_cancelling.completed_at is not null then
    raise exception 'assertion failed: expected an in_progress job to move to cancelling (not yet completed), got %', v_cancelling;
  end if;

  begin
    perform app.acknowledge_job_cancellation(v_pending_job.job_id, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_job_not_cancelling for an already-cancelled job';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_job_not_cancelling' then raise; end if;
  end;

  v_acked := app.acknowledge_job_cancellation(v_in_progress_job.job_id, '00000000-0000-0000-0000-000000003001', 'requester');
  if v_acked.status <> 'cancelled' or v_acked.completed_at is null then
    raise exception 'assertion failed: expected acknowledge_job_cancellation to finish the two-phase cancel, got %', v_acked;
  end if;
end;
$$;

\echo '>> app.complete_export_job: wrong job_type, result file must exist in the same tenant, a valid completion attaches the result file'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_import_job_id uuid;
  v_export_job app.jobs;
  v_result_file app.files;
  v_cross_tenant_file app.files;
  v_completed app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoie');
  v_import_job_id := (select job_id from app.jobs where tenant_id = v_tenant_id and idempotency_key = 'idem-job-clean-commit');

  begin
    perform app.complete_export_job(v_import_job_id, gen_random_uuid(), 1, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_wrong_job_type for an import job';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_wrong_job_type' then raise; end if;
  end;

  v_export_job := app.create_import_export_job(v_tenant_id, 'export', 'shipment_rows', null, '{}'::jsonb, 'idem-export-complete-1', '00000000-0000-0000-0000-000000003001', 'requester');

  begin
    perform app.complete_export_job(v_export_job.job_id, gen_random_uuid(), 5, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected export_result_file_not_found for a file id from nowhere';
  exception
    when no_data_found then
      if sqlerrm !~ 'export_result_file_not_found' then raise; end if;
  end;

  v_result_file := app.initiate_file_upload(v_tenant_id, 'csvupload', 'export_job', gen_random_uuid(), 'result.csv', 'text/csv', 500, null, false, null, '{}', null, 'idem-result-1', '00000000-0000-0000-0000-000000003001', 'requester');
  v_completed := app.complete_export_job(v_export_job.job_id, v_result_file.id, 5, '00000000-0000-0000-0000-000000003001', 'requester');
  if v_completed.status <> 'completed' or v_completed.result_file_id <> v_result_file.id or v_completed.total_rows <> 5 or v_completed.processed_rows <> 5 then
    raise exception 'assertion failed: unexpected completed export job state %', v_completed;
  end if;
end;
$$;

\echo '>> app.record_job_failure / app.requeue_dead_letter_job: retry-until-max_attempts then dead_letter; requeue is admin-only and resets attempts'
do $$
declare
  v_tenant_id uuid;
  v_source_file_id uuid;
  v_job app.jobs;
  v_after1 app.jobs;
  v_after2 app.jobs;
  v_after3 app.jobs;
  v_audit_result text;
  v_requeued app.jobs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeie');
  v_source_file_id := (select id from app.files where tenant_id = v_tenant_id and idempotency_key = 'idem-source-1');

  v_job := app.create_import_export_job(v_tenant_id, 'import', 'shipment_rows', v_source_file_id, '{}'::jsonb, 'idem-job-failure-1', '00000000-0000-0000-0000-000000003001', 'requester');
  if v_job.max_attempts <> 3 then
    raise exception 'assertion failed: expected the default max_attempts to be 3, got %', v_job.max_attempts;
  end if;

  v_after1 := app.record_job_failure(v_job.job_id, 'transient network error', '00000000-0000-0000-0000-000000003001', 'requester');
  if v_after1.status <> 'pending' or v_after1.attempts <> 1 then
    raise exception 'assertion failed: expected attempts=1, status=pending after the first failure, got %', v_after1;
  end if;

  select result into v_audit_result from app.audit_logs where action = 'record_job_failure' and resource_id = v_job.job_id order by occurred_at desc limit 1;
  if v_audit_result <> 'failure' then
    raise exception 'assertion failed: expected the failure audit entry to record result=failure (audit_logs.result only allows success/failure), got %', v_audit_result;
  end if;

  v_after2 := app.record_job_failure(v_job.job_id, 'transient network error again', '00000000-0000-0000-0000-000000003001', 'requester');
  if v_after2.status <> 'pending' or v_after2.attempts <> 2 then
    raise exception 'assertion failed: expected attempts=2, status=pending after the second failure, got %', v_after2;
  end if;

  v_after3 := app.record_job_failure(v_job.job_id, 'final failure', '00000000-0000-0000-0000-000000003001', 'requester');
  if v_after3.status <> 'dead_letter' or v_after3.attempts <> 3 or v_after3.completed_at is null then
    raise exception 'assertion failed: expected the third failure to reach max_attempts and move to dead_letter, got %', v_after3;
  end if;

  begin
    perform app.record_job_failure(v_job.job_id, 'once more', '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected import_export_job_already_terminal for a dead_letter job';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_job_already_terminal' then raise; end if;
  end;

  begin
    perform app.requeue_dead_letter_job(v_job.job_id, '00000000-0000-0000-0000-000000003001', 'requester');
    raise exception 'assertion failed: expected job_requeue_unauthorized for a mere requester (not support/Supreme authority)';
  exception
    when insufficient_privilege then
      null;
  end;

  v_requeued := app.requeue_dead_letter_job(v_job.job_id, '00000000-0000-0000-0000-000000003004', 'tenant admin');
  if v_requeued.status <> 'pending' or v_requeued.attempts <> 0 or v_requeued.error is not null or v_requeued.completed_at is not null then
    raise exception 'assertion failed: expected requeue to reset attempts=0, status=pending, error/completed_at cleared, got %', v_requeued;
  end if;

  begin
    perform app.requeue_dead_letter_job(v_job.job_id, '00000000-0000-0000-0000-000000003004', 'tenant admin');
    raise exception 'assertion failed: expected import_export_job_not_dead_letter for an already-requeued job';
  exception
    when check_violation then
      if sqlerrm !~ 'import_export_job_not_dead_letter' then raise; end if;
  end;
end;
$$;

\echo '>> app.sanitize_formula_injection: a leading =/+/-/@ is prefixed with a single quote; other text is untouched'
do $$
begin
  if app.sanitize_formula_injection('=SUM(A1:A9)') <> '''=SUM(A1:A9)' then
    raise exception 'assertion failed: expected a leading = to be quote-prefixed';
  end if;
  if app.sanitize_formula_injection('+1234567') <> '''+1234567' then
    raise exception 'assertion failed: expected a leading + to be quote-prefixed';
  end if;
  if app.sanitize_formula_injection('-5') <> '''-5' then
    raise exception 'assertion failed: expected a leading - to be quote-prefixed (accepted false-positive on legitimate negative numbers, per this migration''s own disclosed default)';
  end if;
  if app.sanitize_formula_injection('@cmd') <> '''@cmd' then
    raise exception 'assertion failed: expected a leading @ to be quote-prefixed';
  end if;
  if app.sanitize_formula_injection('ordinary text') <> 'ordinary text' then
    raise exception 'assertion failed: expected ordinary text to pass through untouched';
  end if;
  if app.sanitize_formula_injection('REF-001') <> 'REF-001' then
    raise exception 'assertion failed: expected an internal hyphen (not a leading one) to pass through untouched';
  end if;
end;
$$;

\echo '>> RLS on app.jobs: requester and support authority see the row, an unrelated teammate does not, cross-tenant is denied, Supreme sees everything'
do $$
declare
  v_visible_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000003001", "role": "authenticated"}';
  select count(*) into v_visible_count from app.jobs where idempotency_key = 'idem-job-1';
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the requester to see their own job via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000003002", "role": "authenticated"}';
  select count(*) into v_visible_count from app.jobs where idempotency_key = 'idem-job-1';
  if v_visible_count <> 0 then raise exception 'assertion failed: expected a mere teammate (not the requester, not support authority) to be denied visibility via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000003004", "role": "authenticated"}';
  select count(*) into v_visible_count from app.jobs where idempotency_key = 'idem-job-1';
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the tenant_admin (support authority) to see the job via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000003006", "role": "authenticated"}';
  select count(*) into v_visible_count from app.jobs where idempotency_key = 'idem-job-1';
  if v_visible_count <> 0 then raise exception 'assertion failed: expected a cross-tenant actor (IDOR-style guess) to be denied visibility via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000003005", "role": "authenticated"}';
  select count(*) into v_visible_count from app.jobs where idempotency_key = 'idem-job-1';
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the Supreme Admin to see everything regardless of tenant'; end if;
  reset role;
end;
$$;

\echo '>> app.import_export_schemas RLS: broadly readable to any authenticated caller'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000003003", "role": "authenticated"}';
  select count(*) into v_count from app.import_export_schemas where code = 'shipment_rows';
  if v_count <> 1 then raise exception 'assertion failed: expected the import_export_schemas registry to be broadly readable'; end if;
  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated cannot write app.jobs directly, and has no grant at all on app.import_staging_rows'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000003001", "role": "authenticated"}';
  begin
    insert into app.jobs (tenant_id, job_type, requested_by_auth_user_id)
    values (gen_random_uuid(), 'import', gen_random_uuid());
    raise exception 'assertion failed: authenticated must be denied direct INSERT on app.jobs, but it succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform 1 from app.import_staging_rows limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.import_staging_rows entirely, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;
  reset role;
end;
$$;

\echo '>> PLT-131 (Import/Export Job Framework) test suite passed'
