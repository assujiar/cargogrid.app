-- Advanced TMS capability ATW-228 (CG-S10-ATW-009, Prompt 228, "Advanced Milestone
-- and Exception with Multi-Source Telemetry" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). Extends milestone
-- and exception records with real source confidence/freshness provenance, a genuinely
-- new tracking-health exception detector, dependency-aware live ETA, and a bounded
-- schedule-rebaseline operation for unstarted legs -- all without ever letting
-- telemetry become authoritative shipment truth by itself (this prompt's own §24
-- business rule).
--
-- Design boundary (disclosed):
--
-- 1. **Confidence/freshness provenance is computed once, at confirmation time, from
--    the real canonical telemetry event backing a candidate/signal** -- never
--    fabricated for a manually-filed milestone/exception (both stay honestly null).
--    `app.evaluate_telemetry_confidence_and_freshness` is the one shared formula both
--    `app.confirm_milestone_candidate` and `app.confirm_exception_signal` (both
--    `ATW-226G`) now call, reusing `app.resolve_tenant_tracking_source_policy`'s own
--    `freshness_threshold_seconds`/`accuracy_threshold_meters` (`ATW-226A`) and the
--    identical 1x/3x freshness banding `app.get_vehicle_source_health` (`ATW-226F`)
--    already established -- not a forked constant or a third banding formula.
-- 2. **`app.milestone_events`/`app.operational_exceptions` are widened additively**,
--    never forked: four new nullable columns each (`source_class`,
--    `source_confidence_score`, `source_freshness_status`, plus a link back to the
--    staging row that produced it). `app.milestone_events` is append-only (`OPS-173`'s
--    own design) -- these columns are populated only at INSERT time for new rows;
--    every historical row stays honestly null (`226_*.md` §19: "historical source
--    classification may remain unknown rather than fabricated"), never backfilled.
--    `app.ingest_milestone_event`/`app.report_exception` are widened with four new
--    trailing, defaulted (`default null`) parameters -- every existing positional or
--    named call site (including every already-applied Phase 3 caller) is unaffected.
-- 3. **A real, disclosed defect in `app.evaluate_leg_no_signal_escalation` (`ATW-225`)
--    is fixed here, not worked around.** That function measures a still-active
--    session's own staleness against `now() - session.started_at` -- at `225`'s own
--    authoring time `ATW-226F`'s canonical telemetry health did not exist yet, so
--    session *age* was the only signal available. The real defect this leaves: a
--    session that has been reporting perfectly healthy telemetry for longer than
--    `no_signal_escalation_seconds` is incorrectly flagged stale purely for having
--    run that long. Widened (`CREATE OR REPLACE`, identical signature) to measure
--    staleness from the vehicle's own actual last-received telemetry
--    (`app.vehicle_source_health.last_seen_received_at`, `226F`) when one exists,
--    falling back to the original `started_at`-based check only for a session that
--    has never received any telemetry at all (legitimately judged by its own age) or
--    a `driver`-kind session (`226F`'s health table is vehicle-keyed only, no
--    equivalent exists for a bare driver resource).
-- 4. **A second, complementary tracking-health mechanism, staged like every other
--    `226G` signal, not auto-ingested.** `app.evaluate_leg_no_signal_escalation`
--    (design note 3) is a human-triggered, single-leg, directly-authoritative check
--    (an operator investigating one leg). This migration adds a tenant-wide,
--    scan-based, `service_role`-only detector
--    (`app.detect_shipment_leg_tracking_health_signals`) that stages a new signal
--    type (`tracking_health_no_signal`, additive `CHECK` widening on
--    `app.shipment_exception_signals.signal_type` -- reusing that table, never a
--    second staging table) for a currently-executing, tracking-required leg whose
--    live source health is offline -- reviewed and promoted through the exact same
--    already-`VERIFIED` `app.confirm_exception_signal`/`app.dismiss_exception_signal`
--    (`226G`) path, never a new promotion RPC. A recovered leg is silently
--    auto-dismissed (`review_note = 'auto_recovered_tracking_restored'`), mirroring
--    `226G`'s own route-deviation "a silent recovery never fires a signal" precedent
--    -- structurally impossible to spam ("no-signal storm"), since the underlying
--    `(tenant_id, correlation_key) where status = 'pending'` unique index (`226G`)
--    already prevents more than one open episode per leg.
-- 5. **Dependency-aware live ETA is read-only and honestly bounded, never a routing
--    engine.** `app._compute_shipment_leg_eta` (internal) walks the leg's own
--    remaining (`stop_status = 'pending'`) stops in sequence from the vehicle's own
--    live canonical position (`226F`), the same straight-line-corridor approximation
--    `226G`'s own route-deviation evaluator already discloses (design note 5 there),
--    at `ATW-224`'s own governed `app.route_planning_default_speed_kmh()` (40 km/h) --
--    never a second speed constant. Returns `computable = false` with a named reason
--    rather than a fabricated estimate whenever no live position exists, the position
--    is offline, or the leg has no remaining stop. `downstream_leg_count` (a count of
--    later-sequenced, non-cancelled legs on the same shipment order) is the
--    "dependency-aware"/"batch dependency impact" signal this prompt's own §17 names
--    -- a bounded, informational count, never an automatic rewrite of any other leg's
--    own schedule.
-- 6. **Rebaseline is an explicit, human-authorized, bounded mutation** -- only while
--    a leg is still `planned` (this prompt's own §22 "rebaseline unstarted
--    milestones"), `OPS:Edit`-gated, mandatory reason, full before/after audit. It
--    never fires automatically from the ETA projection above.
-- 7. **The public customer projection is widened a third time** (`app.lookup_public_
--    shipment_tracking`, `OPS-180`; `226C` added the sanitized token/rate-limit
--    shape, `226H` added sanitized vehicle position) -- a fourth signature-changing
--    widening via `DROP FUNCTION` + `CREATE FUNCTION` (`226C`'s own precedent for a
--    signature change), adding a coarse `live_eta_status`
--    (`on_time`/`delayed`/`unavailable`) and a rounded `live_eta_at`, gated on the
--    identical `customer_visible` tracking-policy flag (`ATW-225`) vehicle position
--    already uses -- deliberately distinct from `app.shipment_milestone_projections`'
--    own `current_eta`/`is_delayed` (`OPS-173`), which that table's own comment
--    already discloses as "this MVP's own disclosed simplification... never a
--    predictive ETA algorithm" -- this migration is that algorithm's own first real
--    version, exposed as a new field, never overwriting the existing one.
-- 8. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--    ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- ============================================================================
-- 1. Shared confidence/freshness formula.
-- ============================================================================

create type app.telemetry_confidence_freshness as (
  source_class text,
  confidence_score numeric,
  freshness_status text
);

-- Deliberately returns an all-null row (never a fabricated 1.0/healthy default) when
-- no canonical telemetry event backs the candidate/signal at all -- e.g. this
-- migration's own tracking_health_no_signal signal type, whose entire premise is the
-- *absence* of a telemetry event.
create function app.evaluate_telemetry_confidence_and_freshness(p_tenant_id uuid, p_canonical_telemetry_event_id uuid)
returns app.telemetry_confidence_freshness
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_event app.canonical_telemetry_events;
  v_policy record;
  v_confidence numeric := 1.0;
  v_freshness text;
  v_result app.telemetry_confidence_freshness;
begin
  if p_canonical_telemetry_event_id is null then
    return v_result;
  end if;
  select * into v_event from app.canonical_telemetry_events where id = p_canonical_telemetry_event_id;
  if not found then
    return v_result;
  end if;

  select * into v_policy from app.resolve_tenant_tracking_source_policy(p_tenant_id);

  if v_event.accuracy_meters is null or v_event.accuracy_meters > v_policy.accuracy_threshold_meters then
    v_confidence := v_confidence - 0.3;
  end if;

  if now() - v_event.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval then
    v_freshness := 'healthy';
  elsif now() - v_event.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval * 3 then
    v_freshness := 'stale';
    v_confidence := v_confidence - 0.3;
  else
    v_freshness := 'offline';
    v_confidence := v_confidence - 0.3;
  end if;

  v_result.source_class := v_event.source_type;
  v_result.confidence_score := greatest(v_confidence, 0.4);
  v_result.freshness_status := v_freshness;
  return v_result;
end;
$$;

comment on function app.evaluate_telemetry_confidence_and_freshness is
  'ATW-228: the one shared confidence/freshness formula app.confirm_milestone_candidate and app.confirm_exception_signal (both 226G) now call. All-null when no canonical telemetry event exists (a manually-filed record, or this migration''s own tracking_health_no_signal signal, whose premise is the absence of a signal). Confidence starts at 1.0, -0.3 for missing/exceeding-threshold accuracy, -0.3 for stale/offline freshness (both may apply), floored at 0.4 -- never zero/misleading, since the underlying event did win canonical arbitration (226F). Reuses app.resolve_tenant_tracking_source_policy (226A) thresholds and app.get_vehicle_source_health''s own 1x/3x banding (226F), not a forked constant.';

-- ============================================================================
-- 2. Widen app.milestone_events (OPS-173) -- additive columns, then the two
-- functions that populate them.
-- ============================================================================

alter table app.milestone_events add column source_class text;
alter table app.milestone_events add column source_confidence_score numeric;
alter table app.milestone_events add column source_freshness_status text;
alter table app.milestone_events add column source_candidate_id uuid references app.shipment_milestone_candidates (id);

alter table app.milestone_events add constraint milestone_events_source_class_check
  check (source_class is null or source_class in ('driver_mobile', 'direct_device', 'third_party_platform'));
alter table app.milestone_events add constraint milestone_events_source_confidence_check
  check (source_confidence_score is null or (source_confidence_score >= 0 and source_confidence_score <= 1));
alter table app.milestone_events add constraint milestone_events_source_freshness_check
  check (source_freshness_status is null or source_freshness_status in ('healthy', 'stale', 'offline'));

comment on column app.milestone_events.source_class is 'ATW-228: the winning telemetry source type (226F) at confirmation time, or null for a manual/api/webhook/import-sourced event. Never backfilled for a pre-existing row.';
comment on column app.milestone_events.source_confidence_score is 'ATW-228: app.evaluate_telemetry_confidence_and_freshness''s own 0.4-1.0 score at confirmation time, or null when no telemetry event backs this event.';
comment on column app.milestone_events.source_freshness_status is 'ATW-228: healthy/stale/offline at confirmation time, or null when no telemetry event backs this event.';

-- A trailing-parameter widening changes this function's own identity (name +
-- input parameter types), so CREATE OR REPLACE would silently create a second,
-- ambiguous overload rather than replace it (226C's own app.end_leg_tracking_session
-- precedent for exactly this class of change) -- DROP then CREATE is correct here.
drop function app.ingest_milestone_event(uuid, text, timestamptz, timestamptz, jsonb, text, text, uuid, text, uuid, text);

create function app.ingest_milestone_event(
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
  p_actor_label text,
  p_source_class text default null,
  p_source_confidence_score numeric default null,
  p_source_freshness_status text default null,
  p_source_candidate_id uuid default null
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
  if p_source_class is not null and p_source_class not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'milestone_invalid_source_class: % is not a supported telemetry source class', p_source_class using errcode = 'check_violation';
  end if;
  if p_source_confidence_score is not null and (p_source_confidence_score < 0 or p_source_confidence_score > 1) then
    raise exception 'milestone_invalid_confidence: source_confidence_score must be between 0 and 1' using errcode = 'check_violation';
  end if;
  if p_source_freshness_status is not null and p_source_freshness_status not in ('healthy', 'stale', 'offline') then
    raise exception 'milestone_invalid_freshness: % is not a supported freshness status', p_source_freshness_status using errcode = 'check_violation';
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
    tenant_id, shipment_order_id, milestone_code, event_time, received_time, location, source, reason, corrects_event_id, idempotency_key, sequence_no, created_by,
    source_class, source_confidence_score, source_freshness_status, source_candidate_id
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_code, p_event_time, coalesce(p_received_time, now()), p_location, p_source, p_reason, p_corrects_event_id, p_idempotency_key, v_next_seq, p_actor_label,
    p_source_class, p_source_confidence_score, p_source_freshness_status, p_source_candidate_id
  )
  returning * into v_event;

  perform app.recalculate_shipment_milestone_projection(p_shipment_order_id);

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'ingest_milestone_event',
    'app.milestone_events', v_event.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'milestone_code', p_milestone_code, 'source', p_source, 'corrects_event_id', p_corrects_event_id, 'source_class', p_source_class)
  );

  return v_event;
