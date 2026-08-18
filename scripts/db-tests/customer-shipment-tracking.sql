-- Real, executable test evidence for CPL-305 (CG-S13-CPL-007, Prompt 305,
-- "Tracking") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Structural convention mirrors scripts/db-tests/
-- customer-shipment-orders.sql (CPL-304) exactly.
--
-- UUID range 00000000-0000-0000-0000-0000309xxx (tenant cst1) /
-- ...310xxx (tenant cst2) -- grep-verified unclaimed (right after CPL-304's
-- own ...307xxx/...308xxx range). Tenant slugs cst1/cst2. GPS device IMEI
-- 868712345603501 -- grep-verified unclaimed across every scripts/db-tests/
-- *.sql fixture (ATW-246's own disclosed collision-safety discipline).
-- Milestone codes are registered under this file's own unique namespace
-- (customer_tracking_*) rather than reusing another file's codes, since
-- app.milestone_codes is a platform-wide, cross-file-shared registry.
--
-- Covers, live: (1) anti-enumeration (IDENTICAL record_not_found for a
-- nonexistent id, an out-of-scope id, and a cross-tenant identity); (2)
-- actor-identity session cross-check; (3) milestone timeline includes ONLY
-- customer-visible codes, ordered oldest-first, projected to a
-- code/name/category/eventTime allowlist with no staff-internal field; (4)
-- before any tracking-package entitlement is published,
-- position_unavailable_reason=tracking_not_entitled and the milestone
-- timeline is UNCHANGED (entitlement never gates milestones); (5) once
-- entitlement is published, a real ingested canonical position with a
-- customer_visible=true leg policy composes a real vehicle_position_geojson/
-- vehicle_position_status/eta_status/eta_at, position_unavailable_reason
-- null; (6) flipping the leg's own tracking policy to customer_visible=false
-- hides the position (not_customer_visible) without touching milestones;
-- (7) a shipment with no active leg at all (Beta, a different account)
-- reports no_active_leg once entitled; (8) raw-function grant defense in
-- depth (anon has no EXECUTE, authenticated/service_role do); (9) a real,
-- live authenticated-role positive-path call.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cst1 (staff with OPS:Create/Edit/View/Assign + COM:Create/Edit/Approve + CPT:Create, a tenant_admin for Configuration Engine; accounts Alpha/Beta; alpha-admin active on Alpha, beta-admin active on Beta, impersonator with zero relationship); a second, otherwise-empty tenant cst2 (t2-admin on account T2) for cross-tenant isolation; a real job order/shipment order/leg/vehicle/GPS-device pipeline in cst1 for Account Alpha, dispatched with a customer-visible tracking policy and one real ingested canonical position; a second, leg-less confirmed shipment order for Account Beta'
create temporary table cst_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000309001';
  v_supreme uuid := '00000000-0000-0000-0000-000000309003';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000309010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000309020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000309050';
  v_staff2 uuid := '00000000-0000-0000-0000-000000310001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000310010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_quotation app.quotations;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment_order app.shipment_orders;
  v_leg1 app.shipment_legs;
  v_beta_lead app.leads;
  v_beta_prospect app.prospects;
  v_beta_opportunity app.opportunities;
  v_beta_quotation app.quotations;
  v_beta_handoff app.job_order_handoffs;
  v_beta_job_order app.job_orders;
  v_beta_shipment_order app.shipment_orders;
  v_vehicle app.vehicle_operational_profiles;
  v_device app.gps_devices;
  v_key record;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@cst1.test'),
    (v_supreme, 'supreme@cst1.test'),
    (v_alpha_admin, 'alpha-admin@cst1.test'),
    (v_beta_admin, 'beta-admin@cst1.test'),
    (v_impersonator, 'impersonator@cst1.test'),
    (v_staff2, 'staff@cst2.test'),
    (v_t2_admin, 't2-admin@cst2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cst1', 'Customer Shipment Tracking Tenant One', 'idem-cst1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cst1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CST1-CO', 'Cst1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CST1-CO');

  perform app.provision_tenant('cst2', 'Customer Shipment Tracking Tenant Two', 'idem-cst2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cst2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CST2-CO', 'Cst2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@cst1.test', 'Cst1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cst1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@cst2.test', 'Cst2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cst2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant1, 'Ops Portal Staff', 'OPS Edit/Assign + COM Create/Edit/Approve + CPT Create', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'OPS' and action in ('View', 'Create', 'Edit', 'Assign')) or (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve')) or (resource_module_code = 'CPT' and action = 'Create')),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_staff, v_staff, 'tester');
  perform app.grant_principal_membership(v_staff, 'tenant_admin', v_tenant1, null, 'tester');

  v_role2 := (app.create_role(v_tenant2, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_draft2 := app.create_role_version(v_role2, 'tester');
  perform app.set_role_version_permissions(v_draft2.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_role2 and status = 'published'), v_staff2, v_staff2, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cst1 Account Alpha', 'cst1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cst1 Account Beta', 'cst1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cst2 Account T2', 'cst2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'cst1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'cst1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'cst2-staff');

  -- v_impersonator deliberately holds ZERO customer-portal grant of any kind.

  -- Two customer-visible-registry milestone codes -- this file's own
  -- unique namespace (customer_tracking_*), not reused from any other file.
  perform app.register_milestone_code('customer_tracking_pickup_arrival', 'Pickup Arrival', 'pickup', true, false, false, v_supreme, 'supreme');
  perform app.register_milestone_code('customer_tracking_internal_check', 'Internal Ops Check', 'administrative', false, false, false, v_supreme, 'supreme');

  -- A real Commercial -> Operations pipeline for Account Alpha, mirroring
  -- customer-shipment-orders.sql (CPL-304) exactly.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cst1 Alpha Customer Ltd', 'Jane Requester', 'jane@cst1alpha.test', '0811', v_staff, v_company1, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cst1alpha.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cst1alpha.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Cst1 Alpha Customer Ltd', 'Cst1 Alpha', '01.111.222.5-000.000',
    jsonb_build_object('line1', 'Jl. Test 1', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Cst1 Alpha Customer Ltd';
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Cst1 alpha test lane',
    jsonb_build_object('service_type', 'land_freight', 'origin', 'Jakarta', 'destination', 'Bandung'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_contact app.contacts;
    v_draft_quotation app.quotations;
    v_raw_token text;
  begin
    select * into v_contact from app.create_contact(v_tenant1, 'Cst1 Alpha Contact', 'Ops Manager', 'contact@cst1alpha.test', '0813', v_staff, v_company1, v_staff, 'tester');
    select * into v_draft_quotation from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_draft_quotation from app.add_quotation_line(v_draft_quotation.id, v_draft_quotation.record_version, 'service', 'Land freight base charge', null, 1, 6000000, 0, 0, v_staff, 'cst1-staff');
    select * into v_quotation from app.submit_quotation(v_draft_quotation.id, v_draft_quotation.record_version, v_staff, 'cst1-staff');
    select raw_token into v_raw_token from app.send_quotation_for_acceptance(v_quotation.id, v_contact.id, 'email', v_staff, 'cst1-staff');
    perform app.record_quotation_customer_decision(v_raw_token, 'accepted', 'Jane Requester', 'Ops Manager', 'contact@cst1alpha.test', null, null, null);
    select * into v_quotation from app.quotations where id = v_quotation.id;
    perform app.convert_quotation_to_account(v_quotation.id, v_account_alpha, null, v_staff, 'cst1-staff');
  end;
  select * into v_handoff from app.prepare_job_order_handoff(v_quotation.id, v_staff, 'cst1-staff');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_staff, 'cst1-staff');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_staff, 'cst1-staff');
  select * into v_shipment_order from app.create_shipment_order_from_job(
    v_job_order.id, 'shipment-cst1-alpha-001', jsonb_build_object('name', 'Alpha Consignee'), null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 2000, 2000, 40, 2000, 2000, 40, null, v_staff, 'cst1-staff'
  );
  select * into v_shipment_order from app.confirm_shipment_order(v_shipment_order.id, v_shipment_order.record_version, v_staff, 'cst1-staff');

  -- One customer-visible milestone event and one non-customer-visible
  -- (internal) event on Alpha's shipment -- the timeline projection must
  -- surface only the former.
  perform app.ingest_milestone_event(v_shipment_order.id, 'customer_tracking_pickup_arrival', now(), now(), null, 'manual', null, null, 'idem-cst1-pickup', v_staff, 'cst1-staff');
  perform app.ingest_milestone_event(v_shipment_order.id, 'customer_tracking_internal_check', now(), now(), null, 'manual', null, null, 'idem-cst1-internal', v_staff, 'cst1-staff');

  -- A real leg + stops + cargo, dispatched, with a customer_visible=true
  -- tracking policy -- mirrors advanced-tms-milestone-exception-telemetry.sql
  -- (ATW-228)'s own fixture pipeline exactly.
  select * into v_leg1 from app.add_shipment_leg(v_shipment_order.id, 'idem-cst1-leg1', 1, 'land', null, now(), now() + interval '1 day', v_staff, 'cst1-staff');
  perform app.add_shipment_leg_stop(v_leg1.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), v_staff, 'cst1-staff');
  perform app.add_shipment_leg_stop(v_leg1.id, 2, 'delivery', 'Bandung Warehouse', null, 107.619123, -6.917464, now() + interval '1 day', v_staff, 'cst1-staff');
  perform app.allocate_shipment_leg_cargo(v_leg1.id, 2000, 2000, 40, v_staff, 'cst1-staff');
  perform app.confirm_shipment_leg_network(v_shipment_order.id, (select record_version from app.shipment_orders where id = v_shipment_order.id), v_staff, 'cst1-staff');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-CST-A', 'Tracking Truck A', 'owned', 2000, 20, v_staff, 'cst1-staff');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, false, true, false, v_vehicle.record_version, v_staff, 'cst1-staff');
  select * into v_device from app.register_gps_device(v_tenant1, '868712345603501', 'Teltonika FMC920', 'cargogrid', v_staff, 'cst1-staff');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, v_staff, 'cst1-staff');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle.id, 'initial install', v_staff, 'cst1-staff');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'installed', v_device.record_version, v_staff, 'cst1-staff');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'active', v_device.record_version, v_staff, 'cst1-staff');
  select * into v_key from app.create_api_key(v_tenant1, 'Cst1 Tracking Gateway Key', '["OPS:Edit"]'::jsonb, null, null, v_staff, 'cst1-staff');

  perform app.assign_resource(v_shipment_order.id, 'vehicle', v_vehicle.vehicle_master_id, v_staff, 'cst1-staff');
  select * into v_leg1 from app.transition_shipment_leg(v_leg1.id, 'dispatched', v_leg1.record_version, v_staff, 'cst1-staff');

  perform app.upsert_shipment_leg_tracking_policy(
    v_leg1.id, true, array['direct_device'], 'direct_device', array['direct_device'],
    300, 100, 30, 'leg_dispatch', 'leg_complete', null, true, 1800, v_staff, 'cst1-staff'
  );

  -- A real ingested direct-device report, near the pickup stop -- canonicalized
  -- automatically (app.arbitrate_and_project_vehicle_position, ATW-226F) into a
  -- real app.vehicle_current_positions row for this vehicle.
  perform app.ingest_direct_device_telemetry_batch(
    v_key.raw_key, v_device.id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', now()::text, 'longitude', 106.846000, 'latitude', -6.209000, 'speed_kmh', 40)),
    'cst1-test-gateway'
  );

  -- An independent, leg-LESS Account Beta shipment (no app.add_shipment_leg
  -- ever called) -- the "no_active_leg" branch, real once entitlement is on.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cst1 Beta Customer Ltd', 'Beta Requester', 'beta@cst1beta.test', '0812', v_staff, v_company1, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@cst1beta.test';
  perform app.qualify_lead(v_beta_lead.id, v_beta_lead.record_version, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@cst1beta.test';
  perform app.convert_lead_to_prospect(v_beta_lead.id, 'Cst1 Beta Customer Ltd', 'Cst1 Beta', '01.111.222.6-000.000',
    jsonb_build_object('line1', 'Jl. Test 2', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_beta_prospect from app.prospects where legal_name = 'Cst1 Beta Customer Ltd';
  select * into v_beta_opportunity from app.create_opportunity(
    v_tenant1, v_beta_prospect.id, 'Cst1 beta test lane',
    jsonb_build_object('service_type', 'land_freight', 'origin', 'Jakarta', 'destination', 'Bandung'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_beta_contact app.contacts;
    v_beta_draft_quotation app.quotations;
    v_beta_raw_token text;
  begin
    select * into v_beta_contact from app.create_contact(v_tenant1, 'Cst1 Beta Contact', 'Ops Manager', 'contact@cst1beta.test', '0814', v_staff, v_company1, v_staff, 'tester');
    select * into v_beta_draft_quotation from app.create_quotation_draft(v_tenant1, v_beta_opportunity.id, 'IDR', now() + interval '14 days', v_beta_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_beta_draft_quotation from app.add_quotation_line(v_beta_draft_quotation.id, v_beta_draft_quotation.record_version, 'service', 'Land freight base charge', null, 1, 3000000, 0, 0, v_staff, 'cst1-staff');
    select * into v_beta_quotation from app.submit_quotation(v_beta_draft_quotation.id, v_beta_draft_quotation.record_version, v_staff, 'cst1-staff');
    select raw_token into v_beta_raw_token from app.send_quotation_for_acceptance(v_beta_quotation.id, v_beta_contact.id, 'email', v_staff, 'cst1-staff');
    perform app.record_quotation_customer_decision(v_beta_raw_token, 'accepted', 'Beta Requester', 'Ops Manager', 'contact@cst1beta.test', null, null, null);
    select * into v_beta_quotation from app.quotations where id = v_beta_quotation.id;
    perform app.convert_quotation_to_account(v_beta_quotation.id, v_account_beta, null, v_staff, 'cst1-staff');
  end;
  select * into v_beta_handoff from app.prepare_job_order_handoff(v_beta_quotation.id, v_staff, 'cst1-staff');
  select * into v_beta_job_order from app.prepare_job_order(v_beta_handoff.id, v_staff, 'cst1-staff');
  select * into v_beta_job_order from app.confirm_job_order(v_beta_job_order.id, v_beta_job_order.record_version, v_staff, 'cst1-staff');
  select * into v_beta_shipment_order from app.create_shipment_order_from_job(
    v_beta_job_order.id, 'shipment-cst1-beta-001', jsonb_build_object('name', 'Beta Consignee'), null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 5, 500, 10, null, null, null, null, v_staff, 'cst1-staff'
  );
  select * into v_beta_shipment_order from app.confirm_shipment_order(v_beta_shipment_order.id, v_beta_shipment_order.record_version, v_staff, 'cst1-staff');

  insert into cst_test_state (key, value) values
    ('tenant1_id', v_tenant1::text), ('tenant2_id', v_tenant2::text),
    ('shipment_order_id', v_shipment_order.id::text), ('leg1_id', v_leg1.id::text),
    ('beta_shipment_order_id', v_beta_shipment_order.id::text);
end;
$$;

\echo '>> app.get_customer_shipment_tracking: BEFORE tracking.enabled is published -- milestone timeline is real (only the customer-visible code), but tracking_entitled=false and position_unavailable_reason=tracking_not_entitled'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cst1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000309010';
  v_shipment_id uuid := (select value::uuid from cst_test_state where key = 'shipment_order_id');
  v_result app.customer_shipment_tracking_result;
begin
  select * into v_result from app.get_customer_shipment_tracking(v_tenant1, v_alpha_admin, v_shipment_id);

  if v_result.shipment_order_id <> v_shipment_id then
    raise exception 'assertion failed: expected the returned row''s own shipment_order_id to match the requested shipment order';
  end if;
  if jsonb_array_length(v_result.milestones) <> 1 then
    raise exception 'assertion failed: expected exactly 1 customer-visible milestone, got %', jsonb_array_length(v_result.milestones);
  end if;
  if (v_result.milestones -> 0 ->> 'code') <> 'customer_tracking_pickup_arrival' then
    raise exception 'assertion failed: expected the customer-visible pickup code, got %', (v_result.milestones -> 0 ->> 'code');
  end if;
  if (v_result.milestones -> 0) ? 'source' or (v_result.milestones -> 0) ? 'reason' or (v_result.milestones -> 0) ? 'location' or (v_result.milestones -> 0) ? 'sourceClass' then
    raise exception 'assertion failed: milestone projection leaks a staff-internal field: %', (v_result.milestones -> 0);
  end if;

  if v_result.tracking_entitled is distinct from false then
    raise exception 'assertion failed: expected tracking_entitled=false before any tracking.enabled config is published';
  end if;
  if v_result.position_unavailable_reason is distinct from 'tracking_not_entitled' then
    raise exception 'assertion failed: expected position_unavailable_reason=tracking_not_entitled, got %', v_result.position_unavailable_reason;
  end if;
  if v_result.vehicle_position_geojson is not null or v_result.vehicle_position_status is not null or v_result.eta_status is not null or v_result.eta_at is not null then
    raise exception 'assertion failed: expected every position/eta field null while not entitled';
  end if;
end;
$$;

\echo '>> publish tracking.enabled=true for tenant cst1 (Configuration Engine PLT-121, the same general-purpose draft/set-items/publish RPCs every tracking-governed capability in this repository already uses)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cst1');
  v_staff uuid := '00000000-0000-0000-0000-000000309001';
  v_draft app.config_versions;
begin
  v_draft := app.create_config_draft('feature', v_tenant1, 'tenant', null, v_staff, 'cst1-staff');
  perform app.set_config_items(
    v_draft.id,
    '[
      {"key": "tracking.enabled", "value": true},
      {"key": "tracking.package", "value": "standard"},
      {"key": "tracking.limits", "value": {"max_tracked_vehicles": 50, "max_mobile_sessions": 20, "history_retention_days": 90}}
    ]'::jsonb,
    v_staff, 'cst1-staff'
  );
  perform app.publish_config_version(v_draft.id, v_staff, null, 'cst1-staff');

  if app.is_shipment_tracking_entitled(v_tenant1) is distinct from true then
    raise exception 'assertion failed: expected app.is_shipment_tracking_entitled=true once tracking.enabled=true is published';
  end if;
end;
$$;

\echo '>> app.get_customer_shipment_tracking: now entitled, active leg, assigned vehicle, customer_visible=true policy -- a real composed vehicle_position_geojson/vehicle_position_status/eta_status/eta_at, position_unavailable_reason null, milestones unchanged'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cst1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000309010';
  v_shipment_id uuid := (select value::uuid from cst_test_state where key = 'shipment_order_id');
  v_result app.customer_shipment_tracking_result;
begin
  select * into v_result from app.get_customer_shipment_tracking(v_tenant1, v_alpha_admin, v_shipment_id);

  if v_result.tracking_entitled is distinct from true then
    raise exception 'assertion failed: expected tracking_entitled=true now that tracking.enabled is published';
  end if;
  if jsonb_array_length(v_result.milestones) <> 1 then
    raise exception 'assertion failed: expected the milestone timeline to be unaffected by entitlement, still exactly 1 row, got %', jsonb_array_length(v_result.milestones);
  end if;
  if v_result.position_unavailable_reason is not null then
    raise exception 'assertion failed: expected position_unavailable_reason=null once a real position exists on a customer_visible leg, got %', v_result.position_unavailable_reason;
  end if;
  if v_result.vehicle_position_geojson is null or (v_result.vehicle_position_geojson ->> 'type') <> 'Point' then
    raise exception 'assertion failed: expected a real GeoJSON Point vehicle_position_geojson, got %', v_result.vehicle_position_geojson;
  end if;
  if v_result.vehicle_position_status not in ('live', 'delayed') then
    raise exception 'assertion failed: expected vehicle_position_status live or delayed for a just-ingested report, got %', v_result.vehicle_position_status;
  end if;
  if v_result.vehicle_position_updated_at is null then
    raise exception 'assertion failed: expected a real vehicle_position_updated_at';
  end if;
  if v_result.eta_status not in ('on_time', 'delayed') then
    raise exception 'assertion failed: expected a computed eta_status (on_time/delayed) with a real remaining stop and a real live position, got %', v_result.eta_status;
  end if;
  if v_result.eta_at is null then
    raise exception 'assertion failed: expected a real eta_at once eta_status is computed';
  end if;
end;
$$;

\echo '>> a real, live authenticated-role positive-path call: alpha-admin''s own real session gets the same real composition a direct superuser call would (run while the leg is still customer_visible=true, before the next block flips it)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cst1');
  v_shipment_id uuid := (select value::uuid from cst_test_state where key = 'shipment_order_id');
  v_direct app.customer_shipment_tracking_result;
  v_session app.customer_shipment_tracking_result;
begin
  select * into v_direct from app.get_customer_shipment_tracking(v_tenant1, '00000000-0000-0000-0000-000000309010', v_shipment_id);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000309010", "role": "authenticated"}';
  select * into v_session from app.get_customer_shipment_tracking(v_tenant1, '00000000-0000-0000-0000-000000309010', v_shipment_id);
  reset role;

  if v_session.vehicle_position_status is distinct from v_direct.vehicle_position_status
    or v_session.eta_status is distinct from v_direct.eta_status
    or jsonb_array_length(v_session.milestones) <> jsonb_array_length(v_direct.milestones)
  then
    raise exception 'assertion failed: expected the real authenticated session to see the SAME composition as the direct superuser call (status %/%, eta %/%)',
      v_session.vehicle_position_status, v_direct.vehicle_position_status, v_session.eta_status, v_direct.eta_status;
  end if;
  if v_session.vehicle_position_status is null then
    raise exception 'assertion failed: expected a real, nonnull vehicle_position_status at this point in the test (still customer_visible=true, the next block has not flipped it yet)';
  end if;
end;
$$;

\echo '>> flipping the leg''s own tracking policy to customer_visible=false hides the position/eta (not_customer_visible) without touching the milestone timeline'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cst1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000309010';
  v_staff uuid := '00000000-0000-0000-0000-000000309001';
  v_shipment_id uuid := (select value::uuid from cst_test_state where key = 'shipment_order_id');
  v_leg1_id uuid := (select value::uuid from cst_test_state where key = 'leg1_id');
  v_result app.customer_shipment_tracking_result;
begin
  perform app.upsert_shipment_leg_tracking_policy(
    v_leg1_id, true, array['direct_device'], 'direct_device', array['direct_device'],
    300, 100, 30, 'leg_dispatch', 'leg_complete', null, false, 1800, v_staff, 'cst1-staff'
  );

  select * into v_result from app.get_customer_shipment_tracking(v_tenant1, v_alpha_admin, v_shipment_id);

  if v_result.position_unavailable_reason is distinct from 'not_customer_visible' then
    raise exception 'assertion failed: expected position_unavailable_reason=not_customer_visible once the leg policy is flipped, got %', v_result.position_unavailable_reason;
  end if;
  if v_result.vehicle_position_geojson is not null or v_result.vehicle_position_status is not null or v_result.eta_status is not null then
    raise exception 'assertion failed: expected every position/eta field null once customer_visible=false';
  end if;
  if jsonb_array_length(v_result.milestones) <> 1 then
    raise exception 'assertion failed: expected the milestone timeline to be completely unaffected by the policy flip, got %', jsonb_array_length(v_result.milestones);
  end if;
end;
$$;

\echo '>> app.get_customer_shipment_tracking: Account Beta''s own shipment has no leg at all -- entitled, but no_active_leg, and zero milestones'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cst1');
  v_beta_admin uuid := '00000000-0000-0000-0000-000000309020';
  v_beta_shipment_id uuid := (select value::uuid from cst_test_state where key = 'beta_shipment_order_id');
  v_result app.customer_shipment_tracking_result;
begin
  select * into v_result from app.get_customer_shipment_tracking(v_tenant1, v_beta_admin, v_beta_shipment_id);

  if v_result.tracking_entitled is distinct from true then
    raise exception 'assertion failed: expected tracking_entitled=true (tenant-level) for Beta''s own shipment too';
  end if;
  if v_result.position_unavailable_reason is distinct from 'no_active_leg' then
    raise exception 'assertion failed: expected position_unavailable_reason=no_active_leg for a leg-less shipment, got %', v_result.position_unavailable_reason;
  end if;
  if jsonb_array_length(v_result.milestones) <> 0 then
    raise exception 'assertion failed: expected zero milestones on Beta''s own shipment, got %', jsonb_array_length(v_result.milestones);
  end if;
end;
$$;

\echo '>> anti-enumeration -- IDENTICAL record_not_found for a nonexistent id, beta-admin reading Alpha''s shipment (out of scope), and a cross-tenant identity'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cst1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000309010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000309020';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000310010';
  v_shipment_id uuid := (select value::uuid from cst_test_state where key = 'shipment_order_id');
  v_msg_nonexistent text;
  v_msg_forbidden text;
  v_msg_cross_tenant text;
begin
  begin
    perform app.get_customer_shipment_tracking(v_tenant1, v_alpha_admin, gen_random_uuid());
    raise exception 'assertion failed: expected record_not_found for a genuinely nonexistent id';
  exception
    when others then
      v_msg_nonexistent := sqlerrm;
  end;

  begin
    perform app.get_customer_shipment_tracking(v_tenant1, v_beta_admin, v_shipment_id);
    raise exception 'assertion failed: expected record_not_found for beta-admin reading an Alpha shipment order';
  exception
    when others then
      v_msg_forbidden := sqlerrm;
  end;

  begin
    perform app.get_customer_shipment_tracking(v_tenant1, v_t2_admin, v_shipment_id);
    raise exception 'assertion failed: expected record_not_found for a cst2 identity reading a cst1 shipment order';
  exception
    when others then
      v_msg_cross_tenant := sqlerrm;
  end;

  if v_msg_nonexistent not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found for a nonexistent id, got %', v_msg_nonexistent;
  end if;
  if v_msg_forbidden not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found for an out-of-scope id, got %', v_msg_forbidden;
  end if;
  if v_msg_cross_tenant not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found for a cross-tenant identity, got %', v_msg_cross_tenant;
  end if;
end;
$$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cst1');
  v_shipment_id uuid := (select value::uuid from cst_test_state where key = 'shipment_order_id');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000309050", "role": "authenticated"}';
  begin
    -- Real session is impersonator (309050); this call claims to act as alpha-admin (309010).
    perform app.get_customer_shipment_tracking(v_tenant1, '00000000-0000-0000-0000-000000309010', v_shipment_id);
    raise exception 'assertion failed: expected actor_identity_mismatch';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  reset role;
end;
$$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE; authenticated/service_role hold EXECUTE'
do $$
declare
  v_fn text := 'app.get_customer_shipment_tracking(uuid, uuid, uuid)';
  v_has_priv boolean;
begin
  select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_fn;
  end if;
  select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on %', v_fn;
  end if;
  select has_function_privilege('service_role', v_fn, 'EXECUTE') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_fn;
  end if;
end;
$$;
