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

\echo '>> HDN-376 (API Compatibility Audit) finding 1 regression: a NULL signature (no HMAC secret known at all -- the literal unauthenticated-caller case) is rejected as invalid, never silently accepted. Before the fix, `v_expected = null` evaluated to SQL NULL and `if not verify_...()` treated that as verified'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_result record;
  v_direct boolean;
begin
  v_payload := jsonb_build_object('event_id', 'evt-null-sig', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;

  v_direct := app.verify_third_party_provider_webhook_signature(v_connection_id, v_payload, v_ts, null);
  if v_direct is distinct from false then
    raise exception 'assertion failed: expected app.verify_third_party_provider_webhook_signature to return exactly false for a null signature, got %', v_direct;
  end if;

  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'client-null-sig', v_payload, v_ts, null);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: HDN-376 finding 1 regressed -- expected invalid for a NULL (fully unauthenticated) signature, got %', v_result.ingest_status;
  end if;

  if exists (select 1 from app.third_party_telemetry_reports where connection_id = v_connection_id and provider_event_id = 'evt-null-sig') then
    raise exception 'assertion failed: a NULL-signature event must never be inserted into app.third_party_telemetry_reports';
  end if;

  -- Empty-string signature (distinct SQL value from null) must also fail closed.
  v_direct := app.verify_third_party_provider_webhook_signature(v_connection_id, v_payload, v_ts, '');
  if v_direct is distinct from false then
    raise exception 'assertion failed: expected app.verify_third_party_provider_webhook_signature to return exactly false for an empty-string signature, got %', v_direct;
  end if;

  -- Null timestamp must also fail closed (was already guarded pre-fix, re-verified here).
  v_direct := app.verify_third_party_provider_webhook_signature(v_connection_id, v_payload, null, 'anysignature');
  if v_direct is distinct from false then
    raise exception 'assertion failed: expected app.verify_third_party_provider_webhook_signature to return exactly false for a null timestamp, got %', v_direct;
  end if;

  raise notice 'HDN-376 finding 1 regression proof: NULL signature, empty-string signature and NULL timestamp are all rejected as false (never NULL), never accepted as verified';
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

\echo '>> CG-S10-ATW-027 Finding 3 regression: 6 malformed-but-validly-signed field values (each individually crashed this RPC with an uncaught exception before this fix -- non-numeric/out-of-range timestamp/latitude/longitude/heading_degrees/speed_kmh) now all return a clean invalid outcome, never raise, and each still increments third_party_provider_ingestion_attempts (so rate-limit/auto-disable counters can see it)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from provider_test_state where key = 'tenant_id');
  v_vehicle_master_id uuid := (select value::uuid from provider_test_state where key = 'vehicle_master_id');
  v_connection_id uuid;
  v_conn record;
  v_secret text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_result record;
  v_signature text;
  v_before integer;
  v_after integer;
  v_case record;
