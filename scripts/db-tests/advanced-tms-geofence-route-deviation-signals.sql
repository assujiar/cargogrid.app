-- Real, executable test evidence for ATW-226G (CG-S10-ATW-007's family, Prompt 226
-- decomposition "Geofence, route deviation, milestone candidate, and exception
-- signals") -- run via `pnpm run db:test` against a real, disposable Postgres database.
--
-- Exercises the widened app.arbitrate_and_project_vehicle_position (which now also
-- calls app.evaluate_geofence_and_deviation_signals) end to end through the real
-- app.ingest_direct_device_telemetry_batch RPC -- never a direct evaluator call, except
-- where explicitly noted (the conflict-override and overdue-arrival scenarios, which
-- need a fixture row no live telemetry sequence can otherwise produce quickly).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, one confirmed land-freight Shipment Order with an assigned vehicle, an installed direct_device, a two-stop leg (real pickup/delivery coordinates), an active tracking policy with a geofence_policy, and four registered milestone codes'
create temporary table geo_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
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
  v_leg app.shipment_legs;
  v_pickup_stop app.shipment_leg_stops;
  v_delivery_stop app.shipment_leg_stops;
  v_overdue_stop app.shipment_leg_stops;
  v_vehicle app.vehicle_operational_profiles;
  v_key record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000046101', 'admin@acmegeofence.test'),
    ('00000000-0000-0000-0000-000000046102', 'noaccess@acmegeofence.test'),
    ('00000000-0000-0000-0000-000000046103', 'supreme@acmegeofence.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000046103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmegeofence', 'Acme Geofence Co', 'idem-acmegeofence', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmegeofence');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEGEOFENCE-CO', 'Acme Geofence Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEGEOFENCE-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000046101', 'admin@acmegeofence.test', 'Geo Admin', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmegeofence.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000046101', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000046102', 'noaccess@acmegeofence.test', 'No Access', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noaccess@acmegeofence.test'), 'active', 'onboarded', 'tester');

  v_edit_role := (app.create_role(v_tenant1, 'Geofence Editor', 'full commercial + ops', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000046101', '00000000-0000-0000-0000-000000046103', 'tester');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-GEO-A', 'Geo Truck A', 'owned', 2000, 20, '00000000-0000-0000-0000-000000046101', 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, true, true, true, v_vehicle.record_version, '00000000-0000-0000-0000-000000046101', 'admin');

  perform app.register_milestone_code('pickup_arrival', 'Pickup Arrival', 'pickup', true, false, false, '00000000-0000-0000-0000-000000046103', 'supreme');
  perform app.register_milestone_code('pickup_departure', 'Pickup Departure', 'pickup', true, false, false, '00000000-0000-0000-0000-000000046103', 'supreme');
  perform app.register_milestone_code('delivery_arrival', 'Delivery Arrival', 'delivery', true, false, false, '00000000-0000-0000-0000-000000046103', 'supreme');
  perform app.register_milestone_code('delivery_departure', 'Delivery Departure', 'delivery', true, false, true, '00000000-0000-0000-0000-000000046103', 'supreme');

  -- Full commercial-to-shipment pipeline (the vehicle identity established above)
  perform app.capture_lead(v_tenant1, 'manual', null, 'Geotrack Co', 'Jane Geo', 'jane@geotracktest.test', '0811',
    '00000000-0000-0000-0000-000000046101', v_team_a, '00000000-0000-0000-0000-000000046101', 'tester');
  select * into v_lead from app.leads where email = 'jane@geotracktest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000046101', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Geotrack Co', 'CTC226G', '11.111.111.7-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 7', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000046101', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Geo Ops', 'Procurement Lead', 'jane@geotracktest.test', '0811', '00000000-0000-0000-0000-000000046101', v_team_a, '00000000-0000-0000-0000-000000046101', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000046101', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Geotrack test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000046101', v_team_a, '00000000-0000-0000-0000-000000046101', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000046101', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CTC226G-1', 'Contoso Geotrack Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000046101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000046101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000046101', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000046101', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000046101', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000046101', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000046101', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Geo tracking lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000046101', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000046101', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000046101', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Geo Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000046101', 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000046101', 'admin');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000046101', 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000046101', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-geo-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 1000, 1000, 16, 1000, 1000, 16, null, '00000000-0000-0000-0000-000000046101', 'admin'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000046101', 'admin');

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-geo-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000046101', 'admin');
  -- Real coordinates: pickup = Jakarta (-6.208763, 106.845599), delivery = Bandung
  -- (-6.917464, 107.619123) -- ~130km apart, a realistic land-freight lane.
  select * into v_pickup_stop from app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), '00000000-0000-0000-0000-000000046101', 'admin');
  select * into v_delivery_stop from app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bandung Warehouse', null, 107.619123, -6.917464, now() + interval '1 day', '00000000-0000-0000-0000-000000046101', 'admin');
  -- A third stop, never approached by any telemetry report in this file --
  -- app.add_shipment_leg_stop only accepts new stops while the leg is still 'planned', so
  -- this must be added before the leg is dispatched below; the overdue-geofence-arrival
  -- test near the end of this file reads it back by its own stable id, never re-adds it.
  -- Its own coordinates are deliberately placed ON the direct pickup-delivery line
  -- (60% of the way from pickup to delivery, by linear interpolation) rather than off to
  -- one side -- app.evaluate_route_deviation builds its own reference line from every
  -- stop's location_geog in stop_sequence order (pickup -> delivery -> this stop), so an
  -- off-line placement here would silently add a second, non-collinear corridor segment
  -- and invalidate every off-corridor distance this file's own route-deviation tests
  -- below were computed against; a collinear placement keeps the reference geometry
  -- unchanged in effect. It is also >10km from every coordinate the geofence/route-
  -- deviation tests below ever report at, so it is never entered by any of them --
  -- confirmed genuinely unapproached for the overdue-arrival test.
  select * into v_overdue_stop from app.add_shipment_leg_stop(v_leg.id, 3, 'transfer', 'Purwakarta Transfer Point', null, 107.309713, -6.633984, now() - interval '3 hours', '00000000-0000-0000-0000-000000046101', 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 1000, 1000, 16, '00000000-0000-0000-0000-000000046101', 'admin');
  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000046101', 'admin');

  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, '00000000-0000-0000-0000-000000046101', 'admin');

  -- app.evaluate_geofence_and_deviation_signals only resolves a leg whose own leg_status
  -- is dispatched/in_transit (design note: the "currently executing" leg) -- dispatch it
  -- for real via ATW-221's own state machine, not left at its default 'planned'.
  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'dispatched', v_leg.record_version, '00000000-0000-0000-0000-000000046101', 'admin');

  perform app.upsert_shipment_leg_tracking_policy(
    v_leg.id, true, array['direct_device'], 'direct_device', array['direct_device'],
    300, 100, 30, 'leg_dispatch', 'leg_complete',
    jsonb_build_object(
      'enabled', true, 'radius_meters', 500, 'dwell_seconds_before_confirm', 60,
      'route_deviation', jsonb_build_object('enabled', true, 'corridor_width_meters', 1500, 'deviation_sustained_seconds', 120),
      'overdue_arrival_grace_minutes', 60
    ),
    true, 3600, '00000000-0000-0000-0000-000000046101', 'admin'
  );

  -- Real direct_device path -- ATW-226B/226D's own already-proven installation flow,
  -- reused verbatim (identical to 226F's own fixture) rather than reinvented.
  declare
    v_device app.gps_devices;
    v_assignment_id uuid;
    v_doc_draft app.config_versions;
    v_clean_file uuid;
  begin
    select * into v_device from app.register_gps_device(v_tenant1, '868712345602001', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000046101', 'admin');
    select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000046101', 'admin');
    perform app.assign_device_to_vehicle(v_device.id, v_vehicle.id, 'geo fixture', '00000000-0000-0000-0000-000000046101', 'admin');
    v_assignment_id := (select id from app.device_vehicle_assignments where device_id = v_device.id and is_current);
    perform app.register_document_type('gps_device_installation', 'GPS Device Installation Evidence', 'DOC', '00000000-0000-0000-0000-000000046103', 'supreme');
    v_doc_draft := app.create_config_draft('document:gps_device_installation', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000046101', 'admin');
    perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/jpeg', 'application/pdf')),
      jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
      jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
      jsonb_build_object('key', 'default_classification', 'value', 'internal'),
      jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
    ), '00000000-0000-0000-0000-000000046101', 'admin');
    perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000046101', now(), 'admin');
    v_clean_file := (app.initiate_file_upload(
      v_tenant1, 'gps_device_installation', 'gps_device', v_device.id, 'install-photo.jpg', 'image/jpeg', 40960, null, false, null, '{}'::uuid[], null, 'idem-geo-install', '00000000-0000-0000-0000-000000046101', 'admin'
    )).id;
    perform app.record_file_scan_result(v_clean_file, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000046101', 'admin');
    perform app.record_gps_device_installation(v_assignment_id, v_clean_file, 'Budi Teknisi', 'installed under dashboard', v_device.record_version, '00000000-0000-0000-0000-000000046101', 'admin');

    select * into v_key from app.create_api_key(v_tenant1, 'Geo Gateway Key', '["OPS:Edit"]'::jsonb, null, null, '00000000-0000-0000-0000-000000046101', 'admin');

    insert into geo_test_state (key, value) values ('device_id', v_device.id::text), ('api_key', v_key.raw_key);
  end;

  insert into geo_test_state (key, value) values
    ('tenant_id', v_tenant1::text),
    ('vehicle_master_id', v_vehicle.vehicle_master_id::text),
    ('shipment_order_id', v_shipment.id::text),
    ('shipment_leg_id', v_leg.id::text),
    ('pickup_stop_id', v_pickup_stop.id::text),
    ('delivery_stop_id', v_delivery_stop.id::text),
    ('overdue_stop_id', v_overdue_stop.id::text),
    ('admin_actor_id', '00000000-0000-0000-0000-000000046101'),
    ('noaccess_actor_id', '00000000-0000-0000-0000-000000046102');
end $$;

\echo '>> geofence entry: a report inside the pickup radius creates a pending-dwell state row; no candidate yet'
do $$
declare
  v_device_id uuid := (select value::uuid from geo_test_state where key = 'device_id');
  v_api_key text := (select value from geo_test_state where key = 'api_key');
  v_pickup_stop_id uuid := (select value::uuid from geo_test_state where key = 'pickup_stop_id');
  v_state record;
  v_candidate_count integer;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object(
      'report_type', 'location', 'event_at', (now() + interval '1 minute')::text,
      'longitude', 106.845599, 'latitude', -6.208763, 'speed_kmh', 0
    )),
    'test-gateway'
  );

  select * into v_state from app.shipment_leg_stop_geofence_states where shipment_leg_stop_id = v_pickup_stop_id;
  if v_state.state is distinct from 'entered_pending_dwell' or v_state.confirmed_at is not null then
    raise exception 'assertion failed: expected entered_pending_dwell with no confirmed_at, got state=% confirmed_at=%', v_state.state, v_state.confirmed_at;
  end if;

  select count(*) into v_candidate_count from app.shipment_milestone_candidates;
  if v_candidate_count <> 0 then
    raise exception 'assertion failed: expected zero milestone candidates before dwell confirms, found %', v_candidate_count;
  end if;