exception
  when unique_violation then
    select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
    return v_event;
end;
$$;

comment on function app.ingest_milestone_event is
  'OPS-173, widened at ATW-226G (system source) and ATW-228 (design note 2 above): identical to its own prior body, plus four new trailing, defaulted (null) provenance parameters populated only by app.confirm_milestone_candidate. Idempotent on (tenant_id, shipment_order_id, idempotency_key), never blocked by out-of-order event_time. Blocked only once the shipment is cancelled.';

create or replace function app.confirm_milestone_candidate(
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
  v_provenance app.telemetry_confidence_freshness;
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

  v_provenance := app.evaluate_telemetry_confidence_and_freshness(v_shipment.tenant_id, v_candidate.source_canonical_event_id);

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
    p_actor_label := p_actor_label,
    p_source_class := v_provenance.source_class,
    p_source_confidence_score := v_provenance.confidence_score,
    p_source_freshness_status := v_provenance.freshness_status,
    p_source_candidate_id := v_candidate.id
  );

  update app.shipment_milestone_candidates
  set status = 'confirmed', resulting_milestone_event_id = v_event.id, reviewed_by_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_candidate_id;

  return v_event;
end;
$$;

comment on function app.confirm_milestone_candidate is
  'ATW-226G, widened at ATW-228 (design note 1): identical authority/conflict logic, now also computes and passes through real source_class/confidence/freshness provenance via app.evaluate_telemetry_confidence_and_freshness. Still the sole path from a staged candidate to a real app.milestone_events row, always the confirming actor''s own real, RBAC-checked identity, never a null/system bypass.';

