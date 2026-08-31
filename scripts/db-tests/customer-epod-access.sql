-- Real, executable test evidence for CPL-307 (CG-S13-CPL-009, Prompt 307,
-- "ePOD Access") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Structural convention mirrors scripts/db-tests/
-- customer-shipment-orders.sql (CPL-304) and scripts/db-tests/customer-
-- shipment-alerts.sql (CPL-306); the shipment -> delivered -> ePOD capture
-- pipeline mirrors scripts/db-tests/operations-epod-capture-review.sql
-- (OPS-177) exactly.
--
-- UUID range 00000000-0000-0000-0000-0000313xxx (tenant cea1) /
-- ...314xxx (tenant cea2) -- grep-verified unclaimed (right after
-- CPL-306's own ...311xxx/...312xxx range).
--
-- Covers, live: (1) anti-enumerating record_not_found -- genuinely
-- nonexistent, same-tenant out-of-scope, AND cross-tenant zero-relationship
-- all collapse to the identical error; (2) not_available for an in-scope
-- shipment with no completed capture; (3) available -- every referenced
-- evidence file independently re-verified clean, customer-safe metadata
-- returned, granted app.file_access_logs rows written, never storage_path;
-- (4) THE LIVE-REPRODUCED QUARANTINE CASE (migration design decision 2(d)/
-- 5): a file directly re-flagged infected after a capture already reached
-- 'completed' (simulating the disclosed RPD-022 Supreme Admin residual-risk
-- correction path) flips the WHOLE capture to quarantined, files withheld
-- entirely, a denied app.file_access_logs row written; (5) actor-identity
-- session cross-check; (6) raw-function grant defense in depth; (7) app.
-- authorize_file_access is never called by app.get_customer_epod (a live
-- catalog check, not a grep on this migration's own source); (8) app.
-- epod_captures/app.files' own pre-existing RLS remains untouched and still
-- denies a customer_user by default.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cea1 (staff with OPS:Create/Edit/Assign/View + COM:Create/Edit/Approve + CPT:Create, a tenant_admin; a Supreme Admin; accounts Alpha/Beta; alpha-admin active on Alpha, beta-admin active on Beta, impersonator with zero relationship); a second, otherwise-empty tenant cea2 (t2-admin on account T2) for cross-tenant isolation; a real Commercial -> Operations pipeline producing (a) one Account Alpha shipment driven all the way to delivered with a completed ePOD capture (1 clean signature + 1 clean photo file), (b) one Account Alpha shipment left at confirmed only (no capture at all), (c) one Account Beta shipment left at confirmed only'
create temporary table cea_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000313001';
  v_supreme uuid := '00000000-0000-0000-0000-000000313003';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000313010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000313020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000313050';
  v_staff2 uuid := '00000000-0000-0000-0000-000000314001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000314010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_vendor app.master_records;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_quotation app.quotations;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment_delivered app.shipment_orders;
  v_shipment_notdelivered app.shipment_orders;
  v_beta_lead app.leads;
  v_beta_prospect app.prospects;
  v_beta_opportunity app.opportunities;
  v_beta_quotation app.quotations;
  v_beta_handoff app.job_order_handoffs;
  v_beta_job_order app.job_orders;
  v_shipment_beta app.shipment_orders;
  v_pod_draft app.config_versions;
  v_capture app.epod_captures;
  v_signature app.files;
  v_photo app.files;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@cea1.test'),
    (v_supreme, 'supreme@cea1.test'),
    (v_alpha_admin, 'alpha-admin@cea1.test'),
    (v_beta_admin, 'beta-admin@cea1.test'),
    (v_impersonator, 'impersonator@cea1.test'),
    (v_staff2, 'staff@cea2.test'),
    (v_t2_admin, 't2-admin@cea2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cea1', 'Customer Epod Access Tenant One', 'idem-cea1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cea1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CEA1-CO', 'Cea1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CEA1-CO');

  perform app.provision_tenant('cea2', 'Customer Epod Access Tenant Two', 'idem-cea2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cea2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CEA2-CO', 'Cea2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@cea1.test', 'Cea1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cea1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@cea2.test', 'Cea2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cea2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant1, 'Epod Portal Staff', 'OPS Create/Edit/Assign/View + COM Create/Edit/Approve + CPT Create', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'OPS' and action in ('View', 'Create', 'Edit', 'Assign')) or (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve')) or (resource_module_code = 'CPT' and action = 'Create')),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_staff, v_staff, 'tester');
  perform app.grant_principal_membership(v_staff, 'tenant_admin', v_tenant1, null, 'tester');

  v_role2 := (app.create_role(v_tenant2, 'Epod Portal Admin', 'CPT Create', 'tester')).id;
  v_draft2 := app.create_role_version(v_role2, 'tester');
  perform app.set_role_version_permissions(v_draft2.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_role2 and status = 'published'), v_staff2, v_staff2, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cea1 Account Alpha', 'cea1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cea1 Account Beta', 'cea1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cea2 Account T2', 'cea2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'cea1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'cea1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'cea2-staff');

  -- v_impersonator deliberately holds ZERO customer-portal grant of any kind.

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-CEA-1', 'Cea1 Trucking Vendor', '[]'::jsonb, '{}'::jsonb, v_staff, 'cea1-staff');

  -- A real Commercial -> Operations pipeline for Account Alpha.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cea1 Alpha Customer Ltd', 'Jane Requester', 'jane@cea1alpha.test', '0811', v_staff, v_company1, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cea1alpha.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cea1alpha.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Cea1 Alpha Customer Ltd', 'Cea1 Alpha', '01.111.222.7-000.000',
    jsonb_build_object('line1', 'Jl. Test 1', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Cea1 Alpha Customer Ltd';
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Cea1 alpha epod lane',
    jsonb_build_object('service_type', 'land_freight', 'origin', 'Jakarta', 'destination', 'Bandung'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_raw_token text;
  begin
    select * into v_contact from app.create_contact(v_tenant1, 'Cea1 Alpha Contact', 'Ops Manager', 'contact@cea1alpha.test', '0813', v_staff, v_company1, v_staff, 'tester');
    select * into v_quotation from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_quotation from app.add_quotation_line(v_quotation.id, v_quotation.record_version, 'service', 'Land freight base charge', null, 1, 6000000, 0, 0, v_staff, 'cea1-staff');
    select * into v_quotation from app.submit_quotation(v_quotation.id, v_quotation.record_version, v_staff, 'cea1-staff');
    select raw_token into v_raw_token from app.send_quotation_for_acceptance(v_quotation.id, v_contact.id, 'email', v_staff, 'cea1-staff');
    perform app.record_quotation_customer_decision(v_raw_token, 'accepted', 'Jane Requester', 'Ops Manager', 'contact@cea1alpha.test', null, null, null);
    select * into v_quotation from app.quotations where id = v_quotation.id;
    perform app.convert_quotation_to_account(v_quotation.id, v_account_alpha, null, v_staff, 'cea1-staff');
  end;
  select * into v_handoff from app.prepare_job_order_handoff(v_quotation.id, v_staff, 'cea1-staff');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_staff, 'cea1-staff');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_staff, 'cea1-staff');

  select * into v_shipment_delivered from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-cea1-alpha-delivered', jsonb_build_object('name', 'Alpha Consignee'), null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() - interval '2 days', now() - interval '1 hours', 2000, 2000, 40, 2000, 2000, 40, null, v_staff, 'cea1-staff'
  );
  select * into v_shipment_delivered from app.confirm_shipment_order(v_shipment_delivered.id, v_shipment_delivered.record_version, v_staff, 'cea1-staff');
  select * into v_shipment_delivered from app.transition_shipment_order(v_shipment_delivered.id, 'planned', v_shipment_delivered.record_version, null, null, 'idem-cea1-alpha-planned', v_staff, 'cea1-staff');
  select * into v_shipment_delivered from app.transition_shipment_order(v_shipment_delivered.id, 'assigned', v_shipment_delivered.record_version, null, null, 'idem-cea1-alpha-assigned', v_staff, 'cea1-staff');
  perform app.assign_resource(v_shipment_delivered.id, 'vendor', v_vendor.id, v_staff, 'cea1-staff');
  select * into v_shipment_delivered from app.transition_shipment_order(v_shipment_delivered.id, 'dispatched', v_shipment_delivered.record_version, null, null, 'idem-cea1-alpha-dispatched', v_staff, 'cea1-staff');
  select * into v_shipment_delivered from app.transition_shipment_order(v_shipment_delivered.id, 'in_transit', v_shipment_delivered.record_version, null, null, 'idem-cea1-alpha-intransit', v_staff, 'cea1-staff');
  select * into v_shipment_delivered from app.transition_shipment_order(v_shipment_delivered.id, 'delivered', v_shipment_delivered.record_version, null, 'physical delivery confirmed', 'idem-cea1-alpha-delivered-t', v_staff, 'cea1-staff');

  -- A second Account Alpha shipment, left at confirmed only -- in-scope, no
  -- ePOD capture of any kind (for the not_available assertion).
  select * into v_shipment_notdelivered from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-cea1-alpha-notdelivered', jsonb_build_object('name', 'Alpha Consignee'), null, 'land_freight', 'land', 'Jakarta', 'Cirebon',
    now() + interval '1 day', now() + interval '3 days', null, null, null, null, null, null, 'split: not-delivered fixture', v_staff, 'cea1-staff'
  );
  select * into v_shipment_notdelivered from app.confirm_shipment_order(v_shipment_notdelivered.id, v_shipment_notdelivered.record_version, v_staff, 'cea1-staff');

  -- An independent Account Beta shipment, confirmed only (out-of-scope probe target for alpha-admin).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cea1 Beta Customer Ltd', 'Beta Requester', 'beta@cea1beta.test', '0812', v_staff, v_company1, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@cea1beta.test';
  perform app.qualify_lead(v_beta_lead.id, v_beta_lead.record_version, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@cea1beta.test';
  perform app.convert_lead_to_prospect(v_beta_lead.id, 'Cea1 Beta Customer Ltd', 'Cea1 Beta', '01.111.222.8-000.000',
    jsonb_build_object('line1', 'Jl. Test 2', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_beta_prospect from app.prospects where legal_name = 'Cea1 Beta Customer Ltd';
  select * into v_beta_opportunity from app.create_opportunity(
    v_tenant1, v_beta_prospect.id, 'Cea1 beta epod lane',
    jsonb_build_object('service_type', 'land_freight', 'origin', 'Jakarta', 'destination', 'Bandung'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_beta_contact app.contacts;
    v_beta_raw_token text;
  begin
    select * into v_beta_contact from app.create_contact(v_tenant1, 'Cea1 Beta Contact', 'Ops Manager', 'contact@cea1beta.test', '0814', v_staff, v_company1, v_staff, 'tester');
    select * into v_beta_quotation from app.create_quotation_draft(v_tenant1, v_beta_opportunity.id, 'IDR', now() + interval '14 days', v_beta_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_beta_quotation from app.add_quotation_line(v_beta_quotation.id, v_beta_quotation.record_version, 'service', 'Land freight base charge', null, 1, 3000000, 0, 0, v_staff, 'cea1-staff');
    select * into v_beta_quotation from app.submit_quotation(v_beta_quotation.id, v_beta_quotation.record_version, v_staff, 'cea1-staff');
    select raw_token into v_beta_raw_token from app.send_quotation_for_acceptance(v_beta_quotation.id, v_beta_contact.id, 'email', v_staff, 'cea1-staff');
    perform app.record_quotation_customer_decision(v_beta_raw_token, 'accepted', 'Beta Requester', 'Ops Manager', 'contact@cea1beta.test', null, null, null);
    select * into v_beta_quotation from app.quotations where id = v_beta_quotation.id;
    perform app.convert_quotation_to_account(v_beta_quotation.id, v_account_beta, null, v_staff, 'cea1-staff');
  end;
  select * into v_beta_handoff from app.prepare_job_order_handoff(v_beta_quotation.id, v_staff, 'cea1-staff');
  select * into v_beta_job_order from app.prepare_job_order(v_beta_handoff.id, v_staff, 'cea1-staff');
  select * into v_beta_job_order from app.confirm_job_order(v_beta_job_order.id, v_beta_job_order.record_version, v_staff, 'cea1-staff');
  select * into v_shipment_beta from app.create_shipment_order_from_job(
    v_beta_job_order.id, 'idem-cea1-beta-001', jsonb_build_object('name', 'Beta Consignee'), null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 5, 500, 10, null, null, null, null, v_staff, 'cea1-staff'
  );
  select * into v_shipment_beta from app.confirm_shipment_order(v_shipment_beta.id, v_shipment_beta.record_version, v_staff, 'cea1-staff');

  -- ePOD document type + tenant cea1's own published definition.
  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', v_supreme, 'supreme');
  v_pod_draft := app.create_config_draft('document:epod', v_tenant1, 'tenant', null, v_staff, 'cea1-staff');
  perform app.set_config_items(v_pod_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg', 'image/png')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), v_staff, 'cea1-staff');
  perform app.publish_document_type_definition(v_pod_draft.id, v_staff, now(), 'cea1-staff');

  -- The real ePOD capture pipeline for the delivered shipment -- 1 signature + 1 photo, both scanned clean, driven all the way to completed.
  v_capture := app.start_epod_capture(v_tenant1, v_shipment_delivered.id, null, 'idem-cea1-alpha-cap', v_staff, 'cea1-staff');
  select * into v_signature from app.initiate_file_upload(v_tenant1, 'epod', 'shipment_order', v_shipment_delivered.id, 'signature-alpha.png', 'image/png', 20480, null, false, null, '{}'::uuid[], null, 'idem-cea1-alpha-sig', v_staff, 'cea1-staff');
  select * into v_photo from app.initiate_file_upload(v_tenant1, 'epod', 'shipment_order', v_shipment_delivered.id, 'photo-alpha-1.jpg', 'image/jpeg', 102400, null, false, null, '{}'::uuid[], null, 'idem-cea1-alpha-photo', v_staff, 'cea1-staff');
  perform app.record_file_scan_result(v_signature.id, 'clean', 'test-scanner-ref', v_staff, 'cea1-staff');
  perform app.record_file_scan_result(v_photo.id, 'clean', 'test-scanner-ref', v_staff, 'cea1-staff');
  v_capture := app.set_epod_evidence(v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_signature.id, array[v_photo.id], jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.845599, -6.208763)), now(), v_staff, 'cea1-staff');
  v_capture := app.submit_epod_capture(v_capture.id, v_capture.record_version, v_staff, 'cea1-staff');
  v_capture := app.review_epod_capture(v_capture.id, 'approved', 'looks good', v_capture.record_version, v_staff, 'cea1-staff');
  select * into v_shipment_delivered from app.shipment_orders so where so.id = v_shipment_delivered.id;
  v_capture := app.complete_epod_capture(v_capture.id, v_capture.record_version, v_shipment_delivered.record_version, 'idem-cea1-alpha-complete', v_staff, 'cea1-staff');
  if v_capture.status <> 'completed' then
    raise exception 'assertion failed: expected the ePOD capture fixture to reach completed, got %', v_capture.status;
  end if;

  insert into cea_test_state (key, value) values
    ('tenant1_id', v_tenant1::text), ('tenant2_id', v_tenant2::text),
    ('account_alpha_id', v_account_alpha::text), ('account_beta_id', v_account_beta::text),
    ('shipment_delivered_id', v_shipment_delivered.id::text), ('shipment_notdelivered_id', v_shipment_notdelivered.id::text), ('shipment_beta_id', v_shipment_beta.id::text),
    ('capture_id', v_capture.id::text), ('signature_file_id', v_signature.id::text), ('photo_file_id', v_photo.id::text);
end;
$$;

\echo '>> app.get_customer_epod: anti-enumerating record_not_found -- genuinely nonexistent, same-tenant out-of-scope, AND cross-tenant zero-relationship all collapse to the IDENTICAL error'
do $$
declare
  v_tenant1 uuid := (select value from cea_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000313010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000313020';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000314010';
  v_shipment_delivered uuid := (select value::uuid from cea_test_state where key = 'shipment_delivered_id');
  v_msg text;
begin
  begin
    perform app.get_customer_epod(v_tenant1, v_alpha_admin, gen_random_uuid());
    raise exception 'assertion failed: expected record_not_found for a genuinely nonexistent shipment order';
  exception
    when no_data_found then v_msg := sqlerrm;
  end;
  if v_msg not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found (nonexistent), got %', v_msg;
  end if;

  begin
    perform app.get_customer_epod(v_tenant1, v_beta_admin, v_shipment_delivered);
    raise exception 'assertion failed: expected record_not_found for beta-admin probing Alpha''s own delivered shipment (same-tenant, out-of-scope)';
  exception
    when no_data_found then v_msg := sqlerrm;
  end;
  if v_msg not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found (out-of-scope), got %', v_msg;
  end if;

  begin
    perform app.get_customer_epod(v_tenant1, v_t2_admin, v_shipment_delivered);
    raise exception 'assertion failed: expected record_not_found for a cross-tenant identity (t2-admin, zero relationship to cea1) probing with cea1''s own tenant id';
  exception
    when no_data_found then v_msg := sqlerrm;
  end;
  if v_msg not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found (cross-tenant), got %', v_msg;
  end if;
end;
$$;

\echo '>> app.get_customer_epod: not_available for an in-scope shipment with no completed ePOD capture at all'
do $$
declare
  v_tenant1 uuid := (select value from cea_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000313010';
  v_shipment_notdelivered uuid := (select value::uuid from cea_test_state where key = 'shipment_notdelivered_id');
  v_row record;
begin
  select * into v_row from app.get_customer_epod(v_tenant1, v_alpha_admin, v_shipment_notdelivered);
  if v_row.epod_status <> 'not_available' or v_row.epod_capture_id is not null or v_row.files <> '[]'::jsonb then
    raise exception 'assertion failed: expected not_available with no capture id and an empty files array, got status=% capture_id=% files=%', v_row.epod_status, v_row.epod_capture_id, v_row.files;
  end if;
end;
$$;

\echo '>> app.get_customer_epod: available -- every referenced file independently re-verified clean, customer-safe metadata returned, granted app.file_access_logs rows written, never storage_path'
do $$
declare
  v_tenant1 uuid := (select value from cea_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000313010';
  v_shipment_delivered uuid := (select value::uuid from cea_test_state where key = 'shipment_delivered_id');
  v_capture_id uuid := (select value::uuid from cea_test_state where key = 'capture_id');
  v_signature_id uuid := (select value::uuid from cea_test_state where key = 'signature_file_id');
  v_photo_id uuid := (select value::uuid from cea_test_state where key = 'photo_file_id');
  v_row record;
  v_file_count integer;
  v_log_count integer;
begin
  select * into v_row from app.get_customer_epod(v_tenant1, v_alpha_admin, v_shipment_delivered);
  if v_row.epod_status <> 'available' or v_row.epod_capture_id <> v_capture_id or v_row.receiver_name <> 'Budi Santoso' or v_row.captured_at is null or v_row.server_received_at is null then
    raise exception 'assertion failed: expected available with real capture metadata, got %', v_row;
  end if;

  select jsonb_array_length(v_row.files) into v_file_count;
  if v_file_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 evidence files (1 signature + 1 photo), got %', v_file_count;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_row.files) f where (f->>'fileId')::uuid = v_signature_id and f->>'role' = 'signature') then
    raise exception 'assertion failed: expected the signature file to be present with role=signature, got %', v_row.files;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_row.files) f where (f->>'fileId')::uuid = v_photo_id and f->>'role' = 'photo') then
    raise exception 'assertion failed: expected the photo file to be present with role=photo, got %', v_row.files;
  end if;
  if exists (select 1 from jsonb_array_elements(v_row.files) f where f ? 'storagePath' or f ? 'storage_path') then
    raise exception 'assertion failed: expected NO storagePath field anywhere in the returned file metadata -- decision 8, never a working URL/storage key leaves this RPC';
  end if;

  -- Tier C fix (spec-compliance Finding 1, batch review of CPL-305..309):
  -- access_type='metadata_view', not 'signed_url_issued' -- no signed URL is
  -- ever fabricated by app.get_customer_epod (design decision 8).
  select count(*) into v_log_count from app.file_access_logs where file_id in (v_signature_id, v_photo_id) and accessed_by_auth_user_id = v_alpha_admin and result = 'granted' and access_type = 'metadata_view';
  if v_log_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 granted app.file_access_logs rows (1 per evidence file) for this access, got %', v_log_count;
  end if;
end;
$$;

\echo '>> THE LIVE-REPRODUCED QUARANTINE CASE (design decisions 2(d)/5): a file directly re-flagged infected after the capture already reached completed (simulating the disclosed RPD-022 Supreme Admin residual-risk correction path, never reachable through app.record_file_scan_result once resolved) flips the WHOLE capture to quarantined -- files withheld entirely, capture metadata (receiver_name/timestamps) still shown, a denied app.file_access_logs row written for the offending file'
do $$
declare
  v_tenant1 uuid := (select value from cea_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000313010';
  v_shipment_delivered uuid := (select value::uuid from cea_test_state where key = 'shipment_delivered_id');
  v_capture_id uuid := (select value::uuid from cea_test_state where key = 'capture_id');
  v_photo_id uuid := (select value::uuid from cea_test_state where key = 'photo_file_id');
  v_row record;
  v_denied_count integer;
begin
  -- Confirmed unreachable through the ordinary RPC surface first -- app.
  -- record_file_scan_result refuses to re-resolve an already-clean file.
  begin
    perform app.record_file_scan_result(v_photo_id, 'infected', 'retroactive-test', '00000000-0000-0000-0000-000000313001', 'cea1-staff');
    raise exception 'assertion failed: expected document_scan_already_resolved -- app.record_file_scan_result must not be able to flip an already-clean file';
  exception
    when check_violation then
      if sqlerrm !~ 'document_scan_already_resolved' then raise; end if;
  end;

  -- Direct table correction -- the only way this state is reachable today, matching this migration's own disclosed RPD-022 residual-risk reasoning.
  -- ISS-2026-231: this raw re-flag IS the disclosed RPD-022 out-of-band correction path,
  -- and since 20260831130000 that path has to say so. The declaration is not ceremony: it
  -- is what distinguishes this deliberate simulation from an accidental or hostile write,
  -- which were previously byte-identical. It also lands a row in app.file_scan_corrections.
  perform set_config('app.scan_correction_reason', 'db-test: simulating the disclosed RPD-022 out-of-band re-flag of an already-clean file', true);
  update app.files set malware_scan_status = 'infected' where id = v_photo_id;

  select * into v_row from app.get_customer_epod(v_tenant1, v_alpha_admin, v_shipment_delivered);
  if v_row.epod_status <> 'quarantined' or v_row.epod_capture_id <> v_capture_id then
    raise exception 'assertion failed: expected quarantined with the same real capture id, got status=% capture_id=%', v_row.epod_status, v_row.epod_capture_id;
  end if;
  if v_row.receiver_name <> 'Budi Santoso' or v_row.captured_at is null then
    raise exception 'assertion failed: expected trusted capture-column metadata (receiver_name/captured_at) to remain visible while quarantined, got %', v_row;
  end if;
  if v_row.files <> '[]'::jsonb then
    raise exception 'assertion failed: expected files to be withheld ENTIRELY while quarantined (never a partial list), got %', v_row.files;
  end if;

  select count(*) into v_denied_count from app.file_access_logs where file_id = v_photo_id and accessed_by_auth_user_id = v_alpha_admin and result = 'denied' and reason = 'document_infected_quarantined';
  if v_denied_count < 1 then
    raise exception 'assertion failed: expected at least 1 denied app.file_access_logs row for the now-infected photo file with reason=document_infected_quarantined, got %', v_denied_count;
  end if;
end;
$$;

\echo '>> app.authorize_file_access is never called by app.get_customer_epod (a live catalog check against the compiled function body, not a grep on this migration''s own source) -- design decision 2/8''s own claim, independently re-verified'
do $$
declare
  v_calls_authorize boolean;
begin
  select prosrc ~ 'authorize_file_access\s*\(' into v_calls_authorize
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.proname = 'get_customer_epod';
  if v_calls_authorize then
    raise exception 'assertion failed: expected app.get_customer_epod to NEVER call app.authorize_file_access (its customer_account_ref branch cannot match an ePOD file, decision 2) -- found a call';
  end if;
end;
$$;

\echo '>> actor-identity session cross-check on app.get_customer_epod'
do $$
declare
  v_tenant1 uuid := (select value from cea_test_state where key = 'tenant1_id')::uuid;
  v_shipment_delivered uuid := (select value::uuid from cea_test_state where key = 'shipment_delivered_id');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000313050", "role": "authenticated"}';

  begin
    perform app.get_customer_epod(v_tenant1, '00000000-0000-0000-0000-000000313010', v_shipment_delivered);
    raise exception 'assertion failed: expected actor_identity_mismatch';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  reset role;
end;
$$;

\echo '>> a real, live authenticated-role positive-path call: alpha-admin''s own real session sees the same result a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select value from cea_test_state where key = 'tenant1_id')::uuid;
  v_shipment_delivered uuid := (select value::uuid from cea_test_state where key = 'shipment_delivered_id');
  v_direct_status text;
  v_session_status text;
begin
  select epod_status into v_direct_status from app.get_customer_epod(v_tenant1, '00000000-0000-0000-0000-000000313010', v_shipment_delivered);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000313010", "role": "authenticated"}';
  select epod_status into v_session_status from app.get_customer_epod(v_tenant1, '00000000-0000-0000-0000-000000313010', v_shipment_delivered);
  reset role;

  if v_session_status is distinct from v_direct_status or v_session_status is null then
    raise exception 'assertion failed: expected the real authenticated session to see the SAME status a direct superuser call returns (session %, direct %)', v_session_status, v_direct_status;
  end if;
end;
$$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE; authenticated/service_role hold EXECUTE'
do $$
declare
  v_has_priv boolean;
begin
  select has_function_privilege('anon', 'app.get_customer_epod(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: anon must NOT hold EXECUTE on app.get_customer_epod';
  end if;
  select has_function_privilege('authenticated', 'app.get_customer_epod(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on app.get_customer_epod';
  end if;
  select has_function_privilege('service_role', 'app.get_customer_epod(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: service_role SHOULD hold EXECUTE on app.get_customer_epod';
  end if;
end;
$$;

\echo '>> app.epod_captures/app.files'' own pre-existing RLS remains completely untouched by this migration -- both still deny a bare customer_user by default'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000313010", "role": "authenticated"}';
  select count(*) into v_count from app.epod_captures;
  if v_count <> 0 then
    raise exception 'assertion failed: expected alpha-admin (customer_user, zero staff org-unit/owner relationship) to see 0 rows on a raw select against app.epod_captures via its own pre-existing RLS, got %', v_count;
  end if;
  select count(*) into v_count from app.files;
  if v_count <> 0 then
    raise exception 'assertion failed: expected alpha-admin to see 0 rows on a raw select against app.files via its own pre-existing RLS, got %', v_count;
  end if;
  reset role;
end;
$$;