end $$;

\echo '>> geofence dwell confirm: a second report still inside, event_at >= first_entered_at + dwell_seconds_before_confirm, confirms the stop and creates exactly one pending pickup_arrival candidate'
do $$
declare
  v_device_id uuid := (select value::uuid from geo_test_state where key = 'device_id');
  v_api_key text := (select value from geo_test_state where key = 'api_key');
  v_pickup_stop_id uuid := (select value::uuid from geo_test_state where key = 'pickup_stop_id');
  v_state record;
  v_candidate app.shipment_milestone_candidates;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object(
      'report_type', 'location', 'event_at', (now() + interval '3 minutes')::text,
      'longitude', 106.845600, 'latitude', -6.208760, 'speed_kmh', 0
    )),
    'test-gateway'
  );

  select * into v_state from app.shipment_leg_stop_geofence_states where shipment_leg_stop_id = v_pickup_stop_id;
  if v_state.state is distinct from 'confirmed_inside' or v_state.confirmed_at is null then
    raise exception 'assertion failed: expected confirmed_inside with confirmed_at set, got state=% confirmed_at=%', v_state.state, v_state.confirmed_at;
  end if;

  select * into v_candidate from app.shipment_milestone_candidates where shipment_leg_stop_id = v_pickup_stop_id and milestone_code = 'pickup_arrival';
  if v_candidate.id is null or v_candidate.status <> 'pending' then
    raise exception 'assertion failed: expected exactly one pending pickup_arrival candidate, got %', v_candidate;
  end if;
  if v_candidate.dedup_key <> 'geofence_arrival:' || v_pickup_stop_id::text then
    raise exception 'assertion failed: unexpected dedup_key %', v_candidate.dedup_key;
  end if;

  insert into geo_test_state (key, value) values ('pickup_arrival_candidate_id', v_candidate.id::text);
