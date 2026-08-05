-- Real, executable test evidence for ATW-226F (CG-S10-ATW-006's family, Prompt 226
-- decomposition "Canonical telemetry, dedup/order, current position, history, source
-- arbitration, and conflict/fallback") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
--
-- Exercises the widened app.ingest_driver_mobile_report/app.ingest_direct_device_
-- telemetry_batch/app.ingest_third_party_provider_webhook_event end to end -- every
-- assertion below goes through the same anon-facing RPCs a real Driver PWA/GPS Gateway/
-- provider webhook would call, never a direct app.arbitrate_and_project_vehicle_position
-- call, except where explicitly noted (idempotency).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, one confirmed land-freight Shipment Order with an assigned vehicle+driver, an installed GPS device on that vehicle, a webhook-mode third-party connection mapped to that vehicle, and an already-started driver_mobile ATW-225 tracking session'
create temporary table canon_test_state (key text primary key, value text not null);
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
  v_vehicle app.vehicle_operational_profiles;
  v_driver app.driver_operational_profiles;
  v_device app.gps_devices;
  v_assignment_id uuid;
  v_doc_draft app.config_versions;
  v_clean_file uuid;
  v_conn record;
  v_key record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000045101', 'admin@acmecanon.test'),
    ('00000000-0000-0000-0000-000000045103', 'supreme@acmecanon.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000045103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmecanon', 'Acme Canonical Co', 'idem-acmecanon', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmecanon');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMECANON-CO', 'Acme Canonical Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECANON-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000045101', 'admin@acmecanon.test', 'Canon Admin', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmecanon.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000045101', 'tenant_admin', v_tenant1, null, 'tester');

  v_edit_role := (app.create_role(v_tenant1, 'Canon Editor', 'full commercial + ops', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000045101', '00000000-0000-0000-0000-000000045103', 'tester');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-CANON-A', 'Canon Truck A', 'owned', 2000, 20, '00000000-0000-0000-0000-000000045101', 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, true, true, true, v_vehicle.record_version, '00000000-0000-0000-0000-000000045101', 'admin');
  select * into v_driver from app.register_driver_operational_profile(v_tenant1, 'DRV-CANON-A', 'Driver A', 'B2', (now() + interval '2 years')::date, '00000000-0000-0000-0000-000000045101', 'admin');
  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver.id, true, v_driver.record_version, '00000000-0000-0000-0000-000000045101', 'admin');

  -- GPS device, taken to 'installed' via the real ATW-226B evidence flow
  select * into v_device from app.register_gps_device(v_tenant1, '868712345601001', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000045101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle.id, 'canon fixture', '00000000-0000-0000-0000-000000045101', 'admin');
  v_assignment_id := (select id from app.device_vehicle_assignments where device_id = v_device.id and is_current);
  perform app.register_document_type('gps_device_installation', 'GPS Device Installation Evidence', 'DOC', '00000000-0000-0000-0000-000000045103', 'supreme');
  v_doc_draft := app.create_config_draft('document:gps_device_installation', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/jpeg', 'application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000045101', now(), 'admin');
  v_clean_file := (app.initiate_file_upload(
    v_tenant1, 'gps_device_installation', 'gps_device', v_device.id, 'install-photo.jpg', 'image/jpeg', 40960, null, false, null, '{}'::uuid[], null, 'idem-canon-install', '00000000-0000-0000-0000-000000045101', 'admin'
  )).id;
  perform app.record_file_scan_result(v_clean_file, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.record_gps_device_installation(v_assignment_id, v_clean_file, 'Budi Teknisi', 'installed under dashboard', v_device.record_version, '00000000-0000-0000-0000-000000045101', 'admin');

  -- Third-party provider connection + vehicle mapping
  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'acmecanongps', 'webhook', '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle.vehicle_master_id, 'acmecanongps', 'EXT-CANON-001', '00000000-0000-0000-0000-000000045101', 'admin');

  -- Full commercial-to-shipment pipeline (the vehicle/driver identity established above)
  perform app.capture_lead(v_tenant1, 'manual', null, 'Canontrack Co', 'Jane Canon', 'jane@canontracktest.test', '0811',
    '00000000-0000-0000-0000-000000045101', v_team_a, '00000000-0000-0000-0000-000000045101', 'tester');
  select * into v_lead from app.leads where email = 'jane@canontracktest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000045101', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Canontrack Co', 'CTC226F', '11.111.111.6-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 6', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000045101', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Canon Ops', 'Procurement Lead', 'jane@canontracktest.test', '0811', '00000000-0000-0000-0000-000000045101', v_team_a, '00000000-0000-0000-0000-000000045101', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000045101', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Canontrack test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000045101', v_team_a, '00000000-0000-0000-0000-000000045101', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000045101', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CTC226F-1', 'Contoso Canontrack Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000045101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000045101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000045101', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000045101', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000045101', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000045101', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000045101', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Canon tracking lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000045101', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000045101', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000045101', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Canon Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000045101', 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000045101', 'admin');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000045101', 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000045101', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-canon-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 1000, 1000, 16, 1000, 1000, 16, null, '00000000-0000-0000-0000-000000045101', 'admin'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000045101', 'admin');

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-canon-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, now(), '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bandung Warehouse', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 1000, 1000, 16, '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000045101', 'admin');

  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.assign_resource(v_shipment.id, 'driver', v_driver.driver_master_id, '00000000-0000-0000-0000-000000045101', 'admin');

  perform app.upsert_shipment_leg_tracking_policy(
    v_leg.id, true, array['driver_mobile', 'direct_device', 'third_party_platform'], 'driver_mobile', array['driver_mobile', 'direct_device', 'third_party_platform'],
    300, 100, 30, 'leg_dispatch', 'leg_complete', null, true, 3600, '00000000-0000-0000-0000-000000045101', 'admin'
  );
  perform app.start_leg_tracking_session(v_leg.id, 'driver_mobile', 'driver', v_driver.driver_master_id, null, '00000000-0000-0000-0000-000000045101', 'admin');

  select * into v_key from app.create_api_key(v_tenant1, 'Canon Gateway Key', '["OPS:Edit"]'::jsonb, null, null, '00000000-0000-0000-0000-000000045101', 'admin');

  insert into canon_test_state (key, value) values
    ('tenant_id', v_tenant1::text),
    ('vehicle_master_id', v_vehicle.vehicle_master_id::text),
    ('device_id', v_device.id::text),
    ('connection_id', v_conn.connection_id::text),
    ('webhook_secret', v_conn.raw_webhook_secret),
    ('api_key', v_key.raw_key),
    ('tracking_session_id', (select id from app.shipment_leg_tracking_sessions where shipment_leg_id = v_leg.id and is_current)::text);
end $$;

\echo '>> direct_device bootstrap: the first-ever accepted location report for this vehicle becomes the current position unconditionally, with a real bootstrap source-switch row'
do $$
declare
  v_device_id uuid := (select value::uuid from canon_test_state where key = 'device_id');
  v_api_key text := (select value from canon_test_state where key = 'api_key');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_pos record;
  v_switch_count integer;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object(
      'report_type', 'location', 'event_at', now()::text, 'longitude', 106.845599, 'latitude', -6.208763,
      'speed_kmh', 40, 'heading_degrees', 90
    )),
    'test-gateway'
  );

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos.source_type <> 'direct_device' or v_pos.location_geojson is null then
    raise exception 'assertion failed: expected direct_device to win the bootstrap, got source_type=%', v_pos.source_type;
  end if;

  select count(*) into v_switch_count from app.vehicle_source_switches where vehicle_master_id = v_vehicle_id and reason = 'bootstrap';
  if v_switch_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 bootstrap switch row, found %', v_switch_count;
  end if;
