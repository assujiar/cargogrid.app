-- Real, executable test evidence for ATW-227 (CG-S10-ATW-008, Prompt 227 Capacity,
-- Utilization and Tracking Coverage) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (acmecapacity): a tenant_admin (master-data registration only), a rep (OPS:Create/Edit/View), an OPS:View-only viewer, one active vehicle (2000kg/20cbm capacity, direct_device+third_party eligible, mobile ineligible) with one active GPS device and one active provider mapping, a confirmed land-freight Shipment Order with four legs (leg1/leg3/leg4 share one overlapping window, leg2 is a back-to-back non-overlapping window) and a current vehicle resource assignment. Tenant2 (acmecapacity2): an isolated admin/rep for cross-tenant leakage checks. A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_team2 uuid;
  v_rep2_role uuid;
  v_rep2_draft app.role_versions;
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
  v_leg1 app.shipment_legs;
  v_leg2 app.shipment_legs;
  v_leg3 app.shipment_legs;
  v_leg4 app.shipment_legs;
  v_vehicle app.vehicle_operational_profiles;
  v_device app.gps_devices;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000050101', 'admin@acmecapacity.test'),
    ('00000000-0000-0000-0000-000000050102', 'rep@acmecapacity.test'),
    ('00000000-0000-0000-0000-000000050103', 'viewer@acmecapacity.test'),
    ('00000000-0000-0000-0000-000000050104', 'supreme@acmecapacity.test'),
    ('00000000-0000-0000-0000-000000050105', 'admin2@acmecapacity2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000050104', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmecapacity', 'Acme Capacity Co', 'idem-acmecapacity', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmecapacity');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMECAP-CO', 'Acme Capacity Co', 'tester');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECAP-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000050101', 'admin@acmecapacity.test', 'Capacity Admin', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmecapacity.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000050101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000050102', 'rep@acmecapacity.test', 'Capacity Rep', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmecapacity.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000050103', 'viewer@acmecapacity.test', 'Capacity Viewer', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmecapacity.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Capacity Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000050102', '00000000-0000-0000-0000-000000050101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Capacity Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000050103', '00000000-0000-0000-0000-000000050101', 'tester');

  -- register_vehicle_operational_profile calls app.create_master_record internally,
  -- hard-gated to tenant_admin/Supreme Admin regardless of OPS role (ATW-223's own
  -- disclosed precondition) -- grant the rep role to the tenant_admin fixture too.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000050101', '00000000-0000-0000-0000-000000050104', 'tester');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-CAP-A', 'Capacity Truck A', 'owned', 2000, 20, '00000000-0000-0000-0000-000000050101', 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, false, true, true, v_vehicle.record_version, '00000000-0000-0000-0000-000000050101', 'admin');

  select * into v_device from app.register_gps_device(v_tenant1, 'IMEI-CAP-0001', 'Teltonika FMB920', 'cargogrid', '00000000-0000-0000-0000-000000050101', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle.id, 'initial install', '00000000-0000-0000-0000-000000050101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000050101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'installed', v_device.record_version, '00000000-0000-0000-0000-000000050101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'active', v_device.record_version, '00000000-0000-0000-0000-000000050101', 'admin');

  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle.vehicle_master_id, 'TELTONIKA_CLOUD', 'ext-veh-cap-1', '00000000-0000-0000-0000-000000050101', 'admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Capacity227 Co', 'Jane Capacity', 'jane@capacity227test.test', '0811',
    '00000000-0000-0000-0000-000000050102', v_team, '00000000-0000-0000-0000-000000050102', 'tester');
  select * into v_lead from app.leads where email = 'jane@capacity227test.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000050102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Capacity227 Co', 'CAP227', '11.111.111.5-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 5', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000050102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Capacity Ops', 'Procurement Lead', 'jane@capacity227test.test', '0811', '00000000-0000-0000-0000-000000050102', v_team, '00000000-0000-0000-0000-000000050102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000050102', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Capacity227 test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000050102', v_team, '00000000-0000-0000-0000-000000050102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000050102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CAP227-1', 'Contoso Capacity227 Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000050101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000050101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000050102', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000050102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000050102', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000050102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000050102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Capacity227 lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000050102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000050102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000050102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Capacity Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000050102', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000050102', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000050102', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000050102', 'rep');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-capacity-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 2000, 2000, 40, 2000, 2000, 40, null, '00000000-0000-0000-0000-000000050102', 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000050102', 'rep');

  -- leg1 and leg2 are back-to-back (non-overlapping); leg3/leg4 deliberately share
  -- leg1's own window, so a reservation against leg1 must constrain leg3/leg4 but
  -- never leg2.
  select * into v_leg1 from app.add_shipment_leg(v_shipment.id, 'idem-cap-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.add_shipment_leg_stop(v_leg1.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, now(), '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.add_shipment_leg_stop(v_leg1.id, 2, 'delivery', 'Bandung Warehouse', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg1.id, 500, 500, 8, '00000000-0000-0000-0000-000000050102', 'rep');

  select * into v_leg2 from app.add_shipment_leg(v_shipment.id, 'idem-cap-leg2', 2, 'land', null, now() + interval '1 day', now() + interval '2 days', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.add_shipment_leg_stop(v_leg2.id, 1, 'pickup', 'Bandung Cross-dock', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.add_shipment_leg_stop(v_leg2.id, 2, 'delivery', 'Bandung Customer Site', null, null, null, now() + interval '2 days', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg2.id, 500, 500, 8, '00000000-0000-0000-0000-000000050102', 'rep');

  select * into v_leg3 from app.add_shipment_leg(v_shipment.id, 'idem-cap-leg3', 3, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.add_shipment_leg_stop(v_leg3.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, now(), '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.add_shipment_leg_stop(v_leg3.id, 2, 'delivery', 'Bandung Warehouse', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg3.id, 10, 10, 1, '00000000-0000-0000-0000-000000050102', 'rep');

  select * into v_leg4 from app.add_shipment_leg(v_shipment.id, 'idem-cap-leg4', 4, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.add_shipment_leg_stop(v_leg4.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, now(), '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.add_shipment_leg_stop(v_leg4.id, 2, 'delivery', 'Bandung Warehouse', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg4.id, 10, 10, 1, '00000000-0000-0000-0000-000000050102', 'rep');

  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000050102', 'rep');
  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, '00000000-0000-0000-0000-000000050102', 'rep');

  -- Tenant2: fully isolated, zero vehicles/legs -- exists only to prove cross-tenant
  -- scope safety on both the reservation ledger and the coverage/utilization reads.
  perform app.provision_tenant('acmecapacity2', 'Acme Capacity Two', 'idem-acmecapacity2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmecapacity2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMECAP2-CO', 'Acme Capacity Two', 'tester');
  v_team2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMECAP2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000050105', 'admin2@acmecapacity2.test', 'Tenant2 Admin', v_team2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmecapacity2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000050105', 'tenant_admin', v_tenant2, null, 'tester');

  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'OPS create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000050105', '00000000-0000-0000-0000-000000050105', 'tester');
end $$;

\echo '>> app.reserve_vehicle_capacity: OPS:View-only viewer rejected (lacks OPS:Create); rep succeeds, deriving the vehicle from the leg''s own current resource assignment (never caller-supplied); a same-idempotency-key replay returns the identical row unchanged'
do $$
declare
  v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-cap-leg1');
  v_vehicle_master_id uuid := (select vop.vehicle_master_id from app.vehicle_operational_profiles vop join app.master_records mr on mr.id = vop.vehicle_master_id where vop.tenant_id = (select id from app.tenants where slug = 'acmecapacity') and mr.code = 'VEH-CAP-A');
  v_reservation app.vehicle_capacity_reservations;
  v_replay app.vehicle_capacity_reservations;
begin
  begin
    perform app.reserve_vehicle_capacity(v_leg1_id, 1200, 8, 'idem-cap-leg1-reserve', '00000000-0000-0000-0000-000000050103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Create';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_reservation := app.reserve_vehicle_capacity(v_leg1_id, 1200, 8, 'idem-cap-leg1-reserve', '00000000-0000-0000-0000-000000050102', 'rep');
  if v_reservation.vehicle_master_id <> v_vehicle_master_id or v_reservation.status <> 'held' or v_reservation.record_version <> 1 then
    raise exception 'assertion failed: expected a held reservation against the leg''s own assigned vehicle %, got vehicle=% status=% version=%', v_vehicle_master_id, v_reservation.vehicle_master_id, v_reservation.status, v_reservation.record_version;
  end if;
  if v_reservation.window_start <> (select planned_departure_at from app.shipment_legs where id = v_leg1_id)
    or v_reservation.window_end <> (select planned_arrival_at from app.shipment_legs where id = v_leg1_id)
  then
    raise exception 'assertion failed: expected the reservation window to be copied from the leg''s own planned_departure_at/planned_arrival_at';
  end if;

  v_replay := app.reserve_vehicle_capacity(v_leg1_id, 1200, 8, 'idem-cap-leg1-reserve', '00000000-0000-0000-0000-000000050102', 'rep');
  if v_replay.id <> v_reservation.id or v_replay.record_version <> 1 then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical, unchanged row';
  end if;

  if (select count(*) from app.vehicle_capacity_reservations where shipment_leg_id = v_leg1_id) <> 1 then
    raise exception 'assertion failed: expected exactly one reservation row for leg1 despite two reserve calls';
  end if;
end $$;

\echo '>> app.reserve_vehicle_capacity: leg2''s own back-to-back (non-overlapping) window may reserve the same vehicle''s full remaining nominal capacity even though the two legs'' own requested weights would sum past capacity -- proving the check is window-aware, never a naive across-all-legs sum'
do $$
declare
  v_leg2_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-cap-leg2');
  v_reservation app.vehicle_capacity_reservations;
begin
  v_reservation := app.reserve_vehicle_capacity(v_leg2_id, 1200, 5, 'idem-cap-leg2-reserve', '00000000-0000-0000-0000-000000050102', 'rep');
  if v_reservation.status <> 'held' then
    raise exception 'assertion failed: expected leg2''s reservation to succeed despite 1200+1200=2400 > 2000kg vehicle capacity, since the two legs'' own windows never overlap';
  end if;
end $$;

\echo '>> app.reserve_vehicle_capacity: leg3 shares leg1''s own window -- rejected with capacity_exceeded at 1200+900=2100kg > 2000kg, accepted at exactly the 1200+800=2000kg boundary, and a second reservation attempt against the same already-active leg (a different idempotency key) is rejected with reservation_already_active'
do $$
declare
  v_leg3_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-cap-leg3');
  v_reservation app.vehicle_capacity_reservations;
begin
  begin
    perform app.reserve_vehicle_capacity(v_leg3_id, 900, null, 'idem-cap-leg3-try1', '00000000-0000-0000-0000-000000050102', 'rep');
    raise exception 'assertion failed: expected capacity_exceeded -- 1200 (leg1, overlapping) + 900 (leg3) = 2100kg > 2000kg vehicle capacity';
  exception
    when others then
      if sqlerrm not like 'capacity_exceeded%' then raise; end if;
  end;

  v_reservation := app.reserve_vehicle_capacity(v_leg3_id, 800, null, 'idem-cap-leg3-try2', '00000000-0000-0000-0000-000000050102', 'rep');
  if v_reservation.status <> 'held' then
    raise exception 'assertion failed: expected 1200+800=2000kg (exactly at capacity) to succeed, a <= boundary, not a < one';
  end if;

  begin
    perform app.reserve_vehicle_capacity(v_leg3_id, 1, null, 'idem-cap-leg3-try3', '00000000-0000-0000-0000-000000050102', 'rep');
    raise exception 'assertion failed: expected reservation_already_active -- leg3 already carries a held reservation under a different idempotency key';
  exception
    when others then
      if sqlerrm not like 'reservation_already_active%' then raise; end if;
  end;

  if (select count(*) from app.vehicle_capacity_reservations where shipment_leg_id = v_leg3_id) <> 1 then
    raise exception 'assertion failed: expected exactly one reservation row for leg3 despite three reserve attempts';
  end if;
end $$;

\echo '>> app.consume_vehicle_capacity_reservation: OPS:View-only viewer rejected (lacks OPS:Edit); rep succeeds (held -> consumed); a stale expected_version is rejected; consuming an already-consumed reservation is rejected with invalid_transition'
do $$
declare
  v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-cap-leg1');
  v_reservation_id uuid := (select id from app.vehicle_capacity_reservations where shipment_leg_id = v_leg1_id);
  v_reservation app.vehicle_capacity_reservations;
begin
  begin
    perform app.consume_vehicle_capacity_reservation(v_reservation_id, 1, '00000000-0000-0000-0000-000000050103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_reservation := app.consume_vehicle_capacity_reservation(v_reservation_id, 1, '00000000-0000-0000-0000-000000050102', 'rep');
  if v_reservation.status <> 'consumed' or v_reservation.record_version <> 2 then
    raise exception 'assertion failed: expected held -> consumed, record_version 1 -> 2, got status=% version=%', v_reservation.status, v_reservation.record_version;
  end if;

  begin
    perform app.consume_vehicle_capacity_reservation(v_reservation_id, 1, '00000000-0000-0000-0000-000000050102', 'rep');
    raise exception 'assertion failed: expected stale_version -- record_version is now 2, not 1';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  begin
    perform app.consume_vehicle_capacity_reservation(v_reservation_id, 2, '00000000-0000-0000-0000-000000050102', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- reservation is already consumed, not held';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> app.release_vehicle_capacity_reservation: mandatory non-empty reason; releasing leg3''s reservation frees its own overlapping-window capacity for a subsequent reservation (leg4) against the same vehicle/window; releasing an already-released reservation is rejected with invalid_transition'
do $$
declare
  v_leg3_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-cap-leg3');
  v_leg4_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-cap-leg4');
  v_leg3_reservation_id uuid := (select id from app.vehicle_capacity_reservations where shipment_leg_id = v_leg3_id);
  v_reservation app.vehicle_capacity_reservations;
  v_leg4_reservation app.vehicle_capacity_reservations;
begin
  begin
    perform app.release_vehicle_capacity_reservation(v_leg3_reservation_id, '', 1, '00000000-0000-0000-0000-000000050102', 'rep');
    raise exception 'assertion failed: expected reason_required -- an empty reason must be rejected';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  begin
    perform app.reserve_vehicle_capacity(v_leg4_id, 800, 6, 'idem-cap-leg4-try1', '00000000-0000-0000-0000-000000050102', 'rep');
    raise exception 'assertion failed: expected capacity_exceeded -- leg3''s 800kg is still held, 1200(leg1)+800(leg3)+800(leg4)=2800kg > 2000kg';
  exception
    when others then
      if sqlerrm not like 'capacity_exceeded%' then raise; end if;
  end;

  v_reservation := app.release_vehicle_capacity_reservation(v_leg3_reservation_id, 'reassigned to a different vehicle', 1, '00000000-0000-0000-0000-000000050102', 'rep');
  if v_reservation.status <> 'released' or v_reservation.released_reason <> 'reassigned to a different vehicle' then
    raise exception 'assertion failed: expected held -> released with the given reason, got status=% reason=%', v_reservation.status, v_reservation.released_reason;
  end if;

  v_leg4_reservation := app.reserve_vehicle_capacity(v_leg4_id, 800, 6, 'idem-cap-leg4-try2', '00000000-0000-0000-0000-000000050102', 'rep');
  if v_leg4_reservation.status <> 'held' then
    raise exception 'assertion failed: expected leg4''s reservation to now succeed (1200 consumed + 800 held = 2000kg, exactly at capacity) now that leg3''s release freed its own 800kg';
  end if;

  begin
    perform app.release_vehicle_capacity_reservation(v_leg3_reservation_id, 'second attempt', 2, '00000000-0000-0000-0000-000000050102', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- reservation is already released';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> app.get_tenant_tracking_coverage: one row for the tenant''s only active vehicle -- hybrid source class (direct_device+third_party, mobile ineligible), offline coverage (eligible but never reported a real position), an active provider mapping, and the live now() capacity snapshot reflecting only leg1 (consumed) + leg4 (held), never leg2 (future window) or leg3 (released)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmecapacity');
  v_row record;
begin
  select * into v_row from app.get_tenant_tracking_coverage(v_tenant1, '00000000-0000-0000-0000-000000050102') where vehicle_code = 'VEH-CAP-A';
  if not found then
    raise exception 'assertion failed: expected exactly one coverage row for VEH-CAP-A';
  end if;
  if v_row.source_class <> 'hybrid' or v_row.coverage_status <> 'offline' or v_row.has_active_provider_mapping is distinct from true then
    raise exception 'assertion failed: expected hybrid/offline/has_active_provider_mapping=true, got %/%/%', v_row.source_class, v_row.coverage_status, v_row.has_active_provider_mapping;
  end if;
  if v_row.capacity_weight_kg <> 2000 or v_row.capacity_volume_cbm <> 20 then
    raise exception 'assertion failed: expected the vehicle''s own declared capacity (2000kg/20cbm), got %/%', v_row.capacity_weight_kg, v_row.capacity_volume_cbm;
  end if;
  if v_row.reserved_weight_kg <> 2000 or v_row.reserved_volume_cbm <> 14 then
    raise exception 'assertion failed: expected a live reserved snapshot of 2000kg/14cbm (leg1''s 1200/8 consumed + leg4''s 800/6 held; leg2''s future-window 1200/5 and leg3''s released 800/null excluded), got %/%', v_row.reserved_weight_kg, v_row.reserved_volume_cbm;
  end if;
  if v_row.authoritative_source_type is not null or v_row.last_position_at is not null then
    raise exception 'assertion failed: a vehicle that has never had a canonical position applied must report null source/last-position, never a fabricated one';
  end if;
end $$;

\echo '>> app.get_tenant_tracking_utilization_summary: honest all-default entitlement before any tracking package is assigned; device/mobile-session counts; untracked_required_leg_count reflects leg1 once dispatched+tracking-required with no active session, and drops to zero once a real session starts'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmecapacity');
  v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-cap-leg1');
  v_vehicle_master_id uuid := (select vop.vehicle_master_id from app.vehicle_operational_profiles vop join app.master_records mr on mr.id = vop.vehicle_master_id where vop.tenant_id = v_tenant1 and mr.code = 'VEH-CAP-A');
  v_device_id uuid := (select id from app.gps_devices where tenant_id = v_tenant1 and imei = 'IMEI-CAP-0001');
  v_summary app.tenant_tracking_utilization_summary;
  v_leg1_version integer;
begin
  v_summary := app.get_tenant_tracking_utilization_summary(v_tenant1, '00000000-0000-0000-0000-000000050102');
  if v_summary.tracking_enabled is distinct from false or v_summary.package_code is not null or v_summary.max_tracked_vehicles is not null or v_summary.tracked_vehicle_limit_remaining is not null then
    raise exception 'assertion failed: expected the honest all-default entitlement before any tracking package is ever assigned, got enabled=% package=% max=% remaining=%',
      v_summary.tracking_enabled, v_summary.package_code, v_summary.max_tracked_vehicles, v_summary.tracked_vehicle_limit_remaining;
  end if;
  if v_summary.total_active_vehicle_count <> 1 or v_summary.offline_vehicle_count <> 1 or v_summary.tracked_vehicle_count <> 0 then
    raise exception 'assertion failed: expected 1 active vehicle, offline (never reported), got total=% offline=% tracked=%', v_summary.total_active_vehicle_count, v_summary.offline_vehicle_count, v_summary.tracked_vehicle_count;
  end if;
  if v_summary.device_total_count <> 1 or v_summary.device_active_count <> 1 then
    raise exception 'assertion failed: expected 1 total/1 active GPS device, got total=% active=%', v_summary.device_total_count, v_summary.device_active_count;
  end if;
  if v_summary.mobile_session_active_count <> 0 then
    raise exception 'assertion failed: expected zero active mobile sessions -- none was ever started, got %', v_summary.mobile_session_active_count;
  end if;
  if v_summary.untracked_required_leg_count <> 0 then
    raise exception 'assertion failed: expected zero untracked-required legs before leg1 is dispatched, got %', v_summary.untracked_required_leg_count;
  end if;

  -- Define a tracking-required policy on leg1, then dispatch it -- now a
  -- tracking-required leg with no active tracking session.
  perform app.upsert_shipment_leg_tracking_policy(
    v_leg1_id, true, array['direct_device'], 'direct_device', array['direct_device'],
    120, 50, 30, 'leg_dispatch', 'leg_complete', null, true, null, '00000000-0000-0000-0000-000000050102', 'rep'
  );
  select record_version into v_leg1_version from app.shipment_legs where id = v_leg1_id;
  perform app.transition_shipment_leg(v_leg1_id, 'dispatched', v_leg1_version, '00000000-0000-0000-0000-000000050102', 'rep');

  v_summary := app.get_tenant_tracking_utilization_summary(v_tenant1, '00000000-0000-0000-0000-000000050102');
  if v_summary.untracked_required_leg_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 untracked-required leg (leg1: dispatched, tracking_required, no active session), got %', v_summary.untracked_required_leg_count;
  end if;

  perform app.start_leg_tracking_session(v_leg1_id, 'direct_device', 'vehicle', v_vehicle_master_id, v_device_id, '00000000-0000-0000-0000-000000050102', 'rep');

  v_summary := app.get_tenant_tracking_utilization_summary(v_tenant1, '00000000-0000-0000-0000-000000050102');
  if v_summary.untracked_required_leg_count <> 0 then
    raise exception 'assertion failed: expected 0 untracked-required legs once leg1 has a real active tracking session, got %', v_summary.untracked_required_leg_count;
  end if;
end $$;

\echo '>> app.get_tenant_tracking_utilization_summary: assigning a real tracking package (Configuration Engine, 226A) makes tracked_vehicle_limit_remaining a real computed value, never fabricated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmecapacity');
  v_draft app.config_versions;
  v_summary app.tenant_tracking_utilization_summary;
begin
  v_draft := app.create_config_draft('feature', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000050101', 'admin');
  perform app.set_config_items(
    v_draft.id,
    '[
      {"key": "tracking.enabled", "value": true},
      {"key": "tracking.package", "value": "standard"},
      {"key": "tracking.limits", "value": {"max_tracked_vehicles": 5, "max_mobile_sessions": 10, "history_retention_days": 90}}
    ]'::jsonb,
    '00000000-0000-0000-0000-000000050101', 'admin'
  );
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000050101', null, 'admin');

  v_summary := app.get_tenant_tracking_utilization_summary(v_tenant1, '00000000-0000-0000-0000-000000050102');
  if v_summary.tracking_enabled is distinct from true or v_summary.package_code <> 'standard' or v_summary.max_tracked_vehicles <> 5 then
    raise exception 'assertion failed: expected the published standard/5 package to resolve, got enabled=% package=% max=%', v_summary.tracking_enabled, v_summary.package_code, v_summary.max_tracked_vehicles;
  end if;
  if v_summary.tracked_vehicle_limit_remaining <> 5 then
    raise exception 'assertion failed: expected 5 - 0 tracked = 5 remaining (the vehicle is still offline, never tracked), got %', v_summary.tracked_vehicle_limit_remaining;
  end if;
end $$;

\echo '>> cross-tenant scope safety: tenant2''s own admin cannot read tenant1''s coverage/utilization/reservations at all (insufficient_authority calling with tenant1''s id); calling with their own tenant2 id returns a real, all-zero result (zero vehicles, zero reservations), never tenant1''s data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmecapacity');
  v_tenant2 uuid := (select id from app.tenants where slug = 'acmecapacity2');
  v_row_count integer;
  v_summary app.tenant_tracking_utilization_summary;
begin
  begin
    perform app.get_tenant_tracking_coverage(v_tenant1, '00000000-0000-0000-0000-000000050105');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s admin holds no grant at all in tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_tenant_tracking_utilization_summary(v_tenant1, '00000000-0000-0000-0000-000000050105');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s admin holds no grant at all in tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select count(*) into v_row_count from app.get_tenant_tracking_coverage(v_tenant2, '00000000-0000-0000-0000-000000050105');
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero coverage rows for tenant2 (it has zero vehicles), found %', v_row_count;
  end if;

  v_summary := app.get_tenant_tracking_utilization_summary(v_tenant2, '00000000-0000-0000-0000-000000050105');
  if v_summary.total_active_vehicle_count <> 0 or v_summary.device_total_count <> 0 or v_summary.untracked_required_leg_count <> 0 then
    raise exception 'assertion failed: expected an honest all-zero summary for tenant2, got total_active_vehicle_count=% device_total_count=% untracked_required_leg_count=%',
      v_summary.total_active_vehicle_count, v_summary.device_total_count, v_summary.untracked_required_leg_count;
  end if;
end $$;

\echo '>> RLS: tenant-wide read (any tenant1 member, including the view-only viewer) sees tenant1''s own reservation rows; tenant2''s admin sees none of it'
do $$
declare
  v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-cap-leg1');
  v_row_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000050103", "role": "authenticated"}';
  select count(*) into v_row_count from app.vehicle_capacity_reservations where shipment_leg_id = v_leg1_id;
  reset role;
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected the tenant1 viewer to see leg1''s own reservation row (tenant-wide read, not role-scoped), found %', v_row_count;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000050105", "role": "authenticated"}';
  select count(*) into v_row_count from app.vehicle_capacity_reservations where shipment_leg_id = v_leg1_id;
  reset role;
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected tenant2''s admin to see zero of tenant1''s reservation rows -- cross-tenant leak, found %', v_row_count;
  end if;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 5 new functions; authenticated has no direct INSERT/UPDATE/DELETE on vehicle_capacity_reservations'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('reserve_vehicle_capacity', 'consume_vehicle_capacity_reservation', 'release_vehicle_capacity_reservation', 'get_tenant_tracking_coverage', 'get_tenant_tracking_utilization_summary');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 5 new ATW-227 functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app'
    and grantee = 'authenticated'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and table_name = 'vehicle_capacity_reservations';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on vehicle_capacity_reservations, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real reserve/consume/release call captured a tenant-scoped app.audit_logs entry; the rejected attempts (viewer denial, capacity_exceeded, reservation_already_active, stale_version, invalid_transition, empty reason) are not counted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmecapacity');
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.vehicle_capacity_reservations' and action = 'reserve_vehicle_capacity';
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 reserve_vehicle_capacity audit events (leg1, leg2, leg3-try2, leg4-try2 -- not the idempotent replay, not the rejected attempts), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.vehicle_capacity_reservations' and action = 'consume_vehicle_capacity_reservation';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 consume_vehicle_capacity_reservation audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.vehicle_capacity_reservations' and action = 'release_vehicle_capacity_reservation';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 release_vehicle_capacity_reservation audit event, found %', v_count;
  end if;
end $$;

\echo 'advanced-tms-capacity-utilization.sql: ALL PASSED'