end $$;

\echo '>> app.confirm_milestone_candidate: unauthorized actor (no OPS:Create) is rejected; authorized actor produces a real app.milestone_events row; re-confirm raises milestone_candidate_not_pending'
do $$
declare
  v_candidate_id uuid := (select value::uuid from geo_test_state where key = 'pickup_arrival_candidate_id');
  v_admin uuid := (select value::uuid from geo_test_state where key = 'admin_actor_id');
  v_noaccess uuid := (select value::uuid from geo_test_state where key = 'noaccess_actor_id');
  v_event app.milestone_events;
  v_rejected boolean := false;
begin
  begin
    perform app.confirm_milestone_candidate(v_candidate_id, v_noaccess, 'noaccess');
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected an unauthorized actor to be rejected with insufficient_authority';
  end if;

  v_event := app.confirm_milestone_candidate(v_candidate_id, v_admin, 'admin');
  if v_event.milestone_code <> 'pickup_arrival' or v_event.source <> 'system' or v_event.reason <> 'confirmed_geofence_candidate' then
    raise exception 'assertion failed: unexpected confirmed milestone_events row %', v_event;
  end if;
  if v_event.idempotency_key <> 'milestone_candidate:' || v_candidate_id::text then
    raise exception 'assertion failed: unexpected idempotency_key %', v_event.idempotency_key;
  end if;

  if (select status from app.shipment_milestone_candidates where id = v_candidate_id) <> 'confirmed'
     or (select resulting_milestone_event_id from app.shipment_milestone_candidates where id = v_candidate_id) <> v_event.id then
    raise exception 'assertion failed: expected the candidate row to be marked confirmed with resulting_milestone_event_id set';
  end if;

  v_rejected := false;
  begin
    perform app.confirm_milestone_candidate(v_candidate_id, v_admin, 'admin');
  exception
    when others then
      if sqlerrm like 'milestone_candidate_not_pending%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected a re-confirm of an already-confirmed candidate to raise milestone_candidate_not_pending';
  end if;