begin
  -- Its own dedicated connection (same rate-limit-isolation rationale as the Finding
  -- 4 regression tests above): Finding 4's own fix now correctly accumulates invalid
  -- attempts per connection_id regardless of client_key, so 6 sequential invalid
  -- attempts here would otherwise inherit the earlier tests' own already-accumulated
  -- invalid-attempt history on the shared connection and trip rate_limited mid-loop,
  -- masking this test's own real subject (clean-rejection behavior, not rate limiting).
  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'acmegps-malformed-fields', 'webhook', '00000000-0000-0000-0000-000000044101', 'admin');
  v_connection_id := v_conn.connection_id;
  v_secret := v_conn.raw_webhook_secret;
  perform app.register_provider_vehicle_mapping(v_tenant1, v_vehicle_master_id, 'acmegps-malformed-fields', 'EXT-VEH-001-MALFORMED', '00000000-0000-0000-0000-000000044101', 'admin');

  for v_case in
    select * from (values
      -- C1: non-numeric timestamp string -- crashed at (payload->>'timestamp')::timestamptz.
      ('crash-c1-timestamp', jsonb_build_object('event_id', 'crash-c1', 'vehicle_id', 'EXT-VEH-001-MALFORMED', 'event_type', 'heartbeat', 'timestamp', 'not-a-valid-timestamp')),
      -- C2: non-numeric latitude string -- crashed at (payload->>'latitude')::numeric.
      ('crash-c2-latitude-nonnumeric', jsonb_build_object('event_id', 'crash-c2', 'vehicle_id', 'EXT-VEH-001-MALFORMED', 'event_type', 'location', 'timestamp', now()::text, 'latitude', 'garbage', 'longitude', 106.8)),
      -- C3: latitude out of range (999) -- crashed inside app.geojson_point_to_geography's own explicit spatial_coordinate_out_of_range raise.
      ('crash-c3-latitude-out-of-range', jsonb_build_object('event_id', 'crash-c3', 'vehicle_id', 'EXT-VEH-001-MALFORMED', 'event_type', 'location', 'timestamp', now()::text, 'latitude', 999, 'longitude', 106.8)),
      -- C4: heading_degrees out of range (999) -- crashed on the final INSERT's own third_party_telemetry_reports_heading_check CHECK constraint.
      ('crash-c4-heading-out-of-range', jsonb_build_object('event_id', 'crash-c4', 'vehicle_id', 'EXT-VEH-001-MALFORMED', 'event_type', 'location', 'timestamp', now()::text, 'latitude', -6.2, 'longitude', 106.8, 'heading_degrees', 999)),
      -- C5: negative speed_kmh -- crashed on the final INSERT's own third_party_telemetry_reports_speed_check CHECK constraint.
      ('crash-c5-negative-speed', jsonb_build_object('event_id', 'crash-c5', 'vehicle_id', 'EXT-VEH-001-MALFORMED', 'event_type', 'location', 'timestamp', now()::text, 'latitude', -6.2, 'longitude', 106.8, 'speed_kmh', -5)),
      -- C6: longitude out of range (-999) -- crashed inside app.geojson_point_to_geography.
      ('crash-c6-longitude-out-of-range', jsonb_build_object('event_id', 'crash-c6', 'vehicle_id', 'EXT-VEH-001-MALFORMED', 'event_type', 'location', 'timestamp', now()::text, 'latitude', -6.2, 'longitude', -999))
    ) as t(client_key, payload)
  loop
    v_signature := encode(hmac(v_ts::text || '.' || v_case.payload::text, v_secret, 'sha256'), 'hex');
    select count(*) into v_before from app.third_party_provider_ingestion_attempts where client_key = v_case.client_key;

    select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, v_case.client_key, v_case.payload::text, v_ts, v_signature);

    select count(*) into v_after from app.third_party_provider_ingestion_attempts where client_key = v_case.client_key;

    if v_result.ingest_status <> 'invalid' then
      raise exception 'assertion failed (Finding 3 REGRESSED, %): expected a clean invalid outcome (not a raised exception), got %', v_case.client_key, v_result.ingest_status;
    end if;
    if v_after <> v_before + 1 then
      raise exception 'assertion failed (Finding 3 REGRESSED, %): expected exactly 1 new ingestion_attempts row so rate-limit/auto-disable counters can see this attempt, before=% after=%', v_case.client_key, v_before, v_after;
    end if;
  end loop;
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
  v_tenant1 uuid := (select value::uuid from provider_test_state where key = 'tenant_id');
  v_connection_id uuid;
  v_conn record;
  v_ts bigint := extract(epoch from now())::bigint;
  v_result record;
  i integer;
begin
  -- CG-S10-ATW-027 (Finding 4 fix pass): this test now gets its OWN dedicated
  -- connection rather than reusing provider_test_state's own shared connection_id --
  -- the rate-limit count is now bound to connection_id (in addition to client_key,
  -- see the new Finding 4 regression test immediately below), so reusing the shared
  -- connection here would inherit the several already-invalid attempts the earlier
  -- tests above already recorded against it and trip rate_limited early, well before
  -- this test's own 11th attempt. Same isolation technique the ATW-027 adversarial
  -- probe itself used for the identical reason (its own Probe D0).
  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'acmegps-ratelimit-baseline', 'webhook', '00000000-0000-0000-0000-000000044101', 'admin');
  v_connection_id := v_conn.connection_id;

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

