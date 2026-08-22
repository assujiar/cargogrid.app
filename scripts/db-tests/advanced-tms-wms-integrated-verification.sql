-- ATW-026 (Prompt 245, "Advanced TMS/WMS Integrated Verification") integrated
-- verification -- run via `pnpm run db:test` against a real, disposable Postgres
-- database, exactly like every other file in this directory.
--
-- READ-ONLY PROOF, NOT A NEW CAPABILITY. This file adds no schema, no new RPC, no
-- new business rule -- it only CALLS already-VERIFIED RPCs from already-VERIFIED
-- migrations (ATW-221..244 plus their Phase 3 Operations prerequisites) in
-- combinations no single capability's own checkpoint ever exercised together. Every
-- assertion below fails the whole `db:test` run (ON_ERROR_STOP) on any deviation,
-- exactly like every sibling file -- this is real executed evidence, not a
-- restatement of what each capability's own file already proved in isolation.
--
-- Mirrors the established "phase-capstone integrated verification" convention this
-- repository already uses (operations-integrated-verification.sql,
-- commercial-integrated-verification.sql, finance-integrated-verification.sql,
-- platform-core-integrated-verification.sql, and the narrower
-- advanced-tms-gps-telematics-integrated-verification.sql for the ATW-226 family
-- alone) -- one continuous fixture driven through the complete cross-capability
-- flow, then cross-checked against every read-side projection built on top of the
-- same data, which is exactly the class of defect an isolated per-capability test
-- cannot catch.
--
-- Six parts, matching CG-S10-ATW-026's own six required deliverables:
--   Part 1 (tenant atw026golden)  -- transport golden path: multi-leg planning ->
--     dispatch -> resource assignment -> route/capacity planning -> mile execution
--     -> tracking (driver_mobile) -> milestone/exception -> delivery/custody/ePOD,
--     composing Operations (Phase 3) and Advanced TMS (ATW-221/222/224/225/227/228)
--     real RPCs, plus a dedicated canonical-non-duplication sweep.
--   Part 2 (tenant atw026mobile)  -- Mandatory tracking E2E #1: Mobile Tracking
--     package, entitlement/consent/freshness checks included.
--   Part 3 -- Mandatory tracking E2E #2 (Direct Fleet GPS, real sockets) is
--     deliberately NOT in this file -- see the companion driver
--     scripts/verification/atw-026-direct-fleet-gps-canonical-projection.ts /
--     .sh, since a real TCP/Codec-8E proof needs Node's net sockets, not SQL. This
--     file's own Part 1 does exercise the SAME app.ingest_direct_device_telemetry_
--     batch RPC the gateway calls, at the RPC-composition layer.
--   Part 4 (extends atw026golden's own vehicle) -- Mandatory tracking E2E #3:
--     Existing GPS Integration (third-party). No live provider credentials exist in
--     this repository (confirmed: ATW-226E/226I's own residual disclosures,
--     `docs/runtime/KNOWN_ISSUES.md` -- no entry claims one). The live-provider half
--     is explicitly labeled CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE below, per
--     245_*.md's own External-evidence policy; the deterministic adapter-contract
--     half (auth/signature, mapping, canonical projection) is real and unskipped.
--   Part 5 (extends atw026golden's own vehicle) -- Mandatory tracking E2E #4:
--     Hybrid source conflict/fallback/arbitration -- explicit sequential (not
--     merely concurrent-load) hysteresis and full source-history preservation.
--     scripts/load-tests/pgbench/hybrid-arbitration.sql's own real concurrent
--     scenario is re-run fresh separately (see the completion report for that
--     command's own output) -- this part is its sequential complement.
--   Part 6 (extends atw026golden's own shipment/vehicle) -- the accepted-work
--     invariant: a canonical_telemetry_events insert never itself mutates
--     app.shipment_orders.status; only an explicit, separately-authorized
--     transition RPC does. Proven both dynamically (real before/after row
--     snapshots) and statically (pg_get_functiondef source-text sweep).
--
-- External-evidence policy reminder (245_*.md, "External-evidence policy" section):
-- physical Teltonika hardware and a live third-party provider remain unavailable in
-- this environment, exactly as every ATW-226 checkpoint already disclosed
-- (DEFERRED_EXTERNAL_HARDWARE_EVIDENCE / CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE).
-- Nothing in this file claims otherwise; both remain non-blocking per that policy's
-- own closure-treatment clause.

\set ON_ERROR_STOP on

-- =============================================================================
-- PART 1: Transport golden path -- tenant `atw026golden`.
-- multi-leg planning -> dispatch -> resource assignment -> route/capacity planning
-- -> mile execution -> tracking -> milestone/exception -> delivery/custody/ePOD.
-- =============================================================================

\echo '>> Part 1 setup: one tenant, a full commercial-to-job-order pipeline, a two-leg land-freight Shipment Order (Jakarta -> Cikampek -> Bandung), a vehicle eligible for all three tracking sources, a consenting driver, an installed GPS device, and a webhook-mode third-party connection -- all real ATW-221..229/226-family/Phase-3-Operations RPCs, one continuous fixture'
create temporary table golden_state (key text primary key, value text not null);
do $$
declare
  v_tenant uuid;
  v_team uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_supreme uuid := '00000000-0000-0000-0000-000000995003';
  v_actor uuid := '00000000-0000-0000-0000-000000995001';
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
  v_driver app.driver_operational_profiles;
  v_device app.gps_devices;
  v_assignment_id uuid;
  v_doc_draft app.config_versions;
  v_clean_file uuid;
  v_conn record;
  v_gateway_key record;
begin
  insert into auth.users (id, email) values
    (v_actor, 'admin@atw026golden.test'),
    (v_supreme, 'supreme@atw026golden.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('atw026golden', 'ATW026 Golden Path Co', 'idem-atw026golden', 'tester');
  v_tenant := (select id from app.tenants where slug = 'atw026golden');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant, 'company', null, 'ATW026G-CO', 'ATW026 Golden Co', 'tester');
  v_team := (select id from app.org_units where tenant_id = v_tenant and code = 'ATW026G-CO');

  perform app.invite_user(v_tenant, v_actor, 'admin@atw026golden.test', 'Golden Admin', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@atw026golden.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_actor, 'tenant_admin', v_tenant, null, 'tester');

  v_edit_role := (app.create_role(v_tenant, 'Golden Editor', 'full commercial + ops', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), v_actor, v_supreme, 'tester');

  -- Milestone code vocabulary this fixture needs (idempotent -- harmless if an
  -- earlier-sorting db-test file already registered these platform-wide codes).
  perform app.register_milestone_code('pickup_arrival', 'Pickup Arrival', 'pickup', true, false, false, v_supreme, 'supreme');
  perform app.register_milestone_code('delivery_arrival', 'Delivery Arrival', 'delivery', true, true, true, v_supreme, 'supreme');

  -- Resources: one vehicle eligible for all three tracking sources, one consenting
  -- driver, one installed GPS device on that vehicle, one webhook-mode third-party
  -- connection mapped to the same vehicle -- ATW-223/226A/226B/226E real RPCs.
  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant, 'VEH-ATW026-A', 'ATW026 Truck A', 'owned', 2000, 20, v_actor, 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, true, true, true, v_vehicle.record_version, v_actor, 'admin');
  select * into v_driver from app.register_driver_operational_profile(v_tenant, 'DRV-ATW026-A', 'Driver ATW026 A', 'B2', (now() + interval '2 years')::date, v_actor, 'admin');
  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver.id, true, v_driver.record_version, v_actor, 'admin');

  -- ATW-246 hardening note: this literal was previously '868712345603001', coincidentally
  -- identical to the fixture IMEI advanced-tms-fleet-control-tower.sql/advanced-tms-
  -- milestone-exception-telemetry.sql also use for their own, unrelated tenants -- harmless
  -- before app.register_gps_device gained a real cross-tenant collision guard (this
  -- checkpoint's own migration 20260730360000), but a same-shared-database, order-dependent
  -- failure afterward. Changed to a value unique across every scripts/db-tests/*.sql fixture.
  select * into v_device from app.register_gps_device(v_tenant, '868712345603201', 'Teltonika FMC920', 'cargogrid', v_actor, 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, v_actor, 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle.id, 'atw026 golden fixture', v_actor, 'admin');
  v_assignment_id := (select id from app.device_vehicle_assignments where device_id = v_device.id and is_current);
  perform app.register_document_type('gps_device_installation', 'GPS Device Installation Evidence', 'DOC', v_supreme, 'supreme');
  v_doc_draft := app.create_config_draft('document:gps_device_installation', v_tenant, 'tenant', null, v_actor, 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/jpeg', 'application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), v_actor, 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, v_actor, now(), 'admin');
  v_clean_file := (app.initiate_file_upload(
    v_tenant, 'gps_device_installation', 'gps_device', v_device.id, 'install-photo.jpg', 'image/jpeg', 40960, null, false, null, '{}'::uuid[], null, 'idem-atw026-install', v_actor, 'admin'
  )).id;
  perform app.record_file_scan_result(v_clean_file, 'clean', 'test-scanner-ref', v_actor, 'admin');
  perform app.record_gps_device_installation(v_assignment_id, v_clean_file, 'Budi Teknisi', 'installed under dashboard', v_device.record_version, v_actor, 'admin');

  select * into v_conn from app.register_third_party_provider_connection(v_tenant, 'atw026goldengps', 'webhook', v_actor, 'admin');
  perform app.register_provider_vehicle_mapping(v_tenant, v_vehicle.vehicle_master_id, 'atw026goldengps', 'EXT-ATW026-001', v_actor, 'admin');

  select * into v_gateway_key from app.create_api_key(v_tenant, 'ATW026 Gateway Key', '["OPS:Edit"]'::jsonb, null, null, v_actor, 'admin');

  -- Full commercial-to-shipment pipeline (Commercial + Phase 3 Operations, real RPCs).
  perform app.capture_lead(v_tenant, 'manual', null, 'ATW026 Golden Shipper', 'Jane Golden', 'jane@atw026golden.test', '0811',
    v_actor, v_team, v_actor, 'tester');
  select * into v_lead from app.leads where email = 'jane@atw026golden.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_actor, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'ATW026 Golden Shipper', 'ATW026G', '11.111.111.7-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 7', 'city', 'Jakarta', 'country', 'ID'),
    v_actor, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant, 'Jane Golden Ops', 'Procurement Lead', 'jane@atw026golden.test', '0811', v_actor, v_team, v_actor, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_actor, 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant, v_prospect.id, 'ATW026 golden lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    v_actor, v_team, v_actor, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_actor, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant, 'VENDOR-ATW026G-1', 'Contoso ATW026 Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, v_actor, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_actor, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_actor, 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant, 20.00, 'half_up', v_actor, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_actor, 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, v_actor, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_actor, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'ATW026 golden tracking lane', v_calc_id, 1, 4800000, 0, 0, v_actor, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_actor, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_actor, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Golden Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_actor, 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_actor, 'admin');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_actor, 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_actor, 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-atw026-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 1000, 1000, 16, 1000, 1000, 16, null, v_actor, 'admin'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_actor, 'admin');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-atw026-to-planned', v_actor, 'admin');

  -- Multi-leg planning (ATW-221): two real legs, Jakarta -> Cikampek (leg 1, the
  -- one this file's own tracking/telemetry/milestone/custody composition runs
  -- against) and Cikampek -> Bandung (leg 2, proving the shipment-level lifecycle
  -- and the per-leg lifecycle are genuinely independent state machines, never a
  -- second forked canonical root).
  select * into v_leg1 from app.add_shipment_leg(v_shipment.id, 'idem-atw026-leg1', 1, 'land', null, now(), now() + interval '6 hours', v_actor, 'admin');
  perform app.add_shipment_leg_stop(v_leg1.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), v_actor, 'admin');
  perform app.add_shipment_leg_stop(v_leg1.id, 2, 'delivery', 'Cikampek Transfer Point', null, 107.451900, -6.416900, now() + interval '6 hours', v_actor, 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg1.id, 600, 600, 10, v_actor, 'admin');

  select * into v_leg2 from app.add_shipment_leg(v_shipment.id, 'idem-atw026-leg2', 2, 'land', null, now() + interval '7 hours', now() + interval '1 day', v_actor, 'admin');
  perform app.add_shipment_leg_stop(v_leg2.id, 1, 'pickup', 'Cikampek Transfer Point', null, 107.451900, -6.416900, now() + interval '7 hours', v_actor, 'admin');
  perform app.add_shipment_leg_stop(v_leg2.id, 2, 'delivery', 'Bandung Warehouse', null, 107.619123, -6.917464, now() + interval '1 day', v_actor, 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg2.id, 400, 400, 6, v_actor, 'admin');

  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), v_actor, 'admin');

  -- Resource assignment (Phase 3 OPS-172): the SAME vehicle/driver master rows
  -- ATW-223 already registered -- never a second, shipment-scoped copy.
  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, v_actor, 'admin');
  perform app.assign_resource(v_shipment.id, 'driver', v_driver.driver_master_id, v_actor, 'admin');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-atw026-to-assigned', v_actor, 'admin');

  insert into golden_state (key, value) values
    ('tenant_id', v_tenant::text),
    ('actor_id', v_actor::text),
    ('supreme_id', v_supreme::text),
    ('shipment_id', v_shipment.id::text),
    ('shipment_number', v_shipment.shipment_number::text),
    ('leg1_id', v_leg1.id::text),
    ('leg2_id', v_leg2.id::text),
    ('vehicle_profile_id', v_vehicle.id::text),
    ('vehicle_master_id', v_vehicle.vehicle_master_id::text),
    ('driver_profile_id', v_driver.id::text),
    ('driver_master_id', v_driver.driver_master_id::text),
    ('device_id', v_device.id::text),
    ('connection_id', v_conn.connection_id::text),
    ('webhook_secret', v_conn.raw_webhook_secret),
    ('api_key_gateway', v_gateway_key.raw_key);
end $$;

\echo '>> Part 1a: ATW-227 capacity reservation composes against the SAME leg/vehicle -- reserve_vehicle_capacity resolves the vehicle via the SAME app.resource_assignments row assign_resource just wrote, never a second assignment path'
do $$
declare
  v_leg1_id uuid := (select value::uuid from golden_state where key = 'leg1_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_reservation app.vehicle_capacity_reservations;
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
begin
  select * into v_reservation from app.reserve_vehicle_capacity(v_leg1_id, 600, 8, 'idem-atw026-capacity-leg1', v_actor, 'admin');
  if v_reservation.vehicle_master_id <> v_vehicle_master_id then
    raise exception 'assertion failed: expected the capacity reservation to resolve the SAME vehicle_master_id % (via the real resource_assignments row), got %', v_vehicle_master_id, v_reservation.vehicle_master_id;
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'assertion failed: expected a freshly reserved capacity window to be held, got %', v_reservation.status;
  end if;
end $$;

\echo '>> Part 1b: dispatch readiness/dispatch (Phase 3 OPS-175) -- app.evaluate_dispatch_readiness reads the SAME resource_assignments/shipment_orders rows Part 1 wrote; app.dispatch_shipment_order transitions status internally via the SAME app.transition_shipment_order used everywhere else, never a private status writer'
do $$
declare
  v_shipment_id uuid := (select value::uuid from golden_state where key = 'shipment_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_readiness record;
  v_shipment app.shipment_orders;
  v_command app.dispatch_commands;
begin
  select * into v_readiness from app.evaluate_dispatch_readiness(v_shipment_id);
  if not v_readiness.is_ready then
    raise exception 'assertion failed: expected the shipment to be dispatch-ready after resource assignment, blockers=%', v_readiness.blockers;
  end if;

  select * into v_shipment from app.shipment_orders where id = v_shipment_id;
  select * into v_command from app.dispatch_shipment_order(v_shipment_id, v_shipment.record_version, 'idem-atw026-dispatch', v_actor, 'admin');
  select * into v_shipment from app.shipment_orders where id = v_shipment_id;
  if v_shipment.status <> 'dispatched' then
    raise exception 'assertion failed: expected status=dispatched after app.dispatch_shipment_order, got %', v_shipment.status;
  end if;
end $$;

\echo '>> Part 1c: leg 1 dispatch (ATW-221 app.transition_shipment_leg) -- requires the SAME confirmed leg_network_status Part 1 set; leg-level and shipment-level lifecycles are independent state machines over the SAME canonical rows'
do $$
declare
  v_leg1_id uuid := (select value::uuid from golden_state where key = 'leg1_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_leg app.shipment_legs;
begin
  select * into v_leg from app.shipment_legs where id = v_leg1_id;
  select * into v_leg from app.transition_shipment_leg(v_leg1_id, 'dispatched', v_leg.record_version, v_actor, 'admin');
  if v_leg.leg_status <> 'dispatched' then
    raise exception 'assertion failed: expected leg1 leg_status=dispatched, got %', v_leg.leg_status;
  end if;
end $$;

\echo '>> Part 1d: ATW-224 route planning reads app.shipment_tracking_health BEFORE any telemetry exists -- honest not_tracked/unusable baseline, and app.prepare_route_planning_scenario composes against the SAME leg'
do $$
declare
  v_shipment_id uuid := (select value::uuid from golden_state where key = 'shipment_id');
  v_leg1_id uuid := (select value::uuid from golden_state where key = 'leg1_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_pos record;
  v_scenario app.route_planning_scenarios;
begin
  select * into v_pos from app.get_canonical_position_for_planning(v_shipment_id);
  if v_pos.tracking_status <> 'not_tracked' or v_pos.is_usable then
    raise exception 'assertion failed: expected an honest not_tracked/unusable baseline before any telemetry, got tracking_status=% is_usable=%', v_pos.tracking_status, v_pos.is_usable;
  end if;

  select * into v_scenario from app.prepare_route_planning_scenario(v_shipment_id, 'idem-atw026-scenario', 600, 8, v_actor, 'admin');
  if v_scenario.shipment_order_id <> v_shipment_id then
    raise exception 'assertion failed: expected the route planning scenario to reference the SAME shipment_order_id %, got %', v_shipment_id, v_scenario.shipment_order_id;
  end if;
end $$;

\echo '>> Part 1e: mile execution / tracking (ATW-225 + ATW-226 family) -- a real tracking policy naming all three sources, a driver_mobile session started, a real HTTPS-shaped ingestion RPC call (app.ingest_driver_mobile_report -- the exact RPC app/api/tracking/driver-mobile/route.ts calls unmodified), composing through ATW-226F arbitration into the canonical projection'
do $$
declare
  v_leg1_id uuid := (select value::uuid from golden_state where key = 'leg1_id');
  v_shipment_id uuid := (select value::uuid from golden_state where key = 'shipment_id');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_driver_master_id uuid := (select value::uuid from golden_state where key = 'driver_master_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_session app.shipment_leg_tracking_sessions;
  v_start record;
  v_ingest record;
  v_pos record;
begin
  perform app.upsert_shipment_leg_tracking_policy(
    v_leg1_id, true, array['driver_mobile', 'direct_device', 'third_party_platform'], 'driver_mobile', array['driver_mobile', 'direct_device', 'third_party_platform'],
    300, 100, 30, 'leg_dispatch', 'leg_complete',
    jsonb_build_object(
      'enabled', true, 'radius_meters', 500, 'dwell_seconds_before_confirm', 60,
      'route_deviation', jsonb_build_object('enabled', true, 'corridor_width_meters', 1500, 'deviation_sustained_seconds', 120),
      'overdue_arrival_grace_minutes', 60
    ),
    true, 3600, v_actor, 'admin'
  );

  select * into v_session from app.start_leg_tracking_session(v_leg1_id, 'driver_mobile', 'driver', v_driver_master_id, null, v_actor, 'admin');

  select * into v_start from app.start_driver_mobile_session(v_session.id, 24, v_actor, 'admin');

  -- The EXACT RPC server/mutations/driver-mobile-tracking.ts's ingestDriverMobileReport
  -- wraps 1:1, which app/api/tracking/driver-mobile/route.ts calls unmodified -- no live
  -- Supabase/PostgREST endpoint exists in this sandbox to exercise the HTTP hop itself
  -- (ADR-0010, confirmed by scripts/load-tests/gps-telemetry-load.ts's own identical
  -- disclosure), so this IS the real, composed code path below that HTTP hop.
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_start.raw_token, 'atw026-mobile-client', 'location', now()::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.845599, -6.208763)),
    5.0, 85, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the driver_mobile ingest to succeed, got %', v_ingest.ingest_status;
  end if;

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_master_id);
  if v_pos.source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected the canonical current position to be sourced from driver_mobile, got %', v_pos.source_type;
  end if;

  -- app.evaluate_stop_geofence (ATW-226G) evaluates exactly one stop per call --
  -- the leg's own earliest stop not yet 'exited'. Dwell-confirm the pickup stop
  -- (a second report at the SAME pickup coordinates, past dwell_seconds_before_
  -- confirm), then report away from it to fire the real pickup_departure
  -- transition -- only then does the evaluator advance to stop 2 (delivery),
  -- which Part 1h below drives to its own dwell-confirmed arrival.
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_start.raw_token, 'atw026-mobile-client', 'location', (now() + interval '90 seconds')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.845599, -6.208763)),
    5.0, 85, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the dwell-confirming pickup report to be accepted, got %', v_ingest.ingest_status;
  end if;
  -- 40 minutes later (real ~71km Jakarta->Cikampek distance implies ~106 km/h,
  -- safely under the 200 km/h impossible-movement ceiling -- ATW-226F's own
  -- design note 6 compares each candidate against the SAME source's own last-
  -- known position, so this gap must be wide enough for a real inter-city hop).
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_start.raw_token, 'atw026-mobile-client', 'location', (now() + interval '40 minutes')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(107.451900, -6.416900)),
    5.0, 85, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the departure-triggering report to be accepted, got %', v_ingest.ingest_status;
  end if;

  insert into golden_state (key, value) values ('leg1_mobile_raw_token', v_start.raw_token);
end $$;

\echo '>> Part 1f: cross-capability read-side reconciliation -- app.dispatch_board_queue (ATW-222), app.shipment_tracking_health (writer wired at ATW-024/ISS-2026-009), app.get_canonical_position_for_planning (ATW-224), and app.get_tenant_tracking_coverage/utilization (ATW-227) ALL now report the SAME live driver_mobile position, sourced from the SAME canonical_telemetry_events row -- never a second, independently-derived projection'
do $$
declare
  v_tenant_id uuid := (select value::uuid from golden_state where key = 'tenant_id');
  v_shipment_id uuid := (select value::uuid from golden_state where key = 'shipment_id');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_board record;
  v_planning record;
  v_coverage record;
  v_util app.tenant_tracking_utilization_summary;
begin
  select * into v_board from app.dispatch_board_queue where id = v_shipment_id;
  if v_board.tracking_status <> 'tracked' or v_board.authoritative_source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected app.dispatch_board_queue to report tracking_status=tracked authoritative_source_type=driver_mobile, got %/%', v_board.tracking_status, v_board.authoritative_source_type;
  end if;

  select * into v_planning from app.get_canonical_position_for_planning(v_shipment_id);
  if v_planning.tracking_status <> 'tracked' or v_planning.authoritative_source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected app.get_canonical_position_for_planning to now report tracking_status=tracked authoritative_source_type=driver_mobile, got %/%', v_planning.tracking_status, v_planning.authoritative_source_type;
  end if;
  if v_board.last_position_at <> v_planning.last_position_at then
    raise exception 'assertion failed: expected app.dispatch_board_queue and app.get_canonical_position_for_planning to report the IDENTICAL last_position_at (same underlying app.shipment_tracking_health row, never two independently-derived projections), got %/%', v_board.last_position_at, v_planning.last_position_at;
  end if;
  if not v_planning.is_usable then
    raise exception 'assertion failed: expected is_usable=true now that a real, fresh canonical position exists (this specific code path was disclosed unreachable in practice at ATW-224''s own authoring time, before ATW-024/ISS-2026-009 wired the missing app.shipment_tracking_health writer -- this is the first real, composed proof it is reachable)';
  end if;

  select * into v_coverage from app.get_tenant_tracking_coverage(v_tenant_id, v_actor) where vehicle_master_id = v_vehicle_master_id;
  if v_coverage.source_class <> 'hybrid' or v_coverage.coverage_status <> 'tracked' or v_coverage.authoritative_source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected app.get_tenant_tracking_coverage to report source_class=hybrid coverage_status=tracked authoritative_source_type=driver_mobile for the SAME vehicle_master_id, got %/%/%', v_coverage.source_class, v_coverage.coverage_status, v_coverage.authoritative_source_type;
  end if;
  if v_coverage.reserved_weight_kg <> 600 or v_coverage.reserved_volume_cbm <> 8 then
    raise exception 'assertion failed: expected app.get_tenant_tracking_coverage to reflect the SAME 600kg/8cbm capacity reservation Part 1a made, got %/%', v_coverage.reserved_weight_kg, v_coverage.reserved_volume_cbm;
  end if;

  select * into v_util from app.get_tenant_tracking_utilization_summary(v_tenant_id, v_actor);
  if v_util.tracked_vehicle_count <> 1 or v_util.total_active_vehicle_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 tracked/active vehicle tenant-wide, got tracked=% total=%', v_util.tracked_vehicle_count, v_util.total_active_vehicle_count;
  end if;
end $$;

\echo '>> Part 1g: custody at pickup (ATW-221 app.record_shipment_leg_custody_event) -- append-only, server-assigned sequence, over the SAME leg1'
do $$
declare
  v_leg1_id uuid := (select value::uuid from golden_state where key = 'leg1_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_event app.shipment_leg_custody_events;
begin
  select * into v_event from app.record_shipment_leg_custody_event(
    v_leg1_id, 'custody_transfer',
    jsonb_build_object('party', 'shipper', 'name', 'Jane Golden Ops'),
    jsonb_build_object('party', 'carrier', 'name', 'ATW026 Truck A', 'driver', 'Driver ATW026 A'),
    now(), jsonb_build_object('note', 'pickup at Jakarta Warehouse'), v_actor, 'admin'
  );
  if v_event.sequence_no <> 1 or v_event.event_type <> 'custody_transfer' then
    raise exception 'assertion failed: expected the first custody event on leg1 to carry sequence_no=1, got %/%', v_event.sequence_no, v_event.event_type;
  end if;
end $$;

\echo '>> Part 1h: telemetry-driven geofence dwell at leg1''s own delivery stop (Cikampek) -- ATW-226G''s real evaluator, invoked transitively from INSIDE app.arbitrate_and_project_vehicle_position (the SAME call app.ingest_driver_mobile_report already made in Part 1e) -- produces a real pending milestone candidate, never a second, hand-rolled milestone-detection path'
do $$
declare
  v_tenant_id uuid := (select value::uuid from golden_state where key = 'tenant_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_leg1_id uuid := (select value::uuid from golden_state where key = 'leg1_id');
  v_raw_token text := (select value from golden_state where key = 'leg1_mobile_raw_token');
  v_ingest record;
  v_candidate_count integer;
  v_candidate app.shipment_milestone_candidates;
begin
  -- Reuses the SAME bearer token Part 1e already minted for this session (a real
  -- driver_mobile session mints exactly once -- app.start_driver_mobile_session
  -- would correctly reject a second mint for an already-active session, per
  -- ATW-226C's own db-test; this is the intended "continue the same session" path).
  -- Part 1e's own trailing two reports already dwell-confirmed + departed the
  -- pickup stop, so the evaluator now targets stop 2 (delivery) for the first time.

  -- First report inside the Cikampek delivery-stop radius -- pending-dwell, no new candidate yet.
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_raw_token, 'atw026-mobile-client', 'location', (now() + interval '42 minutes')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(107.451900, -6.416900)),
    5.0, 80, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the first geofence-arrival report to be accepted, got %', v_ingest.ingest_status;
  end if;

  -- Second report, still inside, past the dwell threshold -- confirms the stop.
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_raw_token, 'atw026-mobile-client', 'location', (now() + interval '43 minutes 30 seconds')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(107.451900, -6.416900)),
    5.0, 80, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the dwell-confirming report to be accepted, got %', v_ingest.ingest_status;
  end if;

  -- By this point pickup_arrival and pickup_departure candidates ALSO exist
  -- (Part 1e's own dwell-confirm + departure at the pickup stop) -- this checks
  -- specifically for the real, freshly-staged delivery_arrival candidate, not a
  -- fragile "exactly 1 pending total" count.
  select count(*) into v_candidate_count from app.shipment_milestone_candidates where tenant_id = v_tenant_id and status = 'pending' and milestone_code = 'delivery_arrival';
  if v_candidate_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 pending delivery_arrival milestone candidate from the geofence dwell, found %', v_candidate_count;
  end if;

  select * into v_candidate from app.shipment_milestone_candidates where tenant_id = v_tenant_id and status = 'pending' and milestone_code = 'delivery_arrival';

  insert into golden_state (key, value) values ('milestone_candidate_id', v_candidate.id::text);
end $$;

\echo '>> Part 1i: confirming the candidate produces a real app.milestone_events row (Phase 3 OPS-173, extended by ATW-226G/ATW-228) -- and this confirmation does NOT itself change app.shipment_orders.status (full proof deferred to Part 6, spot-checked here)'
do $$
declare
  v_candidate_id uuid := (select value::uuid from golden_state where key = 'milestone_candidate_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_shipment_id uuid := (select value::uuid from golden_state where key = 'shipment_id');
  v_status_before text;
  v_status_after text;
  v_event app.milestone_events;
begin
  select status into v_status_before from app.shipment_orders where id = v_shipment_id;

  select * into v_event from app.confirm_milestone_candidate(v_candidate_id, v_actor, 'admin', null, false);
  if v_event.id is null or v_event.milestone_code <> 'delivery_arrival' or v_event.source <> 'system' then
    raise exception 'assertion failed: expected a real app.milestone_events row (source=system, milestone_code=delivery_arrival), got %', v_event;
  end if;
  -- ATW-228's own confidence/freshness provenance, computed from the SAME real
  -- canonical telemetry event backing this candidate -- never fabricated.
  if v_event.source_class is null or v_event.source_freshness_status is null or v_event.source_confidence_score is null then
    raise exception 'assertion failed: expected a telemetry-derived milestone to carry real confidence/freshness provenance (ATW-228), got source_class=% freshness=% confidence=%', v_event.source_class, v_event.source_freshness_status, v_event.source_confidence_score;
  end if;

  select status into v_status_after from app.shipment_orders where id = v_shipment_id;
  if v_status_before <> v_status_after then
    raise exception 'assertion failed: expected app.confirm_milestone_candidate to leave app.shipment_orders.status untouched (% -> %)', v_status_before, v_status_after;
  end if;
end $$;

\echo '>> Part 1j: leg1 completes its own lifecycle (in_transit -> arrived -> completed); a second custody event (handoff at the Cikampek transfer point) is recorded; leg2 (Cikampek -> Bandung) independently dispatches and completes over the SAME shipment -- two real, distinct app.shipment_legs rows, one canonical app.shipment_orders root'
do $$
declare
  v_leg1_id uuid := (select value::uuid from golden_state where key = 'leg1_id');
  v_leg2_id uuid := (select value::uuid from golden_state where key = 'leg2_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_leg app.shipment_legs;
  v_event app.shipment_leg_custody_events;
begin
  select * into v_leg from app.shipment_legs where id = v_leg1_id;
  select * into v_leg from app.transition_shipment_leg(v_leg1_id, 'in_transit', v_leg.record_version, v_actor, 'admin');
  select * into v_leg from app.transition_shipment_leg(v_leg1_id, 'arrived', v_leg.record_version, v_actor, 'admin');
  select * into v_leg from app.transition_shipment_leg(v_leg1_id, 'completed', v_leg.record_version, v_actor, 'admin');
  if v_leg.leg_status <> 'completed' then
    raise exception 'assertion failed: expected leg1 leg_status=completed, got %', v_leg.leg_status;
  end if;

  select * into v_event from app.record_shipment_leg_custody_event(
    v_leg1_id, 'handoff_confirmed',
    jsonb_build_object('party', 'carrier', 'name', 'ATW026 Truck A'),
    jsonb_build_object('party', 'linehaul', 'name', 'Cikampek Transfer Point'),
    now(), jsonb_build_object('note', 'handoff at Cikampek'), v_actor, 'admin'
  );
  if v_event.sequence_no <> 2 then
    raise exception 'assertion failed: expected the second custody event on leg1 to carry sequence_no=2 (append-only, server-assigned), got %', v_event.sequence_no;
  end if;

  select * into v_leg from app.shipment_legs where id = v_leg2_id;
  select * into v_leg from app.transition_shipment_leg(v_leg2_id, 'dispatched', v_leg.record_version, v_actor, 'admin');
  select * into v_leg from app.transition_shipment_leg(v_leg2_id, 'in_transit', v_leg.record_version, v_actor, 'admin');
  select * into v_leg from app.transition_shipment_leg(v_leg2_id, 'arrived', v_leg.record_version, v_actor, 'admin');
  select * into v_leg from app.transition_shipment_leg(v_leg2_id, 'completed', v_leg.record_version, v_actor, 'admin');
  if v_leg.leg_status <> 'completed' then
    raise exception 'assertion failed: expected leg2 leg_status=completed, got %', v_leg.leg_status;
  end if;

  select * into v_event from app.record_shipment_leg_custody_event(
    v_leg2_id, 'handoff_confirmed',
    jsonb_build_object('party', 'carrier', 'name', 'ATW026 Truck A'),
    jsonb_build_object('party', 'consignee', 'name', 'Bandung Warehouse'),
    now(), jsonb_build_object('note', 'final delivery at Bandung'), v_actor, 'admin'
  );
  -- leg2's OWN custody sequence starts fresh at 1 -- per-leg, not per-shipment,
  -- confirming custody lineage is scoped to the real owning leg, never merged.
  if v_event.sequence_no <> 1 then
    raise exception 'assertion failed: expected leg2''s own first custody event to carry sequence_no=1 (per-leg sequencing, independent of leg1''s), got %', v_event.sequence_no;
  end if;
end $$;

\echo '>> Part 1k: delivery + ePOD (Phase 3 OPS-170/OPS-176) -- app.transition_shipment_order(''delivered'') requires an evidence_ref; the full ePOD capture/evidence/submit/review/complete lifecycle then transitions status a SECOND, explicit time (-> epod) via the SAME app.transition_shipment_order, called internally by app.complete_epod_capture -- never a bespoke status writer'
do $$
declare
  v_shipment_id uuid := (select value::uuid from golden_state where key = 'shipment_id');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_supreme uuid := (select value::uuid from golden_state where key = 'supreme_id');
  v_tenant_id uuid := (select value::uuid from golden_state where key = 'tenant_id');
  v_shipment app.shipment_orders;
  v_doc_draft app.config_versions;
  v_sig_file uuid;
  v_capture app.epod_captures;
begin
  select * into v_shipment from app.shipment_orders where id = v_shipment_id;
  select * into v_shipment from app.transition_shipment_order(v_shipment_id, 'in_transit', v_shipment.record_version, null, null, 'idem-atw026-in-transit', v_actor, 'admin');
  select * into v_shipment from app.transition_shipment_order(v_shipment_id, 'delivered', v_shipment.record_version, null, 'POD-ATW026-1', 'idem-atw026-delivered', v_actor, 'admin');
  if v_shipment.status <> 'delivered' then
    raise exception 'assertion failed: expected status=delivered, got %', v_shipment.status;
  end if;

  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', v_supreme, 'supreme');
  v_doc_draft := app.create_config_draft('document:epod', v_tenant_id, 'tenant', null, v_actor, 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), v_actor, 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, v_actor, now(), 'admin');

  v_sig_file := (app.initiate_file_upload(
    v_tenant_id, 'epod', 'shipment_order', v_shipment_id, 'signature.jpg', 'image/jpeg', 20480, null, false, null, '{}'::uuid[], null, 'idem-atw026-epod-sig', v_actor, 'admin'
  )).id;
  perform app.record_file_scan_result(v_sig_file, 'clean', 'test-scanner-ref', v_actor, 'admin');

  select * into v_capture from app.start_epod_capture(v_tenant_id, v_shipment_id, (select id from app.milestone_events where shipment_order_id = v_shipment_id and milestone_code = 'delivery_arrival'), 'idem-atw026-epod-capture', v_actor, 'admin');
  select * into v_capture from app.set_epod_evidence(v_capture.id, 'Budi Penerima', 'Warehouse Staff', v_sig_file, null, jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(107.619123, -6.917464)), now(), v_actor, 'admin');
  select * into v_capture from app.submit_epod_capture(v_capture.id, v_capture.record_version, v_actor, 'admin');
  select * into v_capture from app.review_epod_capture(v_capture.id, 'approved', null, v_capture.record_version, v_actor, 'admin');

  select * into v_shipment from app.shipment_orders where id = v_shipment_id;
  select * into v_capture from app.complete_epod_capture(v_capture.id, v_capture.record_version, v_shipment.record_version, 'idem-atw026-epod-complete', v_actor, 'admin');
  if v_capture.status <> 'completed' then
    raise exception 'assertion failed: expected the ePOD capture to reach completed, got %', v_capture.status;
  end if;

  select * into v_shipment from app.shipment_orders where id = v_shipment_id;
  if v_shipment.status <> 'epod' then
    raise exception 'assertion failed: expected app.transition_shipment_order to have been called internally by app.complete_epod_capture (status -> epod), got %', v_shipment.status;
  end if;
end $$;

\echo '>> Part 1l: canonical non-duplication sweep -- every capability''s own read (dispatch board, tracking health, resource assignment, capacity reservation, milestone events, custody events, ePOD capture, canonical telemetry, current position) resolves to the SAME single shipment_order_id/vehicle_master_id -- never a forked copy of the canonical root'
do $$
declare
  v_shipment_id uuid := (select value::uuid from golden_state where key = 'shipment_id');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_distinct_shipment_refs integer;
  v_distinct_vehicle_refs integer;
begin
  select count(*) into v_distinct_shipment_refs from (
    select distinct shipment_order_id from app.resource_assignments where shipment_order_id = v_shipment_id
    union select distinct shipment_order_id from app.shipment_tracking_health where shipment_order_id = v_shipment_id
    union select distinct shipment_order_id from app.milestone_events where shipment_order_id = v_shipment_id
    union select distinct shipment_order_id from app.epod_captures where shipment_order_id = v_shipment_id
    union select distinct so.id from app.shipment_orders so where so.id = v_shipment_id
  ) x;
  if v_distinct_shipment_refs <> 1 then
    raise exception 'assertion failed: expected exactly 1 distinct shipment_order_id across every capability''s own read, found %', v_distinct_shipment_refs;
  end if;

  select count(*) into v_distinct_vehicle_refs from (
    select distinct vehicle_master_id from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_master_id
    union select distinct vehicle_master_id from app.vehicle_current_positions where vehicle_master_id = v_vehicle_master_id
    union select distinct vehicle_master_id from app.vehicle_capacity_reservations where vehicle_master_id = v_vehicle_master_id
    union select distinct resource_id from app.resource_assignments where resource_id = v_vehicle_master_id and role = 'vehicle'
  ) x;
  if v_distinct_vehicle_refs <> 1 then
    raise exception 'assertion failed: expected exactly 1 distinct vehicle_master_id across every capability''s own telemetry/capacity/assignment read, found %', v_distinct_vehicle_refs;
  end if;

  -- Exactly 2 legs, both under the SAME shipment_order_id, never a duplicated leg root.
  if (select count(*) from app.shipment_legs where shipment_order_id = v_shipment_id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 shipment_legs rows under the one canonical shipment_order_id';
  end if;
end $$;

\echo 'PART 1 (transport golden path) COMPLETE.'

-- =============================================================================
-- PART 2: Mandatory tracking E2E #1 -- Mobile Tracking package -- tenant
-- `atw026mobile`. Entitlement/consent/freshness checks included, on a clean
-- tenant so the entitlement OFF->ON and consent ON->OFF transitions are each
-- unambiguous (Part 1's own tenant grants consent once and never revokes it).
-- =============================================================================

\echo '>> Part 2 setup: a second, independent tenant with its own vehicle+driver+leg -- NO tracking.enabled config published yet, driver consent NOT yet granted'
create temporary table mobile_state (key text primary key, value text not null);
do $$
declare
  v_tenant uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000000996003';
  v_actor uuid := '00000000-0000-0000-0000-000000996001';
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
begin
  insert into auth.users (id, email) values
    (v_actor, 'admin@atw026mobile.test'),
    (v_supreme, 'supreme@atw026mobile.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('atw026mobile', 'ATW026 Mobile Tracking Co', 'idem-atw026mobile', 'tester');
  v_tenant := (select id from app.tenants where slug = 'atw026mobile');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant, v_actor, 'admin@atw026mobile.test', 'Mobile Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@atw026mobile.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_actor, 'tenant_admin', v_tenant, null, 'tester');

  v_edit_role := (app.create_role(v_tenant, 'Mobile Editor', 'full commercial + ops', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), v_actor, v_supreme, 'tester');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant, 'VEH-ATW026-M', 'ATW026 Mobile Truck', 'owned', 2000, 20, v_actor, 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, true, false, false, v_vehicle.record_version, v_actor, 'admin');
  -- Driver registered WITHOUT mobile tracking consent -- app.register_driver_operational_profile's own default.
  select * into v_driver from app.register_driver_operational_profile(v_tenant, 'DRV-ATW026-M', 'Driver ATW026 Mobile', 'B2', (now() + interval '2 years')::date, v_actor, 'admin');
  if v_driver.mobile_tracking_consent then
    raise exception 'assertion failed: expected a freshly registered driver profile to default mobile_tracking_consent=false, got true';
  end if;

  perform app.capture_lead(v_tenant, 'manual', null, 'ATW026 Mobile Shipper', 'Jane Mobile', 'jane@atw026mobile.test', '0811', v_actor, null, v_actor, 'tester');
  select * into v_lead from app.leads where email = 'jane@atw026mobile.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_actor, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'ATW026 Mobile Shipper', 'ATW026M', '11.111.111.8-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 8', 'city', 'Jakarta', 'country', 'ID'), v_actor, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant, 'Jane Mobile Ops', 'Procurement Lead', 'jane@atw026mobile.test', '0811', v_actor, null, v_actor, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_actor, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant, v_prospect.id, 'ATW026 mobile lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bogor', 'target_ready_date', '2026-08-01'),
    v_actor, null, v_actor, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_actor, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant, 'VENDOR-ATW026M-1', 'Contoso ATW026 Mobile Line', 'land_freight', 'FTL', 'Jakarta', 'Bogor', '20ft',
    null, null, null, null, 'IDR', 2000000, null, '[]'::jsonb, now(), null, null, v_actor, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_actor, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_actor, 'tester');
  select * into v_rule from app.create_margin_rule_version(v_tenant, 20.00, 'half_up', v_actor, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_actor, 'tester');
  perform app.calculate_margin(v_selection.id, 2400000, 'IDR', 0, v_actor, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_actor, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'ATW026 mobile lane', v_calc_id, 1, 2400000, 0, 0, v_actor, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_actor, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_actor, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Mobile Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_actor, 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_actor, 'admin');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_actor, 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_actor, 'admin');
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-atw026mobile-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bogor',
    now() + interval '1 day', now() + interval '2 days', 500, 500, 8, 500, 500, 8, null, v_actor, 'admin'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_actor, 'admin');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-atw026mobile-to-planned', v_actor, 'admin');

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-atw026mobile-leg1', 1, 'land', null, now(), now() + interval '3 hours', v_actor, 'admin');
  perform app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), v_actor, 'admin');
  perform app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bogor Warehouse', null, 106.804430, -6.595038, now() + interval '3 hours', v_actor, 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 500, 500, 8, v_actor, 'admin');
  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), v_actor, 'admin');

  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, v_actor, 'admin');
  perform app.assign_resource(v_shipment.id, 'driver', v_driver.driver_master_id, v_actor, 'admin');

  perform app.upsert_shipment_leg_tracking_policy(
    v_leg.id, true, array['driver_mobile'], 'driver_mobile', array['driver_mobile'],
    300, 100, 30, 'leg_dispatch', 'leg_complete', null, true, 3600, v_actor, 'admin'
  );

  insert into mobile_state (key, value) values
    ('tenant_id', v_tenant::text),
    ('actor_id', v_actor::text),
    ('shipment_id', v_shipment.id::text),
    ('leg_id', v_leg.id::text),
    ('vehicle_master_id', v_vehicle.vehicle_master_id::text),
    ('driver_profile_id', v_driver.id::text),
    ('driver_master_id', v_driver.driver_master_id::text);
end $$;

\echo '>> Part 2a: entitlement is disclosed, never a hard gate (ATW-226A design) -- app.is_shipment_tracking_entitled is false (no tracking.enabled config published for this tenant); consent is the REAL, enforced gate -- app.start_leg_tracking_session correctly rejects driver_mobile with source_not_eligible while consent=false, independent of entitlement'
do $$
declare
  v_tenant_id uuid := (select value::uuid from mobile_state where key = 'tenant_id');
  v_leg_id uuid := (select value::uuid from mobile_state where key = 'leg_id');
  v_driver_master_id uuid := (select value::uuid from mobile_state where key = 'driver_master_id');
  v_actor uuid := (select value::uuid from mobile_state where key = 'actor_id');
  v_entitled boolean;
  v_rejected boolean := false;
begin
  v_entitled := app.is_shipment_tracking_entitled(v_tenant_id);
  if v_entitled then
    raise exception 'assertion failed: expected entitlement=false before any tracking.enabled config is published';
  end if;

  begin
    perform app.start_leg_tracking_session(v_leg_id, 'driver_mobile', 'driver', v_driver_master_id, null, v_actor, 'admin');
  exception
    when others then
      if sqlerrm like 'source_not_eligible%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected app.start_leg_tracking_session to reject driver_mobile for a non-consenting driver with source_not_eligible';
  end if;
end $$;

\echo '>> Part 2b: consent granted (app.set_driver_mobile_tracking_consent, ATW-223) -- session now starts successfully even though entitlement is STILL false, and the session honestly snapshots tracking_entitled_at_start=false (disclosed, not blocking) -- the exact ATW-225 design this repository''s own migration comments describe, now proven with a real, live entitlement=false tenant rather than merely asserted'
do $$
declare
  v_tenant_id uuid := (select value::uuid from mobile_state where key = 'tenant_id');
  v_leg_id uuid := (select value::uuid from mobile_state where key = 'leg_id');
  v_driver_profile_id uuid := (select value::uuid from mobile_state where key = 'driver_profile_id');
  v_driver_master_id uuid := (select value::uuid from mobile_state where key = 'driver_master_id');
  v_actor uuid := (select value::uuid from mobile_state where key = 'actor_id');
  v_driver app.driver_operational_profiles;
  v_session app.shipment_leg_tracking_sessions;
begin
  select * into v_driver from app.driver_operational_profiles where id = v_driver_profile_id;
  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver_profile_id, true, v_driver.record_version, v_actor, 'admin');
  if not v_driver.mobile_tracking_consent or v_driver.mobile_tracking_consent_at is null then
    raise exception 'assertion failed: expected consent=true with a real consent timestamp after app.set_driver_mobile_tracking_consent';
  end if;

  select * into v_session from app.start_leg_tracking_session(v_leg_id, 'driver_mobile', 'driver', v_driver_master_id, null, v_actor, 'admin');
  if v_session.tracking_entitled_at_start <> false then
    raise exception 'assertion failed: expected tracking_entitled_at_start=false (honestly snapshotted, entitlement still not published for this tenant), got %', v_session.tracking_entitled_at_start;
  end if;

  insert into mobile_state (key, value) values ('session1_id', v_session.id::text);
end $$;

\echo '>> Part 2c: publishing tracking.enabled=true (Configuration Engine PLT-121, the SAME general-purpose config draft/publish RPCs every other config-governed capability in this repository uses) flips app.is_shipment_tracking_entitled from false to true for this tenant -- a real, dynamic composition across Platform Core and ATW-226A, never a hardcoded/fixture-only value'
do $$
declare
  v_tenant_id uuid := (select value::uuid from mobile_state where key = 'tenant_id');
  v_actor uuid := (select value::uuid from mobile_state where key = 'actor_id');
  v_draft app.config_versions;
  v_entitled boolean;
begin
  v_draft := app.create_config_draft('feature', v_tenant_id, 'tenant', null, v_actor, 'admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'tracking.enabled', 'value', true),
    jsonb_build_object('key', 'tracking.package', 'value', 'standard'),
    jsonb_build_object('key', 'tracking.limits', 'value', jsonb_build_object('max_tracked_vehicles', 50, 'max_mobile_sessions', 50, 'history_retention_days', 30))
  ), v_actor, 'admin');
  perform app.publish_config_version(v_draft.id, v_actor, now(), 'admin');

  v_entitled := app.is_shipment_tracking_entitled(v_tenant_id);
  if not v_entitled then
    raise exception 'assertion failed: expected entitlement=true immediately after publishing tracking.enabled=true';
  end if;
end $$;

\echo '>> Part 2d: a NEW session started after entitlement flips true snapshots tracking_entitled_at_start=true -- the SAME app.start_leg_tracking_session RPC, now reflecting the SAME tenant''s own real, live entitlement state; the driver_mobile HTTPS ingestion RPC then reports real sequential positions, composing through arbitration into the canonical projection exactly as Part 1 already proved, on a genuinely independent tenant this time'
do $$
declare
  v_leg_id uuid := (select value::uuid from mobile_state where key = 'leg_id');
  v_driver_master_id uuid := (select value::uuid from mobile_state where key = 'driver_master_id');
  v_vehicle_master_id uuid := (select value::uuid from mobile_state where key = 'vehicle_master_id');
  v_actor uuid := (select value::uuid from mobile_state where key = 'actor_id');
  v_session app.shipment_leg_tracking_sessions;
  v_start record;
  v_ingest record;
  v_pos record;
  v_reports_count integer;
begin
  -- app.end_leg_tracking_session is keyed by shipment_leg_id (it resolves the
  -- CURRENT session for that leg itself), not by session id directly.
  perform app.end_leg_tracking_session(v_leg_id, 'manual_stop', 'ending session 1 to start a fresh, entitlement-true session', v_actor, 'admin');

  select * into v_session from app.start_leg_tracking_session(v_leg_id, 'driver_mobile', 'driver', v_driver_master_id, null, v_actor, 'admin');
  if v_session.tracking_entitled_at_start <> true then
    raise exception 'assertion failed: expected tracking_entitled_at_start=true on a session started after publishing tracking.enabled=true, got %', v_session.tracking_entitled_at_start;
  end if;

  select * into v_start from app.start_driver_mobile_session(v_session.id, 24, v_actor, 'admin');

  -- Three real, sequential HTTPS-shaped position reports -- the exact RPC
  -- app/api/tracking/driver-mobile/route.ts's own POST handler calls unmodified
  -- (server/mutations/driver-mobile-tracking.ts's ingestDriverMobileReport wraps
  -- this 1:1; no live Supabase/PostgREST endpoint exists in this sandbox to
  -- exercise the HTTP hop itself above this RPC -- ADR-0010, ISS-2026-019).
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_start.raw_token, 'atw026mobile-client', 'location', now()::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.845599, -6.208763)), 6.0, 90, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then raise exception 'assertion failed: report 1 expected ok, got %', v_ingest.ingest_status; end if;
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_start.raw_token, 'atw026mobile-client', 'location', (now() + interval '5 minutes')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.83, -6.30)), 6.0, 89, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then raise exception 'assertion failed: report 2 expected ok, got %', v_ingest.ingest_status; end if;
  -- 25 minutes after report 2 (the ~33km remaining hop to Bogor implies ~99 km/h,
  -- safely under the 200 km/h impossible-movement ceiling).
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_start.raw_token, 'atw026mobile-client', 'location', (now() + interval '25 minutes')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.804430, -6.595038)), 6.0, 88, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then raise exception 'assertion failed: report 3 expected ok, got %', v_ingest.ingest_status; end if;

  select count(*) into v_reports_count from app.driver_mobile_position_reports where tenant_id = (select value::uuid from mobile_state where key = 'tenant_id') and report_type = 'location';
  if v_reports_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 raw driver_mobile_position_reports for THIS tenant (the raw log, kept separate from the canonical projection per ATW-226C design note 2), found %', v_reports_count;
  end if;

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_master_id);
  if v_pos.source_type <> 'driver_mobile' or (v_pos.location_geojson -> 'coordinates' -> 0)::text::numeric <> 106.804430 then
    raise exception 'assertion failed: expected the canonical current position to reflect the THIRD (newest) real report, got %', v_pos;
  end if;

  insert into mobile_state (key, value) values ('session2_id', v_session.id::text);
end $$;

\echo '>> Part 2e: freshness is real and dynamic, not a fixed flag -- immediately after real telemetry, app.shipment_tracking_health/app.get_tenant_tracking_coverage report fresh/tracked; backdating the canonical position''s own received_at past the tenant''s freshness_threshold_seconds (300s) and forcing a real recompute flips both to stale, proving the freshness classifier actually reacts to elapsed time, not a cached label'
do $$
declare
  v_tenant_id uuid := (select value::uuid from mobile_state where key = 'tenant_id');
  v_shipment_id uuid := (select value::uuid from mobile_state where key = 'shipment_id');
  v_vehicle_master_id uuid := (select value::uuid from mobile_state where key = 'vehicle_master_id');
  v_actor uuid := (select value::uuid from mobile_state where key = 'actor_id');
  v_health app.shipment_tracking_health;
  v_coverage record;
begin
  select * into v_health from app.recalculate_shipment_tracking_health(v_shipment_id);
  if v_health.freshness_status <> 'fresh' or v_health.tracking_status <> 'tracked' then
    raise exception 'assertion failed: expected fresh/tracked immediately after real telemetry, got freshness=% tracking=%', v_health.freshness_status, v_health.tracking_status;
  end if;
  select * into v_coverage from app.get_tenant_tracking_coverage(v_tenant_id, v_actor) where vehicle_master_id = v_vehicle_master_id;
  if v_coverage.coverage_status <> 'tracked' then
    raise exception 'assertion failed: expected app.get_tenant_tracking_coverage coverage_status=tracked immediately after real telemetry, got %', v_coverage.coverage_status;
  end if;

  -- Backdate the REAL canonical row's own received_at by 10 minutes (600s) --
  -- past freshness_threshold_seconds (300s, "stale") but within its 3x band
  -- (900s, still "stale" rather than "offline" -- both app.get_vehicle_source_
  -- health and app.get_tenant_tracking_coverage share the identical 1x/3x
  -- banding, confirmed by direct inspection of both function bodies). The
  -- identical, disclosed test-only technique ATW-226F's own db-test already
  -- established ("no RPC exists to backdate a real device's own clock, nor
  -- should one").
  update app.vehicle_current_positions set received_at = now() - interval '10 minutes' where vehicle_master_id = v_vehicle_master_id;
  update app.vehicle_source_health set last_seen_received_at = now() - interval '10 minutes' where vehicle_master_id = v_vehicle_master_id;

  select * into v_health from app.recalculate_shipment_tracking_health(v_shipment_id);
  if v_health.freshness_status <> 'stale' or v_health.tracking_status <> 'stale' then
    raise exception 'assertion failed: expected freshness_status=stale tracking_status=stale once received_at is older than freshness_threshold_seconds (300s) and a real recompute runs, got freshness=% tracking=%', v_health.freshness_status, v_health.tracking_status;
  end if;
  select * into v_coverage from app.get_tenant_tracking_coverage(v_tenant_id, v_actor) where vehicle_master_id = v_vehicle_master_id;
  if v_coverage.coverage_status <> 'stale' then
    raise exception 'assertion failed: expected app.get_tenant_tracking_coverage coverage_status=stale after the SAME backdated received_at, got %', v_coverage.coverage_status;
  end if;
end $$;

\echo '>> Part 2f: revoking consent (app.set_driver_mobile_tracking_consent, p_consent=false) blocks a NEW session from starting -- consent is re-checked at the moment of session start, not merely once at driver registration; the CURRENTLY ACTIVE session from Part 2d is untouched (out of this RPC''s own scope, matching ATW-223''s own disclosed design)'
do $$
declare
  v_tenant_id uuid := (select value::uuid from mobile_state where key = 'tenant_id');
  v_leg_id uuid := (select value::uuid from mobile_state where key = 'leg_id');
  v_driver_profile_id uuid := (select value::uuid from mobile_state where key = 'driver_profile_id');
  v_driver_master_id uuid := (select value::uuid from mobile_state where key = 'driver_master_id');
  v_actor uuid := (select value::uuid from mobile_state where key = 'actor_id');
  v_session2_id uuid := (select value::uuid from mobile_state where key = 'session2_id');
  v_driver app.driver_operational_profiles;
  v_rejected boolean := false;
  v_still_current boolean;
begin
  select * into v_driver from app.driver_operational_profiles where id = v_driver_profile_id;
  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver_profile_id, false, v_driver.record_version, v_actor, 'admin');
  if v_driver.mobile_tracking_consent or v_driver.mobile_tracking_consent_at is not null then
    raise exception 'assertion failed: expected consent=false with a cleared consent timestamp after revocation, got consent=% at=%', v_driver.mobile_tracking_consent, v_driver.mobile_tracking_consent_at;
  end if;

  select is_current into v_still_current from app.shipment_leg_tracking_sessions where id = v_session2_id;
  if not v_still_current then
    raise exception 'assertion failed: expected the already-active session to remain untouched by a later consent revocation (out of scope for app.set_driver_mobile_tracking_consent, a future session-start/handoff/renewal concern)';
  end if;

  perform app.end_leg_tracking_session(v_leg_id, 'manual_stop', 'ending before revoked-consent retry', v_actor, 'admin');
  begin
    perform app.start_leg_tracking_session(v_leg_id, 'driver_mobile', 'driver', v_driver_master_id, null, v_actor, 'admin');
  exception
    when others then
      if sqlerrm like 'source_not_eligible%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected a NEW session start to be rejected source_not_eligible after consent was revoked';
  end if;
end $$;

\echo 'PART 2 (Mandatory tracking E2E #1 -- Mobile Tracking package) COMPLETE.'

-- =============================================================================
-- PART 4: Mandatory tracking E2E #3 -- Existing GPS Integration (third-party
-- platform) -- extends tenant `atw026golden`'s own already-registered webhook
-- connection + provider_vehicle_mapping (Part 1 setup), reusing the SAME vehicle.
--
-- CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE (245_*.md External-evidence policy
-- item 2): no live third-party GPS platform credential, API access, or provider
-- contract exists anywhere in this repository -- confirmed by direct inspection of
-- docs/runtime/KNOWN_ISSUES.md (no issue entry claims one), ATW-226E's own build
-- log residual disclosure ("No live third-party GPS platform contract exists"),
-- and ATW-226I's own closing residual disclosure (same). This is consistent with
-- every prior ATW-226 checkpoint's own disclosure, not a new gap this task
-- introduces. The live-provider half of this mandatory E2E is therefore skipped,
-- non-blocking per the policy's own closure-treatment clause. The deterministic
-- adapter-CONTRACT half below (authentication/signature check, schema/mapping
-- validation, replay/duplicate defense, quarantine of an unmapped vehicle, and
-- real canonical projection once accepted) is NOT skippable and is real,
-- executed evidence below -- exactly what the policy requires in lieu of a live
-- vendor.
-- =============================================================================

\echo '>> Part 4a: adapter contract -- malformed JSON, bad signature (tampered payload), stale timestamp (outside ADR-0011''s 5-minute window), and an unmapped external vehicle_id are each correctly rejected/quarantined, never silently accepted or crashing the ingestion RPC'
do $$
declare
  v_connection_id uuid := (select value::uuid from golden_state where key = 'connection_id');
  v_secret text := (select value from golden_state where key = 'webhook_secret');
  v_ts bigint;
  v_payload text;
  v_signature text;
  v_result record;
begin
  -- Malformed JSON body.
  v_ts := extract(epoch from now())::bigint;
  v_payload := '{not valid json';
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-contract-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected malformed JSON to be rejected invalid, got %', v_result.ingest_status;
  end if;

  -- Tampered payload -- signature computed over DIFFERENT bytes than what is sent.
  v_ts := extract(epoch from now())::bigint;
  v_payload := jsonb_build_object('event_id', 'atw026-tamper-1', 'vehicle_id', 'EXT-ATW026-001', 'event_type', 'location', 'timestamp', now()::text, 'latitude', -6.9, 'longitude', 107.6)::text;
  v_signature := encode(hmac(v_ts::text || '.' || (v_payload || 'tampered'), v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-contract-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected a tampered-payload signature mismatch to be rejected invalid, got %', v_result.ingest_status;
  end if;

  -- Stale timestamp -- otherwise-correct signature, but 10 minutes outside ADR-0011's 5-minute tolerance.
  v_ts := extract(epoch from (now() - interval '10 minutes'))::bigint;
  v_payload := jsonb_build_object('event_id', 'atw026-stale-1', 'vehicle_id', 'EXT-ATW026-001', 'event_type', 'location', 'timestamp', now()::text, 'latitude', -6.9, 'longitude', 107.6)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-contract-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected a stale timestamp (correct signature) to be rejected invalid, got %', v_result.ingest_status;
  end if;

  -- Unmapped external vehicle_id -- correctly signed, well-formed, but no
  -- app.provider_vehicle_mappings row exists for this external id -- quarantined
  -- (raw payload preserved), never silently dropped.
  v_ts := extract(epoch from now())::bigint;
  v_payload := jsonb_build_object('event_id', 'atw026-unmapped-1', 'vehicle_id', 'EXT-ATW026-UNMAPPED', 'event_type', 'location', 'timestamp', now()::text, 'latitude', -6.9, 'longitude', 107.6)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-contract-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'quarantined' then
    raise exception 'assertion failed: expected an unmapped external vehicle_id to be quarantined, got %', v_result.ingest_status;
  end if;
  if not exists (select 1 from app.third_party_provider_ingestion_attempts where connection_id = v_connection_id and result = 'quarantined' and raw_payload ->> 'event_id' = 'atw026-unmapped-1') then
    raise exception 'assertion failed: expected the quarantined attempt to preserve the full raw_payload, never silently dropped';
  end if;
end $$;

\echo '>> Part 4b: a correctly-signed, correctly-mapped report is accepted and canonically projected (app.canonical_telemetry_events, source_type=third_party_platform) -- composing through the SAME app.arbitrate_and_project_vehicle_position every other source uses; the identical event_id replayed returns duplicate, never re-inserted'
do $$
declare
  v_connection_id uuid := (select value::uuid from golden_state where key = 'connection_id');
  v_secret text := (select value from golden_state where key = 'webhook_secret');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_ts bigint;
  v_payload text;
  v_signature text;
  v_result record;
  v_stored_count integer;
begin
  v_ts := extract(epoch from now())::bigint;
  v_payload := jsonb_build_object('event_id', 'atw026-tpp-valid-1', 'vehicle_id', 'EXT-ATW026-001', 'event_type', 'location', 'timestamp', (now() + interval '90 minutes')::text, 'latitude', -6.90, 'longitude', 107.60, 'speed_kmh', 45)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-contract-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected a correctly-signed, correctly-mapped report to be accepted, got %', v_result.ingest_status;
  end if;

  select count(*) into v_stored_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_master_id and source_type = 'third_party_platform' and source_report_id = v_result.report_id;
  if v_stored_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 canonical_telemetry_events row for this third-party report (composed through the SAME arbitration entry point every other source uses), found %', v_stored_count;
  end if;

  -- Replay: identical event_id, re-signed (a real retried webhook delivery would
  -- resend the SAME body/timestamp/signature) -- returns duplicate, never re-inserted.
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-contract-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'duplicate' then
    raise exception 'assertion failed: expected a replayed identical event_id to return duplicate, got %', v_result.ingest_status;
  end if;
  select count(*) into v_stored_count from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_master_id and source_type = 'third_party_platform';
  if v_stored_count <> 1 then
    raise exception 'assertion failed: expected the replay to NOT create a second canonical_telemetry_events row, found %', v_stored_count;
  end if;
end $$;

\echo 'PART 4 (Mandatory tracking E2E #3 -- Existing GPS Integration / third-party) COMPLETE -- deterministic adapter-contract half real and unskipped; live-provider half CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE.'

-- =============================================================================
-- PART 5: Mandatory tracking E2E #4 -- Hybrid source conflict/fallback/
-- arbitration -- explicit SEQUENTIAL (not merely concurrent-load) proof of
-- source-switch hysteresis and full source-history preservation, extending
-- tenant `atw026golden`'s own vehicle (already carrying real driver_mobile/
-- direct_device/third_party_platform traffic from Parts 1 and 4).
--
-- scripts/load-tests/pgbench/hybrid-arbitration.sql's own real CONCURRENT
-- scenario (49,591+ conflicting transactions proven at ATW-024, re-confirmed
-- fresh as part of this checkpoint -- see the completion report for that
-- separate command's own output) already proves throughput/no-lost-update under
-- contention. This part is deliberately its sequential complement: a fully
-- deterministic, hand-driven chain of THREE real switches across all three
-- source types, each one individually asserted for hysteresis-suppression
-- immediately after the prior switch, then success once hysteresis elapses --
-- and a final, exact, row-by-row check that app.vehicle_source_switches
-- preserves the COMPLETE, correctly-ordered lineage, never overwritten or
-- summarized away.
--
-- Every report below uses the SAME fixed coordinate (0km implied distance
-- between any two reports regardless of time gap) specifically to isolate
-- hysteresis/priority/staleness behavior from the impossible-movement check
-- (already exhaustively proven elsewhere -- ATW-226F's own db-test, and Parts
-- 1/2 above at real inter-city distances/timings).
-- =============================================================================

\echo '>> Part 5 setup: force a clean baseline -- the vehicle''s current position and every existing source switch are pushed 3 hours into the past, so the very first new report below starts from an unambiguous, fully-elapsed state. A baseline timestamp t0, strictly newer than the current position''s own existing event_at (Parts 1/2/4 above deliberately used future-dated event_at values to simulate in-script time passing -- t0 must outrun the highest of those, not merely wall-clock now()), anchors every event_at in this Part -- the arbitration rule "current position never moves backward in event_at" is independent of, and enforced regardless of, received_at staleness.'
do $$
declare
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_pre_existing_switches integer;
  v_t0 timestamptz;
begin
  update app.vehicle_current_positions set received_at = now() - interval '3 hours' where vehicle_master_id = v_vehicle_master_id;
  update app.vehicle_source_switches set switched_at = now() - interval '3 hours' where vehicle_master_id = v_vehicle_master_id;
  select count(*) into v_pre_existing_switches from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id;
  insert into golden_state (key, value) values ('hybrid_pre_existing_switch_count', v_pre_existing_switches::text);

  select greatest(now(), max(event_at) + interval '1 second') into v_t0 from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_master_id;
  insert into golden_state (key, value) values ('hybrid_t0', v_t0::text);
end $$;

\echo '>> Part 5 switch 1: direct_device wins via stale-fallback (current source, whatever it was, is now stale) -- a real, evidenced switch row'
do $$
declare
  v_device_id uuid := (select value::uuid from golden_state where key = 'device_id');
  v_api_key text := (select value from golden_state where key = 'api_key_gateway');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_t0 timestamptz := (select value::timestamptz from golden_state where key = 'hybrid_t0');
  v_pos record;
  v_switch_count integer;
  v_pre_existing integer := (select value::integer from golden_state where key = 'hybrid_pre_existing_switch_count');
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', v_t0::text, 'longitude', 107.6, 'latitude', -6.9, 'speed_kmh', 20)),
    'atw026-hybrid-gateway'
  );
  select * into v_pos from app.get_vehicle_current_position(v_vehicle_master_id);
  if v_pos.source_type <> 'direct_device' then
    raise exception 'assertion failed: expected direct_device to win via stale-fallback, current source is %', v_pos.source_type;
  end if;
  select count(*) into v_switch_count from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id;
  if v_switch_count <> v_pre_existing + 1 then
    raise exception 'assertion failed: expected exactly 1 new switch row (total %), found %', v_pre_existing + 1, v_switch_count;
  end if;
end $$;

\echo '>> Part 5 hysteresis check A: immediately after switch 1, driver_mobile (the tenant-default HIGHEST-priority source) would win by priority alone once hysteresis elapses (proven below) -- but attempted immediately, it is correctly suppressed; current stays direct_device, switch count unchanged'
do $$
declare
  v_raw_token text := (select value from golden_state where key = 'leg1_mobile_raw_token');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_t0 timestamptz := (select value::timestamptz from golden_state where key = 'hybrid_t0');
  v_pre_existing integer := (select value::integer from golden_state where key = 'hybrid_pre_existing_switch_count');
  v_ingest record;
  v_pos record;
  v_switch_count integer;
begin
  select * into v_ingest from app.ingest_driver_mobile_report(
    v_raw_token, 'atw026-hybrid-client', 'location', (v_t0 + interval '30 seconds')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(107.6, -6.9)), 5.0, 80, true, true, '{}'::jsonb
  );
  if v_ingest.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the report itself to be accepted (stored), got %', v_ingest.ingest_status;
  end if;

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_master_id);
  if v_pos.source_type <> 'direct_device' then
    raise exception 'assertion failed: expected the immediate driver_mobile reclaim to be suppressed by hysteresis, current source is %', v_pos.source_type;
  end if;
  select count(*) into v_switch_count from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id;
  if v_switch_count <> v_pre_existing + 1 then
    raise exception 'assertion failed: expected NO new switch row while still inside the hysteresis window (total still %), found %', v_pre_existing + 1, v_switch_count;
  end if;
end $$;

\echo '>> Part 5 switch 2: hysteresis window manually elapsed (real-world equivalent: switch_hysteresis_seconds, 120s default, has genuinely passed) -- driver_mobile now reclaims by priority alone, current source still fresh (NOT a stale-fallback switch -- proves priority-based reclaim is a real, distinct arbitration path)'
do $$
declare
  v_raw_token text := (select value from golden_state where key = 'leg1_mobile_raw_token');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_t0 timestamptz := (select value::timestamptz from golden_state where key = 'hybrid_t0');
  v_pre_existing integer := (select value::integer from golden_state where key = 'hybrid_pre_existing_switch_count');
  v_ingest record;
  v_pos record;
  v_switch app.vehicle_source_switches;
  v_switch_count integer;
begin
  update app.vehicle_source_switches set switched_at = now() - interval '3 minutes' where vehicle_master_id = v_vehicle_master_id;

  select * into v_ingest from app.ingest_driver_mobile_report(
    v_raw_token, 'atw026-hybrid-client', 'location', (v_t0 + interval '1 minute')::text::timestamptz,
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(107.6, -6.9)), 5.0, 80, true, true, '{}'::jsonb
  );

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_master_id);
  if v_pos.source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected driver_mobile to reclaim by priority once hysteresis elapsed, current source is %', v_pos.source_type;
  end if;

  select count(*) into v_switch_count from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id;
  if v_switch_count <> v_pre_existing + 2 then
    raise exception 'assertion failed: expected exactly 2 new switch rows total (total %), found %', v_pre_existing + 2, v_switch_count;
  end if;
  select * into v_switch from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id order by switched_at desc limit 1;
  if v_switch.from_source_type <> 'direct_device' or v_switch.to_source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected switch 2 to record from=direct_device to=driver_mobile, got from=% to=%', v_switch.from_source_type, v_switch.to_source_type;
  end if;
end $$;

\echo '>> Part 5 hysteresis check B: immediately after switch 2, third_party_platform (lowest priority) attempts a fallback even though the current source (driver_mobile) is ALSO now stale -- staleness alone is not enough; hysteresis still correctly blocks it'
do $$
declare
  v_connection_id uuid := (select value::uuid from golden_state where key = 'connection_id');
  v_secret text := (select value from golden_state where key = 'webhook_secret');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_t0 timestamptz := (select value::timestamptz from golden_state where key = 'hybrid_t0');
  v_pre_existing integer := (select value::integer from golden_state where key = 'hybrid_pre_existing_switch_count');
  v_ts bigint := extract(epoch from now())::bigint;
  v_payload text;
  v_signature text;
  v_result record;
  v_pos record;
  v_switch_count integer;
begin
  -- Make the CURRENT source (driver_mobile) stale too -- if hysteresis were not
  -- also gating this attempt, a stale-fallback switch would otherwise be legitimate.
  update app.vehicle_current_positions set received_at = now() - interval '20 minutes' where vehicle_master_id = v_vehicle_master_id;

  v_payload := jsonb_build_object('event_id', 'atw026-hybrid-hyst-b', 'vehicle_id', 'EXT-ATW026-001', 'event_type', 'location', 'timestamp', (v_t0 + interval '2 minutes')::text, 'latitude', -6.9, 'longitude', 107.6)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-hybrid-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the report itself to be accepted (stored), got %', v_result.ingest_status;
  end if;

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_master_id);
  if v_pos.source_type <> 'driver_mobile' then
    raise exception 'assertion failed: expected the fallback attempt to be suppressed by hysteresis despite a stale current source, current source is %', v_pos.source_type;
  end if;
  select count(*) into v_switch_count from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id;
  if v_switch_count <> v_pre_existing + 2 then
    raise exception 'assertion failed: expected still exactly 2 new switch rows total (total %), found %', v_pre_existing + 2, v_switch_count;
  end if;
end $$;

\echo '>> Part 5 switch 3: hysteresis elapsed a second time -- third_party_platform now completes its stale-fallback switch over the (still-stale) driver_mobile source -- a real, evidenced, third switch row'
do $$
declare
  v_connection_id uuid := (select value::uuid from golden_state where key = 'connection_id');
  v_secret text := (select value from golden_state where key = 'webhook_secret');
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_t0 timestamptz := (select value::timestamptz from golden_state where key = 'hybrid_t0');
  v_pre_existing integer := (select value::integer from golden_state where key = 'hybrid_pre_existing_switch_count');
  v_ts bigint := extract(epoch from now())::bigint;
  v_payload text;
  v_signature text;
  v_result record;
  v_pos record;
  v_switch app.vehicle_source_switches;
  v_switch_count integer;
begin
  update app.vehicle_source_switches set switched_at = now() - interval '3 minutes' where vehicle_master_id = v_vehicle_master_id;

  v_payload := jsonb_build_object('event_id', 'atw026-hybrid-switch3', 'vehicle_id', 'EXT-ATW026-001', 'event_type', 'location', 'timestamp', (v_t0 + interval '3 minutes')::text, 'latitude', -6.9, 'longitude', 107.6)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-hybrid-client', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected the report to be accepted, got %', v_result.ingest_status;
  end if;

  select * into v_pos from app.get_vehicle_current_position(v_vehicle_master_id);
  if v_pos.source_type <> 'third_party_platform' then
    raise exception 'assertion failed: expected third_party_platform to complete its stale-fallback switch, current source is %', v_pos.source_type;
  end if;

  select count(*) into v_switch_count from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id;
  if v_switch_count <> v_pre_existing + 3 then
    raise exception 'assertion failed: expected exactly 3 new switch rows total (total %), found %', v_pre_existing + 3, v_switch_count;
  end if;
  select * into v_switch from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id order by switched_at desc limit 1;
  if v_switch.from_source_type <> 'driver_mobile' or v_switch.to_source_type <> 'third_party_platform' or (v_switch.evidence ->> 'current_is_stale')::boolean is not true then
    raise exception 'assertion failed: expected switch 3 to record from=driver_mobile to=third_party_platform with real evidenced staleness, got %', v_switch;
  end if;
end $$;

\echo '>> Part 5 final: full source-history preservation -- app.vehicle_source_switches for this ONE vehicle contains the COMPLETE, correctly-ordered lineage of every switch that ever occurred (Part 1''s own bootstrap plus this Part''s own 3 driven switches), never overwritten/summarized/truncated -- and app.canonical_telemetry_events retains every real event from every part above, applied and rejected alike'
do $$
declare
  v_vehicle_master_id uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_switches text[];
  v_total_switches integer;
  v_total_events integer;
  v_expected_sequence text[] := array['bootstrap:driver_mobile', 'stale_fallback:direct_device', 'priority_reclaim:driver_mobile', 'stale_fallback:third_party_platform'];
begin
  select array_agg(to_source_type order by switched_at asc) into v_switches from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id;
  select count(*) into v_total_switches from app.vehicle_source_switches where vehicle_master_id = v_vehicle_master_id;
  if v_total_switches <> 4 then
    raise exception 'assertion failed: expected exactly 4 total switch rows for this vehicle''s own complete lineage (1 bootstrap + 3 driven here), found % (%)', v_total_switches, v_switches;
  end if;
  if v_switches <> array['driver_mobile', 'direct_device', 'driver_mobile', 'third_party_platform'] then
    raise exception 'assertion failed: expected the exact ordered to_source_type lineage [driver_mobile, direct_device, driver_mobile, third_party_platform], got %', v_switches;
  end if;

  select count(*) into v_total_events from app.canonical_telemetry_events where vehicle_master_id = v_vehicle_master_id;
  if v_total_events < 10 then
    raise exception 'assertion failed: expected at least 10 real canonical_telemetry_events rows preserved across every part of this file (applied and rejected alike -- nothing silently dropped), found %', v_total_events;
  end if;
  if (select count(*) from app.get_vehicle_telemetry_history(v_vehicle_master_id, null, 500)) <> v_total_events then
    raise exception 'assertion failed: expected app.get_vehicle_telemetry_history to reflect every one of the % real events, count mismatch', v_total_events;
  end if;
end $$;

\echo 'PART 5 (Mandatory tracking E2E #4 -- Hybrid source conflict/fallback/arbitration, sequential complement) COMPLETE.'

-- =============================================================================
-- PART 6: the accepted-work invariant -- "no raw telemetry directly mutates
-- shipment lifecycle" (Prompt 248's own closure checklist item 15). A canonical_
-- telemetry_events insert never itself changes app.shipment_orders.status; only
-- an explicit, separately-authorized transition RPC does. Proven both
-- dynamically (real before/after row snapshots across a real telemetry blast)
-- and statically (a repository-wide pg_get_functiondef source-text sweep).
-- =============================================================================

\echo '>> Part 6a: static analysis -- every real ingestion/arbitration/milestone/exception function''s own compiled source (pg_get_functiondef against the LIVE function actually installed in this database, not merely the migration file text) contains zero references to mutating app.shipment_orders -- the exhaustive, repository-wide grep this checkpoint independently performed (every "update app.shipment_orders" statement anywhere in supabase/migrations/) found exactly three writers: app.confirm_shipment_order, app.cancel_shipment_order, and app.transition_shipment_order (called directly, or internally by app.dispatch_shipment_order/app.complete_epod_capture) -- confirmed here live against the actual installed function bodies'
do $$
declare
  v_fn text;
  v_src text;
  v_violations text[] := '{}';
  v_functions text[] := array[
    'app.ingest_driver_mobile_report', 'app.ingest_direct_device_telemetry_batch', 'app.ingest_third_party_provider_webhook_event',
    'app.arbitrate_and_project_vehicle_position', 'app.evaluate_geofence_and_deviation_signals', 'app.evaluate_stop_geofence',
    'app.evaluate_route_deviation', 'app.upsert_milestone_candidate', 'app.upsert_exception_signal',
    'app.confirm_milestone_candidate', 'app.confirm_exception_signal', 'app.recalculate_shipment_tracking_health'
  ];
begin
  foreach v_fn in array v_functions loop
    select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = split_part(v_fn, '.', 2)
    limit 1;
    if v_src is null then
      raise exception 'test_setup_error: function % not found in the live database -- cannot perform static analysis', v_fn;
    end if;
    if v_src ilike '%update app.shipment_orders%' or v_src ilike '%app.transition_shipment_order(%' or v_src ilike '%app.dispatch_shipment_order(%' or v_src ilike '%app.complete_epod_capture(%' then
      v_violations := v_violations || v_fn;
    end if;
  end loop;
  if array_length(v_violations, 1) > 0 then
    raise exception 'assertion failed: found telemetry/milestone/exception function(s) whose OWN compiled source directly or indirectly touches app.shipment_orders.status: %', v_violations;
  end if;
end $$;

\echo '>> Part 6b: dynamic proof -- a real ~20-report telemetry blast across all three sources for the SAME vehicle leaves app.shipment_orders.status/record_version/updated_at byte-for-byte unchanged; only the explicit, separately-authorized app.transition_shipment_order call that follows actually advances it'
do $$
declare
  v_shipment_id uuid := (select value::uuid from golden_state where key = 'shipment_id');
  v_device_id uuid := (select value::uuid from golden_state where key = 'device_id');
  v_api_key text := (select value from golden_state where key = 'api_key_gateway');
  v_connection_id uuid := (select value::uuid from golden_state where key = 'connection_id');
  v_secret text := (select value from golden_state where key = 'webhook_secret');
  v_raw_token text := (select value from golden_state where key = 'leg1_mobile_raw_token');
  v_actor uuid := (select value::uuid from golden_state where key = 'actor_id');
  v_before app.shipment_orders;
  v_after app.shipment_orders;
  v_t0 timestamptz;
  v_i integer;
  v_ts bigint;
  v_payload text;
  v_signature text;
begin
  select * into v_before from app.shipment_orders where id = v_shipment_id;
  select greatest(now(), max(event_at) + interval '1 second') into v_t0 from app.canonical_telemetry_events where vehicle_master_id = (select value::uuid from golden_state where key = 'vehicle_master_id');

  for v_i in 1..20 loop
    if v_i % 3 = 0 then
      perform app.ingest_direct_device_telemetry_batch(
        v_api_key, v_device_id,
        jsonb_build_array(jsonb_build_object('report_type', 'heartbeat', 'event_at', (v_t0 + (v_i || ' seconds')::interval)::text)),
        'atw026-invariant-gateway'
      );
    elsif v_i % 3 = 1 then
      perform app.ingest_driver_mobile_report(
        v_raw_token, 'atw026-invariant-client', 'heartbeat', (v_t0 + (v_i || ' seconds')::interval)::text::timestamptz,
        null, null, null, null, null, '{}'::jsonb
      );
    else
      v_ts := extract(epoch from now())::bigint;
      v_payload := jsonb_build_object('event_id', 'atw026-invariant-' || v_i, 'vehicle_id', 'EXT-ATW026-001', 'event_type', 'heartbeat', 'timestamp', (v_t0 + (v_i || ' seconds')::interval)::text)::text;
      v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
      perform app.ingest_third_party_provider_webhook_event(v_connection_id, 'atw026-invariant-client', v_payload, v_ts, v_signature);
    end if;
  end loop;

  select * into v_after from app.shipment_orders where id = v_shipment_id;
  if v_before.status <> v_after.status or v_before.record_version <> v_after.record_version or v_before.updated_at <> v_after.updated_at then
    raise exception 'assertion failed: expected app.shipment_orders to be COMPLETELY untouched by 20 real telemetry events across all 3 sources -- before=(status=%, version=%, updated_at=%) after=(status=%, version=%, updated_at=%)',
      v_before.status, v_before.record_version, v_before.updated_at, v_after.status, v_after.record_version, v_after.updated_at;
  end if;

  -- Now the explicit, separately-authorized transition -- the ONLY thing that
  -- actually advances shipment lifecycle. The golden shipment is currently
  -- 'epod' (Part 1k) -- 'closed' is its one remaining legal forward transition.
  select * into v_after from app.transition_shipment_order(v_shipment_id, 'closed', v_after.record_version, null, 'CLOSE-ATW026-1', 'idem-atw026-closed', v_actor, 'admin');
  if v_after.status <> 'closed' then
    raise exception 'assertion failed: expected the explicit app.transition_shipment_order call to actually advance status to closed, got %', v_after.status;
  end if;
  if v_after.record_version <= v_before.record_version then
    raise exception 'assertion failed: expected record_version to have genuinely advanced only via this explicit transition, before=% after=%', v_before.record_version, v_after.record_version;
  end if;
end $$;

\echo 'PART 6 (accepted-work invariant -- no raw telemetry directly mutates shipment lifecycle) COMPLETE.'

-- =============================================================================
-- Final: cross-tenant isolation sweep (atw026golden vs. atw026mobile, mirroring
-- ATW-226I's own closing convention) and a repository-wide anon-grant-count
-- tally, unchanged by this read-only verification file.
-- =============================================================================

\echo '>> Final: cross-tenant isolation -- zero rows from atw026golden''s own vehicle/shipment/telemetry are visible under atw026mobile''s own tenant_id, and vice versa'
do $$
declare
  v_golden_tenant uuid := (select value::uuid from golden_state where key = 'tenant_id');
  v_mobile_tenant uuid := (select value::uuid from mobile_state where key = 'tenant_id');
  v_golden_vehicle uuid := (select value::uuid from golden_state where key = 'vehicle_master_id');
  v_mobile_vehicle uuid := (select value::uuid from mobile_state where key = 'vehicle_master_id');
  v_leak_count integer;
begin
  select count(*) into v_leak_count from app.vehicle_current_positions where tenant_id = v_mobile_tenant and vehicle_master_id = v_golden_vehicle;
  if v_leak_count <> 0 then
    raise exception 'assertion failed: atw026golden''s own vehicle current position must never appear under atw026mobile''s own tenant_id, found %', v_leak_count;
  end if;
  select count(*) into v_leak_count from app.vehicle_current_positions where tenant_id = v_golden_tenant and vehicle_master_id = v_mobile_vehicle;
  if v_leak_count <> 0 then
    raise exception 'assertion failed: atw026mobile''s own vehicle current position must never appear under atw026golden''s own tenant_id, found %', v_leak_count;
  end if;

  select count(*) into v_leak_count from app.canonical_telemetry_events where vehicle_master_id = v_golden_vehicle and tenant_id <> v_golden_tenant;
  if v_leak_count <> 0 then
    raise exception 'assertion failed: expected every one of atw026golden''s own vehicle''s canonical_telemetry_events rows to carry tenant_id=atw026golden, found % foreign-tenant rows', v_leak_count;
  end if;

  select count(*) into v_leak_count from app.shipment_orders where id = (select value::uuid from mobile_state where key = 'shipment_id') and tenant_id = v_golden_tenant;
  if v_leak_count <> 0 then
    raise exception 'assertion failed: atw026mobile''s own shipment must never resolve under atw026golden''s own tenant_id, found %', v_leak_count;
  end if;
end $$;

\echo '>> Final: repository-wide anon-grant-count tally unchanged (7, matching ATW-226I''s own closing tally exactly) -- this read-only verification file granted nothing new to anyone'
do $$
declare
  v_count integer;
begin
  -- Baseline moved from 7 to 8: IAE-016 (Prompt 344) added exactly one new
  -- anon-granted function, app.ingest_logistics_partner_webhook_event
  -- (this file itself still adds no schema/grant of its own).
  select count(distinct routine_name) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'anon';
  -- Baseline moved from 8 to 9: IAE-017 added app.ingest_finance_payment_gateway_webhook_event.
  -- Baseline moved from 9 to 10: IAE-026 added app.resolve_enterprise_idp_by_email_domain
  -- (a deliberately public resolver, mirrors app.resolve_tenant_by_domain's own shape).
  if v_count <> 10 then
    raise exception 'assertion failed: expected the anon-grant count to remain exactly 10, found %', v_count;
  end if;
end $$;

drop table golden_state;
drop table mobile_state;

\echo 'ALL ATW-026 (Prompt 245) integrated-verification assertions passed -- Parts 1-6 complete.'
