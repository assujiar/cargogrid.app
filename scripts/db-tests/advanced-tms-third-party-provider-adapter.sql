-- Real, executable test evidence for ATW-226E (CG-S10-ATW-006's family, Prompt 226
-- decomposition "Third-party GPS platform adapter contract") -- run via
-- `pnpm run db:test` against a real, disposable Postgres database.
--
-- The raw webhook secret minted by app.register_third_party_provider_connection() is
-- stored in RETRIEVABLE form (unlike a bearer token/API key), so HMAC assertions here
-- compute the real signature independently (mirroring what a genuine provider webhook
-- sender would do) using pgcrypto's hmac() directly against the secret captured in a
-- session-local temp table -- not app.compute_third_party_provider_webhook_signature
-- itself, so the test does not simply ask the function to grade its own homework for
-- the "correct signature accepted" cases (it is still used to derive the deliberately
-- wrong signature for the "tampered payload" negative case).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, an OPS:Edit admin, a Supreme Admin, one active vehicle with a provider_vehicle_mapping for provider_code=acmegps, and one webhook-mode connection'
create temporary table provider_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_vehicle_master uuid;
  v_conn record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000044101', 'admin@acmeprovider.test'),
    ('00000000-0000-0000-0000-000000044103', 'supreme@acmeprovider.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000044103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeprovider', 'Acme Provider Co', 'idem-acmeprovider', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeprovider');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000044101', 'admin@acmeprovider.test', 'Provider Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeprovider.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000044101', 'tenant_admin', v_tenant1, null, 'tester');

  v_edit_role := (app.create_role(v_tenant1, 'Provider Editor', 'OPS:Edit/Create', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(v_edit_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Edit', 'Create')), 'tester');
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000044101', '00000000-0000-0000-0000-000000044103', 'tester');

  perform app.register_vehicle_operational_profile(v_tenant1, 'VEH-PROVIDER-001', 'Provider Truck 001', 'owned', 5000, 20, '00000000-0000-0000-0000-000000044101', 'admin');
  v_vehicle_master := (select id from app.master_records where tenant_id = v_tenant1 and code = 'VEH-PROVIDER-001');
  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle_master, 'acmegps', 'EXT-VEH-001', '00000000-0000-0000-0000-000000044101', 'admin');

  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'acmegps', 'webhook', '00000000-0000-0000-0000-000000044101', 'admin');

  insert into provider_test_state (key, value) values
    ('tenant_id', v_tenant1::text),
    ('vehicle_master_id', v_vehicle_master::text),
    ('connection_id', v_conn.connection_id::text),
    ('webhook_secret', v_conn.raw_webhook_secret);
end $$;

\echo '>> app.register_third_party_provider_connection: idempotent on (tenant, provider_code) -- a second call returns the same connection with no re-minted secret; a poll-mode connection mints no secret at all'
do $$
declare
  v_tenant1 uuid := (select value::uuid from provider_test_state where key = 'tenant_id');
  v_conn1_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_repeat record;
  v_poll record;
begin
  select * into v_repeat from app.register_third_party_provider_connection(v_tenant1, 'acmegps', 'webhook', '00000000-0000-0000-0000-000000044101', 'admin');
  if v_repeat.connection_id <> v_conn1_id or v_repeat.raw_webhook_secret is not null then
    raise exception 'assertion failed: expected the same connection_id and a null raw_webhook_secret on re-register, got id=% secret=%', v_repeat.connection_id, v_repeat.raw_webhook_secret;
  end if;

  select * into v_poll from app.register_third_party_provider_connection(v_tenant1, 'anotherprovider', 'poll', '00000000-0000-0000-0000-000000044101', 'admin');
  if v_poll.raw_webhook_secret is not null then
    raise exception 'assertion failed: expected a null raw_webhook_secret for a poll-mode connection, got %', v_poll.raw_webhook_secret;
  end if;

  begin
    perform app.rotate_third_party_provider_webhook_secret(v_poll.connection_id, '00000000-0000-0000-0000-000000044101', 'admin');
    raise exception 'assertion failed: expected not_a_webhook_connection when rotating a poll-mode connection''s secret';
  exception
    when others then
      if sqlerrm not like 'not_a_webhook_connection%' then raise; end if;
  end;
end $$;

\echo '>> app.ingest_third_party_provider_webhook_event: a correctly HMAC-signed, well-formed, mapped-vehicle location event is accepted; the identical provider_event_id replayed is a distinct duplicate outcome, never re-inserted'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_secret text := (select value from provider_test_state where key = 'webhook_secret');
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_result record;
  v_count integer;
begin
  v_payload := jsonb_build_object(
    'event_id', 'evt-001', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'location',
    'timestamp', now()::text, 'latitude', -6.208763, 'longitude', 106.845599,
    'speed_kmh', 42.0, 'heading_degrees', 87.3
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');

  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-a', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' or v_result.report_id is null then
    raise exception 'assertion failed: expected ok/non-null report_id, got status=%/report_id=%', v_result.ingest_status, v_result.report_id;
  end if;

  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-a', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'duplicate' then
    raise exception 'assertion failed: expected duplicate on replay of the same provider_event_id, got %', v_result.ingest_status;
  end if;

  select count(*) into v_count from app.third_party_telemetry_reports where connection_id = v_connection_id and provider_event_id = 'evt-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 stored report for evt-001 despite the replay, found %', v_count;
  end if;
end $$;

\echo '>> app.ingest_third_party_provider_webhook_event: a tampered payload (signature computed over different bytes than what is sent) is rejected as invalid, never raised'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_secret text := (select value from provider_test_state where key = 'webhook_secret');
  v_signed_payload text;
  v_sent_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_result record;
begin
  v_signed_payload := jsonb_build_object('event_id', 'evt-tamper-signed', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;
  v_sent_payload := jsonb_build_object('event_id', 'evt-tamper-sent', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_signed_payload, v_secret, 'sha256'), 'hex');

  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-tamper', v_sent_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for a tampered payload, got %', v_result.ingest_status;
  end if;
end $$;

\echo '>> app.ingest_third_party_provider_webhook_event: a stale timestamp (outside the 5-minute ADR-0011 tolerance window) is rejected as invalid even with an otherwise-correct signature'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_secret text := (select value from provider_test_state where key = 'webhook_secret');
  v_payload text;
  v_stale_ts bigint := extract(epoch from now())::bigint - 600;
  v_signature text;
  v_result record;
begin
  v_payload := jsonb_build_object('event_id', 'evt-stale', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;
  v_signature := encode(hmac(v_stale_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');

  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-stale', v_payload, v_stale_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for a stale timestamp, got %', v_result.ingest_status;
  end if;
end $$;

\echo '>> app.ingest_third_party_provider_webhook_event: an unmapped external vehicle_id is quarantined (not dropped, not treated as invalid) with the raw payload preserved for operator review'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_secret text := (select value from provider_test_state where key = 'webhook_secret');
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_result record;
  v_quarantine_row app.third_party_provider_ingestion_attempts;
begin
  v_payload := jsonb_build_object('event_id', 'evt-unmapped', 'vehicle_id', 'NEVER-REGISTERED-VEH', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');

  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-unmapped', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'quarantined' then
    raise exception 'assertion failed: expected quarantined for an unmapped vehicle_id, got %', v_result.ingest_status;
  end if;

  select * into v_quarantine_row from app.third_party_provider_ingestion_attempts where connection_id = v_connection_id and result = 'quarantined' order by occurred_at desc limit 1;
  if v_quarantine_row.raw_payload is null or (v_quarantine_row.raw_payload ->> 'event_id') <> 'evt-unmapped' then
    raise exception 'assertion failed: expected the quarantined row to preserve the exact raw payload, got %', v_quarantine_row.raw_payload;
  end if;
end $$;

\echo '>> app.ingest_third_party_provider_webhook_event: malformed JSON, a bad connection_id, an unsupported event_type, and a location report missing coordinates all return invalid, never raise'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_secret text := (select value from provider_test_state where key = 'webhook_secret');
  v_ts bigint := extract(epoch from now())::bigint;
  v_result record;
  v_payload text;
  v_signature text;
begin
  v_signature := encode(hmac(v_ts::text || '.not valid json{{{', v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-b', 'not valid json{{{', v_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for malformed JSON, got %', v_result.ingest_status;
  end if;

  v_payload := jsonb_build_object('event_id', 'evt-b2', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, 'wrong-secret-entirely', 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event('00000000-0000-0000-0000-000000000000'::uuid, 'client-b', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for a non-existent connection_id, got %', v_result.ingest_status;
  end if;

  v_payload := jsonb_build_object('event_id', 'evt-b3', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'not_a_real_type', 'timestamp', now()::text)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-b', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for an unsupported event_type, got %', v_result.ingest_status;
  end if;

  v_payload := jsonb_build_object('event_id', 'evt-b4', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'location', 'timestamp', now()::text)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-b', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected invalid for a location report with no coordinates, got %', v_result.ingest_status;
  end if;
end $$;

\echo '>> app.get_third_party_telemetry_reports: GeoJSON projection matches the exact coordinates ingested'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_row record;
begin
  select * into v_row from app.get_third_party_telemetry_reports(v_connection_id) where provider_event_id = 'evt-001';
  if v_row.location_geojson is null then
    raise exception 'assertion failed: expected a non-null GeoJSON projection for evt-001';
  end if;
  if (v_row.location_geojson -> 'coordinates' ->> 0)::numeric <> 106.845599 or (v_row.location_geojson -> 'coordinates' ->> 1)::numeric <> -6.208763 then
    raise exception 'assertion failed: GeoJSON coordinates do not match the ingested longitude/latitude, got %', v_row.location_geojson;
  end if;
end $$;

\echo '>> rate limiting: 10 consecutive invalid (bad-signature) attempts from the same client_key trip rate_limited on the 11th'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_ts bigint := extract(epoch from now())::bigint;
  v_result record;
  i integer;
begin
  for i in 1..10 loop
    select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-ratelimit', 'irrelevant payload', v_ts, 'totally-wrong-signature');
    if v_result.ingest_status <> 'invalid' then
      raise exception 'assertion failed: expected invalid on rate-limit-buildup attempt %, got %', i, v_result.ingest_status;
    end if;
  end loop;

  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-ratelimit', 'irrelevant payload', v_ts, 'totally-wrong-signature');
  if v_result.ingest_status <> 'rate_limited' then
    raise exception 'assertion failed: expected rate_limited on the 11th bad attempt, got %', v_result.ingest_status;
  end if;
end $$;

\echo '>> app.update_third_party_provider_poll_cursor: writes only on a poll-mode connection; rejected on a webhook-mode connection'
do $$
declare
  v_tenant1 uuid := (select value::uuid from provider_test_state where key = 'tenant_id');
  v_webhook_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_poll_connection_id uuid := (select id from app.third_party_provider_connections where tenant_id = v_tenant1 and provider_code = 'anotherprovider');
  v_updated app.third_party_provider_connections;
begin
  v_updated := app.update_third_party_provider_poll_cursor(v_poll_connection_id, jsonb_build_object('last_page_token', 'abc123'), '00000000-0000-0000-0000-000000044101', 'admin');
  if v_updated.poll_cursor ->> 'last_page_token' <> 'abc123' then
    raise exception 'assertion failed: expected the poll_cursor to be updated, got %', v_updated.poll_cursor;
  end if;

  begin
    perform app.update_third_party_provider_poll_cursor(v_webhook_connection_id, '{}'::jsonb, '00000000-0000-0000-0000-000000044101', 'admin');
    raise exception 'assertion failed: expected not_a_poll_connection for a webhook-mode connection';
  exception
    when others then
      if sqlerrm not like 'not_a_poll_connection%' then raise; end if;
  end;
end $$;

\echo '>> RLS: authenticated members of the owning tenant can read app.third_party_telemetry_reports via has_active_tenant_membership; a foreign tenant sees zero rows'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_count integer;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000044199', 'foreign@acmeprovidertwo.test')
  on conflict do nothing;
  perform app.provision_tenant('acmeprovidertwo', 'Acme Provider Two Co', 'idem-acmeprovidertwo', 'tester');
  perform app.transition_tenant_status((select id from app.tenants where slug = 'acmeprovidertwo'), 'active', 'setup', 'tester');
  perform app.invite_user((select id from app.tenants where slug = 'acmeprovidertwo'), '00000000-0000-0000-0000-000000044199', 'foreign@acmeprovidertwo.test', 'Foreign', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'foreign@acmeprovidertwo.test'), 'active', 'onboarded', 'tester');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000044101", "role": "authenticated"}';
  select count(*) into v_count from app.third_party_telemetry_reports where connection_id = v_connection_id;
  if v_count = 0 then
    raise exception 'assertion failed: expected the owning tenant''s own admin to see its own telemetry rows';
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000044199", "role": "authenticated"}';
  select count(*) into v_count from app.third_party_telemetry_reports where connection_id = v_connection_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected a foreign tenant''s admin to see zero rows, saw %', v_count;
  end if;
  reset role;
end $$;

\echo '>> schema-privilege defense in depth: only app.ingest_third_party_provider_webhook_event holds an anon grant among this migration''s own functions; anon now holds EXECUTE on exactly 7 functions repository-wide'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in (
      'register_third_party_provider_connection', 'rotate_third_party_provider_webhook_secret',
      'update_third_party_provider_poll_cursor', 'compute_third_party_provider_webhook_signature',
      'verify_third_party_provider_webhook_signature', 'get_third_party_telemetry_reports'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon grants on this migration''s own dispatcher/administration functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon' and routine_name = 'ingest_third_party_provider_webhook_event';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 anon grant on ingest_third_party_provider_webhook_event, found %', v_count;
  end if;

  select count(distinct routine_name) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'anon';
  if v_count <> 7 then
    raise exception 'assertion failed: expected exactly 7 distinct anon-granted functions repository-wide (5 pre-login resolvers + ingest_driver_mobile_report + this migration''s own ingest_third_party_provider_webhook_event), found %', v_count;
  end if;
end $$;

\echo '>> audit trail: register/rotate each recorded a real app.audit_logs event; the anon-facing ingestion path never calls app.capture_audit_event (matches app.driver_mobile_position_reports'' own precedent -- high-volume raw ingestion is not audit_logs-worthy per row)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from provider_test_state where key = 'tenant_id');
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.third_party_provider_connections' and action = 'register_third_party_provider_connection';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 register audit events (acmegps + anotherprovider), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.third_party_provider_connections' and action = 'rotate_third_party_provider_webhook_secret';
  if v_count <> 0 then
    raise exception 'assertion failed: expected exactly 0 rotate audit events (the only rotate call in this file was rejected before capturing one), found %', v_count;
  end if;
end $$;

\echo 'ALL ATW-226E db-test assertions passed.'
