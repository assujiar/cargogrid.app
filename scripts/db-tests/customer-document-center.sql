-- Real, executable test evidence for CPL-308 (CG-S13-CPL-010, Prompt 308,
-- "Document Center") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Structural convention mirrors
-- scripts/db-tests/customer-quote-requests.sql (CPL-302, the attachment
-- pipeline) and scripts/db-tests/customer-epod-access.sql (CPL-307, the ePOD
-- capture pipeline) -- this file builds BOTH real pipelines in one tenant so
-- app.list_customer_documents/app.get_customer_document have real,
-- heterogeneous cross-source data to compose.
--
-- UUID range 00000000-0000-0000-0000-000000315xxx (tenant cdc1) /
-- ...316xxx (tenant cdc2) -- grep-verified unclaimed (right after CPL-307's
-- own ...313xxx/...314xxx range).
--
-- Covers, live: (1) list composes both real sources (quote_request, epod)
-- for an in-scope account/co-worker, cross-account and cross-tenant
-- isolated, deny-by-default; (2) list surfaces a pending (not-yet-scanned)
-- attachment's real malware_scan_status honestly, never hidden or defaulted
-- to clean; (3) source_module filter narrows to exactly one real arm;
-- invoice/ticket are recognized but return zero rows, never an error; an
-- unrecognized value raises invalid_source_module; (4) account_id and
-- shipment_order_id filters narrow correctly, including the "shipment_order_
-- id has no meaning on the quote_request arm" exclusion; (5) date-range
-- filter narrows correctly, and an inverted range raises invalid_date_range;
-- (6) keyset pagination (limit=1) and a half-supplied cursor; (7) get_
-- customer_document: a clean file downloads, logs a granted app.
-- file_access_logs row, and returns the same projection the list uses; a
-- pending file is a normal SUCCESSFUL return (never a raised exception --
-- design decision 5, since raising would roll back its own audit insert)
-- carrying the real pending status, with a durably-committed denied log row
-- (the document_not_downloadable refusal itself is enforced one layer up, at
-- the TypeScript service boundary, tested separately in server/mutations/
-- customer-document.test.ts); an out-of-scope caller and a genuinely
-- nonexistent id both raise the
-- IDENTICAL document_not_found; a shipment_order-typed file that exists but
-- is NOT referenced by any completed ePOD capture also raises document_not_
-- found (design decision 4 -- never a back door into a source this
-- capability does not compose); (8) actor-identity session cross-check;
-- (9) raw-function grant defense in depth.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cdc1 (staff with OPS:Create/Edit/Assign/View + COM:Create/Edit/Approve + CPT:Create, a tenant_admin; accounts Alpha/Beta; alpha-admin+alpha-member active on Alpha, beta-admin active on Beta, impersonator with zero relationship); a second, otherwise-empty tenant cdc2 (t2-admin on account T2) for cross-tenant isolation; a real Commercial -> Operations pipeline for Account Alpha through a delivered shipment with a completed ePOD capture (1 clean signature + 1 clean photo); two Account Alpha quote requests, one with a clean attachment and one with a still-pending (not-yet-scanned) attachment; one Account Beta quote request with a clean attachment; one extra shipment_order-typed file NOT referenced by any capture (negative fixture for design decision 4)'
create temporary table cdc_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000315001';
  v_supreme uuid := '00000000-0000-0000-0000-000000315003';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000315011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000315020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000315050';
  v_staff2 uuid := '00000000-0000-0000-0000-000000316001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000316010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_vendor app.master_records;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_quotation app.quotations;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment app.shipment_orders;
  v_qr_draft app.config_versions;
  v_pod_draft app.config_versions;
  v_req_clean app.customer_portal_quote_requests;
  v_req_pending app.customer_portal_quote_requests;
  v_req_beta app.customer_portal_quote_requests;
  v_file_clean app.files;
  v_file_pending app.files;
  v_file_beta app.files;
  v_capture app.epod_captures;
  v_signature app.files;
  v_photo app.files;
  v_unreferenced app.files;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@cdc1.test'),
    (v_supreme, 'supreme@cdc1.test'),
    (v_alpha_admin, 'alpha-admin@cdc1.test'),
    (v_alpha_member, 'alpha-member@cdc1.test'),
    (v_beta_admin, 'beta-admin@cdc1.test'),
    (v_impersonator, 'impersonator@cdc1.test'),
    (v_staff2, 'staff@cdc2.test'),
    (v_t2_admin, 't2-admin@cdc2.test');

  -- app.register_document_type is Supreme-Admin-gated (unconditionally, even
  -- for an already-registered code) -- mirrors CPL-307's own db-test fixture
  -- exactly, rather than assuming an earlier-alphabetical file has already
  -- registered 'epod' by the time this file runs.
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cdc1', 'Customer Document Center Tenant One', 'idem-cdc1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cdc1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CDC1-CO', 'Cdc1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CDC1-CO');

  perform app.provision_tenant('cdc2', 'Customer Document Center Tenant Two', 'idem-cdc2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cdc2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CDC2-CO', 'Cdc2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@cdc1.test', 'Cdc1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cdc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@cdc2.test', 'Cdc2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cdc2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant1, 'Document Center Portal Staff', 'OPS Create/Edit/Assign/View + COM Create/Edit/Approve + CPT Create', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'OPS' and action in ('View', 'Create', 'Edit', 'Assign')) or (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve')) or (resource_module_code = 'CPT' and action = 'Create')),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_staff, v_staff, 'tester');
  perform app.grant_principal_membership(v_staff, 'tenant_admin', v_tenant1, null, 'tester');

  v_role2 := (app.create_role(v_tenant2, 'Document Center Portal Admin', 'CPT Create', 'tester')).id;
  v_draft2 := app.create_role_version(v_role2, 'tester');
  perform app.set_role_version_permissions(v_draft2.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_role2 and status = 'published'), v_staff2, v_staff2, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cdc1 Account Alpha', 'cdc1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cdc1 Account Beta', 'cdc1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cdc2 Account T2', 'cdc2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'cdc1-staff');
  perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, v_alpha_member, 'member', v_alpha_admin, 'alpha-admin');
  perform app.accept_customer_portal_invite((select id from app.customer_portal_account_memberships where account_id = v_account_alpha and auth_user_id = v_alpha_member), 1, v_alpha_member);
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'cdc1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'cdc2-staff');

  -- v_impersonator deliberately holds ZERO customer-portal grant of any kind.

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-CDC-1', 'Cdc1 Trucking Vendor', '[]'::jsonb, '{}'::jsonb, v_staff, 'cdc1-staff');

  -- --- Quote request attachments (mirrors CPL-302's own db-test pipeline) ---

  v_qr_draft := app.create_config_draft('document:quote_request_attachment', v_tenant1, 'tenant', null, v_staff, 'cdc1-staff');
  perform app.set_config_items(v_qr_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_staff, 'cdc1-staff');
  perform app.publish_document_type_definition(v_qr_draft.id, v_staff, now(), 'cdc1-staff');

  select * into v_req_clean from app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'alpha with clean attachment', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-alpha-clean', v_alpha_admin, 'alpha-admin');
  select * into v_file_clean from app.initiate_file_upload(
    v_tenant1, 'quote_request_attachment', 'customer_portal_quote_request', v_req_clean.id,
    'cargo-photo-clean.jpg', 'image/jpeg', 204800, null, false, null, '{}', null, 'upload-alpha-clean-1', v_alpha_admin, 'alpha-admin'
  );
  perform app.record_file_scan_result(v_file_clean.id, 'clean', 'test-scanner-ref', v_staff, 'cdc1-staff');

  select * into v_req_pending from app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'alpha with pending attachment', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-alpha-pending', v_alpha_admin, 'alpha-admin');
  select * into v_file_pending from app.initiate_file_upload(
    v_tenant1, 'quote_request_attachment', 'customer_portal_quote_request', v_req_pending.id,
    'cargo-photo-pending.jpg', 'image/jpeg', 102400, null, false, null, '{}', null, 'upload-alpha-pending-1', v_alpha_admin, 'alpha-admin'
  );
  -- Deliberately left at malware_scan_status='pending' (app.initiate_file_upload's own default) -- never scanned in this fixture.

  select * into v_req_beta from app.create_customer_quote_request_draft(v_tenant1, v_account_beta, 'beta with clean attachment', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-beta-clean', v_beta_admin, 'beta-admin');
  select * into v_file_beta from app.initiate_file_upload(
    v_tenant1, 'quote_request_attachment', 'customer_portal_quote_request', v_req_beta.id,
    'cargo-photo-beta.jpg', 'image/jpeg', 51200, null, false, null, '{}', null, 'upload-beta-clean-1', v_beta_admin, 'beta-admin'
  );
  perform app.record_file_scan_result(v_file_beta.id, 'clean', 'test-scanner-ref', v_staff, 'cdc1-staff');

  -- --- ePOD capture pipeline (mirrors CPL-307's own db-test pipeline) ---

  perform app.capture_lead(v_tenant1, 'manual', null, 'Cdc1 Alpha Customer Ltd', 'Jane Requester', 'jane@cdc1alpha.test', '0811', v_staff, v_company1, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cdc1alpha.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cdc1alpha.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Cdc1 Alpha Customer Ltd', 'Cdc1 Alpha', '01.111.222.9-000.000',
    jsonb_build_object('line1', 'Jl. Test 1', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Cdc1 Alpha Customer Ltd';
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Cdc1 alpha document center lane',
    jsonb_build_object('service_type', 'land_freight', 'origin', 'Jakarta', 'destination', 'Bandung'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_contact app.contacts;
    v_raw_token text;
  begin
    select * into v_contact from app.create_contact(v_tenant1, 'Cdc1 Alpha Contact', 'Ops Manager', 'contact@cdc1alpha.test', '0813', v_staff, v_company1, v_staff, 'tester');
    select * into v_quotation from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_quotation from app.add_quotation_line(v_quotation.id, v_quotation.record_version, 'service', 'Land freight base charge', null, 1, 6000000, 0, 0, v_staff, 'cdc1-staff');
    select * into v_quotation from app.submit_quotation(v_quotation.id, v_quotation.record_version, v_staff, 'cdc1-staff');
    select raw_token into v_raw_token from app.send_quotation_for_acceptance(v_quotation.id, v_contact.id, 'email', v_staff, 'cdc1-staff');
    perform app.record_quotation_customer_decision(v_raw_token, 'accepted', 'Jane Requester', 'Ops Manager', 'contact@cdc1alpha.test', null, null, null);
    select * into v_quotation from app.quotations where id = v_quotation.id;
    perform app.convert_quotation_to_account(v_quotation.id, v_account_alpha, null, v_staff, 'cdc1-staff');
  end;
  select * into v_handoff from app.prepare_job_order_handoff(v_quotation.id, v_staff, 'cdc1-staff');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_staff, 'cdc1-staff');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_staff, 'cdc1-staff');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-cdc1-alpha-delivered', jsonb_build_object('name', 'Alpha Consignee'), null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() - interval '2 days', now() - interval '1 hours', 2000, 2000, 40, 2000, 2000, 40, null, v_staff, 'cdc1-staff'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_staff, 'cdc1-staff');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-cdc1-alpha-planned', v_staff, 'cdc1-staff');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-cdc1-alpha-assigned', v_staff, 'cdc1-staff');
  perform app.assign_resource(v_shipment.id, 'vendor', v_vendor.id, v_staff, 'cdc1-staff');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'dispatched', v_shipment.record_version, null, null, 'idem-cdc1-alpha-dispatched', v_staff, 'cdc1-staff');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'in_transit', v_shipment.record_version, null, null, 'idem-cdc1-alpha-intransit', v_staff, 'cdc1-staff');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, 'physical delivery confirmed', 'idem-cdc1-alpha-delivered-t', v_staff, 'cdc1-staff');

  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', v_supreme, 'supreme');
  v_pod_draft := app.create_config_draft('document:epod', v_tenant1, 'tenant', null, v_staff, 'cdc1-staff');
  perform app.set_config_items(v_pod_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg', 'image/png')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), v_staff, 'cdc1-staff');
  perform app.publish_document_type_definition(v_pod_draft.id, v_staff, now(), 'cdc1-staff');

  v_capture := app.start_epod_capture(v_tenant1, v_shipment.id, null, 'idem-cdc1-alpha-cap', v_staff, 'cdc1-staff');
  select * into v_signature from app.initiate_file_upload(v_tenant1, 'epod', 'shipment_order', v_shipment.id, 'signature-alpha.png', 'image/png', 20480, null, false, null, '{}'::uuid[], null, 'idem-cdc1-alpha-sig', v_staff, 'cdc1-staff');
  select * into v_photo from app.initiate_file_upload(v_tenant1, 'epod', 'shipment_order', v_shipment.id, 'photo-alpha-1.jpg', 'image/jpeg', 102400, null, false, null, '{}'::uuid[], null, 'idem-cdc1-alpha-photo', v_staff, 'cdc1-staff');
  perform app.record_file_scan_result(v_signature.id, 'clean', 'test-scanner-ref', v_staff, 'cdc1-staff');
  perform app.record_file_scan_result(v_photo.id, 'clean', 'test-scanner-ref', v_staff, 'cdc1-staff');
  v_capture := app.set_epod_evidence(v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_signature.id, array[v_photo.id], jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.845599, -6.208763)), now(), v_staff, 'cdc1-staff');
  v_capture := app.submit_epod_capture(v_capture.id, v_capture.record_version, v_staff, 'cdc1-staff');
  v_capture := app.review_epod_capture(v_capture.id, 'approved', 'looks good', v_capture.record_version, v_staff, 'cdc1-staff');
  select * into v_shipment from app.shipment_orders so where so.id = v_shipment.id;
  v_capture := app.complete_epod_capture(v_capture.id, v_capture.record_version, v_shipment.record_version, 'idem-cdc1-alpha-complete', v_staff, 'cdc1-staff');
  if v_capture.status <> 'completed' then
    raise exception 'assertion failed: expected the ePOD capture fixture to reach completed, got %', v_capture.status;
  end if;

  -- Negative fixture for design decision 4: a REAL app.files row under
  -- record_type='shipment_order'/record_id=this exact shipment, scanned
  -- clean, but NEVER referenced by any app.epod_captures row -- must be
  -- treated as document_not_found by app.get_customer_document and must
  -- never appear in app.list_customer_documents.
  select * into v_unreferenced from app.initiate_file_upload(v_tenant1, 'epod', 'shipment_order', v_shipment.id, 'unrelated-ops-note.pdf', 'application/pdf', 10240, null, false, null, '{}'::uuid[], null, 'idem-cdc1-alpha-unreferenced', v_staff, 'cdc1-staff');
  perform app.record_file_scan_result(v_unreferenced.id, 'clean', 'test-scanner-ref', v_staff, 'cdc1-staff');

  insert into cdc_test_state (key, value) values
    ('tenant1_id', v_tenant1::text), ('tenant2_id', v_tenant2::text),
    ('account_alpha_id', v_account_alpha::text), ('account_beta_id', v_account_beta::text),
    ('shipment_id', v_shipment.id::text),
    ('req_clean_id', v_req_clean.id::text), ('req_pending_id', v_req_pending.id::text), ('req_beta_id', v_req_beta.id::text),
    ('file_clean_id', v_file_clean.id::text), ('file_pending_id', v_file_pending.id::text), ('file_beta_id', v_file_beta.id::text),
    ('signature_file_id', v_signature.id::text), ('photo_file_id', v_photo.id::text),
    ('unreferenced_file_id', v_unreferenced.id::text);
