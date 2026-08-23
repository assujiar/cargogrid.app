-- Advanced TMS capability ATW-226E (Prompt 226 decomposition child, "Third-party GPS
-- platform adapter contract" -- docs/build-log/phase-05/
-- ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1.4). The `third_party_platform` counterpart to
-- ATW-226C's `driver_mobile` and ATW-226D's `direct_device` sources -- an existing
-- vendor GPS/fleet platform pushing telemetry to CargoGrid over an inbound webhook,
-- authenticated with the identical HMAC-SHA256 signature scheme ADR-0011
-- (`PLT-129`'s own `app.compute_webhook_signature`/`app.verify_webhook_signature`)
-- already established for CargoGrid's own *outbound* webhooks.
--
-- Design boundary (disclosed):
--
-- 1. **A third distinct trust model, each one deliberately reusing the closest real
--    precedent rather than inventing a fourth.** `ATW-226C` (driver_mobile) is an
--    unauthenticated PWA with a bearer token; `ATW-226D` (direct_device) is a trusted
--    backend process with a scoped API key; this child is an external vendor platform
--    with no CargoGrid session, authenticated by HMAC signature over the raw webhook
--    body -- the identical scheme `app.webhook_endpoints`/`app.compute_webhook_signature`/
--    `app.verify_webhook_signature` (`PLT-129`, ADR-0011) already implements for the
--    opposite direction (CargoGrid signing its own outbound deliveries). A signing
--    secret is fundamentally different from a bearer token or API key: it must be
--    stored in *retrievable* form to be recomputed and compared, never a one-way hash
--    (`app.webhook_endpoints.secret_value`'s own table comment: "a signing secret cannot
--    be a one-way hash"). `app.third_party_provider_connections.webhook_secret_value`
--    reuses that exact accepted shape -- zero `authenticated`/`anon` grant on the column,
--    the tenant/operator receives the raw value exactly once via
--    `app.register_third_party_provider_connection()`/`app.rotate_third_party_provider_
--    webhook_secret()`'s own return row.
-- 2. **The one deliberate `anon` grant in this migration, the third in this repository,
--    precedented, not novel.** A direct query of `information_schema.routine_privileges`
--    found `anon` already holds `EXECUTE` on six pre-existing functions (five pre-login
--    resolvers plus `app.ingest_driver_mobile_report`, `ATW-226C`). The provider webhook
--    endpoint has no CargoGrid session either, so `app.ingest_third_party_provider_
--    webhook_event` follows `ATW-226C`'s own proven anon-facing shape exactly: a
--    caller-supplied `client_key` rate-limited via its own dedicated attempts table, and
--    a returned status column rather than a raised exception for every failure mode
--    (a raised exception's own distinct error class/timing would be a real signature-
--    oracle for an unauthenticated caller -- the identical reasoning `226C`'s own header
--    already applied to token validation, extended here to signature validation).
-- 3. **Third-party adapters are case-specific (`226_*.md` §16), never a universal
--    lowest-common-denominator payload parser** -- the same design boundary
--    `app.provider_vehicle_mappings` (`ATW-223`) already drew for identity mapping.
--    Since no live vendor contract exists at this checkpoint (`226_*.md` §8's own
--    external-evidence allowance), this migration defines and validates one
--    repository-owned *reference* webhook JSON contract (`event_id`/`vehicle_id`/
--    `event_type`/`timestamp`/`latitude`/`longitude`/`speed_kmh`/`heading_degrees`) --
--    disclosed as a representative example contract, never a claim that any named
--    real-world vendor's actual proprietary payload shape is certified or live. A real
--    vendor integration would add its own translation layer in front of this same RPC,
--    not fork it.
-- 4. **Unmapped vehicles are quarantined, never silently dropped** (`226_*.md` §16:
--    "Quarantine unknown device/provider data"; §14: "Never silently drop accepted
--    data"). `app.third_party_provider_ingestion_attempts.raw_payload` preserves the
--    full decoded payload for a `quarantined` outcome specifically, giving an operator
--    real evidence to later backfill the missing `app.provider_vehicle_mappings` row --
--    the closest real analogue this repository has to the WBS's own named "DLQ"
--    concept, reusing the existing rate-limiting attempts table rather than a third,
--    redundant table.
-- 5. **Replay defense is two-layered**: `app.verify_third_party_provider_webhook_
--    signature` reuses ADR-0011's own 5-minute timestamp-tolerance window verbatim, and
--    `provider_event_id` carries a partial unique index per connection (idempotency --
--    a genuine retried delivery of the same event returns `duplicate`, a real, distinct,
--    non-punished outcome, never treated as `invalid` and never re-inserted).
-- 6. **Polling (`poll_cursor`/watermark) is structurally represented, not executed.**
--    `226_*.md` §8/§14 both explicitly allow this: a live third-party provider contract
--    is conditional, `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE`. `integration_mode =
--    'poll'` connections store a `poll_cursor` (opaque per-provider watermark jsonb) and
--    `app.update_third_party_provider_poll_cursor()` exists for a future real poll
--    worker to call, but no poll HTTP call is made anywhere in this repository -- there
--    is no live provider credential to call, and fabricating one would violate `226_*.md`
--    §8's own "do not claim a named provider is live... without live evidence."
--    `app.jobs` (`PLT-131`/`PLT-132`) is the disclosed intended reuse target for a real
--    poll worker's own scheduling (`ATW-226D`'s own migration header design note 5
--    already named this child as the more natural `app.jobs` consumer) -- not built this
--    checkpoint, since there is nothing real to schedule yet.
-- 7. Per `ERR-2026-004`: this migration carries its own explicit
--    `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its
--    final grants.

create table app.third_party_provider_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  provider_code text not null,
  integration_mode text not null,
  webhook_secret_value text,
  poll_cursor jsonb,
  status text not null default 'active',
  consecutive_failure_count integer not null default 0,
  last_successful_ingest_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint third_party_provider_connections_tenant_provider_unique unique (tenant_id, provider_code),
  constraint third_party_provider_connections_mode_check check (integration_mode in ('webhook', 'poll')),
  constraint third_party_provider_connections_status_check check (status in ('active', 'disabled')),
  constraint third_party_provider_connections_failure_count_check check (consecutive_failure_count >= 0),
  constraint third_party_provider_connections_webhook_secret_check check (integration_mode <> 'webhook' or webhook_secret_value is not null)
);

comment on table app.third_party_provider_connections is
  'ATW-226E: one tenant''s own connection to one external GPS/fleet platform (provider_code, case-specific -- no universal provider abstraction). webhook_secret_value is the raw HMAC-SHA256 signing secret, needed in retrievable form (the identical accepted shape app.webhook_endpoints.secret_value, PLT-129/ADR-0011, already established for the opposite direction) -- zero authenticated/anon grant on this table; the raw value is returned exactly once by app.register_third_party_provider_connection()/app.rotate_third_party_provider_webhook_secret(). poll_cursor is an opaque per-provider watermark, written only by a future real poll worker (structurally represented, not executed this checkpoint -- 226_*.md §8''s own conditional-provider allowance).';

create index third_party_provider_connections_tenant_idx on app.third_party_provider_connections (tenant_id);

create function app.touch_third_party_provider_connections_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger third_party_provider_connections_touch_row
  before update on app.third_party_provider_connections
  for each row
  execute function app.touch_third_party_provider_connections_row();

-- Anti-enumeration rate limiting, the identical shape app.driver_mobile_ingestion_attempts
-- (ATW-226C) already established. raw_payload is populated only for a quarantined
-- outcome (design note 4 above) -- every other outcome leaves it null, since a
-- signature-invalid/rate-limited caller has proven nothing about the payload's own
-- trustworthiness worth preserving.
create table app.third_party_provider_ingestion_attempts (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid references app.third_party_provider_connections (id),
  client_key text not null,
  result text not null,
  reason text,
  raw_payload jsonb,
  occurred_at timestamptz not null default now(),
  constraint third_party_provider_ingestion_attempts_result_check check (result in ('success', 'invalid', 'rate_limited', 'duplicate', 'quarantined'))
);

comment on table app.third_party_provider_ingestion_attempts is
  'ATW-226E: append-only evidence of every app.ingest_third_party_provider_webhook_event() call. A quarantined outcome (unmapped external_vehicle_id) preserves the full raw_payload for operator review -- this repository''s own closest real analogue to the WBS''s named "DLQ" concept.';

create index third_party_provider_ingestion_attempts_client_key_idx on app.third_party_provider_ingestion_attempts (client_key, occurred_at desc);
create index third_party_provider_ingestion_attempts_connection_idx on app.third_party_provider_ingestion_attempts (connection_id, occurred_at desc);

-- Raw, append-only ingestion log -- never normalized/arbitrated here, exactly like
-- app.driver_mobile_position_reports/app.direct_device_telemetry_reports.
-- provider_event_id carries the partial unique index that makes replay/idempotency real
-- (design note 5).
create table app.third_party_telemetry_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.third_party_provider_connections (id),
  vehicle_master_id uuid not null references app.master_records (id),
  provider_event_id text not null,
  report_type text not null,
  event_at timestamptz not null,
  received_at timestamptz not null default now(),
  location geography(Point, 4326),
  speed_kmh numeric,
  heading_degrees numeric,
  raw_fields jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint third_party_telemetry_reports_type_check check (report_type in ('location', 'heartbeat')),
  constraint third_party_telemetry_reports_location_check check (report_type <> 'location' or location is not null),
  constraint third_party_telemetry_reports_location_valid_check check (location is null or app.validate_geography_point(location)),
  constraint third_party_telemetry_reports_heading_check check (heading_degrees is null or heading_degrees between 0 and 360),
  constraint third_party_telemetry_reports_speed_check check (speed_kmh is null or speed_kmh >= 0)
);

comment on table app.third_party_telemetry_reports is
  'ATW-226E: raw third-party-platform telemetry, exactly as reported -- never normalized/arbitrated (ATW-226F''s own scope). provider_event_id is the vendor''s own event identifier, used for idempotent replay defense (partial unique index below), not this repository''s own id.';

create unique index third_party_telemetry_reports_connection_event_unique on app.third_party_telemetry_reports (connection_id, provider_event_id);
create index third_party_telemetry_reports_vehicle_idx on app.third_party_telemetry_reports (vehicle_master_id, received_at desc);
create index third_party_telemetry_reports_tenant_idx on app.third_party_telemetry_reports (tenant_id, received_at desc);

-- app.register_third_party_provider_connection -- idempotent on (tenant_id,
-- provider_code), mirrors app.register_gps_device (ATW-223). Mints a raw webhook secret
-- only for integration_mode='webhook'; a 'poll' connection has no secret to mint (a real
-- poll worker would instead hold the *provider's own* API credential, out of this
-- table's shape entirely -- the identical disclosed boundary app.gps_devices' own table
-- comment already drew for device secrets, ATW-223).
create function app.register_third_party_provider_connection(
  p_tenant_id uuid,
  p_provider_code text,
  p_integration_mode text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (connection_id uuid, provider_code text, integration_mode text, raw_webhook_secret text, status text)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.third_party_provider_connections;
  v_raw_secret text;
  v_conn app.third_party_provider_connections;
begin
  if p_provider_code is null or length(trim(p_provider_code)) = 0 then
    raise exception 'provider_code_required: a non-empty provider_code is required' using errcode = 'check_violation';
  end if;
  if p_integration_mode not in ('webhook', 'poll') then
    raise exception 'invalid_integration_mode: % is not a supported integration mode', p_integration_mode using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.third_party_provider_connections c where c.tenant_id = p_tenant_id and c.provider_code = p_provider_code;
  if found then
    return query select v_existing.id, v_existing.provider_code, v_existing.integration_mode, null::text, v_existing.status;
    return;
  end if;

  if p_integration_mode = 'webhook' then
    v_raw_secret := 'tpws_' || encode(gen_random_bytes(32), 'hex');
  end if;

  insert into app.third_party_provider_connections (tenant_id, provider_code, integration_mode, webhook_secret_value, created_by)
  values (p_tenant_id, p_provider_code, p_integration_mode, v_raw_secret, p_actor_label)
  returning * into v_conn;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_third_party_provider_connection',
    'app.third_party_provider_connections', v_conn.id, 'success', null, null,
    jsonb_build_object('provider_code', p_provider_code, 'integration_mode', p_integration_mode)
  );

  return query select v_conn.id, v_conn.provider_code, v_conn.integration_mode, v_raw_secret, v_conn.status;
end;
$$;

comment on function app.register_third_party_provider_connection is
  'ATW-226E: idempotent on (tenant, provider_code). Returns the raw webhook secret exactly once, only on first creation -- an idempotent re-call (existing connection) returns null for raw_webhook_secret, never re-discloses or re-mints it (app.rotate_third_party_provider_webhook_secret is the only way to get a new one).';

create function app.rotate_third_party_provider_webhook_secret(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (connection_id uuid, raw_webhook_secret text)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
  v_raw_secret text;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_conn.integration_mode <> 'webhook' then
    raise exception 'not_a_webhook_connection: % is a % connection, has no webhook secret to rotate', p_connection_id, v_conn.integration_mode
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_raw_secret := 'tpws_' || encode(gen_random_bytes(32), 'hex');

  update app.third_party_provider_connections set webhook_secret_value = v_raw_secret where id = p_connection_id;

  perform app.capture_audit_event(
    v_conn.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_third_party_provider_webhook_secret',
    'app.third_party_provider_connections', p_connection_id, 'success', null, null, jsonb_build_object('connection_id', p_connection_id)
  );

  return query select v_conn.id, v_raw_secret;
end;
$$;

comment on function app.rotate_third_party_provider_webhook_secret is
  'ATW-226E: immediate rotation, no overlap window (unlike app.rotate_api_key) -- a webhook secret has exactly one live consumer (the provider''s own outbound webhook config), which the operator updates out-of-band at the same time as calling this function.';

create function app.update_third_party_provider_poll_cursor(
  p_connection_id uuid,
  p_cursor jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.third_party_provider_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_conn.integration_mode <> 'poll' then
    raise exception 'not_a_poll_connection: % is a % connection, has no poll cursor to update', p_connection_id, v_conn.integration_mode
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.third_party_provider_connections set poll_cursor = p_cursor where id = p_connection_id
  returning * into v_conn;

  return v_conn;
end;
$$;

comment on function app.update_third_party_provider_poll_cursor is
  'ATW-226E: the write path a future real poll worker would call after each successful page fetch (design note 6 above) -- no such worker exists yet in this repository.';

-- ADR-0011 verbatim, reused for the opposite direction (design note 1/5 above).
create function app.compute_third_party_provider_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint)
returns text
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_secret text;
  v_signed_payload text;
begin
  select webhook_secret_value into v_secret from app.third_party_provider_connections where id = p_connection_id;
  if v_secret is null then
    raise exception 'connection_not_found_or_not_webhook: no webhook-mode connection %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_signed_payload := p_timestamp::text || '.' || p_payload;
  return encode(hmac(v_signed_payload, v_secret, 'sha256'), 'hex');
end;
$$;

create function app.verify_third_party_provider_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint, p_signature text)
returns boolean
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_expected text;
begin
  if p_timestamp is null or abs(extract(epoch from now()) - p_timestamp) > 300 then
    return false;
  end if;

  begin
    v_expected := app.compute_third_party_provider_webhook_signature(p_connection_id, p_payload, p_timestamp);
  exception
    when others then
      return false;
  end;

  return v_expected = p_signature;
end;
$$;

comment on function app.verify_third_party_provider_webhook_signature is
  'ATW-226E: ADR-0011''s own HMAC-SHA256-over-"<timestamp>.<payload>" scheme plus 5-minute timestamp-tolerance replay window, reused verbatim from app.verify_webhook_signature (PLT-129) for the inbound direction. Fails closed to false for every reason (stale timestamp, unknown/non-webhook connection, mismatched signature) -- never raises, so a caller-distinguishable error class/timing never leaks to an unauthenticated provider.';

-- The one anon-callable function in this migration -- see design note 2 above. Never
-- raises for an auth/validation/business-outcome failure; every outcome is a returned
-- row, the identical shape app.ingest_driver_mobile_report (ATW-226C) already
-- established.
create function app.ingest_third_party_provider_webhook_event(
  p_connection_id uuid,
  p_client_key text,
  p_raw_payload text,
  p_timestamp bigint,
  p_signature text
)
returns table (ingest_status text, report_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_conn app.third_party_provider_connections;
  v_payload jsonb;
  v_event_id text;
  v_vehicle_external_id text;
  v_report_type text;
  v_event_at timestamptz;
  v_lat numeric;
  v_lon numeric;
  v_speed numeric;
  v_heading numeric;
  v_mapping app.provider_vehicle_mappings;
  v_geojson jsonb;
  v_geog geography;
  v_report app.third_party_telemetry_reports;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'tracking_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.third_party_provider_ingestion_attempts
  where client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'rate_limited', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found or v_conn.integration_mode <> 'webhook' or v_conn.status <> 'active' then
    -- v_conn.id, not p_connection_id -- a caller-supplied connection_id that does not
    -- exist at all must not be inserted as the FK value (v_conn.id is null in that
    -- case, the FK column's own nullable design intent for exactly this outcome).
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (v_conn.id, p_client_key, 'invalid', 'connection_not_active');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if not app.verify_third_party_provider_webhook_signature(p_connection_id, p_raw_payload, p_timestamp, p_signature) then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'signature_verification_failed');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  begin
    v_payload := p_raw_payload::jsonb;
  exception
    when others then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'malformed_json');
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  v_event_id := v_payload ->> 'event_id';
  v_vehicle_external_id := v_payload ->> 'vehicle_id';
  v_report_type := v_payload ->> 'event_type';
  v_event_at := (v_payload ->> 'timestamp')::timestamptz;

  if v_event_id is null or v_vehicle_external_id is null or v_report_type not in ('location', 'heartbeat') or v_event_at is null then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'schema_validation_failed', v_payload);
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if exists (select 1 from app.third_party_telemetry_reports where connection_id = p_connection_id and provider_event_id = v_event_id) then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'duplicate', 'provider_event_id_already_ingested');
    return query select 'duplicate'::text, null::uuid;
    return;
  end if;

  select * into v_mapping
  from app.provider_vehicle_mappings
  where tenant_id = v_conn.tenant_id and provider_code = v_conn.provider_code and external_vehicle_id = v_vehicle_external_id and status = 'active';
  if not found then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'quarantined', 'unmapped_external_vehicle_id', v_payload);
    return query select 'quarantined'::text, null::uuid;
    return;
  end if;

  v_lat := (v_payload ->> 'latitude')::numeric;
  v_lon := (v_payload ->> 'longitude')::numeric;
  v_speed := (v_payload ->> 'speed_kmh')::numeric;
  v_heading := (v_payload ->> 'heading_degrees')::numeric;

  if v_report_type = 'location' and (v_lat is null or v_lon is null) then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'location_report_missing_coordinates', v_payload);
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  v_geog := null;
  if v_report_type = 'location' then
    v_geojson := jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(v_lon, v_lat));
    v_geog := app.geojson_point_to_geography(v_geojson);
  end if;

  insert into app.third_party_telemetry_reports (
    tenant_id, connection_id, vehicle_master_id, provider_event_id, report_type, event_at, location, speed_kmh, heading_degrees, raw_fields
  ) values (
    v_conn.tenant_id, v_conn.id, v_mapping.vehicle_master_id, v_event_id, v_report_type, v_event_at, v_geog, v_speed, v_heading, v_payload
  )
  returning * into v_report;

  update app.third_party_provider_connections set last_successful_ingest_at = now(), consecutive_failure_count = 0 where id = v_conn.id;

  insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result) values (p_connection_id, p_client_key, 'success');

  return query select 'ok'::text, v_report.id;
end;
$$;

comment on function app.ingest_third_party_provider_webhook_event is
  'ATW-226E: the one anon-callable HTTPS webhook ingestion entry point (design note 2 above). Validates the reference JSON contract (design note 3), quarantines an unmapped external_vehicle_id rather than dropping it (design note 4), and treats a replayed provider_event_id as a distinct duplicate outcome, never an error (design note 5). Raw storage only -- never normalizes/arbitrates (ATW-226F''s own scope).';

-- Computed GeoJSON projection, the identical pattern app.get_direct_device_telemetry_reports
-- (ATW-226D) already established.
create function app.get_third_party_telemetry_reports(p_connection_id uuid)
returns table (
  id uuid, tenant_id uuid, connection_id uuid, vehicle_master_id uuid, provider_event_id text,
  report_type text, event_at timestamptz, received_at timestamptz, location_geojson jsonb,
  speed_kmh numeric, heading_degrees numeric, raw_fields jsonb, created_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public, pg_temp
as $$
  select
    r.id, r.tenant_id, r.connection_id, r.vehicle_master_id, r.provider_event_id,
    r.report_type, r.event_at, r.received_at,
    case when r.location is not null then ST_AsGeoJSON(r.location)::jsonb else null end,
    r.speed_kmh, r.heading_degrees, r.raw_fields, r.created_at
  from app.third_party_telemetry_reports r
  where r.connection_id = p_connection_id
  order by r.received_at desc;
$$;

comment on function app.get_third_party_telemetry_reports is
  'ATW-226E: read projection for one third-party connection''s own raw report history, newest first. Dispatcher/administration read only (226H''s own future UI); never called by the anon-facing ingestion path.';

alter table app.third_party_provider_connections enable row level security;
alter table app.third_party_telemetry_reports enable row level security;

create policy third_party_provider_connections_select_scoped on app.third_party_provider_connections
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy third_party_telemetry_reports_select_scoped on app.third_party_telemetry_reports
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.third_party_provider_connections to authenticated, service_role;
grant insert, update, delete on app.third_party_provider_connections to service_role;
grant select on app.third_party_telemetry_reports to authenticated, service_role;
grant insert, update, delete on app.third_party_telemetry_reports to service_role;
grant insert on app.third_party_provider_ingestion_attempts to service_role;

grant execute on function app.register_third_party_provider_connection(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.rotate_third_party_provider_webhook_secret(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.update_third_party_provider_poll_cursor(uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.compute_third_party_provider_webhook_signature(uuid, text, bigint) to service_role;
grant execute on function app.verify_third_party_provider_webhook_signature(uuid, text, bigint, text) to service_role;
grant execute on function app.get_third_party_telemetry_reports(uuid) to authenticated, service_role;
-- Deliberate exception -- an unauthenticated third-party provider webhook has no other
-- way to reach this function. See design note 2 above for why this is safe.
grant execute on function app.ingest_third_party_provider_webhook_event(uuid, text, text, bigint, text) to anon, authenticated, service_role;