end $$;

\echo '>> same-source continuation: a newer direct_device report updates current position; an older (out-of-order) one is stored but rejected as stale_event_time and never rolls current position backward'
do $$
declare
  v_device_id uuid := (select value::uuid from canon_test_state where key = 'device_id');
  v_api_key text := (select value from canon_test_state where key = 'api_key');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_newer_event_at timestamptz := now() + interval '2 minutes';
  v_older_event_at timestamptz := now() + interval '1 minute';
  v_pos record;
  v_stale_count integer;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', v_newer_event_at::text, 'longitude', 106.8460, 'latitude', -6.2090, 'speed_kmh', 42)),
    'test-gateway'
  );
  select * into v_pos from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos.event_at <> v_newer_event_at then
    raise exception 'assertion failed: expected current position event_at to advance to %, got %', v_newer_event_at, v_pos.event_at;
  end if;

  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', v_older_event_at::text, 'longitude', 106.8465, 'latitude', -6.2095, 'speed_kmh', 41)),
    'test-gateway'
  );
  select * into v_pos from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos.event_at <> v_newer_event_at then
    raise exception 'assertion failed: expected current position to stay at the newer event_at %, got % (moved backward)', v_newer_event_at, v_pos.event_at;
  end if;

  select count(*) into v_stale_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id and rejection_reason = 'stale_event_time';
  if v_stale_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 stale_event_time canonical event, found %', v_stale_count;
  end if;