end;
$$;

\echo '>> app.list_customer_documents: composes both real sources for alpha-admin (4 docs: 2 quote_request + 2 epod), excludes Beta''s own document and the unreferenced shipment_order file entirely'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_file_beta_id uuid := (select value::uuid from cdc_test_state where key = 'file_beta_id');
  v_unreferenced_id uuid := (select value::uuid from cdc_test_state where key = 'unreferenced_file_id');
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin);
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 documents (2 quote_request + 2 epod) for alpha-admin, got %', v_count;
  end if;

  if exists (select 1 from app.list_customer_documents(v_tenant1, v_alpha_admin) d where d.document_id = v_file_beta_id) then
    raise exception 'assertion failed: expected Beta''s own document to be excluded from alpha-admin''s own list';
  end if;
  if exists (select 1 from app.list_customer_documents(v_tenant1, v_alpha_admin) d where d.document_id = v_unreferenced_id) then
    raise exception 'assertion failed: expected the unreferenced shipment_order file (design decision 4 negative fixture) to NEVER appear in the list';
  end if;
end;
$$;

\echo '>> app.list_customer_documents: a co-worker on the same account sees the same documents (account-level scope); beta-admin sees only Beta''s own 1 document; impersonator and a cross-tenant identity both see 0'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_member uuid := '00000000-0000-0000-0000-000000315011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000315020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000315050';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000316010';
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_member);
  if v_count <> 4 then
    raise exception 'assertion failed: expected alpha-member (co-worker) to see the same 4 documents, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_beta_admin);
  if v_count <> 1 then
    raise exception 'assertion failed: expected beta-admin to see exactly 1 document (their own), got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_impersonator);
  if v_count <> 0 then
    raise exception 'assertion failed: expected a zero-scope impersonator to see 0 documents, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_t2_admin);
  if v_count <> 0 then
    raise exception 'assertion failed: expected a cross-tenant identity (t2-admin) probing cdc1''s own tenant id to see 0 documents, got %', v_count;
  end if;
