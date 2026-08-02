-- Real, executable test evidence for ATW-225 (CG-S10-ATW-006, Prompt 225 First-,
-- Middle-, and Last-Mile Orchestration with Tracking Policy) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a rep (OPS:Create/Edit/View/Assign), a manager (adds OPS:Override), an OPS-viewer-only actor, a sibling-team outsider, a global Supreme Admin, one active vehicle + one active driver operational profile (eligible + consented), one active GPS device assigned to the vehicle, one active provider mapping, and one confirmed land-freight Shipment Order with a single planned leg and vehicle/driver resource assignments'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_manager_role uuid;
  v_manager_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment app.shipment_orders;
  v_shipment2 app.shipment_orders;
  v_leg app.shipment_legs;
  v_leg2 app.shipment_legs;
  v_vehicle app.vehicle_operational_profiles;
  v_driver app.driver_operational_profiles;
  v_device app.gps_devices;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000039401', 'admin@acmeorch.test'),
    ('00000000-0000-0000-0000-000000039402', 'repa@acmeorch.test'),
    ('00000000-0000-0000-0000-000000039403', 'manager@acmeorch.test'),
    ('00000000-0000-0000-0000-000000039404', 'viewer@acmeorch.test'),
    ('00000000-0000-0000-0000-000000039405', 'outsider@acmeorch.test'),
    ('00000000-0000-0000-0000-000000039406', 'supreme@acmeorch.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039406', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeorch', 'Acme Mile Co', 'idem-acmeorch', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeorch');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEMILE-CO', 'Acme Mile Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE-CO'), 'ACMEMILE-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE-CO'), 'ACMEMILE-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039401', 'admin@acmeorch.test', 'Mile Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeorch.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039401', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039402', 'repa@acmeorch.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeorch.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039403', 'manager@acmeorch.test', 'Ops Manager', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmeorch.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039404', 'viewer@acmeorch.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmeorch.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039405', 'outsider@acmeorch.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeorch.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Mile Rep', 'full commercial + ops create/edit/view/assign', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000039402', '00000000-0000-0000-0000-000000039401', 'tester');

  v_manager_role := (app.create_role(v_tenant1, 'Mile Manager', 'OPS create/edit/view/assign/override', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role, 'tester');
  perform app.set_role_version_permissions(v_manager_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign', 'Override')), 'tester');
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000039403', '00000000-0000-0000-0000-000000039401', 'tester');

  -- register_vehicle/driver_operational_profile call app.create_master_record
  -- internally, hard-gated to tenant_admin/Supreme Admin regardless of OPS role
  -- (ATW-223's own disclosed precondition) -- also grant the manager role to the
  -- tenant_admin fixture user for the OPS:Create/Edit/Assign it separately needs.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000039401', '00000000-0000-0000-0000-000000039406', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Mile Ops Viewer', 'OPS:View only, no Create/Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000039404', '00000000-0000-0000-0000-000000039404', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Mile Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000039405', '00000000-0000-0000-0000-000000039401', 'tester');

  -- Fleet: one eligible+consented vehicle/driver pair, one active device assigned
  -- to the vehicle, one active provider mapping (real ATW-223 eligibility data).
  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-MILE-A', 'Mile Truck A', 'owned', 2000, 20, '00000000-0000-0000-0000-000000039401', 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, false, true, true, v_vehicle.record_version, '00000000-0000-0000-0000-000000039401', 'admin');
  select * into v_driver from app.register_driver_operational_profile(v_tenant1, 'DRV-MILE-A', 'Driver A', 'B2', (now() + interval '2 years')::date, '00000000-0000-0000-0000-000000039401', 'admin');
  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver.id, true, v_driver.record_version, '00000000-0000-0000-0000-000000039401', 'admin');

  select * into v_device from app.register_gps_device(v_tenant1, 'IMEI-MILE-0001', 'Teltonika FMB920', 'cargogrid', '00000000-0000-0000-0000-000000039401', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle.id, 'initial install', '00000000-0000-0000-0000-000000039401', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000039401', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'installed', v_device.record_version, '00000000-0000-0000-0000-000000039401', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'active', v_device.record_version, '00000000-0000-0000-0000-000000039401', 'admin');

  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle.vehicle_master_id, 'TELTONIKA_CLOUD', 'ext-veh-mile-1', '00000000-0000-0000-0000-000000039401', 'admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Mileorch225 Co', 'Jane Mileorch', 'jane@mileorch225test.test', '0811',
    '00000000-0000-0000-0000-000000039402', v_team_a, '00000000-0000-0000-0000-000000039402', 'tester');
  select * into v_lead from app.leads where email = 'jane@mileorch225test.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000039402', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Mileorch225 Co', 'MO225', '11.111.111.4-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 4', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000039402', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Mileorch Ops', 'Procurement Lead', 'jane@mileorch225test.test', '0811', '00000000-0000-0000-0000-000000039402', v_team_a, '00000000-0000-0000-0000-000000039402', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000039402', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Mileorch225 test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000039402', v_team_a, '00000000-0000-0000-0000-000000039402', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000039402', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-MO225-1', 'Contoso Mileorch225 Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000039401', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000039401', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000039402', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000039402', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000039402', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000039402', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000039402', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Mile orchestration lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000039402', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000039402', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000039402', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Mileorch Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000039402', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000039402', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000039402', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000039402', 'rep');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mile-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 1000, 1000, 16, 1000, 1000, 16, null, '00000000-0000-0000-0000-000000039402', 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000039402', 'rep');

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-mile-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000039402', 'rep');
  perform app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, now(), '00000000-0000-0000-0000-000000039402', 'rep');
  perform app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bandung Warehouse', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000039402', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 500, 500, 8, '00000000-0000-0000-0000-000000039402', 'rep');

  select * into v_leg2 from app.add_shipment_leg(v_shipment.id, 'idem-mile-leg2', 2, 'land', null, now() + interval '1 day', now() + interval '2 days', '00000000-0000-0000-0000-000000039402', 'rep');
  perform app.add_shipment_leg_stop(v_leg2.id, 1, 'pickup', 'Bandung Cross-dock', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000039402', 'rep');
  perform app.add_shipment_leg_stop(v_leg2.id, 2, 'delivery', 'Bandung Customer Site', null, null, null, now() + interval '2 days', '00000000-0000-0000-0000-000000039402', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg2.id, 500, 500, 8, '00000000-0000-0000-0000-000000039402', 'rep');

  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000039402', 'rep');

  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, '00000000-0000-0000-0000-000000039402', 'rep');
  perform app.assign_resource(v_shipment.id, 'driver', v_driver.driver_master_id, '00000000-0000-0000-0000-000000039402', 'rep');