end $$;

\echo '>> cross-source switch suppressed: third_party_platform (lower tenant-default priority than direct_device) cannot take over while direct_device is still fresh'
do $$
declare
  v_connection_id uuid := (select value::uuid from canon_test_state where key = 'connection_id');
  v_secret text := (select value from canon_test_state where key = 'webhook_secret');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_pos_before record;
  v_pos_after record;
  v_suppressed_count integer;
begin
  select * into v_pos_before from app.get_vehicle_current_position(v_vehicle_id);

  v_payload := jsonb_build_object(
    'event_id', 'canon-evt-suppressed', 'vehicle_id', 'EXT-CANON-001', 'event_type', 'location',
    'timestamp', (now() + interval '3 minutes')::text, 'latitude', -6.3000, 'longitude', 106.9000
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  perform app.ingest_third_party_provider_webhook_event(v_connection_id, 'canon-client', v_payload, v_ts, v_signature);

  select * into v_pos_after from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos_after.source_type <> v_pos_before.source_type or v_pos_after.event_at <> v_pos_before.event_at then
    raise exception 'assertion failed: expected the lower-priority third_party report to be suppressed, current position changed from %/% to %/%',
      v_pos_before.source_type, v_pos_before.event_at, v_pos_after.source_type, v_pos_after.event_at;
  end if;

  select count(*) into v_suppressed_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id and rejection_reason = 'switch_suppressed';
  if v_suppressed_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 switch_suppressed canonical event, found %', v_suppressed_count;
  end if;
end $$;

\echo '>> stale-fallback switch: once direct_device has gone quiet beyond the freshness threshold, a lower-priority third_party report is allowed to take over, with a real auditable switch row'
do $$
declare
  v_connection_id uuid := (select value::uuid from canon_test_state where key = 'connection_id');
  v_secret text := (select value from canon_test_state where key = 'webhook_secret');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_pos record;
  v_switch app.vehicle_source_switches;
begin
  -- Simulate direct_device having gone silent well beyond the tenant's own
  -- freshness_threshold_seconds (300s default) -- direct SQL against received_at, since
  -- no RPC exists to backdate a real device's own clock (nor should one). Also elapse
  -- the hysteresis window past the bootstrap switch itself (test 1) -- real vehicles
  -- separate their first-ever pin from any later fallback decision by far more than
  -- switch_hysteresis_seconds; this test's own tight timing needs the same real
  -- separation simulated explicitly, the identical technique test 6 below uses.
  update app.vehicle_current_positions set received_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_id;
  update app.vehicle_source_switches set switched_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_id;

  v_payload := jsonb_build_object(
    'event_id', 'canon-evt-fallback', 'vehicle_id', 'EXT-CANON-001', 'event_type', 'location',
    'timestamp', (now() + interval '4 minutes')::text, 'latitude', -6.3100, 'longitude', 106.9100
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  perform app.ingest_third_party_provider_webhook_event(v_connection_id, 'canon-client', v_payload, v_ts, v_signature);

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos.source_type <> 'third_party_platform' then
    raise exception 'assertion failed: expected third_party_platform to win via stale fallback, got %', v_pos.source_type;
  end if;

  select * into v_switch from app.vehicle_source_switches where vehicle_master_id = v_vehicle_id and reason = 'current_source_stale_fallback' order by switched_at desc limit 1;
  if v_switch.from_source_type <> 'direct_device' or v_switch.to_source_type <> 'third_party_platform' or (v_switch.evidence ->> 'current_is_stale')::boolean is not true then
    raise exception 'assertion failed: expected a real, evidenced stale-fallback switch row, got %', v_switch;
  end if;
end $$;

\echo '>> hysteresis: immediately after a switch, direct_device (higher priority) cannot reclaim current position until switch_hysteresis_seconds has elapsed'
do $$
declare
  v_device_id uuid := (select value::uuid from canon_test_state where key = 'device_id');
  v_api_key text := (select value from canon_test_state where key = 'api_key');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_pos record;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '5 minutes')::text, 'longitude', 106.85, 'latitude', -6.21, 'speed_kmh', 30)),
    'test-gateway'
  );
  select * into v_pos from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos.source_type <> 'third_party_platform' then
    raise exception 'assertion failed: expected the immediate direct_device reclaim to be suppressed by hysteresis, current position source_type is %', v_pos.source_type;
  end if;