end;
$$;

\echo '>> app.list_customer_documents: malware_scan_status is surfaced HONESTLY per document -- the pending attachment appears with status=pending, never hidden or defaulted to clean'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_file_pending_id uuid := (select value::uuid from cdc_test_state where key = 'file_pending_id');
  v_status text;
begin
  select d.malware_scan_status into v_status from app.list_customer_documents(v_tenant1, v_alpha_admin) d where d.document_id = v_file_pending_id;
  if v_status is distinct from 'pending' then
    raise exception 'assertion failed: expected the pending attachment''s real malware_scan_status=pending on the list, got %', v_status;
  end if;
end;
$$;

\echo '>> app.list_customer_documents: p_source_module narrows to exactly one real arm; invoice/ticket are recognized but return 0 rows; an unrecognized value raises invalid_source_module'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_count integer;
  v_msg text;
begin
  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, 'quote_request');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 quote_request documents, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, 'epod');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 epod documents, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, 'invoice');
  if v_count <> 0 then
    raise exception 'assertion failed: expected invoice (recognized, not yet backed) to return 0 rows, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, 'ticket');
  if v_count <> 0 then
    raise exception 'assertion failed: expected ticket (recognized, not yet backed) to return 0 rows, got %', v_count;
  end if;

  begin
    perform app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, 'not_a_real_source');
    raise exception 'assertion failed: expected invalid_source_module for an unrecognized p_source_module';
  exception
    when invalid_parameter_value then v_msg := sqlerrm;
  end;
  if v_msg not like 'invalid_source_module%' then
    raise exception 'assertion failed: expected invalid_source_module, got %', v_msg;
  end if;