-- ============================================================================
-- 3. Widen app.operational_exceptions (OPS-174) -- the identical pattern.
-- ============================================================================

alter table app.operational_exceptions add column source_class text;
alter table app.operational_exceptions add column source_confidence_score numeric;
alter table app.operational_exceptions add column source_freshness_status text;
alter table app.operational_exceptions add column source_signal_id uuid references app.shipment_exception_signals (id);

alter table app.operational_exceptions add constraint operational_exceptions_source_class_check
  check (source_class is null or source_class in ('driver_mobile', 'direct_device', 'third_party_platform'));
alter table app.operational_exceptions add constraint operational_exceptions_source_confidence_check
  check (source_confidence_score is null or (source_confidence_score >= 0 and source_confidence_score <= 1));
alter table app.operational_exceptions add constraint operational_exceptions_source_freshness_check
  check (source_freshness_status is null or source_freshness_status in ('healthy', 'stale', 'offline'));

comment on column app.operational_exceptions.source_class is 'ATW-228: the winning telemetry source type (226F) at confirmation time, or null for a manual exception or one with no backing telemetry event (e.g. tracking_health_no_signal, whose premise is the absence of a signal).';

-- Same reasoning as app.ingest_milestone_event above -- DROP then CREATE, not
-- CREATE OR REPLACE, since the trailing parameters change this function's identity.
drop function app.report_exception(uuid, uuid, text, text, text, text, text, uuid, text);

