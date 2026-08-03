-- Advanced TMS capability ATW-226I (Prompt 226 decomposition's closing child,
-- "Deployment, observability, load, security, outage, and recovery verification" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1.4). A bounded,
-- finding-linked hardening migration (mirrors PLT-138's own `harden_` precedent,
-- docs/build-log/phase-01/PLT-138.md) -- not a new capability.
--
-- Real finding, found during this checkpoint's own outage/recovery review of every
-- `226` ingestion path: `app.third_party_provider_connections.consecutive_failure_count`
-- has existed since `ATW-226E`'s own original migration, correctly reset to 0 on a
-- successful ingest (line 494 of that migration), but nothing anywhere ever increments
-- it or acts on it -- unlike `app.webhook_endpoints.consecutive_failure_count`
-- (`PLT-129`, `ADR-0011`), which auto-disables an endpoint at exactly 10 consecutive
-- delivery failures. A third-party provider whose signing key is compromised, rotated
-- without updating CargoGrid, or that is actively being probed with forged signatures
-- would keep this connection silently `active` forever -- a real, disclosed outage/
-- security gap squarely inside this closing child's own named remit ("security...
-- outage, and recovery"), not a new feature.
--
-- Repair (disclosed):
--
-- 1. **Reuses `ADR-0011`'s exact 10-consecutive-failure threshold and evidence-carrying
--    columns (`auto_disabled_at`/`disabled_reason`), does not invent a new policy.**
--    `app.ingest_third_party_provider_webhook_event` (`ATW-226E`, already widened once
--    at `ATW-226F` to add the canonicalization call) is widened a second time via
--    `CREATE OR REPLACE FUNCTION` with its own exact, unchanged signature -- based on
--    its own *current* body (226F's own `perform app.arbitrate_and_project_vehicle_
--    position(...)` call preserved verbatim, not the stale pre-226F body), only the
--    `signature_verification_failed` branch gains the increment/auto-disable logic,
--    mirroring `app.record_webhook_delivery_attempt`'s own failure-branch exactly
--    (`supabase/migrations/20260719150000_create_api_key_webhook_primitives.sql`).
--    Deliberately scoped to signature failures only, never `malformed_json`/`schema_
--    validation_failed`/`quarantined` -- those are data-quality outcomes, not a
--    security/outage signal about the connection's own health, the same distinction
--    `ADR-0011`'s own webhook-delivery-failure counter draws (a delivery HTTP failure,
--    not a locally-invalid delivery request, increments that counter).
-- 2. **No audit event is captured for the automated auto-disable transition itself** --
--    mirrors `app.record_webhook_delivery_attempt`'s own identical precedent exactly
--    (that function's own auto-disable branch never calls `app.capture_audit_event`
--    either): an unattended, no-human-actor state transition is evidenced by the row's
--    own timestamped `auto_disabled_at`/`disabled_reason` columns, not a synthetic
--    audit-log actor.
-- 3. **Two new authenticated recovery RPCs**, mirroring `app.disable_webhook_endpoint`/
--    `app.reenable_webhook_endpoint` exactly: `app.disable_third_party_provider_
--    connection` (manual disable, idempotent-safe, `OPS:Edit`) and `app.reenable_third_
--    party_provider_connection` (resets the failure counter, `OPS:Edit`) -- without
--    these, an auto-disabled connection had no recovery path at all, and an operator had
--    no way to proactively disable a connection they already know is compromised.
-- 4. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON ALL
--    FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

alter table app.third_party_provider_connections
  add column auto_disabled_at timestamptz,
  add column disabled_reason text;

comment on column app.third_party_provider_connections.auto_disabled_at is
  'ATW-226I: set only by the automated 10-consecutive-signature-failure auto-disable path (never by a human actor) -- app.disable_third_party_provider_connection (manual) also sets it, since both are the identical disabled state, distinguished only by disabled_reason.';

comment on column app.third_party_provider_connections.disabled_reason is
  'ATW-226I: ''consecutive_failure_threshold_exceeded'' for an automated auto-disable, or the caller-supplied (or default ''manual disable'') reason for app.disable_third_party_provider_connection. Cleared on app.reenable_third_party_provider_connection.';

create or replace function app.ingest_third_party_provider_webhook_event(
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
  v_new_failure_count integer;
begin
  -- ATW-226I widens ATW-226F's own already-widened body below (this function was
  -- CREATE OR REPLACE'd a second time at 226F to add the app.arbitrate_and_project_
  -- vehicle_position() call near the end -- that call is preserved unchanged here,
  -- only the signature-failure branch immediately below gains the auto-disable logic).
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
    -- ATW-226I (design note 1): a genuine security/outage signal about this
    -- connection's own health, unlike a locally-invalid payload below -- mirrors
    -- app.record_webhook_delivery_attempt's own failure branch exactly (ADR-0011).
    v_new_failure_count := v_conn.consecutive_failure_count + 1;
    update app.third_party_provider_connections
    set consecutive_failure_count = v_new_failure_count,
        status = case when v_new_failure_count >= 10 then 'disabled' else status end,
        auto_disabled_at = case when v_new_failure_count >= 10 and status <> 'disabled' then now() else auto_disabled_at end,
        disabled_reason = case when v_new_failure_count >= 10 and status <> 'disabled' then 'consecutive_failure_threshold_exceeded' else disabled_reason end
    where id = v_conn.id;

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

  -- ATW-226F: canonicalize -- never raises, never blocks the already-committed raw insert above.
  perform app.arbitrate_and_project_vehicle_position(
    v_conn.tenant_id, v_mapping.vehicle_master_id, 'third_party_platform', v_report.id, v_event_at, v_report.received_at,
    v_geog, v_speed, v_heading, null::numeric
  );

  return query select 'ok'::text, v_report.id;
end;
$$;

comment on function app.ingest_third_party_provider_webhook_event is
  'ATW-226E, widened at ATW-226F (canonicalization, app.arbitrate_and_project_vehicle_position) and again at ATW-226I (harden, design note 1: a 10-consecutive-signature-failure auto-disable on the connection, ADR-0011''s own exact threshold/pattern, mirroring app.record_webhook_delivery_attempt). Quarantines an unmapped external_vehicle_id rather than dropping it (design note 4 of the original ATW-226E migration), and treats a replayed provider_event_id as a distinct duplicate outcome, never an error.';

create function app.disable_third_party_provider_connection(
  p_connection_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.third_party_provider_connections
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
  v_updated app.third_party_provider_connections;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_conn.status = 'disabled' then
    return v_conn;
  end if;

  update app.third_party_provider_connections
  set status = 'disabled', auto_disabled_at = now(), disabled_reason = coalesce(p_reason, 'manual disable')
  where id = p_connection_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'disable_third_party_provider_connection',
    'app.third_party_provider_connections', v_updated.id, 'success', p_reason,
    jsonb_build_object('status', v_conn.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.disable_third_party_provider_connection is
  'ATW-226I: manual counterpart to the automated auto-disable path (design note 1) -- lets an operator proactively disable a connection they already know is compromised or misconfigured, without waiting for 10 consecutive signature failures. Idempotent-safe (already-disabled returns unchanged).';

create function app.reenable_third_party_provider_connection(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.third_party_provider_connections
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
  v_updated app.third_party_provider_connections;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.third_party_provider_connections
  set status = 'active', consecutive_failure_count = 0, auto_disabled_at = null, disabled_reason = null
  where id = p_connection_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'reenable_third_party_provider_connection',
    'app.third_party_provider_connections', v_updated.id, 'success', null,
    jsonb_build_object('status', v_conn.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.reenable_third_party_provider_connection is
  'ATW-226I: manual re-enable after an auto-disable or manual disable -- resets the failure counter, since the operator is asserting the connection (or its secret, out-of-band) is now believed healthy.';

revoke execute on all functions in schema app from public;

grant execute on function app.disable_third_party_provider_connection(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.reenable_third_party_provider_connection(uuid, uuid, text) to authenticated, service_role;

-- Re-grants exactly as ATW-226E's own original migration did -- CREATE OR REPLACE does
-- preserve a prior grant automatically (unlike DROP+CREATE), so this is restated only
-- for self-contained per-migration auditability (226F/226G/226H's own convention), not
-- structurally required here.
grant execute on function app.ingest_third_party_provider_webhook_event(uuid, text, text, bigint, text) to anon, authenticated, service_role;