end;
$$;

\echo '>> app.list_customer_documents: account_id and shipment_order_id filters narrow correctly; p_shipment_order_id excludes every quote_request document (design decision 2)'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_account_alpha uuid := (select value::uuid from cdc_test_state where key = 'account_alpha_id');
  v_account_beta uuid := (select value::uuid from cdc_test_state where key = 'account_beta_id');
  v_shipment_id uuid := (select value::uuid from cdc_test_state where key = 'shipment_id');
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, v_account_alpha);
  if v_count <> 4 then
    raise exception 'assertion failed: expected 4 documents filtered to account_alpha, got %', v_count;
  end if;

  -- alpha-admin has no scope on account_beta at all -- deny-by-default, not an error.
  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, v_account_beta);
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 documents for alpha-admin filtered to an out-of-scope account_beta, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, null, v_shipment_id);
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly the 2 epod documents when filtered by shipment_order_id, got %', v_count;
  end if;
end;
$$;

\echo '>> app.list_customer_documents: date-range filter narrows correctly; an inverted range raises invalid_date_range; keyset pagination (limit=1) visits every row exactly once; a half-supplied cursor raises invalid_cursor'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_count integer;
  v_msg text;
  v_row record;
  v_cursor_created_at timestamptz;
  v_cursor_id uuid;
  v_visited integer := 0;
