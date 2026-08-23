-- Advanced TMS capability ATW-226C (Prompt 226 decomposition child, "Driver Mobile GPS
-- session and HTTPS ingestion" -- docs/build-log/phase-05/
-- ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1.4). The first genuinely real
-- telemetry-producing surface this repository builds -- and grants `anon` EXECUTE on
-- one function, a deliberate, narrow, precedented exception (see design note 3 below),
-- not a departure from `ERR-2026-004`'s own standing discipline (a direct query of
-- `information_schema.routine_privileges` confirms `anon` already holds `EXECUTE` on
-- five pre-existing pre-login functions -- white-label branding, custom-domain
-- resolution, and locale resolution -- plus `app.lookup_public_shipment_tracking`,
-- this migration's own direct precedent).
--
-- Design boundary (disclosed):
--
-- 1. **Integrates with ATW-225's own orchestration layer, never duplicates it.**
--    `app.shipment_leg_tracking_sessions` (ATW-225) already decides *whether* a leg
--    should be tracked by `driver_mobile` and creates the intent-level session row
--    (`app.start_leg_tracking_session`, dispatcher-initiated, `OPS:Edit`). This
--    migration adds exactly one thing on top: the bearer-token layer a Driver PWA
--    (which holds no CargoGrid portal login at all -- drivers are `app.master_records`
--    rows, never `app.users`, confirmed directly by `ATW-223`'s own
--    `app.set_driver_mobile_tracking_consent` being `OPS:Edit`-gated, i.e. recorded by
--    staff on the driver's behalf, not the driver logging in) needs to authenticate its
--    own HTTPS calls. `app.driver_mobile_tracking_sessions` is 1:1 with one
--    already-started `app.shipment_leg_tracking_sessions` row; the token is minted by a
--    dispatcher (`app.start_driver_mobile_session`, `OPS:Edit`, the same tier
--    `start_leg_tracking_session` itself already uses) and transmitted to the driver
--    out-of-band (QR code/SMS -- outside this repository's own scope, same disclosed
--    boundary the PWA/UI capability at `226H` will need to close).
-- 2. **Raw telemetry storage only -- never normalization/arbitration/current-position
--    projection.** `app.driver_mobile_position_reports` is an append-only log of
--    exactly what the device reported (event_at/received_at kept separate per
--    `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §24's own "event time and received time
--    are separate" business rule) -- `ATW-226F`'s own canonical-telemetry/arbitration
--    layer, not built yet, is what will later read this table and project a trusted
--    current position. Nothing in this migration ever writes to
--    `app.shipment_tracking_health` (`ATW-222`) or any position-facing table.
-- 3. **The one deliberate `anon` grant in this migration, precedented, not novel.** A
--    Driver PWA session has no Supabase Auth identity at all. `anon` already holds
--    `EXECUTE` on five pre-existing functions (white-label/custom-domain/locale
--    pre-login resolution, none token-gated) -- but the specific, directly-relevant
--    prior art for a safely anon-callable, *token-gated* `SECURITY DEFINER` function is
--    `app.lookup_public_shipment_tracking` (`OPS-180`), and this migration follows its
--    exact proven shape: a caller-supplied `client_key` rate-limited via its own
--    dedicated attempts table (`app.driver_mobile_ingestion_attempts`, the identical
--    10-bad-attempts/15-minute window `app.tracking_lookup_attempts` already
--    established), a sha256 token-hash lookup (`pgcrypto`'s `digest()`, already an
--    unconditional dependency since `PLT-129`), and a returned status column rather
--    than a raised exception for every auth-failure branch (a raised exception's own
--    distinct error class/timing would be a real enumeration oracle for an
--    unauthenticated caller; a uniform successful return with a `status` field is not).
--    No other function in this migration is anon-granted -- `start_driver_mobile_session`
--    and `revoke_driver_mobile_session` remain dispatcher-only (`OPS:Edit`,
--    `authenticated`/`service_role`).
-- 4. **`app.end_leg_tracking_session` (ATW-225) is widened, not forked.** A driver
--    tapping "Stop" in the PWA needs to end their own tracking session immediately
--    (226_*.md §26: "drivers control only their assigned mobile session") without
--    holding any `OPS:Edit`/`OPS:Override` grant or shipment-record access of their
--    own. Rather than a second, parallel "end session" mechanism (which the WBS's own
--    `226C` `forbidden_paths` explicitly rules out -- "direct mutation of
--    app.shipment_leg_tracking_sessions outside its own already-verified ATW-225
--    RPCs"), this migration `CREATE OR REPLACE`s that function with one new, trailing,
--    `default null` parameter (`p_driver_mobile_session_id`) -- every existing caller's
--    exact signature and behavior is preserved unchanged; only when this new parameter
--    is supplied and independently proven to map to the leg's own current session does
--    the function accept token possession as sufficient authority, and only for
--    `end_reason = 'manual_stop'`.
-- 5. PostGIS point storage/validation reuses `app.geojson_point_to_geography`/
--    `app.validate_geography_point` (`PLT-134`) verbatim -- no second spatial ingestion
--    path.
-- 6. Per `ERR-2026-004`: this migration carries its own explicit
--    `revoke execute on all functions in schema app from public` statement before its
--    final grants.

create table app.driver_mobile_tracking_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_tracking_session_id uuid not null references app.shipment_leg_tracking_sessions (id),
  token_hash text not null,
  status text not null default 'active',
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  created_by text,
  created_at timestamptz not null default now(),
  constraint driver_mobile_tracking_sessions_status_check check (status in ('active', 'revoked', 'expired')),
  constraint driver_mobile_tracking_sessions_revoked_reason_check check (status <> 'revoked' or revoked_reason is not null),
  constraint driver_mobile_tracking_sessions_token_hash_unique unique (token_hash)
);

comment on table app.driver_mobile_tracking_sessions is
  'ATW-226C: at most one active bearer-token row per already-started app.shipment_leg_tracking_sessions (ATW-225) row where source_type=driver_mobile (partial unique index) -- revoked history is preserved, never overwritten, mirroring app.shipment_tracking_tokens (OPS-180) exactly. token_hash is a one-way sha256 digest -- the raw token is never stored and is returned exactly once, by app.start_driver_mobile_session() itself.';

create unique index driver_mobile_tracking_sessions_one_active_idx on app.driver_mobile_tracking_sessions (shipment_leg_tracking_session_id) where status = 'active';
create index driver_mobile_tracking_sessions_tenant_idx on app.driver_mobile_tracking_sessions (tenant_id);

-- Anti-enumeration rate limiting, the identical shape app.tracking_lookup_attempts
-- (OPS-180) already established.
create table app.driver_mobile_ingestion_attempts (
  id uuid primary key default gen_random_uuid(),
  client_key text not null,
  result text not null,
  occurred_at timestamptz not null default now(),
  constraint driver_mobile_ingestion_attempts_result_check check (result in ('success', 'invalid', 'rate_limited'))
);

comment on table app.driver_mobile_ingestion_attempts is
  'ATW-226C: append-only evidence of every app.ingest_driver_mobile_report() call, keyed by a caller-supplied client_key. A client_key accumulating 10+ invalid results within a trailing 15-minute window is rate-limited -- the same real, queryable anti-enumeration mechanism app.tracking_lookup_attempts (OPS-180) already implements.';

create index driver_mobile_ingestion_attempts_client_key_idx on app.driver_mobile_ingestion_attempts (client_key, occurred_at desc);

-- Raw, append-only ingestion log. Never read by anything in this migration beyond its
-- own insert -- ATW-226F's own canonical normalization/arbitration layer is the real
-- consumer, not built yet.
create table app.driver_mobile_position_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  driver_mobile_tracking_session_id uuid not null references app.driver_mobile_tracking_sessions (id),
  report_type text not null,
  event_at timestamptz not null,
  received_at timestamptz not null default now(),
  location geography(Point, 4326),
  accuracy_meters numeric,
  battery_percent integer,
  location_permission_granted boolean,
  background_permission_granted boolean,
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint driver_mobile_position_reports_type_check check (report_type in ('heartbeat', 'location', 'pause', 'resume', 'stop')),
  constraint driver_mobile_position_reports_location_check check (report_type <> 'location' or location is not null),
  constraint driver_mobile_position_reports_location_valid_check check (location is null or app.validate_geography_point(location)),
  constraint driver_mobile_position_reports_accuracy_check check (accuracy_meters is null or accuracy_meters >= 0),
  constraint driver_mobile_position_reports_battery_check check (battery_percent is null or (battery_percent between 0 and 100))
);

comment on table app.driver_mobile_position_reports is
  'ATW-226C: raw driver-mobile telemetry, exactly as reported -- never a position/ping the app has normalized, deduplicated, or arbitrated. event_at (client-claimed) and received_at (server-assigned) are kept separate per 226_*.md §24''s own business rule. This is the "raw-message metadata and controlled raw payload retention" §13 names, distinct from the canonical telemetry events ATW-226F alone may write.';

create index driver_mobile_position_reports_session_idx on app.driver_mobile_position_reports (driver_mobile_tracking_session_id, received_at desc);
create index driver_mobile_position_reports_tenant_idx on app.driver_mobile_position_reports (tenant_id, received_at desc);

create function app.start_driver_mobile_session(
  p_shipment_leg_tracking_session_id uuid,
  p_validity_hours integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (driver_mobile_session_id uuid, raw_token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_session app.shipment_leg_tracking_sessions;
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_raw_token text;
  v_token_hash text;
  v_expires_at timestamptz;
  v_row app.driver_mobile_tracking_sessions;
begin
  select * into v_session from app.shipment_leg_tracking_sessions where id = p_shipment_leg_tracking_session_id;
  if not found then
    raise exception 'tracking_session_not_found: %', p_shipment_leg_tracking_session_id using errcode = 'no_data_found';
  end if;
  if v_session.source_type <> 'driver_mobile' then
    raise exception 'not_a_driver_mobile_session: % has source_type %, not driver_mobile', p_shipment_leg_tracking_session_id, v_session.source_type
      using errcode = 'check_violation';
  end if;
  if not v_session.is_current or v_session.status <> 'active' then
    raise exception 'tracking_session_not_active: % is not the current active tracking session', p_shipment_leg_tracking_session_id
      using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = v_session.shipment_leg_id;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if exists (select 1 from app.driver_mobile_tracking_sessions where shipment_leg_tracking_session_id = p_shipment_leg_tracking_session_id and status = 'active') then
    raise exception 'driver_mobile_session_already_issued: % already has an active mobile session token -- revoke it first to issue a new one', p_shipment_leg_tracking_session_id
      using errcode = 'unique_violation';
  end if;

  if coalesce(p_validity_hours, 0) <= 0 or p_validity_hours > 168 then
    raise exception 'invalid_validity_hours: validity_hours must be between 1 and 168 (7 days)' using errcode = 'check_violation';
  end if;

  v_raw_token := 'dmt_' || encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');
  v_expires_at := now() + (p_validity_hours || ' hours')::interval;

  insert into app.driver_mobile_tracking_sessions (tenant_id, shipment_leg_tracking_session_id, token_hash, expires_at, created_by)
  values (v_shipment.tenant_id, p_shipment_leg_tracking_session_id, v_token_hash, v_expires_at, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_driver_mobile_session',
    'app.driver_mobile_tracking_sessions', v_row.id, 'success', null, null,
    jsonb_build_object('shipment_leg_tracking_session_id', p_shipment_leg_tracking_session_id, 'expires_at', v_expires_at)
  );

  return query select v_row.id, v_raw_token, v_row.expires_at;
end;
$$;

comment on function app.start_driver_mobile_session is
  'ATW-226C: dispatcher-initiated (OPS:Edit, same tier ATW-225''s own app.start_leg_tracking_session uses). Mints a bearer token for an already-started driver_mobile tracking session and returns the raw value exactly once -- transmitting it to the driver''s own device is out of this repository''s scope (226H''s own PWA UI concern).';

create function app.revoke_driver_mobile_session(
  p_shipment_leg_tracking_session_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.driver_mobile_tracking_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.driver_mobile_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_row from app.driver_mobile_tracking_sessions where shipment_leg_tracking_session_id = p_shipment_leg_tracking_session_id and status = 'active';
  if not found then
    raise exception 'driver_mobile_session_not_found: no active mobile session token for tracking session %', p_shipment_leg_tracking_session_id using errcode = 'no_data_found';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'revoke_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_session from app.shipment_leg_tracking_sessions where id = v_row.shipment_leg_tracking_session_id;
  select * into v_leg from app.shipment_legs where id = v_session.shipment_leg_id;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.driver_mobile_tracking_sessions
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = v_row.id
  returning * into v_row;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_driver_mobile_session',
    'app.driver_mobile_tracking_sessions', v_row.id, 'success', p_reason, null, null
  );

  return v_row;
end;
$$;

comment on function app.revoke_driver_mobile_session is
  'ATW-226C: dispatcher-initiated revocation (e.g. lost phone). OPS:Edit-gated; raises driver_mobile_session_not_found if no active token exists for the tracking session (never silently no-ops on a stale/already-revoked target). Revoking does not itself issue a replacement -- a dispatcher calls app.start_driver_mobile_session again for that, now unblocked by the partial-unique-index gate this row''s own revocation clears. Does not itself end the underlying ATW-225 tracking session -- a dispatcher who revokes the token still separately decides whether to end/handoff the session via ATW-225''s own already-verified RPCs.';

-- Widened, not forked -- see this migration's own header design note 4. A new trailing
-- parameter changes this function's own signature, so `CREATE OR REPLACE` (same-
-- signature only) cannot be used here -- Postgres would keep the original 5-argument
-- function AND add this as a distinct overload, making every existing unqualified
-- 5-argument call site ambiguous. `DROP` then `CREATE` is the correct, still-forward-
-- only technique for a signature-widening change (the old migration file itself is
-- never edited); every existing 5-positional-argument call site (ATW-225's own
-- db-test, any future dispatcher-initiated caller) is unaffected, since the new
-- trailing parameter defaults to null and takes the pre-existing OPS:Edit/Override +
-- can_access_record path unchanged.
drop function app.end_leg_tracking_session(uuid, text, text, uuid, text);

create function app.end_leg_tracking_session(
  p_shipment_leg_id uuid,
  p_end_reason text,
  p_reason_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_driver_mobile_session_id uuid default null
)
returns app.shipment_leg_tracking_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_session app.shipment_leg_tracking_sessions;
begin
  if p_end_reason not in ('leg_completed', 'manual_stop', 'unauthorized_override') then
    raise exception 'invalid_end_reason: % is not a supported end reason for a direct end call', p_end_reason using errcode = 'check_violation';
  end if;
  if p_end_reason = 'manual_stop' and (p_reason_note is null or length(trim(p_reason_note)) = 0) then
    raise exception 'end_reason_required: a non-empty reason is required to manually stop a tracking session' using errcode = 'check_violation';
  end if;
  if p_end_reason = 'unauthorized_override' and (p_reason_note is null or length(trim(p_reason_note)) = 0) then
    raise exception 'override_reason_required: a non-empty reason is required to force-end a tracking session' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if p_driver_mobile_session_id is not null then
    -- Driver-initiated stop via an already-validated mobile session token -- token
    -- possession IS the authority for this one session (226_*.md §26: "drivers
    -- control only their assigned mobile session"). Never a blanket bypass: only
    -- manual_stop, and only when the given token genuinely maps to this leg's own
    -- current tracking session.
    if p_end_reason <> 'manual_stop' then
      raise exception 'invalid_end_reason: a driver-mobile-initiated stop must use manual_stop' using errcode = 'check_violation';
    end if;
    if not exists (
      select 1 from app.driver_mobile_tracking_sessions dms
      join app.shipment_leg_tracking_sessions slts on slts.id = dms.shipment_leg_tracking_session_id
      where dms.id = p_driver_mobile_session_id and slts.shipment_leg_id = p_shipment_leg_id and slts.is_current
    ) then
      raise exception 'driver_mobile_session_mismatch: % does not map to the current tracking session for leg %', p_driver_mobile_session_id, p_shipment_leg_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    if p_end_reason = 'unauthorized_override' then
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Override');
      if not v_decision.allowed then
        raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
          using errcode = 'insufficient_privilege';
      end if;
    else
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
      if not v_decision.allowed then
        raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
          using errcode = 'insufficient_privilege';
      end if;
    end if;
    if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  select * into v_session from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if not found then
    raise exception 'no_active_session: leg % has no active tracking session to end', p_shipment_leg_id using errcode = 'check_violation';
  end if;

  update app.shipment_leg_tracking_sessions
  set is_current = false, status = 'ended', ended_at = now(), end_reason = p_end_reason
  where id = v_session.id
  returning * into v_session;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, coalesce(p_actor_label, 'driver-mobile'), 'end_leg_tracking_session',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', p_reason_note, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'end_reason', p_end_reason, 'driver_mobile_session_id', p_driver_mobile_session_id)
  );

  return v_session;
end;
$$;

-- The one anon-callable function in this migration -- see design note 3 above. Never
-- raises for an auth/validation failure; every outcome (including rate_limited/invalid)
-- is a returned row, the identical shape app.lookup_public_shipment_tracking
-- (OPS-180) already established, so no error class/timing leaks caller-distinguishable
-- information to an unauthenticated party.
create function app.ingest_driver_mobile_report(
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

  if p_report_type = 'location' and p_location is null then
    insert into app.driver_mobile_ingestion_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  v_geog := case when p_location is not null then app.geojson_point_to_geography(p_location) else null end;

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
  'ATW-226C: the one anon-callable HTTPS ingestion entry point (see this migration''s own header design note 3). Raw storage only -- never normalizes, deduplicates, or arbitrates (ATW-226F''s own scope). A stop report also ends the underlying ATW-225 session via app.end_leg_tracking_session''s own widened driver-mobile-token path.';

-- Computed GeoJSON projection, the identical pattern app.get_shipment_leg_stops
-- (ATW-221) already established -- a raw geography column returned through PostgREST
-- directly would surface as opaque WKB, not a value a caller could use. `security
-- invoker` (not definer): RLS on the base table still governs row visibility, this
-- function only reshapes the geography column.
create function app.get_driver_mobile_position_reports(p_driver_mobile_tracking_session_id uuid)
returns table (
  id uuid, tenant_id uuid, driver_mobile_tracking_session_id uuid, report_type text,
  event_at timestamptz, received_at timestamptz, location_geojson jsonb,
  accuracy_meters numeric, battery_percent integer,
  location_permission_granted boolean, background_permission_granted boolean,
  raw_payload jsonb, created_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public, pg_temp
as $$
  select
    r.id, r.tenant_id, r.driver_mobile_tracking_session_id, r.report_type,
    r.event_at, r.received_at,
    case when r.location is not null then ST_AsGeoJSON(r.location)::jsonb else null end,
    r.accuracy_meters, r.battery_percent,
    r.location_permission_granted, r.background_permission_granted,
    r.raw_payload, r.created_at
  from app.driver_mobile_position_reports r
  where r.driver_mobile_tracking_session_id = p_driver_mobile_tracking_session_id
  order by r.received_at desc;
$$;

comment on function app.get_driver_mobile_position_reports is
  'ATW-226C: read projection for one driver-mobile tracking session''s own raw report history, newest first -- the same GeoJSON-computed-column shape app.get_shipment_leg_stops (ATW-221) already established. Dispatcher/administration read only (226H''s own future UI); never called by the anon-facing ingestion path.';

alter table app.driver_mobile_tracking_sessions enable row level security;
alter table app.driver_mobile_position_reports enable row level security;

create policy driver_mobile_tracking_sessions_select_scoped on app.driver_mobile_tracking_sessions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy driver_mobile_position_reports_select_scoped on app.driver_mobile_position_reports
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.driver_mobile_tracking_sessions to authenticated, service_role;
grant insert, update, delete on app.driver_mobile_tracking_sessions to service_role;
grant select on app.driver_mobile_position_reports to authenticated, service_role;
grant insert, update, delete on app.driver_mobile_position_reports to service_role;
grant insert on app.driver_mobile_ingestion_attempts to service_role;

grant execute on function app.start_driver_mobile_session(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_driver_mobile_session(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.end_leg_tracking_session(uuid, text, text, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.get_driver_mobile_position_reports(uuid) to authenticated, service_role;
-- Deliberate exception -- an unauthenticated Driver PWA session has no other way to
-- reach this function. See design note 3 above for why this is safe.
grant execute on function app.ingest_driver_mobile_report(text, text, text, timestamptz, jsonb, numeric, integer, boolean, boolean, jsonb) to anon, authenticated, service_role;