end $$;

\echo '>> geofence exit: a report far outside the pickup radius exits the pickup stop and creates a pending pickup_departure candidate'
do $$
declare
  v_device_id uuid := (select value::uuid from geo_test_state where key = 'device_id');
  v_api_key text := (select value from geo_test_state where key = 'api_key');
  v_pickup_stop_id uuid := (select value::uuid from geo_test_state where key = 'pickup_stop_id');
  v_state record;
  v_candidate app.shipment_milestone_candidates;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object(
      'report_type', 'location', 'event_at', (now() + interval '65 minutes')::text,
      'longitude', 106.850, 'latitude', -6.205, 'speed_kmh', 20
    )),
    'test-gateway'
  );

  select * into v_state from app.shipment_leg_stop_geofence_states where shipment_leg_stop_id = v_pickup_stop_id;
  if v_state.state is distinct from 'exited' then
    raise exception 'assertion failed: expected the pickup stop to be exited, got %', v_state.state;
  end if;

  select * into v_candidate from app.shipment_milestone_candidates where shipment_leg_stop_id = v_pickup_stop_id and milestone_code = 'pickup_departure';
  if v_candidate.id is null or v_candidate.status <> 'pending' then
    raise exception 'assertion failed: expected exactly one pending pickup_departure candidate, got %', v_candidate;
  end if;

  insert into geo_test_state (key, value) values ('pickup_departure_candidate_id', v_candidate.id::text);
end $$;

\echo '>> app.dismiss_milestone_candidate: dismisses the departure candidate without creating any app.milestone_events row; re-dismiss raises milestone_candidate_not_pending'
do $$
declare
  v_candidate_id uuid := (select value::uuid from geo_test_state where key = 'pickup_departure_candidate_id');
  v_admin uuid := (select value::uuid from geo_test_state where key = 'admin_actor_id');
  v_before_events integer;
  v_after_events integer;
  v_candidate app.shipment_milestone_candidates;
  v_rejected boolean := false;
begin
  select count(*) into v_before_events from app.milestone_events where milestone_code = 'pickup_departure';

  v_candidate := app.dismiss_milestone_candidate(v_candidate_id, v_admin, 'admin', 'false positive, driver was parked nearby');

  if v_candidate.status <> 'dismissed' or v_candidate.review_note <> 'false positive, driver was parked nearby' or v_candidate.resulting_milestone_event_id is not null then
    raise exception 'assertion failed: unexpected dismissed candidate row %', v_candidate;
  end if;

  select count(*) into v_after_events from app.milestone_events where milestone_code = 'pickup_departure';
  if v_after_events <> v_before_events then
    raise exception 'assertion failed: expected dismiss to never create a real milestone_events row, count moved from % to %', v_before_events, v_after_events;
  end if;

  begin
    perform app.dismiss_milestone_candidate(v_candidate_id, v_admin, 'admin', 'again');
  exception
    when others then
      if sqlerrm like 'milestone_candidate_not_pending%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected a re-dismiss of an already-dismissed candidate to raise milestone_candidate_not_pending';
  end if;
end $$;

