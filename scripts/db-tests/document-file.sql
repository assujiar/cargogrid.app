-- Real, executable test evidence for PLT-128 (Document and File Engine, CG-S6-PLT-025).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; Acme has an uploader, a shared-org-unit teammate, an outsider, a tenant_admin (support authority), and a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000002001', 'uploaderdoc@example.test'),
    ('00000000-0000-0000-0000-000000002002', 'teammatedoc@example.test'),
    ('00000000-0000-0000-0000-000000002003', 'outsiderdoc@example.test'),
    ('00000000-0000-0000-0000-000000002004', 'tenantadmindoc@example.test'),
    ('00000000-0000-0000-0000-000000002005', 'supremedoc@example.test'),
    ('00000000-0000-0000-0000-000000002006', 'othertenantdoc@example.test');

  perform app.provision_tenant('acmedoc', 'Acme Document Co', 'idem-acmedoc', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEDOC-CO', 'Acme Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEDOC-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000002001', 'uploaderdoc@example.test', 'Uploader', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'uploaderdoc@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002001', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000002002', 'teammatedoc@example.test', 'Teammate', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'teammatedoc@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002002', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000002003', 'outsiderdoc@example.test', 'Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsiderdoc@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002003', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000002004', 'tenantadmindoc@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmindoc@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002004', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002005', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmodoc', 'Gizmo Document Co', 'idem-gizmodoc', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmodoc');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000002006', 'othertenantdoc@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantdoc@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002006', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.register_document_type: idempotent, Supreme-Admin-only, and mints a dedicated document:<code> config_type (PLT-121''s registry reused, not forked)'
do $$
declare
  v_registered1 app.document_types;
  v_registered2 app.document_types;
  v_config_type_exists boolean;
begin
  begin
    perform app.register_document_type('contract', 'Contract', 'DOC', '00000000-0000-0000-0000-000000002004', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a document type';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_document_type('contract', 'Contract', 'DOC', '00000000-0000-0000-0000-000000002005', 'supreme admin');
  v_registered2 := app.register_document_type('contract', 'Contract', 'DOC', '00000000-0000-0000-0000-000000002005', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;

  select exists (select 1 from app.config_types where code = 'document:contract') into v_config_type_exists;
  if not v_config_type_exists then
    raise exception 'assertion failed: expected app.register_document_type to also mint a document:contract config_type';
  end if;

  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000002005', 'supreme admin');
end;
$$;

\echo '>> app.validate_document_type_definition / app.publish_document_type_definition: every structural failure mode is a distinct, named exception; a valid definition publishes'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_draft := app.create_config_draft('document:contract', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000002004', 'tenant admin');

  begin
    perform app.set_config_items(v_draft.id, '[]'::jsonb, '00000000-0000-0000-0000-000000002004', 'tenant admin');
    perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
    raise exception 'assertion failed: expected document_missing_mime_types';
  exception
    when check_violation then
      if sqlerrm !~ 'document_missing_mime_types' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/x-msdownload'))
    ), '00000000-0000-0000-0000-000000002004', 'tenant admin');
    perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
    raise exception 'assertion failed: expected document_invalid_mime_type';
  exception
    when check_violation then
      if sqlerrm !~ 'document_invalid_mime_type' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg'))
    ), '00000000-0000-0000-0000-000000002004', 'tenant admin');
    perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
    raise exception 'assertion failed: expected document_missing_max_size';
  exception
    when check_violation then
      if sqlerrm !~ 'document_missing_max_size' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
      jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(999999999999::bigint))
    ), '00000000-0000-0000-0000-000000002004', 'tenant admin');
    perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
    raise exception 'assertion failed: expected document_invalid_max_size';
  exception
    when check_violation then
      if sqlerrm !~ 'document_invalid_max_size' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
      jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760))
    ), '00000000-0000-0000-0000-000000002004', 'tenant admin');
    perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
    raise exception 'assertion failed: expected document_invalid_retention_class';
  exception
    when check_violation then
      if sqlerrm !~ 'document_invalid_retention_class' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
      jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
      jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text))
    ), '00000000-0000-0000-0000-000000002004', 'tenant admin');
    perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
    raise exception 'assertion failed: expected document_invalid_default_classification';
  exception
    when check_violation then
      if sqlerrm !~ 'document_invalid_default_classification' then raise; end if;
  end;

  begin
    perform app.set_config_items(v_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
      jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
      jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
      jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text))
    ), '00000000-0000-0000-0000-000000002004', 'tenant admin');
    perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
    raise exception 'assertion failed: expected document_missing_legal_hold_eligible';
  exception
    when check_violation then
      if sqlerrm !~ 'document_missing_legal_hold_eligible' then raise; end if;
  end;

  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(true))
  ), '00000000-0000-0000-0000-000000002004', 'tenant admin');
  v_published := app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the valid contract definition to publish';
  end if;

  -- A second document type ('epod'), deliberately not legal-hold-eligible and with a
  -- tighter max size, to prove per-type rule differences are real, not shared globals.
  v_draft := app.create_config_draft('document:epod', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000002004', 'tenant admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/jpeg', 'image/png')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(1048576)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), '00000000-0000-0000-0000-000000002004', 'tenant admin');
  perform app.publish_document_type_definition(v_draft.id, '00000000-0000-0000-0000-000000002004', now(), 'tenant admin');
end;
$$;

\echo '>> app.initiate_file_upload: unauthorized actor, unconfigured type, unsafe filename, disallowed MIME, oversized, weak classification, legal-hold failures all rejected; a valid upload succeeds and is idempotent'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_file app.files;
  v_replay app.files;
  v_record_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmodoc');
  v_record_id := gen_random_uuid();

  begin
    perform app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'a.pdf', 'application/pdf', 1000, null, false, null, '{}', null, null, '00000000-0000-0000-0000-000000002006', 'outsider tenant admin');
    raise exception 'assertion failed: expected an actor with no membership in this tenant to be refused outright';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.initiate_file_upload(v_tenant_id, 'invoice', 'shipment', gen_random_uuid(), 'a.pdf', 'application/pdf', 1000, null, false, null, '{}', null, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_type_not_configured for a document type never published for this tenant';
  exception
    when check_violation then
      if sqlerrm !~ 'document_type_not_configured' then raise; end if;
  end;

  begin
    perform app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), '../../etc/passwd', 'application/pdf', 1000, null, false, null, '{}', null, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_unsafe_filename for a traversal-shaped filename';
  exception
    when check_violation then
      if sqlerrm !~ 'document_unsafe_filename' then raise; end if;
  end;

  begin
    perform app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'a.exe', 'application/x-msdownload', 1000, null, false, null, '{}', null, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_mime_type_not_allowed';
  exception
    when check_violation then
      if sqlerrm !~ 'document_mime_type_not_allowed' then raise; end if;
  end;

  begin
    perform app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'a.pdf', 'application/pdf', 999999999, null, false, null, '{}', null, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_file_too_large';
  exception
    when check_violation then
      if sqlerrm !~ 'document_file_too_large' then raise; end if;
  end;

  begin
    perform app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'a.pdf', 'application/pdf', 1000, 'internal', false, null, '{}', null, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_classification_too_weak (internal is weaker than contract''s confidential default)';
  exception
    when check_violation then
      if sqlerrm !~ 'document_classification_too_weak' then raise; end if;
  end;

  begin
    perform app.initiate_file_upload(v_tenant_id, 'epod', 'shipment', gen_random_uuid(), 'proof.jpg', 'image/jpeg', 1000, null, true, 'litigation hold', '{}', null, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_type_not_legal_hold_eligible for epod';
  exception
    when check_violation then
      if sqlerrm !~ 'document_type_not_legal_hold_eligible' then raise; end if;
  end;

  begin
    perform app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'a.pdf', 'application/pdf', 1000, null, true, null, '{}', null, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_legal_hold_reason_required';
  exception
    when check_violation then
      if sqlerrm !~ 'document_legal_hold_reason_required' then raise; end if;
  end;

  v_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', v_record_id, 'msa.pdf', 'application/pdf', 204800, null, false, null, '{}', null, 'idem-msa-upload-1', '00000000-0000-0000-0000-000000002001', 'uploader');
  if v_file.malware_scan_status <> 'pending' or v_file.classification <> 'confidential' or v_file.lifecycle_status <> 'active' or v_file.version_number <> 1 or not v_file.is_latest_version then
    raise exception 'assertion failed: unexpected initial file state %', v_file;
  end if;
  if position(v_file.id::text in v_file.storage_path) = 0 or position(v_file.original_filename in v_file.storage_path) > 0 then
    raise exception 'assertion failed: expected storage_path to be derived from the file id, never the original filename';
  end if;

  -- ATW-031 (ISS-2026-029) CORRECTION: this replay call previously passed a FRESH
  -- gen_random_uuid() as p_record_id, so it was never a replay of the same request at
  -- all -- it was an upload against a genuinely DIFFERENT record that the unguarded
  -- short-circuit silently answered with the FIRST record's file row. The assertion
  -- below therefore asserted the defect, which is exactly why no prior checkpoint
  -- caught it. A real client retry reuses the same record id, as it now does here.
  v_replay := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', v_record_id, 'msa.pdf', 'application/pdf', 204800, null, false, null, '{}', null, 'idem-msa-upload-1', '00000000-0000-0000-0000-000000002001', 'uploader');
  if v_replay.id <> v_file.id then
    raise exception 'assertion failed: expected a repeated idempotency_key to return the existing row, not create a duplicate';
  end if;

  -- ATW-031: the same key against a DIFFERENT record must now be rejected outright,
  -- never answered with another record's own file.
  begin
    perform app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'msa.pdf', 'application/pdf', 204800, null, false, null, '{}', null, 'idem-msa-upload-1', '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: reusing one idempotency_key for a DIFFERENT record silently returned the first record''s file instead of raising idempotency_key_conflict';
  exception
    when unique_violation then
      if sqlerrm !~ 'idempotency_key_conflict' then raise; end if;
  end;
end;
$$;

\echo '>> app.record_file_scan_result: invalid status, idempotent re-resolution, conflicting re-resolution, and the audit_logs success/failure mapping'
do $$
declare
  v_tenant_id uuid;
  v_file_id uuid;
  v_updated app.files;
  v_again app.files;
  v_audit_result text;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_file_id := (select id from app.files where tenant_id = v_tenant_id and idempotency_key = 'idem-msa-upload-1');

  begin
    perform app.record_file_scan_result(v_file_id, 'not_a_status', null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_scan_status_invalid';
  exception
    when check_violation then
      if sqlerrm !~ 'document_scan_status_invalid' then raise; end if;
  end;

  v_updated := app.record_file_scan_result(v_file_id, 'clean', 'provider-ref-1', '00000000-0000-0000-0000-000000002001', 'uploader');
  if v_updated.malware_scan_status <> 'clean' or v_updated.malware_scan_completed_at is null then
    raise exception 'assertion failed: expected malware_scan_status=clean with a completed_at timestamp';
  end if;

  v_again := app.record_file_scan_result(v_file_id, 'clean', 'provider-ref-1', '00000000-0000-0000-0000-000000002001', 'uploader');
  if v_again.id <> v_updated.id then
    raise exception 'assertion failed: expected re-resolving to the same status to be a no-op, not an error';
  end if;

  begin
    perform app.record_file_scan_result(v_file_id, 'infected', null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_scan_already_resolved when re-resolving to a different status';
  exception
    when check_violation then
      if sqlerrm !~ 'document_scan_already_resolved' then raise; end if;
  end;

  select result into v_audit_result from app.audit_logs where action = 'record_file_scan_result' and resource_id = v_file_id order by occurred_at desc limit 1;
  if v_audit_result <> 'success' then
    raise exception 'assertion failed: expected the clean-scan audit entry to record result=success, got %', v_audit_result;
  end if;
end;
$$;

\echo '>> ISS-2026-231 regression: app.record_file_scan_result''s own "cannot re-resolve" invariant has no BLOCKING schema-level backstop (deliberate, matches an established pattern used by 4 other domains'' own test suites -- see the raw UPDATE tests in customer-epod-access.sql/procurement-vendor-compliance.sql/procurement-vendor-financial-security.sql/ticketing-customer.sql), but a raw, session-context-free out-of-band correction now DOES produce an app.audit_logs entry (RPD-022''s own "every such mutation is audited" doctrine), where before it produced none'
do $$
declare
  v_tenant_id uuid;
  v_file_id uuid;
  v_audit_count integer;
  v_before_status text;
  v_after_status text;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_file_id := (select id from app.files where tenant_id = v_tenant_id and idempotency_key = 'idem-msa-upload-1');

  -- Same shape as the 4 other domains' own established RPD-022 residual-risk raw
  -- correction: a plain UPDATE, no session context (no set local request.jwt.claims
  -- in this session at this point), re-flagging an already-'clean' file. Confirmed
  -- NOT blocked -- app.record_file_scan_result's own RPC-level check (the primary,
  -- documented control) already refused this above; this is the schema-level path.
  update app.files set malware_scan_status = 'infected' where id = v_file_id;

  select count(*) into v_audit_count from app.audit_logs
  where action = 'files_malware_scan_status_raw_correction' and resource_id = v_file_id
    and result = 'success' and actor_auth_user_id is null;
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly one no-session-actor app.audit_logs row for the raw malware_scan_status correction, got %', v_audit_count;
  end if;

  select before_value ->> 'malware_scan_status', after_value ->> 'malware_scan_status'
    into v_before_status, v_after_status
  from app.audit_logs
  where action = 'files_malware_scan_status_raw_correction' and resource_id = v_file_id
  order by occurred_at desc limit 1;
  if v_before_status <> 'clean' or v_after_status <> 'infected' then
    raise exception 'assertion failed: expected before/after malware_scan_status of clean/infected captured on the raw-correction audit row, got %/%', v_before_status, v_after_status;
  end if;

  -- The RPC's own no-op re-resolution path (same status) does NOT double-fire this
  -- trigger's audit capture -- it never reaches the UPDATE statement for a same-value
  -- transition at all (early return), so the count above stays exactly 1.
  perform app.record_file_scan_result(v_file_id, 'infected', null, '00000000-0000-0000-0000-000000002001', 'uploader');
  select count(*) into v_audit_count from app.audit_logs
  where action = 'files_malware_scan_status_raw_correction' and resource_id = v_file_id;
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected the raw-correction audit count to stay at 1 after a same-status no-op re-resolution attempt, got %', v_audit_count;
  end if;

  update app.files set malware_scan_status = 'clean' where id = v_file_id;
end;
$$;

\echo '>> app.record_file_scan_result: an infected result audits as failure, not the raw ''infected'' literal (the exact audit_logs.result CHECK class of bug PLT-127 found)'
do $$
declare
  v_tenant_id uuid;
  v_file app.files;
  v_audit_result text;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'infected.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-infected-1', '00000000-0000-0000-0000-000000002001', 'uploader');
  perform app.record_file_scan_result(v_file.id, 'infected', 'provider-ref-2', '00000000-0000-0000-0000-000000002001', 'uploader');

  select result into v_audit_result from app.audit_logs where action = 'record_file_scan_result' and resource_id = v_file.id order by occurred_at desc limit 1;
  if v_audit_result <> 'failure' then
    raise exception 'assertion failed: expected the infected-scan audit entry to record result=failure (audit_logs.result only allows success/failure), got %', v_audit_result;
  end if;
end;
$$;

\echo '>> app.authorize_file_access: the malware-scan gate -- uploader may access their own not-yet-clean file, another tenant member may not; infected blocks even the uploader; metadata_view bypasses the scan gate'
do $$
declare
  v_tenant_id uuid;
  v_pending_file app.files;
  v_infected_file_id uuid;
  v_log app.file_access_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_pending_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'pending.pdf', 'application/pdf', 1000, null, false, null, array[(select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEDOC-CO')], null, 'idem-pending-1', '00000000-0000-0000-0000-000000002001', 'uploader');

  v_log := app.authorize_file_access(v_pending_file.id, 'download', '00000000-0000-0000-0000-000000002001');
  if v_log.result <> 'granted' then
    raise exception 'assertion failed: expected the uploader to be granted access to their own not-yet-scanned file';
  end if;

  v_log := app.authorize_file_access(v_pending_file.id, 'download', '00000000-0000-0000-0000-000000002002');
  if v_log.result <> 'denied' or v_log.reason <> 'document_not_yet_scanned' then
    raise exception 'assertion failed: expected a non-uploader teammate to be denied with document_not_yet_scanned, got % / %', v_log.result, v_log.reason;
  end if;

  v_log := app.authorize_file_access(v_pending_file.id, 'metadata_view', '00000000-0000-0000-0000-000000002002');
  if v_log.result <> 'granted' then
    raise exception 'assertion failed: expected metadata_view to bypass the malware-scan gate (pending scan is visible with safe status), got %', v_log.result;
  end if;

  v_infected_file_id := (select id from app.files where tenant_id = v_tenant_id and idempotency_key = 'idem-infected-1');
  v_log := app.authorize_file_access(v_infected_file_id, 'download', '00000000-0000-0000-0000-000000002001');
  if v_log.result <> 'denied' or v_log.reason <> 'document_infected_quarantined' then
    raise exception 'assertion failed: expected an infected file to be quarantined even from its own uploader, got % / %', v_log.result, v_log.reason;
  end if;

  begin
    perform app.authorize_file_access(v_pending_file.id, 'download', '00000000-0000-0000-0000-000000002006');
    raise exception 'assertion failed: expected an actor with no membership in this tenant to be refused outright, not logged';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> app.authorize_file_access: record-scope and classification gates -- a shared-org-unit teammate is granted a clean confidential file, denied a restricted one; an outsider is denied both; support authority overrides the classification gate'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_file app.files;
  v_restricted app.files;
  v_log app.file_access_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEDOC-CO');

  v_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'shared.pdf', 'application/pdf', 1000, null, false, null, array[v_org_unit_id], null, 'idem-shared-1', '00000000-0000-0000-0000-000000002001', 'uploader');
  perform app.record_file_scan_result(v_file.id, 'clean', null, '00000000-0000-0000-0000-000000002001', 'uploader');

  v_log := app.authorize_file_access(v_file.id, 'download', '00000000-0000-0000-0000-000000002002');
  if v_log.result <> 'granted' then
    raise exception 'assertion failed: expected the shared-org-unit teammate to be granted a clean confidential file';
  end if;

  v_log := app.authorize_file_access(v_file.id, 'download', '00000000-0000-0000-0000-000000002003');
  if v_log.result <> 'denied' or v_log.reason <> 'document_record_access_denied' then
    raise exception 'assertion failed: expected the outsider (no share, not the owner) to be denied with document_record_access_denied, got % / %', v_log.result, v_log.reason;
  end if;

  v_restricted := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'restricted.pdf', 'application/pdf', 1000, 'restricted', false, null, array[v_org_unit_id], null, 'idem-restricted-1', '00000000-0000-0000-0000-000000002001', 'uploader');
  perform app.record_file_scan_result(v_restricted.id, 'clean', null, '00000000-0000-0000-0000-000000002001', 'uploader');

  v_log := app.authorize_file_access(v_restricted.id, 'download', '00000000-0000-0000-0000-000000002002');
  if v_log.result <> 'denied' or v_log.reason <> 'document_classification_access_denied' then
    raise exception 'assertion failed: expected the shared-org-unit teammate to be denied a restricted file (share alone is not enough), got % / %', v_log.result, v_log.reason;
  end if;

  v_log := app.authorize_file_access(v_restricted.id, 'download', '00000000-0000-0000-0000-000000002004');
  if v_log.result <> 'granted' then
    raise exception 'assertion failed: expected the tenant_admin (support authority) to be granted the restricted file';
  end if;
end;
$$;

\echo '>> app.create_file_version: authority, deleted-file, non-latest-version, and MIME/size re-validation guards; a valid version bump flips the prior row to superseded and keeps exactly one is_latest_version per group'
do $$
declare
  v_tenant_id uuid;
  v_file app.files;
  v_v2 app.files;
  v_v3 app.files;
  v_prev_reloaded app.files;
  v_latest_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'v1.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-version-1', '00000000-0000-0000-0000-000000002001', 'uploader');

  begin
    perform app.create_file_version(v_file.id, 'v2.pdf', 'application/pdf', 1200, null, '00000000-0000-0000-0000-000000002003', 'outsider');
    raise exception 'assertion failed: expected document_version_unauthorized for a non-uploader, non-support actor';
  exception
    when insufficient_privilege then
      null;
  end;

  v_v2 := app.create_file_version(v_file.id, 'v2.pdf', 'application/pdf', 1200, null, '00000000-0000-0000-0000-000000002001', 'uploader');
  if v_v2.version_number <> 2 or not v_v2.is_latest_version or v_v2.version_group_id <> v_file.version_group_id then
    raise exception 'assertion failed: unexpected v2 state %', v_v2;
  end if;

  select * into v_prev_reloaded from app.files where id = v_file.id;
  if v_prev_reloaded.is_latest_version or v_prev_reloaded.lifecycle_status <> 'superseded' then
    raise exception 'assertion failed: expected v1 to be flipped to is_latest_version=false, lifecycle_status=superseded';
  end if;

  select count(*) into v_latest_count from app.files where version_group_id = v_file.version_group_id and is_latest_version;
  if v_latest_count <> 1 then
    raise exception 'assertion failed: expected exactly one is_latest_version row per version group, got %', v_latest_count;
  end if;

  begin
    perform app.create_file_version(v_file.id, 'v2b.pdf', 'application/pdf', 1200, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_version_not_latest when versioning from a since-superseded row';
  exception
    when check_violation then
      if sqlerrm !~ 'document_version_not_latest' then raise; end if;
  end;

  begin
    perform app.create_file_version(v_v2.id, 'v3.exe', 'application/x-msdownload', 1200, null, '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_mime_type_not_allowed to be re-checked on a new version';
  exception
    when check_violation then
      if sqlerrm !~ 'document_mime_type_not_allowed' then raise; end if;
  end;

  v_v3 := app.create_file_version(v_v2.id, 'v3.pdf', 'application/pdf', 1300, null, '00000000-0000-0000-0000-000000002001', 'uploader');
  if v_v3.version_number <> 3 then
    raise exception 'assertion failed: expected v3';
  end if;
end;
$$;

\echo '>> app.request_file_deletion / app.set_file_legal_hold: legal hold blocks deletion; only support/Supreme may set a hold; deletion is idempotent and soft-only'
do $$
declare
  v_tenant_id uuid;
  v_file app.files;
  v_deleted app.files;
  v_deleted_again app.files;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hold.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-hold-1', '00000000-0000-0000-0000-000000002001', 'uploader');

  begin
    perform app.set_file_legal_hold(v_file.id, true, 'litigation', '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_legal_hold_unauthorized for a regular org_user';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.set_file_legal_hold(v_file.id, true, null, '00000000-0000-0000-0000-000000002004', 'tenant admin');
    raise exception 'assertion failed: expected document_legal_hold_reason_required';
  exception
    when check_violation then
      if sqlerrm !~ 'document_legal_hold_reason_required' then raise; end if;
  end;

  perform app.set_file_legal_hold(v_file.id, true, 'litigation hold pending case #42', '00000000-0000-0000-0000-000000002004', 'tenant admin');

  begin
    perform app.request_file_deletion(v_file.id, 'no longer needed', '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_legal_hold_blocks_deletion';
  exception
    when check_violation then
      if sqlerrm !~ 'document_legal_hold_blocks_deletion' then raise; end if;
  end;

  perform app.set_file_legal_hold(v_file.id, false, null, '00000000-0000-0000-0000-000000002004', 'tenant admin');

  begin
    perform app.request_file_deletion(v_file.id, 'no longer needed', '00000000-0000-0000-0000-000000002003', 'outsider');
    raise exception 'assertion failed: expected document_deletion_unauthorized for a non-uploader, non-support actor';
  exception
    when insufficient_privilege then
      null;
  end;

  v_deleted := app.request_file_deletion(v_file.id, 'no longer needed', '00000000-0000-0000-0000-000000002001', 'uploader');
  if v_deleted.deleted_at is null or v_deleted.lifecycle_status <> 'deleted' then
    raise exception 'assertion failed: expected a soft delete (deleted_at set, lifecycle_status=deleted)';
  end if;

  v_deleted_again := app.request_file_deletion(v_file.id, 'no longer needed', '00000000-0000-0000-0000-000000002001', 'uploader');
  if v_deleted_again.deleted_at <> v_deleted.deleted_at then
    raise exception 'assertion failed: expected a repeated deletion request to be idempotent (same deleted_at), not a fresh mutation';
  end if;
end;
$$;

\echo '>> RLS on app.files: uploader/shared-teammate see a row, outsider and cross-tenant callers do not; restricted classification hides from a mere teammate but not support authority; a deleted row hides from a regular member but not support authority; Supreme sees everything'
do $$
declare
  v_tenant_id uuid;
  v_visible_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002001", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-shared-1';
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the uploader to see their own row via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002002", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-shared-1';
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the shared-org-unit teammate to see the row via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002003", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-shared-1';
  if v_visible_count <> 0 then raise exception 'assertion failed: expected the outsider to be denied visibility via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002006", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-shared-1';
  if v_visible_count <> 0 then raise exception 'assertion failed: expected a cross-tenant actor (IDOR-style guess) to be denied visibility via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002002", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-restricted-1';
  if v_visible_count <> 0 then raise exception 'assertion failed: expected the mere teammate to be denied visibility of a restricted file via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002004", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-restricted-1';
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the tenant_admin (support authority) to see the restricted file via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002001", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-hold-1';
  if v_visible_count <> 0 then raise exception 'assertion failed: expected a regular member (the former uploader) to be denied visibility of a deleted file via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002004", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-hold-1';
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the tenant_admin (support authority) to still see the deleted file via RLS'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002005", "role": "authenticated"}';
  select count(*) into v_visible_count from app.files where idempotency_key = 'idem-hold-1';
  if v_visible_count <> 1 then raise exception 'assertion failed: expected the Supreme Admin to see everything regardless of tenant/classification/deletion'; end if;
  reset role;
end;
$$;

\echo '>> app.document_types RLS: broadly readable to any authenticated caller'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002003", "role": "authenticated"}';
  select count(*) into v_count from app.document_types where code = 'contract';
  if v_count <> 1 then raise exception 'assertion failed: expected the document_types registry to be broadly readable'; end if;
  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated cannot write app.files directly, and has no grant at all on app.file_access_logs'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002001", "role": "authenticated"}';
  begin
    insert into app.files (tenant_id, document_type_code, config_version_id, record_type, record_id, classification, original_filename, mime_type, size_bytes, storage_path, version_group_id, uploaded_by_auth_user_id)
    values (gen_random_uuid(), 'contract', gen_random_uuid(), 'shipment', gen_random_uuid(), 'internal', 'x.pdf', 'application/pdf', 100, 'x', gen_random_uuid(), gen_random_uuid());
    raise exception 'assertion failed: authenticated must be denied direct INSERT on app.files, but it succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform 1 from app.file_access_logs limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.file_access_logs entirely, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;
  reset role;
end;
$$;

\echo '>> HDN-377 (Storage and Signed URL Audit) regression: app.files.storage_path is no longer selectable by authenticated at all -- other columns remain readable, service_role is unaffected'
do $$
declare
  v_tenant_id uuid;
  v_file app.files;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hdn377-key.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-hdn377-storagepath-1', '00000000-0000-0000-0000-000000002001', 'uploader');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002001", "role": "authenticated"}';
  begin
    perform storage_path from app.files where id = v_file.id;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.files.storage_path, even for their own uploaded row, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;
  perform original_filename, malware_scan_status from app.files where id = v_file.id;
  reset role;

  perform storage_path from app.files where id = v_file.id;
end;
$$;

\echo '>> HDN-377 (Storage and Signed URL Audit) regression: a raw DELETE of a legally-held file is blocked at the schema level -- app.request_file_deletion''s own RPC-level check is not the only guard, and Supreme Admin''s RPD-022 override still works, audited'
do $$
declare
  v_tenant_id uuid;
  v_file app.files;
  v_audit app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');
  v_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hdn377-hold.pdf', 'application/pdf', 1000, null, true, 'litigation hold', '{}', null, 'idem-hdn377-hold-1', '00000000-0000-0000-0000-000000002001', 'uploader');

  perform set_config('request.jwt.claims', 'null', true);
  begin
    delete from app.files where id = v_file.id;
    raise exception 'assertion failed: a raw DELETE of a legal_hold=true row must be blocked with no actor context, but it succeeded';
  exception when others then
    if sqlerrm !~ 'document_legal_hold_blocks_deletion' then raise; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000002001', 'role', 'authenticated')::text, true);
  begin
    delete from app.files where id = v_file.id;
    raise exception 'assertion failed: a raw DELETE of a legal_hold=true row must be blocked for the uploader themselves, but it succeeded';
  exception when others then
    if sqlerrm !~ 'document_legal_hold_blocks_deletion' then raise; end if;
  end;
  perform set_config('request.jwt.claims', 'null', true);

  -- Supreme Admin's own RPD-022 absolute-CRUD exception still works (best-effort
  -- evidence, not a preventive control -- the guard's own disclosed design).
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000002005', 'role', 'authenticated')::text, true);
  delete from app.files where id = v_file.id;
  if exists (select 1 from app.files where id = v_file.id) then
    raise exception 'assertion failed: expected Supreme Admin''s RPD-022 override to actually delete the legally-held row';
  end if;
  perform set_config('request.jwt.claims', 'null', true);

  select * into v_audit from app.audit_logs where resource_type = 'app.files' and resource_id = v_file.id and action = 'delete_legally_held_file';
  if v_audit.id is null then
    raise exception 'assertion failed: expected an app.audit_logs row for the Supreme Admin RPD-022 override delete';
  end if;
end;
$$;

\echo '>> HDN-377 (Storage and Signed URL Audit) regression: the two legal-hold mechanisms are now bridged -- a generic (IAE-031) app.request_legal_hold on scope app.files blocks app.request_file_deletion, and a PLT-128-native file hold is visible to app._is_under_legal_hold (consulted by app.request_retention_archive''s own dry-run classification)'
do $$
declare
  v_tenant_id uuid;
  v_ret_role uuid;
  v_ret_draft app.role_versions;
  v_file_a app.files;
  v_file_b app.files;
  v_archive app.retention_archive_requests;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');

  -- 00000000-0000-0000-0000-000000002004 is the tenant_admin fixture actor -- grant
  -- them a real RET:Configure role too, mirroring IAE-031's own established
  -- data-retention-archival.sql fixture shape (a bare tenant_admin membership does
  -- not itself carry RET:Configure).
  v_ret_role := (app.create_role(v_tenant_id, 'AcmeDoc RET Configure', 'HDN-377 bridge regression fixture', 'tester')).id;
  v_ret_draft := app.create_role_version(v_ret_role, 'tester');
  perform app.set_role_version_permissions(v_ret_draft.id, array(select id from app.permissions where resource_module_code = 'RET' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_ret_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_ret_role and status = 'published'), '00000000-0000-0000-0000-000000002004', '00000000-0000-0000-0000-000000002005', 'supreme admin');

  -- Direction A: a generic (IAE-031) hold placed on a file must block PLT-128's own deletion RPC.
  v_file_a := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hdn377-bridge-a.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-hdn377-bridge-a', '00000000-0000-0000-0000-000000002001', 'uploader');
  perform app.request_legal_hold(v_tenant_id, 'operational', 'app.files', v_file_a.id, 'HDN-377 bridge regression', '00000000-0000-0000-0000-000000002004', 'tenant admin');
  begin
    perform app.request_file_deletion(v_file_a.id, 'attempted deletion under a generic hold', '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected document_legal_hold_blocks_deletion for a file under a generic (app.legal_holds) hold, deletion succeeded instead';
  exception
    when others then
      if sqlerrm !~ 'document_legal_hold_blocks_deletion' then raise; end if;
  end;

  -- Direction B: a PLT-128-native hold must be visible to the generic retention-archive dry-run classification.
  v_file_b := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hdn377-bridge-b.pdf', 'application/pdf', 1000, null, true, 'HDN-377 bridge regression', '{}', null, 'idem-hdn377-bridge-b', '00000000-0000-0000-0000-000000002001', 'uploader');
  v_archive := app.request_retention_archive(v_tenant_id, 'operational', 'app.files', v_file_b.id, now() - interval '10 years', true, '00000000-0000-0000-0000-000000002004', 'tenant admin');
  if v_archive.status <> 'blocked_legal_hold' or not v_archive.legal_hold_blocking then
    raise exception 'assertion failed: expected a file-native legal_hold=true to be visible to app.request_retention_archive''s own dry-run classification (status=blocked_legal_hold), got status=% legal_hold_blocking=%', v_archive.status, v_archive.legal_hold_blocking;
  end if;
end;
$$;

\echo '>> HDN-377 Tier C regression: a raw UPDATE setting deleted_at on a legally-held file (native OR generic hold) is blocked at the schema level too, not just the physical DELETE path -- the Tier C attack-surface lens live-forced this gap in the first round''s own trigger'
do $$
declare
  v_tenant_id uuid;
  v_file_native app.files;
  v_file_generic app.files;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');

  -- Native hold.
  v_file_native := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hdn377-tierc-softdel-native.pdf', 'application/pdf', 1000, null, true, 'litigation hold', '{}', null, 'idem-hdn377-tierc-softdel-native', '00000000-0000-0000-0000-000000002001', 'uploader');
  perform set_config('request.jwt.claims', 'null', true);
  begin
    update app.files set deleted_at = now(), lifecycle_status = 'deleted' where id = v_file_native.id;
    raise exception 'assertion failed: expected a raw soft-delete UPDATE of a natively-held file to be blocked, but it succeeded';
  exception when others then
    if sqlerrm !~ 'document_legal_hold_blocks_deletion' then raise; end if;
  end;

  -- Generic (IAE-031) hold, the exact gap the Tier C attack-surface lens found.
  v_file_generic := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hdn377-tierc-softdel-generic.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-hdn377-tierc-softdel-generic', '00000000-0000-0000-0000-000000002001', 'uploader');
  perform app.request_legal_hold(v_tenant_id, 'operational', 'app.files', v_file_generic.id, 'HDN-377 Tier C regression', '00000000-0000-0000-0000-000000002004', 'tenant admin');
  begin
    update app.files set deleted_at = now(), lifecycle_status = 'deleted' where id = v_file_generic.id;
    raise exception 'assertion failed: expected a raw soft-delete UPDATE of a generically-held file to be blocked, but it succeeded -- this is the exact gap the first round''s own trigger missed';
  exception when others then
    if sqlerrm !~ 'document_legal_hold_blocks_deletion' then raise; end if;
  end;

  -- An ordinary, unrelated UPDATE (not touching deleted_at) on the same held file
  -- must still succeed -- the guard is scoped to the deletion transition only.
  update app.files set original_filename = 'renamed-while-held.pdf' where id = v_file_generic.id;
  if (select original_filename from app.files where id = v_file_generic.id) <> 'renamed-while-held.pdf' then
    raise exception 'assertion failed: expected an ordinary, non-deletion UPDATE on a held file to succeed unimpeded';
  end if;
end;
$$;

\echo '>> HDN-377 Tier C regression: app.request_legal_hold normalizes scope_record_table (case/whitespace) so a variant still matches a real hold, and loudly rejects a non-schema-qualified value instead of silently creating a non-protecting hold -- the Tier C attack-surface lens live-forced the prior silent-no-op'
do $$
declare
  v_tenant_id uuid;
  v_file_mixed_case app.files;
  v_file_whitespace app.files;
  v_hold app.legal_holds;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');

  v_file_mixed_case := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hdn377-tierc-scope-case.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-hdn377-tierc-scope-case', '00000000-0000-0000-0000-000000002001', 'uploader');
  v_hold := app.request_legal_hold(v_tenant_id, 'operational', 'App.Files', v_file_mixed_case.id, 'HDN-377 Tier C regression -- mixed case', '00000000-0000-0000-0000-000000002004', 'tenant admin');
  if v_hold.scope_record_table <> 'app.files' then
    raise exception 'assertion failed: expected scope_record_table to be normalized to lowercase, got %', v_hold.scope_record_table;
  end if;
  begin
    perform app.request_file_deletion(v_file_mixed_case.id, 'attempted deletion under a mixed-case-scoped hold', '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected a mixed-case scope_record_table (App.Files) to still match and block deletion, but it succeeded';
  exception when others then
    if sqlerrm !~ 'document_legal_hold_blocks_deletion' then raise; end if;
  end;

  v_file_whitespace := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hdn377-tierc-scope-ws.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-hdn377-tierc-scope-ws', '00000000-0000-0000-0000-000000002001', 'uploader');
  perform app.request_legal_hold(v_tenant_id, 'operational', '  app.files  ', v_file_whitespace.id, 'HDN-377 Tier C regression -- whitespace', '00000000-0000-0000-0000-000000002004', 'tenant admin');
  begin
    perform app.request_file_deletion(v_file_whitespace.id, 'attempted deletion under a whitespace-padded-scoped hold', '00000000-0000-0000-0000-000000002001', 'uploader');
    raise exception 'assertion failed: expected a whitespace-padded scope_record_table to still match and block deletion, but it succeeded';
  exception when others then
    if sqlerrm !~ 'document_legal_hold_blocks_deletion' then raise; end if;
  end;

  begin
    perform app.request_legal_hold(v_tenant_id, 'operational', 'files', gen_random_uuid(), 'HDN-377 Tier C regression -- missing schema prefix', '00000000-0000-0000-0000-000000002004', 'tenant admin');
    raise exception 'assertion failed: expected a non-schema-qualified scope_record_table (files) to be loudly rejected, not silently accepted';
  exception when others then
    if sqlerrm !~ 'legal_hold_scope_table_not_qualified' then raise; end if;
  end;
end;
$$;

\echo '>> ISS-2026-223 closure: a legal hold records WHO placed it, and lifting one requires authority at least as high -- so a tenant administrator can lift their own organisation''s hold but not one the platform placed on them.'
do $$
declare
  v_tenant_id uuid;
  v_file app.files;
  v_after app.files;
  v_raised boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmedoc');

  -- PROPERTY 1 -- placing a hold is unchanged, and now records its provenance.
  v_file := app.initiate_file_upload(v_tenant_id, 'contract', 'shipment', gen_random_uuid(), 'hold-prov.pdf', 'application/pdf', 1000, null, false, null, '{}', null, 'idem-hold-prov-1', '00000000-0000-0000-0000-000000002001', 'uploader');
  v_after := app.set_file_legal_hold(v_file.id, true, 'platform litigation order', '00000000-0000-0000-0000-000000002005', 'supreme admin');
  if v_after.legal_hold_placed_authority is distinct from 'supreme_admin' then
    raise exception 'assertion failed: a Supreme-Admin-placed hold recorded authority % instead of supreme_admin', v_after.legal_hold_placed_authority;
  end if;
  if v_after.legal_hold_placed_by_auth_user_id is distinct from '00000000-0000-0000-0000-000000002005' then
    raise exception 'assertion failed: the placing identity was not recorded on the held row';
  end if;

  -- PROPERTY 2 -- THE FIX. The tenant's own admin may NOT lift a hold the platform placed.
  -- This is the exact bypass ISS-2026-223 live-forced: is_support_grant_authority admitted any
  -- tenant_admin, so before this fix the call below succeeded.
  v_raised := false;
  begin
    perform app.set_file_legal_hold(v_file.id, false, null, '00000000-0000-0000-0000-000000002004', 'tenant admin');
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'document_legal_hold_clear_requires_higher_authority' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: a tenant_admin lifted a Supreme-Admin-placed legal hold -- ISS-2026-223 has regressed and the hold cannot constrain the party it exists to constrain';
  end if;

  -- PROPERTY 3 -- the hold really is still in force after the refused attempt, i.e. the refusal
  -- is not merely cosmetic and left the row untouched.
  select * into v_after from app.files where id = v_file.id;
  if not v_after.legal_hold then
    raise exception 'assertion failed: the refused lift still cleared the hold';
  end if;

  -- PROPERTY 4 -- equal-or-higher authority CAN lift it, so this is a narrowing and not a lockout.
  v_after := app.set_file_legal_hold(v_file.id, false, null, '00000000-0000-0000-0000-000000002005', 'supreme admin');
  if v_after.legal_hold then
    raise exception 'assertion failed: Supreme Admin could not lift a Supreme-Admin-placed hold';
  end if;
  if v_after.legal_hold_placed_authority is not null or v_after.legal_hold_placed_by_auth_user_id is not null then
    raise exception 'assertion failed: provenance was not cleared when the hold was lifted';
  end if;

  -- PROPERTY 5 -- the legitimate tenant flow is untouched: a tenant admin places a hold on their
  -- own organisation's file and lifts it again. Equal rank, so it passes. This is the same shape
  -- the pre-existing block above already relies on, asserted here explicitly so a future change
  -- that over-tightens the rule fails loudly instead of quietly breaking a customer workflow.
  v_after := app.set_file_legal_hold(v_file.id, true, 'our own counsel advised a hold', '00000000-0000-0000-0000-000000002004', 'tenant admin');
  if v_after.legal_hold_placed_authority is distinct from 'tenant_admin' then
    raise exception 'assertion failed: a tenant_admin-placed hold recorded authority %', v_after.legal_hold_placed_authority;
  end if;
  v_after := app.set_file_legal_hold(v_file.id, false, null, '00000000-0000-0000-0000-000000002004', 'tenant admin');
  if v_after.legal_hold then
    raise exception 'assertion failed: a tenant_admin could not lift their OWN tenant_admin-placed hold -- the rule has over-tightened into a lockout';
  end if;

  -- PROPERTY 6 -- an actor with no authority at all is still refused outright, with the original
  -- error, so the new branch did not accidentally become the only gate.
  v_raised := false;
  begin
    perform app.set_file_legal_hold(v_file.id, true, 'nope', '00000000-0000-0000-0000-000000002001', 'uploader');
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'document_legal_hold_unauthorized' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: an ordinary org_user set a legal hold';
  end if;

  raise notice 'ISS-2026-223 closure: hold provenance is recorded; a tenant_admin cannot lift a platform-placed hold but can lift their own; equal-or-higher authority still can; an unauthorised actor still cannot place one';
end;
$$;

\echo '>> PLT-128 (Document and File Engine) test suite passed'
