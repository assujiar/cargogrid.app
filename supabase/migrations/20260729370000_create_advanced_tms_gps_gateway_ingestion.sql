-- Advanced TMS capability ATW-226D (Prompt 226 decomposition child, "Always-on GPS
-- Gateway and direct-device telemetry ingestion" -- docs/build-log/phase-05/
-- ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1.4). The `direct_device` counterpart to
-- ATW-226C's `driver_mobile` source -- one physical hardware tracker (`app.gps_devices`,
-- ATW-223), speaking the Teltonika Codec 8 Extended protocol over raw TCP, instead of a
-- Driver PWA speaking HTTPS.
--
-- Design boundary (disclosed):
--
-- 1. **A fundamentally different trust model than ATW-226C, not the same one reused.**
--    A Driver PWA is an unauthenticated public browser session (226C's own `anon` grant
--    is the necessary consequence). The GPS Gateway is the opposite: an always-on,
--    CargoGrid-operated backend process (`220_*.md` §6: "always-on container/VPS...
--    explicitly not a Vercel Function") holding a long-lived credential of its own. This
--    migration therefore grants nothing to `anon` at all -- both functions below are
--    `service_role`-only, and reuse `PLT-129`'s `app.authenticate_api_key`/
--    `app.api_key_has_scope` exactly as that migration's own header already
--    anticipated ("the real authentication entry point a future API-gateway middleware
--    would call"). A scoped API key (`OPS:Edit`) lets the gateway's own credential be
--    revoked/rotated independently of the shared `service_role` secret -- defense in
--    depth, not a replacement for the Postgres-level `service_role` boundary.
-- 2. **Two-phase interaction, mirroring the real Teltonika wire protocol.** A device's
--    TCP handshake presents only its IMEI and needs an immediate accept/reject decision
--    before any further bytes are exchanged -- `app.resolve_gps_device_for_handshake()`
--    is that decision, called once per TCP connection. Every subsequent AVL data packet
--    on the same still-open connection is a separate `app.ingest_direct_device_telemetry_
--    batch()` call, keyed by the `device_id` the handshake already resolved (never a
--    second IMEI lookup per batch) -- the gateway process itself is what holds the
--    TCP-connection-to-device_id mapping in memory, this migration only ever sees
--    discrete, stateless RPC calls.
-- 3. **IMEI is looked up globally, not per-tenant.** `app.gps_devices` (`ATW-223`)
--    scopes its own uniqueness to `(tenant_id, imei)`, but the physical handshake only
--    ever presents the bare IMEI -- the owning tenant is not yet known to the gateway at
--    that point. `app.resolve_gps_device_for_handshake()` therefore matches on `imei`
--    alone across every tenant and explicitly refuses (rather than guesses) if more than
--    one row matches -- a deliberately conservative, disclosed limitation (a real-world
--    duplicate/typo'd IMEI registered under two tenants is refused, never silently
--    routed to the wrong one). No new database-level uniqueness constraint is added to
--    the already-applied `app.gps_devices` table for this -- widening an existing
--    table's own constraint is out of this migration's scope, and the runtime refusal
--    is a strictly safer fallback than a schema change made under uncertainty.
-- 4. **Raw storage only, exactly like `app.driver_mobile_position_reports` (`ATW-226C`).**
--    `app.direct_device_telemetry_reports` is an append-only log of what the device
--    reported, decoded but not normalized/arbitrated -- `ATW-226F`'s own canonical-
--    telemetry/arbitration layer is the real downstream consumer, not built yet. Raw
--    per-record Codec 8E IO elements are preserved verbatim in `io_elements` (a decoded
--    `{io_id: value}` map) rather than modeled as individual typed columns -- Codec 8E
--    defines dozens of IO IDs (ignition, odometer, fuel, temperature, ...) and inventing
--    a typed column per ID here would be unrequested scope; `226F` decides which IDs are
--    canonically meaningful.
-- 5. **`app.jobs` (`PLT-131`/`PLT-132`) is deliberately not used for live ingestion.**
--    `00_ADVANCED_TMS_WMS_WBS.md` names the existing generic queue as *a* reuse target
--    for GPS Gateway batch ingestion, but `226_*.md` §14B's own required mechanism is
--    "batch/RPC write" with durable buffering owned by the gateway itself -- the
--    standalone `services/gps-gateway` process (this checkpoint's own second half) is
--    where that durable buffer genuinely lives (local persistence + retry-with-backoff
--    against transient connectivity loss to Supabase), not a second, redundant
--    server-side queue. `app.jobs` remains the better fit for a genuinely scheduled/
--    poll-driven workload -- `ATW-226E`'s third-party platform adapter, a real polling
--    job by nature, is that capability's own more natural consumer, left to that child's
--    own design.
-- 6. Device status auto-transition (`installed`/`offline` -> `active` on first/renewed
--    telemetry) reuses the exact status vocabulary `app.transition_gps_device_status`
--    (`ATW-223`) already defined, but does not call that function directly -- it is
--    `OPS:Edit`-gated against a human `actor_auth_user_id`, and this transition is
--    machine-triggered with no such actor. The direct `UPDATE` below is narrowly scoped
--    (only the two specific edges telemetry itself can justify) and still captures the
--    identical audit-trail shape via `app.capture_audit_event` with a null actor and a
--    `gps-gateway:<imei>` label -- `app.audit_logs.actor_auth_user_id` is nullable by
--    design (`PLT-116`'s own schema) precisely for platform/device-triggered events like
--    this one, confirmed by direct inspection of `20260716113048_create_audit_trail.sql`.
-- 7. PostGIS point storage/validation reuses `app.geojson_point_to_geography`/
--    `app.validate_geography_point` (`PLT-134`) verbatim -- no second spatial ingestion
--    path (the parser in `services/gps-gateway` converts Codec 8E's raw lon/lat integers
--    to a GeoJSON `{type: "Point", coordinates: [lon, lat]}` payload before calling
--    either RPC below, the identical shape ATW-226C's own PWA client already produces).
-- 8. External-evidence policy (`226_*.md` §8): no physical Teltonika hardware or live
--    cellular network exists in this repository's environment. Protocol correctness is
--    proven by `services/gps-gateway`'s own deterministic byte-level parser unit tests
--    plus a local TCP simulator integration test (a scripted client that speaks the exact
--    wire protocol against the real server code) -- disclosed as
--    `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` in this checkpoint's build log, per §8's own
--    "simulators/recorded vendor frames prove repository-controlled correctness"
--    allowance.
-- 9. Per `ERR-2026-004`: this migration carries its own explicit
--    `revoke execute on all functions in schema app from public` statement before its
--    final grants.

-- Additive column (Prompt 223's own `app.gps_devices` table is never edited in place).
-- Nullable, no default -- a device that has never reported telemetry stays null, not a
-- fabricated epoch value.
alter table app.gps_devices add column last_telemetry_at timestamptz;

comment on column app.gps_devices.last_telemetry_at is
  'ATW-226D: server-assigned received_at of the most recent app.direct_device_telemetry_reports row for this device, updated only by app.ingest_direct_device_telemetry_batch(). Null until the device''s first accepted telemetry batch.';

create table app.direct_device_telemetry_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  device_id uuid not null references app.gps_devices (id),
  report_type text not null,
  event_at timestamptz not null,
  received_at timestamptz not null default now(),
  location geography(Point, 4326),
  altitude_meters numeric,
  heading_degrees numeric,
  speed_kmh numeric,
  satellite_count integer,
  raw_codec_id text not null default '8E',
  io_elements jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint direct_device_telemetry_reports_type_check check (report_type in ('location', 'heartbeat')),
  constraint direct_device_telemetry_reports_location_check check (report_type <> 'location' or location is not null),
  constraint direct_device_telemetry_reports_location_valid_check check (location is null or app.validate_geography_point(location)),
  constraint direct_device_telemetry_reports_heading_check check (heading_degrees is null or heading_degrees between 0 and 360),
  constraint direct_device_telemetry_reports_speed_check check (speed_kmh is null or speed_kmh >= 0),
  constraint direct_device_telemetry_reports_satellite_check check (satellite_count is null or satellite_count >= 0)
);

comment on table app.direct_device_telemetry_reports is
  'ATW-226D: raw direct-hardware-device telemetry decoded from Teltonika Codec 8 Extended AVL records, exactly as reported -- never normalized/arbitrated (ATW-226F''s own scope). event_at (device-claimed, from the AVL record''s own millisecond timestamp) and received_at (server-assigned) are kept separate, the identical business rule app.driver_mobile_position_reports (ATW-226C) already established. io_elements preserves the full decoded {io_id: value} map verbatim.';

create index direct_device_telemetry_reports_device_idx on app.direct_device_telemetry_reports (device_id, received_at desc);
create index direct_device_telemetry_reports_tenant_idx on app.direct_device_telemetry_reports (tenant_id, received_at desc);

-- The TCP-handshake accept/reject decision (design note 2 above). Never raises for an
-- unrecognized/foreign IMEI (an ordinary, expected outcome -- random internet scanners
-- and misconfigured devices routinely dial a raw public TCP port) -- only an invalid
-- caller credential (the gateway's own presented API key) is exceptional, since that
-- indicates the gateway deployment's own credential is broken, a real operational
-- incident, not a per-device business outcome. Every attempt, accepted or rejected, is
-- captured via app.capture_audit_event -- tenant_id is null for an IMEI that resolves to
-- no known device at all (app.audit_logs.tenant_id is nullable exactly for this
-- "platform-wide event" shape, per that table's own migration comment).
create function app.resolve_gps_device_for_handshake(
  p_raw_api_key text,
  p_imei text,
  p_gateway_instance_label text
)
returns table (accepted boolean, device_id uuid, tenant_id uuid, rejection_reason text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_auth record;
  v_match_count integer;
  v_device app.gps_devices;
  v_label text;
begin
  if p_imei is null or length(trim(p_imei)) = 0 then
    raise exception 'imei_required: a non-empty IMEI is required' using errcode = 'check_violation';
  end if;

  select * into v_auth from app.authenticate_api_key(p_raw_api_key);

  if not app.api_key_has_scope(v_auth.api_key_id, 'OPS:Edit') then
    raise exception 'insufficient_authority: presented API key lacks OPS:Edit scope required for GPS gateway operation'
      using errcode = 'insufficient_privilege';
  end if;

  v_label := coalesce(p_gateway_instance_label, 'gps-gateway') || ':' || p_imei;

  select count(*) into v_match_count from app.gps_devices where imei = p_imei;

  if v_match_count = 0 then
    perform app.capture_audit_event(
      null, null, v_label, 'gps_gateway_device_handshake',
      'app.gps_devices', null, 'failure', 'imei_not_registered', null, jsonb_build_object('imei', p_imei)
    );
    return query select false, null::uuid, null::uuid, 'imei_not_registered'::text;
    return;
  end if;

  if v_match_count > 1 then
    perform app.capture_audit_event(
      null, null, v_label, 'gps_gateway_device_handshake',
      'app.gps_devices', null, 'failure', 'imei_ambiguous_across_tenants', null, jsonb_build_object('imei', p_imei)
    );
    return query select false, null::uuid, null::uuid, 'imei_ambiguous_across_tenants'::text;
    return;
  end if;

  select * into v_device from app.gps_devices where imei = p_imei;

  if v_device.tenant_id <> v_auth.tenant_id then
    perform app.capture_audit_event(
      v_device.tenant_id, null, v_label, 'gps_gateway_device_handshake',
      'app.gps_devices', v_device.id, 'failure', 'tenant_mismatch', null, jsonb_build_object('imei', p_imei)
    );
    return query select false, v_device.id, v_device.tenant_id, 'tenant_mismatch'::text;
    return;
  end if;

  if v_device.status not in ('installed', 'active', 'offline') then
    perform app.capture_audit_event(
      v_device.tenant_id, null, v_label, 'gps_gateway_device_handshake',
      'app.gps_devices', v_device.id, 'failure', 'device_not_ingestible', null, jsonb_build_object('imei', p_imei, 'status', v_device.status)
    );
    return query select false, v_device.id, v_device.tenant_id, 'device_not_ingestible'::text;
    return;
  end if;

  perform app.capture_audit_event(
    v_device.tenant_id, null, v_label, 'gps_gateway_device_handshake',
    'app.gps_devices', v_device.id, 'success', null, null, jsonb_build_object('imei', p_imei)
  );

  return query select true, v_device.id, v_device.tenant_id, null::text;
end;
$$;

comment on function app.resolve_gps_device_for_handshake is
  'ATW-226D: called once per TCP connection, immediately after a device presents its IMEI. service_role-only (see this migration''s own header design note 1) -- never anon. Returns a status row, never raises, for every per-device outcome; only a bad gateway credential itself raises.';

-- Per-connection batch ingestion (design note 2 above), keyed by the device_id the
-- handshake already resolved. Re-validates the API key/scope/tenant/status on every call
-- (defense in depth -- a long-lived TCP connection could outlive a mid-connection
-- suspend/revoke) rather than trusting the handshake's decision to still hold.
create function app.ingest_direct_device_telemetry_batch(
  p_raw_api_key text,
  p_device_id uuid,
  p_reports jsonb,
  p_gateway_instance_label text
)
returns table (device_id uuid, tenant_id uuid, accepted_count integer, device_status text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_auth record;
  v_device app.gps_devices;
  v_report jsonb;
  v_report_type text;
  v_event_at timestamptz;
  v_lon numeric;
  v_lat numeric;
  v_geojson jsonb;
  v_geog geography;
  v_accepted integer := 0;
  v_max_event_at timestamptz;
  v_new_status text;
  v_label text;
begin
  if p_device_id is null then
    raise exception 'device_id_required: a device_id is required' using errcode = 'check_violation';
  end if;
  if p_reports is null or jsonb_typeof(p_reports) <> 'array' or jsonb_array_length(p_reports) = 0 then
    raise exception 'reports_required: at least one report is required' using errcode = 'check_violation';
  end if;

  select * into v_auth from app.authenticate_api_key(p_raw_api_key);

  if not app.api_key_has_scope(v_auth.api_key_id, 'OPS:Edit') then
    raise exception 'insufficient_authority: presented API key lacks OPS:Edit scope required for GPS gateway operation'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;
  if v_device.tenant_id <> v_auth.tenant_id then
    raise exception 'tenant_mismatch: device % belongs to a different tenant than the presented API key', p_device_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_device.status not in ('installed', 'active', 'offline') then
    raise exception 'device_not_ingestible: device % is % and cannot accept telemetry', p_device_id, v_device.status
      using errcode = 'check_violation';
  end if;

  v_label := coalesce(p_gateway_instance_label, 'gps-gateway') || ':' || v_device.imei;
  v_max_event_at := v_device.last_telemetry_at;

  for v_report in select * from jsonb_array_elements(p_reports)
  loop
    v_report_type := v_report ->> 'report_type';
    if v_report_type not in ('location', 'heartbeat') then
      raise exception 'invalid_report_type: % is not a supported report type', v_report_type using errcode = 'check_violation';
    end if;

    v_event_at := (v_report ->> 'event_at')::timestamptz;
    if v_event_at is null then
      raise exception 'event_at_required: every report requires event_at' using errcode = 'check_violation';
    end if;

    v_geog := null;
    if v_report_type = 'location' then
      v_lon := (v_report ->> 'longitude')::numeric;
      v_lat := (v_report ->> 'latitude')::numeric;
      if v_lon is null or v_lat is null then
        raise exception 'location_required: a location report requires longitude and latitude' using errcode = 'check_violation';
      end if;
      v_geojson := jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(v_lon, v_lat));
      v_geog := app.geojson_point_to_geography(v_geojson);
    end if;

    -- received_at uses clock_timestamp(), not the column's own now()-based default --
    -- a single batch call inserts every one of its reports inside one transaction, and
    -- now() is frozen at transaction start (identical for every row in the loop);
    -- clock_timestamp() genuinely advances per iteration, so "newest first" ordering
    -- downstream (app.get_direct_device_telemetry_reports) stays meaningful even for
    -- reports that share one ingestion batch.
    insert into app.direct_device_telemetry_reports (
      tenant_id, device_id, report_type, event_at, received_at, location,
      altitude_meters, heading_degrees, speed_kmh, satellite_count, raw_codec_id, io_elements
    ) values (
      v_device.tenant_id, v_device.id, v_report_type, v_event_at, clock_timestamp(), v_geog,
      (v_report ->> 'altitude_meters')::numeric, (v_report ->> 'heading_degrees')::numeric,
      (v_report ->> 'speed_kmh')::numeric, (v_report ->> 'satellite_count')::integer,
      coalesce(v_report ->> 'raw_codec_id', '8E'), coalesce(v_report -> 'io_elements', '{}'::jsonb)
    );

    v_accepted := v_accepted + 1;
    if v_max_event_at is null or v_event_at > v_max_event_at then
      v_max_event_at := v_event_at;
    end if;
  end loop;

  v_new_status := v_device.status;
  if v_device.status in ('installed', 'offline') then
    v_new_status := 'active';
  end if;

  update app.gps_devices
  set last_telemetry_at = v_max_event_at,
      status = v_new_status
  where id = v_device.id
  returning * into v_device;

  perform app.capture_audit_event(
    v_device.tenant_id, null, v_label, 'ingest_direct_device_telemetry_batch',
    'app.gps_devices', v_device.id, 'success', null, null,
    jsonb_build_object('device_id', v_device.id, 'accepted_count', v_accepted, 'device_status', v_new_status)
  );

  return query select v_device.id, v_device.tenant_id, v_accepted, v_device.status;
end;
$$;

comment on function app.ingest_direct_device_telemetry_batch is
  'ATW-226D: the per-connection batch-write RPC (design note 2/5 above) -- durable buffering/retry against transient connectivity loss is services/gps-gateway''s own responsibility, not this function''s. Raises on any structurally invalid report (a trusted, already-protocol-decoded caller, unlike ATW-226C''s anon-facing status-column pattern) -- the whole batch rolls back atomically on the first bad report, never a partial silent accept. Auto-transitions device status installed/offline -> active on any accepted batch (design note 6).';

-- Computed GeoJSON projection, the identical pattern app.get_driver_mobile_position_reports
-- (ATW-226C) already established.
create function app.get_direct_device_telemetry_reports(p_device_id uuid)
returns table (
  id uuid, tenant_id uuid, device_id uuid, report_type text,
  event_at timestamptz, received_at timestamptz, location_geojson jsonb,
  altitude_meters numeric, heading_degrees numeric, speed_kmh numeric, satellite_count integer,
  raw_codec_id text, io_elements jsonb, created_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public, pg_temp
as $$
  select
    r.id, r.tenant_id, r.device_id, r.report_type,
    r.event_at, r.received_at,
    case when r.location is not null then ST_AsGeoJSON(r.location)::jsonb else null end,
    r.altitude_meters, r.heading_degrees, r.speed_kmh, r.satellite_count,
    r.raw_codec_id, r.io_elements, r.created_at
  from app.direct_device_telemetry_reports r
  where r.device_id = p_device_id
  order by r.received_at desc;
$$;

comment on function app.get_direct_device_telemetry_reports is
  'ATW-226D: read projection for one direct-hardware device''s own raw report history, newest first. Dispatcher/administration read only (226H''s own future UI); never called by the GPS Gateway ingestion path.';

alter table app.direct_device_telemetry_reports enable row level security;

create policy direct_device_telemetry_reports_select_scoped on app.direct_device_telemetry_reports
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.direct_device_telemetry_reports to authenticated, service_role;
grant insert, update, delete on app.direct_device_telemetry_reports to service_role;

grant execute on function app.resolve_gps_device_for_handshake(text, text, text) to service_role;
grant execute on function app.ingest_direct_device_telemetry_batch(text, uuid, jsonb, text) to service_role;
grant execute on function app.get_direct_device_telemetry_reports(uuid) to authenticated, service_role;
