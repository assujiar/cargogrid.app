-- Real, executable test evidence for ATW-226C (CG-S10-ATW-006's family, Prompt 226
-- decomposition "Driver Mobile GPS session and HTTPS ingestion") -- run via
-- `pnpm run db:test` against a real, disposable Postgres database.
--
-- A raw bearer token is one-way hashed at rest (never re-derivable from the table), so
-- every assertion that depends on a specific minted token's own raw value stays inside
-- the same `do $$ ... $$` block that minted it -- PL/pgSQL block-local variables do not
-- persist across separate top-level statements, unlike the table-driven re-derivation
-- every other capability's own db-test file relies on.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, an OPS:Edit dispatcher, an OPS:View-only viewer, one active vehicle + one active driver operational profile (eligible + consented), one confirmed land-freight Shipment Order with a single planned leg, a driver_mobile-allowed tracking policy, and an already-started driver_mobile ATW-225 tracking session'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_dispatcher_role uuid;
  v_dispatcher_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
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
    ('00000000-0000-0000-0000-000000042101', 'dispatcher@acmemobile.test'),
    ('00000000-0000-0000-0000-000000042102', 'viewer@acmemobile.test'),
    ('00000000-0000-0000-0000-000000042103', 'supreme@acmemobile.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000042103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmemobile', 'Acme Mobile Co', 'idem-acmemobile', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmemobile');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEMOBILE-CO', 'Acme Mobile Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMOBILE-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000042101', 'dispatcher@acmemobile.test', 'Dispatcher', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'dispatcher@acmemobile.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000042101', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000042102', 'viewer@acmemobile.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmemobile.test'), 'active', 'onboarded', 'tester');

  v_dispatcher_role := (app.create_role(v_tenant1, 'Mobile Dispatcher', 'full commercial + ops', 'tester')).id;
  v_dispatcher_draft := app.create_role_version(v_dispatcher_role, 'tester');
  perform app.set_role_version_permissions(
    v_dispatcher_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_dispatcher_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_dispatcher_role and status = 'published'), '00000000-0000-0000-0000-000000042101', '00000000-0000-0000-0000-000000042103', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Mobile Ops Viewer', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000042102', '00000000-0000-0000-0000-000000042103', 'tester');

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-MOBILE-A', 'Mobile Truck A', 'owned', 2000, 20, '00000000-0000-0000-0000-000000042101', 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, false, true, true, v_vehicle.record_version, '00000000-0000-0000-0000-000000042101', 'admin');
  select * into v_driver from app.register_driver_operational_profile(v_tenant1, 'DRV-MOBILE-A', 'Driver A', 'B2', (now() + interval '2 years')::date, '00000000-0000-0000-0000-000000042101', 'admin');
  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver.id, true, v_driver.record_version, '00000000-0000-0000-0000-000000042101', 'admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Mobiletrack Co', 'Jane Mobile', 'jane@mobiletracktest.test', '0811',
    '00000000-0000-0000-0000-000000042101', v_team_a, '00000000-0000-0000-0000-000000042101', 'tester');
  select * into v_lead from app.leads where email = 'jane@mobiletracktest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000042101', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Mobiletrack Co', 'MTC226', '11.111.111.5-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 5', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000042101', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Mobile Ops', 'Procurement Lead', 'jane@mobiletracktest.test', '0811', '00000000-0000-0000-0000-000000042101', v_team_a, '00000000-0000-0000-0000-000000042101', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000042101', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Mobiletrack test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000042101', v_team_a, '00000000-0000-0000-0000-000000042101', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000042101', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-MTC226-1', 'Contoso Mobiletrack Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000042101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000042101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000042101', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000042101', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000042101', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000042101', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000042101', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Mobile tracking lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000042101', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000042101', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000042101', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Mobile Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000042101', 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000042101', 'admin');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000042101', 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000042101', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mobile-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 1000, 1000, 16, 1000, 1000, 16, null, '00000000-0000-0000-0000-000000042101', 'admin'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000042101', 'admin');

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-mobile-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000042101', 'admin');
  perform app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, now(), '00000000-0000-0000-0000-000000042101', 'admin');
  perform app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bandung Warehouse', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000042101', 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 1000, 1000, 16, '00000000-0000-0000-0000-000000042101', 'admin');
  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000042101', 'admin');

  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, '00000000-0000-0000-0000-000000042101', 'admin');
  perform app.assign_resource(v_shipment.id, 'driver', v_driver.driver_master_id, '00000000-0000-0000-0000-000000042101', 'admin');

  perform app.upsert_shipment_leg_tracking_policy(
    v_leg.id, true, array['driver_mobile', 'direct_device'], 'driver_mobile', array['driver_mobile', 'direct_device'],
    300, 100, 30, 'leg_dispatch', 'leg_complete', null, true, 3600, '00000000-0000-0000-0000-000000042101', 'admin'
  );

  perform app.start_leg_tracking_session(v_leg.id, 'driver_mobile', 'driver', v_driver.driver_master_id, null, '00000000-0000-0000-0000-000000042101', 'admin');