end $$;

\echo '>> driver_mobile (highest tenant-default priority) reclaims current position after the hysteresis window is manually elapsed'
do $$
declare
  v_tracking_session_id uuid := (select value::uuid from canon_test_state where key = 'tracking_session_id');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_start record;
  v_result record;
  v_pos record;
begin
  -- Elapse the hysteresis window for real (no RPC exists to backdate it, nor should one).
  update app.vehicle_source_switches set switched_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_id;

  select * into v_start from app.start_driver_mobile_session(v_tracking_session_id, 24, '00000000-0000-0000-0000-000000045101', 'admin');

  select * into v_result from app.ingest_driver_mobile_report(
    v_start.raw_token, 'canon-mobile-client', 'location', (now() + interval '6 minutes')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.8462, -6.2088)),
    5.0, 80, true, true, '{}'::jsonb
  );
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected ok, got %', v_result.ingest_status;
  end if;

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos.source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected driver_mobile (highest tenant-default priority) to win once hysteresis has elapsed, got %', v_pos.source_type;
  end if;
end $$;

\echo '>> impossible movement: a same-source report implying > 200 km/h is rejected and never applied, current position unchanged'
do $$
declare
  v_device_id uuid := (select value::uuid from canon_test_state where key = 'device_id');
  v_api_key text := (select value from canon_test_state where key = 'api_key');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_pos_before record;
  v_pos_after record;
  v_impossible_count integer;
  v_health_before record;
  v_health_after record;
begin
  -- direct_device is not the current winner at this point (driver_mobile is, the
  -- tenant-default highest-priority source, still fresh) -- nothing can dislodge it by
  -- priority alone, so first make it stale (exactly test 4's own technique) to let
  -- direct_device reclaim via fallback, plus elapse hysteresis, giving it a fresh, real,
  -- plausible current position of its own to serve as the impossible-movement check's
  -- own same-source baseline.
  update app.vehicle_current_positions set received_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_id;
  update app.vehicle_source_switches set switched_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_id;
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '7 minutes')::text, 'longitude', 106.85, 'latitude', -6.21, 'speed_kmh', 30)),
    'test-gateway'
  );
  select * into v_pos_before from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos_before.source_type <> 'direct_device' then
    raise exception 'assertion failed (test setup): expected direct_device to be current before the impossible-movement probe, got %', v_pos_before.source_type;
  end if;

  -- ATW-031 (ISS-2026-025): snapshot the per-source plausibility baseline before the probe.
  select last_location, last_seen_event_at, last_seen_received_at into v_health_before
    from app.vehicle_source_health where vehicle_master_id = v_vehicle_id and source_type = 'direct_device';

  -- ~500km away, 10 seconds later -- structurally impossible for a ground vehicle.
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '7 minutes 10 seconds')::text, 'longitude', 112.0, 'latitude', -7.5, 'speed_kmh', 30)),
    'test-gateway'
  );
  select * into v_pos_after from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos_after.event_at <> v_pos_before.event_at then
    raise exception 'assertion failed: expected the impossible-movement report to be rejected, current position event_at changed from % to %', v_pos_before.event_at, v_pos_after.event_at;
  end if;

  select count(*) into v_impossible_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id and rejection_reason = 'impossible_movement';
  if v_impossible_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 impossible_movement canonical event, found %', v_impossible_count;
  end if;

  -- ATW-031 (ISS-2026-025): the rejected report must NOT have seeded the very baseline it
  -- just failed against. Before this repair app.vehicle_source_health.last_location and
  -- last_seen_event_at advanced unconditionally on every candidate, so an
  -- impossible_movement rejection still moved the reference point the NEXT report is
  -- measured from -- the plausibility rule partially defeating itself, and the mechanism
  -- behind the "salami-slicing" path ATW-027's adversarial probe live-observed.
  select last_location, last_seen_event_at, last_seen_received_at into v_health_after
    from app.vehicle_source_health where vehicle_master_id = v_vehicle_id and source_type = 'direct_device';
  if ST_Distance(v_health_after.last_location, v_health_before.last_location) > 1 then
    raise exception 'assertion failed: an impossible_movement-rejected report moved the direct_device plausibility baseline (last_location) -- ISS-2026-025 is still open';
  end if;
  if v_health_after.last_seen_event_at <> v_health_before.last_seen_event_at then
    raise exception 'assertion failed: an impossible_movement-rejected report advanced last_seen_event_at from % to %', v_health_before.last_seen_event_at, v_health_after.last_seen_event_at;
  end if;
  -- Liveness evidence, by contrast, MUST still advance: a rejected report still proves the
  -- source is alive and talking, and external freshness reads depend on that distinction
  -- (ATW-027 Finding 2).
  if v_health_after.last_seen_received_at < v_health_before.last_seen_received_at then
    raise exception 'assertion failed: last_seen_received_at went backwards -- liveness evidence must advance even for a rejected report';
  end if;

  raise notice 'ATW-031 baseline proof: an impossible_movement-rejected report leaves last_location/last_seen_event_at untouched while last_seen_received_at still advances';