begin
  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, null, now() + interval '1 day');
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 documents for a date_from strictly in the future, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, null, now() - interval '1 day', now() + interval '1 day');
  if v_count <> 4 then
    raise exception 'assertion failed: expected all 4 documents inside a wide date range, got %', v_count;
  end if;

  begin
    perform app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, null, now(), now() - interval '1 day');
    raise exception 'assertion failed: expected invalid_date_range for an inverted range';
  exception
    when invalid_parameter_value then v_msg := sqlerrm;
  end;
  if v_msg not like 'invalid_date_range%' then
    raise exception 'assertion failed: expected invalid_date_range, got %', v_msg;
  end if;

  <<page_loop>>
  loop
    select * into v_row from app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, null, null, null, v_cursor_created_at, v_cursor_id, 1) limit 1;
    exit page_loop when not found;
    v_visited := v_visited + 1;
    v_cursor_created_at := v_row.created_at;
    v_cursor_id := v_row.document_id;
    exit page_loop when v_visited > 10;
  end loop;
  if v_visited <> 4 then
    raise exception 'assertion failed: expected keyset pagination at limit=1 to visit exactly 4 rows total, visited %', v_visited;
  end if;

  begin
    -- Half-supplied means p_cursor_id present WITHOUT p_cursor_created_at
    -- (the function's own validated shape -- the reverse combination,
    -- p_cursor_created_at alone, is harmlessly ignored by the WHERE clause's
    -- own `p_cursor_id is null or (...)` short-circuit, mirroring every
    -- other Phase 8 list RPC's identical asymmetric convention).
    perform app.list_customer_documents(v_tenant1, v_alpha_admin, null, null, null, null, null, null, gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor for a half-supplied cursor';
  exception
    when invalid_parameter_value then v_msg := sqlerrm;
  end;
  if v_msg not like 'invalid_cursor%' then
    raise exception 'assertion failed: expected invalid_cursor, got %', v_msg;
  end if;
end;
$$;

\echo '>> app.get_customer_document: a clean file downloads -- returns the same projection the list uses and writes a granted app.file_access_logs row'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_file_clean_id uuid := (select value::uuid from cdc_test_state where key = 'file_clean_id');
  v_req_clean_id uuid := (select value::uuid from cdc_test_state where key = 'req_clean_id');
  v_row record;
  v_log_count integer;
begin
  select * into v_row from app.get_customer_document(v_tenant1, v_alpha_admin, v_file_clean_id);
  if v_row.document_id <> v_file_clean_id or v_row.source_module <> 'quote_request' or v_row.source_entity_id <> v_req_clean_id
    or v_row.document_type <> 'quote_request_attachment' or v_row.malware_scan_status <> 'clean' or v_row.original_filename <> 'cargo-photo-clean.jpg' then
    raise exception 'assertion failed: expected the clean attachment''s real projection, got %', v_row;
  end if;

  -- Tier C fix (spec-compliance Finding 2, batch review of CPL-305..309):
  -- access_type='metadata_view', not 'signed_url_issued' -- no signed URL is
  -- ever fabricated by app.get_customer_document (mirrors CPL-307's fix).
  select count(*) into v_log_count from app.file_access_logs where file_id = v_file_clean_id and accessed_by_auth_user_id = v_alpha_admin and result = 'granted' and access_type = 'metadata_view';
  if v_log_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 granted app.file_access_logs row, got %', v_log_count;
  end if;
end;
$$;

\echo '>> app.get_customer_document: an epod signature file also downloads correctly, tagged epod_signature'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_signature_id uuid := (select value::uuid from cdc_test_state where key = 'signature_file_id');
  v_shipment_id uuid := (select value::uuid from cdc_test_state where key = 'shipment_id');
  v_row record;
begin
  select * into v_row from app.get_customer_document(v_tenant1, v_alpha_admin, v_signature_id);
  if v_row.source_module <> 'epod' or v_row.source_entity_id <> v_shipment_id or v_row.document_type <> 'epod_signature' then
    raise exception 'assertion failed: expected the signature file to be tagged epod/epod_signature against the real shipment id, got %', v_row;
  end if;
end;
$$;

\echo '>> app.get_customer_document: a pending (not-yet-scanned) file is a normal, SUCCESSFUL return (never a raised exception, design decision 5 -- raising here would roll back its own audit insert) -- the row honestly carries malware_scan_status=pending, and a real denied app.file_access_logs row is durably written'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_file_pending_id uuid := (select value::uuid from cdc_test_state where key = 'file_pending_id');
  v_row record;
  v_denied_count integer;
begin
  select * into v_row from app.get_customer_document(v_tenant1, v_alpha_admin, v_file_pending_id);
  if v_row.document_id <> v_file_pending_id or v_row.malware_scan_status <> 'pending' then
    raise exception 'assertion failed: expected a normal successful return with the real pending status, got %', v_row;
  end if;

  select count(*) into v_denied_count from app.file_access_logs where file_id = v_file_pending_id and accessed_by_auth_user_id = v_alpha_admin and result = 'denied' and reason = 'document_not_yet_scanned';
  if v_denied_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 durably-committed denied app.file_access_logs row with reason=document_not_yet_scanned, got %', v_denied_count;
  end if;
end;
$$;

\echo '>> app.get_customer_document: anti-enumeration -- a genuinely nonexistent id, an out-of-scope caller on a real Alpha document, AND a real but unreferenced shipment_order file (design decision 4) all raise the IDENTICAL document_not_found'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_beta_admin uuid := '00000000-0000-0000-0000-000000315020';
  v_file_clean_id uuid := (select value::uuid from cdc_test_state where key = 'file_clean_id');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000315010';
  v_unreferenced_id uuid := (select value::uuid from cdc_test_state where key = 'unreferenced_file_id');
  v_msg text;
begin
  begin
    perform app.get_customer_document(v_tenant1, v_beta_admin, gen_random_uuid());
    raise exception 'assertion failed: expected document_not_found for a genuinely nonexistent document id';
  exception
    when no_data_found then v_msg := sqlerrm;
  end;
  if v_msg not like 'document_not_found%' then
    raise exception 'assertion failed: expected document_not_found (nonexistent), got %', v_msg;
  end if;

  begin
    perform app.get_customer_document(v_tenant1, v_beta_admin, v_file_clean_id);
    raise exception 'assertion failed: expected document_not_found for beta-admin probing Alpha''s own document (out-of-scope)';
  exception
    when no_data_found then v_msg := sqlerrm;
  end;
  if v_msg not like 'document_not_found%' then
    raise exception 'assertion failed: expected document_not_found (out-of-scope), got %', v_msg;
  end if;

  begin
    perform app.get_customer_document(v_tenant1, v_alpha_admin, v_unreferenced_id);
    raise exception 'assertion failed: expected document_not_found for a real, in-tenant, scan-clean file that exists but is NOT referenced by any completed ePOD capture (design decision 4) -- even for the identity who otherwise has full scope on this exact shipment';
  exception
    when no_data_found then v_msg := sqlerrm;
  end;
  if v_msg not like 'document_not_found%' then
    raise exception 'assertion failed: expected document_not_found (unreferenced shipment_order file), got %', v_msg;
  end if;
end;
$$;

\echo '>> actor-identity session cross-check on both new RPCs'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_file_clean_id uuid := (select value::uuid from cdc_test_state where key = 'file_clean_id');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000315050", "role": "authenticated"}';

  begin
    perform app.list_customer_documents(v_tenant1, '00000000-0000-0000-0000-000000315010');
    raise exception 'assertion failed: expected actor_identity_mismatch on list_customer_documents';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.get_customer_document(v_tenant1, '00000000-0000-0000-0000-000000315010', v_file_clean_id);
    raise exception 'assertion failed: expected actor_identity_mismatch on get_customer_document';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  reset role;
end;
$$;

\echo '>> a real, live authenticated-role positive-path call: alpha-admin''s own real session sees the same count a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select value from cdc_test_state where key = 'tenant1_id')::uuid;
  v_direct_count integer;
  v_session_count integer;
begin
  select count(*) into v_direct_count from app.list_customer_documents(v_tenant1, '00000000-0000-0000-0000-000000315010');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000315010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_documents(v_tenant1, '00000000-0000-0000-0000-000000315010');
  reset role;

  if v_session_count is distinct from v_direct_count or v_session_count is null then
    raise exception 'assertion failed: expected the real authenticated session to see the SAME count a direct superuser call returns (session %, direct %)', v_session_count, v_direct_count;
  end if;
end;
$$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE; authenticated/service_role hold EXECUTE on both new functions'
do $$
declare
  v_has_priv boolean;
begin
  select has_function_privilege('anon', 'app.list_customer_documents(uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, timestamptz, uuid, integer)', 'EXECUTE') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: anon must NOT hold EXECUTE on app.list_customer_documents';
  end if;
  select has_function_privilege('authenticated', 'app.list_customer_documents(uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, timestamptz, uuid, integer)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on app.list_customer_documents';
  end if;

  select has_function_privilege('anon', 'app.get_customer_document(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: anon must NOT hold EXECUTE on app.get_customer_document';
  end if;
  select has_function_privilege('authenticated', 'app.get_customer_document(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on app.get_customer_document';
  end if;
  select has_function_privilege('service_role', 'app.get_customer_document(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: service_role SHOULD hold EXECUTE on app.get_customer_document';
  end if;
end;
$$;