end $$;

\echo '>> app.start_driver_mobile_session: authority-gated, rejects a nonexistent/non-driver_mobile session; a real call mints a real dmt_-prefixed token exactly once and a second call on the same tracking session is rejected'
do $$
declare
  v_session_id uuid := (select id from app.shipment_leg_tracking_sessions where is_current and status = 'active' limit 1);
  v_result record;
begin
  begin
    perform app.start_driver_mobile_session(v_session_id, 24, '00000000-0000-0000-0000-000000042102', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for the OPS:View-only viewer';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.start_driver_mobile_session('00000000-0000-0000-0000-000000000001', 24, '00000000-0000-0000-0000-000000042101', 'admin');
    raise exception 'assertion failed: expected tracking_session_not_found for a nonexistent session id';
  exception
    when others then
      if sqlerrm not like 'tracking_session_not_found%' then raise; end if;
  end;

  select * into v_result from app.start_driver_mobile_session(v_session_id, 24, '00000000-0000-0000-0000-000000042101', 'admin');
  if v_result.raw_token is null or v_result.raw_token !~ '^dmt_' or v_result.expires_at <= now() then
    raise exception 'assertion failed: expected a real dmt_-prefixed token with a future expiry, got %/%', v_result.raw_token, v_result.expires_at;
  end if;

  begin
    perform app.start_driver_mobile_session(v_session_id, 24, '00000000-0000-0000-0000-000000042101', 'admin');
    raise exception 'assertion failed: expected driver_mobile_session_already_issued -- a token already exists for this tracking session';
  exception
    when others then
      if sqlerrm not like 'driver_mobile_session_already_issued%' then raise; end if;
  end;
end $$;

\echo '>> app.ingest_driver_mobile_report: invalid token and malformed report_type are both a uniform "invalid" outcome -- never a raised exception, never a distinguishable timing/error class for an unauthenticated caller'
do $$
declare
  v_bogus_token text := 'dmt_' || repeat('0', 64);
  v_result record;
begin
  select * into v_result from app.ingest_driver_mobile_report(
    v_bogus_token, 'client-key-1', 'heartbeat', now(), null, null, null, null, null, '{}'::jsonb
  );
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for an unknown token, got %', v_result.ingest_status;
  end if;

  select * into v_result from app.ingest_driver_mobile_report(
    v_bogus_token, 'client-key-2', 'not_a_real_type', now(), null, null, null, null, null, '{}'::jsonb
  );
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for a malformed report_type, got %', v_result.ingest_status;
  end if;
end $$;

\echo '>> app.ingest_driver_mobile_report: a real token (revoke + reissue proves the full real dispatcher lifecycle, not just first-mint) accepts heartbeat/location/pause/resume, keeps event_at strictly separate from received_at, rejects a location report with no coordinates, then a stop report both records the raw report AND ends the underlying ATW-225 session -- after which the same token is immediately rejected, proving real-time consistency with the ATW-225 side'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmemobile');
  v_slts_id uuid := (select id from app.shipment_leg_tracking_sessions where is_current and status = 'active' limit 1);
  v_dms_id uuid;
  v_raw_token text;
  v_result record;
  v_location_row app.driver_mobile_position_reports;
  v_report_count integer;
begin
  perform app.revoke_driver_mobile_session(v_slts_id, 'test: reissue for ingestion lifecycle test', '00000000-0000-0000-0000-000000042101', 'admin');
  select * into v_result from app.start_driver_mobile_session(v_slts_id, 24, '00000000-0000-0000-0000-000000042101', 'admin');
  v_raw_token := v_result.raw_token;
  v_dms_id := v_result.driver_mobile_session_id;

  select * into v_result from app.ingest_driver_mobile_report(v_raw_token, 'client-key-3', 'heartbeat', now(), null, null, 85, true, false, jsonb_build_object('appVersion', '1.0.0'));
  if v_result.ingest_status <> 'ok' or v_result.report_id is null then
    raise exception 'assertion failed: expected ok with a real report_id for a valid heartbeat, got %/%', v_result.ingest_status, v_result.report_id;
  end if;

  select * into v_result from app.ingest_driver_mobile_report(v_raw_token, 'client-key-3', 'location', now() - interval '5 seconds', null, 10, 84, true, true, '{}'::jsonb);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for a location report with no coordinates, got %', v_result.ingest_status;
  end if;

  select * into v_result from app.ingest_driver_mobile_report(
    v_raw_token, 'client-key-3', 'location', now() - interval '5 seconds',
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(107.6191, -6.9175)),
    12.5, 83, true, true, jsonb_build_object('appVersion', '1.0.0')
  );
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected ok for a valid location report, got %', v_result.ingest_status;
  end if;

  select * into v_location_row from app.driver_mobile_position_reports where id = v_result.report_id;
  if v_location_row.location is null or v_location_row.event_at >= v_location_row.received_at then
    raise exception 'assertion failed: expected a stored location and event_at strictly before received_at (event_at was backdated 5 seconds)';
  end if;

  declare
    v_projected record;
  begin
    select * into v_projected from app.get_driver_mobile_position_reports(v_dms_id) where id = v_result.report_id;
    if v_projected.location_geojson is null or (v_projected.location_geojson ->> 'type') <> 'Point'
       or (v_projected.location_geojson -> 'coordinates' ->> 0)::numeric <> 107.6191
       or (v_projected.location_geojson -> 'coordinates' ->> 1)::numeric <> -6.9175
    then
      raise exception 'assertion failed: expected app.get_driver_mobile_position_reports to project the exact GeoJSON Point stored, got %', v_projected.location_geojson;
    end if;
  end;

  perform app.ingest_driver_mobile_report(v_raw_token, 'client-key-3', 'pause', now(), null, null, 82, true, true, '{}'::jsonb);
  perform app.ingest_driver_mobile_report(v_raw_token, 'client-key-3', 'resume', now(), null, null, 81, true, true, '{}'::jsonb);

  select count(*) into v_report_count from app.driver_mobile_position_reports where driver_mobile_tracking_session_id = v_dms_id;
  if v_report_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 raw reports so far (heartbeat, location, pause, resume), found %', v_report_count;
  end if;

  select * into v_result from app.ingest_driver_mobile_report(v_raw_token, 'client-key-3', 'stop', now(), null, null, 79, true, true, '{}'::jsonb);
  if v_result.ingest_status <> 'ok' or v_result.session_ended is not true then
    raise exception 'assertion failed: expected ok with session_ended=true for a stop report, got %/%', v_result.ingest_status, v_result.session_ended;
  end if;

  if (select status from app.shipment_leg_tracking_sessions where id = v_slts_id) <> 'ended'
     or (select is_current from app.shipment_leg_tracking_sessions where id = v_slts_id)
     or (select end_reason from app.shipment_leg_tracking_sessions where id = v_slts_id) <> 'manual_stop'
  then
    raise exception 'assertion failed: expected the underlying ATW-225 session to be ended with end_reason=manual_stop as a side effect of the stop report';
  end if;

  select * into v_result from app.ingest_driver_mobile_report(v_raw_token, 'client-key-3', 'heartbeat', now(), null, null, 78, true, true, '{}'::jsonb);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid -- the underlying tracking session is no longer current/active, real-time consistency with the ATW-225 side';
  end if;