end $$;

\echo '>> heartbeat: stored as a canonical event with rejection_reason=heartbeat_no_location, current position untouched, source_health last_seen advances'
do $$
declare
  v_device_id uuid := (select value::uuid from canon_test_state where key = 'device_id');
  v_api_key text := (select value from canon_test_state where key = 'api_key');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_pos_before record;
  v_pos_after record;
  v_heartbeat_event_at timestamptz := now() + interval '8 minutes';
  v_health record;
begin
  select * into v_pos_before from app.get_vehicle_current_position(v_vehicle_id);

  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'heartbeat', 'event_at', v_heartbeat_event_at::text)),
    'test-gateway'
  );

  select * into v_pos_after from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos_after.event_at <> v_pos_before.event_at then
    raise exception 'assertion failed: expected a heartbeat to never change current position, event_at moved from % to %', v_pos_before.event_at, v_pos_after.event_at;
  end if;

  select * into v_health from app.get_vehicle_source_health(
    (select value::uuid from canon_test_state where key = 'tenant_id'), v_vehicle_id
  ) where source_type = 'direct_device';
  if v_health.last_seen_event_at <> v_heartbeat_event_at then
    raise exception 'assertion failed: expected vehicle_source_health.last_seen_event_at to advance to the heartbeat''s own event_at %, got %', v_heartbeat_event_at, v_health.last_seen_event_at;
  end if;
end $$;

\echo '>> per-vehicle source override: disabling direct_device for this one vehicle makes every subsequent direct_device report source_disabled, never applied, regardless of priority/staleness'
do $$
declare
  v_tenant1 uuid := (select value::uuid from canon_test_state where key = 'tenant_id');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_device_id uuid := (select value::uuid from canon_test_state where key = 'device_id');
  v_api_key text := (select value from canon_test_state where key = 'api_key');
  v_pos_before record;
  v_pos_after record;
  v_disabled_count integer;
begin
  insert into app.vehicle_tracking_source_priorities (tenant_id, vehicle_master_id, source_type, priority_rank, is_enabled)
  values (v_tenant1, v_vehicle_id, 'direct_device', 1, false);

  select * into v_pos_before from app.get_vehicle_current_position(v_vehicle_id);

  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '9 minutes')::text, 'longitude', 106.85, 'latitude', -6.21, 'speed_kmh', 20)),
    'test-gateway'
  );

  select * into v_pos_after from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos_after.event_at <> v_pos_before.event_at then
    raise exception 'assertion failed: expected a per-vehicle-disabled source to never apply, current position event_at changed from % to %', v_pos_before.event_at, v_pos_after.event_at;
  end if;

  select count(*) into v_disabled_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id and rejection_reason = 'source_disabled';
  if v_disabled_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 source_disabled canonical event, found %', v_disabled_count;
  end if;
end $$;

\echo '>> idempotency: a direct call to app.arbitrate_and_project_vehicle_position with an already-canonicalized source_report_id returns the existing row, never a duplicate'
do $$
declare
  v_tenant1 uuid := (select value::uuid from canon_test_state where key = 'tenant_id');
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_existing_report_id uuid := (select source_report_id from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id and source_type = 'direct_device' limit 1);
  v_before_count integer;
  v_after_count integer;
  v_result app.canonical_telemetry_events;
