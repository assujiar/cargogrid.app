-- Real, executable test evidence for ATW-228 (CG-S10-ATW-009, Prompt 228 Advanced
-- Milestone and Exception with Multi-Source Telemetry) -- run via `pnpm run db:test`
-- against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, an OPS:Create/Edit/View/Assign rep, an OPS:View-only viewer, a Supreme Admin, one active direct_device-eligible vehicle with an installed+active GPS device, a confirmed land-freight Shipment Order with leg1 (dispatched, real Jakarta/Bandung coordinates, a full geofence/route-deviation/no-signal tracking policy) and leg2 (still planned, for rebaseline), a current vehicle resource assignment, and a real API key for direct-device ingestion. A second, fully isolated tenant for cross-tenant checks.'
create temporary table met_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
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
  v_vehicle app.vehicle_operational_profiles;
  v_device app.gps_devices;
  v_key record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000060101', 'admin@acmemilestone.test'),
    ('00000000-0000-0000-0000-000000060102', 'rep@acmemilestone.test'),
    ('00000000-0000-0000-0000-000000060103', 'viewer@acmemilestone.test'),
    ('00000000-0000-0000-0000-000000060104', 'supreme@acmemilestone.test'),
    ('00000000-0000-0000-0000-000000060105', 'admin2@acmemilestone2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000060104', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmemilestone228', 'Acme Milestone Co', 'idem-acmemilestone228', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmemilestone228');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEMILE228-CO', 'Acme Milestone Co', 'tester');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE228-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000060101', 'admin@acmemilestone.test', 'Milestone Admin', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmemilestone.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000060101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000060102', 'rep@acmemilestone.test', 'Milestone Rep', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmemilestone.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000060103', 'viewer@acmemilestone.test', 'Milestone Viewer', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmemilestone.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Milestone Rep Role', 'full commercial + ops create/edit/view/assign', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000060102', '00000000-0000-0000-0000-000000060101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000060101', '00000000-0000-0000-0000-000000060104', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Milestone Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000060103', '00000000-0000-0000-0000-000000060101', 'tester');

  perform app.register_milestone_code('pickup_arrival', 'Pickup Arrival', 'pickup', true, false, false, '00000000-0000-0000-0000-000000060104', 'supreme');
  perform app.register_milestone_code('pickup_departure', 'Pickup Departure', 'pickup', true, false, false, '00000000-0000-0000-0000-000000060104', 'supreme');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-MS-A', 'Milestone Truck A', 'owned', 2000, 20, '00000000-0000-0000-0000-000000060101', 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, false, true, false, v_vehicle.record_version, '00000000-0000-0000-0000-000000060101', 'admin');

  -- ATW-246 hardening note: this literal was previously '868712345603001', coincidentally
  -- identical to the fixture IMEI advanced-tms-fleet-control-tower.sql/advanced-tms-wms-
  -- integrated-verification.sql also use for their own, unrelated tenants -- harmless before
  -- app.register_gps_device gained a real cross-tenant collision guard (this checkpoint's
  -- own migration 20260730360000), but a same-shared-database, order-dependent failure
  -- afterward. Changed to a value unique across every scripts/db-tests/*.sql fixture.
  select * into v_device from app.register_gps_device(v_tenant1, '868712345603101', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000060101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000060101', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle.id, 'initial install', '00000000-0000-0000-0000-000000060101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'installed', v_device.record_version, '00000000-0000-0000-0000-000000060101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'active', v_device.record_version, '00000000-0000-0000-0000-000000060101', 'admin');

  select * into v_key from app.create_api_key(v_tenant1, 'Milestone Gateway Key', '["OPS:Edit"]'::jsonb, null, null, '00000000-0000-0000-0000-000000060101', 'admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Milestone228 Co', 'Jane Milestone', 'jane@milestone228test.test', '0811',
    '00000000-0000-0000-0000-000000060102', v_team, '00000000-0000-0000-0000-000000060102', 'tester');
  select * into v_lead from app.leads where email = 'jane@milestone228test.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000060102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Milestone228 Co', 'MS228', '11.111.111.6-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 6', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000060102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Milestone Ops', 'Procurement Lead', 'jane@milestone228test.test', '0811', '00000000-0000-0000-0000-000000060102', v_team, '00000000-0000-0000-0000-000000060102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000060102', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Milestone228 test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000060102', v_team, '00000000-0000-0000-0000-000000060102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000060102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-MS228-1', 'Contoso Milestone228 Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000060101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000060101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000060102', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000060102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000060102', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000060102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000060102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Milestone228 lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000060102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000060102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000060102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Milestone Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000060102', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000060102', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000060102', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000060102', 'rep');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-milestone-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 2000, 2000, 40, 2000, 2000, 40, null, '00000000-0000-0000-0000-000000060102', 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000060102', 'rep');

  select * into v_leg1 from app.add_shipment_leg(v_shipment.id, 'idem-milestone-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000060102', 'rep');
  perform app.add_shipment_leg_stop(v_leg1.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), '00000000-0000-0000-0000-000000060102', 'rep');
  perform app.add_shipment_leg_stop(v_leg1.id, 2, 'delivery', 'Bandung Warehouse', null, 107.619123, -6.917464, now() + interval '1 day', '00000000-0000-0000-0000-000000060102', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg1.id, 500, 500, 8, '00000000-0000-0000-0000-000000060102', 'rep');

  select * into v_leg2 from app.add_shipment_leg(v_shipment.id, 'idem-milestone-leg2', 2, 'land', null, now() + interval '1 day', now() + interval '2 days', '00000000-0000-0000-0000-000000060102', 'rep');
  perform app.add_shipment_leg_stop(v_leg2.id, 1, 'pickup', 'Bandung Cross-dock', null, 107.619123, -6.917464, now() + interval '1 day', '00000000-0000-0000-0000-000000060102', 'rep');
  perform app.add_shipment_leg_stop(v_leg2.id, 2, 'delivery', 'Bandung Customer Site', null, 107.63, -6.9, now() + interval '2 days', '00000000-0000-0000-0000-000000060102', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg2.id, 10, 10, 1, '00000000-0000-0000-0000-000000060102', 'rep');

  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000060102', 'rep');
  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, '00000000-0000-0000-0000-000000060102', 'rep');

  select * into v_leg1 from app.transition_shipment_leg(v_leg1.id, 'dispatched', v_leg1.record_version, '00000000-0000-0000-0000-000000060102', 'rep');

  perform app.upsert_shipment_leg_tracking_policy(
    v_leg1.id, true, array['direct_device'], 'direct_device', array['direct_device'],
    300, 100, 30, 'leg_dispatch', 'leg_complete',
    jsonb_build_object(
      'enabled', true, 'radius_meters', 500, 'dwell_seconds_before_confirm', 60,
      'route_deviation', jsonb_build_object('enabled', true, 'corridor_width_meters', 1500, 'deviation_sustained_seconds', 120),
      'overdue_arrival_grace_minutes', 60
    ),
    true, 1800, '00000000-0000-0000-0000-000000060102', 'rep'
  );

  -- Tenant2: fully isolated, no vehicles/legs -- cross-tenant scope safety only.
  perform app.provision_tenant('acmemilestone2282', 'Acme Milestone Two', 'idem-acmemilestone2282', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmemilestone2282');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEMILE2282-CO', 'Acme Milestone Two', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000060105', 'admin2@acmemilestone2.test', 'Tenant2 Admin', (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEMILE2282-CO'), 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmemilestone2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000060105', 'tenant_admin', v_tenant2, null, 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'OPS create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000060105', '00000000-0000-0000-0000-000000060105', 'tester');

  insert into met_test_state (key, value) values
    ('tenant1_id', v_tenant1::text), ('tenant2_id', v_tenant2::text),
    ('shipment_order_id', v_shipment.id::text), ('leg1_id', v_leg1.id::text), ('leg2_id', v_leg2.id::text),
    ('vehicle_master_id', v_vehicle.vehicle_master_id::text), ('device_id', v_device.id::text), ('api_key', v_key.raw_key);
end $$;

\echo '>> real geofence dwell+confirm on the pickup stop (two ingested direct_device reports) creates exactly one pending pickup_arrival candidate backed by a real canonical telemetry event'
do $$
declare
  v_api_key text := (select value from met_test_state where key = 'api_key');
  v_device_id uuid := (select value::uuid from met_test_state where key = 'device_id');
  v_leg1_id uuid := (select value::uuid from met_test_state where key = 'leg1_id');
  v_candidate_count integer;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '1 minute')::text, 'longitude', 106.845599, 'latitude', -6.208763, 'speed_kmh', 0)),
    'test-gateway'
  );
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '3 minutes')::text, 'longitude', 106.845600, 'latitude', -6.208760, 'speed_kmh', 0)),
    'test-gateway'
  );

  select count(*) into v_candidate_count from app.shipment_milestone_candidates where shipment_leg_id = v_leg1_id and status = 'pending';
  if v_candidate_count <> 1 then
    raise exception 'assertion failed: expected exactly one pending milestone candidate after dwell-confirm, found %', v_candidate_count;
  end if;
end $$;

\echo '>> app.confirm_milestone_candidate: an OPS:View-only viewer is rejected; the rep''s real confirmation now carries real source_class/confidence/freshness provenance (direct_device carries no accuracy_meters, so confidence = 1.0 - 0.3 = 0.7, freshness = healthy, since the event was just ingested)'
do $$
declare
  v_leg1_id uuid := (select value::uuid from met_test_state where key = 'leg1_id');
  v_candidate_id uuid := (select id from app.shipment_milestone_candidates where shipment_leg_id = v_leg1_id and status = 'pending');
  v_event app.milestone_events;
begin
  begin
    perform app.confirm_milestone_candidate(v_candidate_id, '00000000-0000-0000-0000-000000060103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Create';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_event := app.confirm_milestone_candidate(v_candidate_id, '00000000-0000-0000-0000-000000060102', 'rep');
  if v_event.source_class is distinct from 'direct_device' or v_event.source_freshness_status is distinct from 'healthy' then
    raise exception 'assertion failed: expected source_class=direct_device, source_freshness_status=healthy, got %/%', v_event.source_class, v_event.source_freshness_status;
  end if;
  if v_event.source_confidence_score is distinct from 0.7 then
    raise exception 'assertion failed: expected source_confidence_score=0.7 (1.0 - 0.3 for missing accuracy_meters), got %', v_event.source_confidence_score;
  end if;
  if v_event.source_candidate_id is distinct from v_candidate_id then
    raise exception 'assertion failed: expected source_candidate_id to link back to the confirmed candidate';
  end if;
end $$;

\echo '>> a manually-filed milestone event carries honestly null provenance (never fabricated)'
do $$
declare
  v_shipment_id uuid := (select value::uuid from met_test_state where key = 'shipment_order_id');
  v_event app.milestone_events;
begin
  v_event := app.ingest_milestone_event(v_shipment_id, 'pickup_departure', now(), now(), null, 'manual', null, null, 'idem-manual-departure', '00000000-0000-0000-0000-000000060102', 'rep');
  if v_event.source_class is not null or v_event.source_confidence_score is not null or v_event.source_freshness_status is not null then
    raise exception 'assertion failed: expected null provenance for a manual event, got source_class=% confidence=% freshness=%', v_event.source_class, v_event.source_confidence_score, v_event.source_freshness_status;
  end if;
end $$;

\echo '>> app.confirm_exception_signal: a staged signal backed by the same real canonical telemetry event carries the identical real provenance; a signal with no backing event (this migration''s own tracking_health_no_signal, staged directly here) honestly carries null provenance'
do $$
declare
  v_tenant1 uuid := (select value::uuid from met_test_state where key = 'tenant1_id');
  v_shipment_id uuid := (select value::uuid from met_test_state where key = 'shipment_order_id');
  v_leg1_id uuid := (select value::uuid from met_test_state where key = 'leg1_id');
  v_canonical_event_id uuid;
  v_signal_id uuid;
  v_exception app.operational_exceptions;
begin
  select source_canonical_event_id into v_canonical_event_id from app.shipment_milestone_candidates where shipment_leg_id = v_leg1_id order by created_at desc limit 1;

  perform app.upsert_exception_signal(
    v_tenant1, v_shipment_id, v_leg1_id, 'route_deviation', 'delay', 'medium',
    v_canonical_event_id, null, 'test-authored route deviation signal', 'route_deviation:test-authored:' || now()::text
  );
  v_signal_id := (select id from app.shipment_exception_signals where shipment_leg_id = v_leg1_id and signal_type = 'route_deviation' and status = 'pending');

  v_exception := app.confirm_exception_signal(v_signal_id, '00000000-0000-0000-0000-000000060102', 'rep');
  if v_exception.source_class is distinct from 'direct_device' or v_exception.source_confidence_score is distinct from 0.7 then
    raise exception 'assertion failed: expected the resulting exception to carry the same real provenance as its backing canonical event, got source_class=% confidence=%', v_exception.source_class, v_exception.source_confidence_score;
  end if;
  if v_exception.source_signal_id is distinct from v_signal_id then
    raise exception 'assertion failed: expected source_signal_id to link back to the confirmed signal';
  end if;
end $$;

\echo '>> app.detect_shipment_leg_tracking_health_signals: a healthy, just-reported vehicle raises nothing; a backdated (offline) source health raises exactly one pending tracking_health_no_signal signal, deduplicated on a second scan; a fresh report auto-recovers (silently dismissed) it; confirming a fresh episode later yields an exception with honestly null provenance'
do $$
declare
  v_tenant1 uuid := (select value::uuid from met_test_state where key = 'tenant1_id');
  v_leg1_id uuid := (select value::uuid from met_test_state where key = 'leg1_id');
  v_vehicle_master_id uuid := (select value::uuid from met_test_state where key = 'vehicle_master_id');
  v_api_key text := (select value from met_test_state where key = 'api_key');
  v_device_id uuid := (select value::uuid from met_test_state where key = 'device_id');
  v_correlation_key text := 'tracking_health_no_signal:' || v_leg1_id;
  v_count integer;
  v_signal app.shipment_exception_signals;
  v_exception app.operational_exceptions;
begin
  v_count := app.detect_shipment_leg_tracking_health_signals(v_tenant1);
  if exists (select 1 from app.shipment_exception_signals where correlation_key = v_correlation_key and status = 'pending') then
    raise exception 'assertion failed: expected no tracking_health_no_signal signal while the vehicle is genuinely healthy';
  end if;

  update app.vehicle_source_health set last_seen_received_at = now() - interval '20 minutes', last_seen_event_at = now() - interval '20 minutes'
    where vehicle_master_id = v_vehicle_master_id and source_type = 'direct_device';

  v_count := app.detect_shipment_leg_tracking_health_signals(v_tenant1);
  select * into v_signal from app.shipment_exception_signals where correlation_key = v_correlation_key and status = 'pending';
  if v_signal.id is null or v_signal.exception_type <> 'delay' or v_signal.source_canonical_event_id is not null then
    raise exception 'assertion failed: expected exactly one pending tracking_health_no_signal signal with no backing canonical event, got %', v_signal;
  end if;

  perform app.detect_shipment_leg_tracking_health_signals(v_tenant1);
  select count(*) into v_count from app.shipment_exception_signals where correlation_key = v_correlation_key and status = 'pending';
  if v_count <> 1 then
    raise exception 'assertion failed: expected a re-scan while still offline to refresh, never duplicate, the one pending signal, found %', v_count;
  end if;

  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '10 minutes')::text, 'longitude', 106.85, 'latitude', -6.25, 'speed_kmh', 40)),
    'test-gateway'
  );
  perform app.detect_shipment_leg_tracking_health_signals(v_tenant1);
  select * into v_signal from app.shipment_exception_signals where correlation_key = v_correlation_key order by created_at desc limit 1;
  if v_signal.status <> 'dismissed' or v_signal.review_note <> 'auto_recovered_tracking_restored' then
    raise exception 'assertion failed: expected the recovered leg''s own pending signal to be silently auto-dismissed, got status=% note=%', v_signal.status, v_signal.review_note;
  end if;

  -- A fresh episode: go offline again, detect, confirm -- honestly null provenance.
  update app.vehicle_source_health set last_seen_received_at = now() - interval '20 minutes', last_seen_event_at = now() - interval '20 minutes'
    where vehicle_master_id = v_vehicle_master_id and source_type = 'direct_device';
  perform app.detect_shipment_leg_tracking_health_signals(v_tenant1);
  select id into v_signal from app.shipment_exception_signals where correlation_key = v_correlation_key and status = 'pending';

  v_exception := app.confirm_exception_signal(v_signal.id, '00000000-0000-0000-0000-000000060102', 'rep');
  if v_exception.source_class is not null or v_exception.source_confidence_score is not null then
    raise exception 'assertion failed: expected honestly null provenance for a tracking_health_no_signal exception (no backing telemetry event), got source_class=% confidence=%', v_exception.source_class, v_exception.source_confidence_score;
  end if;

  -- Restore health for the remaining scenarios below.
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '11 minutes')::text, 'longitude', 106.85, 'latitude', -6.25, 'speed_kmh', 40)),
    'test-gateway'
  );
end $$;

\echo '>> app.evaluate_leg_no_signal_escalation (ATW-225, fixed at ATW-228): a session running long but reporting fresh telemetry is never wrongly ended; a session both old and genuinely silent is correctly ended, raising a real operational exception'
do $$
declare
  v_leg1_id uuid := (select value::uuid from met_test_state where key = 'leg1_id');
  v_vehicle_master_id uuid := (select value::uuid from met_test_state where key = 'vehicle_master_id');
  v_device_id uuid := (select value::uuid from met_test_state where key = 'device_id');
  v_session app.shipment_leg_tracking_sessions;
  v_exception_count integer;
begin
  v_session := app.start_leg_tracking_session(v_leg1_id, 'direct_device', 'vehicle', v_vehicle_master_id, v_device_id, '00000000-0000-0000-0000-000000060102', 'rep');

  -- Long-running (40 min > the leg's own 1800s/30min threshold) but genuinely
  -- healthy (last_seen_received_at just refreshed above) -- must NOT be ended.
  update app.shipment_leg_tracking_sessions set started_at = now() - interval '40 minutes' where id = v_session.id;
  v_session := app.evaluate_leg_no_signal_escalation(v_leg1_id, '00000000-0000-0000-0000-000000060102', 'rep');
  if v_session.is_current is distinct from true or v_session.status <> 'active' then
    raise exception 'assertion failed: expected a long-running-but-healthy session to remain active (the real ATW-225 defect this checkpoint fixes), got is_current=% status=%', v_session.is_current, v_session.status;
  end if;

  -- Now genuinely silent too -- must be ended, with a real exception raised.
  update app.vehicle_source_health set last_seen_received_at = now() - interval '40 minutes', last_seen_event_at = now() - interval '40 minutes'
    where vehicle_master_id = v_vehicle_master_id and source_type = 'direct_device';
  v_session := app.evaluate_leg_no_signal_escalation(v_leg1_id, '00000000-0000-0000-0000-000000060102', 'rep');
  if v_session.is_current is distinct from false or v_session.status <> 'ended' or v_session.end_reason <> 'stale_source' then
    raise exception 'assertion failed: expected a genuinely stale session to be ended, got is_current=% status=% end_reason=%', v_session.is_current, v_session.status, v_session.end_reason;
  end if;

  select count(*) into v_exception_count from app.operational_exceptions where correlation_key = 'leg-no-signal:' || v_leg1_id::text;
  if v_exception_count <> 1 then
    raise exception 'assertion failed: expected exactly one real operational exception for the genuinely stale session, found %', v_exception_count;
  end if;

  -- Restore health for the ETA scenarios below.
  update app.vehicle_source_health set last_seen_received_at = now(), last_seen_event_at = now()
    where vehicle_master_id = v_vehicle_master_id and source_type = 'direct_device';
end $$;

\echo '>> app.get_shipment_leg_eta_projection: a healthy live position yields a real computable ETA with a positive remaining distance and the correct downstream leg count; leg2 (still planned, not active) is honestly uncomputable; cross-tenant actor rejected'
do $$
declare
  v_leg1_id uuid := (select value::uuid from met_test_state where key = 'leg1_id');
  v_leg2_id uuid := (select value::uuid from met_test_state where key = 'leg2_id');
  v_tenant2_admin uuid := '00000000-0000-0000-0000-000000060105';
  v_projection app.shipment_leg_eta_projection;
begin
  v_projection := app.get_shipment_leg_eta_projection(v_leg1_id, '00000000-0000-0000-0000-000000060102');
  if v_projection.computable is distinct from true or v_projection.remaining_distance_km is null or v_projection.remaining_distance_km <= 0 or v_projection.estimated_arrival_at is null then
    raise exception 'assertion failed: expected a real computable ETA for leg1, got %', v_projection;
  end if;
  if v_projection.downstream_leg_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 downstream leg (leg2), got %', v_projection.downstream_leg_count;
  end if;

  v_projection := app.get_shipment_leg_eta_projection(v_leg2_id, '00000000-0000-0000-0000-000000060102');
  if v_projection.computable is distinct from false or v_projection.reason <> 'leg_not_active' then
    raise exception 'assertion failed: expected leg2 (still planned) to be honestly uncomputable with reason leg_not_active, got computable=% reason=%', v_projection.computable, v_projection.reason;
  end if;

  begin
    -- ISS-2026-146: tenant2's admin (acmemilestone2282) holds no membership in acmemilestone228, so app.get_shipment_leg_eta_projection
    -- now collapses that zero-membership case into its own generic
    -- leg_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.get_shipment_leg_eta_projection(v_leg1_id, v_tenant2_admin);
    raise exception 'assertion failed: expected leg_not_found -- tenant2''s admin holds no grant at all in tenant1';
  exception
    when others then
      if sqlerrm not like 'leg_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.get_shipment_leg_eta_projection: a stale (offline) live position is honestly uncomputable (position_stale), never a fabricated estimate'
do $$
declare
  v_leg1_id uuid := (select value::uuid from met_test_state where key = 'leg1_id');
  v_vehicle_master_id uuid := (select value::uuid from met_test_state where key = 'vehicle_master_id');
  v_projection app.shipment_leg_eta_projection;
begin
  update app.vehicle_current_positions set received_at = now() - interval '20 minutes' where vehicle_master_id = v_vehicle_master_id;
  v_projection := app.get_shipment_leg_eta_projection(v_leg1_id, '00000000-0000-0000-0000-000000060102');
  if v_projection.computable is distinct from false or v_projection.reason <> 'position_stale' then
    raise exception 'assertion failed: expected an offline position to be honestly uncomputable with reason position_stale, got computable=% reason=%', v_projection.computable, v_projection.reason;
  end if;
  update app.vehicle_current_positions set received_at = now() where vehicle_master_id = v_vehicle_master_id;
end $$;

\echo '>> app.rebaseline_shipment_leg_schedule: an OPS:View-only viewer is rejected; an empty reason, an inverted schedule, and a stale expected_version are all rejected before ever mutating the leg; a valid rebaseline on the still-planned leg2 updates its own schedule with a full audit trail; a dispatched leg (leg1) may never be rebaselined'
do $$
declare
  v_leg1_id uuid := (select value::uuid from met_test_state where key = 'leg1_id');
  v_leg2_id uuid := (select value::uuid from met_test_state where key = 'leg2_id');
  v_leg2_version integer := (select record_version from app.shipment_legs where id = v_leg2_id);
  v_new_departure timestamptz := now() + interval '3 days';
  v_new_arrival timestamptz := now() + interval '4 days';
  v_leg app.shipment_legs;
  v_audit_count integer;
begin
  begin
    perform app.rebaseline_shipment_leg_schedule(v_leg2_id, v_new_departure, v_new_arrival, 'customer requested delay', v_leg2_version, '00000000-0000-0000-0000-000000060103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.rebaseline_shipment_leg_schedule(v_leg2_id, v_new_departure, v_new_arrival, '', v_leg2_version, '00000000-0000-0000-0000-000000060102', 'rep');
    raise exception 'assertion failed: expected reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  begin
    perform app.rebaseline_shipment_leg_schedule(v_leg2_id, v_new_arrival, v_new_departure, 'inverted schedule', v_leg2_version, '00000000-0000-0000-0000-000000060102', 'rep');
    raise exception 'assertion failed: expected invalid_schedule when new arrival is before new departure';
  exception
    when others then
      if sqlerrm not like 'invalid_schedule%' then raise; end if;
  end;

  begin
    perform app.rebaseline_shipment_leg_schedule(v_leg2_id, v_new_departure, v_new_arrival, 'stale attempt', v_leg2_version + 99, '00000000-0000-0000-0000-000000060102', 'rep');
    raise exception 'assertion failed: expected stale_version for a wrong expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_leg := app.rebaseline_shipment_leg_schedule(v_leg2_id, v_new_departure, v_new_arrival, 'customer requested delay', v_leg2_version, '00000000-0000-0000-0000-000000060102', 'rep');
  if v_leg.planned_departure_at is distinct from v_new_departure or v_leg.planned_arrival_at is distinct from v_new_arrival or v_leg.record_version <> v_leg2_version + 1 then
    raise exception 'assertion failed: expected the rebaseline to update the schedule and bump record_version, got %', v_leg;
  end if;

  select count(*) into v_audit_count from app.audit_logs where resource_type = 'app.shipment_legs' and action = 'rebaseline_shipment_leg_schedule' and resource_id = v_leg2_id;
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly one rebaseline_shipment_leg_schedule audit event, found %', v_audit_count;
  end if;

  begin
    perform app.rebaseline_shipment_leg_schedule(v_leg1_id, v_new_departure, v_new_arrival, 'attempt on a dispatched leg', (select record_version from app.shipment_legs where id = v_leg1_id), '00000000-0000-0000-0000-000000060102', 'rep');
    raise exception 'assertion failed: expected leg_not_unstarted -- leg1 is dispatched, not planned';
  exception
    when others then
      if sqlerrm not like 'leg_not_unstarted%' then raise; end if;
  end;
end $$;

\echo '>> widened app.lookup_public_shipment_tracking: a customer_visible=true policy with a real, computable ETA yields a real live_eta_status/live_eta_at; every prior output column (lookup_status=ok, vehicle position) is unaffected'
do $$
declare
  v_shipment_id uuid := (select value::uuid from met_test_state where key = 'shipment_order_id');
  v_issue record;
  v_result record;
begin
  select * into v_issue from app.issue_shipment_tracking_token(v_shipment_id, 24, '00000000-0000-0000-0000-000000060102', 'rep');
  select * into v_result from app.lookup_public_shipment_tracking(v_issue.raw_token, 'met-client-visible');

  if v_result.lookup_status <> 'ok' or v_result.vehicle_position_geojson is null then
    raise exception 'assertion failed: expected an unaffected, real sanitized vehicle position, got %', v_result;
  end if;
  if v_result.live_eta_status is null or v_result.live_eta_status not in ('on_time', 'delayed') or v_result.live_eta_at is null then
    raise exception 'assertion failed: expected a real, computable live_eta_status/live_eta_at, got status=% at=%', v_result.live_eta_status, v_result.live_eta_at;
  end if;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any internal/service_role-only ATW-228 function; authenticated has EXECUTE on the two new authenticated RPCs; app.lookup_public_shipment_tracking keeps its own exact anon/authenticated/service_role grant after being dropped and recreated'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('evaluate_telemetry_confidence_and_freshness', 'detect_shipment_leg_tracking_health_signals', '_compute_shipment_leg_eta', 'get_shipment_leg_eta_projection', 'rebaseline_shipment_leg_schedule');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across the new/internal ATW-228 functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'authenticated'
    and routine_name in ('get_shipment_leg_eta_projection', 'rebaseline_shipment_leg_schedule');
  if v_count <> 2 then
    raise exception 'assertion failed: expected authenticated EXECUTE on both new authenticated RPCs, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon' and routine_name = 'lookup_public_shipment_tracking';
  if v_count <> 1 then
    raise exception 'assertion failed: expected app.lookup_public_shipment_tracking to keep its own exact anon grant after DROP+CREATE, found %', v_count;
  end if;
end $$;

\echo 'advanced-tms-milestone-exception-telemetry.sql: ALL PASSED'