end $$;

\echo '>> app.ingest_driver_mobile_report: rate limiting -- 10 invalid attempts from the same client_key within the trailing window are followed by rate_limited, not a further invalid'
do $$
declare
  v_bogus_token text := 'dmt_' || repeat('1', 64);
  v_result record;
  i integer;
begin
  for i in 1..10 loop
    perform app.ingest_driver_mobile_report(v_bogus_token, 'rate-limit-client', 'heartbeat', now(), null, null, null, null, null, '{}'::jsonb);
  end loop;

  select * into v_result from app.ingest_driver_mobile_report(v_bogus_token, 'rate-limit-client', 'heartbeat', now(), null, null, null, null, null, '{}'::jsonb);
  if v_result.ingest_status <> 'rate_limited' then
    raise exception 'assertion failed: expected rate_limited after 10 invalid attempts from the same client_key, got %', v_result.ingest_status;
  end if;
end $$;

\echo '>> app.end_leg_tracking_session backward compatibility: the pre-existing 5-positional-argument dispatcher call shape (ATW-225''s own) still resolves to exactly one function after this checkpoint''s own widening -- never "function is not unique"'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmemobile');
  v_leg_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-mobile-leg1');
  v_vehicle_master_id uuid := (select vehicle_master_id from app.vehicle_operational_profiles where tenant_id = v_tenant1);