create function app.report_exception(
  p_shipment_order_id uuid,
  p_milestone_event_id uuid,
  p_type text,
  p_severity text,
  p_description text,
  p_source text,
  p_correlation_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_source_class text default null,
  p_source_confidence_score numeric default null,
  p_source_freshness_status text default null,
  p_source_signal_id uuid default null
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.exception_sla_policy_versions;
  v_existing app.operational_exceptions;
  v_exception app.operational_exceptions;
begin
  if p_type not in ('delay', 'hold', 'damage', 'loss', 'incident') then
    raise exception 'exception_invalid_type: % is not a supported exception type', p_type using errcode = 'check_violation';
  end if;
  if p_severity not in ('low', 'medium', 'high', 'critical') then
    raise exception 'exception_invalid_severity: % is not a supported severity', p_severity using errcode = 'check_violation';
  end if;
  if p_source not in ('manual', 'system') then
    raise exception 'exception_invalid_source: % is not one of manual/system', p_source using errcode = 'check_violation';
  end if;
  if p_source_class is not null and p_source_class not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'exception_invalid_source_class: % is not a supported telemetry source class', p_source_class using errcode = 'check_violation';
  end if;
  if p_source_confidence_score is not null and (p_source_confidence_score < 0 or p_source_confidence_score > 1) then
    raise exception 'exception_invalid_confidence: source_confidence_score must be between 0 and 1' using errcode = 'check_violation';
  end if;
  if p_source_freshness_status is not null and p_source_freshness_status not in ('healthy', 'stale', 'offline') then
    raise exception 'exception_invalid_freshness: % is not a supported freshness status', p_source_freshness_status using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if p_milestone_event_id is not null and not exists (select 1 from app.milestone_events where id = p_milestone_event_id and shipment_order_id = p_shipment_order_id) then
    raise exception 'milestone_event_not_found: % is not an event on shipment order %', p_milestone_event_id, p_shipment_order_id
      using errcode = 'no_data_found';
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

  if p_source = 'system' and p_correlation_key is not null then
    select * into v_existing from app.operational_exceptions
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and correlation_key = p_correlation_key;
    if found then
      return v_existing;
    end if;
  end if;

  select * into v_policy from app.exception_sla_policy_versions
  where tenant_id = v_shipment.tenant_id and type = p_type and severity = p_severity and status = 'published';

  insert into app.operational_exceptions (
    tenant_id, shipment_order_id, milestone_event_id, type, severity, source, correlation_key, description,
    sla_policy_version_id, sla_hours, due_at, created_by,
    source_class, source_confidence_score, source_freshness_status, source_signal_id
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_event_id, p_type, p_severity, p_source, p_correlation_key, p_description,
    v_policy.id, v_policy.sla_hours, case when v_policy.sla_hours is not null then now() + (v_policy.sla_hours || ' hours')::interval else null end,
    p_actor_label,
    p_source_class, p_source_confidence_score, p_source_freshness_status, p_source_signal_id
  )
  returning * into v_exception;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'report_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'type', p_type, 'severity', p_severity, 'source', p_source, 'source_class', p_source_class)
  );

  return v_exception;
exception
  when unique_violation then
    select * into v_exception from app.operational_exceptions
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and correlation_key = p_correlation_key;
    return v_exception;
end;
$$;

comment on function app.report_exception is
  'OPS-174, widened at ATW-228 (design note 2 above): identical to its own prior body, plus four new trailing, defaulted (null) provenance parameters populated only by app.confirm_exception_signal.';