\echo '>> delivery stop arrival+dwell+departure: the same dwell state machine reused for the second stop, ending with a confirmed terminal delivery_departure milestone'
do $$
declare
  v_device_id uuid := (select value::uuid from geo_test_state where key = 'device_id');
  v_api_key text := (select value from geo_test_state where key = 'api_key');
  v_delivery_stop_id uuid := (select value::uuid from geo_test_state where key = 'delivery_stop_id');
  v_admin uuid := (select value::uuid from geo_test_state where key = 'admin_actor_id');
  v_state record;
  v_arrival_candidate app.shipment_milestone_candidates;
  v_departure_candidate app.shipment_milestone_candidates;
  v_arrival_event app.milestone_events;
  v_departure_event app.milestone_events;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object(
      'report_type', 'location', 'event_at', (now() + interval '156 minutes')::text,
      'longitude', 107.619123, 'latitude', -6.917464, 'speed_kmh', 80
    )),
    'test-gateway'
  );
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object(
      'report_type', 'location', 'event_at', (now() + interval '158 minutes')::text,
      'longitude', 107.619120, 'latitude', -6.917460, 'speed_kmh', 0
    )),
    'test-gateway'
  );

  select * into v_state from app.shipment_leg_stop_geofence_states where shipment_leg_stop_id = v_delivery_stop_id;
  if v_state.state is distinct from 'confirmed_inside' then
    raise exception 'assertion failed: expected the delivery stop to be confirmed_inside, got %', v_state.state;
  end if;

  select * into v_arrival_candidate from app.shipment_milestone_candidates where shipment_leg_stop_id = v_delivery_stop_id and milestone_code = 'delivery_arrival';
  if v_arrival_candidate.id is null then
    raise exception 'assertion failed: expected a pending delivery_arrival candidate';
  end if;
  v_arrival_event := app.confirm_milestone_candidate(v_arrival_candidate.id, v_admin, 'admin');
  if v_arrival_event.milestone_code <> 'delivery_arrival' then
    raise exception 'assertion failed: unexpected confirmed event %', v_arrival_event;
  end if;

  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object(
      'report_type', 'location', 'event_at', (now() + interval '256 minutes')::text,
      'longitude', 106.845599, 'latitude', -6.208763, 'speed_kmh', 80
    )),
    'test-gateway'
  );

  select * into v_state from app.shipment_leg_stop_geofence_states where shipment_leg_stop_id = v_delivery_stop_id;
  if v_state.state is distinct from 'exited' then
    raise exception 'assertion failed: expected the delivery stop to be exited, got %', v_state.state;
  end if;

  select * into v_departure_candidate from app.shipment_milestone_candidates where shipment_leg_stop_id = v_delivery_stop_id and milestone_code = 'delivery_departure';
  if v_departure_candidate.id is null then
    raise exception 'assertion failed: expected a pending delivery_departure candidate';
  end if;
  v_departure_event := app.confirm_milestone_candidate(v_departure_candidate.id, v_admin, 'admin');
  if v_departure_event.milestone_code <> 'delivery_departure' then
    raise exception 'assertion failed: unexpected confirmed terminal event %', v_departure_event;
  end if;

  insert into geo_test_state (key, value) values ('terminal_event_time', v_departure_event.event_time::text);
end $$;

\echo '>> milestone-candidate conflict: a synthetic candidate dated after the already-confirmed terminal event is rejected by default and only succeeds with p_override_conflict'
do $$
declare
  v_tenant1 uuid := (select value::uuid from geo_test_state where key = 'tenant_id');
  v_shipment_order_id uuid := (select value::uuid from geo_test_state where key = 'shipment_order_id');
  v_leg_id uuid := (select value::uuid from geo_test_state where key = 'shipment_leg_id');
  v_pickup_stop_id uuid := (select value::uuid from geo_test_state where key = 'pickup_stop_id');
  v_terminal_event_time timestamptz := (select value::timestamptz from geo_test_state where key = 'terminal_event_time');
  v_admin uuid := (select value::uuid from geo_test_state where key = 'admin_actor_id');
  v_candidate_id uuid;
  v_rejected boolean := false;
  v_event app.milestone_events;
begin
  insert into app.shipment_milestone_candidates (
    tenant_id, shipment_order_id, shipment_leg_id, shipment_leg_stop_id, milestone_code,
    candidate_event_time, location, dedup_key
  ) values (
    v_tenant1, v_shipment_order_id, v_leg_id, v_pickup_stop_id, 'pickup_arrival',
    v_terminal_event_time + interval '1 hour', app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.8456, -6.2088))),
    'test-conflict-candidate'
  )
  returning id into v_candidate_id;

  begin
    perform app.confirm_milestone_candidate(v_candidate_id, v_admin, 'admin');
  exception
    when others then
      if sqlerrm like 'milestone_candidate_conflicts_confirmed_event%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected a candidate dated after a confirmed terminal event to be rejected by default';
  end if;

  v_event := app.confirm_milestone_candidate(v_candidate_id, v_admin, 'admin', null, true);
  if v_event.reason <> 'confirmed_geofence_candidate_override' then
    raise exception 'assertion failed: expected the override path to record reason=confirmed_geofence_candidate_override, got %', v_event.reason;
  end if;
  if (select status from app.shipment_milestone_candidates where id = v_candidate_id) <> 'confirmed' then
    raise exception 'assertion failed: expected the overridden candidate to be marked confirmed';
  end if;
end $$;

\echo '>> route deviation: two off-corridor reports at least deviation_sustained_seconds apart confirm one exception signal; a recovery in between resets the episode; a second episode gets its own distinct correlation_key'
do $$
declare
  v_device_id uuid := (select value::uuid from geo_test_state where key = 'device_id');
  v_api_key text := (select value from geo_test_state where key = 'api_key');
  v_leg_id uuid := (select value::uuid from geo_test_state where key = 'shipment_leg_id');
  v_state record;
  v_signal_count integer;
  v_signal1 app.shipment_exception_signals;
  v_signal2 app.shipment_exception_signals;
  v_admin uuid := (select value::uuid from geo_test_state where key = 'admin_actor_id');
  v_exception app.operational_exceptions;