\echo '>> CG-S10-ATW-027 Finding 4 regression: rate limiting is bound to connection_id, not just caller-controlled client_key -- reproduces the adversarial probe''s exact exploit (many bad-signature attempts against the SAME connection, each with a DISTINCT client_key, simulating an attacker rotating the x-forwarded-for header app/api/webhooks/third-party-gps/[connectionId]/route.ts derives client_key from) and confirms rate_limited now trips regardless'
do $$
declare
  v_tenant1 uuid := (select value::uuid from provider_test_state where key = 'tenant_id');
  v_connection_id uuid;
  v_conn record;
  v_ts bigint := extract(epoch from now())::bigint;
  v_result record;
  i integer;
  v_rate_limited_count integer := 0;
  v_distinct_keys_before_limit integer := 0;
begin
  -- Its own dedicated connection (same isolation rationale as immediately above) --
  -- proves the fix on a clean connection with zero prior invalid-attempt history.
  select * into v_conn from app.register_third_party_provider_connection(v_tenant1, 'acmegps-ratelimit-bypass', 'webhook', '00000000-0000-0000-0000-000000044101', 'admin');
  v_connection_id := v_conn.connection_id;

  for i in 1..15 loop
    select * into v_result from app.ingest_third_party_provider_webhook_event(
      v_connection_id, 'attacker-rotated-key-' || i, 'irrelevant payload', v_ts, 'totally-wrong-signature'
    );
    if v_result.ingest_status = 'rate_limited' then
      v_rate_limited_count := v_rate_limited_count + 1;
    else
      v_distinct_keys_before_limit := v_distinct_keys_before_limit + 1;
    end if;
  end loop;

  if v_rate_limited_count = 0 then
    raise exception 'assertion failed (Finding 4 REGRESSED): 15 bad-signature attempts against the same connection, each with a distinct client_key, never tripped rate_limited (0/15) -- the rate limit is bypassable by rotating client_key exactly as the adversarial probe demonstrated';
  end if;

  -- Deterministic: 10 distinct-key attempts accumulate as invalid (each below the
  -- connection-scoped threshold) before the 11th-and-onward trip rate_limited,
  -- regardless of client_key varying on every single call.
  if v_distinct_keys_before_limit <> 10 or v_rate_limited_count <> 5 then
    raise exception 'assertion failed: expected exactly 10 invalid + 5 rate_limited across 15 varied-client_key attempts, got %/% ', v_distinct_keys_before_limit, v_rate_limited_count;
  end if;

  -- Confirm the connection-scoped count is real, not merely a coincidental repeat of
  -- the shared-key baseline above: every one of the 15 client_keys used here was
  -- unique, yet rate_limited still fired.
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'attacker-rotated-key-final-check', 'irrelevant payload', v_ts, 'totally-wrong-signature');
  if v_result.ingest_status <> 'rate_limited' then
    raise exception 'assertion failed: expected a 16th attempt with yet another distinct client_key to still be rate_limited, got %', v_result.ingest_status;
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

  -- Baseline moved from 7 to 8: IAE-016 (Prompt 344) added exactly one further
  -- anon-granted function, app.ingest_logistics_partner_webhook_event.
  select count(distinct routine_name) into v_count from information_schema.routine_privileges where routine_schema = 'app' and grantee = 'anon';
  -- Baseline moved from 8 to 9: IAE-017 added a further anon-granted function,
  -- app.ingest_finance_payment_gateway_webhook_event.
  -- Baseline moved from 9 to 10: IAE-026 added app.resolve_enterprise_idp_by_email_domain
  -- (a deliberately public resolver, mirrors app.resolve_tenant_by_domain's own shape).
  if v_count <> 10 then
    raise exception 'assertion failed: expected exactly 10 distinct anon-granted functions repository-wide (5 pre-login resolvers + ingest_driver_mobile_report + this migration''s own ingest_third_party_provider_webhook_event + IAE-016''s own ingest_logistics_partner_webhook_event + IAE-017''s own ingest_finance_payment_gateway_webhook_event + IAE-026''s own resolve_enterprise_idp_by_email_domain), found %', v_count;
  end if;
end $$;

\echo '>> CG-S10-ATW-027 Finding 1 regression: webhook_secret_value is no longer readable by a same-tenant authenticated member with ZERO role/permission assignment via a direct table SELECT -- every other legitimate column remains readable for that same tenant-scoped row'
do $$
declare
  v_tenant1 uuid := (select value::uuid from provider_test_state where key = 'tenant_id');
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_real_secret text := (select value from provider_test_state where key = 'webhook_secret');
  v_leaked_secret text;
  v_denied boolean := false;
  v_status text;
  v_provider_code text;
begin
  -- The weakest possible legitimate identity still satisfying has_active_tenant_
  -- membership: invited, activated, but never granted any role/permission at all --
  -- exactly the adversarial probe's own zero-permission caller (Probe A).
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000044188', 'noperm@acmeprovider.test');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000044188', 'noperm@acmeprovider.test', 'No Permission User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noperm@acmeprovider.test'), 'active', 'onboarded', 'tester');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000044188", "role": "authenticated"}';

  begin
    select webhook_secret_value into v_leaked_secret from app.third_party_provider_connections where id = v_connection_id;
  exception
    when insufficient_privilege then
      v_denied := true;
  end;

  -- The SAME zero-permission caller, same row -- every OTHER column must still be
  -- readable (this is a column-scoped fix, never a table-wide lockout).
  select status, provider_code into v_status, v_provider_code from app.third_party_provider_connections where id = v_connection_id;
  reset role;

  if not v_denied then
    raise exception 'assertion failed (Finding 1 REGRESSED): a zero-permission same-tenant authenticated member read webhook_secret_value (got %, real value %) via a direct table SELECT instead of being denied', v_leaked_secret, v_real_secret;
  end if;

  if v_status is distinct from 'active' or v_provider_code is distinct from 'acmegps' then
    raise exception 'assertion failed: expected the same zero-permission caller to still read every other legitimate column for its own tenant-scoped row (status=%, provider_code=%)', v_status, v_provider_code;
  end if;
