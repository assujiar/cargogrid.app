-- Advanced TMS capability ATW-226G (Prompt 226 decomposition child, "Geofence, route
-- deviation, milestone candidate, and exception signals" -- docs/build-log/phase-05/
-- ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1.4). Reads every canonical position that wins
-- arbitration (`ATW-226F`) and derives two kinds of signal: a milestone candidate
-- (stop-geofence arrival/departure) and an exception signal (route deviation, overdue
-- geofence arrival) -- both staged, reviewed, and only then promoted into the real
-- Operations record (`app.milestone_events`/`app.operational_exceptions`, `OPS-173`/
-- `OPS-174`) by an authenticated, RBAC-checked human actor.
--
-- Design boundary (disclosed):
--
-- 1. **Every derived signal is staged and reviewed -- never auto-ingested.** This is a
--    structural consequence, not merely a policy choice: `app.ingest_milestone_event`
--    (`OPS-173`) and `app.report_exception` (`OPS-174`) both call `app.evaluate_
--    permission(p_actor_auth_user_id, ...)` and `app.can_access_record(...)` against a
--    *real* identity, and both fail closed (`insufficient_authority`) for a null/absent
--    actor -- confirmed by direct inspection of both functions' own bodies before writing
--    a single line of this migration, not assumed. There is no "system identity" anywhere
--    in this repository's RBAC model, and inventing one purely to let a telemetry-
--    triggered function bypass RBAC would be a real, unjustified privilege-escalation
--    surface (any `authenticated`-granted caller of a null-actor-bypassing function could
--    exploit the exact same bypass). This migration therefore never calls either
--    function directly from `app.evaluate_geofence_and_deviation_signals()` (the
--    telemetry-triggered path, `service_role`-only, no human actor in scope) -- it writes
--    only to this migration's own new staging tables. `app.confirm_milestone_candidate()`/
--    `app.confirm_exception_signal()` are the sole promotion path, each requiring a real
--    `authenticated` actor who legitimately holds `OPS:Create` for the shipment's own
--    tenant -- the same authority `OPS-173`/`OPS-174` already require of a human filing a
--    milestone/exception directly. This is a stricter, more literal reading of
--    `226_*.md` §25 ("derived milestone/exception cannot contradict confirmed actual
--    events without review") than treating review as conditional -- every derived signal
--    passes through review, not only the ones that would contradict something.
-- 2. **Widens `app.arbitrate_and_project_vehicle_position` (`ATW-226F`), does not fork
--    it.** Same technique `226F` itself already used on `226C`/`226D`/`226E`:
--    `CREATE OR REPLACE FUNCTION` with the exact, unchanged signature, one addition --
--    a call to `app.evaluate_geofence_and_deviation_signals()` immediately after a
--    canonical event actually wins arbitration (`v_apply`), never for a rejected/
--    duplicate candidate. Every existing `226F` (and by extension `226C`/`226D`/`226E`)
--    db-test re-passes unmodified.
-- 3. **Widens `app.ingest_milestone_event` (`OPS-173`, Phase 3) and `app.milestone_
--    events`'s own `source` CHECK constraint -- the first ATW checkpoint to widen a
--    pre-Phase-5 capability's own function.** Disclosed and justified, not silent: no
--    earlier capability ever needed `ingest_milestone_event` to accept a provenance value
--    describing "GPS-derived, human-confirmed" -- the existing `manual`/`api`/`webhook`/
--    `import` vocabulary describes delivery *mechanism*, not detection origin, and none
--    of them honestly fits. The widening is a same-signature `CREATE OR REPLACE` (one
--    added string in an allowlist) plus a same-effect widening `ALTER TABLE ... DROP
--    CONSTRAINT ... ADD CONSTRAINT` on `milestone_events_source_check` -- both provably
--    additive: every existing row's own `source` value was already in the narrower
--    allowed set, so it remains valid under the wider one, and every existing caller
--    passing `manual`/`api`/`webhook`/`import` is completely unaffected. `OPS-173`'s own
--    already-applied migration file is never edited; its own db-test
--    (`scripts/db-tests/operations-milestone-management.sql`) re-passes unmodified.
-- 4. **Geofences are circular (center + radius), not polygon.** No `geography(Polygon,
--    4326)`/point-in-polygon primitive exists anywhere in this repository (`PLT-134`'s
--    own convention is `geography(Point,4326)` only); `app.bounded_st_dwithin()` already
--    governs a bounded-radius containment test exactly. A stop-linked circle is
--    sufficient for "vehicle is at this pickup/transfer/delivery point" -- a free-standing
--    zone unrelated to any stop (e.g. a customs area) is a named residual (§5), not this
--    checkpoint's scope.
-- 5. **Route deviation has no stored reference polyline to compare against** -- no
--    routing-engine geometry exists anywhere in this repository (`ATW-224`'s own route
--    planning stores only ordered stop points and straight-line stop-to-stop distances,
--    never a road-network path). The reference "corridor" is a straight line built at
--    query time (`ST_MakeLine` over a leg's own ordered `app.shipment_leg_stops.
--    location_geog`), never a stored geometry column -- a disclosed, straight-line-only
--    approximation, not a claim of road-aware routing.
-- 6. **Both geofence dwell and route-deviation confirmation use the identical elapsed-
--    time-sustained pattern** (`first_entered_at`/`first_off_corridor_at` plus a
--    configured duration, confirmed only once via a null->set transition on
--    `confirmed_at`) -- one shared, auditable, easy-to-reason-about mechanic reused
--    twice, not two different heuristics for what is structurally the same problem
--    ("has this held true long enough to stop being noise").
-- 7. **Configuration lives inside `app.shipment_leg_tracking_policies.geofence_policy`**
--    (`ATW-225`'s own disclosed hook: "geofence_policy is a candidate configuration blob
--    only; actual geofence evaluation is ATW-226G's own scope"), never a second policy
--    table. Every numeric/boolean key is read defensively (`app.safe_jsonb_numeric`/
--    `app.safe_jsonb_boolean`, this migration) with a disclosed platform default on any
--    missing or malformed value -- an operator's own configuration typo must never break
--    the live telemetry-ingestion pipeline every one of `226C`/`226D`/`226E` still relies
--    on (`226_*.md` §23: never silently break accepted data flow).
-- 8. **Raw telemetry never directly completes a shipment lifecycle** (`226_*.md` §24) --
--    this migration never writes to `app.shipment_legs.leg_status`/`app.shipment_leg_
--    stops.stop_status`/`app.shipment_orders.status` at all; a confirmed milestone
--    candidate becomes a real `app.milestone_events` row (which itself, per `OPS-173`,
--    only *projects* status via `app.shipment_milestone_projections`, never mutates the
--    canonical shipment lifecycle either).
-- 9. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON ALL
--    FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- ============================================================================
-- Defensive jsonb config readers -- a malformed/missing key in geofence_policy always
-- falls back to the disclosed default, never raises (design note 7).
-- ============================================================================

create function app.safe_jsonb_numeric(p_jsonb jsonb, p_key text, p_default numeric)
returns numeric
language plpgsql
immutable
as $$
declare
  v_result numeric;
begin
  if p_jsonb is null then
    return p_default;
  end if;
  if not (p_jsonb ? p_key) or p_jsonb -> p_key = 'null'::jsonb then
    return p_default;
  end if;
  begin
    v_result := (p_jsonb ->> p_key)::numeric;
  exception when others then
    return p_default;
  end;
  return coalesce(v_result, p_default);
end;
$$;

comment on function app.safe_jsonb_numeric is
  'ATW-226G: reads a numeric key out of a caller-supplied jsonb config blob, falling back to p_default on a missing key, a null value, or a malformed (non-numeric) value -- never raises. Used throughout this migration''s own geofence_policy readers so an operator''s own configuration typo can never break the live telemetry-ingestion pipeline it is embedded in.';

create function app.safe_jsonb_boolean(p_jsonb jsonb, p_key text, p_default boolean)
returns boolean
language plpgsql
immutable
as $$
declare
  v_result boolean;
begin
  if p_jsonb is null then
    return p_default;
  end if;
  if not (p_jsonb ? p_key) or p_jsonb -> p_key = 'null'::jsonb then
    return p_default;
  end if;
  begin
    v_result := (p_jsonb ->> p_key)::boolean;
  exception when others then
    return p_default;
  end;
  return coalesce(v_result, p_default);
end;
$$;

comment on function app.safe_jsonb_boolean is
  'ATW-226G: the boolean counterpart to app.safe_jsonb_numeric -- same never-raises, defaulted-on-any-malformed-input contract.';

-- ============================================================================
-- Geofence dwell state (one row per shipment_leg_stop, lazily created on first entry).
-- ============================================================================

create table app.shipment_leg_stop_geofence_states (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_stop_id uuid not null references app.shipment_leg_stops (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  radius_meters numeric not null,
  dwell_seconds_before_confirm numeric not null,
  state text not null default 'entered_pending_dwell',
  first_entered_at timestamptz,
  confirmed_at timestamptz,
  last_evaluated_at timestamptz not null,
  last_evaluated_location geography (point, 4326),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_leg_stop_geofence_states_stop_unique unique (shipment_leg_stop_id),
  constraint shipment_leg_stop_geofence_states_state_check check (state in ('outside', 'entered_pending_dwell', 'confirmed_inside', 'exited')),
  constraint shipment_leg_stop_geofence_states_radius_check check (radius_meters > 0),
  constraint shipment_leg_stop_geofence_states_dwell_check check (dwell_seconds_before_confirm >= 0),
  constraint shipment_leg_stop_geofence_states_location_valid_check check (last_evaluated_location is null or app.validate_geography_point(last_evaluated_location))
);

comment on table app.shipment_leg_stop_geofence_states is
  'ATW-226G: dwell-tracking state for one stop''s own circular geofence (radius_meters, center = app.shipment_leg_stops.location_geog). Lazily created only on first entry into the radius -- a stop never approached carries no row. outside->entered_pending_dwell->confirmed_inside->exited is one-directional (no re-entry modeling this checkpoint); confirmed_at set exactly once, on the elapsed-time transition that fires the arrival milestone candidate.';

create index shipment_leg_stop_geofence_states_leg_idx on app.shipment_leg_stop_geofence_states (shipment_leg_id);

-- ============================================================================
-- Route-deviation state (one row per shipment_leg, lazily created on first deviation).
-- ============================================================================

create table app.shipment_leg_route_deviation_states (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  state text not null default 'off_corridor',
  first_off_corridor_at timestamptz,
  confirmed_at timestamptz,
  last_evaluated_at timestamptz not null,
  last_distance_meters numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_leg_route_deviation_states_leg_unique unique (shipment_leg_id),
  constraint shipment_leg_route_deviation_states_state_check check (state in ('on_corridor', 'off_corridor'))
);

comment on table app.shipment_leg_route_deviation_states is
  'ATW-226G: sustained-deviation tracking for one leg''s own straight-line stop-to-stop corridor (design note 5). A silent recovery (back inside the corridor) resets first_off_corridor_at/confirmed_at to null -- the next episode gets a fresh timestamp, load-bearing for app.shipment_exception_signals.correlation_key uniqueness (each deviation episode is a distinct, independently-dedup''d signal).';

-- ============================================================================
-- Milestone candidate -- staged, reviewed, only then promoted into a real
-- app.milestone_events row via app.confirm_milestone_candidate (design note 1).
-- ============================================================================

create table app.shipment_milestone_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  shipment_leg_stop_id uuid not null references app.shipment_leg_stops (id),
  milestone_code text not null,
  candidate_event_time timestamptz not null,
  detected_at timestamptz not null default now(),
  source_canonical_event_id uuid references app.canonical_telemetry_events (id),
  location geography (point, 4326),
  status text not null default 'pending',
  dedup_key text not null,
  resulting_milestone_event_id uuid references app.milestone_events (id),
  reviewed_by_user_id uuid references auth.users (id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  constraint shipment_milestone_candidates_status_check check (status in ('pending', 'confirmed', 'dismissed')),
  constraint shipment_milestone_candidates_location_valid_check check (location is null or app.validate_geography_point(location))
);

comment on table app.shipment_milestone_candidates is
  'ATW-226G: a geofence-derived, not-yet-real milestone. milestone_code carries no FK to app.milestone_codes -- deliberately deferred, since that registry is a permanent, Supreme-Admin-registered, platform-wide set (OPS-173) this checkpoint does not auto-populate; an unregistered code simply cannot be confirmed yet (app.ingest_milestone_event''s own existing milestone_unknown_code check), not a new failure mode this migration invents. dedup_key is stable per (stop, direction) -- a stop can arrive/depart at most once in this checkpoint''s own one-directional state model, so no timestamp component is needed the way app.shipment_exception_signals.correlation_key needs one.';

create unique index shipment_milestone_candidates_tenant_dedup_pending_unique on app.shipment_milestone_candidates (tenant_id, dedup_key) where status = 'pending';
create index shipment_milestone_candidates_shipment_idx on app.shipment_milestone_candidates (shipment_order_id, detected_at desc);

-- ============================================================================
-- Exception signal -- staged, reviewed, only then promoted into a real
-- app.operational_exceptions row via app.confirm_exception_signal (design note 1).
-- ============================================================================

create table app.shipment_exception_signals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  signal_type text not null,
  exception_type text not null,
  severity text not null,
  detected_at timestamptz not null default now(),
  source_canonical_event_id uuid references app.canonical_telemetry_events (id),
  location geography (point, 4326),
  description text not null,
  correlation_key text not null,
  status text not null default 'pending',
  resulting_exception_id uuid references app.operational_exceptions (id),
  reviewed_by_user_id uuid references auth.users (id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  constraint shipment_exception_signals_signal_type_check check (signal_type in ('route_deviation', 'overdue_geofence_arrival')),
  constraint shipment_exception_signals_exception_type_check check (exception_type in ('delay', 'hold', 'damage', 'loss', 'incident')),
  constraint shipment_exception_signals_severity_check check (severity in ('low', 'medium', 'high', 'critical')),
  constraint shipment_exception_signals_status_check check (status in ('pending', 'confirmed', 'dismissed')),
  constraint shipment_exception_signals_location_valid_check check (location is null or app.validate_geography_point(location))
);

comment on table app.shipment_exception_signals is
  'ATW-226G: a geofence/route-derived, not-yet-real exception. exception_type/severity mirror app.operational_exceptions'' own fixed vocabulary (OPS-174) exactly, since app.confirm_exception_signal passes both straight through to app.report_exception unchanged. correlation_key embeds a timestamp for route_deviation (a leg can have multiple distinct deviation episodes over its own lifetime) but not for overdue_geofence_arrival (a given stop becomes overdue at most meaningfully once per still-pending state) -- reused as app.report_exception''s own (tenant_id, shipment_order_id, correlation_key) dedup key once confirmed (OPS-174''s own existing idempotency, not duplicated here).';

create unique index shipment_exception_signals_tenant_correlation_pending_unique on app.shipment_exception_signals (tenant_id, correlation_key) where status = 'pending';
create index shipment_exception_signals_shipment_idx on app.shipment_exception_signals (shipment_order_id, detected_at desc);

-- ============================================================================
-- Internal staging writers (service_role-only, called from the evaluators below).
-- ============================================================================

create function app.upsert_milestone_candidate(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_shipment_leg_id uuid,
  p_shipment_leg_stop_id uuid,
  p_milestone_code text,
  p_candidate_event_time timestamptz,
  p_source_canonical_event_id uuid,
  p_location geography,
  p_dedup_key text
)
returns void
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
begin
  insert into app.shipment_milestone_candidates (
    tenant_id, shipment_order_id, shipment_leg_id, shipment_leg_stop_id, milestone_code,
    candidate_event_time, source_canonical_event_id, location, dedup_key
  ) values (
    p_tenant_id, p_shipment_order_id, p_shipment_leg_id, p_shipment_leg_stop_id, p_milestone_code,
    p_candidate_event_time, p_source_canonical_event_id, p_location, p_dedup_key
  )
  on conflict (tenant_id, dedup_key) where status = 'pending' do update
  set candidate_event_time = excluded.candidate_event_time,
      source_canonical_event_id = excluded.source_canonical_event_id,
      location = excluded.location,
      detected_at = now();
end;
$$;

create function app.upsert_exception_signal(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_shipment_leg_id uuid,
  p_signal_type text,
  p_exception_type text,
  p_severity text,
  p_source_canonical_event_id uuid,
  p_location geography,
  p_description text,
  p_correlation_key text
)
returns void
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
begin
  insert into app.shipment_exception_signals (
    tenant_id, shipment_order_id, shipment_leg_id, signal_type, exception_type, severity,
    source_canonical_event_id, location, description, correlation_key
  ) values (
    p_tenant_id, p_shipment_order_id, p_shipment_leg_id, p_signal_type, p_exception_type, p_severity,
    p_source_canonical_event_id, p_location, p_description, p_correlation_key
  )
  on conflict (tenant_id, correlation_key) where status = 'pending' do update
  set description = excluded.description,
      source_canonical_event_id = excluded.source_canonical_event_id,
      location = excluded.location,
      detected_at = now();
end;
$$;

-- ============================================================================
-- Evaluators -- called from the widened app.arbitrate_and_project_vehicle_position
-- (design note 2), one call per canonical event that actually wins arbitration.
-- ============================================================================

create function app.evaluate_stop_geofence(
  p_tenant_id uuid,
  p_shipment_leg_id uuid,
  p_canonical_event_id uuid,
  p_location geography,
  p_event_at timestamptz,
  p_geofence_policy jsonb
)
returns void
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_stop app.shipment_leg_stops;
  v_state app.shipment_leg_stop_geofence_states;
  v_has_state boolean;
  v_radius_meters numeric;
  v_dwell_seconds numeric;
  v_inside boolean;
  v_shipment_order_id uuid;
  v_milestone_code text;
  v_dedup_key text;
begin
  select ls.* into v_stop
  from app.shipment_leg_stops ls
  left join app.shipment_leg_stop_geofence_states gs on gs.shipment_leg_stop_id = ls.id
  where ls.shipment_leg_id = p_shipment_leg_id and ls.location_geog is not null and (gs.id is null or gs.state <> 'exited')
  order by ls.stop_sequence
  limit 1;
  if not found then
    return;
  end if;

  select sl.shipment_order_id into v_shipment_order_id from app.shipment_legs sl where sl.id = p_shipment_leg_id;

  v_radius_meters := app.safe_jsonb_numeric(p_geofence_policy, 'radius_meters', 300);
  if v_radius_meters <= 0 or v_radius_meters > app.postgis_max_query_radius_meters() then
    v_radius_meters := 300;
  end if;
  v_dwell_seconds := app.safe_jsonb_numeric(p_geofence_policy, 'dwell_seconds_before_confirm', 120);
  if v_dwell_seconds < 0 then
    v_dwell_seconds := 120;
  end if;

  select * into v_state from app.shipment_leg_stop_geofence_states where shipment_leg_stop_id = v_stop.id;
  v_has_state := found;

  v_inside := app.bounded_st_dwithin(p_location, v_stop.location_geog, v_radius_meters);

  if v_inside then
    if not v_has_state then
      insert into app.shipment_leg_stop_geofence_states (
        tenant_id, shipment_leg_stop_id, shipment_leg_id, radius_meters, dwell_seconds_before_confirm,
        state, first_entered_at, last_evaluated_at, last_evaluated_location
      ) values (
        p_tenant_id, v_stop.id, p_shipment_leg_id, v_radius_meters, v_dwell_seconds,
        'entered_pending_dwell', p_event_at, p_event_at, p_location
      )
      returning * into v_state;
    elsif v_state.state = 'outside' then
      update app.shipment_leg_stop_geofence_states
      set state = 'entered_pending_dwell', first_entered_at = p_event_at, last_evaluated_at = p_event_at, last_evaluated_location = p_location, updated_at = now()
      where id = v_state.id
      returning * into v_state;
    else
      update app.shipment_leg_stop_geofence_states
      set last_evaluated_at = p_event_at, last_evaluated_location = p_location, updated_at = now()
      where id = v_state.id
      returning * into v_state;
    end if;

    if v_state.state = 'entered_pending_dwell' and v_state.confirmed_at is null
       and extract(epoch from (p_event_at - v_state.first_entered_at)) >= v_dwell_seconds then
      update app.shipment_leg_stop_geofence_states
      set state = 'confirmed_inside', confirmed_at = p_event_at, updated_at = now()
      where id = v_state.id;

      v_milestone_code := coalesce(p_geofence_policy #>> array['milestone_code_map', v_stop.stop_type || '_arrival'], v_stop.stop_type || '_arrival');
      v_dedup_key := 'geofence_arrival:' || v_stop.id;
      perform app.upsert_milestone_candidate(
        p_tenant_id, v_shipment_order_id, p_shipment_leg_id, v_stop.id, v_milestone_code,
        p_event_at, p_canonical_event_id, p_location, v_dedup_key
      );
    end if;
  else
    if v_has_state and v_state.state = 'entered_pending_dwell' then
      update app.shipment_leg_stop_geofence_states
      set state = 'outside', first_entered_at = null, last_evaluated_at = p_event_at, last_evaluated_location = p_location, updated_at = now()
      where id = v_state.id;
    elsif v_has_state and v_state.state = 'confirmed_inside' then
      update app.shipment_leg_stop_geofence_states
      set state = 'exited', last_evaluated_at = p_event_at, last_evaluated_location = p_location, updated_at = now()
      where id = v_state.id;

      v_milestone_code := coalesce(p_geofence_policy #>> array['milestone_code_map', v_stop.stop_type || '_departure'], v_stop.stop_type || '_departure');
      v_dedup_key := 'geofence_departure:' || v_stop.id;
      perform app.upsert_milestone_candidate(
        p_tenant_id, v_shipment_order_id, p_shipment_leg_id, v_stop.id, v_milestone_code,
        p_event_at, p_canonical_event_id, p_location, v_dedup_key
      );
    end if;
  end if;
end;
$$;

comment on function app.evaluate_stop_geofence is
  'ATW-226G: evaluates exactly one stop per call -- the leg''s own earliest stop not yet in state ''exited'' (ordered by stop_sequence). A dwell-confirmed arrival or a departure-from-confirmed transition each fire exactly one milestone candidate (design note 1); an entry that never reaches dwell (leaves early) silently resets to ''outside'', no candidate.';

create function app.evaluate_route_deviation(
  p_tenant_id uuid,
  p_shipment_leg_id uuid,
  p_canonical_event_id uuid,
  p_location geography,
  p_event_at timestamptz,
  p_geofence_policy jsonb
)
returns void
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_deviation_policy jsonb;
  v_enabled boolean;
  v_corridor_width_meters numeric;
  v_sustained_seconds numeric;
  v_ref_line geography;
  v_stop_count integer;
  v_distance_meters numeric;
  v_state app.shipment_leg_route_deviation_states;
  v_has_state boolean;
  v_shipment_order_id uuid;
  v_correlation_key text;
begin
  v_deviation_policy := p_geofence_policy -> 'route_deviation';
  v_enabled := app.safe_jsonb_boolean(v_deviation_policy, 'enabled', true);
  if not v_enabled then
    return;
  end if;

  select count(*) into v_stop_count from app.shipment_leg_stops where shipment_leg_id = p_shipment_leg_id and location_geog is not null;
  if v_stop_count < 2 then
    return;
  end if;

  select ST_MakeLine(location_geog::geometry order by stop_sequence)::geography
  into v_ref_line
  from app.shipment_leg_stops
  where shipment_leg_id = p_shipment_leg_id and location_geog is not null;

  v_corridor_width_meters := app.safe_jsonb_numeric(v_deviation_policy, 'corridor_width_meters', 1500);
  if v_corridor_width_meters <= 0 or v_corridor_width_meters > app.postgis_max_query_radius_meters() then
    v_corridor_width_meters := 1500;
  end if;
  v_sustained_seconds := app.safe_jsonb_numeric(v_deviation_policy, 'deviation_sustained_seconds', 300);
  if v_sustained_seconds < 0 then
    v_sustained_seconds := 300;
  end if;

  v_distance_meters := ST_Distance(p_location, v_ref_line);

  select sl.shipment_order_id into v_shipment_order_id from app.shipment_legs sl where sl.id = p_shipment_leg_id;

  select * into v_state from app.shipment_leg_route_deviation_states where shipment_leg_id = p_shipment_leg_id;
  v_has_state := found;

  if v_distance_meters > v_corridor_width_meters then
    if not v_has_state then
      insert into app.shipment_leg_route_deviation_states (
        tenant_id, shipment_leg_id, state, first_off_corridor_at, last_evaluated_at, last_distance_meters
      ) values (
        p_tenant_id, p_shipment_leg_id, 'off_corridor', p_event_at, p_event_at, v_distance_meters
      )
      returning * into v_state;
    elsif v_state.state = 'on_corridor' then
      update app.shipment_leg_route_deviation_states
      set state = 'off_corridor', first_off_corridor_at = p_event_at, confirmed_at = null, last_evaluated_at = p_event_at, last_distance_meters = v_distance_meters, updated_at = now()
      where id = v_state.id
      returning * into v_state;
    else
      update app.shipment_leg_route_deviation_states
      set last_evaluated_at = p_event_at, last_distance_meters = v_distance_meters, updated_at = now()
      where id = v_state.id
      returning * into v_state;
    end if;

    if v_state.state = 'off_corridor' and v_state.confirmed_at is null
       and extract(epoch from (p_event_at - v_state.first_off_corridor_at)) >= v_sustained_seconds then
      update app.shipment_leg_route_deviation_states set confirmed_at = p_event_at, updated_at = now() where id = v_state.id;

      v_correlation_key := 'route_deviation:' || p_shipment_leg_id || ':' || to_char(v_state.first_off_corridor_at, 'YYYYMMDDHH24MISSUS');
      perform app.upsert_exception_signal(
        p_tenant_id, v_shipment_order_id, p_shipment_leg_id, 'route_deviation', 'delay', 'medium',
        p_canonical_event_id, p_location,
        format('Vehicle is %s meters off the planned route corridor (limit %s meters), sustained for at least %s seconds.', round(v_distance_meters), v_corridor_width_meters, v_sustained_seconds),
        v_correlation_key
      );
    end if;
  else
    if v_has_state and v_state.state = 'off_corridor' then
      update app.shipment_leg_route_deviation_states
      set state = 'on_corridor', first_off_corridor_at = null, confirmed_at = null, last_evaluated_at = p_event_at, last_distance_meters = v_distance_meters, updated_at = now()
      where id = v_state.id;
    end if;
  end if;
end;
$$;

comment on function app.evaluate_route_deviation is
  'ATW-226G: distance from a straight-line, query-time-built stop-to-stop reference (design note 5), sustained-duration-confirmed exactly like app.evaluate_stop_geofence''s own dwell test (design note 6). A silent recovery never fires a signal; a fresh episode after recovery gets its own timestamp-keyed correlation_key, so repeated deviations on the same leg over its own lifetime are each a distinct, independently reviewable signal.';

create function app.evaluate_geofence_and_deviation_signals(
  p_tenant_id uuid,
  p_vehicle_master_id uuid,
  p_canonical_event_id uuid,
  p_location geography,
  p_event_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_policy app.shipment_leg_tracking_policies;
begin
  if p_location is null then
    return;
  end if;

  select sl.* into v_leg
  from app.resource_assignments ra
  join app.shipment_legs sl on sl.shipment_order_id = ra.shipment_order_id and sl.leg_status in ('dispatched', 'in_transit')
  where ra.role = 'vehicle' and ra.resource_id = p_vehicle_master_id and ra.is_current and ra.status = 'active'
  order by sl.sequence_no
  limit 1;
  if not found then
    return;
  end if;

  select * into v_policy from app.shipment_leg_tracking_policies where shipment_leg_id = v_leg.id;
  if not found or v_policy.status <> 'active' or not v_policy.tracking_required or v_policy.geofence_policy is null
     or not app.safe_jsonb_boolean(v_policy.geofence_policy, 'enabled', true) then
    return;
  end if;

  perform app.evaluate_stop_geofence(p_tenant_id, v_leg.id, p_canonical_event_id, p_location, p_event_at, v_policy.geofence_policy);
  perform app.evaluate_route_deviation(p_tenant_id, v_leg.id, p_canonical_event_id, p_location, p_event_at, v_policy.geofence_policy);
end;
$$;

comment on function app.evaluate_geofence_and_deviation_signals is
  'ATW-226G: the single entry point the widened app.arbitrate_and_project_vehicle_position (226F) calls for every canonical event that wins arbitration. Resolves the vehicle''s own currently-assigned, currently-executing leg via app.resource_assignments (OPS-172) -- the same uniform vehicle->shipment_order path 226F itself already established for the direct_device/third_party_platform case, reused here for all three source types alike since by this point the caller already resolved a real vehicle_master_id regardless of source. No active leg, no active/required tracking policy, or an explicitly disabled geofence_policy each cleanly no-op -- never raises, never blocks the canonicalization that already committed one call up the stack.';

-- ============================================================================
-- Overdue geofence arrival -- scan-based, cron-deferred (design note below), mirroring
-- OPS-174's own already-disclosed "mechanism real, live scheduler wiring deferred"
-- posture for app.escalate_exception (no cron/poll infrastructure exists anywhere in
-- this repository yet, PLT-129/132's own original disclosure).
-- ============================================================================

create function app.detect_overdue_geofence_arrivals(p_tenant_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_stop record;
  v_count integer := 0;
  v_grace_minutes numeric;
  v_correlation_key text;
begin
  for v_stop in
    select ls.id, ls.shipment_leg_id, ls.stop_type, ls.planned_at, sl.tenant_id, sl.shipment_order_id,
           coalesce(p.geofence_policy, '{}'::jsonb) as geofence_policy
    from app.shipment_leg_stops ls
    join app.shipment_legs sl on sl.id = ls.shipment_leg_id
    left join app.shipment_leg_tracking_policies p on p.shipment_leg_id = sl.id
    where ls.stop_status = 'pending'
      and ls.planned_at is not null
      and sl.leg_status in ('dispatched', 'in_transit')
      and (p_tenant_id is null or sl.tenant_id = p_tenant_id)
      and (p.status is null or p.status = 'active')
      and coalesce(p.tracking_required, true)
      and not exists (
        -- 'exited' (not just 'confirmed_inside') also proves a real arrival was already
        -- detected at some point -- a stop that reached and left confirmed_inside must
        -- never be re-flagged overdue just because its own geofence state has since
        -- moved past that state.
        select 1 from app.shipment_leg_stop_geofence_states gs
        where gs.shipment_leg_stop_id = ls.id and gs.state in ('confirmed_inside', 'exited')
      )
      and not exists (
        select 1 from app.shipment_exception_signals es
        where es.correlation_key = 'overdue_arrival:' || ls.id and es.status = 'confirmed'
      )
  loop
    v_grace_minutes := app.safe_jsonb_numeric(v_stop.geofence_policy, 'overdue_arrival_grace_minutes', 60);
    if v_grace_minutes < 0 then
      v_grace_minutes := 60;
    end if;

    if now() > v_stop.planned_at + (v_grace_minutes || ' minutes')::interval then
      v_correlation_key := 'overdue_arrival:' || v_stop.id;
      perform app.upsert_exception_signal(
        v_stop.tenant_id, v_stop.shipment_order_id, v_stop.shipment_leg_id, 'overdue_geofence_arrival', 'delay',
        case when now() > v_stop.planned_at + (v_grace_minutes * 2 || ' minutes')::interval then 'high' else 'medium' end,
        null, null,
        format('Stop %s (%s) has not been confirmed arrived %s minutes after its planned time.', v_stop.id, v_stop.stop_type, round(v_grace_minutes)),
        v_correlation_key
      );
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

comment on function app.detect_overdue_geofence_arrivals is
  'ATW-226G: a real, callable, tenant-optionally-scoped scan -- no live scheduler invokes it anywhere in this repository (the identical disclosed posture OPS-174''s own app.escalate_exception already established: mechanism real, cron wiring deferred, PLT-129/132''s original disclosure). Returns the count of stops evaluated as overdue this run (a re-scan of an already-pending signal still counts -- an informational count only, never load-bearing for correctness, since app.upsert_exception_signal''s own dedup is what actually prevents a duplicate pending row). Excludes a stop whose overdue-arrival signal was already confirmed once, to avoid re-raising noise for a condition already tracked through OPS-174''s own SLA/escalation mechanism.';

-- ============================================================================
-- Review/promotion RPCs (authenticated) -- design note 1: the sole path a derived
-- signal ever becomes a real app.milestone_events/app.operational_exceptions row.
-- ============================================================================

create function app.confirm_milestone_candidate(
  p_candidate_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_override_event_time timestamptz default null,
  p_override_conflict boolean default false
)
returns app.milestone_events
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_candidate app.shipment_milestone_candidates;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_conflict app.milestone_events;
  v_event app.milestone_events;
  v_event_time timestamptz;
begin
  select * into v_candidate from app.shipment_milestone_candidates where id = p_candidate_id;
  if not found then
    raise exception 'milestone_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if v_candidate.status <> 'pending' then
    raise exception 'milestone_candidate_not_pending: % is %, not pending', p_candidate_id, v_candidate.status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_candidate.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_candidate.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_event_time := coalesce(p_override_event_time, v_candidate.candidate_event_time);

  -- Bounded conflict definition (226_*.md §25), disclosed rather than an exhaustive
  -- general-purpose consistency checker: a terminal milestone (e.g. delivered) already
  -- confirmed strictly before this candidate's own claimed event time means confirming
  -- this candidate would assert an earlier-lifecycle event happened after the shipment
  -- already reached a terminal state.
  select me.* into v_conflict
  from app.milestone_events me
  join app.milestone_codes mc on mc.code = me.milestone_code
  where me.shipment_order_id = v_candidate.shipment_order_id and mc.is_terminal and me.event_time < v_event_time
  order by me.event_time desc
  limit 1;

  if found and not p_override_conflict then
    raise exception 'milestone_candidate_conflicts_confirmed_event: shipment order % already has a confirmed terminal milestone (%) recorded before this candidate''s own event time -- pass p_override_conflict to proceed', v_candidate.shipment_order_id, v_conflict.milestone_code
      using errcode = 'check_violation';
  end if;

  v_event := app.ingest_milestone_event(
    p_shipment_order_id := v_candidate.shipment_order_id,
    p_milestone_code := v_candidate.milestone_code,
    p_event_time := v_event_time,
    p_received_time := now(),
    p_location := app.geography_to_geojson_point(v_candidate.location),
    p_source := 'system',
    p_reason := case when p_override_conflict and found then 'confirmed_geofence_candidate_override' else 'confirmed_geofence_candidate' end,
    p_corrects_event_id := null,
    p_idempotency_key := 'milestone_candidate:' || v_candidate.id,
    p_actor_auth_user_id := p_actor_auth_user_id,
    p_actor_label := p_actor_label
  );

  update app.shipment_milestone_candidates
  set status = 'confirmed', resulting_milestone_event_id = v_event.id, reviewed_by_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_candidate_id;

  return v_event;
end;
$$;

comment on function app.confirm_milestone_candidate is
  'ATW-226G: the sole path from a staged candidate to a real app.milestone_events row -- always calls app.ingest_milestone_event with the confirming actor''s own real, RBAC-checked identity (OPS:Create), never a null/system bypass (design note 1). Idempotent on p_candidate_id via app.ingest_milestone_event''s own idempotency_key mechanism -- a retried confirm of an already-confirmed candidate raises milestone_candidate_not_pending, not a duplicate event.';

create function app.dismiss_milestone_candidate(
  p_candidate_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_review_note text
)
returns app.shipment_milestone_candidates
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_candidate app.shipment_milestone_candidates;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_candidate from app.shipment_milestone_candidates where id = p_candidate_id;
  if not found then
    raise exception 'milestone_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if v_candidate.status <> 'pending' then
    raise exception 'milestone_candidate_not_pending: % is %, not pending', p_candidate_id, v_candidate.status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_candidate.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_candidate.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_milestone_candidates
  set status = 'dismissed', reviewed_by_user_id = p_actor_auth_user_id, reviewed_at = now(), review_note = p_review_note
  where id = p_candidate_id
  returning * into v_candidate;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'dismiss_milestone_candidate',
    'app.shipment_milestone_candidates', v_candidate.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', v_candidate.shipment_order_id, 'milestone_code', v_candidate.milestone_code, 'review_note', p_review_note)
  );

  return v_candidate;
end;
$$;

create function app.confirm_exception_signal(
  p_signal_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_signal app.shipment_exception_signals;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_exception app.operational_exceptions;
begin
  select * into v_signal from app.shipment_exception_signals where id = p_signal_id;
  if not found then
    raise exception 'exception_signal_not_found: %', p_signal_id using errcode = 'no_data_found';
  end if;
  if v_signal.status <> 'pending' then
    raise exception 'exception_signal_not_pending: % is %, not pending', p_signal_id, v_signal.status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_signal.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_signal.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_exception := app.report_exception(
    p_shipment_order_id := v_signal.shipment_order_id,
    p_milestone_event_id := null,
    p_type := v_signal.exception_type,
    p_severity := v_signal.severity,
    p_description := v_signal.description,
    p_source := 'system',
    p_correlation_key := v_signal.correlation_key,
    p_actor_auth_user_id := p_actor_auth_user_id,
    p_actor_label := p_actor_label
  );

  update app.shipment_exception_signals
  set status = 'confirmed', resulting_exception_id = v_exception.id, reviewed_by_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_signal_id;

  return v_exception;
end;
$$;

comment on function app.confirm_exception_signal is
  'ATW-226G: the sole path from a staged signal to a real app.operational_exceptions row -- always calls app.report_exception with the confirming actor''s own real, RBAC-checked identity (OPS:Create), passing p_source=''system''/p_correlation_key straight through to reuse OPS-174''s own already-tested (tenant_id, shipment_order_id, correlation_key) idempotent dedup -- a retried confirm producing the identical correlation_key returns the same exception row, never a duplicate.';

create function app.dismiss_exception_signal(
  p_signal_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_review_note text
)
returns app.shipment_exception_signals
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_signal app.shipment_exception_signals;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_signal from app.shipment_exception_signals where id = p_signal_id;
  if not found then
    raise exception 'exception_signal_not_found: %', p_signal_id using errcode = 'no_data_found';
  end if;
  if v_signal.status <> 'pending' then
    raise exception 'exception_signal_not_pending: % is %, not pending', p_signal_id, v_signal.status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_signal.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_signal.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_exception_signals
  set status = 'dismissed', reviewed_by_user_id = p_actor_auth_user_id, reviewed_at = now(), review_note = p_review_note
  where id = p_signal_id
  returning * into v_signal;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'dismiss_exception_signal',
    'app.shipment_exception_signals', v_signal.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', v_signal.shipment_order_id, 'signal_type', v_signal.signal_type, 'review_note', p_review_note)
  );

  return v_signal;
end;
$$;

-- ============================================================================
-- Read projections (authenticated) -- mirror OPS-173's own app.get_shipment_milestone_
-- timeline pattern: security definer, explicit OPS:View + can_access_record gate.
-- ============================================================================

create function app.get_shipment_milestone_candidates(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_status text default 'pending')
returns table (
  id uuid, tenant_id uuid, shipment_order_id uuid, shipment_leg_id uuid, shipment_leg_stop_id uuid,
  milestone_code text, candidate_event_time timestamptz, detected_at timestamptz,
  source_canonical_event_id uuid, location_geojson jsonb, status text, dedup_key text,
  resulting_milestone_event_id uuid, reviewed_by_user_id uuid, reviewed_at timestamptz, review_note text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    c.id, c.tenant_id, c.shipment_order_id, c.shipment_leg_id, c.shipment_leg_stop_id,
    c.milestone_code, c.candidate_event_time, c.detected_at,
    c.source_canonical_event_id, case when c.location is not null then ST_AsGeoJSON(c.location)::jsonb else null end,
    c.status, c.dedup_key, c.resulting_milestone_event_id, c.reviewed_by_user_id, c.reviewed_at, c.review_note, c.created_at
  from app.shipment_milestone_candidates c
  where c.shipment_order_id = p_shipment_order_id and (p_status is null or c.status = p_status)
  order by c.detected_at desc;
end;
$$;

create function app.get_shipment_exception_signals(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_status text default 'pending')
returns table (
  id uuid, tenant_id uuid, shipment_order_id uuid, shipment_leg_id uuid, signal_type text,
  exception_type text, severity text, detected_at timestamptz, source_canonical_event_id uuid,
  location_geojson jsonb, description text, correlation_key text, status text,
  resulting_exception_id uuid, reviewed_by_user_id uuid, reviewed_at timestamptz, review_note text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    s.id, s.tenant_id, s.shipment_order_id, s.shipment_leg_id, s.signal_type,
    s.exception_type, s.severity, s.detected_at, s.source_canonical_event_id,
    case when s.location is not null then ST_AsGeoJSON(s.location)::jsonb else null end,
    s.description, s.correlation_key, s.status,
    s.resulting_exception_id, s.reviewed_by_user_id, s.reviewed_at, s.review_note, s.created_at
  from app.shipment_exception_signals s
  where s.shipment_order_id = p_shipment_order_id and (p_status is null or s.status = p_status)
  order by s.detected_at desc;
end;
$$;

create function app.get_shipment_leg_geofence_state(p_shipment_leg_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, shipment_leg_stop_id uuid, shipment_leg_id uuid,
  radius_meters numeric, dwell_seconds_before_confirm numeric, state text,
  first_entered_at timestamptz, confirmed_at timestamptz, last_evaluated_at timestamptz,
  last_evaluated_location_geojson jsonb, created_at timestamptz, updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_leg from app.shipment_legs sl where sl.id = p_shipment_leg_id;
  if not found then
    raise exception 'shipment_leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment leg %', p_actor_auth_user_id, p_shipment_leg_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    g.id, g.tenant_id, g.shipment_leg_stop_id, g.shipment_leg_id,
    g.radius_meters, g.dwell_seconds_before_confirm, g.state,
    g.first_entered_at, g.confirmed_at, g.last_evaluated_at,
    case when g.last_evaluated_location is not null then ST_AsGeoJSON(g.last_evaluated_location)::jsonb else null end,
    g.created_at, g.updated_at
  from app.shipment_leg_stop_geofence_states g
  where g.shipment_leg_id = p_shipment_leg_id
  order by g.created_at;
end;
$$;

create function app.get_shipment_leg_route_deviation_state(p_shipment_leg_id uuid, p_actor_auth_user_id uuid)
returns setof app.shipment_leg_route_deviation_states
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'shipment_leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment leg %', p_actor_auth_user_id, p_shipment_leg_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.shipment_leg_route_deviation_states where shipment_leg_id = p_shipment_leg_id;
end;
$$;

-- ============================================================================
-- Widen app.arbitrate_and_project_vehicle_position (ATW-226F, design note 2) --
-- CREATE OR REPLACE, identical signature, byte-for-byte identical body apart from one
-- added call. The already-applied 226F migration file is never edited.
-- ============================================================================

create or replace function app.arbitrate_and_project_vehicle_position(
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

  -- ATW-226G: derive geofence/route-deviation signals only from a canonical event that
  -- actually won arbitration -- never from a rejected/duplicate candidate (design note 2).
  if v_apply then
    perform app.evaluate_geofence_and_deviation_signals(p_tenant_id, p_vehicle_master_id, v_event.id, p_location, p_event_at);
  end if;

  return v_event;
end;
$$;

comment on function app.arbitrate_and_project_vehicle_position is
  'ATW-226F, widened at ATW-226G (design note 2 above): the single canonical normalization/arbitration entry point, PLUS a geofence/route-deviation evaluation call for a canonical event that wins arbitration. Every rejected candidate is still stored; vehicle_source_health is updated unconditionally, regardless of arbitration outcome, since even a rejected/disabled-source report is real evidence the source is alive.';

-- ============================================================================
-- Widen app.ingest_milestone_event (OPS-173, Phase 3, design note 3) -- CREATE OR
-- REPLACE, identical signature, one added allowed p_source value ('system'). The
-- already-applied OPS-173 migration file is never edited.
-- ============================================================================

create or replace function app.ingest_milestone_event(
  p_shipment_order_id uuid,
  p_milestone_code text,
  p_event_time timestamptz,
  p_received_time timestamptz,
  p_location jsonb,
  p_source text,
  p_reason text,
  p_corrects_event_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.milestone_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_corrected app.milestone_events;
  v_next_seq integer;
  v_event app.milestone_events;
begin
  if p_source not in ('manual', 'api', 'webhook', 'import', 'system') then
    raise exception 'milestone_invalid_source: % is not one of manual/api/webhook/import/system', p_source using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.milestone_codes where code = p_milestone_code) then
    raise exception 'milestone_unknown_code: % is not a registered milestone code', p_milestone_code using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled and can no longer receive milestone events', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if p_corrects_event_id is not null then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a correction requires a non-empty reason' using errcode = 'check_violation';
    end if;
    select * into v_corrected from app.milestone_events where id = p_corrects_event_id and shipment_order_id = p_shipment_order_id;
    if not found then
      raise exception 'milestone_event_not_found: % is not a prior event on shipment order %', p_corrects_event_id, p_shipment_order_id
        using errcode = 'no_data_found';
    end if;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    return v_event;
  end if;

  select coalesce(max(sequence_no), 0) + 1 into v_next_seq from app.milestone_events where shipment_order_id = p_shipment_order_id;

  insert into app.milestone_events (
    tenant_id, shipment_order_id, milestone_code, event_time, received_time, location, source, reason, corrects_event_id, idempotency_key, sequence_no, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_code, p_event_time, coalesce(p_received_time, now()), p_location, p_source, p_reason, p_corrects_event_id, p_idempotency_key, v_next_seq, p_actor_label
  )
  returning * into v_event;

  perform app.recalculate_shipment_milestone_projection(p_shipment_order_id);

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'ingest_milestone_event',
    'app.milestone_events', v_event.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'milestone_code', p_milestone_code, 'source', p_source, 'corrects_event_id', p_corrects_event_id)
  );

  return v_event;
exception
  when unique_violation then
    select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
    return v_event;
end;
$$;

comment on function app.ingest_milestone_event is
  'OPS-173, widened at ATW-226G (design note 3 above): identical to its own original body, plus ''system'' added to the allowed p_source vocabulary -- a GPS-derived, human-confirmed milestone (app.confirm_milestone_candidate) is honestly neither manual/api/webhook/import. Idempotent on (tenant_id, shipment_order_id, idempotency_key), never blocked by out-of-order event_time. Blocked only once the shipment is cancelled. A correction requires a non-empty reason and a real prior event on the same shipment.';

-- Widening-only ALTER (design note 3): every existing row's own source value was
-- already in the narrower set, so it remains valid under the wider one.
alter table app.milestone_events drop constraint milestone_events_source_check;
alter table app.milestone_events add constraint milestone_events_source_check check (source in ('manual', 'api', 'webhook', 'import', 'system'));

-- ============================================================================
-- Row level security -- all four new tables carry zero direct authenticated grant
-- (design note below), mirroring app.operational_exceptions' own more conservative
-- precedent (not app.canonical_telemetry_events'/226F's own direct-RLS-select
-- pattern) -- every authenticated read goes through this migration's own eight
-- security-definer functions, never a direct table select.
-- ============================================================================

alter table app.shipment_leg_stop_geofence_states enable row level security;
alter table app.shipment_leg_route_deviation_states enable row level security;
alter table app.shipment_milestone_candidates enable row level security;
alter table app.shipment_exception_signals enable row level security;

revoke execute on all functions in schema app from public;

grant select, insert, update, delete on app.shipment_leg_stop_geofence_states to service_role;
grant select, insert, update, delete on app.shipment_leg_route_deviation_states to service_role;
grant select, insert, update, delete on app.shipment_milestone_candidates to service_role;
grant select, insert, update, delete on app.shipment_exception_signals to service_role;

grant execute on function app.safe_jsonb_numeric(jsonb, text, numeric) to service_role;
grant execute on function app.safe_jsonb_boolean(jsonb, text, boolean) to service_role;
grant execute on function app.upsert_milestone_candidate(uuid, uuid, uuid, uuid, text, timestamptz, uuid, geography, text) to service_role;
grant execute on function app.upsert_exception_signal(uuid, uuid, uuid, text, text, text, uuid, geography, text, text) to service_role;
grant execute on function app.evaluate_stop_geofence(uuid, uuid, uuid, geography, timestamptz, jsonb) to service_role;
grant execute on function app.evaluate_route_deviation(uuid, uuid, uuid, geography, timestamptz, jsonb) to service_role;
grant execute on function app.evaluate_geofence_and_deviation_signals(uuid, uuid, uuid, geography, timestamptz) to service_role;
grant execute on function app.detect_overdue_geofence_arrivals(uuid) to service_role;

grant execute on function app.confirm_milestone_candidate(uuid, uuid, text, timestamptz, boolean) to authenticated, service_role;
grant execute on function app.dismiss_milestone_candidate(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.confirm_exception_signal(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.dismiss_exception_signal(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.get_shipment_milestone_candidates(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_shipment_exception_signals(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_shipment_leg_geofence_state(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_shipment_leg_route_deviation_state(uuid, uuid) to authenticated, service_role;

-- Re-grant the two widened functions exactly as their own original migrations already
-- did -- CREATE OR REPLACE preserves an existing grant across a same-signature
-- replacement, but each is re-stated here for this migration's own self-contained
-- auditability (226F's own established convention).
grant execute on function app.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) to service_role;
grant execute on function app.ingest_milestone_event(uuid, text, timestamptz, timestamptz, jsonb, text, text, uuid, text, uuid, text) to authenticated, service_role;
