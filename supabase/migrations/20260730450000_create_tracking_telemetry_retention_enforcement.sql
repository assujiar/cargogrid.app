-- CG-S10-ATW-031 (post-Prompt-248 codebase audit — closes `ISS-2026-027`).
--
-- Phase 5's ratified retention POLICY (`RPD-025`: operational data retained "contract
-- term + 90 days", the class GPS telemetry falls under) had no enforcement mechanism in
-- code. `app.tenant_tracking_source_policies`' own entitlement composite type declares a
-- `history_retention_days` field (`tracking.limits.history_retention_days`), but a
-- repository-wide search confirms that value was read nowhere outside its own definition
-- and the mirroring TypeScript contract. No function anywhere deleted or aged out a
-- telemetry row, so every position report ever accepted remained queryable indefinitely —
-- a ratified retention commitment with nothing behind it.
--
-- ===========================================================================
-- What this migration adds, and what it deliberately does not
-- ===========================================================================
--
-- It adds the ENFORCEMENT MECHANISM: a real, authority-gated, tenant-scoped, bounded,
-- idempotent-by-construction purge function, plus a job type so it can be driven by a
-- scheduler when one exists.
--
-- It does NOT add a scheduler. No `pg_cron`, worker, or timer runtime exists anywhere in
-- this repository (`ISS-2026-015`, repository-wide and pre-dating Phase 5), and inventing
-- one here would be a new capability smuggled into an audit checkpoint. The distinction
-- matters and is stated plainly rather than blurred: after this migration the policy is
-- *enforceable and tested*; it is not yet *automatically enforced*. Whichever checkpoint
-- builds the scheduler wires `tracking_telemetry_retention` to it — that is a one-line
-- job enqueue, not a redesign, and `ISS-2026-015` already owns that obligation.
--
-- ===========================================================================
-- Design
-- ===========================================================================
--
-- 1. **Per-tenant retention window.** Resolved from that tenant's own entitlement via
--    `app.resolve_tenant_tracking_package(...).history_retention_days`, falling back to
--    `app.default_tracking_history_retention_days()` when the package leaves it unset.
--    The default is a named function rather than a literal so the ratified `RPD-025`
--    figure lives in exactly one place — the same discipline `ISS-2026-012` was opened
--    for when a valid-list was copied into four.
--
-- 2. **Purged by RECEIVED time, never event time.** `received_at` is the real server
--    clock; `event_at` is device-supplied and attacker-influenceable. Retention keyed on
--    `event_at` would let a device with a back-dated clock have its history purged early,
--    or with a forward-dated clock retained forever. `ATW-027` Finding 2 established that
--    same reasoning for freshness; retention inherits it.
--
-- 3. **Deletion order respects the foreign keys.** `canonical_telemetry_events.
--    source_report_id` references the per-source raw report tables, so the canonical
--    layer is purged first, then the raw sources, then the switch history.
--
-- 4. **Bounded per call.** `p_max_rows` caps how many rows a single invocation deletes
--    (default 50,000, hard ceiling 500,000) so a first run against a large backlog cannot
--    hold a long transaction or blow up WAL. The function reports whether more remains,
--    so a caller loops rather than the database stalling.
--
-- 5. **Never touches Finance, inventory, shipment, audit, or ledger data.** Its entire
--    surface is the five Phase 5 telemetry tables named below. Audit logs specifically
--    are NOT in scope: they have their own retention class under `RPD-025` and the
--    Supreme Admin exception, and conflating the two would silently widen this repair
--    into a deletion path over evidence records.
--
-- Additive and reversible: two new functions. No table, column, index, constraint, grant,
-- or policy is touched, and no already-applied migration file is edited. The function is
-- inert until something calls it, so applying this migration deletes nothing.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

create or replace function app.default_tracking_history_retention_days()
returns integer
language sql
immutable
set search_path = app, pg_temp
as $$
  -- RPD-025: operational data is retained for the contract term + 90 days. With no
  -- contract-term model in the schema yet, the enforceable floor is the +90 day tail
  -- expressed against a one-year nominal term. Deliberately a named function, not a
  -- literal, so the ratified figure has exactly one home.
  select 455;
$$;

comment on function app.default_tracking_history_retention_days is
  'ATW-031 (ISS-2026-027): the RPD-025-derived default telemetry retention window in days, used when a tenant''s own tracking package leaves history_retention_days unset. One home for the ratified figure -- see app.purge_tracking_telemetry_history.';