begin
  select count(*) into v_before_count from app.canonical_telemetry_events where source_type = 'direct_device' and source_report_id = v_existing_report_id;

  v_result := app.arbitrate_and_project_vehicle_position(
    v_tenant1, v_vehicle_id, 'direct_device', v_existing_report_id, now(), now(), null, null, null, null
  );

  select count(*) into v_after_count from app.canonical_telemetry_events where source_type = 'direct_device' and source_report_id = v_existing_report_id;
  if v_before_count <> 1 or v_after_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row before and after the idempotent retry, got %/%', v_before_count, v_after_count;
  end if;
end $$;

\echo '>> app.get_vehicle_telemetry_history: newest-first, hard-capped, and reflects every real event (applied and rejected alike)'
do $$
declare
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_total_events integer;
  v_history_rows integer;
  v_first record;
begin
  select count(*) into v_total_events from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id;
  select count(*) into v_history_rows from app.get_vehicle_telemetry_history(v_vehicle_id, null, 500);
  if v_history_rows <> v_total_events then
    raise exception 'assertion failed: expected app.get_vehicle_telemetry_history to reflect all % real events, returned %', v_total_events, v_history_rows;
  end if;

  select * into v_first from app.get_vehicle_telemetry_history(v_vehicle_id, null, 1);
  if v_first.event_at <> (select max(event_at) from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id) then
    raise exception 'assertion failed: expected the newest-first row to carry the maximum event_at';
  end if;

  select count(*) into v_history_rows from app.get_vehicle_telemetry_history(v_vehicle_id, null, 999999);
  if v_history_rows > 500 then
    raise exception 'assertion failed: expected the 500-row hard cap regardless of p_limit, got %', v_history_rows;
  end if;
end $$;

\echo '>> RLS: authenticated members of the owning tenant can read every new table via has_active_tenant_membership; a foreign tenant sees zero rows'
do $$
declare
  v_vehicle_id uuid := (select value::uuid from canon_test_state where key = 'vehicle_master_id');
  v_count integer;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000045199', 'foreign@acmecanontwo.test') on conflict do nothing;
  perform app.provision_tenant('acmecanontwo', 'Acme Canon Two Co', 'idem-acmecanontwo', 'tester');
  perform app.transition_tenant_status((select id from app.tenants where slug = 'acmecanontwo'), 'active', 'setup', 'tester');
  perform app.invite_user((select id from app.tenants where slug = 'acmecanontwo'), '00000000-0000-0000-0000-000000045199', 'foreign@acmecanontwo.test', 'Foreign', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'foreign@acmecanontwo.test'), 'active', 'onboarded', 'tester');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000045101", "role": "authenticated"}';
  select count(*) into v_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id;
  if v_count = 0 then
    raise exception 'assertion failed: expected the owning tenant''s own admin to see its own canonical events';
  end if;
  select count(*) into v_count from app.vehicle_current_positions where vehicle_master_id = v_vehicle_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 visible current-position row for the owning tenant';
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000045199", "role": "authenticated"}';
  select count(*) into v_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected a foreign tenant''s admin to see zero canonical events, saw %', v_count;
  end if;
  select count(*) into v_count from app.vehicle_current_positions where vehicle_master_id = v_vehicle_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected a foreign tenant''s admin to see zero current-position rows, saw %', v_count;
  end if;
  reset role;
end $$;

