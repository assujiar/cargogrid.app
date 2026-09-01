-- Real, executable test evidence for ISS-2026-274 (master-data bulk import: the
-- `customer` and `item` adapters, and the `app.create_customer_account_direct` primitive
-- they required) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.
--
-- The `vendor` third of ISS-2026-274 is covered by
-- scripts/db-tests/procurement-vendor-registration.sql (ISS-2026-057), not duplicated here.

\set ON_ERROR_STOP on

\echo '>> setup: tenant mdimp1 with a tenant_admin holding COM Approve/Import/View and OPS Create/Import/View, a viewer with no Import, and a second tenant mdimp2 for isolation. A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid;
  v_admin_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000094101', 'admin@mdimp1.test'),
    ('00000000-0000-0000-0000-000000094102', 'viewer@mdimp1.test'),
    ('00000000-0000-0000-0000-000000094201', 'admin@mdimp2.test'),
    ('00000000-0000-0000-0000-000000094999', 'supreme@mdimp.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000094999', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('mdimp1', 'MasterData Import One', 'idem-mdimp1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'mdimp1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('mdimp2', 'MasterData Import Two', 'idem-mdimp2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'mdimp2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000094101', 'admin@mdimp1.test', 'MdImp Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@mdimp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000094101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000094102', 'viewer@mdimp1.test', 'MdImp Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@mdimp1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000094201', 'admin@mdimp2.test', 'MdImp2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@mdimp2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000094201', 'tenant_admin', v_tenant2, null, 'tester');

  -- tenant_admin does NOT confer COM:Import or OPS:Import -- those still need a granting
  -- role, the same independence ISS-2026-236's own regression proves for other tuples.
  v_admin_role := (app.create_role(v_tenant1, 'MdImp Importer', 'COM Approve/Import/View + OPS Create/Import/View', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(
    v_admin_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Approve', 'Import', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Import', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000094101', '00000000-0000-0000-0000-000000094101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'MdImp Viewer Role', 'COM/OPS View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code in ('COM', 'OPS') and action = 'View'),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000094102', '00000000-0000-0000-0000-000000094101', 'tester');

  v_admin_role := (app.create_role(v_tenant2, 'MdImp2 Importer', 'COM/OPS import', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(
    v_admin_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Approve', 'Import', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Import', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000094201', '00000000-0000-0000-0000-000000094201', 'tester');
end $$;

\echo '>> RBAC seed: COM:Import and OPS:Import exist exactly once each'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.permissions where action = 'Import' and resource_module_code in ('COM', 'OPS');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly one COM:Import and one OPS:Import permission row, found %', v_count;
  end if;
end $$;

\echo '>> app.create_customer_account_direct: COM:Approve-gated (viewer rejected); creates a real account with normalized identity and a computed duplicate fingerprint; a second call for the same legal identity LINKS to the existing account rather than creating a duplicate; source_prospect_id is honestly null'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'mdimp2');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_viewer uuid := '00000000-0000-0000-0000-000000094102';
  v_admin2 uuid := '00000000-0000-0000-0000-000000094201';
  v_account app.accounts;
  v_again app.accounts;
  v_count integer;
begin
  begin
    perform app.create_customer_account_direct(v_tenant1, 'PT Rejected Co', null, null, null, null, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- COM:View alone must not create a canonical customer identity';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.create_customer_account_direct(v_tenant1, '   ', null, null, null, null, v_admin, 'admin');
    raise exception 'assertion failed: expected missing_legal_name for a whitespace-only legal_name';
  exception when check_violation then
    null;
  end;

  v_account := app.create_customer_account_direct(
    v_tenant1, 'PT Nusantara Logistik Prima', 'Nusantara Prima', '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Thamrin 1', 'city', 'Jakarta', 'country', 'ID'),
    null, v_admin, 'admin'
  );
  if v_account.tenant_id <> v_tenant1 or v_account.status <> 'active' or v_account.customer_status <> 'active' then
    raise exception 'assertion failed: expected an active account in mdimp1, got %', v_account;
  end if;
  if v_account.normalized_legal_name is null or v_account.duplicate_fingerprint is null then
    raise exception 'assertion failed: expected the same normalization/fingerprint the quotation path computes, got normalized=% fingerprint=%', v_account.normalized_legal_name, v_account.duplicate_fingerprint;
  end if;
  -- Honest about provenance: there was no prospect, and none is fabricated.
  if v_account.source_prospect_id is not null then
    raise exception 'assertion failed: expected source_prospect_id to be null for a directly-created account, got %', v_account.source_prospect_id;
  end if;
  if v_account.source_import_staging_row_id is not null then
    raise exception 'assertion failed: a directly-created (non-imported) account must carry no import provenance';
  end if;

  -- Create-or-link: the SAME legal identity must not produce a second account. This is the
  -- accounts_tenant_fingerprint_active_unique control working, reached through the new
  -- door exactly as it is through the quotation door.
  v_again := app.create_customer_account_direct(
    v_tenant1, 'PT Nusantara Logistik Prima', 'Different Trade Name', '01.234.567.8-901.000',
    null, null, v_admin, 'admin'
  );
  if v_again.id <> v_account.id then
    raise exception 'assertion failed: expected the same legal identity to LINK to the existing account, got a different id';
  end if;
  select count(*) into v_count from app.accounts where tenant_id = v_tenant1 and status = 'active';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 account after the create-or-link replay, found %', v_count;
  end if;

  -- Tenant scoping: the identical legal identity in a DIFFERENT tenant is a different
  -- customer and must create its own account.
  perform app.create_customer_account_direct(v_tenant2, 'PT Nusantara Logistik Prima', null, '01.234.567.8-901.000', null, null, v_admin2, 'admin2');
  select count(*) into v_count from app.accounts where tenant_id = v_tenant2 and status = 'active';
  if v_count <> 1 then
    raise exception 'assertion failed: expected the same legal identity in a different tenant to create its own account, found % in mdimp2', v_count;
  end if;

  -- A parent account from another tenant is refused.
  begin
    perform app.create_customer_account_direct(v_tenant1, 'PT Cross Tenant Parent', null, null, null,
      (select id from app.accounts where tenant_id = v_tenant2 limit 1), v_admin, 'admin');
    raise exception 'assertion failed: expected parent_account_not_found for a cross-tenant parent';
  exception when no_data_found then
    null;
  end;
end $$;

\echo '>> master-data import setup: source document type and the tenant''s own published column definitions for customer_import and item_import'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_supreme uuid := '00000000-0000-0000-0000-000000094999';
  v_doctype_draft app.config_versions;
  v_draft app.config_versions;
begin
  perform app.register_document_type('master_data_import_source', 'Master Data Import Source File', 'COM', v_supreme, 'supreme');
  v_doctype_draft := app.create_config_draft('document:master_data_import_source', v_tenant1, 'tenant', null, v_admin, 'admin');
  perform app.set_config_items(v_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin, 'admin');
  perform app.publish_document_type_definition(v_doctype_draft.id, v_admin, now(), 'admin');

  v_draft := app.create_config_draft('import_export:customer_import', v_tenant1, 'tenant', null, v_admin, 'admin');
  perform app.set_config_items(
    v_draft.id,
    jsonb_build_array(jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'legal_name', 'label', 'Legal name', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'trade_name', 'label', 'Trade name', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'tax_id', 'label', 'Tax id', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'billing_line1', 'label', 'Billing line 1', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'billing_city', 'label', 'Billing city', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'billing_country', 'label', 'Billing country', 'required', false, 'data_type', 'text')
    ), 'canonical_ref', null)),
    v_admin, 'admin'
  );
  perform app.publish_import_export_schema(v_draft.id, v_admin, now(), 'admin');

  v_draft := app.create_config_draft('import_export:item_import', v_tenant1, 'tenant', null, v_admin, 'admin');
  perform app.set_config_items(
    v_draft.id,
    jsonb_build_array(jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'code', 'label', 'Item code', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'name', 'label', 'Item name', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'description', 'label', 'Description', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'base_uom_code', 'label', 'Base UOM', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'owner_account_tax_id', 'label', 'Owner account tax id', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'owner_account_legal_name', 'label', 'Owner account legal name', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'lot_controlled', 'label', 'Lot controlled', 'required', false, 'data_type', 'boolean')
    ), 'canonical_ref', null)),
    v_admin, 'admin'
  );
  perform app.publish_import_export_schema(v_draft.id, v_admin, now(), 'admin');
end $$;

\echo '>> customer_import: validator rejects formula injection, a whitespace-only legal_name and any platform-derived column a file must never supply (duplicate_fingerprint in particular); a valid batch creates real accounts; a row whose legal identity matches an earlier row LINKS rather than duplicating, and is counted, not silently dropped; replay creates zero duplicates'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_viewer uuid := '00000000-0000-0000-0000-000000094102';
  v_source_file app.files;
  v_job app.jobs;
  v_updated app.jobs;
  v_ids uuid[];
  v_idx integer;
  v_status text;
  v_error text;
  v_before integer;
  v_after integer;
begin
  v_source_file := app.initiate_file_upload(
    v_tenant1, 'master_data_import_source', 'import_source', gen_random_uuid(),
    'customers.csv', 'text/csv', 2048, 'internal', false, null, null, null,
    'idem-mdimp-cust-source', v_admin, 'admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin, 'admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'customer_import', v_source_file.id, '{}'::jsonb, 'idem-mdimp-cust-job', v_admin, 'admin');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(
      -- 1: valid, brand-new customer.
      jsonb_build_object('legal_name', 'PT Sinar Bahari Kargo', 'trade_name', 'Sinar Bahari', 'tax_id', '02.111.222.3-444.000',
                         'billing_line1', 'Jl. Gajah Mada 5', 'billing_city', 'Surabaya', 'billing_country', 'ID'),
      -- 2: formula injection in legal_name.
      jsonb_build_object('legal_name', '=HYPERLINK("http://evil","click")', 'tax_id', '02.999.999.9-999.000'),
      -- 3: whitespace-only legal_name.
      jsonb_build_object('legal_name', '  ', 'tax_id', '02.888.888.8-888.000'),
      -- 4: a file trying to supply its own duplicate fingerprint -- i.e. trying to steer,
      --    or defeat, the duplicate control.
      jsonb_build_object('legal_name', 'PT Sneaky Co', 'duplicate_fingerprint', 'anything-i-like'),
      -- 5: valid, and the SAME legal identity as row 1 -- an ordinary occurrence in a
      --    migration extract. Must link, not duplicate, and must be counted.
      jsonb_build_object('legal_name', 'PT Sinar Bahari Kargo', 'tax_id', '02.111.222.3-444.000'),
      -- 6: valid, and the same legal identity as an account that PREDATES this job
      --    (created directly in the earlier block). Must link, and must NOT rewrite that
      --    account's provenance.
      jsonb_build_object('legal_name', 'PT Nusantara Logistik Prima', 'tax_id', '01.234.567.8-901.000')
    ),
    v_admin, 'admin'
  );

  select array_agg(id order by row_number) into v_ids from app.import_staging_rows where job_id = v_job.job_id;
  for v_idx in 1..6 loop
    perform app.validate_customer_import_row(v_ids[v_idx], v_admin, 'admin');
  end loop;

  if (select validation_status from app.import_staging_rows where id = v_ids[1]) <> 'valid' then
    raise exception 'assertion failed: expected row 1 to validate cleanly';
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[2];
  if v_status <> 'invalid' or v_error not like '%disallowed formula/spreadsheet-injection prefix%' then
    raise exception 'assertion failed: expected row 2 rejected for formula injection, got status=% error=%', v_status, v_error;
  end if;
  if (select raw_payload ->> 'legal_name' from app.import_staging_rows where id = v_ids[2]) <> '=HYPERLINK("http://evil","click")' then
    raise exception 'assertion failed: expected the raw payload preserved verbatim, not sanitized';
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[3];
  if v_status <> 'invalid' or v_error not like '%must not be empty or whitespace-only%' then
    raise exception 'assertion failed: expected row 3 rejected for a whitespace-only legal_name, got status=% error=%', v_status, v_error;
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[4];
  if v_status <> 'invalid' or v_error not like '%duplicate_fingerprint: is not an importable column%' then
    raise exception 'assertion failed: expected row 4 rejected -- a file must never supply its own duplicate fingerprint, got status=% error=%', v_status, v_error;
  end if;

  -- viewer holds COM:View but neither tenant_admin authority nor COM:Import.
  begin
    perform app.commit_customer_import_job(v_job.job_id, true, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer committing a customer import';
  exception when insufficient_privilege then
    null;
  end;

  select count(*) into v_before from app.accounts where tenant_id = v_tenant1 and status = 'active';

  v_updated := app.commit_customer_import_job(v_job.job_id, true, v_admin, 'admin');
  if v_updated.status <> 'completed' then
    raise exception 'assertion failed: expected the job to complete (partial commit), got %', v_updated.status;
  end if;

  -- Exactly ONE new account: row 1 created it, rows 5 and 6 linked.
  select count(*) into v_after from app.accounts where tenant_id = v_tenant1 and status = 'active';
  if v_after <> v_before + 1 then
    raise exception 'assertion failed: expected exactly 1 new account (rows 5 and 6 must LINK, not duplicate), before=% after=%', v_before, v_after;
  end if;

  if not exists (
    select 1 from app.accounts
    where tenant_id = v_tenant1 and source_import_staging_row_id = v_ids[1]
      and legal_name = 'PT Sinar Bahari Kargo' and trade_name = 'Sinar Bahari'
      and billing_address ->> 'city' = 'Surabaya'
  ) then
    raise exception 'assertion failed: expected row 1 to have produced a stamped account with its billing address assembled from the flat columns';
  end if;

  -- Row 5 linked to row 1's account and must NOT have rebound its provenance.
  if exists (select 1 from app.accounts where source_import_staging_row_id = v_ids[5]) then
    raise exception 'assertion failed: a row that linked to an existing account must not be stamped as having created it';
  end if;

  -- Row 6 linked to the pre-existing directly-created account, which must keep its own
  -- (null) provenance -- the import did not create it and must not claim it.
  if (select source_import_staging_row_id from app.accounts where tenant_id = v_tenant1 and legal_name = 'PT Nusantara Logistik Prima') is not null then
    raise exception 'assertion failed: an account that predates the job must not have its provenance rewritten by an import that merely matched it';
  end if;

  -- The invalid rows created nothing at all.
  if exists (select 1 from app.accounts where tenant_id = v_tenant1 and legal_name in ('PT Sneaky Co', '=HYPERLINK("http://evil","click")')) then
    raise exception 'assertion failed: expected the invalid rows to have created no account';
  end if;

  -- Replay is refused by the framework's own contract and creates zero duplicates.
  begin
    perform app.commit_customer_import_job(v_job.job_id, true, v_admin, 'admin');
    raise exception 'assertion failed: expected import_export_job_not_committable on a replayed commit';
  exception when sqlstate '23514' then
    if sqlerrm not like 'import_export_job_not_committable%' then raise; end if;
  end;
  if (select count(*) from app.accounts where tenant_id = v_tenant1 and status = 'active') <> v_after then
    raise exception 'assertion failed: expected the replayed commit attempt to create zero additional accounts';
  end if;
end $$;

\echo '>> ISS-2026-278 (Step 16 historical-issue-backlog remediation, resumed) regression: app.commit_customer_import_job composes app.assert_current_step_up_authorization(tenant, actor, ''COM'', ''Import'') immediately after its own existing COM:Import check -- a strict no-op for a tenant with no MFA policy configured, and a real block-then-unblock once the tenant opts (COM, Import) into its own additional_high_risk_actions and completes a genuine step-up challenge'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_supreme uuid := '00000000-0000-0000-0000-000000094999';
  v_source_file1 app.files;
  v_source_file2 app.files;
  v_job1 app.jobs;
  v_job2 app.jobs;
  v_committed app.jobs;
  v_challenge app.mfa_step_up_challenges;
  v_raised boolean;
begin
  -- v_supreme already exists and holds supreme_admin from this file's own top-level setup.

  -- (a) no app.mfa_tenant_policies row at all yet for this tenant -- a strict no-op, the
  -- commit succeeds exactly as it did before this checkpoint.
  v_source_file1 := app.initiate_file_upload(
    v_tenant1, 'master_data_import_source', 'import_source', gen_random_uuid(),
    'customers-mfacheck-a.csv', 'text/csv', 2048, 'internal', false, null, null, null,
    'idem-mdimp-cust-mfacheck-source-a', v_admin, 'admin'
  );
  perform app.record_file_scan_result(v_source_file1.id, 'clean', 'test-scanner', v_admin, 'admin');
  v_job1 := app.create_import_export_job(v_tenant1, 'import', 'customer_import', v_source_file1.id, '{}'::jsonb, 'idem-mdimp-cust-mfacheck-job-a', v_admin, 'admin');
  perform app.stage_import_rows(v_job1.job_id, jsonb_build_array(jsonb_build_object(
    'legal_name', 'PT Mfa Check Kargo A', 'tax_id', '02.777.777.7-771.000'
  )), v_admin, 'admin');
  perform app.validate_customer_import_row((select id from app.import_staging_rows where job_id = v_job1.job_id and row_number = 1), v_admin, 'admin');
  v_committed := app.commit_customer_import_job(v_job1.job_id, false, v_admin, 'admin');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected a real completed commit for a tenant with no MFA policy configured (strict no-op), got %', v_committed;
  end if;

  -- (b) this tenant now additively opts (COM, Import) into its own additional_high_risk_
  -- actions -- tenant_wide_required deliberately left false, since app.assert_current_
  -- step_up_authorization gates on is_high_risk_action alone, never on tenant_wide_required.
  perform app.set_mfa_tenant_policy(v_tenant1, false, '["supreme_admin", "tenant_admin"]'::jsonb, 15, '[{"moduleCode": "COM", "action": "Import"}]'::jsonb, v_supreme, 'supreme');

  v_source_file2 := app.initiate_file_upload(
    v_tenant1, 'master_data_import_source', 'import_source', gen_random_uuid(),
    'customers-mfacheck-b.csv', 'text/csv', 2048, 'internal', false, null, null, null,
    'idem-mdimp-cust-mfacheck-source-b', v_admin, 'admin'
  );
  perform app.record_file_scan_result(v_source_file2.id, 'clean', 'test-scanner', v_admin, 'admin');
  v_job2 := app.create_import_export_job(v_tenant1, 'import', 'customer_import', v_source_file2.id, '{}'::jsonb, 'idem-mdimp-cust-mfacheck-job-b', v_admin, 'admin');
  perform app.stage_import_rows(v_job2.job_id, jsonb_build_array(jsonb_build_object(
    'legal_name', 'PT Mfa Check Kargo B', 'tax_id', '02.777.777.7-772.000'
  )), v_admin, 'admin');
  perform app.validate_customer_import_row((select id from app.import_staging_rows where job_id = v_job2.job_id and row_number = 1), v_admin, 'admin');

  v_raised := false;
  begin
    perform app.commit_customer_import_job(v_job2.job_id, false, v_admin, 'admin');
    raise exception 'assertion failed: expected mfa_step_up_required with no verified challenge on record, the call unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'mfa_step_up_required' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected mfa_step_up_required, got none';
  end if;
  if (select status from app.jobs where job_id = v_job2.job_id) <> 'in_progress' then
    raise exception 'assertion failed: expected the job to remain in_progress while blocked on step-up';
  end if;

  -- (c) a genuine step-up challenge (request + verify) for the SAME actor/tenant/module/
  -- action then unblocks the identical commit call.
  v_challenge := app.request_mfa_step_up_challenge(v_tenant1, 'COM', 'Import', v_admin, 'admin');
  perform app.verify_mfa_step_up_challenge(v_challenge.id, v_admin, 'admin');

  v_committed := app.commit_customer_import_job(v_job2.job_id, false, v_admin, 'admin');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected a real completed commit once a current verified step-up challenge exists, got %', v_committed;
  end if;

  raise notice 'PASS: app.commit_customer_import_job (ISS-2026-278, resumed) is a strict no-op for a tenant with no MFA policy configured, blocks with mfa_step_up_required once the tenant opts (COM, Import) into its own additional_high_risk_actions, and succeeds again once a genuine step-up challenge is requested and verified';
end;
$$;

\echo '>> item_import: validator resolves the owner account by tax id or legal name and refuses an unresolved or AMBIGUOUS owner rather than guessing; an unregistered base_uom_code is rejected at validation, not mid-commit; a valid batch creates real item masters under the right owner; a repeated (owner, code) links rather than duplicating'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_source_file app.files;
  v_job app.jobs;
  v_updated app.jobs;
  v_ids uuid[];
  v_idx integer;
  v_status text;
  v_error text;
  v_owner_id uuid;
  v_count integer;
begin
  select id into v_owner_id from app.accounts where tenant_id = v_tenant1 and legal_name = 'PT Sinar Bahari Kargo';
  if v_owner_id is null then
    raise exception 'assertion failed: the customer import block must have created PT Sinar Bahari Kargo';
  end if;

  v_source_file := app.initiate_file_upload(
    v_tenant1, 'master_data_import_source', 'import_source', gen_random_uuid(),
    'items.csv', 'text/csv', 2048, 'internal', false, null, null, null,
    'idem-mdimp-item-source', v_admin, 'admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin, 'admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'item_import', v_source_file.id, '{}'::jsonb, 'idem-mdimp-item-job', v_admin, 'admin');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(
      -- 1: valid, owner named by tax id.
      jsonb_build_object('code', 'SKU-0001', 'name', 'Karton Besar', 'base_uom_code', 'PCS',
                         'owner_account_tax_id', '02.111.222.3-444.000', 'lot_controlled', 'true'),
      -- 2: valid, same owner named by legal name instead.
      jsonb_build_object('code', 'SKU-0002', 'name', 'Palet Kayu', 'base_uom_code', 'PCS',
                         'owner_account_legal_name', 'PT Sinar Bahari Kargo'),
      -- 3: unregistered UOM -- must fail at VALIDATION, so it never aborts the batch
      --    mid-commit inside app.create_item_master.
      jsonb_build_object('code', 'SKU-0003', 'name', 'Barang Aneh', 'base_uom_code', 'FURLONG',
                         'owner_account_tax_id', '02.111.222.3-444.000'),
      -- 4: no owner named at all.
      jsonb_build_object('code', 'SKU-0004', 'name', 'Tanpa Pemilik', 'base_uom_code', 'KG'),
      -- 5: owner that does not resolve.
      jsonb_build_object('code', 'SKU-0005', 'name', 'Pemilik Hilang', 'base_uom_code', 'KG',
                         'owner_account_legal_name', 'PT Tidak Ada Sama Sekali'),
      -- 6: same (owner, code) as row 1 -- must link, not duplicate.
      jsonb_build_object('code', 'SKU-0001', 'name', 'Karton Besar (duplikat baris)', 'base_uom_code', 'PCS',
                         'owner_account_tax_id', '02.111.222.3-444.000')
    ),
    v_admin, 'admin'
  );

  select array_agg(id order by row_number) into v_ids from app.import_staging_rows where job_id = v_job.job_id;
  for v_idx in 1..6 loop
    perform app.validate_item_import_row(v_ids[v_idx], v_admin, 'admin');
  end loop;

  if (select validation_status from app.import_staging_rows where id = v_ids[1]) <> 'valid'
     or (select validation_status from app.import_staging_rows where id = v_ids[2]) <> 'valid' then
    raise exception 'assertion failed: expected rows 1 and 2 to validate cleanly (owner by tax id and by legal name respectively)';
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[3];
  if v_status <> 'invalid' or v_error not like '%is not a registered active UOM code%' then
    raise exception 'assertion failed: expected row 3 rejected for an unregistered UOM at validation time, got status=% error=%', v_status, v_error;
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[4];
  if v_status <> 'invalid' or v_error not like '%one of owner_account_tax_id or owner_account_legal_name is required%' then
    raise exception 'assertion failed: expected row 4 rejected for naming no owner, got status=% error=%', v_status, v_error;
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[5];
  if v_status <> 'invalid' or v_error not like '%does not resolve to an active customer account%' then
    raise exception 'assertion failed: expected row 5 rejected for an unresolved owner, got status=% error=%', v_status, v_error;
  end if;

  v_updated := app.commit_item_import_job(v_job.job_id, true, v_admin, 'admin');
  if v_updated.status <> 'completed' then
    raise exception 'assertion failed: expected the item job to complete, got %', v_updated.status;
  end if;

  select count(*) into v_count from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_owner_id;
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 item masters (rows 1 and 2; row 6 must LINK to row 1''s item), found %', v_count;
  end if;

  if not exists (
    select 1 from app.item_masters
    where source_import_staging_row_id = v_ids[1] and code = 'SKU-0001' and owner_account_id = v_owner_id
      and base_uom_code = 'PCS' and lot_controlled
  ) then
    raise exception 'assertion failed: expected row 1''s item stamped with its staging row, under the resolved owner, with lot_controlled carried through';
  end if;
  if not exists (select 1 from app.item_masters where source_import_staging_row_id = v_ids[2] and code = 'SKU-0002') then
    raise exception 'assertion failed: expected row 2''s item (owner resolved by legal name) to exist and be stamped';
  end if;
  -- Row 6 linked; it must not have rebound row 1's provenance, and must not have renamed
  -- the existing item -- app.create_item_master returns the existing row untouched.
  if exists (select 1 from app.item_masters where source_import_staging_row_id = v_ids[6]) then
    raise exception 'assertion failed: a row that linked to an existing item must not be stamped as having created it';
  end if;
  if (select name from app.item_masters where source_import_staging_row_id = v_ids[1]) <> 'Karton Besar' then
    raise exception 'assertion failed: linking must never silently overwrite the existing item''s own name';
  end if;

  -- The invalid rows created nothing.
  if exists (select 1 from app.item_masters where tenant_id = v_tenant1 and code in ('SKU-0003', 'SKU-0004', 'SKU-0005')) then
    raise exception 'assertion failed: expected the invalid rows to have created no item master';
  end if;