end $$;

\echo '>> app.upsert_shipment_leg_tracking_policy: authority-gated, idempotent-upsert per leg, rejects an inconsistent not-required policy'
do $$
declare
  v_leg_id uuid;
  v_policy app.shipment_leg_tracking_policies;
begin
  select id into v_leg_id from app.shipment_legs where idempotency_key = 'idem-mile-leg1';

  begin
    perform app.upsert_shipment_leg_tracking_policy(
      v_leg_id, true, array['driver_mobile', 'direct_device'], 'direct_device', array['direct_device', 'driver_mobile'],
      120, 50, 30, 'leg_dispatch', 'leg_complete', null, true, 1, '00000000-0000-0000-0000-000000039404', 'viewer'
    );
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select * into v_policy from app.upsert_shipment_leg_tracking_policy(
    v_leg_id, true, array['driver_mobile', 'direct_device'], 'direct_device', array['direct_device', 'driver_mobile'],
    120, 50, 30, 'leg_dispatch', 'leg_complete', null, true, 1, '00000000-0000-0000-0000-000000039402', 'rep'
  );
  if v_policy.policy_version <> 1 or v_policy.tracking_required is not true then
    raise exception 'assertion failed: expected a fresh policy_version 1, tracking_required true';
  end if;

  select * into v_policy from app.upsert_shipment_leg_tracking_policy(
    v_leg_id, true, array['driver_mobile', 'direct_device'], 'driver_mobile', array['driver_mobile', 'direct_device'],
    120, 50, 30, 'leg_dispatch', 'leg_complete', null, true, 1, '00000000-0000-0000-0000-000000039402', 'rep'
  );
  if v_policy.policy_version <> 2 or v_policy.preferred_source <> 'driver_mobile' then
    raise exception 'assertion failed: expected the upsert to bump policy_version to 2 and update preferred_source';
  end if;

  begin
    perform app.upsert_shipment_leg_tracking_policy(
      v_leg_id, false, array['driver_mobile'], null, '{}', null, null, null, 'leg_dispatch', 'leg_complete', null, false, null,
      '00000000-0000-0000-0000-000000039402', 'rep'
    );
    raise exception 'assertion failed: expected a check_violation -- tracking_required=false requires empty allowed_sources';
  exception
    when others then
      if sqlerrm not like '%violates check constraint%' then raise; end if;
  end;
end $$;