create or replace function app.confirm_exception_signal(
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
  v_provenance app.telemetry_confidence_freshness;
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

  v_provenance := app.evaluate_telemetry_confidence_and_freshness(v_shipment.tenant_id, v_signal.source_canonical_event_id);

  v_exception := app.report_exception(
    p_shipment_order_id := v_signal.shipment_order_id,
    p_milestone_event_id := null,
    p_type := v_signal.exception_type,
    p_severity := v_signal.severity,
    p_description := v_signal.description,
    p_source := 'system',
    p_correlation_key := v_signal.correlation_key,
    p_actor_auth_user_id := p_actor_auth_user_id,
    p_actor_label := p_actor_label,
    p_source_class := v_provenance.source_class,
    p_source_confidence_score := v_provenance.confidence_score,
    p_source_freshness_status := v_provenance.freshness_status,
    p_source_signal_id := v_signal.id
  );

  update app.shipment_exception_signals
  set status = 'confirmed', resulting_exception_id = v_exception.id, reviewed_by_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_signal_id;

  return v_exception;
end;
$$;

comment on function app.confirm_exception_signal is
  'ATW-226G, widened at ATW-228 (design note 1): identical authority logic, now also computes and passes through real source_class/confidence/freshness provenance. tracking_health_no_signal signals (this migration''s own new signal type) carry no source_canonical_event_id, so their resulting exception honestly carries null provenance -- the absence of a signal is the whole premise.';

-- ============================================================================
-- 4. Tracking-health exception taxonomy -- a new staged signal type reusing the
-- existing app.shipment_exception_signals table (design note 4).
-- ============================================================================

alter table app.shipment_exception_signals drop constraint shipment_exception_signals_signal_type_check;
alter table app.shipment_exception_signals add constraint shipment_exception_signals_signal_type_check
  check (signal_type in ('route_deviation', 'overdue_geofence_arrival', 'tracking_health_no_signal'));

create function app.detect_shipment_leg_tracking_health_signals(p_tenant_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_leg record;
  v_count integer := 0;
  v_correlation_key text;
  v_health_status text;
  v_last_received_at timestamptz;
begin
  for v_leg in
    select sl.id, sl.tenant_id, sl.shipment_order_id, ra.resource_id as vehicle_master_id
    from app.shipment_legs sl
    join app.shipment_leg_tracking_policies p on p.shipment_leg_id = sl.id
    join app.resource_assignments ra on ra.shipment_order_id = sl.shipment_order_id and ra.role = 'vehicle' and ra.is_current and ra.status = 'active'
    where sl.leg_status in ('dispatched', 'in_transit')
      and p.status = 'active'
      and p.tracking_required
      and (p_tenant_id is null or sl.tenant_id = p_tenant_id)
  loop
    select h.status, h.last_seen_received_at into v_health_status, v_last_received_at
    from app.get_vehicle_source_health(v_leg.tenant_id, v_leg.vehicle_master_id) h
    order by case h.status when 'healthy' then 1 when 'stale' then 2 when 'offline' then 3 else 4 end
    limit 1;

    v_correlation_key := 'tracking_health_no_signal:' || v_leg.id;

    if v_health_status is null or v_health_status in ('offline', 'unknown') then
      perform app.upsert_exception_signal(
        v_leg.tenant_id, v_leg.shipment_order_id, v_leg.id, 'tracking_health_no_signal', 'delay', 'medium',
        null, null,
        format('Leg %s requires tracking but its best-available source is currently %s%s.', v_leg.id, coalesce(v_health_status, 'unknown'),
          case when v_last_received_at is not null then ' (last seen ' || v_last_received_at::text || ')' else ' (never seen)' end),
        v_correlation_key
      );
      v_count := v_count + 1;
    else
      update app.shipment_exception_signals
      set status = 'dismissed', review_note = 'auto_recovered_tracking_restored', reviewed_at = now()
      where correlation_key = v_correlation_key and status = 'pending';
    end if;
  end loop;
  return v_count;
end;
$$;

comment on function app.detect_shipment_leg_tracking_health_signals is
  'ATW-228: a real, callable, tenant-optionally-scoped scan (the identical disclosed "mechanism real, cron wiring deferred" posture app.detect_overdue_geofence_arrivals, 226G, and app.escalate_exception, OPS-174, already established) -- best-available source health across every eligible telemetry source for the leg''s own assigned vehicle (app.get_vehicle_source_health, 226F); offline/unknown stages (or refreshes) exactly one pending signal per leg (design note 4, dedup via the existing partial unique index); a recovered leg is silently auto-dismissed, never re-raised as noise.';

-- ============================================================================
-- 5. Fix a real defect in app.evaluate_leg_no_signal_escalation (ATW-225, design
-- note 3) -- same signature, widened body only.
-- ============================================================================

create or replace function app.evaluate_leg_no_signal_escalation(
  p_shipment_leg_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
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
  v_policy app.shipment_leg_tracking_policies;
  v_session app.shipment_leg_tracking_sessions;
  v_last_received_at timestamptz;
  v_stale_since timestamptz;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
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

  select * into v_session from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if not found then
    return null;
  end if;

  select * into v_policy from app.shipment_leg_tracking_policies where id = v_session.policy_id;
  if v_policy.no_signal_escalation_seconds is null then
    return v_session;
  end if;

  -- ATW-228 fix (design note 3): prefer the vehicle's own actual last-received
  -- telemetry (226F) over the session's own started_at when one exists, so a
  -- long-running but genuinely healthy session is never wrongly flagged stale.
  v_stale_since := v_session.started_at;
  if v_session.resource_kind = 'vehicle' then
    select last_seen_received_at into v_last_received_at
    from app.vehicle_source_health
    where vehicle_master_id = v_session.resource_master_id and source_type = v_session.source_type;
    if v_last_received_at is not null then
      v_stale_since := v_last_received_at;
    end if;
  end if;

  if now() - v_stale_since < (v_policy.no_signal_escalation_seconds || ' seconds')::interval then
    return v_session;
  end if;

  update app.shipment_leg_tracking_sessions
  set is_current = false, status = 'ended', ended_at = now(), end_reason = 'stale_source'
  where id = v_session.id
  returning * into v_session;

  perform app.report_exception(
    v_leg.shipment_order_id, null, 'incident', 'medium',
    format('Tracking session %s for leg %s exceeded its own no-signal escalation threshold (%s seconds) without ending or handoff', v_session.id, p_shipment_leg_id, v_policy.no_signal_escalation_seconds),
    'system', 'leg-no-signal:' || p_shipment_leg_id::text, p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_leg_no_signal_escalation',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'no_signal_escalation_seconds', v_policy.no_signal_escalation_seconds, 'stale_since', v_stale_since)
  );

  return v_session;
end;
$$;

comment on function app.evaluate_leg_no_signal_escalation is
  'ATW-225, fixed at ATW-228 (design note 3 above): now measures staleness from the vehicle''s own actual last-received telemetry (app.vehicle_source_health, 226F) when one exists, not merely how long the session has been running -- the real defect a long-running-but-healthy session exposed. Falls back to the original started_at-based check for a session that has never received any telemetry, or a driver-kind session (226F''s health table is vehicle-keyed only).';

-- ============================================================================
-- 6. Dependency-aware live ETA -- read-only.
-- ============================================================================

create type app.shipment_leg_eta_projection as (
  shipment_leg_id uuid,
  computable boolean,
  reason text,
  position_status text,
  remaining_distance_km numeric,
  estimated_arrival_at timestamptz,
  planned_arrival_at timestamptz,
  delay_minutes numeric,
  downstream_leg_count integer
);

-- Internal (no actor) -- reused by both the authenticated projection below and the
-- public tracking lookup widening (design note 7), which has no actor to gate on.
create function app._compute_shipment_leg_eta(p_shipment_leg_id uuid)
returns app.shipment_leg_eta_projection
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_result app.shipment_leg_eta_projection;
  v_vehicle_master_id uuid;
  v_position app.vehicle_current_positions;
  v_policy record;
  v_freshness text;
  v_ref_line geography;
  v_stop_count integer;
  v_distance_meters numeric;
begin
  v_result.shipment_leg_id := p_shipment_leg_id;
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    v_result.computable := false;
    v_result.reason := 'leg_not_found';
    return v_result;
  end if;
  v_result.planned_arrival_at := v_leg.planned_arrival_at;

  select count(*) into v_result.downstream_leg_count
  from app.shipment_legs
  where shipment_order_id = v_leg.shipment_order_id and sequence_no > v_leg.sequence_no and leg_status <> 'cancelled';

  if v_leg.leg_status not in ('dispatched', 'in_transit') then
    v_result.computable := false;
    v_result.reason := 'leg_not_active';
    return v_result;
  end if;

  select resource_id into v_vehicle_master_id from app.resource_assignments
    where shipment_order_id = v_leg.shipment_order_id and role = 'vehicle' and is_current and status = 'active';
  if v_vehicle_master_id is null then
    v_result.computable := false;
    v_result.reason := 'vehicle_not_assigned';
    return v_result;
  end if;

  select * into v_position from app.vehicle_current_positions where vehicle_master_id = v_vehicle_master_id;
  if not found then
    v_result.computable := false;
    v_result.reason := 'no_live_position';
    return v_result;
  end if;

  select * into v_policy from app.resolve_tenant_tracking_source_policy(v_leg.tenant_id);
  if now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval then
    v_freshness := 'healthy';
  elsif now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval * 3 then
    v_freshness := 'stale';
  else
    v_freshness := 'offline';
  end if;
  v_result.position_status := v_freshness;
  if v_freshness = 'offline' then
    v_result.computable := false;
    v_result.reason := 'position_stale';
    return v_result;
  end if;

  select count(*) into v_stop_count from app.shipment_leg_stops where shipment_leg_id = p_shipment_leg_id and stop_status = 'pending' and location_geog is not null;
  if v_stop_count = 0 then
    v_result.computable := false;
    v_result.reason := 'no_remaining_stops';
    return v_result;
  end if;

  select ST_MakeLine(pt::geometry order by seq)::geography into v_ref_line
  from (
    select 0 as seq, v_position.location as pt
    union all
    select stop_sequence, location_geog from app.shipment_leg_stops where shipment_leg_id = p_shipment_leg_id and stop_status = 'pending' and location_geog is not null
  ) points;

  v_distance_meters := ST_Length(v_ref_line);
  v_result.remaining_distance_km := round((v_distance_meters / 1000.0)::numeric, 2);
  v_result.estimated_arrival_at := now() + (v_result.remaining_distance_km / app.route_planning_default_speed_kmh()) * interval '1 hour';
  if v_leg.planned_arrival_at is not null then
    v_result.delay_minutes := round(extract(epoch from (v_result.estimated_arrival_at - v_leg.planned_arrival_at)) / 60, 1);
  end if;
  v_result.computable := true;
  v_result.reason := null;
  return v_result;
end;
$$;

comment on function app._compute_shipment_leg_eta is
  'ATW-228: internal (no actor/RBAC) -- the leg''s own remaining (stop_status=pending) stops, in sequence, from the vehicle''s own live canonical position (226F), straight-line only (the identical corridor approximation app.evaluate_route_deviation, 226G, already discloses), at app.route_planning_default_speed_kmh() (ATW-224, 40 km/h -- never a second speed constant). computable=false with a named reason (never a fabricated estimate) whenever no live position, an offline position, or no remaining stop exists. downstream_leg_count is a bounded, informational later-sequenced-leg count -- this function never mutates any other leg''s own schedule.';

create function app.get_shipment_leg_eta_projection(p_shipment_leg_id uuid, p_actor_auth_user_id uuid)
returns app.shipment_leg_eta_projection
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
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return app._compute_shipment_leg_eta(p_shipment_leg_id);
end;
$$;

comment on function app.get_shipment_leg_eta_projection is
  'ATW-228: OPS:View-gated, record-scoped wrapper around app._compute_shipment_leg_eta for the control tower.';

-- ============================================================================
-- 7. Rebaseline -- explicit, bounded, unstarted-leg-only mutation.
-- ============================================================================

create function app.rebaseline_shipment_leg_schedule(
  p_shipment_leg_id uuid,
  p_new_planned_departure_at timestamptz,
  p_new_planned_arrival_at timestamptz,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_legs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_before jsonb;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to rebaseline a leg''s own schedule' using errcode = 'check_violation';
  end if;
  if p_new_planned_arrival_at <= p_new_planned_departure_at then
    raise exception 'invalid_schedule: new_planned_arrival_at must be after new_planned_departure_at' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
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

  if v_leg.record_version <> p_expected_version then
    raise exception 'stale_version: leg % expected version % but found %', p_shipment_leg_id, p_expected_version, v_leg.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_unstarted: leg % is %, only a planned (unstarted) leg may be rebaselined', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_before := jsonb_build_object('planned_departure_at', v_leg.planned_departure_at, 'planned_arrival_at', v_leg.planned_arrival_at);

  update app.shipment_legs
  set planned_departure_at = p_new_planned_departure_at, planned_arrival_at = p_new_planned_arrival_at
  where id = p_shipment_leg_id and record_version = p_expected_version
  returning * into v_leg;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'rebaseline_shipment_leg_schedule',
    'app.shipment_legs', v_leg.id, 'success', null, v_before,
    jsonb_build_object('planned_departure_at', v_leg.planned_departure_at, 'planned_arrival_at', v_leg.planned_arrival_at, 'shipment_leg_id', p_shipment_leg_id, 'reason', p_reason)
  );

  return v_leg;
end;
$$;

comment on function app.rebaseline_shipment_leg_schedule is
  'ATW-228 (design note 6): explicit, OPS:Edit-gated, mandatory-reason rebaseline of a still-planned (unstarted) leg''s own planned_departure_at/planned_arrival_at -- never fires automatically from app._compute_shipment_leg_eta. Optimistic-concurrency gated against app.shipment_legs.record_version (its own existing touch trigger, ATW-221, bumps it). A dispatched/in_transit/arrived/completed/cancelled leg may never be rebaselined.';

-- ============================================================================
-- 8. Widen the public customer tracking projection a third time (design note 7).
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
  vehicle_position_status text,
  live_eta_status text,
  live_eta_at timestamptz
)
language plpgsql
security definer
set search_path = app, public, pg_temp
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
  v_active_leg_id uuid;
  v_eta app.shipment_leg_eta_projection;
  v_live_eta_status text;
  v_live_eta_at timestamptz;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'tracking_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.tracking_lookup_attempts
  where client_key = p_client_key and result in ('not_found', 'invalid') and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'rate_limited');
    return query select 'rate_limited'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean, null::jsonb, null::timestamptz, null::text, null::text, null::timestamptz;
    return;
  end if;

  if p_raw_token is null or length(p_raw_token) = 0 then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean, null::jsonb, null::timestamptz, null::text, null::text, null::timestamptz;
    return;
  end if;

  v_hash := encode(digest(p_raw_token, 'sha256'), 'hex');
  select * into v_token from app.shipment_tracking_tokens where token_hash = v_hash;

  if not found or v_token.status <> 'active' or v_token.expires_at <= now() then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'not_found');
    return query select 'not_found'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean, null::jsonb, null::timestamptz, null::text, null::text, null::timestamptz;
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

  select ra.resource_id into v_vehicle_master_id
  from app.resource_assignments ra
  where ra.shipment_order_id = v_shipment.id and ra.role = 'vehicle' and ra.is_current and ra.status = 'active';

  select sl.id into v_active_leg_id
  from app.shipment_legs sl
  where sl.shipment_order_id = v_shipment.id and sl.leg_status in ('dispatched', 'in_transit')
  order by sl.sequence_no
  limit 1;

  if v_active_leg_id is not null then
    select p.customer_visible into v_customer_visible from app.shipment_leg_tracking_policies p where p.shipment_leg_id = v_active_leg_id;
  end if;

  if v_vehicle_master_id is not null and coalesce(v_customer_visible, false) then
    select * into v_position from app.vehicle_current_positions where vehicle_master_id = v_vehicle_master_id;
    if found then
      select * into v_policy from app.resolve_tenant_tracking_source_policy(v_shipment.tenant_id);
      v_vehicle_position_geojson := ST_AsGeoJSON(v_position.location)::jsonb;
      v_vehicle_position_updated_at := v_position.received_at;
      v_vehicle_position_status := case
        when now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval then 'live'
        when now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval * 3 then 'delayed'
        else 'unavailable'
      end;
    end if;

    v_eta := app._compute_shipment_leg_eta(v_active_leg_id);
    if v_eta.computable then
      v_live_eta_at := v_eta.estimated_arrival_at;
      v_live_eta_status := case
        when v_eta.delay_minutes is null then 'on_time'
        when v_eta.delay_minutes <= 30 then 'on_time'
        else 'delayed'
      end;
    else
      v_live_eta_status := 'unavailable';
    end if;
  end if;

  return query select
    'ok'::text, v_shipment.shipment_number, v_shipment.status, v_shipment.mode, v_shipment.origin, v_shipment.destination,
    v_shipment.planned_delivery_at, v_projection.current_eta, coalesce(v_projection.is_delayed, false), v_milestones, coalesce(v_epod_available, false),
    v_vehicle_position_geojson, v_vehicle_position_updated_at, v_vehicle_position_status,
    v_live_eta_status, v_live_eta_at;