begin
  -- Well off the Jakarta-Bandung straight line (~130km apart along a roughly
  -- east-southeast bearing) -- clearly more than the 1500m corridor width.
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '356 minutes')::text, 'longitude', 107.38, 'latitude', -6.56, 'speed_kmh', 60)),
    'test-gateway'
  );
  select * into v_state from app.shipment_leg_route_deviation_states where shipment_leg_id = v_leg_id;
  if v_state.state is distinct from 'off_corridor' or v_state.confirmed_at is not null then
    raise exception 'assertion failed: expected off_corridor with no confirmed_at yet, got state=% confirmed_at=%', v_state.state, v_state.confirmed_at;
  end if;

  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '359 minutes')::text, 'longitude', 107.39, 'latitude', -6.57, 'speed_kmh', 60)),
    'test-gateway'
  );
  select * into v_state from app.shipment_leg_route_deviation_states where shipment_leg_id = v_leg_id;
  if v_state.state is distinct from 'off_corridor' or v_state.confirmed_at is null then
    raise exception 'assertion failed: expected off_corridor with confirmed_at set after the sustained window, got state=% confirmed_at=%', v_state.state, v_state.confirmed_at;
  end if;

  select count(*) into v_signal_count from app.shipment_exception_signals where signal_type = 'route_deviation';
  if v_signal_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 route_deviation exception signal, found %', v_signal_count;
  end if;
  select * into v_signal1 from app.shipment_exception_signals where signal_type = 'route_deviation';
  if v_signal1.exception_type <> 'delay' or v_signal1.severity <> 'medium' or v_signal1.status <> 'pending' then
    raise exception 'assertion failed: unexpected first route_deviation signal %', v_signal1;
  end if;

  -- Recovery: a point back on the corridor silently resets the episode, no new signal.
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '456 minutes')::text, 'longitude', 107.232361, 'latitude', -6.563114, 'speed_kmh', 60)),
    'test-gateway'
  );
  select * into v_state from app.shipment_leg_route_deviation_states where shipment_leg_id = v_leg_id;
  if v_state.state is distinct from 'on_corridor' or v_state.first_off_corridor_at is not null or v_state.confirmed_at is not null then
    raise exception 'assertion failed: expected a silent recovery to reset state to on_corridor with null first_off_corridor_at/confirmed_at, got %', v_state;
  end if;

  -- A second, independent episode.
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '556 minutes')::text, 'longitude', 107.38, 'latitude', -6.58, 'speed_kmh', 60)),
    'test-gateway'
  );
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '559 minutes')::text, 'longitude', 107.39, 'latitude', -6.59, 'speed_kmh', 60)),
    'test-gateway'
  );
  select count(*) into v_signal_count from app.shipment_exception_signals where signal_type = 'route_deviation';
  if v_signal_count <> 2 then
    raise exception 'assertion failed: expected a second, distinct route_deviation exception signal after a fresh episode, found %', v_signal_count;
  end if;
  select * into v_signal2 from app.shipment_exception_signals where signal_type = 'route_deviation' and id <> v_signal1.id;
  if v_signal2.correlation_key = v_signal1.correlation_key then
    raise exception 'assertion failed: expected the two episodes to carry distinct correlation_key values, both were %', v_signal1.correlation_key;
  end if;

  -- Review the first signal via confirm, the second via dismiss.
  v_exception := app.confirm_exception_signal(v_signal1.id, v_admin, 'admin');
  if v_exception.type <> 'delay' or v_exception.source <> 'system' or v_exception.correlation_key <> v_signal1.correlation_key then
    raise exception 'assertion failed: unexpected confirmed exception row %', v_exception;
  end if;
  if (select status from app.shipment_exception_signals where id = v_signal1.id) <> 'confirmed'
     or (select resulting_exception_id from app.shipment_exception_signals where id = v_signal1.id) <> v_exception.id then
    raise exception 'assertion failed: expected the first signal to be marked confirmed with resulting_exception_id set';
  end if;

  perform app.dismiss_exception_signal(v_signal2.id, v_admin, 'admin', 'driver took an approved detour around road closure');
  if (select status from app.shipment_exception_signals where id = v_signal2.id) <> 'dismissed' then
    raise exception 'assertion failed: expected the second signal to be marked dismissed';
  end if;
  if exists (select 1 from app.operational_exceptions where correlation_key = v_signal2.correlation_key) then
    raise exception 'assertion failed: expected dismiss to never create a real operational_exceptions row';
  end if;
end $$;

