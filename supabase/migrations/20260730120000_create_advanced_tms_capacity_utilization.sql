-- Advanced TMS capability ATW-227 (CG-S10-ATW-008, Prompt 227, "Capacity, Utilization
-- and Tracking Coverage" -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md
-- §1). Implements the two things named in the prompt's own objective as distinct
-- dimensions that must never be conflated: (1) exact physical resource capacity
-- reservation (a real ledger, not a derived estimate) and (2) tracking coverage /
-- subscription-utilization read projections, scope-safe and never mutating
-- entitlement or source mappings.
--
-- Design boundary (disclosed):
--
-- 1. **Capacity is per-vehicle and per-leg, never a new shipment-level concept.**
--    ATW-223's own `app.vehicle_operational_profiles.capacity_weight_kg`/
--    `capacity_volume_cbm` is the physical truth this ledger holds against; ATW-224's
--    own `app.route_planning_scenarios.requested_weight_kg`/`requested_volume_cbm`
--    and `app.route_planning_candidate_plans.capacity_utilization_pct` are decision
--    *support* only (224_*.md §21's own "planning is decision support only, no shape
--    here ever mutates app.shipment_legs") -- neither reserves anything. This
--    migration's own `app.vehicle_capacity_reservations` is the first real reservation
--    ledger: planning may recommend a plan, but only a reservation against a leg
--    actually holds capacity, exactly matching this prompt's own §21 main flow
--    ("planning reserves capacity; dispatch consumes it").
-- 2. **The reserved vehicle is derived, never caller-supplied.** A reservation is
--    always against a leg's own current `app.resource_assignments` (OPS-172) `role =
--    'vehicle'` occupant -- the identical derivation ATW-225's own
--    `app.resolve_leg_tracking_policy` already established for eligibility -- so a
--    reservation can never target a vehicle other than the one actually assigned to
--    that leg. Reassigning the vehicle (OPS-172's own `app.reassign_resource`) does
--    not automatically move an existing reservation; the exception-flow business rule
--    below names this explicitly.
-- 3. **Overbooking is prevented by locking the vehicle's own operational-profile row**,
--    not a table-wide lock or a `SELECT ... FOR UPDATE` on the reservations table
--    itself (which cannot serialize inserts against rows that do not exist yet).
--    Every reservation for a given vehicle takes `app.vehicle_operational_profiles`'s
--    own row lock first, so two reservations against the same vehicle's overlapping
--    window can never both observe the pre-reservation sum -- the second waits for the
--    first's transaction to commit or roll back, then re-reads the up-to-date sum.
--    This repository's own disclosed single-threaded sandbox (`scripts/db-tests/
--    commercial-quotation-versioning.sql`'s own "single-threaded sandbox disclosure")
--    cannot execute two real overlapping transactions to prove blocking directly; this
--    migration's own test evidence instead proves the *aggregation and rejection*
--    logic the lock protects is correct on every sequential call, the same disclosed
--    boundary that precedent already established.
-- 4. **Tracking coverage/utilization reuses ATW-226A/223/226F/225 read paths, never
--    re-derives them.** `app.resolve_tenant_tracking_package` (226A) is the sole
--    entitlement/limit source; per-vehicle eligibility flags and `app.gps_devices`
--    come from ATW-223; live position/freshness comes from ATW-226F's own
--    `app.vehicle_current_positions`/`app.vehicle_source_health` tables (this
--    migration computes healthy/stale/offline on read against the same
--    `freshness_threshold_seconds`/1x-3x banding `app.get_vehicle_source_health`
--    already established, not a forked constant); "tracking-required but untracked"
--    detection reuses ATW-225's own `app.shipment_leg_tracking_policies.tracking_
--    required` and `app.shipment_leg_tracking_sessions` (`status = 'active' and
--    is_current`) against ATW-221's own `app.shipment_legs.leg_status in
--    ('dispatched', 'in_transit')`. No analytics read here ever mutates entitlement,
--    source policy, or provider mapping (this prompt's own §14 boundary).
-- 5. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--    ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Capacity reservation ledger.
create table app.vehicle_capacity_reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  vehicle_master_id uuid not null references app.master_records (id),
  idempotency_key text not null,
  requested_weight_kg numeric,
  requested_volume_cbm numeric,
  window_start timestamptz not null,
  window_end timestamptz not null,
  status text not null default 'held',
  released_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_capacity_reservations_status_check check (status in ('held', 'consumed', 'released')),
  constraint vehicle_capacity_reservations_window_check check (window_end > window_start),
  constraint vehicle_capacity_reservations_weight_check check (requested_weight_kg is null or requested_weight_kg >= 0),
  constraint vehicle_capacity_reservations_volume_check check (requested_volume_cbm is null or requested_volume_cbm >= 0),
  constraint vehicle_capacity_reservations_released_reason_check check (status <> 'released' or released_reason is not null),
  constraint vehicle_capacity_reservations_tenant_leg_idempotency_unique unique (tenant_id, shipment_leg_id, idempotency_key)
);

comment on table app.vehicle_capacity_reservations is
  'ATW-227: a real capacity ledger, not a derived estimate -- one row per (leg, idempotency_key) attempt; at most one row per shipment_leg_id may ever be status in (held, consumed) at a time (partial unique index below). window_start/window_end are copied from the leg''s own planned_departure_at/planned_arrival_at at reservation time (a schedule change on the leg does not retroactively move an existing reservation -- see app.reserve_vehicle_capacity''s own comment). held = capacity is set aside by planning; consumed = dispatch has actually committed the vehicle to this leg; released = capacity returned, either because the leg completed/cancelled or because an authorized actor explicitly released it (released_reason discloses which).';

create unique index vehicle_capacity_reservations_active_leg_unique on app.vehicle_capacity_reservations (shipment_leg_id) where status in ('held', 'consumed');
create index vehicle_capacity_reservations_tenant_vehicle_status_idx on app.vehicle_capacity_reservations (tenant_id, vehicle_master_id, status);
create index vehicle_capacity_reservations_tenant_idx on app.vehicle_capacity_reservations (tenant_id);

create function app.touch_vehicle_capacity_reservations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vehicle_capacity_reservations_touch_row
  before update on app.vehicle_capacity_reservations
  for each row
  execute function app.touch_vehicle_capacity_reservations_row();

-- app.reserve_vehicle_capacity -- idempotent on (tenant_id, shipment_leg_id,
-- idempotency_key); locks the vehicle's own operational-profile row (design note 3
-- above) before summing overlapping active reservations, so concurrent reservations
-- against the same vehicle can never both observe a pre-reservation sum.
create function app.reserve_vehicle_capacity(
  p_shipment_leg_id uuid,
  p_requested_weight_kg numeric,
  p_requested_volume_cbm numeric,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vehicle_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_leg app.shipment_legs;
  v_shipment record;
  v_vehicle_master_id uuid;
  v_profile app.vehicle_operational_profiles;
  v_existing app.vehicle_capacity_reservations;
  v_reservation app.vehicle_capacity_reservations;
  v_reserved_weight numeric;
  v_reserved_volume numeric;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;
  if p_requested_weight_kg is not null and p_requested_weight_kg < 0 then
    raise exception 'invalid_requested_weight: requested_weight_kg must not be negative' using errcode = 'check_violation';
  end if;
  if p_requested_volume_cbm is not null and p_requested_volume_cbm < 0 then
    raise exception 'invalid_requested_volume: requested_volume_cbm must not be negative' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.vehicle_capacity_reservations
    where tenant_id = v_leg.tenant_id and shipment_leg_id = p_shipment_leg_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_leg.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_leg.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
  if not app.can_access_record(p_actor_auth_user_id, v_leg.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_leg.planned_departure_at is null or v_leg.planned_arrival_at is null then
    raise exception 'leg_schedule_required: leg % has no planned_departure_at/planned_arrival_at to reserve a capacity window against', p_shipment_leg_id
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.vehicle_capacity_reservations where shipment_leg_id = p_shipment_leg_id and status in ('held', 'consumed')) then
    raise exception 'reservation_already_active: leg % already has an active (held/consumed) capacity reservation -- release it before reserving again', p_shipment_leg_id
      using errcode = 'check_violation';
  end if;

  select resource_id into v_vehicle_master_id from app.resource_assignments
    where shipment_order_id = v_leg.shipment_order_id and role = 'vehicle' and is_current and status = 'active';
  if v_vehicle_master_id is null then
    raise exception 'vehicle_not_assigned: leg % (shipment order %) has no current active vehicle resource assignment', p_shipment_leg_id, v_leg.shipment_order_id
      using errcode = 'check_violation';
  end if;

  -- Row lock on the vehicle's own operational profile -- see design note 3. Every
  -- reservation attempt against this vehicle acquires this same single row lock
  -- before reading the overlapping-reservation sum, serializing concurrent attempts.
  select * into v_profile from app.vehicle_operational_profiles
    where tenant_id = v_leg.tenant_id and vehicle_master_id = v_vehicle_master_id
    for update;
  if not found or v_profile.status <> 'active' then
    raise exception 'vehicle_not_active: vehicle % is not an active operational profile', v_vehicle_master_id using errcode = 'check_violation';
  end if;

  select coalesce(sum(requested_weight_kg), 0), coalesce(sum(requested_volume_cbm), 0)
    into v_reserved_weight, v_reserved_volume
    from app.vehicle_capacity_reservations
    where tenant_id = v_leg.tenant_id
      and vehicle_master_id = v_vehicle_master_id
      and shipment_leg_id <> p_shipment_leg_id
      and status in ('held', 'consumed')
      and window_start < v_leg.planned_arrival_at
      and window_end > v_leg.planned_departure_at;

  if p_requested_weight_kg is not null and v_profile.capacity_weight_kg is not null
    and (v_reserved_weight + p_requested_weight_kg) > v_profile.capacity_weight_kg
  then
    raise exception 'capacity_exceeded: vehicle % weight capacity % kg, already holding % kg over this window, requested % kg would exceed it',
      v_vehicle_master_id, v_profile.capacity_weight_kg, v_reserved_weight, p_requested_weight_kg
      using errcode = 'check_violation';
  end if;
  if p_requested_volume_cbm is not null and v_profile.capacity_volume_cbm is not null
    and (v_reserved_volume + p_requested_volume_cbm) > v_profile.capacity_volume_cbm
  then
    raise exception 'capacity_exceeded: vehicle % volume capacity % cbm, already holding % cbm over this window, requested % cbm would exceed it',
      v_vehicle_master_id, v_profile.capacity_volume_cbm, v_reserved_volume, p_requested_volume_cbm
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vehicle_capacity_reservations (
      tenant_id, shipment_leg_id, vehicle_master_id, idempotency_key,
      requested_weight_kg, requested_volume_cbm, window_start, window_end, created_by
    ) values (
      v_leg.tenant_id, p_shipment_leg_id, v_vehicle_master_id, p_idempotency_key,
      p_requested_weight_kg, p_requested_volume_cbm, v_leg.planned_departure_at, v_leg.planned_arrival_at, p_actor_label
    )
    returning * into v_reservation;
  exception
    when unique_violation then
      select * into v_reservation from app.vehicle_capacity_reservations
        where tenant_id = v_leg.tenant_id and shipment_leg_id = p_shipment_leg_id and idempotency_key = p_idempotency_key;
      if found then
        return v_reservation;
      end if;
      -- The pre-check above already covers the common case; this is a narrow
      -- defense-in-depth path for the disclosed single-threaded-sandbox race
      -- (design note 3) between that check and this insert.
      raise exception 'reservation_already_active: leg % already has an active (held/consumed) capacity reservation under a different idempotency key', p_shipment_leg_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_leg.tenant_id, p_actor_auth_user_id, p_actor_label, 'reserve_vehicle_capacity',
    'app.vehicle_capacity_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'vehicle_master_id', v_vehicle_master_id, 'requested_weight_kg', p_requested_weight_kg, 'requested_volume_cbm', p_requested_volume_cbm)
  );

  return v_reservation;
end;
$$;

comment on function app.reserve_vehicle_capacity is
  'ATW-227: idempotent on (tenant_id, shipment_leg_id, idempotency_key). The reserved vehicle is always the leg''s own current app.resource_assignments (OPS-172) role=vehicle occupant (design note 2) -- never caller-supplied. Locks app.vehicle_operational_profiles for the assigned vehicle before summing overlapping held/consumed reservations (design note 3), rejecting with capacity_exceeded when the sum plus this request would exceed the vehicle''s own capacity_weight_kg/capacity_volume_cbm (a null capacity dimension is an unbounded/unknown limit, never a fabricated one, and is simply not checked). At most one held/consumed reservation may exist per leg at a time (partial unique index).';

-- app.consume_vehicle_capacity_reservation -- dispatch actually committing the
-- vehicle to the leg (this prompt's own §21 main flow: "dispatch consumes it").
create function app.consume_vehicle_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vehicle_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vehicle_capacity_reservations;
begin
  select * into v_reservation from app.vehicle_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'check_violation';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: reservation % is % -- only a held reservation may be consumed', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vehicle_capacity_reservations set status = 'consumed' where id = p_reservation_id
    returning * into v_reservation;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'consume_vehicle_capacity_reservation',
    'app.vehicle_capacity_reservations', v_reservation.id, 'success', null, null, jsonb_build_object('shipment_leg_id', v_reservation.shipment_leg_id)
  );

  return v_reservation;
end;
$$;

comment on function app.consume_vehicle_capacity_reservation is
  'ATW-227: held -> consumed only, optimistic-concurrency gated (record_version). Consuming never re-checks capacity -- the held reservation already accounted for it; this is a status transition, not a second reservation attempt.';

-- app.release_vehicle_capacity_reservation -- covers both a normal completion/leg-
-- cancellation release and an explicit authorized early release; released_reason
-- discloses which (this prompt's own §14 "reserve/release/consume" three ops, no
-- separate cancel op).
create function app.release_vehicle_capacity_reservation(
  p_reservation_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vehicle_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vehicle_capacity_reservations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to release a capacity reservation' using errcode = 'check_violation';
  end if;

  select * into v_reservation from app.vehicle_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'check_violation';
  end if;
  if v_reservation.status = 'released' then
    raise exception 'invalid_transition: reservation % is already released', p_reservation_id using errcode = 'check_violation';
  end if;

  update app.vehicle_capacity_reservations set status = 'released', released_reason = p_reason where id = p_reservation_id
    returning * into v_reservation;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_vehicle_capacity_reservation',
    'app.vehicle_capacity_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', v_reservation.shipment_leg_id, 'reason', p_reason)
  );

  return v_reservation;
end;
$$;

comment on function app.release_vehicle_capacity_reservation is
  'ATW-227: held or consumed -> released, optimistic-concurrency gated, mandatory reason. Frees the vehicle''s own held/consumed capacity for this leg''s window immediately -- a subsequent app.reserve_vehicle_capacity call against an overlapping window on the same vehicle will no longer see this reservation in its sum.';

alter table app.vehicle_capacity_reservations enable row level security;

create policy vehicle_capacity_reservations_select_scoped on app.vehicle_capacity_reservations
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.vehicle_capacity_reservations to authenticated, service_role;
grant insert, update, delete on app.vehicle_capacity_reservations to service_role;

grant execute on function app.reserve_vehicle_capacity(uuid, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.consume_vehicle_capacity_reservation(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.release_vehicle_capacity_reservation(uuid, text, integer, uuid, text) to authenticated, service_role;

-- 2. Tracking coverage and subscription-utilization read projections. Read-only --
-- never mutates entitlement, source policy, or provider mapping (this prompt's own
-- §14 boundary, design note 4).

create function app.get_tenant_tracking_coverage(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  vehicle_master_id uuid,
  vehicle_code text,
  vehicle_name text,
  source_class text,
  coverage_status text,
  authoritative_source_type text,
  last_position_at timestamptz,
  has_active_provider_mapping boolean,
  capacity_weight_kg numeric,
  capacity_volume_cbm numeric,
  reserved_weight_kg numeric,
  reserved_volume_cbm numeric
)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy record;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_policy from app.resolve_tenant_tracking_source_policy(p_tenant_id);

  return query
  select
    vop.vehicle_master_id,
    mr.code,
    mr.name,
    case
      when not (vop.mobile_tracking_eligible or vop.direct_device_tracking_eligible or vop.third_party_tracking_eligible) then 'none'
      when (vop.mobile_tracking_eligible::int + vop.direct_device_tracking_eligible::int + vop.third_party_tracking_eligible::int) > 1 then 'hybrid'
      when vop.mobile_tracking_eligible then 'mobile_only'
      when vop.direct_device_tracking_eligible then 'direct_device_only'
      else 'third_party_only'
    end,
    case
      when not (vop.mobile_tracking_eligible or vop.direct_device_tracking_eligible or vop.third_party_tracking_eligible) then 'not_tracked'
      when vcp.received_at is null then 'offline'
      when now() - vcp.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval then 'tracked'
      when now() - vcp.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval * 3 then 'stale'
      else 'offline'
    end,
    vcp.source_type,
    vcp.received_at,
    exists (select 1 from app.provider_vehicle_mappings pvm where pvm.vehicle_master_id = vop.vehicle_master_id and pvm.status = 'active'),
    vop.capacity_weight_kg,
    vop.capacity_volume_cbm,
    (select coalesce(sum(r.requested_weight_kg), 0) from app.vehicle_capacity_reservations r
      where r.vehicle_master_id = vop.vehicle_master_id and r.status in ('held', 'consumed') and r.window_start <= now() and r.window_end >= now()),
    (select coalesce(sum(r.requested_volume_cbm), 0) from app.vehicle_capacity_reservations r
      where r.vehicle_master_id = vop.vehicle_master_id and r.status in ('held', 'consumed') and r.window_start <= now() and r.window_end >= now())
  from app.vehicle_operational_profiles vop
  join app.master_records mr on mr.id = vop.vehicle_master_id
  left join app.vehicle_current_positions vcp on vcp.vehicle_master_id = vop.vehicle_master_id
  where vop.tenant_id = p_tenant_id and vop.status = 'active'
  order by mr.code;
end;
$$;

comment on function app.get_tenant_tracking_coverage is
  'ATW-227: one row per active vehicle for a tenant -- coverage_status/source_class are computed on read (never a stored, potentially-stale column), reusing app.get_vehicle_source_health''s own 1x/3x freshness-threshold banding (226F) applied to the vehicle''s current winning source rather than per-source history. reserved_weight_kg/reserved_volume_cbm are this instant''s live utilization snapshot (window_start <= now() <= window_end), distinct from app.reserve_vehicle_capacity''s own leg-window overlap check.';

create type app.tenant_tracking_utilization_summary as (
  tracking_enabled boolean,
  package_code text,
  max_tracked_vehicles integer,
  max_mobile_sessions integer,
  total_active_vehicle_count integer,
  tracked_vehicle_count integer,
  stale_vehicle_count integer,
  offline_vehicle_count integer,
  not_tracked_vehicle_count integer,
  tracked_vehicle_limit_remaining integer,
  device_total_count integer,
  device_active_count integer,
  mobile_session_active_count integer,
  untracked_required_leg_count integer
);

create function app.get_tenant_tracking_utilization_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.tenant_tracking_utilization_summary
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.tracking_package_resolution;
  v_result app.tenant_tracking_utilization_summary;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_package := app.resolve_tenant_tracking_package(p_tenant_id);
  v_result.tracking_enabled := v_package.enabled;
  v_result.package_code := v_package.package_code;
  v_result.max_tracked_vehicles := v_package.max_tracked_vehicles;
  v_result.max_mobile_sessions := v_package.max_mobile_sessions;

  select
    count(*),
    count(*) filter (where coverage.coverage_status = 'tracked'),
    count(*) filter (where coverage.coverage_status = 'stale'),
    count(*) filter (where coverage.coverage_status = 'offline'),
    count(*) filter (where coverage.coverage_status = 'not_tracked')
    into
    v_result.total_active_vehicle_count,
    v_result.tracked_vehicle_count,
    v_result.stale_vehicle_count,
    v_result.offline_vehicle_count,
    v_result.not_tracked_vehicle_count
  from app.get_tenant_tracking_coverage(p_tenant_id, p_actor_auth_user_id) coverage;

  v_result.tracked_vehicle_count := coalesce(v_result.tracked_vehicle_count, 0) + coalesce(v_result.stale_vehicle_count, 0);
  if v_package.max_tracked_vehicles is not null then
    v_result.tracked_vehicle_limit_remaining := v_package.max_tracked_vehicles - v_result.tracked_vehicle_count;
  end if;

  select count(*), count(*) filter (where status = 'active') into v_result.device_total_count, v_result.device_active_count
    from app.gps_devices where tenant_id = p_tenant_id;

  select count(*) into v_result.mobile_session_active_count
    from app.driver_mobile_tracking_sessions where tenant_id = p_tenant_id and status = 'active';

  select count(*) into v_result.untracked_required_leg_count
    from app.shipment_legs leg
    join app.shipment_leg_tracking_policies pol on pol.shipment_leg_id = leg.id and pol.tracking_required
    where leg.tenant_id = p_tenant_id
      and leg.leg_status in ('dispatched', 'in_transit')
      and not exists (
        select 1 from app.shipment_leg_tracking_sessions sess
        where sess.shipment_leg_id = leg.id and sess.status = 'active' and sess.is_current
      );

  return v_result;
end;
$$;

comment on function app.get_tenant_tracking_utilization_summary is
  'ATW-227: one tenant-wide row, composing app.resolve_tenant_tracking_package (226A entitlement/limits), app.get_tenant_tracking_coverage (this migration''s own coverage read, stale counted as tracked for the subscription-limit comparison, distinct in its own right for display), app.gps_devices (223 device utilization), app.driver_mobile_tracking_sessions (226C active mobile-session compliance), and app.shipment_leg_tracking_policies/app.shipment_leg_tracking_sessions (225, tracking-required-but-untracked leg detection). Never mutates any of the tables it reads.';

grant execute on function app.get_tenant_tracking_coverage(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_tenant_tracking_utilization_summary(uuid, uuid) to authenticated, service_role;