\echo '>> app.resolve_leg_tracking_policy: reflects real ATW-223 eligibility data, resolves the policy''s own fallback order, discloses entitlement without gating on it'
do $$
declare
  v_leg_id uuid;
  v_row record;
begin
  select id into v_leg_id from app.shipment_legs where idempotency_key = 'idem-mile-leg1';

  select * into v_row from app.resolve_leg_tracking_policy(v_leg_id, '00000000-0000-0000-0000-000000039402');
  if not ('driver_mobile' = any (v_row.eligible_sources) and 'direct_device' = any (v_row.eligible_sources) and 'third_party_platform' = any (v_row.eligible_sources)) then
    raise exception 'assertion failed: expected all three sources objectively eligible (driver consented, vehicle device active, provider mapping active), got %', v_row.eligible_sources;
  end if;
  if v_row.resolved_source <> 'driver_mobile' then
    raise exception 'assertion failed: expected resolved_source = driver_mobile (first in the policy''s own fallback_order), got %', v_row.resolved_source;
  end if;
  if v_row.resolved_driver_master_id is null or v_row.blocked_reason is not null then
    raise exception 'assertion failed: expected a resolved driver and a null blocked_reason';
  end if;
  if v_row.tracking_entitled is not false then
    raise exception 'assertion failed: expected the honest, currently-always-false tracking_entitled stub (ATW-226A has not shipped)';
  end if;
end $$;

\echo '>> app.start_leg_tracking_session / app.handoff_leg_tracking_session: real eligibility enforced, session_already_active guarded, handoff supersedes with update-before-insert ordering'
do $$
declare
  v_leg_id uuid;
  v_leg2_id uuid;
  v_vehicle_master_id uuid;
  v_driver_master_id uuid;
  v_device_id uuid;
  v_session1 app.shipment_leg_tracking_sessions;
  v_session2 app.shipment_leg_tracking_sessions;