\echo '>> overdue geofence arrival: a third, never-approached stop past its own planned_at + grace is detected exactly once, deduplicated on repeat scans, and stops re-firing once confirmed'
do $$
declare
  v_tenant1 uuid := (select value::uuid from geo_test_state where key = 'tenant_id');
  v_overdue_stop_id uuid := (select value::uuid from geo_test_state where key = 'overdue_stop_id');
  v_admin uuid := (select value::uuid from geo_test_state where key = 'admin_actor_id');
  v_detected_count integer;
  v_signal app.shipment_exception_signals;
  v_pending_count integer;
  v_exception app.operational_exceptions;
begin
  v_detected_count := app.detect_overdue_geofence_arrivals(v_tenant1);
  if v_detected_count < 1 then
    raise exception 'assertion failed: expected at least 1 stop detected as overdue, got %', v_detected_count;
  end if;

  select * into v_signal from app.shipment_exception_signals where signal_type = 'overdue_geofence_arrival' and correlation_key = 'overdue_arrival:' || v_overdue_stop_id::text;
  if v_signal.id is null or v_signal.status <> 'pending' or v_signal.severity <> 'high' then
    raise exception 'assertion failed: expected a pending, high-severity overdue_geofence_arrival signal, got %', v_signal;
  end if;

  -- Re-scan while still pending: no duplicate pending row.
  perform app.detect_overdue_geofence_arrivals(v_tenant1);
  select count(*) into v_pending_count from app.shipment_exception_signals where correlation_key = v_signal.correlation_key;
  if v_pending_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 signal row for this correlation_key after a repeat scan, found %', v_pending_count;
  end if;

  v_exception := app.confirm_exception_signal(v_signal.id, v_admin, 'admin');
  if v_exception.type <> 'delay' then
    raise exception 'assertion failed: unexpected confirmed overdue-arrival exception %', v_exception;
  end if;

  -- Re-scan after confirm: still overdue in the real world, but never re-raised once
  -- already confirmed (design note in app.detect_overdue_geofence_arrivals' own comment).
  perform app.detect_overdue_geofence_arrivals(v_tenant1);
  select count(*) into v_pending_count from app.shipment_exception_signals where correlation_key = v_signal.correlation_key and status = 'pending';
  if v_pending_count <> 0 then
    raise exception 'assertion failed: expected zero new pending signals for an already-confirmed correlation_key, found %', v_pending_count;
  end if;
end $$;

\echo '>> read projections: app.get_shipment_milestone_candidates/get_shipment_exception_signals/get_shipment_leg_geofence_state/get_shipment_leg_route_deviation_state return the right shape for an authorized actor'
do $$
declare
  v_shipment_order_id uuid := (select value::uuid from geo_test_state where key = 'shipment_order_id');
  v_leg_id uuid := (select value::uuid from geo_test_state where key = 'shipment_leg_id');
  v_admin uuid := (select value::uuid from geo_test_state where key = 'admin_actor_id');
  v_confirmed_count integer;
  v_dismissed_count integer;
  v_geofence_state_count integer;
  v_deviation_state_count integer;
begin
  select count(*) into v_confirmed_count from app.get_shipment_milestone_candidates(v_shipment_order_id, v_admin, 'confirmed');
  if v_confirmed_count < 1 then
    raise exception 'assertion failed: expected at least 1 confirmed milestone candidate visible, got %', v_confirmed_count;
  end if;
  select count(*) into v_dismissed_count from app.get_shipment_exception_signals(v_shipment_order_id, v_admin, 'dismissed');
  if v_dismissed_count < 1 then
    raise exception 'assertion failed: expected at least 1 dismissed exception signal visible, got %', v_dismissed_count;
  end if;

  select count(*) into v_geofence_state_count from app.get_shipment_leg_geofence_state(v_leg_id, v_admin);
  if v_geofence_state_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 geofence state rows (pickup + delivery), got %', v_geofence_state_count;
  end if;

  select count(*) into v_deviation_state_count from app.get_shipment_leg_route_deviation_state(v_leg_id, v_admin);
  if v_deviation_state_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 route-deviation state row for this leg, got %', v_deviation_state_count;
  end if;
end $$;

\echo '>> cross-tenant authorization: a foreign tenant''s own OPS-capable admin cannot confirm/dismiss/read this tenant''s own candidates, signals, or leg states'
do $$
declare
  v_tenant2 uuid;
  v_team_b uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_foreign_actor uuid := '00000000-0000-0000-0000-000000046199';
  v_pickup_stop_id uuid := (select value::uuid from geo_test_state where key = 'pickup_stop_id');
  v_shipment_order_id uuid := (select value::uuid from geo_test_state where key = 'shipment_order_id');
  v_leg_id uuid := (select value::uuid from geo_test_state where key = 'shipment_leg_id');
  v_dummy_candidate_id uuid;
  v_rejected boolean := false;
begin
  insert into auth.users (id, email) values (v_foreign_actor, 'foreign@acmegeofencetwo.test');
  perform app.provision_tenant('acmegeofencetwo', 'Acme Geofence Two Co', 'idem-acmegeofencetwo', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmegeofencetwo');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEGEOFENCETWO-CO', 'Acme Geofence Two Co', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEGEOFENCETWO-CO');
  perform app.invite_user(v_tenant2, v_foreign_actor, 'foreign@acmegeofencetwo.test', 'Foreign Admin', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'foreign@acmegeofencetwo.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_foreign_actor, 'tenant_admin', v_tenant2, null, 'tester');
  v_edit_role := (app.create_role(v_tenant2, 'Foreign Editor', 'ops', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), v_foreign_actor, v_foreign_actor, 'tester');

  -- A fresh synthetic pending candidate on MY tenant's own pickup stop.
  insert into app.shipment_milestone_candidates (
    tenant_id, shipment_order_id, shipment_leg_id, shipment_leg_stop_id, milestone_code,
    candidate_event_time, dedup_key
  ) values (
    (select value::uuid from geo_test_state where key = 'tenant_id'), v_shipment_order_id, v_leg_id, v_pickup_stop_id, 'pickup_arrival',
    now(), 'test-cross-tenant-candidate'
  )
  returning id into v_dummy_candidate_id;

  begin
    perform app.confirm_milestone_candidate(v_dummy_candidate_id, v_foreign_actor, 'foreign');
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected a foreign tenant''s own admin to be rejected confirming this tenant''s own candidate';
  end if;

  v_rejected := false;
  begin
    perform app.get_shipment_leg_geofence_state(v_leg_id, v_foreign_actor);
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected a foreign tenant''s own admin to be rejected reading this tenant''s own leg geofence state';
  end if;
end $$;

\echo '>> schema-privilege defense in depth: none of the four new tables carries any direct anon/authenticated grant -- every authenticated read/write goes only through this migration''s own security-definer functions; the eight review/read RPCs are authenticated-callable, the six internal evaluators are service_role-only'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app'
    and grantee in ('anon', 'authenticated')
    and table_name in ('shipment_leg_stop_geofence_states', 'shipment_leg_route_deviation_states', 'shipment_milestone_candidates', 'shipment_exception_signals');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon/authenticated grants on the four new tables, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee in ('anon', 'authenticated')
    and routine_name in (
      'safe_jsonb_numeric', 'safe_jsonb_boolean', 'upsert_milestone_candidate', 'upsert_exception_signal',
      'evaluate_stop_geofence', 'evaluate_route_deviation', 'evaluate_geofence_and_deviation_signals', 'detect_overdue_geofence_arrivals'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon/authenticated grants on the internal evaluator/writer functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'authenticated'
    and routine_name in (
      'confirm_milestone_candidate', 'dismiss_milestone_candidate', 'confirm_exception_signal', 'dismiss_exception_signal',
      'get_shipment_milestone_candidates', 'get_shipment_exception_signals', 'get_shipment_leg_geofence_state', 'get_shipment_leg_route_deviation_state'
    );
  if v_count <> 8 then
    raise exception 'assertion failed: expected all 8 review/read RPCs to be authenticated-callable, found %', v_count;
  end if;

  -- The two widened functions keep their own exact pre-existing grants (226F/OPS-173's
  -- own established convention -- widening must never accidentally narrow or broaden).
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and routine_name = 'arbitrate_and_project_vehicle_position' and grantee = 'authenticated';
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.arbitrate_and_project_vehicle_position to remain service_role-only (never authenticated), found a grant';
  end if;
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and routine_name = 'ingest_milestone_event' and grantee in ('authenticated', 'service_role');
  if v_count <> 2 then
    raise exception 'assertion failed: expected app.ingest_milestone_event to remain granted to both authenticated and service_role, found %', v_count;
  end if;

  -- The anon-grant count repository-wide is unchanged by this migration (this checkpoint
  -- adds zero new anon-facing surface).
  select count(distinct routine_name) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'anon';
  if v_count <> 7 then
    raise exception 'assertion failed: expected the anon-grant count to remain exactly 7 after this migration, found %', v_count;
  end if;
end $$;

\echo '>> milestone_events.source widening: the constraint now accepts ''system'' alongside the original four values, and every value already in use remains valid'
do $$
declare
  v_check_def text;
begin
  select pg_get_constraintdef(oid) into v_check_def
  from pg_constraint
  where conname = 'milestone_events_source_check' and conrelid = 'app.milestone_events'::regclass;
  if v_check_def not like '%''system''%' or v_check_def not like '%''manual''%' or v_check_def not like '%''api''%' or v_check_def not like '%''webhook''%' or v_check_def not like '%''import''%' then
    raise exception 'assertion failed: expected the widened source CHECK to still name all five values, got %', v_check_def;
  end if;
end $$;

drop table geo_test_state;

\echo 'ALL ATW-226G db-test assertions passed.'