end $$;

\echo '>> item_import: an AMBIGUOUS owner_account_legal_name is an error, never a silent pick -- attaching one customer''s items to another customer''s account is a confidentiality problem'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_source_file app.files;
  v_job app.jobs;
  v_row_id uuid;
  v_status text;
  v_error text;
begin
  -- Two active accounts whose legal names normalize identically but whose tax ids differ,
  -- so the fingerprint index permits both to exist -- exactly the real-world case where a
  -- name lookup is genuinely ambiguous.
  perform app.create_customer_account_direct(v_tenant1, 'PT Ambigu Sekali', null, '03.111.111.1-111.000', null, null, v_admin, 'admin');
  perform app.create_customer_account_direct(v_tenant1, 'PT Ambigu Sekali', null, '03.222.222.2-222.000', null, null, v_admin, 'admin');

  v_source_file := app.initiate_file_upload(
    v_tenant1, 'master_data_import_source', 'import_source', gen_random_uuid(),
    'items-ambiguous.csv', 'text/csv', 512, 'internal', false, null, null, null,
    'idem-mdimp-item-ambig-source', v_admin, 'admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin, 'admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'item_import', v_source_file.id, '{}'::jsonb, 'idem-mdimp-item-ambig-job', v_admin, 'admin');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(jsonb_build_object('code', 'SKU-AMBIG', 'name', 'Barang Ambigu', 'base_uom_code', 'KG',
                                         'owner_account_legal_name', 'PT Ambigu Sekali')),
    v_admin, 'admin'
  );
  select id into v_row_id from app.import_staging_rows where job_id = v_job.job_id and row_number = 1;
  perform app.validate_item_import_row(v_row_id, v_admin, 'admin');

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_row_id;
  if v_status <> 'invalid' or v_error not like '%ambiguous%' then
    raise exception 'assertion failed: expected an ambiguous owner name to be rejected with a clear reason, got status=% error=%', v_status, v_error;
  end if;

  -- And no p_allow_partial means the whole job is refused rather than silently dropping it.
  begin
    perform app.commit_item_import_job(v_job.job_id, false, v_admin, 'admin');
    raise exception 'assertion failed: expected import_export_job_has_invalid_rows without p_allow_partial';
  exception when sqlstate '23514' then
    if sqlerrm not like 'import_export_job_has_invalid_rows%' then raise; end if;
  end;

  if exists (select 1 from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-AMBIG') then
    raise exception 'assertion failed: expected no item master created for the ambiguous row';
  end if;
end $$;

\echo '>> cross-schema and grant guards: each commit adapter refuses a job of the other schema code; neither anon nor authenticated holds EXECUTE on any new function or its public wrapper'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_cust_job uuid;
  v_item_job uuid;
  v_has boolean;
  v_fn text;
begin
  select job_id into v_cust_job from app.jobs where tenant_id = v_tenant1 and import_export_schema_code = 'customer_import' limit 1;
  select job_id into v_item_job from app.jobs where tenant_id = v_tenant1 and import_export_schema_code = 'item_import' limit 1;

  begin
    perform app.commit_item_import_job(v_cust_job, true, v_admin, 'admin');
    raise exception 'assertion failed: expected import_export_wrong_schema committing a customer job through the item adapter';
  exception when sqlstate '23514' then
    if sqlerrm not like 'import_export_wrong_schema%' then raise; end if;
  end;

  begin
    perform app.commit_customer_import_job(v_item_job, true, v_admin, 'admin');
    raise exception 'assertion failed: expected import_export_wrong_schema committing an item job through the customer adapter';
  exception when sqlstate '23514' then
    if sqlerrm not like 'import_export_wrong_schema%' then raise; end if;
  end;

  foreach v_fn in array array[
    'app.create_customer_account_direct(uuid, text, text, text, jsonb, uuid, uuid, text)',
    'app.validate_customer_import_row(uuid, uuid, text)',
    'app.commit_customer_import_job(uuid, boolean, uuid, text, text)',
    'app.validate_item_import_row(uuid, uuid, text)',
    'app.commit_item_import_job(uuid, boolean, uuid, text, text)',
    'public.create_customer_account_direct(uuid, text, text, text, jsonb, uuid, uuid, text)',
    'public.validate_customer_import_row(uuid, uuid, text)',
    'public.commit_customer_import_job(uuid, boolean, uuid, text, text)',
    'public.validate_item_import_row(uuid, uuid, text)',
    'public.commit_item_import_job(uuid, boolean, uuid, text, text)'
  ] loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has;
    if v_has then raise exception 'assertion failed: anon must hold no EXECUTE on %', v_fn; end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has;
    if v_has then raise exception 'assertion failed: authenticated must hold no EXECUTE on %', v_fn; end if;
  end loop;
end $$;

\echo '>> ISS-2026-303 setup: a warehouse and a location for tenant mdimp1, plus the tenant''s own published inventory_opening_balance_import column definition -- the fifth PLT-131 adapter, reusing the item masters and owner account the item_import block above already created'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_supreme uuid := '00000000-0000-0000-0000-000000094999';
  v_company uuid;
  v_warehouse app.warehouses;
  v_draft app.config_versions;
  v_user app.users;
begin
  -- Created unconditionally under its own code rather than looked up by type: this file has
  -- never needed an org unit before, and a lookup that silently finds nothing would fail
  -- later, inside create_warehouse, where the reason is much harder to read.
  perform app.create_org_unit(v_tenant1, 'company', null, 'MDIMP-CO', 'MdImp Co', 'tester');
  select id into v_company from app.org_units where tenant_id = v_tenant1 and code = 'MDIMP-CO';

  -- The importer needs genuine RECORD scope over the warehouse, not merely OPS:Import.
  -- app.post_inventory_movement checks app.can_access_record against the warehouse's own
  -- company org unit, and the adapter passes the importer's identity straight through -- so
  -- somebody who could not post this movement by hand must not be able to post it via an
  -- import either. Giving the admin that scope here is what makes the happy path a real
  -- authorization pass rather than a bypass.
  select * into v_user from app.users where tenant_id = v_tenant1 and auth_user_id = v_admin;
  perform app.reassign_user_org_unit(v_user.id, v_company, v_user.record_version, 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-MDIMP-1', 'MdImp Warehouse 1', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'supreme');
  perform app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-A1', 'Rack A1', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'supreme');

  v_draft := app.create_config_draft('import_export:inventory_opening_balance_import', v_tenant1, 'tenant', null, v_admin, 'admin');
  perform app.set_config_items(
    v_draft.id,
    jsonb_build_array(jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'warehouse_code', 'label', 'Warehouse', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'location_code', 'label', 'Location', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'owner_account_tax_id', 'label', 'Owner tax id', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'item_code', 'label', 'Item code', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'uom_code', 'label', 'UOM', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'quantity', 'label', 'Quantity', 'required', true, 'data_type', 'number')
    ), 'canonical_ref', null)),
    v_admin, 'admin'
  );
  perform app.publish_import_export_schema(v_draft.id, v_admin, now(), 'admin');