end $$;

\echo '>> CG-S10-ATW-027 Finding 1 regression (defense-in-depth verification): the same zero-permission caller cannot reach the raw secret via app.rotate_third_party_provider_webhook_secret either -- confirms its own OPS:Edit gate remains the only legitimate way to ever see/rotate the secret, and that the fix above closed specifically the raw table GRANT, not a broader RBAC collapse'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_rejected boolean := false;
begin
  begin
    perform app.rotate_third_party_provider_webhook_secret(v_connection_id, '00000000-0000-0000-0000-000000044188', 'noperm');
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then
        v_rejected := true;
      else
        raise;
      end if;
  end;

  if not v_rejected then
    raise exception 'assertion failed (Finding 1 REGRESSED): a zero-permission caller was able to rotate/see the webhook secret via app.rotate_third_party_provider_webhook_secret''s own RPC layer';
  end if;
end $$;

\echo '>> CG-S10-ATW-027 Finding 1 regression (exploit chain closed): the leaked-secret-forged-signature exploit the probe live-reproduced no longer has a secret to leak in the first place -- attempting to forge a signature with a wrong/guessed secret is still cleanly rejected as invalid'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_result record;
  v_pos_before record;
  v_pos_after record;
  v_vehicle_id uuid := (select value::uuid from provider_test_state where key = 'vehicle_master_id');