end;
$$;

comment on function app.lookup_public_shipment_tracking is
  'OPS-180, widened at ATW-226C (rate limiting), ATW-226H (sanitized vehicle position), and ATW-228 (live_eta_status/live_eta_at, design note 7): every prior output column unchanged. live_eta_status/live_eta_at are deliberately distinct from current_eta/is_delayed (OPS-173''s own disclosed milestone-only heuristic) -- this is the real, telemetry-based estimate, gated on the identical customer_visible tracking-policy flag vehicle position already uses, computed via app._compute_shipment_leg_eta and coarsened to on_time/delayed/unavailable, never a raw distance/delay-minutes figure.';

-- ============================================================================
-- 9. RLS + grants.
-- ============================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.evaluate_telemetry_confidence_and_freshness(uuid, uuid) to service_role;
grant execute on function app.ingest_milestone_event(uuid, text, timestamptz, timestamptz, jsonb, text, text, uuid, text, uuid, text, text, numeric, text, uuid) to authenticated, service_role;
grant execute on function app.confirm_milestone_candidate(uuid, uuid, text, timestamptz, boolean) to authenticated, service_role;
grant execute on function app.report_exception(uuid, uuid, text, text, text, text, text, uuid, text, text, numeric, text, uuid) to authenticated, service_role;
grant execute on function app.confirm_exception_signal(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.detect_shipment_leg_tracking_health_signals(uuid) to service_role;
grant execute on function app.evaluate_leg_no_signal_escalation(uuid, uuid, text) to authenticated, service_role;
grant execute on function app._compute_shipment_leg_eta(uuid) to service_role;
grant execute on function app.get_shipment_leg_eta_projection(uuid, uuid) to authenticated, service_role;
grant execute on function app.rebaseline_shipment_leg_schedule(uuid, timestamptz, timestamptz, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.lookup_public_shipment_tracking(text, text) to anon, authenticated, service_role;
