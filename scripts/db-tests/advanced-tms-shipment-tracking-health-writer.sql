-- Real, executable test evidence for CG-S10-ATW-024 (Prompt 243) Deliverable A --
-- closes ISS-2026-009 (docs/runtime/KNOWN_ISSUES.md): app.shipment_tracking_health
-- (ATW-222) finally has a real writer. Run via `pnpm run db:test` against a real,
-- disposable Postgres database.
--
-- Exercises app.recalculate_shipment_tracking_health/app.reconcile_shipment_
-- tracking_health both directly and, more importantly, indirectly through the real
-- anon-facing ingestion RPCs (app.ingest_direct_device_telemetry_batch/app.ingest_
-- third_party_provider_webhook_event) via the widened app.arbitrate_and_project_
-- vehicle_position -- the same real trigger point production traffic uses, never a
-- shortcut direct call except where explicitly noted.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, two vehicles (A: receives real telemetry, B: never does), one GPS device on vehicle A, a third-party connection mapped to vehicle A, four Shipment Orders (C: no resource assigned, D: vehicle B assigned, E+F: both vehicle A assigned concurrently) via the real Commercial pipeline'
create temporary table th_test_state (key text primary key, value text not null);
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
  v_shipment_c app.shipment_orders;
  v_shipment_d app.shipment_orders;
  v_shipment_e app.shipment_orders;
  v_shipment_f app.shipment_orders;
  v_vehicle_a app.vehicle_operational_profiles;
  v_vehicle_b app.vehicle_operational_profiles;
  v_device app.gps_devices;
  v_conn record;
  v_key record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000047201', 'admin@acmehealth.test'),
    ('00000000-0000-0000-0000-000000047203', 'supreme@acmehealth.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000047203', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmehealth', 'Acme Health Co', 'idem-acmehealth', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmehealth');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEHEALTH-CO', 'Acme Health Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEHEALTH-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000047201', 'admin@acmehealth.test', 'Health Admin', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmehealth.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000047201', 'tenant_admin', v_tenant1, null, 'tester');

  -- tenant_admin membership alone does not carry RBAC module permissions --
  -- app.evaluate_permission requires a real assigned role version, exactly like
  -- every other db-test fixture in this repository (e.g.
  -- advanced-tms-canonical-telemetry-arbitration.sql's own identical "Canon
  -- Editor" role).
  v_edit_role := (app.create_role(v_tenant1, 'Health Editor', 'full commercial + ops', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000047201', '00000000-0000-0000-0000-000000047203', 'tester');

  select * into v_vehicle_a from app.register_vehicle_operational_profile(v_tenant1, 'VEH-HEALTH-A', 'Health Truck A', 'owned', 2000, 20, '00000000-0000-0000-0000-000000047201', 'admin');
  select * into v_vehicle_a from app.set_vehicle_tracking_eligibility(v_vehicle_a.id, true, true, true, v_vehicle_a.record_version, '00000000-0000-0000-0000-000000047201', 'admin');
  select * into v_vehicle_b from app.register_vehicle_operational_profile(v_tenant1, 'VEH-HEALTH-B', 'Health Truck B (never tracked)', 'owned', 2000, 20, '00000000-0000-0000-0000-000000047201', 'admin');
  select * into v_vehicle_b from app.set_vehicle_tracking_eligibility(v_vehicle_b.id, true, true, true, v_vehicle_b.record_version, '00000000-0000-0000-0000-000000047201', 'admin');

  -- GPS device on vehicle A -- transitioned to 'installed' directly (device
  -- installation evidence is not a precondition of app.transition_gps_device_
  -- status's own hardcoded status-edge check, confirmed by direct inspection of
  -- 20260729310000; this fixture is deliberately not re-testing that already-
  -- covered evidence flow, ATW-226B's own scope).
  -- ATW-246 hardening note: this literal was previously '868712345602001', coincidentally
  -- identical to the fixture IMEI advanced-tms-geofence-route-deviation-signals.sql also
  -- uses for its own, unrelated tenant -- harmless before app.register_gps_device gained a
  -- real cross-tenant collision guard (this checkpoint's own migration 20260730360000), but
  -- a same-shared-database, order-dependent failure afterward. Changed to a value unique
  -- across every scripts/db-tests/*.sql fixture.
  select * into v_device from app.register_gps_device(v_tenant1, '868712345602101', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000047201', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000047201', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'installed', v_device.record_version, '00000000-0000-0000-0000-000000047201', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle_a.id, 'health fixture', '00000000-0000-0000-0000-000000047201', 'admin');

  -- Third-party provider connection + vehicle mapping, both on vehicle A (used to
  -- prove the fallback_active projection).
  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'acmehealthgps', 'webhook', '00000000-0000-0000-0000-000000047201', 'admin');
  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle_a.vehicle_master_id, 'acmehealthgps', 'EXT-HEALTH-001', '00000000-0000-0000-0000-000000047201', 'admin');

  select * into v_key from app.create_api_key(v_tenant1, 'Health Gateway Key', '["OPS:Edit"]'::jsonb, null, null, '00000000-0000-0000-0000-000000047201', 'admin');

  -- Full commercial-to-shipment pipeline, once, then four Shipment Orders off the
  -- same confirmed Job Order (mirrors advanced-tms-dispatch-board.sql's own
  -- multi-shipment-per-job-order pattern).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Healthtrack Co', 'Jane Health', 'jane@healthtracktest.test', '0811',
    '00000000-0000-0000-0000-000000047201', v_team_a, '00000000-0000-0000-0000-000000047201', 'tester');
  select * into v_lead from app.leads where email = 'jane@healthtracktest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000047201', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Healthtrack Co', 'HTC243', '11.111.111.7-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 7', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000047201', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Health Ops', 'Procurement Lead', 'jane@healthtracktest.test', '0811', '00000000-0000-0000-0000-000000047201', v_team_a, '00000000-0000-0000-0000-000000047201', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000047201', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Healthtrack test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000047201', v_team_a, '00000000-0000-0000-0000-000000047201', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000047201', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-HTC243-1', 'Contoso Healthtrack Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000047201', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000047201', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000047201', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000047201', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000047201', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000047201', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000047201', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Health tracking lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000047201', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000047201', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000047201', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Health Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000047201', 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000047201', 'admin');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000047201', 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000047201', 'admin');

  -- Shipment C: no resource assigned at all.
  select * into v_shipment_c from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-health-c', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000047201', 'admin'
  );
  select * into v_shipment_c from app.confirm_shipment_order(v_shipment_c.id, v_shipment_c.record_version, '00000000-0000-0000-0000-000000047201', 'admin');

  -- Shipment D: vehicle B assigned (never tracked).
  select * into v_shipment_d from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-health-d', null, null, 'land_freight', 'land', 'Jakarta', 'Bogor',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: d', '00000000-0000-0000-0000-000000047201', 'admin'
  );
  select * into v_shipment_d from app.confirm_shipment_order(v_shipment_d.id, v_shipment_d.record_version, '00000000-0000-0000-0000-000000047201', 'admin');
  perform app.assign_resource(v_shipment_d.id, 'vehicle', v_vehicle_b.vehicle_master_id, '00000000-0000-0000-0000-000000047201', 'admin');

  -- Shipment E: vehicle A assigned via the real, normal app.assign_resource RPC.
  select * into v_shipment_e from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-health-e', null, null, 'land_freight', 'land', 'Jakarta', 'Cirebon',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: e', '00000000-0000-0000-0000-000000047201', 'admin'
  );
  select * into v_shipment_e from app.confirm_shipment_order(v_shipment_e.id, v_shipment_e.record_version, '00000000-0000-0000-0000-000000047201', 'admin');
  perform app.assign_resource(v_shipment_e.id, 'vehicle', v_vehicle_a.vehicle_master_id, '00000000-0000-0000-0000-000000047201', 'admin');

  -- Shipment F: ALSO vehicle A, assigned via a direct app.resource_assignments
  -- INSERT rather than app.assign_resource (design note f -- "there may
  -- legitimately be zero or more than zero such shipments for a given vehicle at
  -- once, do not assume exactly one"). Direct inspection of app.assign_resource
  -- (20260727130000) found it structurally enforces at most one active shipment
  -- per resource across the WHOLE tenant via its own assignment_conflict guard --
  -- so two concurrently-assigned shipments for the same vehicle cannot actually
  -- be produced through that RPC today. This fixture bypasses it on purpose, via
  -- the exact same columns/defaults app.assign_resource itself would set, to
  -- prove the widened app.arbitrate_and_project_vehicle_position's own defensive
  -- "zero, one, or more than one" loop (this migration's own design note 7)
  -- handles a real multi-row case correctly, in case a future assignment path
  -- ever legitimately produces one.
  select * into v_shipment_f from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-health-f', null, null, 'land_freight', 'land', 'Jakarta', 'Semarang',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: f', '00000000-0000-0000-0000-000000047201', 'admin'
  );
  select * into v_shipment_f from app.confirm_shipment_order(v_shipment_f.id, v_shipment_f.record_version, '00000000-0000-0000-0000-000000047201', 'admin');
  insert into app.resource_assignments (tenant_id, shipment_order_id, role, resource_id, resource_snapshot, created_by)
  values (v_tenant1, v_shipment_f.id, 'vehicle', v_vehicle_a.vehicle_master_id, jsonb_build_object('code', 'VEH-HEALTH-A', 'name', 'Health Truck A'), 'admin');

  insert into th_test_state (key, value) values
    ('tenant_id', v_tenant1::text),
    ('vehicle_a_master_id', v_vehicle_a.vehicle_master_id::text),
    ('vehicle_b_master_id', v_vehicle_b.vehicle_master_id::text),
    ('device_id', v_device.id::text),
    ('connection_id', v_conn.connection_id::text),
    ('webhook_secret', v_conn.raw_webhook_secret),
    ('api_key', v_key.raw_key),
    ('shipment_c_id', v_shipment_c.id::text),
    ('shipment_d_id', v_shipment_d.id::text),
    ('shipment_e_id', v_shipment_e.id::text),
    ('shipment_f_id', v_shipment_f.id::text);
end $$;

\echo '>> no vehicle assignment (shipment C): not_tracked, tracking_exception_count reflects a real open exception, then drops to 0 once resolved'
do $$
declare
  v_shipment_id uuid := (select value::uuid from th_test_state where key = 'shipment_c_id');
  v_exception app.operational_exceptions;
  v_health app.shipment_tracking_health;
begin
  v_exception := app.report_exception(v_shipment_id, null, 'delay', 'medium', 'health test exception', 'manual', 'health-c-exc', '00000000-0000-0000-0000-000000047201', 'admin');

  v_health := app.recalculate_shipment_tracking_health(v_shipment_id);
  if v_health.tracking_status <> 'not_tracked' or v_health.authoritative_source_type is not null or v_health.last_position_at is not null
     or v_health.freshness_status is not null or v_health.accuracy_meters is not null or v_health.fallback_active is not false then
    raise exception 'assertion failed: expected an honest not_tracked/null projection for an unassigned shipment, got %', v_health;
  end if;
  if v_health.tracking_exception_count <> 1 then
    raise exception 'assertion failed: expected tracking_exception_count = 1 (one open exception), got %', v_health.tracking_exception_count;
  end if;
  if v_health.record_version <> 1 then
    raise exception 'assertion failed: expected record_version = 1 after the first-ever recompute (a real INSERT, no prior row), got %', v_health.record_version;
  end if;

  perform app.resolve_exception(v_exception.id, v_exception.record_version, 'resolved for test', '00000000-0000-0000-0000-000000047201', 'admin');
  v_health := app.recalculate_shipment_tracking_health(v_shipment_id);
  if v_health.tracking_exception_count <> 0 then
    raise exception 'assertion failed: expected tracking_exception_count = 0 once the exception resolved, got %', v_health.tracking_exception_count;
  end if;
  if v_health.tracking_status <> 'not_tracked' then
    raise exception 'assertion failed: expected tracking_status to remain not_tracked regardless of exception state when no vehicle is assigned, got %', v_health.tracking_status;
  end if;
  -- Design note: record_version bumps on every real recompute regardless of
  -- whether the projected enum values happen to be unchanged (this migration's
  -- own touch-trigger-equivalent convention) -- the second call above is a real
  -- UPDATE (ON CONFLICT), so version advances to 2 even though tracking_status
  -- stayed 'not_tracked' both times.
  if v_health.record_version <> 2 then
    raise exception 'assertion failed: expected record_version = 2 after a second real recompute (ON CONFLICT UPDATE), got %', v_health.record_version;
  end if;
end $$;

\echo '>> vehicle assigned but never reported a position (shipment D, vehicle B): not_tracked'
do $$
declare
  v_shipment_id uuid := (select value::uuid from th_test_state where key = 'shipment_d_id');
  v_health app.shipment_tracking_health;
begin
  v_health := app.recalculate_shipment_tracking_health(v_shipment_id);
  if v_health.tracking_status <> 'not_tracked' or v_health.authoritative_source_type is not null or v_health.last_position_at is not null then
    raise exception 'assertion failed: expected not_tracked for an assigned-but-never-reported vehicle, got %', v_health;
  end if;
end $$;

\echo '>> real telemetry (shipments E and F, vehicle A): a single ingested direct_device report recomputes health for BOTH concurrently-assigned shipments -- tracked, fresh, no exceptions yet'
do $$
declare
  v_device_id uuid := (select value::uuid from th_test_state where key = 'device_id');
  v_api_key text := (select value from th_test_state where key = 'api_key');
  v_shipment_e_id uuid := (select value::uuid from th_test_state where key = 'shipment_e_id');
  v_shipment_f_id uuid := (select value::uuid from th_test_state where key = 'shipment_f_id');
  v_health_e app.shipment_tracking_health;
  v_health_f app.shipment_tracking_health;
  v_event_at timestamptz := now();
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object(
      'report_type', 'location', 'event_at', v_event_at::text, 'longitude', 106.845599, 'latitude', -6.208763,
      'speed_kmh', 40, 'heading_degrees', 90
    )),
    'test-gateway'
  );

  select * into v_health_e from app.shipment_tracking_health where shipment_order_id = v_shipment_e_id;
  select * into v_health_f from app.shipment_tracking_health where shipment_order_id = v_shipment_f_id;

  if v_health_e.tracking_status <> 'tracked' or v_health_f.tracking_status <> 'tracked' then
    raise exception 'assertion failed: expected BOTH shipment E and F to be tracked after one ingest for their shared vehicle, got E=% F=%', v_health_e.tracking_status, v_health_f.tracking_status;
  end if;
  if v_health_e.authoritative_source_type <> 'direct_device' or v_health_f.authoritative_source_type <> 'direct_device' then
    raise exception 'assertion failed: expected authoritative_source_type = direct_device for both, got E=% F=%', v_health_e.authoritative_source_type, v_health_f.authoritative_source_type;
  end if;
  if v_health_e.freshness_status <> 'fresh' or v_health_f.freshness_status <> 'fresh' then
    raise exception 'assertion failed: expected freshness_status = fresh for both, got E=% F=%', v_health_e.freshness_status, v_health_f.freshness_status;
  end if;
  if v_health_e.last_position_at <> v_event_at or v_health_f.last_position_at <> v_event_at then
    raise exception 'assertion failed: expected last_position_at = the report''s own event_at for both';
  end if;
  -- accuracy_meters is honestly NULL here -- direct inspection of the already-
  -- applied, already-widened app.ingest_direct_device_telemetry_batch
  -- (20260729390000) found it hardcodes p_accuracy_meters=null in its own call to
  -- app.arbitrate_and_project_vehicle_position, regardless of any accuracy value
  -- present in the raw report JSON (the identical hardcoded null exists in app.
  -- ingest_third_party_provider_webhook_event too). Only app.ingest_driver_mobile_
  -- report actually threads a real p_accuracy_meters through today. This is a
  -- pre-existing gap in those two already-applied/already-widened ATW-226D/226E
  -- functions, not introduced or fixed by this migration (out of this task's own
  -- bounded scope per AGENTS.md -- fixing it would mean re-widening two
  -- functions unrelated to the tracking-health write path) -- disclosed here and
  -- in this migration's own design note 4, not silently masked by a passing
  -- assertion. The next test below proves app.canonical_telemetry_events.
  -- accuracy_meters IS correctly carried through to app.shipment_tracking_health
  -- whenever the upstream source does provide a real value.
  if v_health_e.accuracy_meters is not null or v_health_f.accuracy_meters is not null then
    raise exception 'assertion failed: expected accuracy_meters = null for a direct_device-sourced position (upstream never provides one today), got E=% F=%', v_health_e.accuracy_meters, v_health_f.accuracy_meters;
  end if;
  if v_health_e.fallback_active is not false or v_health_f.fallback_active is not false then
    raise exception 'assertion failed: expected fallback_active = false (bootstrap, not a stale-fallback switch)';
  end if;
end $$;

\echo '>> accuracy_meters pass-through: when a source DOES provide a real accuracy value (app.canonical_telemetry_events.accuracy_meters, ATW-226F''s own already-real column), app.recalculate_shipment_tracking_health carries it through honestly -- proven via a direct app.arbitrate_and_project_vehicle_position call (this test file''s own disclosed exception to "always via the real ingest RPC", since no anon-facing ingest path threads a real accuracy value through today, see the previous test)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from th_test_state where key = 'tenant_id');
  v_vehicle_a_id uuid := (select value::uuid from th_test_state where key = 'vehicle_a_master_id');
  v_shipment_e_id uuid := (select value::uuid from th_test_state where key = 'shipment_e_id');
  v_prior_event_at timestamptz := (select event_at from app.vehicle_current_positions where vehicle_master_id = v_vehicle_a_id);
  v_health app.shipment_tracking_health;
begin
  -- event_at/received_at are anchored to the PRIOR canonical event's own event_at
  -- (not wall-clock now()) with a generous 2-minute gap -- avoids a spurious
  -- impossible_movement rejection: the implied-speed check divides distance by
  -- elapsed EVENT time, and two test blocks running back-to-back in the same
  -- transaction-per-DO-block script can have an arbitrarily small real elapsed
  -- wall-clock gap between their own now() calls, which would otherwise imply an
  -- absurd speed over even a small distance.
  perform app.arbitrate_and_project_vehicle_position(
    v_tenant1, v_vehicle_a_id, 'direct_device', gen_random_uuid(), v_prior_event_at + interval '2 minutes', v_prior_event_at + interval '2 minutes',
    app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.8461, -6.2089))),
    38, 91, 7.25
  );

  v_health := app.recalculate_shipment_tracking_health(v_shipment_e_id);
  if v_health.accuracy_meters is distinct from 7.25 then
    raise exception 'assertion failed: expected accuracy_meters = 7.25 (real value carried from the winning canonical_telemetry_events row) once the upstream source actually provides one, got %', v_health.accuracy_meters;
  end if;
end $$;

\echo '>> degraded (shipment F only): an open exception on an otherwise-fresh position flips tracking_status to degraded, while shipment E (no exception) stays tracked'
do $$
declare
  v_shipment_e_id uuid := (select value::uuid from th_test_state where key = 'shipment_e_id');
  v_shipment_f_id uuid := (select value::uuid from th_test_state where key = 'shipment_f_id');
  v_health_e app.shipment_tracking_health;
  v_health_f app.shipment_tracking_health;
begin
  perform app.report_exception(v_shipment_f_id, null, 'incident', 'high', 'health test exception on F only', 'manual', 'health-f-exc', '00000000-0000-0000-0000-000000047201', 'admin');

  v_health_e := app.recalculate_shipment_tracking_health(v_shipment_e_id);
  v_health_f := app.recalculate_shipment_tracking_health(v_shipment_f_id);

  if v_health_f.tracking_status <> 'degraded' or v_health_f.tracking_exception_count <> 1 then
    raise exception 'assertion failed: expected shipment F to be degraded with tracking_exception_count = 1, got status=% count=%', v_health_f.tracking_status, v_health_f.tracking_exception_count;
  end if;
  if v_health_e.tracking_status <> 'tracked' or v_health_e.tracking_exception_count <> 0 then
    raise exception 'assertion failed: expected shipment E to remain tracked/0 exceptions (the exception was reported only against F), got status=% count=%', v_health_e.tracking_status, v_health_e.tracking_exception_count;
  end if;
end $$;

\echo '>> stale precedence over degraded (design note 3): once the shared vehicle''s position goes stale, F reports stale (not degraded) even with its open exception still present, and E reports stale too'
do $$
declare
  v_vehicle_a_id uuid := (select value::uuid from th_test_state where key = 'vehicle_a_master_id');
  v_shipment_e_id uuid := (select value::uuid from th_test_state where key = 'shipment_e_id');
  v_shipment_f_id uuid := (select value::uuid from th_test_state where key = 'shipment_f_id');
  v_health_e app.shipment_tracking_health;
  v_health_f app.shipment_tracking_health;
begin
  -- Simulate the position having gone silent well beyond the tenant's own
  -- freshness_threshold_seconds (default 300s) -- direct SQL against received_at,
  -- the identical technique advanced-tms-canonical-telemetry-arbitration.sql
  -- already uses (no RPC exists to backdate a real device's own clock, nor should
  -- one).
  update app.vehicle_current_positions set received_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_a_id;
  update app.vehicle_source_health set last_seen_received_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_a_id;

  v_health_e := app.recalculate_shipment_tracking_health(v_shipment_e_id);
  v_health_f := app.recalculate_shipment_tracking_health(v_shipment_f_id);

  if v_health_e.tracking_status <> 'stale' or v_health_e.freshness_status <> 'stale' then
    raise exception 'assertion failed: expected shipment E stale/stale once the source health goes non-healthy, got status=% freshness=%', v_health_e.tracking_status, v_health_e.freshness_status;
  end if;
  if v_health_f.tracking_status <> 'stale' or v_health_f.freshness_status <> 'stale' then
    raise exception 'assertion failed: expected shipment F to also report stale (not degraded) despite its own open exception -- staleness takes precedence (design note 3), got status=% freshness=%', v_health_f.tracking_status, v_health_f.freshness_status;
  end if;
  if v_health_f.tracking_exception_count <> 1 then
    raise exception 'assertion failed: expected tracking_exception_count to remain honestly 1 even while tracking_status is stale, got %', v_health_f.tracking_exception_count;
  end if;
end $$;

\echo '>> fallback_active: once vehicle A''s direct_device source is stale, a lower-priority third_party report legitimately takes over via current_source_stale_fallback -- fallback_active becomes true, then false again once a higher-priority source reclaims'
do $$
declare
  v_connection_id uuid := (select value::uuid from th_test_state where key = 'connection_id');
  v_secret text := (select value from th_test_state where key = 'webhook_secret');
  v_device_id uuid := (select value::uuid from th_test_state where key = 'device_id');
  v_api_key text := (select value from th_test_state where key = 'api_key');
  v_vehicle_a_id uuid := (select value::uuid from th_test_state where key = 'vehicle_a_master_id');
  v_shipment_e_id uuid := (select value::uuid from th_test_state where key = 'shipment_e_id');
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_health app.shipment_tracking_health;
begin
  -- The position/source-health rows are already backdated stale (previous test) --
  -- also elapse the hysteresis window past the earlier bootstrap switch so this
  -- fallback switch is not itself suppressed.
  update app.vehicle_source_switches set switched_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_a_id;

  v_payload := jsonb_build_object(
    'event_id', 'health-evt-fallback', 'vehicle_id', 'EXT-HEALTH-001', 'event_type', 'location',
    'timestamp', (now() + interval '10 minutes')::text, 'latitude', -6.3100, 'longitude', 106.9100
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  perform app.ingest_third_party_provider_webhook_event(v_connection_id, 'health-client', v_payload, v_ts, v_signature);

  select * into v_health from app.shipment_tracking_health where shipment_order_id = v_shipment_e_id;
  if v_health.authoritative_source_type <> 'third_party_platform' or v_health.fallback_active is not true then
    raise exception 'assertion failed: expected third_party_platform via stale-fallback, fallback_active = true, got source=% fallback=%', v_health.authoritative_source_type, v_health.fallback_active;
  end if;
  if v_health.tracking_status <> 'tracked' then
    raise exception 'assertion failed: expected tracked once a fresh position is flowing again (via the new winning source), got %', v_health.tracking_status;
  end if;

  -- Now let driver reclaim: elapse hysteresis again, then a fresh, higher-priority
  -- direct_device report reclaims -- the latest vehicle_source_switches row is no
  -- longer a stale-fallback reason, so fallback_active must flip back to false.
  update app.vehicle_source_switches set switched_at = now() - interval '1 hour' where vehicle_master_id = v_vehicle_a_id;
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', (now() + interval '11 minutes')::text, 'longitude', 106.85, 'latitude', -6.21, 'speed_kmh', 35)),
    'test-gateway'
  );

  select * into v_health from app.shipment_tracking_health where shipment_order_id = v_shipment_e_id;
  if v_health.authoritative_source_type <> 'direct_device' or v_health.fallback_active is not false then
    raise exception 'assertion failed: expected direct_device to reclaim with fallback_active = false (higher_priority_source_available, not stale fallback), got source=% fallback=%', v_health.authoritative_source_type, v_health.fallback_active;
  end if;
end $$;

\echo '>> app.reconcile_shipment_tracking_health: bounded, cursor-able -- covers every shipment with an active vehicle assignment in the tenant (D, E, F) across two small-limit calls, ascending shipment_order_id, no duplicates, none missed'
do $$
declare
  v_tenant1 uuid := (select value::uuid from th_test_state where key = 'tenant_id');
  v_shipment_d_id uuid := (select value::uuid from th_test_state where key = 'shipment_d_id');
  v_shipment_e_id uuid := (select value::uuid from th_test_state where key = 'shipment_e_id');
  v_shipment_f_id uuid := (select value::uuid from th_test_state where key = 'shipment_f_id');
  v_first_page uuid[];
  v_second_page uuid[];
  v_all uuid[];
  v_cursor uuid;
  v_expected uuid[];
begin
  select array_agg(shipment_order_id order by shipment_order_id) into v_first_page
  from app.reconcile_shipment_tracking_health(v_tenant1, null, 2);
  if array_length(v_first_page, 1) <> 2 then
    raise exception 'assertion failed: expected exactly 2 rows on the first bounded page (p_limit=2), got %', array_length(v_first_page, 1);
  end if;
  v_cursor := v_first_page[array_upper(v_first_page, 1)];

  select array_agg(shipment_order_id order by shipment_order_id) into v_second_page
  from app.reconcile_shipment_tracking_health(v_tenant1, v_cursor, 2);
  if array_length(v_second_page, 1) <> 1 then
    raise exception 'assertion failed: expected exactly 1 remaining row on the second page (3 total assigned shipments), got %', array_length(v_second_page, 1);
  end if;

  v_all := v_first_page || v_second_page;
  v_expected := array(select unnest(array[v_shipment_d_id, v_shipment_e_id, v_shipment_f_id]) order by 1);
  if v_all <> v_expected then
    raise exception 'assertion failed: expected the two pages together to cover exactly {D,E,F} with no duplicates/omissions, got % vs expected %', v_all, v_expected;
  end if;

  -- A third page past the end returns zero rows, not an error.
  if (select count(*) from app.reconcile_shipment_tracking_health(v_tenant1, v_second_page[1], 2)) <> 0 then
    raise exception 'assertion failed: expected zero rows once the cursor has passed every eligible shipment';
  end if;
end $$;

\echo '>> app.dispatch_board_queue reflects the real writer end-to-end (not a manually-inserted row)'
do $$
declare
  v_tracking_status text;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000047201", "role": "authenticated"}';
  select tracking_status into v_tracking_status from app.dispatch_board_queue where idempotency_key = 'idem-health-e';
  reset role;
  if v_tracking_status <> 'tracked' then
    raise exception 'assertion failed: expected the dispatch board to reflect the real recomputed tracked status for shipment E, got %', v_tracking_status;
  end if;
end $$;

\echo '>> shipment_order_not_found: recalculating a nonexistent shipment raises a named error, never a silent no-op'
do $$
begin
  begin
    perform app.recalculate_shipment_tracking_health('00000000-0000-0000-0000-000000000000');
    raise exception 'assertion failed: expected shipment_order_not_found to be raised';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then
        raise;
      end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: neither app.recalculate_shipment_tracking_health nor app.reconcile_shipment_tracking_health is EXECUTE-granted to anon/authenticated (ERR-2026-004 regression guard, service_role-only per this migration''s own design note 8)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee in ('anon', 'authenticated')
    and routine_name in ('recalculate_shipment_tracking_health', 'reconcile_shipment_tracking_health');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon/authenticated EXECUTE grants on the two new functions, found %', v_count;
  end if;
end $$;
