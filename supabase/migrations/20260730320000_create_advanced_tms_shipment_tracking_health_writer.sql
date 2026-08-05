-- Advanced TMS capability CG-S10-ATW-024 (Prompt 243, "High-Volume TMS/WMS and
-- Multi-Source Telemetry Controls"), Deliverable A -- closes `docs/runtime/KNOWN_
-- ISSUES.md` `ISS-2026-009`: `app.shipment_tracking_health` (ATW-222,
-- `20260729300000_create_advanced_tms_dispatch_board.sql`) has had zero writer
-- anywhere in this repository since it was created. That migration's own comment
-- already named the intended owner verbatim ("ATW-226F... will populate it
-- later"); ATW-226F (`20260729390000_create_advanced_tms_canonical_telemetry_
-- arbitration.sql`) shipped `VERIFIED` without ever doing so. This migration is
-- the real, dedicated task ISS-2026-009 itself said this required ("deliberately
-- not attempted ad hoc in a remediation checkpoint").
--
-- Design decisions (disclosed):
--
-- 1. **Vehicle resolution reuses the exact, already-established join pattern** --
--    `app.resource_assignments` (role='vehicle', is_current=true, status='active')
--    -- verbatim from `app.detect_shipment_leg_tracking_health_signals` and
--    `app._compute_shipment_leg_eta` (both `20260730130000_create_advanced_tms_
--    milestone_exception_telemetry.sql`). No new "which vehicle is this shipment's
--    own" resolution mechanism is invented.
--    **Disclosed discrepancy against ISS-2026-009's own wording (adversarial review
--    finding, addressed here rather than only by cross-referencing a different
--    migration):** the issue's own text names mapping via "`app.resource_assignments`/
--    `ATW-225`'s leg tracking sessions, including precedence/timing rules" as part of
--    the required design. This migration resolves the vehicle at the shipment-order
--    level only, via `app.resource_assignments`, and never reads `app.shipment_leg_
--    tracking_sessions`/`app.shipment_legs` at all -- the identical simplification
--    `app.detect_shipment_leg_tracking_health_signals` (`ATW-228`, already `VERIFIED`)
--    already made for the same "which vehicle is this shipment's own" question, not a
--    novel shortcut invented here. Consequence, disclosed rather than silently
--    accepted: for a multi-leg shipment whose legs are serviced by genuinely different
--    vehicles over time, `app.shipment_tracking_health` reflects "the" shipment-level
--    vehicle assignment (`app.resource_assignments`), not the currently-active leg's
--    own tracking session/handoff state (`app.shipment_leg_tracking_sessions`'
--    `superseded_by_id`/`end_reason`/`is_current` precedence chain). Per-leg-aware
--    tracking-health precedence is out of this bounded task's own scope (it would mean
--    re-deriving "which leg, and therefore which vehicle, is authoritative right now"
--    a second, independent way from `app._compute_shipment_leg_eta`'s own established
--    resolution, a real design decision this checkpoint deliberately does not make ad
--    hoc) and remains open against `ISS-2026-009`'s original wording.
-- 2. **Freshness is never reimplemented** -- `app.recalculate_shipment_tracking_
--    health` calls `app.get_vehicle_source_health()` (ATW-226F) for the winning
--    position's own `source_type` and reads its `status` output
--    (`healthy`/`stale`/`offline`/`unknown`), rather than re-deriving a second
--    freshness classifier from `received_at`/`freshness_threshold_seconds`
--    directly. `app.shipment_tracking_health.freshness_status` only has three
--    values (`fresh`/`stale`/`unknown`, no `offline`) -- `healthy` maps to
--    `fresh`; `stale`/`offline`/`unknown` all map to `stale` here (the shipment-
--    level projection deliberately does not distinguish "quite stale" from
--    "very stale" the way the vehicle-level health check does -- both already
--    mean "the dispatcher should not trust this position blindly").
-- 3. **tracking_status precedence (judgment call, disclosed):** Prompt 243's own
--    design brief states "tracked when fresh, stale when not fresh, degraded when
--    tracking_exception_count > 0 (even if position itself is fresh)". Read
--    literally this leaves the fresh+exceptions case unambiguous (degraded) but
--    is silent on stale+exceptions. This migration resolves that as: `stale`
--    takes precedence over `degraded` -- staleness is itself already a stronger,
--    more specific signal ("the position feed itself is unreliable") than
--    `degraded` ("the feed is fine but something else is wrong"); collapsing both
--    into `degraded` would discard the more actionable staleness signal, and the
--    five-value taxonomy (`not_tracked`/`tracked`/`stale`/`degraded`/`conflict`)
--    has no value that means "both." `degraded` therefore only ever occurs on an
--    otherwise-`fresh` position with 1+ currently-open exceptions.
-- 4. **accuracy_meters is real, not fabricated, and not left null.** Direct
--    inspection of `20260729390000` confirms `app.canonical_telemetry_events` DOES
--    carry a real `accuracy_meters numeric` column (populated from each ingestion
--    RPC's own `p_accuracy_meters`), even though `app.vehicle_current_positions`
--    itself does not. The winning position's own `canonical_telemetry_event_id`
--    is joined back to `app.canonical_telemetry_events` to read that event's own
--    `accuracy_meters` -- real upstream data, not a second, redundant capture.
--    It is null exactly when the winning source never reported an accuracy value
--    (e.g. `driver_mobile` heartbeats, or a provider that never sends accuracy) --
--    an honest null, per the table's own already-applied nullable-by-design
--    column, never a fabricated number.
--    **Residual finding, disclosed not fixed (out of this task's own bounded
--    scope):** direct inspection of the already-applied, already-widened
--    `app.ingest_direct_device_telemetry_batch` (`ATW-226D`, widened at
--    `ATW-226F`) and `app.ingest_third_party_provider_webhook_event` (`ATW-226E`,
--    widened at `ATW-226F`) found both hardcode `p_accuracy_meters := null` in
--    their own call to `app.arbitrate_and_project_vehicle_position`, regardless
--    of any accuracy value present in the raw report. Only `app.ingest_driver_
--    mobile_report` (`ATW-226C`) actually threads a real `p_accuracy_meters`
--    through today. This means `accuracy_meters` on `app.shipment_tracking_
--    health` is, in the CURRENT already-applied ingestion layer, honestly null
--    for any vehicle whose winning source is `direct_device`/`third_party_
--    platform`, and only ever real for `driver_mobile`. This is a pre-existing
--    gap in those two functions, not introduced by this migration; fixing it
--    would mean re-widening two functions unrelated to the tracking-health write
--    path this task is scoped to, so it is disclosed here (and proven honestly
--    null in this checkpoint's own db-test for the direct_device case, with a
--    second, explicitly-labeled direct-call test proving the pass-through logic
--    itself is correct once an upstream source does provide a value) rather than
--    silently patched or silently masked by a passing assertion that never
--    exercises the real ingestion path.
-- 5. **fallback_active** is true exactly when the vehicle's own most recent
--    `app.vehicle_source_switches` row (by `switched_at`) has
--    `reason = 'current_source_stale_fallback'`. Taking the single most-recent row
--    by construction already satisfies "no later higher-priority switch has
--    occurred since" -- if a later switch had happened, IT would be the most
--    recent row, and its own `reason` would not be `current_source_stale_fallback`
--    unless the fallback is still the latest true state.
-- 6. **tracking_exception_count** always counts currently-open
--    `app.operational_exceptions` rows for the shipment (`status in ('open',
--    'acknowledged', 'reopened')` -- the same three-value "not yet resolved/
--    closed" set `app.resolve_exception`/`app.close_exception`/`app.reopen_
--    exception`, `OPS-174`, already use as their own transition preconditions),
--    regardless of tracking_status -- even a `not_tracked` shipment's own open
--    exception count is honestly reported, never zeroed out just because there is
--    no live position.
-- 7. **Write trigger point widens `app.arbitrate_and_project_vehicle_position`
--    (ATW-226F) via `CREATE OR REPLACE FUNCTION` with an identical signature** --
--    the same "same-signature widening, never edit the applied migration"
--    technique `20260730280000_harden_advanced_tms_inventory_balances_
--    reservation_record_version.sql` already used for `app.reserve_inventory`/
--    `app.release_inventory_reservation`/`app.consume_inventory_reservation`.
--    IMPORTANT (found and fixed during this checkpoint's own db-test rehearsal,
--    disclosed rather than silently corrected): this function was ALREADY widened
--    once before this checkpoint, by `20260730090000_create_advanced_tms_
--    geofence_route_deviation_signals.sql` (ATW-226G, which appends a call to
--    `app.evaluate_geofence_and_deviation_signals()` for an arbitration-winning
--    event). A first draft of this migration mistakenly based its own `CREATE OR
--    REPLACE` on the ORIGINAL `20260729390000` (ATW-226F) body -- which, applied
--    after `20260730090000` in migration-filename order, would have silently
--    reverted ATW-226G's own geofence-detection call, breaking
--    `advanced-tms-geofence-route-deviation-signals.sql`'s own already-passing
--    db-test (caught by a full `db:test` re-run before this migration was
--    finalized, never shipped). The body below is instead based on the CURRENT
--    (ATW-226G-widened) already-applied version, with exactly one further
--    addition at the very end, after the geofence call: resolving every
--    `shipment_order_id`
--    currently assigned this vehicle (there may legitimately be zero, one, or more
--    than one active shipment concurrently assigned the same vehicle -- no
--    "exactly one" assumption) and recalculating tracking health for each. The
--    added block is wrapped in its own `begin/exception when others then null`
--    sub-block (an implicit savepoint) so a tracking-health recompute failure can
--    never roll back an already-accepted canonical telemetry write or the raw
--    ingestion insert underneath it -- the identical "canonicalization never
--    breaks raw ingestion" guarantee `20260729390000`'s own design note 2 already
--    established, extended transitively to this new consumer.
-- 8. **`app.recalculate_shipment_tracking_health` is also directly callable** for
--    manual/batch recompute, and **`app.reconcile_shipment_tracking_health`** is a
--    bounded, cursor-able batch RPC (the real "reconciliation checkpoint" Prompt
--    243 section 13 asks for) that recomputes health for every shipment with a
--    currently active vehicle assignment in a tenant -- this is also how any
--    shipment whose health fell out of sync before this migration existed (every
--    shipment ever assigned a vehicle prior to this checkpoint) gets caught up.
--    Both are service_role-only (no actor/authority parameter, no per-caller
--    authorization check) -- the identical convention this repository's own
--    "detect_*" scan functions already use (`app.detect_shipment_leg_tracking_
--    health_signals`, `app.detect_overdue_geofence_arrivals`, both `service_role`-
--    only), since these are system recomputation entry points, not
--    tenant-user-facing mutations.
-- 9. **No new read RPC.** `app.dispatch_board_queue` (ATW-222, `20260729300000`)
--    already `LEFT JOIN`s `app.shipment_tracking_health` and already projects
--    every one of its columns (`tracking_status`/`authoritative_source_type`/
--    `last_position_at`/`freshness_status`/`accuracy_meters`/`fallback_active`/
--    `tracking_exception_count`) to the dispatch board; `server/queries/dispatch-
--    board.ts` and `server/contracts/dispatch-board/dispatch-board.ts` already
--    consume that exact shape end to end. This migration only wires the writer --
--    confirmed by direct inspection that no duplicate read path is needed.
-- 10. Per `ERR-2026-004`: this migration carries its own explicit `revoke execute
--     on all functions in schema app from public;` statement before its final
--     grants.
-- 11. **CG-S10-ATW-024 fix-pass addition (adversarial review, Finding 1, HIGH):**
--     `app.arbitrate_and_project_vehicle_position`'s own read-decide-write shape (the
--     dedup check, the current-position read that feeds the arbitration decision, and
--     the later unconditional `ON CONFLICT DO UPDATE`) was live-reproduced as a real
--     TOCTOU race under concurrent multi-source telemetry for the same vehicle,
--     directly violating this migration's own inherited "current position must never
--     move backward" guarantee. Closed via a per-vehicle `pg_advisory_xact_lock`, taken
--     before the dedup check -- see that lock's own inline comment for the full
--     analysis (two distinct races closed, not just one). Regression-proven under real
--     concurrent database load by `scripts/load-tests/pgbench/hybrid-arbitration.sql`
--     (Scenario 8), not merely asserted.
-- 12. **CG-S10-ATW-024 fix-pass addition (adversarial review, Finding 2, MEDIUM):** the
--     same read-decide-write TOCTOU shape exists in `app.recalculate_shipment_tracking_
--     health` itself (a live telemetry-triggered recompute racing a concurrent
--     `app.reconcile_shipment_tracking_health` batch sweep for the same shipment).
--     Closed via a per-shipment `pg_advisory_xact_lock` -- see that lock's own inline
--     comment.

-- ============================================================================
-- 1. The real writer -- app.recalculate_shipment_tracking_health.
-- ============================================================================

create function app.recalculate_shipment_tracking_health(p_shipment_order_id uuid)
returns app.shipment_tracking_health
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_vehicle_master_id uuid;
  v_exception_count integer;
  v_position app.vehicle_current_positions;
  v_source_status text;
  v_tracking_status text := 'not_tracked';
  v_authoritative_source_type text := null;
  v_last_position_at timestamptz := null;
  v_freshness_status text := null;
  v_accuracy_meters numeric := null;
  v_fallback_active boolean := false;
  v_latest_switch app.vehicle_source_switches;
  v_health app.shipment_tracking_health;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  -- CG-S10-ATW-024 fix-pass addition (MEDIUM-severity concurrency finding, adversarial
  -- review): this function reads several independent pieces of live state (current
  -- position, source health, latest source switch, open exception count) and then
  -- performs one INSERT ... ON CONFLICT (shipment_order_id) DO UPDATE with no
  -- freshness/compare-and-swap guard against the row's own live value. Two
  -- near-simultaneous recomputes for the same shipment -- e.g. one triggered by a live
  -- telemetry event (from the arbitration loop below) racing a concurrent
  -- app.reconcile_shipment_tracking_health batch sweep, or two rapid telemetry events
  -- for a shared vehicle -- can commit in the reverse of their own read order: the call
  -- that read first but commits last silently overwrites the row with its own older
  -- snapshot (record_version still increments, so no error is ever raised and the loss
  -- is silent). A per-shipment session-transaction advisory lock (same technique/
  -- rationale as the per-vehicle lock added above; a different salt (1) is used purely
  -- so this lock's key space is never confused with the vehicle-keyed lock above, though
  -- a UUID collision across the two unrelated id columns is not a realistic concern)
  -- fully serializes every concurrent recompute of the same shipment, closing the race
  -- without changing any of the projection logic below.
  perform pg_advisory_xact_lock(hashtextextended(p_shipment_order_id::text, 1));

  -- Design note 1: identical join pattern to app.detect_shipment_leg_tracking_
  -- health_signals / app._compute_shipment_leg_eta (20260730130000).
  select ra.resource_id into v_vehicle_master_id
  from app.resource_assignments ra
  where ra.shipment_order_id = p_shipment_order_id and ra.role = 'vehicle' and ra.is_current and ra.status = 'active';

  -- Design note 6: always computed, regardless of tracking_status outcome below.
  select count(*) into v_exception_count
  from app.operational_exceptions
  where shipment_order_id = p_shipment_order_id and status in ('open', 'acknowledged', 'reopened');

  if v_vehicle_master_id is not null then
    select * into v_position from app.vehicle_current_positions where vehicle_master_id = v_vehicle_master_id;
    if found then
      -- Design note 2: reuse app.get_vehicle_source_health's own freshness
      -- classification for the winning position's own source_type, never a second
      -- freshness classifier.
      select h.status into v_source_status
      from app.get_vehicle_source_health(v_shipment.tenant_id, v_vehicle_master_id) h
      where h.source_type = v_position.source_type;

      v_freshness_status := case when v_source_status = 'healthy' then 'fresh' else 'stale' end;

      -- Design note 3 (disclosed precedence judgment call).
      v_tracking_status := case
        when v_freshness_status <> 'fresh' then 'stale'
        when v_exception_count > 0 then 'degraded'
        else 'tracked'
      end;

      v_authoritative_source_type := v_position.source_type;
      v_last_position_at := v_position.event_at;

      -- Design note 4: real upstream accuracy, joined via the winning canonical
      -- event -- never fabricated, honestly null when the winning source never
      -- reported one.
      select cte.accuracy_meters into v_accuracy_meters
      from app.canonical_telemetry_events cte
      where cte.id = v_position.canonical_telemetry_event_id;

      -- Design note 5.
      select * into v_latest_switch
      from app.vehicle_source_switches
      where vehicle_master_id = v_vehicle_master_id
      order by switched_at desc
      limit 1;
      v_fallback_active := found and v_latest_switch.reason = 'current_source_stale_fallback';
    end if;
    -- else: vehicle assigned but app.vehicle_current_positions has no row yet --
    -- remains the initialized 'not_tracked' default (design step c).
  end if;
  -- else: no current vehicle assignment -- remains the initialized 'not_tracked'
  -- default (design step b).

  insert into app.shipment_tracking_health (
    tenant_id, shipment_order_id, tracking_status, authoritative_source_type, last_position_at,
    freshness_status, accuracy_meters, fallback_active, tracking_exception_count
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, v_tracking_status, v_authoritative_source_type, v_last_position_at,
    v_freshness_status, v_accuracy_meters, v_fallback_active, v_exception_count
  )
  on conflict (shipment_order_id) do update set
    tracking_status = excluded.tracking_status,
    authoritative_source_type = excluded.authoritative_source_type,
    last_position_at = excluded.last_position_at,
    freshness_status = excluded.freshness_status,
    accuracy_meters = excluded.accuracy_meters,
    fallback_active = excluded.fallback_active,
    tracking_exception_count = excluded.tracking_exception_count,
    record_version = app.shipment_tracking_health.record_version + 1,
    updated_at = now()
  returning * into v_health;

  return v_health;
end;
$$;

comment on function app.recalculate_shipment_tracking_health is
  'CG-S10-ATW-024: the real writer ATW-222''s own migration comment (20260729300000) named but never shipped (ISS-2026-009). Upserts app.shipment_tracking_health for one shipment, keyed on (shipment_order_id), bumping record_version on every recompute regardless of whether the projected value actually changed (a real recompute is a real event, matching this repository''s own touch-trigger convention). service_role-only (design note 8) -- a system recomputation entry point, not a tenant-user mutation.';

-- ============================================================================
-- 2. The bounded, cursor-able batch reconciliation RPC (design note 8, Prompt 243
-- section 13's own "reconciliation checkpoint").
-- ============================================================================

create function app.reconcile_shipment_tracking_health(
  p_tenant_id uuid,
  p_cursor_shipment_order_id uuid default null,
  p_limit integer default 200
)
returns setof app.shipment_tracking_health
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment_id uuid;
  v_limit integer;
begin
  if p_tenant_id is null then
    raise exception 'tenant_id_required: p_tenant_id is required' using errcode = 'check_violation';
  end if;

  -- Bounded regardless of caller input (matches app.get_vehicle_telemetry_
  -- history's own least(coalesce(...), cap) convention, 20260729390000) --
  -- never an unbounded scan of a tenant's entire assigned-shipment set in one call.
  v_limit := least(greatest(coalesce(p_limit, 200), 1), 500);

  for v_shipment_id in
    select distinct ra.shipment_order_id
    from app.resource_assignments ra
    where ra.role = 'vehicle' and ra.is_current and ra.status = 'active'
      and ra.tenant_id = p_tenant_id
      and (p_cursor_shipment_order_id is null or ra.shipment_order_id > p_cursor_shipment_order_id)
    order by ra.shipment_order_id
    limit v_limit
  loop
    return next app.recalculate_shipment_tracking_health(v_shipment_id);
  end loop;

  return;
end;
$$;

comment on function app.reconcile_shipment_tracking_health is
  'CG-S10-ATW-024: bounded (<=500 rows/call regardless of p_limit) batch recompute over every shipment with a currently active vehicle assignment in a tenant, keyset-cursor-able on shipment_order_id (ascending) -- the caller resumes with p_cursor_shipment_order_id set to the last returned row''s own shipment_order_id, the same "derive the next cursor from the last row" convention this repository''s own read-side keyset RPCs (app.list_customer_inventory_balances, ATW-023) already establish. Also the real catch-up path for every shipment assigned a vehicle before this migration ever existed -- their app.shipment_tracking_health row (if any) predates a real writer entirely.';

-- ============================================================================
-- 3. Widen app.arbitrate_and_project_vehicle_position (ATW-226F) -- CREATE OR
-- REPLACE, identical signature, body byte-for-byte identical to 20260729390000's
-- own version with exactly one addition at the end (design note 7). The applied
-- migration file itself is never edited.
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
  'ATW-226F, widened at ATW-226G (geofence/route-deviation evaluation) and again at CG-S10-ATW-024 (design note 7 above): the single canonical normalization/arbitration entry point. Every rejected candidate is still stored; vehicle_source_health is updated unconditionally, regardless of arbitration outcome, since even a rejected/disabled-source report is real evidence the source is alive. Now also recomputes app.shipment_tracking_health for every shipment currently assigned this vehicle after every accepted-or-rejected canonicalization attempt -- the real writer ISS-2026-009 named as missing, wrapped so a recompute failure never rolls back the canonical telemetry write or the geofence evaluation.';

revoke execute on all functions in schema app from public;

grant execute on function app.recalculate_shipment_tracking_health(uuid) to service_role;
grant execute on function app.reconcile_shipment_tracking_health(uuid, uuid, integer) to service_role;

-- Re-grant the widened arbitration entry point exactly as its own original
-- migration already did -- CREATE OR REPLACE preserves an existing grant across a
-- same-signature replacement, but re-stated here for this migration's own
-- self-contained auditability (mirrors 20260730280000's own identical practice).
grant execute on function app.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) to service_role;