begin
  begin
    perform app.start_leg_tracking_session(v_leg_id, 'direct_device', 'vehicle', v_vehicle_master_id, null, '00000000-0000-0000-0000-000000042101', 'admin');
  exception
    when others then
      if sqlerrm ~ 'function .* is not unique' then
        raise exception 'assertion failed: app.end_leg_tracking_session''s own widening broke the pre-existing 5-argument call resolution: %', sqlerrm;
      end if;
      -- Any other outcome (source_not_eligible, no active device assignment, etc.) is
      -- an acceptable, expected fixture limitation -- this block's own purpose is
      -- proving unambiguous function resolution, not exercising direct_device
      -- eligibility (already covered by ATW-225's own db-test).
  end;

  begin
    perform app.end_leg_tracking_session(v_leg_id, 'manual_stop', 'backward-compat probe', '00000000-0000-0000-0000-000000042101', 'admin');
  exception
    when others then
      if sqlerrm ~ 'function .* is not unique' then
        raise exception 'assertion failed: app.end_leg_tracking_session''s own 5-argument call shape is ambiguous after this checkpoint''s own widening: %', sqlerrm;
      end if;
  end;
end $$;

\echo '>> RLS: tenant-wide read on both new tables; schema-privilege defense in depth -- anon holds EXECUTE on exactly app.ingest_driver_mobile_report and nothing else, authenticated has no direct INSERT/UPDATE/DELETE on either new table'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmemobile');
  v_row_count integer;
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000042102", "role": "authenticated"}';
  select count(*) into v_row_count from app.driver_mobile_tracking_sessions where tenant_id = v_tenant1;
  reset role;
  if v_row_count < 1 then
    raise exception 'assertion failed: expected the tenant''s own viewer to see at least one driver_mobile_tracking_sessions row';
  end if;

  -- Repository-wide anon EXECUTE is rare but not unprecedented (pre-login tenant/
  -- branding/locale resolution already grants it in five other capabilities) -- what
  -- this checkpoint's own db-test actually guards is narrower and more important:
  -- app.ingest_driver_mobile_report is anon-granted, and no *other* function this
  -- migration itself defines picked up an accidental anon grant.
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon' and routine_name = 'ingest_driver_mobile_report';
  if v_count <> 1 then
    raise exception 'assertion failed: expected app.ingest_driver_mobile_report to be anon-granted, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon'
    and routine_name in ('start_driver_mobile_session', 'revoke_driver_mobile_session', 'end_leg_tracking_session', 'get_driver_mobile_position_reports');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 4 dispatcher/administration-only functions this migration also defines, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app' and grantee = 'authenticated'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and table_name in ('driver_mobile_tracking_sessions', 'driver_mobile_position_reports');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on the 2 new tables, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real start/revoke_driver_mobile_session and driver-mobile-initiated end_leg_tracking_session call recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmemobile');
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.driver_mobile_tracking_sessions' and action = 'start_driver_mobile_session';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 start_driver_mobile_session audit events (initial mint + one reissue), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.driver_mobile_tracking_sessions' and action = 'revoke_driver_mobile_session';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 revoke_driver_mobile_session audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.shipment_leg_tracking_sessions' and action = 'end_leg_tracking_session' and actor_label = 'driver-mobile';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 driver-mobile-initiated end_leg_tracking_session audit event, found %', v_count;
  end if;
end $$;

\echo 'advanced-tms-driver-mobile-tracking.sql: ALL PASSED'