begin
  select id into v_leg_id from app.shipment_legs where idempotency_key = 'idem-mile-leg1';
  select id into v_leg2_id from app.shipment_legs where idempotency_key = 'idem-mile-leg2';
  select vop.vehicle_master_id into v_vehicle_master_id from app.vehicle_operational_profiles vop join app.master_records mr on mr.id = vop.vehicle_master_id where mr.code = 'VEH-MILE-A';
  select dop.driver_master_id into v_driver_master_id from app.driver_operational_profiles dop join app.master_records mr on mr.id = dop.driver_master_id where mr.code = 'DRV-MILE-A';
  select id into v_device_id from app.gps_devices where imei = 'IMEI-MILE-0001';

  begin
    perform app.start_leg_tracking_session(v_leg_id, 'driver_mobile', 'driver', v_driver_master_id, null, '00000000-0000-0000-0000-000000039404', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select * into v_session1 from app.start_leg_tracking_session(v_leg_id, 'driver_mobile', 'driver', v_driver_master_id, null, '00000000-0000-0000-0000-000000039402', 'rep');
  if v_session1.status <> 'active' or v_session1.tracking_entitled_at_start is not false then
    raise exception 'assertion failed: expected an active session with an honest false tracking_entitled_at_start snapshot';
  end if;

  begin
    perform app.start_leg_tracking_session(v_leg_id, 'direct_device', 'vehicle', v_vehicle_master_id, v_device_id, '00000000-0000-0000-0000-000000039402', 'rep');
    raise exception 'assertion failed: expected session_already_active';
  exception
    when others then
      if sqlerrm not like 'session_already_active%' then raise; end if;
  end;

  begin
    perform app.handoff_leg_tracking_session(v_leg_id, 'direct_device', 'vehicle', v_vehicle_master_id, v_device_id, '', '00000000-0000-0000-0000-000000039402', 'rep');
    raise exception 'assertion failed: expected handoff_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'handoff_reason_required%' then raise; end if;
  end;

  select * into v_session2 from app.handoff_leg_tracking_session(
    v_leg_id, 'direct_device', 'vehicle', v_vehicle_master_id, v_device_id, 'driver ended shift, switching to installed device', '00000000-0000-0000-0000-000000039402', 'rep'
  );
  if v_session2.source_type <> 'direct_device' then
    raise exception 'assertion failed: expected the new current session to be direct_device';
  end if;

  select * into v_session1 from app.shipment_leg_tracking_sessions where id = v_session1.id;
  if v_session1.is_current or v_session1.end_reason <> 'handoff' or v_session1.superseded_by_id <> v_session2.id then
    raise exception 'assertion failed: expected the prior session superseded via handoff, never overwritten in place';
  end if;
  if (select count(*) from app.shipment_leg_tracking_sessions where shipment_leg_id = v_leg_id and is_current) <> 1 then
    raise exception 'assertion failed: expected exactly one is_current session per leg (partial unique index)';
  end if;

  -- leg2 has no tracking policy defined yet -- a genuinely distinct leg-scoped guard.
  begin
    perform app.start_leg_tracking_session(v_leg2_id, 'driver_mobile', 'driver', v_driver_master_id, null, '00000000-0000-0000-0000-000000039402', 'rep');
    raise exception 'assertion failed: expected policy_not_defined for a leg with no tracking policy yet';
  exception
    when others then
      if sqlerrm not like 'policy_not_defined%' then raise; end if;
  end;
end $$;

\echo '>> app.end_leg_tracking_session: leg_completed/manual_stop require OPS:Edit; unauthorized_override requires OPS:Override plus a mandatory reason'
do $$
declare
  v_tenant1 uuid;
  v_leg_id uuid;
  v_session app.shipment_leg_tracking_sessions;
  v_driver_master_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeorch');
  select id into v_leg_id from app.shipment_legs where idempotency_key = 'idem-mile-leg1';
  select dop.driver_master_id into v_driver_master_id from app.driver_operational_profiles dop join app.master_records mr on mr.id = dop.driver_master_id where mr.code = 'DRV-MILE-A';

  begin
    perform app.end_leg_tracking_session(v_leg_id, 'manual_stop', '', '00000000-0000-0000-0000-000000039402', 'rep');
    raise exception 'assertion failed: expected end_reason_required for an empty manual_stop reason';
  exception
    when others then
      if sqlerrm not like 'end_reason_required%' then raise; end if;
  end;

  select * into v_session from app.end_leg_tracking_session(v_leg_id, 'manual_stop', 'dispatcher correction', '00000000-0000-0000-0000-000000039402', 'rep');
  if v_session.status <> 'ended' or v_session.end_reason <> 'manual_stop' then
    raise exception 'assertion failed: expected the session ended with manual_stop';
  end if;

  begin
    perform app.end_leg_tracking_session(v_leg_id, 'manual_stop', 'no session left', '00000000-0000-0000-0000-000000039402', 'rep');
    raise exception 'assertion failed: expected no_active_session';
  exception
    when others then
      if sqlerrm not like 'no_active_session%' then raise; end if;
  end;

  perform app.start_leg_tracking_session(v_leg_id, 'driver_mobile', 'driver', v_driver_master_id, null, '00000000-0000-0000-0000-000000039402', 'rep');

  begin
    perform app.end_leg_tracking_session(v_leg_id, 'unauthorized_override', 'force stop', '00000000-0000-0000-0000-000000039402', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- rep holds OPS:Create/Edit/View/Assign but not OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.end_leg_tracking_session(v_leg_id, 'unauthorized_override', '', '00000000-0000-0000-0000-000000039403', 'manager');
    raise exception 'assertion failed: expected override_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'override_reason_required%' then raise; end if;
  end;

  -- Widen rep's own grants with the manager role's OPS:Override permission
  -- (roles are additive per identity) -- proves Override is the genuine
  -- deciding factor on the exact identity that already owns this shipment
  -- (app.shipment_orders carries no org_unit_id; record-scope is owner-only),
  -- the identical fixture technique ATW-224's own db-test already established.
  perform app.assign_role(v_tenant1, (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id where r.name = 'Mile Manager' and rv.status = 'published'), '00000000-0000-0000-0000-000000039402', '00000000-0000-0000-0000-000000039406', 'tester');

  select * into v_session from app.end_leg_tracking_session(v_leg_id, 'unauthorized_override', 'compliance-directed force stop', '00000000-0000-0000-0000-000000039402', 'rep');
  if v_session.end_reason <> 'unauthorized_override' then
    raise exception 'assertion failed: expected the session force-ended with unauthorized_override';
  end if;
end $$;

\echo '>> app.evaluate_leg_no_signal_escalation: an orchestration-level staleness check (session left open past its own no_signal_escalation_seconds) ends the session and raises a real app.operational_exceptions row'
do $$
declare
  v_leg_id uuid;
  v_shipment_id uuid;
  v_driver_master_id uuid;
  v_session app.shipment_leg_tracking_sessions;
  v_exception_count integer;
begin
  select id into v_leg_id from app.shipment_legs where idempotency_key = 'idem-mile-leg1';
  select shipment_order_id into v_shipment_id from app.shipment_legs where id = v_leg_id;
  select dop.driver_master_id into v_driver_master_id from app.driver_operational_profiles dop join app.master_records mr on mr.id = dop.driver_master_id where mr.code = 'DRV-MILE-A';

  select * into v_session from app.start_leg_tracking_session(v_leg_id, 'driver_mobile', 'driver', v_driver_master_id, null, '00000000-0000-0000-0000-000000039402', 'rep');

  -- Not yet stale (the policy's own no_signal_escalation_seconds is 1).
  select * into v_session from app.evaluate_leg_no_signal_escalation(v_leg_id, '00000000-0000-0000-0000-000000039402', 'rep');
  if v_session.status <> 'active' then
    raise exception 'assertion failed: expected the session still active -- it has not yet exceeded the escalation threshold';
  end if;

  -- Backdate started_at directly (this test's own simulation of elapsed time --
  -- no live telemetry exists to actually wait on, this migration's own header).
  update app.shipment_leg_tracking_sessions set started_at = now() - interval '5 seconds' where id = v_session.id;

  select * into v_session from app.evaluate_leg_no_signal_escalation(v_leg_id, '00000000-0000-0000-0000-000000039402', 'rep');
  if v_session.status <> 'ended' or v_session.end_reason <> 'stale_source' then
    raise exception 'assertion failed: expected the session ended with stale_source once past its own escalation threshold';
  end if;

  select count(*) into v_exception_count from app.operational_exceptions
    where shipment_order_id = v_shipment_id and type = 'incident' and source = 'system' and correlation_key = 'leg-no-signal:' || v_leg_id::text;
  if v_exception_count <> 1 then
    raise exception 'assertion failed: expected exactly one real app.operational_exceptions row raised for this leg''s own no-signal escalation, found %', v_exception_count;
  end if;

  -- Idempotent no-op: no current session remains, must not raise.
  select * into v_session from app.evaluate_leg_no_signal_escalation(v_leg_id, '00000000-0000-0000-0000-000000039402', 'rep');
  if v_session is not null then
    raise exception 'assertion failed: expected null once no current session remains';
  end if;
end $$;

\echo '>> cross-tenant isolation: app.upsert_shipment_leg_tracking_policy/app.resolve_leg_tracking_policy fail closed for an identity with no membership in the shipment''s own tenant'
do $$
declare
  v_tenant2 uuid;
  v_leg_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000039407', 'admin2@acmeorch2.test');
  perform app.provision_tenant('acmeorch2', 'Acme Mile Co 2', 'idem-acmeorch2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeorch2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000039407', 'admin2@acmeorch2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmeorch2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039407', 'tenant_admin', v_tenant2, null, 'tester');

  select id into v_leg_id from app.shipment_legs where idempotency_key = 'idem-mile-leg1';

  begin
    perform app.upsert_shipment_leg_tracking_policy(
      v_leg_id, true, array['driver_mobile'], 'driver_mobile', array['driver_mobile'], null, null, null, 'leg_dispatch', 'leg_complete', null, false, null,
      '00000000-0000-0000-0000-000000039407', 'tenant2-admin'
    );
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Edit in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.resolve_leg_tracking_policy(v_leg_id, '00000000-0000-0000-0000-000000039407');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin cannot access tenant 1''s shipment order';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 8 new Mile Orchestration functions (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in (
      'check_leg_tracking_source_eligible', 'upsert_shipment_leg_tracking_policy', 'resolve_leg_tracking_policy',
      'start_leg_tracking_session', 'handoff_leg_tracking_session', 'end_leg_tracking_session',
      'evaluate_leg_no_signal_escalation', 'get_shipment_leg_tracking_sessions'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 8 new Mile Orchestration functions, found %', v_count;
  end if;
end $$;

\echo '>> schema-privilege defense in depth: authenticated has no direct INSERT/UPDATE/DELETE on either of the 2 new tables (mutation only through the governed RPCs above)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app'
    and grantee = 'authenticated'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and table_name in ('shipment_leg_tracking_policies', 'shipment_leg_tracking_sessions');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on the 2 new tables, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real Mile Orchestration mutation recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeorch');

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.shipment_leg_tracking_policies' and action = 'upsert_shipment_leg_tracking_policy';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 upsert_shipment_leg_tracking_policy audit events (the denied attempt is not counted), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.shipment_leg_tracking_sessions' and action = 'handoff_leg_tracking_session';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 handoff_leg_tracking_session audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.shipment_leg_tracking_sessions' and action = 'evaluate_leg_no_signal_escalation';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 evaluate_leg_no_signal_escalation audit event, found %', v_count;
  end if;
end $$;
