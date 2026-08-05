-- CG-S10-ATW-027 (Prompt 246, "Advanced TMS/WMS Integrity and Security Hardening").
-- A dedicated adversarial-probe agent live-reproduced 4 confirmed vulnerabilities plus
-- 1 informational gap against the Third-Party GPS Platform (ATW-226E/226I) and Hybrid
-- arbitration (ATW-226F/226G, widened again at CG-S10-ATW-024) source classes. This
-- migration is the minimal, targeted repair for each -- purely additive (REVOKE/GRANT
-- plus CREATE OR REPLACE FUNCTION at each function's own exact, unchanged signature).
-- No already-applied migration file is edited; no functional scope expands beyond the
-- 5 findings below (mirrors the bounded `harden_` precedent already established by
-- `20260730110000`/`20260730170000`/`20260730280000`/`20260730330000`/
-- `20260730311000`).
--
-- Findings addressed (disclosed):
--
-- 1. CRITICAL -- `app.third_party_provider_connections.webhook_secret_value` was
--    readable by ANY authenticated tenant member regardless of role/permission, via a
--    table-wide `grant select on app.third_party_provider_connections to
--    authenticated` (`20260729380000` line 544) -- RLS only scopes ROWS by tenant,
--    never COLUMNS. Live-reproduced end to end: a zero-permission tenant member read
--    the raw secret directly, computed a valid HMAC-SHA256 signature from it, and
--    successfully forged accepted telemetry via `app.ingest_third_party_provider_
--    webhook_event`, becoming the vehicle's live current position. Repaired below by
--    the identical, already-proven, already-documented pattern
--    `20260716110430_create_field_record_access.sql` established for
--    `app.users`/`email` (PLT-113/114): a column-level REVOKE alone cannot carve an
--    exception out of an existing table-level GRANT (Postgres ACLs are additive, not
--    layered with override semantics) -- the table-level SELECT grant must be revoked
--    entirely and re-granted on an explicit column list that excludes
--    `webhook_secret_value`. The column list below is enumerated from the table's own
--    live `information_schema.columns` (15 total: the 13 `20260729380000` originally
--    defined plus `auto_disabled_at`/`disabled_reason` added by `20260730110000`),
--    confirmed by direct inspection against a real disposable database, not guessed.
--    `app.register_third_party_provider_connection`/`app.rotate_third_party_provider_
--    webhook_secret` remain the only ways to ever see the raw secret (both already
--    OPS:Create/OPS:Edit-gated, unchanged here) -- their own `RETURNS TABLE(...,
--    raw_webhook_secret text, ...)` is a SECURITY DEFINER computed return value, never
--    a raw table SELECT, so this column-privilege change does not affect them at all
--    (independently confirmed: `app.rotate_third_party_provider_webhook_secret`
--    already correctly rejects a zero-permission caller today -- the bug was
--    specifically the raw table GRANT bypassing that same intended gate, not a
--    broader RBAC collapse).
-- 2. HIGH (de facto Critical combined with Finding 1) -- `app.arbitrate_and_project_
--    vehicle_position`'s `stale_event_time` guard ran with no upper bound on
--    caller-controlled `p_event_at`, and the first-ever report for a vehicle
--    ("bootstrap") applied unconditionally with zero priority/plausibility gating. A
--    single forged far-future `event_at` (e.g. 2099-01-01, live-reproduced from the
--    lowest-priority source both on a fresh vehicle's own bootstrap path AND via the
--    normal stale-fallback takeover path on an already-healthy vehicle) permanently
--    became the stored comparison baseline -- every subsequent real report from every
--    source, including the tenant's own highest-priority source, was permanently
--    rejected `stale_event_time`, with no repair RPC anywhere in the schema. Repaired
--    by rejecting any candidate whose `p_event_at` is implausibly far ahead of
--    `clock_timestamp()`, evaluated BEFORE the value can win arbitration or become the
--    stored baseline, on every path including bootstrap (the new branch sits in the
--    same unconditional first `if/elsif` chain that already computes `source_disabled`/
--    `heartbeat_no_location` regardless of `v_has_current`).
--    **Disclosed deviation from the suggested fix value:** the suggested repair text
--    proposed mirroring ADR-0011's own exact 5-minute webhook-timestamp-tolerance
--    value. Direct inspection of the already-shipped, already-`VERIFIED`,
--    already-passing db-test suites this same function feeds
--    (`scripts/db-tests/advanced-tms-geofence-route-deviation-signals.sql`,
--    ATW-226G) found real, legitimate fixture `event_at` values up to `now() +
--    interval '559 minutes'` (~9.3 hours) -- a pre-existing, unrelated,
--    already-verified convention (representing a long simulated vehicle journey
--    across many geofence checks without literal `sleep()` calls in a
--    transaction-per-statement test script), not something this bounded 5-finding
--    task may rewrite (`226_*.md` §12: "unrelated domains" are forbidden; ATW-226G's
--    own already-`VERIFIED` evidence is not this checkpoint's to re-litigate). A
--    literal 5-minute bound would have broken that already-passing, unmodified suite
--    (and several others: up to `now() + interval '11 minutes'` in
--    `advanced-tms-milestone-exception-telemetry.sql`/`advanced-tms-shipment-
--    tracking-health-writer.sql`, up to `now() + interval '90 minutes'` in
--    `advanced-tms-wms-integrated-verification.sql`). A materially larger but still
--    small, explicit, named, finite constant is used instead -- **24 hours** --
--    comfortably clear of every real fixture found repository-wide (largest: ~9.3
--    hours) while remaining an emphatic, disclosed, self-healing bound instead of the
--    original defect's true unbounded/permanent one: the live-reproduced probe
--    payloads (`2099-01-01`, `2099-06-15`, ~73 years out) are rejected by an enormous
--    margin regardless of the exact finite bound chosen, and any candidate that DOES
--    land inside the 24-hour tolerance can only ever pre-empt real traffic for that
--    same bounded window, never permanently -- real-time reports naturally catch up
--    and immediately resume winning once wall-clock time passes the stored value,
--    closing the "permanent, unbounded" defect this finding is actually about. Same
--    inline-magic-number-plus-comment STYLE as ADR-0011's own `> 300` check is
--    preserved; only the literal value differs, for the disclosed reason above.
--    **Residual finding, disclosed not fixed (out of this task's own bounded scope):**
--    `app.vehicle_source_health.last_seen_event_at`/`last_location` are still updated
--    unconditionally from `p_event_at`/`p_location` regardless of rejection reason
--    (by original design: "even a rejected/disabled-source report is real evidence
--    the source is alive," `20260729390000`'s own table comment) -- an
--    `event_time_implausible_future`-rejected candidate can therefore still poison
--    that one source's own per-source health row. Confirmed by direct inspection this
--    does NOT reopen the original defect: `app.get_vehicle_source_health`'s own
--    healthy/stale/offline classification reads only `last_seen_received_at` (always
--    real server-clock time, never caller-controlled) never `last_seen_event_at`, so
--    dispatch-board/shipment-tracking-health freshness is unaffected; the only actual
--    consumer of the poisoned `last_seen_event_at` is this same function's own
--    same-source impossible-movement check, which would simply stop evaluating
--    (`v_elapsed_seconds <= 0`, a skipped check, not a false rejection) for that one
--    source on that one vehicle going forward -- a narrow, non-blocking, non-lockout
--    weakening of a secondary defense-in-depth signal, not a recurrence of Finding 2's
--    own "permanent lockout" defect. Left unfixed here to keep this change minimal and
--    targeted at the one already-dense, already-heavily-tested function; flagged for a
--    future dedicated finding if ever prioritized.
-- 3. MEDIUM (elevated) -- only the JSON-parse step in `app.ingest_third_party_
--    provider_webhook_event` had exception handling; the `timestamp`/`latitude`/
--    `longitude`/`speed_kmh`/`heading_degrees` casts and the final INSERT's own CHECK
--    constraints (heading/speed range, `app.geojson_point_to_geography`'s own explicit
--    `spatial_coordinate_out_of_range` raise for out-of-range lat/lon) were unguarded,
--    so a validly-signed-but-malformed payload raised an uncaught exception instead of
--    this function's own documented "never raises" contract -- and because the
--    failure was uncaught, zero row landed in `third_party_provider_ingestion_
--    attempts`, invisible to both the 15-minute rate limiter and the
--    10-consecutive-failure auto-disable counter (`ATW-226I`). Repaired by widening
--    the exception boundary to a new nested `begin/exception when others` block
--    covering every field extraction/cast from `event_id` through the final INSERT
--    (an implicit savepoint -- a mid-block failure cleanly discards only that block's
--    own partial effects) -- every already-clean early-return outcome inside that
--    span (`schema_validation_failed`/`duplicate`/`quarantined`/`location_report_
--    missing_coordinates`) is a `RETURN`, not an exception, and is therefore entirely
--    unaffected; only a genuine uncaught error is now caught, recorded as a real
--    `third_party_provider_ingestion_attempts` row (`reason = 'malformed_field_
--    value'`), and returned as a clean `invalid` outcome. The same, already-reviewed
--    "never let an uncaught exception become a caller-distinguishable signature
--    oracle" convention this function's own JSON-parse block, and
--    `app.ingest_driver_mobile_report` (`ATW-226C`), already established -- not a
--    novel pattern.
-- 4. MEDIUM -- the 15-minute/10-attempt rate-limit check in `app.ingest_third_party_
--    provider_webhook_event` counted only rows matching caller-supplied `client_key`,
--    itself fed by `app/api/webhooks/third-party-gps/[connectionId]/route.ts`'s own
--    hash of `x-forwarded-for`'s first, externally-suppliable segment -- trivially
--    bypassed by varying that header per request (live-reproduced: 30 bad-signature
--    attempts against the same connection, 30 distinct client_keys, never tripped
--    `rate_limited`). Repaired by widening the count's own WHERE clause to match
--    EITHER `connection_id = p_connection_id` OR `client_key = p_client_key` --
--    `connection_id` (the caller's own chosen attack target, never rotatable without
--    abandoning the attack) is now the primary, unavoidable bound; `client_key` is
--    kept as a secondary signal (still meaningfully rate-limits a fixed-key attacker
--    probing many different connections, and remains the only signal available for a
--    wholly nonexistent `connection_id`, which is inserted with a null `connection_id`
--    FK by original design -- see that branch's own inline comment -- so cannot be
--    matched by the `connection_id` predicate).
-- 5. LOW/informational -- `anon` held `EXECUTE` on `app.ingest_third_party_provider_
--    webhook_event` (and 6 other pre-existing functions) but no `USAGE` on schema
--    `app` at all -- confirmed live: `set role anon; select app.ingest_third_party_
--    provider_webhook_event(...)` raised `permission denied for schema app` before
--    ever reaching the function body. Fails safe today (the real route always uses a
--    service-role client), but the repeatedly-documented "anon-callable" claim
--    (`ATW-226C`/`226E`/`226I`) had never been live-verified end to end and would
--    silently break a future direct-PostgREST/anon-key caller or a route refactor
--    that assumed the anon grant alone was sufficient. Confirmed by direct inspection
--    (`grep` across every migration, `has_schema_privilege('anon','app','USAGE')`)
--    that `USAGE ON SCHEMA app` was never granted to `anon` anywhere in this
--    repository for any other reason -- this is a real, standalone gap, not a
--    double-grant. `USAGE` on a schema only makes an ALREADY-granted `EXECUTE`/
--    `SELECT` actually reachable; it grants no new object-level privilege on its own,
--    so this cannot newly expose anything `anon` does not already hold an explicit
--    grant on.
--
-- Per ERR-2026-004: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` statement before its own explicit grants.

-- ============================================================================
-- Finding 1 (CRITICAL): column-scoped SELECT on
-- app.third_party_provider_connections.
-- ============================================================================

revoke select on app.third_party_provider_connections from authenticated;
grant select (
  id, tenant_id, provider_code, integration_mode, poll_cursor, status,
  consecutive_failure_count, last_successful_ingest_at, record_version, created_by,
  created_at, updated_at, auto_disabled_at, disabled_reason
) on app.third_party_provider_connections to authenticated;

-- ============================================================================
-- Finding 2 (HIGH): app.arbitrate_and_project_vehicle_position -- CREATE OR REPLACE,
-- identical signature, full body carried forward byte-for-byte from its own current
-- (CG-S10-ATW-024-widened, 20260730320000) version, with exactly one new elsif
-- branch added to the first reason-computation if/elsif chain (design note above).
-- The applied migration file itself is never edited.
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
  v_th_shipment_id uuid;
begin
  -- CG-S10-ATW-024 fix-pass addition (HIGH-severity concurrency finding, adversarial
  -- review): taken here, BEFORE even the dedup existing-row check below, so it closes
  -- two distinct TOCTOU gaps in one critical section, not just one:
  --  (a) the dedup check itself (`select ... if found then return`) followed much later
  --      by a plain `INSERT` with no `ON CONFLICT` on `canonical_telemetry_events` --
  --      two genuinely concurrent FIRST-time submissions of the identical
  --      (source_type, source_report_id) (a real scenario: a webhook retried by a slow
  --      third-party platform before it saw the first ACK) could both observe "not
  --      found" and both attempt the INSERT; the loser would hit a raw, uncaught
  --      unique_violation on canonical_telemetry_events_dedup_unique that -- since
  --      every caller here (`perform`, not a wrapped `begin/exception` block in any of
  --      the three ingestion RPCs) never catches it -- would propagate up and roll back
  --      the caller's own ALREADY-EXECUTED raw report insert too, directly contradicting
  --      this repository's own "canonicalization never breaks raw ingestion" guarantee
  --      (20260729390000's own design note 2).
  --  (b) the read-decide-then-blind-write race (the finding's own primary subject): the
  --      read of vehicle_current_positions below, the arbitration decision it feeds, and
  --      the later unconditional `INSERT ... ON CONFLICT (vehicle_master_id) DO UPDATE
  --      SET event_at = excluded.event_at, ...` (no freshness WHERE guard) together form
  --      a read-decide-then-blind-write TOCTOU gap: two concurrent calls for the SAME
  --      vehicle can both read the "no current row"/"current is source X" snapshot
  --      before either commits, each independently decide to apply, and then commit in
  --      the REVERSE of their own event_at order -- the call that decided using the
  --      older event_at can commit last and unconditionally overwrite an
  --      already-committed newer position. This was live-reproduced against a verbatim
  --      copy of this function's own read/decide/write shape (two concurrent sessions,
  --      older-event_at session sleeping between its own read and write) and directly
  --      violates this migration's own inherited design note 3 guarantee ("current
  --      position must never move backward to older recorded_at merely because it
  --      arrived later," 226_*.md §25).
  -- A per-vehicle session-transaction advisory lock, held until this call's own
  -- transaction commits or rolls back, fully serializes every concurrent arbitration
  -- attempt (dedup check through final write) for the same vehicle -- the identical "no
  -- single row to lock, cross-row-decision consistency" technique
  -- app.ship_confirm_wms_outbound_shipment already established for cross-shipment ship-confirm
  -- serialization (20260730260000_create_advanced_tms_wms_outbound.sql,
  -- pg_advisory_xact_lock keyed on the shared decision scope, salt 0). A concurrent
  -- caller blocks here until the prior call's transaction ends, so every read below
  -- always observes either a fully-committed or a not-yet-started concurrent write for
  -- this vehicle, never one concurrently in-flight -- closing both races without
  -- weakening any existing decision logic (dedup/rank/hysteresis/impossible-movement)
  -- below, which still runs unchanged against a now-consistent snapshot.
  perform pg_advisory_xact_lock(hashtextextended(p_vehicle_master_id::text, 0));

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
  elsif p_event_at > clock_timestamp() + interval '24 hours' then
    -- CG-S10-ATW-027 fix-pass addition (adversarial review, Finding 2, HIGH): closes an
    -- unbounded, priority-blind, PERMANENT arbitration lockout. Unconditional (checked
    -- regardless of v_has_current, so it applies on the bootstrap/first-ever-report path
    -- too, per the finding's own explicit requirement) and evaluated here, in the same
    -- reason-computation chain that already governs whether v_apply can ever become
    -- true below -- an implausible-future candidate can therefore never win arbitration
    -- or become the stored app.vehicle_current_positions.event_at comparison baseline
    -- that stale_event_time (the next branch) and every future candidate's own
    -- v_has_current/p_event_at <= v_current.event_at check depend on. Same inline
    -- magic-number-plus-comment style as ADR-0011's own `> 300` webhook-timestamp
    -- tolerance check (app.verify_webhook_signature/app.verify_third_party_provider_
    -- webhook_signature) -- this migration's own header discloses why the literal
    -- value differs (24 hours, not 5 minutes): a 5-minute bound would break several
    -- already-shipped, already-VERIFIED db-test suites' own pre-existing, unrelated
    -- multi-hour synthetic-elapsed-time fixture convention (largest found: ~9.3 hours,
    -- ATW-226G's own geofence suite), while 24 hours remains a small, explicit,
    -- self-healing bound that closes the true defect (permanent/unbounded poisoning)
    -- regardless -- the live-reproduced probe payloads (~73 years out) are rejected by
    -- an enormous margin under either value.
    v_reason := 'event_time_implausible_future';
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

  -- CG-S10-ATW-024 addition (design note 7): resolve every shipment currently
  -- assigned this vehicle (zero, one, or more than one) and recompute its
  -- tracking-health projection. Wrapped in its own sub-block so a tracking-health
  -- recompute failure can never roll back the already-accepted canonical
  -- telemetry write (or the ATW-226G geofence evaluation) above -- the identical
  -- "canonicalization never breaks raw ingestion" guarantee this function's own
  -- design note 2 (20260729390000) already established, extended transitively to
  -- this new consumer.
  begin
    for v_th_shipment_id in
      select ra.shipment_order_id
      from app.resource_assignments ra
      where ra.resource_id = p_vehicle_master_id and ra.role = 'vehicle' and ra.is_current and ra.status = 'active'
    loop
      perform app.recalculate_shipment_tracking_health(v_th_shipment_id);
    end loop;
  exception
    when others then
      null;
  end;

  return v_event;
end;
$$;

comment on function app.arbitrate_and_project_vehicle_position is
  'ATW-226F, widened at ATW-226G (geofence/route-deviation evaluation), CG-S10-ATW-024 (design note 7: app.shipment_tracking_health recompute, plus the per-vehicle/per-shipment advisory-lock TOCTOU closures) and again at CG-S10-ATW-027 (Finding 2: any candidate whose p_event_at is more than 24 hours ahead of clock_timestamp() is rejected event_time_implausible_future, evaluated unconditionally -- including on the bootstrap/first-ever-report path -- before it can win arbitration or become the stored current-position comparison baseline, closing a real, live-reproduced permanent/unbounded arbitration-lockout defect). Every rejected candidate is still stored; vehicle_source_health is updated unconditionally, regardless of arbitration outcome, since even a rejected/disabled-source report is real evidence the source is alive.';

-- ============================================================================
-- Findings 3 + 4: app.ingest_third_party_provider_webhook_event -- CREATE OR
-- REPLACE, identical signature, full body carried forward byte-for-byte from its own
-- current (ATW-226I-widened, 20260730110000) version, with: (Finding 4) the
-- rate-limit count's own WHERE clause widened to match connection_id in addition to
-- client_key, and (Finding 3) field extraction/casting through the final INSERT
-- wrapped in a new nested begin/exception block. The applied migration file itself is
-- never edited.
-- ============================================================================

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

  -- CG-S10-ATW-027 fix-pass addition (adversarial review, Finding 4, MEDIUM): widened
  -- from client_key-only to (connection_id OR client_key) -- client_key is fully
  -- caller-controlled (the real HTTP route derives it from x-forwarded-for's own
  -- externally-suppliable first hop), so a client_key-only count is trivially bypassed
  -- by varying it per request (live-reproduced: 30 distinct client_keys against the
  -- same connection, 0/30 ever tripped rate_limited). connection_id is the caller's
  -- own chosen attack target and cannot be rotated without abandoning the attack, so it
  -- is now the primary, unavoidable bound; client_key is kept as a secondary signal --
  -- still the only signal available for a wholly nonexistent connection_id, which the
  -- "invalid: connection_not_active" branch below deliberately records with a null
  -- connection_id FK (see that branch's own inline comment), so it can never be matched
  -- by the connection_id predicate on its own.
  select count(*) into v_recent_bad_count
  from app.third_party_provider_ingestion_attempts
  where result = 'invalid' and occurred_at > now() - interval '15 minutes'
    and (connection_id = p_connection_id or client_key = p_client_key);
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

  -- CG-S10-ATW-027 fix-pass addition (adversarial review, Finding 3, MEDIUM): widens
  -- the exception boundary from "JSON-parse only" to cover every field
  -- extraction/cast below AND the final INSERT's own CHECK constraints -- a
  -- validly-signed-but-malformed payload (non-numeric/out-of-range latitude,
  -- longitude, speed_kmh, heading_degrees, or a non-timestamp `timestamp` string) was
  -- live-reproduced raising an uncaught exception instead of this function's own
  -- documented "never raises" contract, and because the failure was uncaught, zero
  -- row landed in third_party_provider_ingestion_attempts -- invisible to both the
  -- rate limiter above and ATW-226I's own auto-disable counter. This begin/exception
  -- block is an implicit savepoint: every already-clean early RETURN inside it
  -- (schema_validation_failed/duplicate/quarantined/location_report_missing_
  -- coordinates) is normal control flow, not an exception, and is entirely
  -- unaffected -- only a genuine uncaught error (a bad cast, or
  -- app.geojson_point_to_geography's own explicit spatial_coordinate_out_of_range
  -- raise, or a table CHECK violation on the final INSERT) is now caught here.
  begin
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
  exception
    when others then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'malformed_field_value', v_payload);
      return query select 'invalid'::text, null::uuid;
      return;
  end;

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
  'ATW-226E, widened at ATW-226F (canonicalization, app.arbitrate_and_project_vehicle_position), ATW-226I (harden, 10-consecutive-signature-failure auto-disable) and again at CG-S10-ATW-027 (Finding 3: the exception boundary now also covers every field extraction/cast and the final INSERT''s own CHECK constraints, so a validly-signed-but-malformed payload always returns a clean invalid outcome with a recorded ingestion_attempts row, never an uncaught exception; Finding 4: the rate-limit count is now bound to connection_id in addition to client_key). Quarantines an unmapped external_vehicle_id rather than dropping it, and treats a replayed provider_event_id as a distinct duplicate outcome, never an error.';

-- ============================================================================
-- Finding 5 (LOW/informational): anon lacks USAGE on schema app. Per ERR-2026-004
-- convention, positioned with this migration's other explicit grants, after its own
-- restated `revoke execute on all functions in schema app from public` below.
-- ============================================================================

revoke execute on all functions in schema app from public;

grant usage on schema app to anon;

-- Re-grants exactly as each function's own owning migration already did -- CREATE OR
-- REPLACE preserves a prior grant automatically (unlike DROP+CREATE), so these are
-- restated only for this migration's own self-contained auditability (matches
-- 20260730110000/20260730320000's own identical practice), not structurally required.
grant execute on function app.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) to service_role;
grant execute on function app.ingest_third_party_provider_webhook_event(uuid, text, text, bigint, text) to anon, authenticated, service_role;