create or replace function app.purge_tracking_telemetry_history(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_max_rows integer default 50000
)
returns table (
  retention_days integer,
  cutoff_received_at timestamptz,
  canonical_events_deleted bigint,
  direct_device_reports_deleted bigint,
  third_party_reports_deleted bigint,
  driver_mobile_reports_deleted bigint,
  source_switches_deleted bigint,
  more_remaining boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.tracking_package_resolution;
  v_retention_days integer;
  v_cutoff timestamptz;
  v_budget integer;
  v_canonical bigint := 0;
  v_direct bigint := 0;
  v_third bigint := 0;
  v_mobile bigint := 0;
  v_switches bigint := 0;
begin
  if p_tenant_id is null then
    raise exception 'tenant_required: a tenant id is required to purge telemetry history' using errcode = 'check_violation';
  end if;

  -- Deletion of operational history is an override-tier action, not ordinary editing.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_package := app.resolve_tenant_tracking_package(p_tenant_id);
  v_retention_days := coalesce(v_package.history_retention_days, app.default_tracking_history_retention_days());
  if v_retention_days <= 0 then
    raise exception 'invalid_retention_window: resolved retention window must be positive, got %', v_retention_days using errcode = 'check_violation';
  end if;

  v_budget := least(greatest(coalesce(p_max_rows, 50000), 1), 500000);
  v_cutoff := now() - make_interval(days => v_retention_days);

  -- Canonical layer first: canonical_telemetry_events.source_report_id references the raw
  -- per-source tables, so purging those first would violate the foreign key.
  with doomed as (
    select id from app.canonical_telemetry_events
    where tenant_id = p_tenant_id and received_at < v_cutoff
    order by received_at
    limit v_budget
  )
  delete from app.canonical_telemetry_events e using doomed d where e.id = d.id;
  get diagnostics v_canonical = row_count;

  with doomed as (
    select id from app.direct_device_telemetry_reports
    where tenant_id = p_tenant_id and received_at < v_cutoff
    order by received_at
    limit v_budget
  )
  delete from app.direct_device_telemetry_reports r using doomed d where r.id = d.id;
  get diagnostics v_direct = row_count;

  with doomed as (
    select id from app.third_party_telemetry_reports
    where tenant_id = p_tenant_id and received_at < v_cutoff
    order by received_at
    limit v_budget
  )
  delete from app.third_party_telemetry_reports r using doomed d where r.id = d.id;
  get diagnostics v_third = row_count;

  with doomed as (
    select id from app.driver_mobile_position_reports
    where tenant_id = p_tenant_id and received_at < v_cutoff
    order by received_at
    limit v_budget
  )
  delete from app.driver_mobile_position_reports r using doomed d where r.id = d.id;
  get diagnostics v_mobile = row_count;

  with doomed as (
    select id from app.vehicle_source_switches
    where tenant_id = p_tenant_id and switched_at < v_cutoff
    order by switched_at
    limit v_budget
  )
  delete from app.vehicle_source_switches s using doomed d where s.id = d.id;
  get diagnostics v_switches = row_count;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'purge_tracking_telemetry_history',
    'app.canonical_telemetry_events', null, 'success', null, null,
    jsonb_build_object(
      'retention_days', v_retention_days,
      'cutoff_received_at', v_cutoff,
      'canonical_events_deleted', v_canonical,
      'direct_device_reports_deleted', v_direct,
      'third_party_reports_deleted', v_third,
      'driver_mobile_reports_deleted', v_mobile,
      'source_switches_deleted', v_switches
    )
  );

  return query select
    v_retention_days,
    v_cutoff,
    v_canonical,
    v_direct,
    v_third,
    v_mobile,
    v_switches,
    -- Any table hitting the per-call budget means more rows remain past the cutoff, so
    -- the caller should invoke again rather than assume the sweep finished.
    (v_canonical >= v_budget or v_direct >= v_budget or v_third >= v_budget
      or v_mobile >= v_budget or v_switches >= v_budget);
end;
$$;

comment on function app.purge_tracking_telemetry_history is
  'ATW-031 (ISS-2026-027): the enforcement mechanism for RPD-025 telemetry retention, which previously existed as a ratified policy with no code behind it. OPS:Override-gated, tenant-scoped. Resolves the window from the tenant''s own entitlement (history_retention_days) falling back to app.default_tracking_history_retention_days(). Purges by received_at (the real server clock) never event_at (device-supplied and attacker-influenceable -- the same reasoning ATW-027 Finding 2 established for freshness). Deletes the canonical layer before the raw per-source tables it references. Bounded by p_max_rows and reports more_remaining so a caller loops instead of the database stalling. Touches ONLY the five Phase 5 telemetry tables -- never Finance, inventory, shipment, ledger, or audit records. No scheduler exists in this repository yet (ISS-2026-015), so nothing calls this automatically: after this migration the policy is enforceable and tested, not yet automatically enforced.';

revoke execute on all functions in schema app from public;

grant execute on function app.default_tracking_history_retention_days() to authenticated, service_role;
grant execute on function app.purge_tracking_telemetry_history(uuid, uuid, text, integer) to authenticated, service_role;