\echo '>> schema-privilege defense in depth: neither anon nor authenticated hold EXECUTE on arbitration/vehicle-resolution internals -- service_role only; the four read projections remain authenticated-callable'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee in ('anon', 'authenticated')
    and routine_name in (
      'arbitrate_and_project_vehicle_position', 'resolve_vehicle_source_priority_rank',
      'resolve_vehicle_for_driver_mobile_session', 'resolve_vehicle_for_gps_device'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon/authenticated grants on the arbitration internals, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'authenticated'
    and routine_name in ('get_vehicle_current_position', 'get_vehicle_telemetry_history', 'get_vehicle_source_health', 'get_vehicle_source_switches');
  if v_count <> 4 then
    raise exception 'assertion failed: expected all 4 read projections to be authenticated-callable, found %', v_count;
  end if;

  -- The anon-grant count repository-wide is unchanged by this migration (design note 1:
  -- widening preserves the exact anon grant each of 226C/226E already carried).
  select count(distinct routine_name) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'anon';
  if v_count <> 7 then
    raise exception 'assertion failed: expected the anon-grant count to remain exactly 7 after this migration''s own widening, found %', v_count;
  end if;
end $$;

\echo '>> CG-S10-ATW-027 Finding 2 regression (bootstrap path): a forged far-future event_at is now rejected event_time_implausible_future on the very first-ever report for a vehicle -- never applied unconditionally -- and the tenant''s own highest-priority source still bootstraps normally afterward (no permanent lockout)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from canon_test_state where key = 'tenant_id');
  v_connection_id uuid := (select value::uuid from canon_test_state where key = 'connection_id');
  v_secret text := (select value from canon_test_state where key = 'webhook_secret');
  v_vehicle app.vehicle_operational_profiles;
  v_vehicle_id uuid;
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_result record;
  v_pos record;
  v_implausible_count integer;
  v_event app.canonical_telemetry_events;
begin
  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-CANON-B01', 'Canon Truck B01', 'owned', 2000, 20, '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle.vehicle_master_id, 'acmecanongps', 'EXT-CANON-B01', '00000000-0000-0000-0000-000000045101', 'admin');
  v_vehicle_id := v_vehicle.vehicle_master_id;

  -- Mirrors the CG-S10-ATW-027 adversarial probe's own Probe B1 exactly: the
  -- FIRST-EVER report for this vehicle, from the lowest-tenant-default-priority
  -- source (third_party_platform), with a forged event_at ~73 years in the future.
  v_payload := jsonb_build_object(
    'event_id', 'canon-evt-poison-bootstrap', 'vehicle_id', 'EXT-CANON-B01', 'event_type', 'location',
    'timestamp', '2099-01-01T00:00:00Z', 'latitude', 1.234, 'longitude', 103.456, 'speed_kmh', 40, 'heading_degrees', 0
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');

  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'canon-poison-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed (test setup): expected the forged payload to still be RAW-accepted (ok) -- only canonicalization/arbitration rejects it, got %', v_result.ingest_status;
  end if;

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos.source_type is not null then
    raise exception 'assertion failed (Finding 2 REGRESSED): the forged 2099-01-01 bootstrap report became the current position (source=%/event_at=%) -- an implausible-future candidate must never win arbitration, even on the bootstrap path', v_pos.source_type, v_pos.event_at;
  end if;

  select count(*) into v_implausible_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id and rejection_reason = 'event_time_implausible_future';
  if v_implausible_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 event_time_implausible_future canonical event, found %', v_implausible_count;
  end if;

  -- Recovery: the tenant's own highest-priority source (driver_mobile) then reports a
  -- real, current position -- must succeed normally, proving the vehicle was never
  -- permanently locked out despite the earlier forged bootstrap attempt (mirrors the
  -- probe's own Probe B2: calling the shared arbitration entry point directly is the
  -- identical, precedented technique the idempotency test above already uses).
  v_event := app.arbitrate_and_project_vehicle_position(
    v_tenant1, v_vehicle_id, 'driver_mobile', gen_random_uuid(), now(), now(),
    app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.8, -6.2))),
    35::numeric, 90::numeric, 5::numeric
  );
  if v_event.rejection_reason is not null then
    raise exception 'assertion failed (Finding 2 REGRESSED -- permanent lockout): a real, present-day report from the tenant''s own highest-priority source was rejected (%) after the earlier forged bootstrap attempt', v_event.rejection_reason;
  end if;

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos.source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected driver_mobile to now hold current position after recovering from the poisoned bootstrap, got %', v_pos.source_type;
  end if;
end $$;

\echo '>> CG-S10-ATW-027 Finding 2 regression (stale-fallback path): the identical lockout is not achievable via the normal stale-fallback takeover path either -- a forged far-future event_at from a lower-priority source is rejected event_time_implausible_future, current position stays exactly where it was, and the highest-priority source recovers normally afterward'
do $$
declare
  v_tenant1 uuid := (select value::uuid from canon_test_state where key = 'tenant_id');
  v_connection_id uuid := (select value::uuid from canon_test_state where key = 'connection_id');
  v_secret text := (select value from canon_test_state where key = 'webhook_secret');
  v_vehicle app.vehicle_operational_profiles;
  v_vehicle_id uuid;
  v_bootstrap_event_at timestamptz := now() - interval '10 minutes';
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_result record;
  v_pos_before record;
  v_pos_after record;
  v_event app.canonical_telemetry_events;
  v_recovery_event app.canonical_telemetry_events;