end $$;

\echo '>> ISS-2026-303: inventory_opening_balance_import -- an unresolvable warehouse/location/item and a non-positive quantity are refused at VALIDATION, so a cutover batch does not abort on row 700; a valid batch posts real opening-balance movements through app.post_inventory_movement rather than writing inventory itself; re-committing is a no-op, not a double-post'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_owner_id uuid;
  v_owner_tax text;
  v_source_file app.files;
  v_job app.jobs;
  v_updated app.jobs;
  v_recommit app.jobs;
  v_ids uuid[];
  v_idx integer;
  v_status text;
  v_error text;
  v_movement_count integer;
  v_balance numeric;
begin
  select id, tax_id into v_owner_id, v_owner_tax from app.accounts where tenant_id = v_tenant1 and legal_name = 'PT Sinar Bahari Kargo';
  if v_owner_id is null or coalesce(v_owner_tax, '') = '' then
    raise exception 'assertion failed: the customer import block must have created PT Sinar Bahari Kargo with a resolvable tax id';
  end if;

  v_source_file := app.initiate_file_upload(
    v_tenant1, 'master_data_import_source', 'import_source', gen_random_uuid(),
    'opening-stock.csv', 'text/csv', 2048, 'internal', false, null, null, null,
    'idem-mdimp-invob-source', v_admin, 'admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin, 'admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'inventory_opening_balance_import', v_source_file.id, '{}'::jsonb, 'idem-mdimp-invob-job', v_admin, 'admin');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(
      -- 1: valid.
      jsonb_build_object('warehouse_code', 'WH-MDIMP-1', 'location_code', 'RACK-A1', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-0001', 'uom_code', 'PCS', 'quantity', '120'),
      -- 2: valid, a second item at the same location.
      jsonb_build_object('warehouse_code', 'WH-MDIMP-1', 'location_code', 'RACK-A1', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-0002', 'uom_code', 'PCS', 'quantity', '7.5'),
      -- 3: unknown warehouse.
      jsonb_build_object('warehouse_code', 'WH-NOPE', 'location_code', 'RACK-A1', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-0001', 'uom_code', 'PCS', 'quantity', '5'),
      -- 4: unknown location within a real warehouse.
      jsonb_build_object('warehouse_code', 'WH-MDIMP-1', 'location_code', 'RACK-NOPE', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-0001', 'uom_code', 'PCS', 'quantity', '5'),
      -- 5: an item that is not owned by the resolved account.
      jsonb_build_object('warehouse_code', 'WH-MDIMP-1', 'location_code', 'RACK-A1', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-NOT-MINE', 'uom_code', 'PCS', 'quantity', '5'),
      -- 6: a zero quantity. An opening balance is what is on the shelf, so zero is a source
      --    data error, refused up front rather than mid-commit.
      jsonb_build_object('warehouse_code', 'WH-MDIMP-1', 'location_code', 'RACK-A1', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-0001', 'uom_code', 'PCS', 'quantity', '0'),
      -- 7: a negative quantity.
      jsonb_build_object('warehouse_code', 'WH-MDIMP-1', 'location_code', 'RACK-A1', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-0001', 'uom_code', 'PCS', 'quantity', '-3'),
      -- 8: an unregistered UOM.
      jsonb_build_object('warehouse_code', 'WH-MDIMP-1', 'location_code', 'RACK-A1', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-0001', 'uom_code', 'NOPE', 'quantity', '5'),
      -- 9: a formula-injection prefix in a text cell.
      jsonb_build_object('warehouse_code', '=cmd|calc', 'location_code', 'RACK-A1', 'owner_account_tax_id', v_owner_tax,
                         'item_code', 'SKU-0001', 'uom_code', 'PCS', 'quantity', '5')
    ),
    v_admin, 'admin'
  );

  select array_agg(id order by row_number) into v_ids from app.import_staging_rows where job_id = v_job.job_id;

  for v_idx in 1..9 loop
    perform app.validate_inventory_opening_balance_import_row(v_ids[v_idx], v_admin, 'admin');
  end loop;

  for v_idx in 1..2 loop
    select validation_status into v_status from app.import_staging_rows where id = v_ids[v_idx];
    if v_status <> 'valid' then
      raise exception 'assertion failed: row % should be valid, got % (%)', v_idx, v_status,
        (select error from app.import_staging_rows where id = v_ids[v_idx]);
    end if;
  end loop;

  for v_idx in 3..9 loop
    select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[v_idx];
    if v_status <> 'invalid' then
      raise exception 'assertion failed: row % should be invalid, got %', v_idx, v_status;
    end if;
    if coalesce(v_error, '') = '' then
      raise exception 'assertion failed: row % is invalid but carries no reason -- an importer cannot fix what they are not told', v_idx;
    end if;
  end loop;

  v_updated := app.commit_inventory_opening_balance_import_job(v_job.job_id, true, v_admin, 'admin');
  if v_updated.status <> 'completed' then
    raise exception 'assertion failed: expected a completed job, got %', v_updated.status;
  end if;
  if (v_updated.payload ->> 'posted_count')::integer <> 2 then
    raise exception 'assertion failed: expected 2 posted rows, got %', v_updated.payload ->> 'posted_count';
  end if;

  -- The adapter writes no inventory itself: every row went through app.post_inventory_movement,
  -- so the movements carry that primitive's own opening_balance type and source lineage.
  select count(*) into v_movement_count from app.inventory_movements
  where tenant_id = v_tenant1 and movement_type = 'opening_balance' and source_type = 'opening_balance'
    and idempotency_key like 'inventory-opening-balance-import:%';
  if v_movement_count <> 2 then
    raise exception 'assertion failed: expected 2 opening-balance movements posted through the primitive, got %', v_movement_count;
  end if;

  -- And the balance the primitive maintains genuinely moved -- proof the import produced real
  -- stock rather than a movement header with nothing behind it.
  select sum(b.on_hand) into v_balance from app.inventory_balances b
  join app.item_masters i on i.id = b.item_master_id
  where b.tenant_id = v_tenant1 and i.code in ('SKU-0001', 'SKU-0002');
  if coalesce(v_balance, 0) <> 127.5 then
    raise exception 'assertion failed: expected 120 + 7.5 = 127.5 units on hand from the import, got %', coalesce(v_balance, 0);
  end if;

  -- The invalid rows created nothing at all.
  if exists (
    select 1 from app.inventory_movements
    where tenant_id = v_tenant1 and idempotency_key = any(array[
      'inventory-opening-balance-import:' || v_ids[3]::text,
      'inventory-opening-balance-import:' || v_ids[6]::text,
      'inventory-opening-balance-import:' || v_ids[7]::text
    ])
  ) then
    raise exception 'assertion failed: an invalid row must post no movement';
  end if;

  -- Re-committing is a no-op rather than a double-post. A cutover that half-succeeded and was
  -- retried must not duplicate a warehouse's opening stock.
  update app.jobs set status = 'in_progress' where job_id = v_job.job_id;
  v_recommit := app.commit_inventory_opening_balance_import_job(v_job.job_id, true, v_admin, 'admin');
  if (v_recommit.payload ->> 'posted_count')::integer <> 0 or (v_recommit.payload ->> 'skipped_count')::integer <> 2 then
    raise exception 'assertion failed: a re-commit must post 0 and skip 2, got posted=% skipped=%',
      v_recommit.payload ->> 'posted_count', v_recommit.payload ->> 'skipped_count';
  end if;
  select count(*) into v_movement_count from app.inventory_movements
  where tenant_id = v_tenant1 and idempotency_key like 'inventory-opening-balance-import:%';
  if v_movement_count <> 2 then
    raise exception 'assertion failed: a re-commit must not create a third movement, got %', v_movement_count;
  end if;

  raise notice 'PASS: inventory opening balances import in bulk through the existing movement primitive, invalid rows are refused with reasons at validation time, and a retry is a no-op';
end $$;

\echo '>> ISS-2026-303: the inventory adapter refuses a caller without OPS:Import, and refuses a job staged under a different schema -- an adapter that will commit anything is not an adapter'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'mdimp1');
  v_admin uuid := '00000000-0000-0000-0000-000000094101';
  v_viewer uuid := '00000000-0000-0000-0000-000000094102';
  v_wrong_job uuid := (select job_id from app.jobs where tenant_id = v_tenant1 and import_export_schema_code = 'item_import' limit 1);
  v_job_id uuid := (select job_id from app.jobs where tenant_id = v_tenant1 and import_export_schema_code = 'inventory_opening_balance_import' limit 1);
begin
  update app.jobs set status = 'in_progress' where job_id = v_job_id;
  begin
    perform app.commit_inventory_opening_balance_import_job(v_job_id, true, v_viewer, 'viewer');
    raise exception 'assertion failed: expected a caller without OPS:Import to be refused';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' and sqlerrm not like 'job_actor_unauthorized%' then raise; end if;
  end;

  begin
    perform app.commit_inventory_opening_balance_import_job(v_wrong_job, true, v_admin, 'admin');
    raise exception 'assertion failed: expected an item_import job to be refused by the inventory adapter';
  exception
    when others then
      if sqlerrm not like 'import_export_wrong_schema%' then raise; end if;
  end;

  update app.jobs set status = 'completed' where job_id = v_job_id;
  raise notice 'PASS: the inventory adapter refuses an unauthorized caller and a foreign schema';
end $$;

\echo '>> master-data-import.sql: ALL PASSED'
