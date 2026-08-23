-- CG-S10-ATW-027 (Prompt 246, "Advanced TMS/WMS Integrity and Security Hardening").
-- Repairs 4 of the 7 confirmed findings a dedicated adversarial-probe agent live-
-- reproduced against the Direct Device (GPS Gateway) and Driver Mobile source classes.
-- The remaining 3 findings (durable-buffer poison-pill, TCP socket exhaustion, log
-- redaction bypass) are TypeScript-only repairs in `services/gps-gateway/` -- see that
-- package's own updated `src/buffer.ts`/`src/server.ts`/`src/logger.ts` and their tests.
-- A sibling agent is concurrently repairing a disjoint finding set in the Third-Party
-- GPS + Hybrid arbitration source classes in this same working tree -- this migration
-- never touches `app.arbitrate_and_project_vehicle_position`,
-- `app.ingest_third_party_provider_webhook_event`, or `app.third_party_provider_
-- connections` grants (see design note 2 below for the one place that boundary left a
-- real, disclosed gap unrepaired here).
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.
--
-- ===========================================================================
-- Design notes
-- ===========================================================================
--
-- 1. **Finding 1 (HIGH) -- cross-tenant IMEI collision -> permanent DoS against a victim
--    tenant's real device.** `app.gps_devices` uniqueness is `(tenant_id, imei)` only
--    (`ATW-223`); `app.register_gps_device` required only ordinary in-tenant `OPS:Create`,
--    no cross-tenant check. `app.resolve_gps_device_for_handshake` (`ATW-226D`) looks up
--    IMEI globally and unconditionally refuses (`imei_ambiguous_across_tenants`) once >1
--    row matches. Live-reproduced: any tenant could self-register another tenant's real,
--    active device's IMEI, permanently breaking that victim device's every future
--    handshake, with no admin remediation path anywhere in the schema. Repaired three ways:
--    (a) `app.register_gps_device` is widened (same signature, `CREATE OR REPLACE`) to
--    reject -- `imei_registered_to_another_tenant` -- a registration attempt for an IMEI
--    a DIFFERENT tenant already holds, serialized against a genuinely concurrent
--    cross-tenant race via a per-IMEI `pg_advisory_xact_lock` (this repository's own
--    established idiom, e.g. `20260730320000_..._tracking_health_writer.sql`), taken
--    only after the existing same-tenant-idempotent and authority checks (so an
--    unauthorized or same-tenant-idempotent caller never pays the lock's cost). This
--    check is deliberately NOT status-filtered -- a real hardware IMEI stays permanently
--    claimed by whichever tenant first registered it, retired or not, until an authorized
--    `app.deregister_gps_device` call explicitly clears that specific row; otherwise a
--    third tenant could claim a real, historically-owned-by-someone-else piece of
--    hardware the moment its owner retires it, the identical identity-confusion class
--    this whole finding exists to close. (b) A new, narrow, `OPS:Override`-gated
--    remediation RPC, `app.deregister_gps_device`, lets an authorized actor clear a
--    spurious or erroneously-registered row (status-transition/soft-delete to the
--    already-existing terminal `'retired'` status `app.transition_gps_device_status`
--    itself established, `ATW-223` -- no new status value, no new capability-shaped
--    column). Evaluated against the DEVICE'S OWN tenant via the existing
--    `app.evaluate_permission`'s already-established `supreme_admin` exception (`RPD-022`)
--    -- a tenant's own `OPS:Override` holder may self-service-deregister their own device
--    (the "legitimately-retired" case), but clearing a DIFFERENT tenant's spurious row (the
--    actual cross-tenant remediation this finding targets) always requires a real
--    `supreme_admin`, since ordinary tenant-scoped role assignment structurally cannot
--    span a tenant boundary -- the identical reasoning this repository already applies to
--    every genuinely cross-tenant administrative action, requiring no new RBAC plumbing.
--    (c) `app.resolve_gps_device_for_handshake`'s own ambiguity count/lookup is widened to
--    exclude `status = 'retired'` rows -- without this, `app.deregister_gps_device` would
--    retire the spurious row but the victim's own handshake would still see it and stay
--    ambiguous forever, making the remediation RPC a no-op in practice. Both the count and
--    the follow-up row lookup apply the identical filter, so `v_match_count = 1` always
--    corresponds to exactly the one row the lookup actually fetches -- never a
--    non-deterministic pick among multiple physical rows sharing one IMEI.
--
-- 2. **Finding 2 (HIGH) -- concurrent-connection impersonation; rejected reports poisoning
--    the impossible-movement baseline.** Two concurrent raw TCP connections presenting the
--    identical real, active IMEI both completed a full handshake -- no exclusivity check
--    existed. Repaired (bounded, per this finding's own framing): `services/gps-gateway/
--    src/server.ts` now tracks in-flight IMEI -> connection state in-process and rejects a
--    second concurrent handshake for an IMEI that already has an open connection --
--    chosen over a Postgres advisory lock because this gateway's own architecture makes a
--    session-scoped lock unreliable (`src/ingestClient.ts` issues one stateless PostgREST
--    RPC call per handshake/batch, each potentially served by a different pooled
--    connection from Supabase's own connection pooler -- a `pg_advisory_lock` acquired in
--    one RPC call is not dependably still held by the time a later RPC call on the same
--    logical TCP connection runs), and because the gateway is architected as a single
--    always-on process (`220_*.md` §6), so in-process state is a complete, sufficient
--    fix for the addressable half of this finding. See `services/gps-gateway/src/
--    server.ts`'s own updated header and `test/server.test.ts` for the regression proof.
--
--    The DISCLOSED, NOT-fully-fixed residual half of this finding (RPD-022-style accepted-
--    risk record, kept here rather than as a new `docs/runtime/KNOWN_ISSUES.md` row to
--    avoid a concurrent-edit collision with the sibling agent working the same checkpoint
--    in that same shared ledger file):
--      Accepted condition: IMEIs are not secret (printed on the device/box, often
--      externally queryable), so IMEI-presentation-in-the-clear is not, and must never be
--      represented as, device-identity proof. A patient attacker who waits for the real
--      device's own connection to genuinely end (rather than racing a still-open one) is
--      unaffected by the concurrency check above and can still pass a fresh handshake with
--      a known victim IMEI; if that spoofed traffic also respects the existing 200 km/h
--      impossible-movement ceiling, it can still inject plausible false telemetry. Fixing
--      this fully would require a real device-level PKI/certificate provisioning scheme --
--      out of reach without physical Teltonika hardware to design or validate against
--      (`226_*.md`'s own external-evidence policy) and far beyond this task's own bounded
--      "hardening, not new capability" scope.
--      Separately: the probe also flagged that a rejected/disabled-arbitration candidate
--      still moves `app.vehicle_source_health.last_location` (an unconditional upsert
--      inside `app.arbitrate_and_project_vehicle_position`), poisoning the baseline the
--      NEXT impossible-movement comparison uses. That defect lives entirely inside
--      `app.arbitrate_and_project_vehicle_position`'s own body -- explicitly out of this
--      migration's assigned file boundary this checkpoint (owned by the concurrently-
--      running sibling remediation covering the Third-Party/Hybrid-arbitration source
--      classes, whose own remit already names "silent history overwrite" as an in-scope
--      Hybrid adversarial category). Left for that work, not silently dropped or worked
--      around by duplicating arbitration logic here.
--      Required permanent handling: never represent the direct-device raw-TCP channel as
--      providing device-identity authentication beyond bare IMEI presentation, in any
--      future Direct Device security/customer-facing material.
--
-- 3. **Finding 4 (HIGH) -- revoked driver mobile-tracking consent never honored
--    mid-session.** `app.driver_operational_profiles.mobile_tracking_consent` was checked
--    only once, at `app.start_leg_tracking_session` (via `app.check_leg_tracking_source_
--    eligible`). `app.ingest_driver_mobile_report` never re-checked it -- revoking consent
--    mid-session via `app.set_driver_mobile_tracking_consent` did not stop a subsequent
--    ingestion call from succeeding and persisting the driver's location. Repaired: same-
--    signature widening (`CREATE OR REPLACE`, combined with finding 5's edit to the same
--    function) adds a live re-check of the session's own driver's CURRENT `status`/
--    `mobile_tracking_consent`, mirroring both the exact eligibility predicate `app.
--    check_leg_tracking_source_eligible` already uses for `driver_mobile` AND this same
--    function's own existing live re-check pattern for the tracking session's `is_current`/
--    `status` a few lines above. `app.shipment_leg_tracking_sessions.resource_master_id`
--    is always the session's own driver's `app.master_records.id` for a `source_type =
--    'driver_mobile'` session (that table's own `kind_source_match_check` constraint,
--    `ATW-225`) -- no extra join through `app.resource_assignments` is needed. Returns the
--    same clean `'invalid'` result (never a raise) every other validation branch in this
--    anon-facing function already returns.
--
-- 4. **Finding 5 (MEDIUM) -- out-of-range coordinates raise, violating this function's own
--    "never raises" contract and rolling back rate-limit bookkeeping.** `app.geojson_
--    point_to_geography` raises (`spatial_coordinate_out_of_range`/`spatial_invalid_
--    geojson_type`/`spatial_invalid_coordinate_count`) for a malformed/out-of-bounds
--    point, uncaught inside `app.ingest_driver_mobile_report` -- the exception unwound the
--    whole function, so the rate-limit bookkeeping insert (`app.driver_mobile_ingestion_
--    attempts`) never ran: 50 out-of-range requests produced 50 exceptions and zero
--    rate-limit rows, a real gap versus this function's own correctly-working token-based
--    rate limiter as a control. Repaired: the geography-conversion call is now wrapped in
--    its own `begin ... exception when others ... end` block, converting ANY exception
--    from that call (not just the out-of-range case) into the same clean `'invalid'`
--    result every other branch already returns, with the rate-limit bookkeeping row still
--    recorded before returning.

-- ===========================================================================
-- Finding 1a -- app.register_gps_device: reject a cross-tenant IMEI collision.
-- Same signature as the original (`ATW-223`) -- CREATE OR REPLACE, not DROP+CREATE.
-- ===========================================================================
create or replace function app.register_gps_device(
  p_tenant_id uuid,
  p_imei text,
  p_device_model text,
  p_ownership_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.gps_devices
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.gps_devices;
  v_device app.gps_devices;
  v_foreign_count integer;
begin
  if p_imei is null or length(trim(p_imei)) = 0 then
    raise exception 'imei_required: a non-empty IMEI is required' using errcode = 'check_violation';
  end if;
  if p_ownership_type not in ('cargogrid', 'customer', 'partner') then
    raise exception 'invalid_ownership_type: % is not a supported device ownership type', p_ownership_type using errcode = 'check_violation';
  end if;

  select * into v_existing from app.gps_devices where tenant_id = p_tenant_id and imei = p_imei;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ATW-246 finding 1(a): serializes every concurrent registration attempt for this
  -- EXACT imei value (across any tenant) for the remainder of this transaction, closing
  -- the narrow TOCTOU window the check-then-insert below would otherwise leave between
  -- two simultaneous cross-tenant registration calls for the same real hardware IMEI --
  -- mirrors this repository's own established per-key pg_advisory_xact_lock idiom (e.g.
  -- `20260730320000_create_advanced_tms_shipment_tracking_health_writer.sql`).
  perform pg_advisory_xact_lock(hashtextextended('app.gps_devices.imei:' || p_imei, 0));

  -- A real physical GPS device's IMEI is a globally-unique hardware identifier -- refuse
  -- (never silently accept) a registration attempt for an IMEI a DIFFERENT tenant has
  -- already claimed, closing the live-reproduced cross-tenant denial-of-service this
  -- finding describes. Deliberately NOT status-filtered (see this migration's own header
  -- design note 1) -- unlike app.resolve_gps_device_for_handshake's own ambiguity check
  -- (widened below), a real hardware identifier stays permanently claimed by whichever
  -- tenant first registered it, retired or not, until an authorized app.deregister_gps_
  -- device call explicitly clears that specific row.
  select count(*) into v_foreign_count from app.gps_devices where imei = p_imei and tenant_id <> p_tenant_id;
  if v_foreign_count > 0 then
    raise exception 'imei_registered_to_another_tenant: IMEI % is already registered to a different tenant', p_imei
      using errcode = 'unique_violation';
  end if;

  begin
    insert into app.gps_devices (tenant_id, imei, device_model, ownership_type, created_by)
    values (p_tenant_id, p_imei, p_device_model, p_ownership_type, p_actor_label)
    returning * into v_device;
  exception
    when unique_violation then
      select * into v_device from app.gps_devices where tenant_id = p_tenant_id and imei = p_imei;
      return v_device;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_gps_device',
    'app.gps_devices', v_device.id, 'success', null, null, jsonb_build_object('device_model', p_device_model, 'ownership_type', p_ownership_type)
  );

  return v_device;
end;
$$;

comment on function app.register_gps_device is
  'ATW-223, hardened at ATW-246 finding 1(a): idempotent on (tenant_id, imei) exactly as before, but now REJECTS (imei_registered_to_another_tenant) a registration attempt for an IMEI a different tenant already holds -- a real hardware IMEI is globally unique and permanently claimed by whichever tenant registered it first, until an authorized app.deregister_gps_device call clears that specific row. Serialized per-IMEI via pg_advisory_xact_lock against a genuine concurrent cross-tenant race.';

-- ===========================================================================
-- Finding 1b -- app.deregister_gps_device: new, narrow, OPS:Override-gated remediation
-- RPC. Status-transition/soft-delete style (-> the already-existing terminal 'retired'
-- status), matching app.transition_gps_device_status's own established convention -- not
-- a new capability, not a new status value, not a raw DB delete.
-- ===========================================================================
create function app.deregister_gps_device(
  p_device_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.gps_devices
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_device app.gps_devices;
  v_decision app.rbac_decision;
  v_previous_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'deregister_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;

  if v_device.record_version <> p_expected_version then
    raise exception 'stale_version: device % expected version % but found %', p_device_id, p_expected_version, v_device.record_version
      using errcode = 'serialization_failure';
  end if;

  -- OPS:Override, evaluated against the DEVICE'S OWN tenant (mirrors app.evaluate_
  -- permission's already-established supreme_admin exception, RPD-022 -- see this
  -- migration's own header design note 1(b)). A tenant's own OPS:Override holder may
  -- self-service-deregister their OWN device (the "legitimately-retired" case), but
  -- clearing a DIFFERENT tenant's spurious/malicious row (this finding's actual
  -- cross-tenant remediation target) always requires a real supreme_admin, since ordinary
  -- tenant-scoped role assignment structurally cannot span a tenant boundary.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_device.status = 'retired' then
    return v_device;
  end if;

  v_previous_status := v_device.status;

  update app.gps_devices
  set status = 'retired'
  where id = p_device_id and record_version = p_expected_version
  returning * into v_device;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'deregister_gps_device',
    'app.gps_devices', v_device.id, 'success', p_reason, jsonb_build_object('status', v_previous_status), jsonb_build_object('status', 'retired')
  );

  return v_device;
end;
$$;

comment on function app.deregister_gps_device is
  'ATW-246 finding 1(b): the admin remediation path app.gps_devices previously had none of -- clears a spurious/erroneously-registered or legitimately-retired device row (status -> the existing terminal ''retired'', never a raw DB delete) so it stops counting toward app.resolve_gps_device_for_handshake''s own ambiguity check. OPS:Override-gated (stricter than app.register_gps_device''s own OPS:Create), idempotent-safe if already retired. A device retired this way can never transition again (app.transition_gps_device_status has no edge out of ''retired''), so a cleared cross-tenant collision can never be re-created under the offending tenant''s own id.';

-- ===========================================================================
-- Finding 1c -- app.resolve_gps_device_for_handshake: exclude 'retired' rows from the
-- ambiguity count/lookup, so app.deregister_gps_device actually restores a victim's own
-- handshake instead of leaving it permanently ambiguous. Same signature as the original
-- (`ATW-226D`) -- CREATE OR REPLACE.
-- ===========================================================================
create or replace function app.resolve_gps_device_for_handshake(
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

  -- ATW-246 finding 1(c): excludes a 'retired' row from the ambiguity count/lookup --
  -- app.deregister_gps_device is the one supported way to durably clear a spurious or
  -- erroneous registration (status -> 'retired' is a real terminal state; no RPC in this
  -- repository ever moves a device OUT of 'retired'), so a retired row can never again
  -- ambiguate a legitimate device's own handshake. Both queries below apply the identical
  -- filter, so v_match_count = 1 always corresponds to exactly the one row the follow-up
  -- SELECT actually fetches -- never a non-deterministic pick among >1 physical row.
  select count(*) into v_match_count from app.gps_devices where imei = p_imei and status <> 'retired';

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

  select * into v_device from app.gps_devices where imei = p_imei and status <> 'retired';

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
  'ATW-226D, hardened at ATW-246 finding 1(c): called once per TCP connection, immediately after a device presents its IMEI. service_role-only -- never anon. Returns a status row, never raises, for every per-device outcome; only a bad gateway credential itself raises. A ''retired'' row (app.deregister_gps_device) is excluded from the ambiguity count/lookup, so clearing a spurious cross-tenant registration actually restores the victim device''s own handshake.';

-- ===========================================================================
-- Findings 4 & 5 -- app.ingest_driver_mobile_report: live re-check the session's own
-- driver's CURRENT mobile_tracking_consent on every call (finding 4), and catch any
-- exception from the geography-conversion call instead of letting it unwind the whole
-- function and skip rate-limit bookkeeping (finding 5). Same signature as the original
-- (`ATW-226C`, already once widened at `ATW-226F` to add canonicalization) -- CREATE OR
-- REPLACE, body based on the function's own CURRENT (ATW-226F) definition, preserving
-- the app.arbitrate_and_project_vehicle_position call verbatim (that function's own body
-- is untouched by this migration -- see this migration's own header design note 2).
-- ===========================================================================
create or replace function app.ingest_driver_mobile_report(
  p_raw_token text,
  p_client_key text,
  p_report_type text,
  p_event_at timestamptz,
  p_location jsonb,
  p_accuracy_meters numeric,
  p_battery_percent integer,
  p_location_permission_granted boolean,
  p_background_permission_granted boolean,
  p_raw_payload jsonb
)
returns table (ingest_status text, report_id uuid, session_ended boolean)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_hash text;
  v_dms app.driver_mobile_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
  v_report app.driver_mobile_position_reports;
  v_geog geography;
  v_ended boolean := false;
  v_vehicle_master_id uuid;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'tracking_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.driver_mobile_ingestion_attempts
  where client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'rate_limited');
    return query select 'rate_limited'::text, null::uuid, false;
    return;
  end if;

  if p_raw_token is null or length(p_raw_token) = 0 or p_report_type not in ('heartbeat', 'location', 'pause', 'resume', 'stop') or p_event_at is null then
    insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  v_hash := encode(digest(p_raw_token, 'sha256'), 'hex');
  select * into v_dms from app.driver_mobile_tracking_sessions where token_hash = v_hash;
  if not found or v_dms.status <> 'active' or v_dms.expires_at <= now() then
    insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  select * into v_session from app.shipment_leg_tracking_sessions where id = v_dms.shipment_leg_tracking_session_id;
  if not v_session.is_current or v_session.status <> 'active' then
    -- The dispatcher already ended/handed off this session on the ATW-225 side --
    -- real-time consistency: mobile ingestion stops the instant that happens, never a
    -- stale token still silently accepted.
    insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  -- ATW-246 finding 4: live re-check the session's own driver's CURRENT status/
  -- mobile_tracking_consent on every call, mirroring both the is_current/status live
  -- re-check immediately above AND the exact eligibility predicate app.check_leg_
  -- tracking_source_eligible already applies for driver_mobile at session-start time
  -- (ATW-225). mobile_tracking_consent was previously checked only once, at app.start_
  -- leg_tracking_session -- revoking consent mid-session via app.set_driver_mobile_
  -- tracking_consent never stopped a subsequent call here from succeeding and persisting
  -- the driver's location. v_session.resource_master_id is always this session's own
  -- driver's app.master_records.id for a source_type='driver_mobile' session (that
  -- table's own kind_source_match_check constraint) -- no extra join needed.
  if not exists (
    select 1 from app.driver_operational_profiles
    where driver_master_id = v_session.resource_master_id and status = 'active' and mobile_tracking_consent
  ) then
    insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  if p_report_type = 'location' and p_location is null then
    insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  -- ATW-246 finding 5: app.geojson_point_to_geography raises (spatial_coordinate_out_of_
  -- range / spatial_invalid_geojson_type / spatial_invalid_coordinate_count) for a
  -- malformed/out-of-bounds point -- previously uncaught here, unwinding this whole
  -- function and skipping the rate-limit bookkeeping insert below (a real, exploitable
  -- gap: repeated out-of-range coordinates cost the caller nothing toward the
  -- 10-bad-attempts/15-minute limiter, unlike every other invalid input this function
  -- handles). Caught and converted to the same clean 'invalid' result every other
  -- validation branch in this function already returns -- this RPC's own documented
  -- "never raises" contract now holds for every input shape, not just most of them.
  begin
    v_geog := case when p_location is not null then app.geojson_point_to_geography(p_location) else null end;
  exception
    when others then
      insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'invalid');
      return query select 'invalid'::text, null::uuid, false;
      return;
  end;

  insert into app.driver_mobile_position_reports (
    tenant_id, driver_mobile_tracking_session_id, report_type, event_at, location,
    accuracy_meters, battery_percent, location_permission_granted, background_permission_granted, raw_payload
  ) values (
    v_dms.tenant_id, v_dms.id, p_report_type, p_event_at, v_geog,
    p_accuracy_meters, p_battery_percent, p_location_permission_granted, p_background_permission_granted, coalesce(p_raw_payload, '{}'::jsonb)
  )
  returning * into v_report;

  update app.driver_mobile_tracking_sessions set last_seen_at = now() where id = v_dms.id;

  insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'success');

  -- ATW-226F: canonicalize a location/heartbeat report -- never raises, never blocks the
  -- already-committed raw insert above. Preserved verbatim from the current (ATW-226F)
  -- body -- app.arbitrate_and_project_vehicle_position's own definition is untouched by
  -- this migration (see this migration's own header design note 2).
  if p_report_type in ('location', 'heartbeat') then
    v_vehicle_master_id := app.resolve_vehicle_for_driver_mobile_session(v_dms.id);
    if v_vehicle_master_id is not null then
      perform app.arbitrate_and_project_vehicle_position(
        v_dms.tenant_id, v_vehicle_master_id, 'driver_mobile', v_report.id, p_event_at, v_report.received_at,
        v_geog, null::numeric, null::numeric, p_accuracy_meters
      );
    end if;
  end if;

  if p_report_type = 'stop' then
    perform app.end_leg_tracking_session(
      v_session.shipment_leg_id, 'manual_stop', 'driver stopped tracking via mobile app', null, 'driver-mobile', v_dms.id
    );
    v_ended := true;
  end if;

  return query select 'ok'::text, v_report.id, v_ended;
end;
$$;

comment on function app.ingest_driver_mobile_report is
  'ATW-226C, widened at ATW-226F (canonicalization) and hardened at ATW-246 (findings 4/5): raw storage only, PLUS a canonicalization call for a location/heartbeat report. The one anon-callable HTTPS ingestion entry point -- never normalizes/arbitrates itself. Live re-checks the session''s own driver''s CURRENT mobile_tracking_consent on every call (finding 4) and never raises for a malformed/out-of-range coordinate (finding 5) -- every validation outcome is now a clean returned status row, matching this function''s own documented anon-safe contract for every input shape. A stop report also ends the underlying ATW-225 session via app.end_leg_tracking_session''s own widened driver-mobile-token path.';

revoke execute on all functions in schema app from public;

grant execute on function app.register_gps_device(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.deregister_gps_device(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_gps_device_for_handshake(text, text, text) to service_role;

-- Re-grant exactly as app.ingest_driver_mobile_report's own original migration did --
-- CREATE OR REPLACE preserves a prior grant automatically, restated here only for this
-- migration's own self-contained auditability (the identical convention `20260730110000`/
-- `20260730340000` already established), not structurally required.
grant execute on function app.ingest_driver_mobile_report(text, text, text, timestamptz, jsonb, numeric, integer, boolean, boolean, jsonb) to anon, authenticated, service_role;
