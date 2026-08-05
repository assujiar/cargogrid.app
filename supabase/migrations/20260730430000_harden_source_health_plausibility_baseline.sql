-- CG-S10-ATW-031 (post-Prompt-248 codebase audit — closes `ISS-2026-025`).
--
-- `app.arbitrate_and_project_vehicle_position` rejects a report whose implied speed from
-- that source's own last known position exceeds 200 km/h (`impossible_movement`). But
-- `app.vehicle_source_health.last_location`/`last_seen_event_at` — the very baseline that
-- check measures against — were updated UNCONDITIONALLY on every candidate, including one
-- that had just been rejected as implausible.
--
-- So the check partially defeated itself: the report the rule refused still became the
-- baseline the NEXT report is measured against. Repeated, that lets a source with a valid
-- but compromised or impersonated credential walk its own plausibility baseline away from
-- the truth using reports that never become the vehicle's official position — the
-- "salami-slicing" path `ISS-2026-025` records, live-observed by `ATW-027`'s own
-- adversarial device + driver-mobile probe (a report rejected `impossible_movement` was
-- observed still updating the baseline).
--
-- ===========================================================================
-- Repair
-- ===========================================================================
--
-- `last_location`/`last_seen_event_at` now advance only when the report was NOT rejected
-- for an INTEGRITY reason — `impossible_movement`, `event_time_implausible_future`,
-- `accuracy_below_threshold`. A report that fails the plausibility rules can no longer
-- seed the baseline those same rules are enforced against.
--
-- An ARBITRATION rejection (`switch_suppressed`, `stale_event_time`) deliberately still
-- advances the baseline. Those reports are perfectly plausible; they simply did not win
-- priority or hysteresis. Freezing a legitimate secondary source's baseline while it
-- keeps moving would make its first accepted report after it becomes authoritative look
-- like a teleport and be falsely rejected — trading a real availability defect for a
-- marginal integrity gain. The distinction between the two rejection classes IS the
-- repair; treating all rejections alike would be a regression, not a stronger fix.
--
-- `last_seen_received_at` remains unconditional. It is pure liveness evidence on the real
-- server clock, never a plausibility baseline, and it is what external freshness reads
-- consume — keeping it unconditional is what stops an integrity rejection from being
-- mistakable for a dead source (`ATW-027` Finding 2's own reasoning, preserved intact).
--
-- ===========================================================================
-- Disclosed residual — NOT closed here, deliberately
-- ===========================================================================
--
-- The plausibility check is PER SOURCE. A non-authoritative source's reports never have
-- to agree with the canonical position, so a source can drift arbitrarily far from the
-- vehicle's real location using only individually-plausible steps, and when it later wins
-- arbitration (the authoritative source merely going stale is enough) the canonical
-- position jumps to it with no cross-check.
--
-- A cross-source guard — validating a switch-winning report against the CURRENT CANONICAL
-- position, not just the source's own baseline — was built and tested during this audit
-- and then deliberately withdrawn. It works, but it changes which source wins arbitration
-- in real scenarios, and the already-`VERIFIED` `advanced-tms-canonical-telemetry-
-- arbitration.sql` suite demonstrates why that is not an audit checkpoint's call to make:
-- its fixtures legitimately compress real journeys into minutes (~13 km in 60 s across
-- several tests), so any physically-honest threshold either rejects those or is too loose
-- to be meaningful. Choosing that threshold, and reworking the fixtures to be physically
-- coherent, is a real design decision about arbitration semantics — `AGENTS.md` reserves
-- that for a dedicated prompt, not an opportunistic widening here. Recorded as
-- `ISS-2026-031` with the full analysis and the working approach.
--
-- Additive and reversible: one `CREATE OR REPLACE FUNCTION` on an identical signature. No
-- table, column, index, constraint, grant, or policy is touched, and no already-applied
-- migration file is edited.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grant.

CREATE OR REPLACE FUNCTION app.arbitrate_and_project_vehicle_position(p_tenant_id uuid, p_vehicle_master_id uuid, p_source_type text, p_source_report_id uuid, p_event_at timestamp with time zone, p_received_at timestamp with time zone, p_location geography, p_speed_kmh numeric, p_heading_degrees numeric, p_accuracy_meters numeric)
 RETURNS app.canonical_telemetry_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_existing app.canonical_telemetry_events;
  v_event app.canonical_telemetry_events;
  v_current app.vehicle_current_positions;
  v_has_current boolean;
  v_source_health app.vehicle_source_health;
  -- ATW-031 (ISS-2026-025): true when this candidate was rejected for an INTEGRITY
  -- reason (implausible geometry/time/accuracy) as opposed to an arbitration reason
  -- (lost on priority/hysteresis). An integrity-rejected report must never seed the
  -- per-source plausibility baseline it just failed against.
  v_integrity_rejected boolean := false;
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

  -- ATW-031 (ISS-2026-025): classify the rejection. Only integrity rejections are
  -- withheld from the plausibility baseline below; an arbitration rejection
  -- (switch_suppressed, stale_event_time) is a perfectly plausible report that simply did
  -- not win, and MUST still advance its own source's baseline -- otherwise a legitimate
  -- secondary source's baseline would freeze while it keeps moving, and its first
  -- accepted report after becoming authoritative would be falsely rejected as impossible.
  v_integrity_rejected := v_reason in (
    'impossible_movement', 'event_time_implausible_future', 'accuracy_below_threshold'
  );

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
    set last_seen_event_at = case
          when v_integrity_rejected then app.vehicle_source_health.last_seen_event_at
          else greatest(app.vehicle_source_health.last_seen_event_at, excluded.last_seen_event_at)
        end,
        -- last_seen_received_at is pure LIVENESS evidence on the real server clock, never
        -- a plausibility baseline, so it advances unconditionally -- even a report rejected
        -- for bad geometry still proves the source is alive and talking. This is what
        -- external freshness reads consume, and keeping it unconditional is what stops an
        -- integrity rejection from being mistakable for a dead source (ATW-027 Finding 2).
        last_seen_received_at = greatest(app.vehicle_source_health.last_seen_received_at, excluded.last_seen_received_at),
        last_location = case
          when v_integrity_rejected then app.vehicle_source_health.last_location
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
$function$;


revoke execute on all functions in schema app from public;

grant execute on function app.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) to service_role;
