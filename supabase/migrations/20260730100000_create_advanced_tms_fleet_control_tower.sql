-- Advanced TMS capability ATW-226H (Prompt 226 decomposition child, "Administration,
-- Fleet Control Tower, device administration, and sanitized projections" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1.4). Backend read
-- surface for the first genuinely UI-heavy child in the `226` family -- every prior
-- child (`226A`-`226G`) shipped zero `app/` pages beyond two webhook routes and one
-- HTTPS ingestion route.
--
-- Design boundary (disclosed):
--
-- 1. **Two new tenant-wide aggregating reads, not N per-vehicle/per-shipment calls.**
--    `app.get_vehicle_current_position` (`226F`), `app.get_shipment_milestone_
--    candidates`/`app.get_shipment_exception_signals` (`226G`) are all scoped to one
--    vehicle/shipment at a time -- exactly right for their own original callers (a
--    widened ingestion RPC, a shipment detail panel), but a Fleet Control Tower list
--    view genuinely needs "every vehicle's own current position for this tenant" and
--    "every pending signal across this tenant's own shipments" in one call each,
--    per `226_*.md` §17's own "do not use... one database request per item" rule.
--    `app.get_tenant_vehicle_tracking_overview`/`app.get_tenant_pending_milestone_
--    candidates`/`app.get_tenant_pending_exception_signals` are the three new reads
--    this checkpoint adds for exactly that purpose -- no new write path.
-- 2. **The public tracking projection is widened (`app.lookup_public_shipment_
--    tracking`, `OPS-180`), not forked** -- a signature-changing widening (three new
--    trailing output columns), so `DROP FUNCTION` + `CREATE FUNCTION` is the correct
--    technique here (`226C`'s own `end_leg_tracking_session` precedent for a
--    signature change, not `226F`/`226G`'s own same-signature `CREATE OR REPLACE`).
--    Every existing output column is unchanged; `scripts/db-tests/operations-public-
--    tracking.sql`'s own assertions (all field-name-based, never positional) re-pass
--    unmodified.
-- 3. **Vehicle position is exposed to a customer only when the shipment's own
--    currently-executing leg's tracking policy explicitly marks `customer_visible =
--    true`** (`app.shipment_leg_tracking_policies.customer_visible`, `ATW-225`,
--    already real) -- reused, not reinvented. No tracking policy, no currently-
--    executing leg, or `customer_visible = false` all cleanly yield null position
--    fields, never a raised error and never a silent default-to-visible.
-- 4. **A coarse three-word status (`live`/`delayed`/`unavailable`), never the raw
--    `driver_mobile`/`direct_device`/`third_party_platform` source type** -- a
--    customer-safe projection of `226_*.md` §16's own "customers see sanitized
--    shipment-level projections... raw payload and driver-sensitive data are
--    restricted," reusing the tenant's own `freshness_threshold_seconds`
--    (`app.resolve_tenant_tracking_source_policy`, `226A`) for the live/delayed
--    banding, the identical multiplier `app.get_vehicle_source_health` (`226F`)
--    already established (1x/3x the threshold) for its own healthy/stale/offline
--    bands, just relabeled for a customer-facing audience.
-- 5. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--    ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

create function app.get_tenant_vehicle_tracking_overview(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  vehicle_master_id uuid,
  vehicle_code text,
  vehicle_name text,
  mobile_tracking_eligible boolean,
  direct_device_tracking_eligible boolean,
  third_party_tracking_eligible boolean,
  current_source_type text,
  current_location_geojson jsonb,
  current_speed_kmh numeric,
  current_heading_degrees numeric,
  current_event_at timestamptz,
  current_received_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    vop.vehicle_master_id, mr.code, mr.name,
    vop.mobile_tracking_eligible, vop.direct_device_tracking_eligible, vop.third_party_tracking_eligible,
    vcp.source_type,
    case when vcp.location is not null then ST_AsGeoJSON(vcp.location)::jsonb else null end,
    vcp.speed_kmh, vcp.heading_degrees, vcp.event_at, vcp.received_at
  from app.vehicle_operational_profiles vop
  join app.master_records mr on mr.id = vop.vehicle_master_id
  left join app.vehicle_current_positions vcp on vcp.vehicle_master_id = vop.vehicle_master_id
  where vop.tenant_id = p_tenant_id and vop.status = 'active'
  order by mr.code;
end;
$$;

comment on function app.get_tenant_vehicle_tracking_overview is
  'ATW-226H: one row per active vehicle for a tenant, left-joined against its own current position (226F) -- a vehicle never yet tracked simply carries null position fields, not a missing row. The single aggregating read the Fleet Control Tower list/map view needs, avoiding one app.get_vehicle_current_position call per vehicle.';

create function app.get_tenant_pending_milestone_candidates(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns table (
  id uuid, shipment_order_id uuid, shipment_number text, shipment_leg_id uuid, shipment_leg_stop_id uuid,
  milestone_code text, candidate_event_time timestamptz, detected_at timestamptz, location_geojson jsonb
)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    c.id, c.shipment_order_id, so.shipment_number, c.shipment_leg_id, c.shipment_leg_stop_id,
    c.milestone_code, c.candidate_event_time, c.detected_at,
    case when c.location is not null then ST_AsGeoJSON(c.location)::jsonb else null end
  from app.shipment_milestone_candidates c
  join app.shipment_orders so on so.id = c.shipment_order_id
  where c.tenant_id = p_tenant_id and c.status = 'pending'
  order by c.detected_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.get_tenant_pending_milestone_candidates is
  'ATW-226H: the tenant-wide pending-review queue app.get_shipment_milestone_candidates (226G) cannot provide on its own, since that read is scoped to one shipment order at a time. Hard-capped at 200 rows regardless of p_limit.';

create function app.get_tenant_pending_exception_signals(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns table (
  id uuid, shipment_order_id uuid, shipment_number text, shipment_leg_id uuid,
  signal_type text, exception_type text, severity text, detected_at timestamptz, description text, location_geojson jsonb
)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    s.id, s.shipment_order_id, so.shipment_number, s.shipment_leg_id,
    s.signal_type, s.exception_type, s.severity, s.detected_at, s.description,
    case when s.location is not null then ST_AsGeoJSON(s.location)::jsonb else null end
  from app.shipment_exception_signals s
  join app.shipment_orders so on so.id = s.shipment_order_id
  where s.tenant_id = p_tenant_id and s.status = 'pending'
  order by s.detected_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.get_tenant_pending_exception_signals is
  'ATW-226H: the tenant-wide pending-review queue app.get_shipment_exception_signals (226G) cannot provide on its own. Hard-capped at 200 rows regardless of p_limit.';

-- ============================================================================
-- Widen app.lookup_public_shipment_tracking (OPS-180, design note 2) -- DROP + CREATE,
-- a signature-changing widening (three new trailing output columns), the same
-- technique 226C's own end_leg_tracking_session widening already established.
-- ============================================================================

drop function app.lookup_public_shipment_tracking(text, text);

create function app.lookup_public_shipment_tracking(
  p_raw_token text,
  p_client_key text
)
returns table (
  lookup_status text,
  shipment_number text,
  status text,
  mode text,
  origin text,
  destination text,
  planned_delivery_at timestamptz,
  current_eta timestamptz,
  is_delayed boolean,
  milestones jsonb,
  epod_available boolean,
  vehicle_position_geojson jsonb,
  vehicle_position_updated_at timestamptz,
  vehicle_position_status text
)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_hash text;
  v_token app.shipment_tracking_tokens;
  v_shipment app.shipment_orders;
  v_projection app.shipment_milestone_projections;
  v_epod_available boolean;
  v_milestones jsonb;
  v_vehicle_master_id uuid;
  v_customer_visible boolean;
  v_position app.vehicle_current_positions;
  v_policy record;
  v_vehicle_position_geojson jsonb;
  v_vehicle_position_updated_at timestamptz;
  v_vehicle_position_status text;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'tracking_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.tracking_lookup_attempts
  where client_key = p_client_key and result in ('not_found', 'invalid') and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'rate_limited');
    return query select 'rate_limited'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean, null::jsonb, null::timestamptz, null::text;
    return;
  end if;

  if p_raw_token is null or length(p_raw_token) = 0 then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean, null::jsonb, null::timestamptz, null::text;
    return;
  end if;

  v_hash := encode(digest(p_raw_token, 'sha256'), 'hex');
  select * into v_token from app.shipment_tracking_tokens where token_hash = v_hash;

  if not found or v_token.status <> 'active' or v_token.expires_at <= now() then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'not_found');
    return query select 'not_found'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean, null::jsonb, null::timestamptz, null::text;
    return;
  end if;

  insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'success');

  select * into v_shipment from app.shipment_orders so where so.id = v_token.shipment_order_id;
  select * into v_projection from app.shipment_milestone_projections where shipment_order_id = v_shipment.id;

  select coalesce(jsonb_agg(jsonb_build_object('code', me.milestone_code, 'eventTime', me.event_time) order by me.event_time asc), '[]'::jsonb)
  into v_milestones
  from app.milestone_events me
  join app.milestone_codes mc on mc.code = me.milestone_code
  where me.shipment_order_id = v_shipment.id and mc.is_customer_visible;

  select exists (
    select 1 from app.epod_captures ec where ec.shipment_order_id = v_shipment.id and ec.is_latest_version and ec.status = 'completed'
  ) into v_epod_available;

  -- Design note 3: vehicle position is exposed only when the currently-executing
  -- leg's own tracking policy explicitly marks customer_visible -- reused from
  -- ATW-225, never a new field this migration invents.
  select ra.resource_id into v_vehicle_master_id
  from app.resource_assignments ra
  where ra.shipment_order_id = v_shipment.id and ra.role = 'vehicle' and ra.is_current and ra.status = 'active';

  if v_vehicle_master_id is not null then
    select p.customer_visible into v_customer_visible
    from app.shipment_legs sl
    join app.shipment_leg_tracking_policies p on p.shipment_leg_id = sl.id
    where sl.shipment_order_id = v_shipment.id and sl.leg_status in ('dispatched', 'in_transit')
    order by sl.sequence_no
    limit 1;

    if coalesce(v_customer_visible, false) then
      select * into v_position from app.vehicle_current_positions where vehicle_master_id = v_vehicle_master_id;
      if found then
        v_vehicle_position_geojson := ST_AsGeoJSON(v_position.location)::jsonb;
        v_vehicle_position_updated_at := v_position.received_at;

        select * into v_policy from app.resolve_tenant_tracking_source_policy(v_shipment.tenant_id);
        if now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval then
          v_vehicle_position_status := 'live';
        elsif now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval * 3 then
          v_vehicle_position_status := 'delayed';
        else
          v_vehicle_position_status := 'unavailable';
        end if;
      end if;
    end if;
  end if;

  return query
  select
    'ok', v_shipment.shipment_number, v_shipment.status, v_shipment.mode, v_shipment.origin, v_shipment.destination,
    v_shipment.planned_delivery_at, v_projection.current_eta, coalesce(v_projection.is_delayed, false),
    v_milestones, v_epod_available,
    v_vehicle_position_geojson, v_vehicle_position_updated_at, v_vehicle_position_status;
end;
$$;

comment on function app.lookup_public_shipment_tracking is
  'OPS-180, widened at ATW-226H (design note 2 above): identical to its own original body, plus a sanitized vehicle-position projection (design notes 3/4) -- coarse live/delayed/unavailable status, never the raw source type, and only when the currently-executing leg''s own tracking policy explicitly opted in (customer_visible). No vehicle assignment, no currently-executing leg, or an explicit customer_visible=false all cleanly yield null position fields, never an error.';

revoke execute on all functions in schema app from public;

grant execute on function app.get_tenant_vehicle_tracking_overview(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_tenant_pending_milestone_candidates(uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.get_tenant_pending_exception_signals(uuid, uuid, integer) to authenticated, service_role;

-- Re-grant exactly as OPS-180's own original migration did -- DROP + CREATE does not
-- preserve a prior grant automatically (unlike CREATE OR REPLACE), so this is not
-- merely restated for self-contained auditability (226F/226G's own convention) but
-- structurally required here.
grant execute on function app.issue_shipment_tracking_token(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_shipment_tracking_token(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.lookup_public_shipment_tracking(text, text) to anon, authenticated, service_role;
