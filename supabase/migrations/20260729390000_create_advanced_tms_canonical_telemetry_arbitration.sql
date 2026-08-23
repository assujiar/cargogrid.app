-- Advanced TMS capability ATW-226F (Prompt 226 decomposition child, "Canonical
-- telemetry, dedup/order, current position, history, source arbitration, and
-- conflict/fallback" -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md
-- §1.4). The single normalization/arbitration layer every one of ATW-226C/226D/226E's
-- own raw ingestion RPCs now feeds -- "all modes call one canonical normalization and
-- source-arbitration service" (226_GPS_TELEMATICS_INTEGRATION_PROMPT.md §14).
--
-- Design boundary (disclosed):
--
-- 1. **Widens three already-applied ingestion functions, does not fork them.**
--    `app.ingest_driver_mobile_report` (`226C`), `app.ingest_direct_device_telemetry_
--    batch` (`226D`), and `app.ingest_third_party_provider_webhook_event` (`226E`) are
--    each re-declared here via `CREATE OR REPLACE FUNCTION` with their own *exact,
--    unchanged* signature (this is a body-only widening -- unlike `226C`'s own
--    `end_leg_tracking_session` DROP+CREATE, no parameter is added or removed, so
--    `CREATE OR REPLACE` is the correct, lower-risk technique here per this repository's
--    own standing convention: DROP+CREATE only when the signature itself changes). Each
--    widened body is byte-for-byte identical to its own already-applied migration's
--    version, with exactly one addition: a call to `app.arbitrate_and_project_vehicle_
--    position()` immediately after its own raw report insert succeeds, for a
--    `location`/`heartbeat` report. Every existing db-test for `226C`/`226D`/`226E`
--    re-passes unmodified against these widened bodies (proven in this checkpoint's own
--    full-suite gate re-run) -- the observable ingestion contract (return shape, status
--    values, rate limiting, signature/token gating) is completely unchanged.
-- 2. **Canonicalization never breaks raw ingestion.** The raw report insert (already a
--    tested, relied-upon contract) always completes and is durably stored regardless of
--    whether canonicalization succeeds -- vehicle resolution
--    (`app.resolve_vehicle_for_driver_mobile_session`/`app.resolve_vehicle_for_gps_
--    device`) returns `null` (never raises) when no current resource assignment/device-
--    vehicle mapping can be found, and the widened bodies simply skip arbitration in
--    that case. `226C`'s own `anon`-facing status-contract is untouched by design: the
--    arbitration call sits strictly after the point where every widened function has
--    already committed to a `'success'`/`'ok'` outcome.
-- 3. **Deterministic, reproducible, auditable arbitration** (`226_*.md` §24/§25:
--    "canonical current position is selected deterministically," "reproducible from
--    stored policy and evidence," "source switches are auditable and cannot oscillate
--    without configured hysteresis"). `app.arbitrate_and_project_vehicle_position()`
--    evaluates, in order: source-priority-disabled, heartbeat-carries-no-location,
--    accuracy-below-threshold, stale-event-time (`226_*.md` §25: "current position must
--    never move backward to older recorded_at merely because it arrived later"),
--    impossible-movement (implied speed between the current and candidate position),
--    then same-source-continuation or cross-source-switch (gated by
--    `app.tenant_tracking_source_policies`' own `freshness_threshold_seconds`/
--    `switch_hysteresis_seconds`, `226A`). Every rejected candidate is still stored as a
--    canonical event with its own `rejection_reason` -- "never silently drop accepted
--    data" (`226_*.md` §23) applies to the canonical layer exactly as it already does at
--    the raw layer.
-- 4. **Per-vehicle priority (`app.vehicle_tracking_source_priorities`, `ATW-223`) wins
--    over the tenant default (`app.tenant_tracking_source_policies`, `ATW-226A`)** --
--    `app.resolve_vehicle_source_priority_rank()` checks the per-vehicle override first;
--    a source explicitly disabled there (`is_enabled = false`) can never win arbitration
--    regardless of the tenant default, closing `223`'s own disclosed "declares only a
--    policy, not live arbitration -- that is ATW-226F's own scope" boundary.
-- 5. **Current position is a single row per vehicle, deliberately separate from history**
--    (`226_*.md` §13: "keep current position separate from high-volume history").
--    `app.canonical_telemetry_events` (append-only, one row per accepted canonical
--    event, whether or not it won arbitration) *is* the history tier -- no third,
--    redundant "position_history" table. Route-segment aggregation is not built this
--    checkpoint (not named in `226_*.md` §20's own `226F` task line the way "current
--    position, history, source arbitration" are); a future read-side aggregation over
--    `app.canonical_telemetry_events` is the natural place for it.
-- 6. **Impossible-movement uses a fixed, disclosed ceiling (200 km/h implied speed)** --
--    a deliberately generous bound for ground-vehicle tracking (never a claim this suits
--    every conceivable mode/geography), applied only when both the current and
--    candidate position carry real coordinates and positive elapsed event time.
-- 7. Per `ERR-2026-004`: this migration carries its own explicit
--    `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its
--    final grants.

create table app.canonical_telemetry_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vehicle_master_id uuid not null references app.master_records (id),
  source_type text not null,
  source_report_id uuid not null,
  event_at timestamptz not null,
  received_at timestamptz not null,
  location geography(Point, 4326),
  speed_kmh numeric,
  heading_degrees numeric,
  accuracy_meters numeric,
  applied_to_current_position boolean not null default false,
  rejection_reason text,
  created_at timestamptz not null default now(),
  constraint canonical_telemetry_events_source_check check (source_type in ('driver_mobile', 'direct_device', 'third_party_platform')),
  constraint canonical_telemetry_events_dedup_unique unique (source_type, source_report_id),
  constraint canonical_telemetry_events_location_valid_check check (location is null or app.validate_geography_point(location)),
  constraint canonical_telemetry_events_applied_reason_check check (applied_to_current_position = false or rejection_reason is null)
);

comment on table app.canonical_telemetry_events is
  'ATW-226F: the single normalized event log every one of 226C/226D/226E''s own raw tables feeds into (source_report_id is that raw table''s own row id, polymorphic on source_type -- no FK, since three different tables). This *is* the "history" tier (226_*.md §13) -- current position (app.vehicle_current_positions) is deliberately a separate, single-row-per-vehicle table. A row with applied_to_current_position=false is not a dropped event -- it is a real, retained, explained-by-rejection_reason record (226_*.md §23: never silently drop accepted data).';

create index canonical_telemetry_events_vehicle_idx on app.canonical_telemetry_events (vehicle_master_id, event_at desc);
create index canonical_telemetry_events_tenant_idx on app.canonical_telemetry_events (tenant_id, received_at desc);

create table app.vehicle_current_positions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vehicle_master_id uuid not null references app.master_records (id),
  source_type text not null,
  canonical_telemetry_event_id uuid not null references app.canonical_telemetry_events (id),
  location geography(Point, 4326) not null,
  speed_kmh numeric,
  heading_degrees numeric,
  event_at timestamptz not null,
  received_at timestamptz not null,
  updated_at timestamptz not null default now(),
  constraint vehicle_current_positions_vehicle_unique unique (vehicle_master_id),
  constraint vehicle_current_positions_source_check check (source_type in ('driver_mobile', 'direct_device', 'third_party_platform')),
  constraint vehicle_current_positions_location_valid_check check (app.validate_geography_point(location))
);

comment on table app.vehicle_current_positions is
  'ATW-226F: one row per vehicle -- the sole authoritative "where is this vehicle right now" projection, deliberately separate from app.canonical_telemetry_events''s own high-volume history. Only app.arbitrate_and_project_vehicle_position() ever writes here.';

create function app.touch_vehicle_current_positions_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger vehicle_current_positions_touch_row
  before update on app.vehicle_current_positions
  for each row
  execute function app.touch_vehicle_current_positions_row();

-- Read-side-computed staleness (app.get_vehicle_source_health) rather than a stored
-- status column -- avoids a background sweep just to flip a status enum, and a status
-- computed against the tenant's own live freshness_threshold_seconds is never stale
-- itself.
create table app.vehicle_source_health (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vehicle_master_id uuid not null references app.master_records (id),
  source_type text not null,
  last_seen_event_at timestamptz,
  last_seen_received_at timestamptz,
  last_location geography(Point, 4326),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_source_health_vehicle_source_unique unique (vehicle_master_id, source_type),
  constraint vehicle_source_health_source_check check (source_type in ('driver_mobile', 'direct_device', 'third_party_platform')),
  constraint vehicle_source_health_last_location_valid_check check (last_location is null or app.validate_geography_point(last_location))
);

comment on table app.vehicle_source_health is
  'ATW-226F: last-seen evidence per (vehicle, source), updated on every accepted canonical event regardless of whether it won arbitration -- a heartbeat or a priority-disabled source still proves the source is alive. last_location is this source''s own last reported point (never blanked by a heartbeat) -- the impossible-movement check in app.arbitrate_and_project_vehicle_position() compares a candidate against this per-source history, not the (possibly different-source) current winning position, since two independently-clocked sources cannot be compared for implied speed against each other. app.get_vehicle_source_health() computes healthy/stale/offline on read against the tenant''s own live freshness_threshold_seconds, never a stored, potentially-stale status.';

create index vehicle_source_health_vehicle_idx on app.vehicle_source_health (vehicle_master_id);

-- Append-only audit -- "source switches are auditable and cannot oscillate without
-- configured hysteresis" (226_*.md §24).
create table app.vehicle_source_switches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vehicle_master_id uuid not null references app.master_records (id),
  from_source_type text,
  to_source_type text not null,
  reason text not null,
  canonical_telemetry_event_id uuid not null references app.canonical_telemetry_events (id),
  evidence jsonb not null default '{}'::jsonb,
  switched_at timestamptz not null default now(),
  constraint vehicle_source_switches_to_check check (to_source_type in ('driver_mobile', 'direct_device', 'third_party_platform')),
  constraint vehicle_source_switches_from_check check (from_source_type is null or from_source_type in ('driver_mobile', 'direct_device', 'third_party_platform')),
  constraint vehicle_source_switches_reason_check check (reason in ('bootstrap', 'higher_priority_source_available', 'current_source_stale_fallback'))
);

comment on table app.vehicle_source_switches is
  'ATW-226F: one row every time app.vehicle_current_positions.source_type actually changes (including the first-ever bootstrap, from_source_type null). evidence carries the exact ranks/thresholds/elapsed-seconds the arbitration decision used -- "reproducible from stored policy and evidence" (226_*.md §25), not merely a free-text reason string.';

create index vehicle_source_switches_vehicle_idx on app.vehicle_source_switches (vehicle_master_id, switched_at desc);

-- Per-vehicle override (app.vehicle_tracking_source_priorities, ATW-223) wins over the
-- tenant default (app.tenant_tracking_source_policies, ATW-226A); null means "this
-- source may never win arbitration for this vehicle" (either explicitly is_enabled=false
-- per-vehicle, or simply absent from the tenant's own default_source_priority array).
create function app.resolve_vehicle_source_priority_rank(p_tenant_id uuid, p_vehicle_master_id uuid, p_source_type text)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_override app.vehicle_tracking_source_priorities;
  v_policy record;
begin
  select * into v_override from app.vehicle_tracking_source_priorities where vehicle_master_id = p_vehicle_master_id and source_type = p_source_type;
  if found then
    if not v_override.is_enabled then
      return null;
    end if;
    return v_override.priority_rank;
  end if;

  select * into v_policy from app.resolve_tenant_tracking_source_policy(p_tenant_id);
  return array_position(v_policy.default_source_priority, p_source_type);
end;
$$;

comment on function app.resolve_vehicle_source_priority_rank is
  'ATW-226F: lower rank = higher priority (array_position''s own 1-based convention). Null means this source is disabled/unranked for this vehicle and can never win arbitration -- closes ATW-223''s own disclosed "declares only a policy, not live arbitration" boundary on app.vehicle_tracking_source_priorities.';

-- Resolves the vehicle a driver-mobile session''s own report should project onto: the
-- session''s leg''s own shipment order''s own currently-assigned vehicle
-- (app.resource_assignments, OPS-172) -- a driver-mobile session itself only names the
-- DRIVER (app.shipment_leg_tracking_sessions.resource_kind='driver'), never the vehicle
-- directly. Returns null (never raises) when no current vehicle assignment exists --
-- app.ingest_driver_mobile_report skips canonicalization gracefully in that case,
-- never failing the already-committed raw report insert.
create function app.resolve_vehicle_for_driver_mobile_session(p_driver_mobile_tracking_session_id uuid)
returns uuid
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select ra.resource_id
  from app.driver_mobile_tracking_sessions dms
  join app.shipment_leg_tracking_sessions slts on slts.id = dms.shipment_leg_tracking_session_id
  join app.shipment_legs sl on sl.id = slts.shipment_leg_id
  join app.resource_assignments ra on ra.shipment_order_id = sl.shipment_order_id and ra.role = 'vehicle' and ra.is_current and ra.status = 'active'
  where dms.id = p_driver_mobile_tracking_session_id
  limit 1;
$$;

-- Resolves the vehicle a direct-hardware device''s own telemetry should project onto:
-- app.device_vehicle_assignments'' own current row (ATW-223). Returns null (never
-- raises) when the device has no current vehicle assignment.
create function app.resolve_vehicle_for_gps_device(p_device_id uuid)
returns uuid
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select vop.vehicle_master_id
  from app.device_vehicle_assignments dva
  join app.vehicle_operational_profiles vop on vop.id = dva.vehicle_operational_profile_id
  where dva.device_id = p_device_id and dva.is_current
  limit 1;
$$;

-- The one real normalization/arbitration entry point every raw ingestion RPC now calls
-- (design note 1 above). Idempotent on (source_type, source_report_id) -- a retried call
-- for an already-canonicalized report returns the existing row rather than erroring or
-- double-counting. Never raises for a business-outcome rejection (mirrors the raw
-- ingestion layer''s own anon-safe status-column discipline where it applies, though this
-- function itself is service_role-only, called only from within already-SECURITY-DEFINER
-- ingestion bodies).
create function app.arbitrate_and_project_vehicle_position(
  p_tenant_id uuid,
  p_vehicle_master_id uuid,
  p_source_type text,
  p_source_report_id uuid,
  p_event_at timestamptz,
  p_received_at timestamptz,
  p_location geography,
  p_speed_kmh numeric,
  p_heading_degrees numeric,
  p_accuracy_meters numeric
)
returns app.canonical_telemetry_events
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_existing app.canonical_telemetry_events;
  v_event app.canonical_telemetry_events;
  v_current app.vehicle_current_positions;
  v_has_current boolean;
  v_source_health app.vehicle_source_health;
  v_has_source_history boolean;
  v_policy record;
  v_incoming_rank integer;
  v_current_rank integer;
  v_apply boolean := false;
  v_reason text;
  v_switch_reason text;
  v_distance_meters numeric;
  v_elapsed_seconds numeric;
  v_implied_speed_kmh numeric;
  v_evidence jsonb;
begin
  select * into v_existing from app.canonical_telemetry_events where source_type = p_source_type and source_report_id = p_source_report_id;
  if found then
    return v_existing;
  end if;

  select * into v_current from app.vehicle_current_positions where vehicle_master_id = p_vehicle_master_id;
  v_has_current := found;

  -- Per-source history, not the (possibly different-source) current winning position --
  -- two independently-clocked sources cannot be compared for implied speed against each
  -- other without producing spurious impossible-movement false positives on a
  -- legitimate cross-source arbitration candidate.
  select * into v_source_health from app.vehicle_source_health where vehicle_master_id = p_vehicle_master_id and source_type = p_source_type;
  v_has_source_history := found;

  select * into v_policy from app.resolve_tenant_tracking_source_policy(p_tenant_id);

  v_incoming_rank := app.resolve_vehicle_source_priority_rank(p_tenant_id, p_vehicle_master_id, p_source_type);

  if v_incoming_rank is null then
    v_reason := 'source_disabled';
  elsif p_location is null then
    v_reason := 'heartbeat_no_location';
  elsif p_accuracy_meters is not null and p_accuracy_meters > v_policy.accuracy_threshold_meters then
    v_reason := 'accuracy_below_threshold';
  elsif v_has_current and p_event_at <= v_current.event_at then
    v_reason := 'stale_event_time';
  elsif v_has_source_history and v_source_health.last_location is not null and v_source_health.last_seen_event_at is not null then
    v_distance_meters := ST_Distance(v_source_health.last_location, p_location);
    v_elapsed_seconds := extract(epoch from (p_event_at - v_source_health.last_seen_event_at));
    if v_elapsed_seconds > 0 then
      v_implied_speed_kmh := (v_distance_meters / 1000) / (v_elapsed_seconds / 3600);
      if v_implied_speed_kmh > 200 then
        v_reason := 'impossible_movement';
      end if;
    end if;
  end if;

  if v_reason is null and v_has_current and v_current.source_type <> p_source_type then
    v_current_rank := coalesce(app.resolve_vehicle_source_priority_rank(p_tenant_id, p_vehicle_master_id, v_current.source_type), 999999);
    declare
      v_is_higher_priority boolean := v_incoming_rank < v_current_rank;
      v_current_is_stale boolean := (p_received_at - v_current.received_at) > (v_policy.freshness_threshold_seconds::text || ' seconds')::interval;
      v_recent_switch boolean;
    begin
      select exists (
        select 1 from app.vehicle_source_switches
        where vehicle_master_id = p_vehicle_master_id and switched_at > now() - (v_policy.switch_hysteresis_seconds::text || ' seconds')::interval
      ) into v_recent_switch;

      if (v_is_higher_priority or v_current_is_stale) and not v_recent_switch then
        v_apply := true;
        v_switch_reason := case when v_is_higher_priority then 'higher_priority_source_available' else 'current_source_stale_fallback' end;
        v_evidence := jsonb_build_object(
          'incoming_rank', v_incoming_rank, 'current_rank', v_current_rank,
          'is_higher_priority', v_is_higher_priority, 'current_is_stale', v_current_is_stale,
          'freshness_threshold_seconds', v_policy.freshness_threshold_seconds
        );
      else
        v_reason := 'switch_suppressed';
      end if;
    end;
  elsif v_reason is null then
    v_apply := true;
    if not v_has_current then
      v_switch_reason := 'bootstrap';
      v_evidence := jsonb_build_object('incoming_rank', v_incoming_rank);
    end if;
  end if;

  insert into app.canonical_telemetry_events (
    tenant_id, vehicle_master_id, source_type, source_report_id, event_at, received_at,
    location, speed_kmh, heading_degrees, accuracy_meters, applied_to_current_position, rejection_reason
  ) values (
    p_tenant_id, p_vehicle_master_id, p_source_type, p_source_report_id, p_event_at, p_received_at,
    p_location, p_speed_kmh, p_heading_degrees, p_accuracy_meters, v_apply, case when v_apply then null else v_reason end
  )
  returning * into v_event;

  if v_apply then
    insert into app.vehicle_current_positions (tenant_id, vehicle_master_id, source_type, canonical_telemetry_event_id, location, speed_kmh, heading_degrees, event_at, received_at)
    values (p_tenant_id, p_vehicle_master_id, p_source_type, v_event.id, p_location, p_speed_kmh, p_heading_degrees, p_event_at, p_received_at)
    on conflict (vehicle_master_id) do update
      set source_type = excluded.source_type, canonical_telemetry_event_id = excluded.canonical_telemetry_event_id,
          location = excluded.location, speed_kmh = excluded.speed_kmh, heading_degrees = excluded.heading_degrees,
          event_at = excluded.event_at, received_at = excluded.received_at;

    if v_switch_reason is not null then
      insert into app.vehicle_source_switches (tenant_id, vehicle_master_id, from_source_type, to_source_type, reason, canonical_telemetry_event_id, evidence)
      values (p_tenant_id, p_vehicle_master_id, case when v_has_current then v_current.source_type else null end, p_source_type, v_switch_reason, v_event.id, coalesce(v_evidence, '{}'::jsonb));
    end if;
  end if;

  -- last_location only advances when this report is the newest-by-event_at seen so far
  -- for this source, and never blanks out on a heartbeat (p_location null) -- a
  -- heartbeat still proves the source is alive (last_seen_* always advances) without
  -- discarding the last real fix.
  insert into app.vehicle_source_health (tenant_id, vehicle_master_id, source_type, last_seen_event_at, last_seen_received_at, last_location)
  values (p_tenant_id, p_vehicle_master_id, p_source_type, p_event_at, p_received_at, p_location)
  on conflict (vehicle_master_id, source_type) do update
    set last_seen_event_at = greatest(app.vehicle_source_health.last_seen_event_at, excluded.last_seen_event_at),
        last_seen_received_at = greatest(app.vehicle_source_health.last_seen_received_at, excluded.last_seen_received_at),
        last_location = case
          when excluded.last_location is not null and (app.vehicle_source_health.last_seen_event_at is null or p_event_at >= app.vehicle_source_health.last_seen_event_at)
          then excluded.last_location
          else app.vehicle_source_health.last_location
        end,
        updated_at = now();

  return v_event;
end;
$$;

comment on function app.arbitrate_and_project_vehicle_position is
  'ATW-226F: the single canonical normalization/arbitration entry point (design note 3 above). Every rejected candidate is still stored (design note 3); vehicle_source_health is updated unconditionally, regardless of arbitration outcome, since even a rejected/disabled-source report is real evidence the source is alive.';

create function app.get_vehicle_current_position(p_vehicle_master_id uuid)
returns table (
  vehicle_master_id uuid, tenant_id uuid, source_type text, location_geojson jsonb,
  speed_kmh numeric, heading_degrees numeric, event_at timestamptz, received_at timestamptz, updated_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public, pg_temp
as $$
  select
    p.vehicle_master_id, p.tenant_id, p.source_type, ST_AsGeoJSON(p.location)::jsonb,
    p.speed_kmh, p.heading_degrees, p.event_at, p.received_at, p.updated_at
  from app.vehicle_current_positions p
  where p.vehicle_master_id = p_vehicle_master_id;
$$;

comment on function app.get_vehicle_current_position is
  'ATW-226F: the sole authoritative "where is this vehicle right now" read, GeoJSON-projected exactly like app.get_direct_device_telemetry_reports (ATW-226D). Returns zero rows if the vehicle has never had a canonical position applied.';

-- Bounded (226_*.md §15: "bounded route history") -- a hard 500-row cap regardless of
-- p_limit, never an unbounded scan.
create function app.get_vehicle_telemetry_history(p_vehicle_master_id uuid, p_since timestamptz default null, p_limit integer default 200)
returns table (
  id uuid, tenant_id uuid, vehicle_master_id uuid, source_type text, event_at timestamptz, received_at timestamptz,
  location_geojson jsonb, speed_kmh numeric, heading_degrees numeric, accuracy_meters numeric,
  applied_to_current_position boolean, rejection_reason text
)
language sql
stable
security invoker
set search_path = app, public, pg_temp
as $$
  select
    e.id, e.tenant_id, e.vehicle_master_id, e.source_type, e.event_at, e.received_at,
    case when e.location is not null then ST_AsGeoJSON(e.location)::jsonb else null end,
    e.speed_kmh, e.heading_degrees, e.accuracy_meters, e.applied_to_current_position, e.rejection_reason
  from app.canonical_telemetry_events e
  where e.vehicle_master_id = p_vehicle_master_id and (p_since is null or e.event_at >= p_since)
  order by e.event_at desc
  limit least(coalesce(p_limit, 200), 500);
$$;

comment on function app.get_vehicle_telemetry_history is
  'ATW-226F: newest-first, hard-capped at 500 rows regardless of the caller''s own p_limit (226_*.md §15''s own "bounded route history" requirement, enforced structurally, not by UI convention alone).';

create function app.get_vehicle_source_health(p_tenant_id uuid, p_vehicle_master_id uuid)
returns table (source_type text, last_seen_event_at timestamptz, last_seen_received_at timestamptz, status text)
language plpgsql
stable
security invoker
set search_path = app, public, pg_temp
as $$
declare
  v_policy record;
begin
  select * into v_policy from app.resolve_tenant_tracking_source_policy(p_tenant_id);

  return query
  select
    h.source_type, h.last_seen_event_at, h.last_seen_received_at,
    case
      when h.last_seen_received_at is null then 'unknown'
      when now() - h.last_seen_received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval then 'healthy'
      when now() - h.last_seen_received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval * 3 then 'stale'
      else 'offline'
    end
  from app.vehicle_source_health h
  where h.vehicle_master_id = p_vehicle_master_id;
end;
$$;

comment on function app.get_vehicle_source_health is
  'ATW-226F: computed on read against the tenant''s own live freshness_threshold_seconds -- never a stored, potentially-stale status column (design note above). "stale" is 1x-3x the freshness threshold since last received_at, "offline" beyond that -- a disclosed, reasonable banding, not itself a named business rule.';

create function app.get_vehicle_source_switches(p_vehicle_master_id uuid, p_limit integer default 50)
returns setof app.vehicle_source_switches
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.vehicle_source_switches
  where vehicle_master_id = p_vehicle_master_id
  order by switched_at desc
  limit least(coalesce(p_limit, 50), 200);
$$;

-- ============================================================================
-- Widened ingestion RPCs (design note 1/2 above) -- CREATE OR REPLACE, identical
-- signature, byte-for-byte identical body apart from one added canonicalization call
-- each. The already-applied migration files that first created these functions are
-- never edited.
-- ============================================================================

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

  -- ATW-226F: canonicalize a location/heartbeat report -- never raises, never blocks the
  -- already-committed raw insert above.
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
  'ATW-226C, widened at ATW-226F (design note 1/2 above): raw storage only, PLUS a canonicalization call for a location/heartbeat report. The one anon-callable HTTPS ingestion entry point -- never normalizes/arbitrates itself, always delegates to app.arbitrate_and_project_vehicle_position(). A stop report also ends the underlying ATW-225 session via app.end_leg_tracking_session''s own widened driver-mobile-token path.';

create or replace function app.ingest_direct_device_telemetry_batch(
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
  v_report_id uuid;
  v_received_at timestamptz;
  v_vehicle_master_id uuid;
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
  v_vehicle_master_id := app.resolve_vehicle_for_gps_device(v_device.id);

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
    v_received_at := clock_timestamp();
    insert into app.direct_device_telemetry_reports (
      tenant_id, device_id, report_type, event_at, received_at, location,
      altitude_meters, heading_degrees, speed_kmh, satellite_count, raw_codec_id, io_elements
    ) values (
      v_device.tenant_id, v_device.id, v_report_type, v_event_at, v_received_at, v_geog,
      (v_report ->> 'altitude_meters')::numeric, (v_report ->> 'heading_degrees')::numeric,
      (v_report ->> 'speed_kmh')::numeric, (v_report ->> 'satellite_count')::integer,
      coalesce(v_report ->> 'raw_codec_id', '8E'), coalesce(v_report -> 'io_elements', '{}'::jsonb)
    )
    returning id into v_report_id;

    v_accepted := v_accepted + 1;
    if v_max_event_at is null or v_event_at > v_max_event_at then
      v_max_event_at := v_event_at;
    end if;

    -- ATW-226F: canonicalize -- never raises, never blocks the already-committed raw insert above.
    if v_vehicle_master_id is not null then
      perform app.arbitrate_and_project_vehicle_position(
        v_device.tenant_id, v_vehicle_master_id, 'direct_device', v_report_id, v_event_at, v_received_at,
        v_geog, (v_report ->> 'speed_kmh')::numeric, (v_report ->> 'heading_degrees')::numeric, null::numeric
      );
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
  'ATW-226D, widened at ATW-226F (design note 1/2 above): raw storage only, PLUS a canonicalization call per accepted report. The per-connection batch-write RPC -- durable buffering/retry against transient connectivity loss is services/gps-gateway''s own responsibility. Raises on any structurally invalid report (a trusted, already-protocol-decoded caller). Auto-transitions device status installed/offline -> active on any accepted batch.';

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

  -- ATW-226F: canonicalize -- never raises, never blocks the already-committed raw insert above.
  perform app.arbitrate_and_project_vehicle_position(
    v_conn.tenant_id, v_mapping.vehicle_master_id, 'third_party_platform', v_report.id, v_event_at, v_report.received_at,
    v_geog, v_speed, v_heading, null::numeric
  );

  return query select 'ok'::text, v_report.id;
end;
$$;

comment on function app.ingest_third_party_provider_webhook_event is
  'ATW-226E, widened at ATW-226F (design note 1/2 above): raw storage only, PLUS a canonicalization call. The one anon-callable HTTPS webhook ingestion entry point. Quarantines an unmapped external_vehicle_id rather than dropping it; treats a replayed provider_event_id as a distinct duplicate outcome.';

alter table app.canonical_telemetry_events enable row level security;
alter table app.vehicle_current_positions enable row level security;
alter table app.vehicle_source_health enable row level security;
alter table app.vehicle_source_switches enable row level security;

create policy canonical_telemetry_events_select_scoped on app.canonical_telemetry_events
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy vehicle_current_positions_select_scoped on app.vehicle_current_positions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy vehicle_source_health_select_scoped on app.vehicle_source_health
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy vehicle_source_switches_select_scoped on app.vehicle_source_switches
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.canonical_telemetry_events to authenticated, service_role;
grant insert, update, delete on app.canonical_telemetry_events to service_role;
grant select on app.vehicle_current_positions to authenticated, service_role;
grant insert, update, delete on app.vehicle_current_positions to service_role;
grant select on app.vehicle_source_health to authenticated, service_role;
grant insert, update, delete on app.vehicle_source_health to service_role;
grant select on app.vehicle_source_switches to authenticated, service_role;
grant insert, update, delete on app.vehicle_source_switches to service_role;

grant execute on function app.resolve_vehicle_source_priority_rank(uuid, uuid, text) to service_role;
grant execute on function app.resolve_vehicle_for_driver_mobile_session(uuid) to service_role;
grant execute on function app.resolve_vehicle_for_gps_device(uuid) to service_role;
grant execute on function app.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) to service_role;
grant execute on function app.get_vehicle_current_position(uuid) to authenticated, service_role;
grant execute on function app.get_vehicle_telemetry_history(uuid, timestamptz, integer) to authenticated, service_role;
grant execute on function app.get_vehicle_source_health(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vehicle_source_switches(uuid, integer) to authenticated, service_role;

-- Re-grant the three widened ingestion RPCs exactly as their own original migrations
-- already did -- CREATE OR REPLACE preserves an existing grant across a same-signature
-- replacement, but each is re-stated here for this migration's own self-contained
-- auditability (a reader should never need to cross-reference an older file to know
-- who may call these).
grant execute on function app.ingest_driver_mobile_report(text, text, text, timestamptz, jsonb, numeric, integer, boolean, boolean, jsonb) to anon, authenticated, service_role;
grant execute on function app.ingest_direct_device_telemetry_batch(text, uuid, jsonb, text) to service_role;
grant execute on function app.ingest_third_party_provider_webhook_event(uuid, text, text, bigint, text) to anon, authenticated, service_role;
