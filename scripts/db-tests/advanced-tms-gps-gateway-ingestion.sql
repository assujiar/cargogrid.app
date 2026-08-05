-- Real, executable test evidence for ATW-226D (CG-S10-ATW-006's family, Prompt 226
-- decomposition "Always-on GPS Gateway and direct-device telemetry ingestion") -- run
-- via `pnpm run db:test` against a real, disposable Postgres database.
--
-- The raw API key minted by app.create_api_key() is one-way hashed at rest (never
-- re-derivable from app.api_keys), so every assertion depending on a specific key's own
-- raw value stays inside the same `do $$ ... $$` block that minted it -- the identical
-- ATW-226C block-scoping discipline this repository already established for its own raw
-- bearer token.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, each with an OPS:Edit admin, a Supreme Admin, and one GPS device installed on one vehicle (assigned -> installed via the real ATW-226B evidence flow); one active OPS:Edit-scoped API key per tenant for the gateway to present'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_vehicle_master uuid;
  v_vehicle_profile app.vehicle_operational_profiles;
  v_device app.gps_devices;
  v_doc_draft app.config_versions;
  v_clean_file uuid;
  v_assignment_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000043101', 'admin@acmegateway.test'),
    ('00000000-0000-0000-0000-000000043102', 'admin2@acmegatewaytwo.test'),
    ('00000000-0000-0000-0000-000000043103', 'supreme@acmegateway.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000043103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmegateway', 'Acme Gateway Co', 'idem-acmegateway', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmegateway');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('acmegatewaytwo', 'Acme Gateway Two Co', 'idem-acmegatewaytwo', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmegatewaytwo');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000043101', 'admin@acmegateway.test', 'Gateway Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmegateway.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000043101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000043102', 'admin2@acmegatewaytwo.test', 'Gateway Two Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmegatewaytwo.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000043102', 'tenant_admin', v_tenant2, null, 'tester');

  v_edit_role := (app.create_role(v_tenant1, 'Gateway Editor', 'OPS:Edit/Create/Assign', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(v_edit_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Edit', 'Create', 'Assign')), 'tester');
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000043101', '00000000-0000-0000-0000-000000043103', 'tester');

  v_edit_role := (app.create_role(v_tenant2, 'Gateway Two Editor', 'OPS:Edit/Create/Assign', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(v_edit_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Edit', 'Create', 'Assign')), 'tester');
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000043102', '00000000-0000-0000-0000-000000043103', 'tester');

  -- tenant 1: one device, taken all the way to 'installed' via the real ATW-226B flow
  perform app.register_vehicle_operational_profile(v_tenant1, 'VEH-GATEWAY-001', 'Gateway Truck 001', 'owned', 5000, 20, '00000000-0000-0000-0000-000000043101', 'admin');
  v_vehicle_master := (select id from app.master_records where tenant_id = v_tenant1 and code = 'VEH-GATEWAY-001');
  select * into v_vehicle_profile from app.vehicle_operational_profiles where vehicle_master_id = v_vehicle_master;

  select * into v_device from app.register_gps_device(v_tenant1, '868712345600001', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000043101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000043101', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle_profile.id, 'gateway fixture', '00000000-0000-0000-0000-000000043101', 'admin');
  v_assignment_id := (select id from app.device_vehicle_assignments where device_id = v_device.id and is_current);

  perform app.register_document_type('gps_device_installation', 'GPS Device Installation Evidence', 'DOC', '00000000-0000-0000-0000-000000043103', 'supreme');
  v_doc_draft := app.create_config_draft('document:gps_device_installation', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000043101', 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/jpeg', 'application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000043101', 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000043101', now(), 'admin');

  v_clean_file := (app.initiate_file_upload(
    v_tenant1, 'gps_device_installation', 'gps_device', v_device.id, 'install-photo.jpg', 'image/jpeg', 40960, null, false, null, '{}'::uuid[], null, 'idem-gateway-install', '00000000-0000-0000-0000-000000043101', 'admin'
  )).id;
  perform app.record_file_scan_result(v_clean_file, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000043101', 'admin');
  perform app.record_gps_device_installation(v_assignment_id, v_clean_file, 'Budi Teknisi', 'installed under dashboard', v_device.record_version, '00000000-0000-0000-0000-000000043101', 'admin');

  if (select status from app.gps_devices where id = v_device.id) <> 'installed' then
    raise exception 'assertion failed: fixture device expected status installed';
  end if;

  -- tenant 2: a second, unrelated device, deliberately left in 'stock' (used only for
  -- the cross-tenant isolation and not-yet-installed rejection tests)
  select * into v_device from app.register_gps_device(v_tenant2, '868712345600002', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000043102', 'admin2');
end $$;

\echo '>> app.create_api_key: mint one active OPS:Edit-scoped key per tenant for the gateway; raw values captured in a session-local temp table for later blocks (never re-derivable from app.api_keys itself)'
create temporary table gateway_test_keys (tenant_slug text primary key, raw_key text not null);
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmegateway');
  v_tenant2 uuid := (select id from app.tenants where slug = 'acmegatewaytwo');
  v_key1 record;
  v_key2 record;
begin
  select * into v_key1 from app.create_api_key(v_tenant1, 'GPS Gateway Instance 1', '["OPS:Edit"]'::jsonb, null, null, '00000000-0000-0000-0000-000000043101', 'admin');
  select * into v_key2 from app.create_api_key(v_tenant2, 'GPS Gateway Instance 2', '["OPS:Edit"]'::jsonb, null, null, '00000000-0000-0000-0000-000000043102', 'admin2');

  insert into gateway_test_keys (tenant_slug, raw_key) values ('acmegateway', v_key1.raw_key), ('acmegatewaytwo', v_key2.raw_key);
end $$;

\echo '>> app.resolve_gps_device_for_handshake: rejects a bad API key (raised, not a status row); returns accepted=false with a rejection_reason for an unknown IMEI, a cross-tenant key/device pair, and a not-yet-installed device -- never raises for any of those'
do $$
declare
  v_raw_key text := (select raw_key from gateway_test_keys where tenant_slug = 'acmegateway');
  v_raw_key2 text := (select raw_key from gateway_test_keys where tenant_slug = 'acmegatewaytwo');
  v_result record;
begin
  begin
    perform app.resolve_gps_device_for_handshake('wrong-key-entirely', '868712345600001', 'test-gateway');
    raise exception 'assertion failed: expected api_key_not_found for a bogus API key';
  exception
    when others then
      if sqlerrm not like 'api_key_not_found%' then raise; end if;
  end;

  select * into v_result from app.resolve_gps_device_for_handshake(v_raw_key, '999999999999999', 'test-gateway');
  if v_result.accepted or v_result.rejection_reason <> 'imei_not_registered' then
    raise exception 'assertion failed: expected accepted=false/imei_not_registered for an unknown IMEI, got accepted=% reason=%', v_result.accepted, v_result.rejection_reason;
  end if;

  -- tenant 2's key presented against tenant 1's own device IMEI -- device is found
  -- (imei lookup is global) but belongs to a different tenant than the presented key.
  select * into v_result from app.resolve_gps_device_for_handshake(v_raw_key2, '868712345600001', 'test-gateway');
  if v_result.accepted or v_result.rejection_reason <> 'tenant_mismatch' then
    raise exception 'assertion failed: expected accepted=false/tenant_mismatch, got accepted=% reason=%', v_result.accepted, v_result.rejection_reason;
  end if;

  -- tenant 2's own device has never been installed (still 'stock')
  select * into v_result from app.resolve_gps_device_for_handshake(v_raw_key2, '868712345600002', 'test-gateway');
  if v_result.accepted or v_result.rejection_reason <> 'device_not_ingestible' then
    raise exception 'assertion failed: expected accepted=false/device_not_ingestible, got accepted=% reason=%', v_result.accepted, v_result.rejection_reason;
  end if;
end $$;

\echo '>> app.resolve_gps_device_for_handshake: accepts the real installed device for its own tenant''s key; app.ingest_direct_device_telemetry_batch: accepts a real location+heartbeat batch, transitions installed -> active, and rejects a structurally invalid report atomically'
do $$
declare
  v_raw_key text := (select raw_key from gateway_test_keys where tenant_slug = 'acmegateway');
  v_handshake record;
  v_device_id uuid;
  v_ingest record;
  v_count integer;
begin
  select * into v_handshake from app.resolve_gps_device_for_handshake(v_raw_key, '868712345600001', 'test-gateway');
  if not v_handshake.accepted then
    raise exception 'assertion failed: expected the real installed device to be accepted, got reason %', v_handshake.rejection_reason;
  end if;
  v_device_id := v_handshake.device_id;

  select * into v_ingest from app.ingest_direct_device_telemetry_batch(
    v_raw_key, v_device_id,
    jsonb_build_array(
      jsonb_build_object('report_type', 'heartbeat', 'event_at', (now() - interval '2 minutes')::text),
      jsonb_build_object(
        'report_type', 'location', 'event_at', now()::text,
        'longitude', 106.845599, 'latitude', -6.208763, 'altitude_meters', 12.5,
        'heading_degrees', 87.3, 'speed_kmh', 42.0, 'satellite_count', 9,
        'io_elements', jsonb_build_object('239', 1, '66', 12588)
      )
    ),
    'test-gateway'
  );

  if v_ingest.accepted_count <> 2 or v_ingest.device_status <> 'active' then
    raise exception 'assertion failed: expected accepted_count=2/device_status=active, got accepted_count=%/device_status=%', v_ingest.accepted_count, v_ingest.device_status;
  end if;

  if (select status from app.gps_devices where id = v_device_id) <> 'active' then
    raise exception 'assertion failed: expected the device row itself to now be active';
  end if;
  if (select last_telemetry_at from app.gps_devices where id = v_device_id) is null then
    raise exception 'assertion failed: expected last_telemetry_at to be populated';
  end if;

  select count(*) into v_count from app.direct_device_telemetry_reports where device_id = v_device_id;
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 stored reports, found %', v_count;
  end if;

  -- a second, wholly bad batch must roll back atomically -- no partial insert
  begin
    perform app.ingest_direct_device_telemetry_batch(
      v_raw_key, v_device_id,
      jsonb_build_array(
        jsonb_build_object('report_type', 'location', 'event_at', now()::text, 'longitude', 106.8, 'latitude', -6.2),
        jsonb_build_object('report_type', 'not_a_real_type', 'event_at', now()::text)
      ),
      'test-gateway'
    );
    raise exception 'assertion failed: expected invalid_report_type to be raised';
  exception
    when others then
      if sqlerrm not like 'invalid_report_type%' then raise; end if;
  end;

  select count(*) into v_count from app.direct_device_telemetry_reports where device_id = v_device_id;
  if v_count <> 2 then
    raise exception 'assertion failed: expected the failed batch to roll back entirely (still 2 reports), found %', v_count;
  end if;
end $$;

\echo '>> app.get_direct_device_telemetry_reports: GeoJSON projection matches the exact coordinates ingested, newest first'
do $$
declare
  v_device_id uuid := (select id from app.gps_devices where imei = '868712345600001');
  v_rows app.direct_device_telemetry_reports%rowtype;
  v_first record;
begin
  select * into v_first from app.get_direct_device_telemetry_reports(v_device_id) limit 1;
  if v_first.report_type <> 'location' or v_first.location_geojson is null then
    raise exception 'assertion failed: expected the newest row to be the location report with a non-null GeoJSON projection';
  end if;
  if (v_first.location_geojson -> 'coordinates' ->> 0)::numeric <> 106.845599 or (v_first.location_geojson -> 'coordinates' ->> 1)::numeric <> -6.208763 then
    raise exception 'assertion failed: GeoJSON coordinates do not match the ingested longitude/latitude, got %', v_first.location_geojson;
  end if;
end $$;

\echo '>> a device going offline then reporting again transitions offline -> active (not merely installed -> active); a suspended device is refused ingestion entirely'
do $$
declare
  v_raw_key text := (select raw_key from gateway_test_keys where tenant_slug = 'acmegateway');
  v_device app.gps_devices;
  v_ingest record;
  v_handshake record;
begin
  select * into v_device from app.gps_devices where imei = '868712345600001';
  select * into v_device from app.transition_gps_device_status(v_device.id, 'offline', v_device.record_version, '00000000-0000-0000-0000-000000043101', 'admin');

  select * into v_ingest from app.ingest_direct_device_telemetry_batch(
    v_raw_key, v_device.id,
    jsonb_build_array(jsonb_build_object('report_type', 'heartbeat', 'event_at', now()::text)),
    'test-gateway'
  );
  if v_ingest.device_status <> 'active' then
    raise exception 'assertion failed: expected offline -> active on reconnect, got %', v_ingest.device_status;
  end if;

  select * into v_device from app.gps_devices where imei = '868712345600001';
  select * into v_device from app.transition_gps_device_status(v_device.id, 'suspended', v_device.record_version, '00000000-0000-0000-0000-000000043101', 'admin');

  select * into v_handshake from app.resolve_gps_device_for_handshake(v_raw_key, '868712345600001', 'test-gateway');
  if v_handshake.accepted or v_handshake.rejection_reason <> 'device_not_ingestible' then
    raise exception 'assertion failed: expected a suspended device to be refused at handshake, got accepted=% reason=%', v_handshake.accepted, v_handshake.rejection_reason;
  end if;

  begin
    perform app.ingest_direct_device_telemetry_batch(
      v_raw_key, v_device.id,
      jsonb_build_array(jsonb_build_object('report_type', 'heartbeat', 'event_at', now()::text)),
      'test-gateway'
    );
    raise exception 'assertion failed: expected device_not_ingestible to be raised for a suspended device';
  exception
    when others then
      if sqlerrm not like 'device_not_ingestible%' then raise; end if;
  end;

  -- restore to active for the remaining assertions below
  select * into v_device from app.gps_devices where imei = '868712345600001';
  perform app.transition_gps_device_status(v_device.id, 'active', v_device.record_version, '00000000-0000-0000-0000-000000043101', 'admin');
end $$;

\echo '>> a revoked API key is refused by both RPCs; a key lacking OPS:Edit scope is refused by app.api_key_has_scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmegateway');
  v_device_id uuid := (select id from app.gps_devices where imei = '868712345600001');
  v_narrow record;
  v_revoked app.api_keys;
begin
  select * into v_narrow from app.create_api_key(v_tenant1, 'Narrow Scope Key', '["OPS:Assign"]'::jsonb, null, null, '00000000-0000-0000-0000-000000043101', 'admin');

  begin
    perform app.resolve_gps_device_for_handshake(v_narrow.raw_key, '868712345600001', 'test-gateway');
    raise exception 'assertion failed: expected insufficient_authority for a key lacking OPS:Edit scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_revoked := app.revoke_api_key(v_narrow.id, 'test cleanup', '00000000-0000-0000-0000-000000043101', 'admin');
  begin
    perform app.ingest_direct_device_telemetry_batch(v_narrow.raw_key, v_device_id, jsonb_build_array(jsonb_build_object('report_type', 'heartbeat', 'event_at', now()::text)), 'test-gateway');
    raise exception 'assertion failed: expected api_key_revoked for a revoked key';
  exception
    when others then
      if sqlerrm not like 'api_key_revoked%' then raise; end if;
  end;
end $$;

\echo '>> RLS: authenticated members of the owning tenant can read app.direct_device_telemetry_reports via has_active_tenant_membership; a foreign tenant sees zero rows'
do $$
declare
  v_device_id uuid := (select id from app.gps_devices where imei = '868712345600001');
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000043101", "role": "authenticated"}';
  select count(*) into v_count from app.direct_device_telemetry_reports where device_id = v_device_id;
  if v_count = 0 then
    raise exception 'assertion failed: expected the owning tenant''s own admin to see its device''s telemetry rows';
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000043102", "role": "authenticated"}';
  select count(*) into v_count from app.direct_device_telemetry_reports where device_id = v_device_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected a foreign tenant''s admin to see zero rows, saw %', v_count;
  end if;
  reset role;
end $$;

\echo '>> schema-privilege defense in depth: neither anon nor authenticated hold EXECUTE on either GPS Gateway ingestion RPC -- service_role only (ERR-2026-004 regression guard, this migration''s own design note 1)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('resolve_gps_device_for_handshake', 'ingest_direct_device_telemetry_batch')
    and grantee in ('anon', 'authenticated');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon/authenticated grants on the GPS Gateway ingestion RPCs, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name = 'resolve_gps_device_for_handshake'
    and grantee = 'service_role';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 service_role grant on resolve_gps_device_for_handshake, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every handshake attempt and every accepted ingestion batch recorded a real app.audit_logs event with a null actor_auth_user_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmegateway');
  v_handshake_count integer;
  v_ingest_count integer;
  v_null_actor_count integer;
begin
  -- spans both tenants (tenant2's own stock-status device produced one
  -- device_not_ingestible event tagged with tenant2's own id) plus one null-tenant
  -- event for the wholly-unregistered IMEI -- exactly 5 across the whole script:
  -- unregistered, tenant_mismatch, tenant2-stock-device_not_ingestible, one accepted,
  -- one suspended-device_not_ingestible.
  select count(*) into v_handshake_count from app.audit_logs where action = 'gps_gateway_device_handshake';
  if v_handshake_count <> 5 then
    raise exception 'assertion failed: expected exactly 5 handshake audit events, found %', v_handshake_count;
  end if;

  select count(*) into v_ingest_count from app.audit_logs where action = 'ingest_direct_device_telemetry_batch' and tenant_id = v_tenant1;
  if v_ingest_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 successful ingestion audit events, found %', v_ingest_count;
  end if;

  select count(*) into v_null_actor_count from app.audit_logs where action in ('gps_gateway_device_handshake', 'ingest_direct_device_telemetry_batch') and actor_auth_user_id is not null;
  if v_null_actor_count <> 0 then
    raise exception 'assertion failed: expected every GPS Gateway audit event to carry a null actor_auth_user_id (machine-triggered), found % with a non-null actor', v_null_actor_count;
  end if;
end $$;

\echo '>> ATW-246 finding 1: app.register_gps_device rejects a cross-tenant IMEI collision (imei_registered_to_another_tenant), without disturbing the victim''s own idempotent re-registration; app.deregister_gps_device (OPS:Override) clears a spurious registration without touching the legitimate device, and only after clearing it does app.resolve_gps_device_for_handshake stop reporting imei_ambiguous_across_tenants for the victim'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmegateway');
  v_tenant2 uuid := (select id from app.tenants where slug = 'acmegatewaytwo');
  v_raw_key1 text := (select raw_key from gateway_test_keys where tenant_slug = 'acmegateway');
  v_alpha_device app.gps_devices;
  v_spurious app.gps_devices;
  v_handshake record;
  v_returned app.gps_devices;
begin
  select * into v_alpha_device from app.gps_devices where imei = '868712345600001'; -- tenant1's real, active device (fixture above)
  if v_alpha_device.tenant_id <> v_tenant1 or v_alpha_device.status <> 'active' then
    raise exception 'assertion failed: fixture precondition -- expected the 868712345600001 device to belong to tenant1 and be active, got tenant %/status %', v_alpha_device.tenant_id, v_alpha_device.status;
  end if;

  -- Beta (tenant2), holding real OPS:Create in its own tenant, attempts to self-register
  -- Alpha's (tenant1's) real, active device IMEI.
  begin
    perform app.register_gps_device(v_tenant2, '868712345600001', 'Attacker Clone', 'partner', '00000000-0000-0000-0000-000000043102', 'admin2');
    raise exception 'assertion failed: expected imei_registered_to_another_tenant when Beta tries to register Alpha''s active IMEI';
  exception
    when others then
      if sqlerrm not like 'imei_registered_to_another_tenant%' then raise; end if;
  end;

  -- No new row was created by the rejected attempt -- still exactly one row for this IMEI.
  if (select count(*) from app.gps_devices where imei = '868712345600001') <> 1 then
    raise exception 'assertion failed: expected the rejected cross-tenant attempt to create zero rows';
  end if;

  -- Alpha's own legitimate re-registration of its OWN existing IMEI remains completely
  -- unaffected -- still idempotent, still returns the exact same row.
  select * into v_returned from app.register_gps_device(v_tenant1, '868712345600001', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000043101', 'admin');
  if v_returned.id <> v_alpha_device.id then
    raise exception 'assertion failed: expected Alpha''s own re-registration of its own IMEI to remain idempotent and unaffected by the new cross-tenant guard';
  end if;

  -- Simulate a PRE-EXISTING spurious cross-tenant row (as if created before this
  -- checkpoint's own new register_gps_device guard existed -- exactly what app.
  -- deregister_gps_device exists to clean up; the RPC-level guard above cannot
  -- retroactively undo data that already exists).
  insert into app.gps_devices (tenant_id, imei, device_model, ownership_type, status, created_by)
  values (v_tenant2, '868712345600001', 'Spurious Duplicate', 'partner', 'stock', 'legacy-fixture')
  returning * into v_spurious;

  -- The victim's own real device now fails handshake -- ambiguous.
  select * into v_handshake from app.resolve_gps_device_for_handshake(v_raw_key1, '868712345600001', 'test-gateway');
  if v_handshake.accepted or v_handshake.rejection_reason <> 'imei_ambiguous_across_tenants' then
    raise exception 'assertion failed: expected the victim''s own handshake to now be ambiguous, got accepted=% reason=%', v_handshake.accepted, v_handshake.rejection_reason;
  end if;

  -- An ordinary OPS:Edit/Create/Assign-only actor (Beta's own admin, who holds no
  -- OPS:Override anywhere in this fixture) cannot deregister ANY device, including its
  -- own spurious one.
  begin
    perform app.deregister_gps_device(v_spurious.id, 'self-cleanup attempt', v_spurious.record_version, '00000000-0000-0000-0000-000000043102', 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:Override-lacking actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- The spurious row is untouched by the rejected attempt.
  if (select status from app.gps_devices where id = v_spurious.id) <> 'stock' then
    raise exception 'assertion failed: expected the rejected deregister attempt to leave the spurious row unchanged';
  end if;

  -- Only a real supreme_admin (the one identity in this fixture holding cross-tenant
  -- authority -- see app.evaluate_permission's own supreme_admin exception, RPD-022) can
  -- clear Beta's spurious row.
  select * into v_returned from app.deregister_gps_device(v_spurious.id, 'clearing erroneous cross-tenant registration', v_spurious.record_version, '00000000-0000-0000-0000-000000043103', 'supreme');
  if v_returned.status <> 'retired' then
    raise exception 'assertion failed: expected the spurious row to be retired, got status %', v_returned.status;
  end if;

  -- Alpha's own legitimate device row is completely untouched by the remediation.
  select * into v_alpha_device from app.gps_devices where id = v_alpha_device.id;
  if v_alpha_device.status <> 'active' then
    raise exception 'assertion failed: expected the victim''s own legitimate device to remain unaffected (still active), got %', v_alpha_device.status;
  end if;

  -- The victim's own real device now handshakes successfully again -- the remediation
  -- actually restores functionality, not merely renames the spurious row's status.
  select * into v_handshake from app.resolve_gps_device_for_handshake(v_raw_key1, '868712345600001', 'test-gateway');
  if not v_handshake.accepted or v_handshake.device_id <> v_alpha_device.id then
    raise exception 'assertion failed: expected the victim''s own device to handshake successfully once the spurious row is retired, got accepted=% device_id=% (expected %)', v_handshake.accepted, v_handshake.device_id, v_alpha_device.id;
  end if;

  -- The retired spurious row can never be resurrected via app.register_gps_device --
  -- (tenant2, imei) remains permanently claimed by tenant2's own retired row (still
  -- idempotent, still no new active row created).
  select * into v_returned from app.register_gps_device(v_tenant2, '868712345600001', 'Attacker Clone Retry', 'partner', '00000000-0000-0000-0000-000000043102', 'admin2');
  if v_returned.id <> v_spurious.id or v_returned.status <> 'retired' then
    raise exception 'assertion failed: expected a repeat same-tenant register_gps_device call to remain idempotent against the retired row, not create a new active one';
  end if;

  -- app.deregister_gps_device itself is idempotent-safe on an already-retired row --
  -- called with the CURRENT version (v_returned, refreshed by the immediately-preceding
  -- register_gps_device idempotent return above; the touch trigger already advanced the
  -- spurious row's own record_version to 2 on the very first successful deregister call,
  -- so v_spurious's own now-stale, pre-deregister version would correctly raise
  -- stale_version instead -- optimistic concurrency intentionally still applies even to
  -- an idempotent-shaped call, matching app.transition_gps_device_status's own identical
  -- version-checked-before-anything-else convention on this same table).
  select * into v_returned from app.deregister_gps_device(v_spurious.id, 'idempotent re-deregister', v_returned.record_version, '00000000-0000-0000-0000-000000043103', 'supreme');
  if v_returned.status <> 'retired' then
    raise exception 'assertion failed: expected a repeat deregister call on an already-retired device (with its own current version) to remain a no-op';
  end if;

  -- A mandatory, non-empty reason is required.
  begin
    perform app.deregister_gps_device(v_alpha_device.id, '', v_alpha_device.record_version, '00000000-0000-0000-0000-000000043103', 'supreme');
    raise exception 'assertion failed: expected deregister_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'deregister_reason_required%' then raise; end if;
  end;
end $$;

drop table gateway_test_keys;

\echo 'ALL ATW-226D db-test assertions passed.'
