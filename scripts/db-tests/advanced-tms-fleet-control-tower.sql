-- Real, executable test evidence for ATW-226H (CG-S10-ATW-007's family, Prompt 226
-- decomposition "Administration, Fleet Control Tower, device administration, and
-- sanitized projections") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
--
-- Exercises the three new tenant-wide aggregating reads and the widened
-- app.lookup_public_shipment_tracking's own new sanitized vehicle-position fields.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, two vehicles (one tracked with a real position via direct_device, one never tracked), one confirmed Shipment Order with a customer_visible tracking policy and an assigned/tracked vehicle, one pending milestone candidate, one pending exception signal'
create temporary table fct_test_state (key text primary key, value text not null);
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
  v_vehicle_tracked app.vehicle_operational_profiles;
  v_vehicle_untracked app.vehicle_operational_profiles;
  v_device app.gps_devices;
  v_key record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000047101', 'admin@acmecontroltower.test'),
    ('00000000-0000-0000-0000-000000047102', 'noaccess@acmecontroltower.test'),
    ('00000000-0000-0000-0000-000000047103', 'supreme@acmecontroltower.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000047103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmecontroltower', 'Acme Control Tower Co', 'idem-acmecontroltower', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmecontroltower');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMECONTROLTOWER-CO', 'Acme Control Tower Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONTROLTOWER-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000047101', 'admin@acmecontroltower.test', 'CT Admin', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmecontroltower.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000047101', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000047102', 'noaccess@acmecontroltower.test', 'No Access', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noaccess@acmecontroltower.test'), 'active', 'onboarded', 'tester');

  v_edit_role := (app.create_role(v_tenant1, 'CT Editor', 'full commercial + ops', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000047101', '00000000-0000-0000-0000-000000047103', 'tester');

  -- Vehicle codes deliberately ordered so the alphabetical assertion below is
  -- meaningful (Tracked sorts before Untracked).
  select * into v_vehicle_tracked from app.register_vehicle_operational_profile(v_tenant1, 'VEH-A-TRACKED', 'CT Truck Tracked', 'owned', 2000, 20, '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_vehicle_tracked from app.set_vehicle_tracking_eligibility(v_vehicle_tracked.id, true, true, true, v_vehicle_tracked.record_version, '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_vehicle_untracked from app.register_vehicle_operational_profile(v_tenant1, 'VEH-B-UNTRACKED', 'CT Truck Untracked', 'owned', 2000, 20, '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_vehicle_untracked from app.set_vehicle_tracking_eligibility(v_vehicle_untracked.id, true, true, true, v_vehicle_untracked.record_version, '00000000-0000-0000-0000-000000047101', 'admin');

  -- Full commercial-to-shipment pipeline for the tracked vehicle.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Controltower Co', 'Jane CT', 'jane@controltowertest.test', '0811',
    '00000000-0000-0000-0000-000000047101', v_team_a, '00000000-0000-0000-0000-000000047101', 'tester');
  select * into v_lead from app.leads where email = 'jane@controltowertest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000047101', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Controltower Co', 'CTC226H', '11.111.111.8-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 8', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000047101', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane CT Ops', 'Procurement Lead', 'jane@controltowertest.test', '0811', '00000000-0000-0000-0000-000000047101', v_team_a, '00000000-0000-0000-0000-000000047101', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000047101', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Controltower test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000047101', v_team_a, '00000000-0000-0000-0000-000000047101', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000047101', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CTC226H-1', 'Contoso Controltower Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000047101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000047101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000047101', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000047101', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000047101', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000047101', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000047101', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'CT tracking lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000047101', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000047101', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000047101', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane CT Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000047101', 'admin');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000047101', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-ct-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 1000, 1000, 16, 1000, 1000, 16, null, '00000000-0000-0000-0000-000000047101', 'admin'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000047101', 'admin');

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-ct-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_pickup_stop from app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_delivery_stop from app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bandung Warehouse', null, 107.619123, -6.917464, now() + interval '1 day', '00000000-0000-0000-0000-000000047101', 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 1000, 1000, 16, '00000000-0000-0000-0000-000000047101', 'admin');
  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000047101', 'admin');

  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle_tracked.vehicle_master_id, '00000000-0000-0000-0000-000000047101', 'admin');

  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'dispatched', v_leg.record_version, '00000000-0000-0000-0000-000000047101', 'admin');

  -- customer_visible = true -- the widened public-tracking projection's own gate.
  perform app.upsert_shipment_leg_tracking_policy(
    v_leg.id, true, array['direct_device'], 'direct_device', array['direct_device'],
    300, 100, 30, 'leg_dispatch', 'leg_complete', null, true, 3600, '00000000-0000-0000-0000-000000047101', 'admin'
  );

  select * into v_device from app.register_gps_device(v_tenant1, '868712345603001', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000047101', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle_tracked.id, 'ct fixture', '00000000-0000-0000-0000-000000047101', 'admin');
  -- 'installed' (not just 'assigned') is required before app.ingest_direct_device_
  -- telemetry_batch will accept a report -- the full evidence-capture flow (226B) is
  -- not this file's own concern, so transition directly, mirroring 226F/226G's own
  -- fixture precedent of only exercising the evidence flow where it is the file's own
  -- subject.
  select * into v_device from app.transition_gps_device_status(v_device.id, 'installed', v_device.record_version, '00000000-0000-0000-0000-000000047101', 'admin');
  select * into v_key from app.create_api_key(v_tenant1, 'CT Gateway Key', '["OPS:Edit"]'::jsonb, null, null, '00000000-0000-0000-0000-000000047101', 'admin');

  -- One pending milestone candidate and one pending exception signal, inserted
  -- directly -- this file tests the two new tenant-wide aggregating reads (226H's
  -- own scope), not 226G's own already-proven detection logic.
  insert into app.shipment_milestone_candidates (
    tenant_id, shipment_order_id, shipment_leg_id, shipment_leg_stop_id, milestone_code, candidate_event_time, dedup_key
  ) values (
    v_tenant1, v_shipment.id, v_leg.id, v_pickup_stop.id, 'pickup_arrival', now(), 'test-fct-candidate'
  );
  insert into app.shipment_exception_signals (
    tenant_id, shipment_order_id, shipment_leg_id, signal_type, exception_type, severity, description, correlation_key
  ) values (
    v_tenant1, v_shipment.id, v_leg.id, 'route_deviation', 'delay', 'medium', 'test fixture deviation', 'test-fct-signal'
  );

  insert into fct_test_state (key, value) values
    ('tenant_id', v_tenant1::text),
    ('shipment_order_id', v_shipment.id::text),
    ('shipment_number', v_shipment.shipment_number),
    ('vehicle_tracked_master_id', v_vehicle_tracked.vehicle_master_id::text),
    ('vehicle_untracked_master_id', v_vehicle_untracked.vehicle_master_id::text),
    ('device_id', v_device.id::text),
    ('api_key', v_key.raw_key),
    ('admin_actor_id', '00000000-0000-0000-0000-000000047101'),
    ('noaccess_actor_id', '00000000-0000-0000-0000-000000047102');
end $$;

\echo '>> app.get_tenant_vehicle_tracking_overview: one row per active vehicle, left-joined against current position -- a never-tracked vehicle carries null position fields, not a missing row; unauthorized actor rejected'
do $$
declare
  v_tenant1 uuid := (select value::uuid from fct_test_state where key = 'tenant_id');
  v_admin uuid := (select value::uuid from fct_test_state where key = 'admin_actor_id');
  v_noaccess uuid := (select value::uuid from fct_test_state where key = 'noaccess_actor_id');
  v_device_id uuid := (select value::uuid from fct_test_state where key = 'device_id');
  v_api_key text := (select value from fct_test_state where key = 'api_key');
  v_vehicle_tracked_id uuid := (select value::uuid from fct_test_state where key = 'vehicle_tracked_master_id');
  v_vehicle_untracked_id uuid := (select value::uuid from fct_test_state where key = 'vehicle_untracked_master_id');
  v_rows record;
  v_row_count integer := 0;
  v_tracked_row record;
  v_untracked_row record;
  v_rejected boolean := false;
begin
  perform app.ingest_direct_device_telemetry_batch(
    v_api_key, v_device_id,
    jsonb_build_array(jsonb_build_object('report_type', 'location', 'event_at', now()::text, 'longitude', 106.845599, 'latitude', -6.208763, 'speed_kmh', 40)),
    'test-gateway'
  );

  for v_rows in select * from app.get_tenant_vehicle_tracking_overview(v_tenant1, v_admin) loop
    v_row_count := v_row_count + 1;
    if v_rows.vehicle_master_id = v_vehicle_tracked_id then
      v_tracked_row := v_rows;
    elsif v_rows.vehicle_master_id = v_vehicle_untracked_id then
      v_untracked_row := v_rows;
    end if;
  end loop;

  if v_row_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 vehicle rows, got %', v_row_count;
  end if;
  if v_tracked_row.vehicle_master_id is null or v_tracked_row.current_location_geojson is null or v_tracked_row.current_source_type <> 'direct_device' then
    raise exception 'assertion failed: expected the tracked vehicle to carry a real position, got %', v_tracked_row;
  end if;
  if v_untracked_row.vehicle_master_id is null or v_untracked_row.current_location_geojson is not null then
    raise exception 'assertion failed: expected the never-tracked vehicle to carry a null position, got %', v_untracked_row;
  end if;

  begin
    perform app.get_tenant_vehicle_tracking_overview(v_tenant1, v_noaccess);
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
end $$;

\echo '>> app.get_tenant_pending_milestone_candidates / app.get_tenant_pending_exception_signals: tenant-wide, joined with the real shipment_number, capped, unauthorized actor rejected'
do $$
declare
  v_tenant1 uuid := (select value::uuid from fct_test_state where key = 'tenant_id');
  v_admin uuid := (select value::uuid from fct_test_state where key = 'admin_actor_id');
  v_noaccess uuid := (select value::uuid from fct_test_state where key = 'noaccess_actor_id');
  v_shipment_number text := (select value from fct_test_state where key = 'shipment_number');
  v_candidate_row record;
  v_signal_row record;
  v_count integer;
  v_rejected boolean := false;
begin
  select * into v_candidate_row from app.get_tenant_pending_milestone_candidates(v_tenant1, v_admin, 50);
  if v_candidate_row.id is null or v_candidate_row.shipment_number <> v_shipment_number or v_candidate_row.milestone_code <> 'pickup_arrival' then
    raise exception 'assertion failed: unexpected pending milestone candidate row %', v_candidate_row;
  end if;

  select * into v_signal_row from app.get_tenant_pending_exception_signals(v_tenant1, v_admin, 50);
  if v_signal_row.id is null or v_signal_row.shipment_number <> v_shipment_number or v_signal_row.signal_type <> 'route_deviation' then
    raise exception 'assertion failed: unexpected pending exception signal row %', v_signal_row;
  end if;

  select count(*) into v_count from app.get_tenant_pending_milestone_candidates(v_tenant1, v_admin, 999999);
  if v_count > 200 then
    raise exception 'assertion failed: expected the 200-row hard cap regardless of p_limit, got %', v_count;
  end if;

  begin
    perform app.get_tenant_pending_milestone_candidates(v_tenant1, v_noaccess, 50);
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected an unauthorized actor to be rejected reading pending milestone candidates';
  end if;

  v_rejected := false;
  begin
    perform app.get_tenant_pending_exception_signals(v_tenant1, v_noaccess, 50);
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected an unauthorized actor to be rejected reading pending exception signals';
  end if;
end $$;

\echo '>> widened app.lookup_public_shipment_tracking: a customer_visible=true policy with a real position yields a sanitized live position; a customer_visible=false leg yields null position fields, never an error'
do $$
declare
  v_shipment_order_id uuid := (select value::uuid from fct_test_state where key = 'shipment_order_id');
  v_admin uuid := (select value::uuid from fct_test_state where key = 'admin_actor_id');
  v_issue record;
  v_result record;
  v_leg_id uuid;
begin
  select * into v_issue from app.issue_shipment_tracking_token(v_shipment_order_id, 24, v_admin, 'admin');
  select * into v_result from app.lookup_public_shipment_tracking(v_issue.raw_token, 'ct-client-visible');

  if v_result.lookup_status <> 'ok' or v_result.vehicle_position_geojson is null or v_result.vehicle_position_status <> 'live' or v_result.vehicle_position_updated_at is null then
    raise exception 'assertion failed: expected a sanitized, live vehicle position for a customer_visible policy, got %', v_result;
  end if;

  -- Flip the same leg's own tracking policy to customer_visible = false and confirm
  -- the position fields cleanly disappear -- never an error, never a stale leak.
  select id into v_leg_id from app.shipment_legs where shipment_order_id = v_shipment_order_id;
  perform app.upsert_shipment_leg_tracking_policy(
    v_leg_id, true, array['direct_device'], 'direct_device', array['direct_device'],
    300, 100, 30, 'leg_dispatch', 'leg_complete', null, false, 3600, v_admin, 'admin'
  );

  select * into v_result from app.lookup_public_shipment_tracking(v_issue.raw_token, 'ct-client-hidden');
  if v_result.lookup_status <> 'ok' or v_result.vehicle_position_geojson is not null or v_result.vehicle_position_status is not null or v_result.vehicle_position_updated_at is not null then
    raise exception 'assertion failed: expected null vehicle position fields once customer_visible is false, got %', v_result;
  end if;
end $$;

\echo '>> schema-privilege defense in depth: the three new tenant-wide reads are authenticated-only; app.lookup_public_shipment_tracking keeps its own exact pre-existing anon grant, and the repository-wide anon-grant count remains exactly 7'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee in ('anon', 'authenticated')
    and routine_name in ('get_tenant_vehicle_tracking_overview', 'get_tenant_pending_milestone_candidates', 'get_tenant_pending_exception_signals')
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon grants on the three new tenant-wide reads, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'authenticated'
    and routine_name in ('get_tenant_vehicle_tracking_overview', 'get_tenant_pending_milestone_candidates', 'get_tenant_pending_exception_signals');
  if v_count <> 3 then
    raise exception 'assertion failed: expected all 3 new tenant-wide reads to be authenticated-callable, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and routine_name = 'lookup_public_shipment_tracking' and grantee in ('anon', 'authenticated', 'service_role');
  if v_count <> 3 then
    raise exception 'assertion failed: expected app.lookup_public_shipment_tracking to keep its exact 3-grantee (anon/authenticated/service_role) shape after the DROP+CREATE widening, found %', v_count;
  end if;

  -- Baseline moved from 7 to 8: IAE-016 (Prompt 344) added exactly one new
  -- anon-granted function, app.ingest_logistics_partner_webhook_event.
  select count(distinct routine_name) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'anon';
  if v_count <> 8 then
    raise exception 'assertion failed: expected the anon-grant count to remain exactly 8, found %', v_count;
  end if;
end $$;

drop table fct_test_state;

\echo 'ALL ATW-226H db-test assertions passed.'