begin
  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-CANON-B02', 'Canon Truck B02', 'owned', 2000, 20, '00000000-0000-0000-0000-000000045101', 'admin');
  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle.vehicle_master_id, 'acmecanongps', 'EXT-CANON-B02', '00000000-0000-0000-0000-000000045101', 'admin');
  v_vehicle_id := v_vehicle.vehicle_master_id;

  -- Healthy, legitimate bootstrap via the highest-priority source (driver_mobile),
  -- real event_at -- mirrors the adversarial probe's own Probe B3 setup.
  v_event := app.arbitrate_and_project_vehicle_position(
    v_tenant1, v_vehicle_id, 'driver_mobile', gen_random_uuid(), v_bootstrap_event_at, v_bootstrap_event_at,
    app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.8, -6.2))),
    30::numeric, 90::numeric, 5::numeric
  );
  if v_event.rejection_reason is not null then
    raise exception 'assertion failed (test setup): expected the legitimate driver_mobile bootstrap to apply cleanly, got rejection_reason=%', v_event.rejection_reason;
  end if;

  -- Simulate driver_mobile having genuinely gone quiet beyond the freshness threshold
  -- -- identical backdating technique this file's own earlier tests (4/6) already use,
  -- since no RPC exists to backdate a real clock, nor should one.
  update app.vehicle_current_positions set received_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_id;
  update app.vehicle_source_switches set switched_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_id;

  select * into v_pos_before from app.get_vehicle_current_position(v_vehicle_id);

  -- The lower-priority third_party_platform source takes over via the legitimate
  -- stale-fallback path (lower priority is allowed to win specifically because the
  -- incumbent is stale) and forges a ~73-years-out event_at in the very report that
  -- attempts the takeover -- mirrors the probe's own Probe B3 exploit exactly.
  v_payload := jsonb_build_object(
    'event_id', 'canon-evt-poison-fallback', 'vehicle_id', 'EXT-CANON-B02', 'event_type', 'location',
    'timestamp', '2099-06-15T00:00:00Z', 'latitude', 2.5, 'longitude', 104.5
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'canon-poison-client-2', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed (test setup): expected the forged payload to still be RAW-accepted (ok) -- only canonicalization/arbitration rejects it, got %', v_result.ingest_status;
  end if;

  select * into v_pos_after from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos_after.source_type <> v_pos_before.source_type or v_pos_after.event_at <> v_pos_before.event_at then
    raise exception 'assertion failed (Finding 2 REGRESSED): the forged 2099-06-15 stale-fallback report changed current position from %/% to %/% -- an implausible-future candidate must be rejected even via the legitimate stale-fallback takeover path', v_pos_before.source_type, v_pos_before.event_at, v_pos_after.source_type, v_pos_after.event_at;
  end if;

  if not exists (select 1 from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_id and source_type = 'third_party_platform' and rejection_reason = 'event_time_implausible_future') then
    raise exception 'assertion failed: expected a stored third_party_platform canonical event with rejection_reason=event_time_implausible_future';
  end if;

  -- Recovery: the highest-priority source (driver_mobile) then reports a real,
  -- present-day position -- must succeed normally, proving no permanent lockout via
  -- the stale-fallback path either.
  v_recovery_event := app.arbitrate_and_project_vehicle_position(
    v_tenant1, v_vehicle_id, 'driver_mobile', gen_random_uuid(), now(), now(),
    app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.81, -6.21))),
    30::numeric, 90::numeric, 5::numeric
  );
  if v_recovery_event.rejection_reason is not null then
    raise exception 'assertion failed (Finding 2 REGRESSED -- permanent lockout): a real, present-day report from the highest-priority source was rejected (%) after the earlier forged stale-fallback attempt', v_recovery_event.rejection_reason;
  end if;

  select * into v_pos_after from app.get_vehicle_current_position(v_vehicle_id);
  if v_pos_after.source_type <> 'driver_mobile' or v_pos_after.event_at <> v_recovery_event.event_at then
    raise exception 'assertion failed: expected driver_mobile to hold current position with the real recovered event_at after the forged fallback attempt, got source=%/event_at=%', v_pos_after.source_type, v_pos_after.event_at;
  end if;
end $$;

drop table canon_test_state;

\echo 'ALL ATW-226F db-test assertions passed.'