begin
  v_payload := jsonb_build_object(
    'event_id', 'evt-forged-no-secret', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'location',
    'timestamp', now()::text, 'latitude', -6.9, 'longitude', 107.6, 'speed_kmh', 55, 'heading_degrees', 10
  )::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, 'a-guessed-or-wrong-secret', 'sha256'), 'hex');

  select * into v_pos_before from app.get_vehicle_current_position(v_vehicle_id);
  select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'attacker-without-leaked-secret', v_payload, v_ts, v_signature);
  select * into v_pos_after from app.get_vehicle_current_position(v_vehicle_id);

  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected a wrong-secret-signed payload to be rejected invalid, got %', v_result.ingest_status;
  end if;
  if v_pos_after.source_type is distinct from v_pos_before.source_type or v_pos_after.event_at is distinct from v_pos_before.event_at then
    raise exception 'assertion failed: current position must not change when the signature cannot be forged';
  end if;
end $$;

\echo '>> CG-S10-ATW-027 Finding 5 regression: anon now holds USAGE on schema app -- the documented anon-callable webhook RPC path no longer fails with "permission denied for schema app"; it still correctly accepts/rejects based on signature validity exactly as before'
do $$
declare
  v_connection_id uuid := (select value::uuid from provider_test_state where key = 'connection_id');
  v_secret text := (select value from provider_test_state where key = 'webhook_secret');
  v_payload text;
  v_ts bigint := extract(epoch from now())::bigint;
  v_signature text;
  v_result record;
  v_schema_denied boolean := false;
  v_usage boolean;
begin
  select has_schema_privilege('anon', 'app', 'USAGE') into v_usage;
  if not v_usage then
    raise exception 'assertion failed (Finding 5 REGRESSED): has_schema_privilege(anon, app, USAGE) is still false';
  end if;

  v_payload := jsonb_build_object('event_id', 'evt-anon-liveness', 'vehicle_id', 'EXT-VEH-001', 'event_type', 'heartbeat', 'timestamp', now()::text)::text;
  v_signature := encode(hmac(v_ts::text || '.' || v_payload, v_secret, 'sha256'), 'hex');

  set local role anon;
  begin
    select * into v_result from app.ingest_third_party_provider_webhook_event(v_connection_id, 'anon-liveness-client', v_payload, v_ts, v_signature);
  exception
    when insufficient_privilege then
      v_schema_denied := true;
  end;
  reset role;

  if v_schema_denied then
    raise exception 'assertion failed (Finding 5 REGRESSED): a literal anon-role call to app.ingest_third_party_provider_webhook_event still fails with permission denied for schema app';
  end if;

  -- Still correctly gated on signature validity, not merely schema access -- a
  -- well-formed, correctly-signed heartbeat called literally AS anon succeeds.
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected a well-formed, correctly-signed heartbeat invoked literally as anon to be accepted (ok), got %', v_result.ingest_status;
  end if;
end $$;

\echo '>> audit trail: register/rotate each recorded a real app.audit_logs event; the anon-facing ingestion path never calls app.capture_audit_event (matches app.driver_mobile_position_reports'' own precedent -- high-volume raw ingestion is not audit_logs-worthy per row)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from provider_test_state where key = 'tenant_id');
  v_count integer;
begin
  -- 5, not 2: acmegps + anotherprovider (original setup) plus the CG-S10-ATW-027
  -- Finding 3/4 regression tests' own 3 dedicated isolation connections
  -- (acmegps-malformed-fields, acmegps-ratelimit-baseline, acmegps-ratelimit-bypass)
  -- registered above.
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.third_party_provider_connections' and action = 'register_third_party_provider_connection';
  if v_count <> 5 then
    raise exception 'assertion failed: expected exactly 5 register audit events (acmegps + anotherprovider + acmegps-malformed-fields + acmegps-ratelimit-baseline + acmegps-ratelimit-bypass), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.third_party_provider_connections' and action = 'rotate_third_party_provider_webhook_secret';
  if v_count <> 0 then
    raise exception 'assertion failed: expected exactly 0 rotate audit events (the only rotate call in this file was rejected before capturing one), found %', v_count;
  end if;
end $$;

\echo 'ALL ATW-226E db-test assertions passed.'
