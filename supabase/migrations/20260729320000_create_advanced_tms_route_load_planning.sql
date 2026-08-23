-- Advanced TMS capability CG-S10-ATW-005 (Prompt 224, Route and Load Planning Using
-- Canonical Position). Implements explainable route and load planning that reads
-- location-dependent input through exactly one trusted, source-arbitrated
-- projection -- never raw mobile, direct-device, or third-party telemetry.
--
-- Design boundary (disclosed): `ATW-226F` (canonical telemetry storage,
-- normalization, ordering, and source arbitration) has not been built yet -- this
-- repository's own `app.shipment_tracking_health` (ATW-222) is already the single
-- canonical per-shipment tracking-health *projection* Prompt 224 §6/§14 require
-- planning to read through, and it remains a genuinely real, empty, honest table
-- (`tracking_status = 'not_tracked'` for every row) until ATW-226F ships a live
-- writer. This migration therefore never invents a second position-input surface --
-- `app.get_canonical_position_for_planning()` reads `app.shipment_tracking_health`
-- directly (LEFT JOIN, identical to ATW-222's own dispatch-board read model) and
-- reports the same honest `not_tracked`/`unknown` projection every caller sees today.
-- Prompt 224 §22's own alternative flow ("plan manually when no trusted position
-- exists") is therefore this checkpoint's *real, exercised* path, not a theoretical
-- fallback -- every scenario validated against this repository's current state
-- degrades to position-unaware planning, which is the honest, correct outcome, never
-- a fabricated live position (§16/§33's own "no false optimality" and "no raw
-- telemetry dependency" acceptance criteria).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **One RPC per row-level mutation, mirroring `ATW-221`'s own established
--   granularity** (`app.add_shipment_leg` / `app.add_shipment_leg_stop` /
--   `app.allocate_shipment_leg_cargo`, never a single bulk-jsonb-array entry point).
--   A planning scenario is prepared empty (`app.prepare_route_planning_scenario`),
--   then stops and constraints are added one at a time
--   (`app.add_route_planning_stop` / `app.add_route_planning_constraint`), both
--   gated to the scenario's own `draft` status exactly as `ATW-221`'s "started-leg
--   destructive edit prevention" gates stop/cargo edits to `planned` legs.
-- * **The deterministic baseline planner is genuinely bounded and capacity-fit
--   driven, not a claimed-optimal routing/TSP solver.** Every candidate for one
--   scenario shares the identical stop sequence (this checkpoint does not
--   re-order stops) and the identical governed default speed constant
--   (`app.route_planning_default_speed_kmh()` = 40 km/h, a disclosed reasoned
--   default in the same "no blueprint-mandated number exists for this dimension"
--   class `ADR-0002`/`ADR-0004`/`ADR-0011`/`ADR-0012`/`ADR-0013`/`ADR-0014` already
--   used -- not minted as its own ADR since it is a coarse duration *label* for
--   human review, never a governed enforcement threshold). What genuinely
--   differentiates candidates is resource capacity fit: up to 3 active
--   vehicle/driver pairs are ranked by tightest sufficient capacity match
--   (least wasted `capacity_weight_kg`), each candidate's score components stored
--   individually for explainability (Prompt 224 §4's own "explainable" requirement).
--   Hard constraints that depend on a later-known fact (`max_distance_km`, computed
--   only once stops are geocoded and summed) are enforced at candidate-generation
--   time; hard constraints that name a specific resource
--   (`required_vehicle_master_id`/`required_driver_master_id`) are checked for
--   existence/eligibility at validation time -- both stages disclosed here, not
--   left implicit.
-- * **"Async jobs" reuses `PLT-132`'s own generic `app.jobs` queue verbatim**, adding
--   exactly one new `job_type` (`route_load_planning`) to the already-widened
--   `jobs_job_type_check` constraint and to `app.enqueue_job`'s own
--   `v_valid_job_types` array (both via `CREATE OR REPLACE`/`ALTER ... DROP
--   CONSTRAINT` + `ADD CONSTRAINT`, the identical extension mechanic PLT-132's own
--   migration header already used for `record_job_failure`). No live continuous
--   worker-polling process exists anywhere in this repository yet (`NOT_RUN`,
--   the same disclosed class PLT-132's own header, PLT-123's escalation timer, and
--   PLT-125's numbering counter already carry) -- `app.run_next_route_planning_job`
--   is the real, directly-invokable domain worker entry point
--   (`app.claim_next_job` -> deterministic planner -> `app.complete_job` /
--   `app.record_job_failure`), proven by this checkpoint's own db-test invoking it
--   directly, exactly the "mechanism proven, live wiring deferred" posture PLT-132's
--   own claim/complete lifecycle already established.
-- * **Selection history follows `app.device_vehicle_assignments`' own
--   `is_current`/`superseded_by_id` precedent** (ATW-223) -- a human selection is
--   never overwritten in place, always superseded, preserving the full decision
--   trail an override must be able to point back to.
-- * **Planning is decision support only (Prompt 224 §24 business rule 1) --
--   this migration never mutates `app.shipment_legs`.** Selecting or overriding a
--   plan records the human decision; a dispatcher still executes it through
--   `ATW-221`'s own existing leg/assignment mutations exactly as today. Replanning
--   (`app.replan_route_planning_scenario`) copies the prior scenario's own stops
--   and constraints into a fresh `draft` scenario and blocks only the one concrete
--   case this checkpoint can actually prove: every one of the shipment's own legs
--   already left `planned` (nothing left to replan). `ATW-228` (Advanced Milestone
--   and Exception) does not exist yet, so the "approved tracking-derived exception"
--   trigger named in Prompt 224 §22 is captured here as a disclosed, audited
--   free-text `p_reason` only, never a verified upstream exception record --
--   `ATW-228` will supply the structured trigger once it ships.
-- * **Record-scope reuses `app.can_access_record`/`app.lead_record_scope_org_unit_ids`
--   joined through to the owning Shipment Order**, identical to `ATW-221`'s own
--   `shipment_legs`/`shipment_leg_stops` policy shape (a planning scenario has no
--   owner/org-unit column of its own).
-- * Permission catalogue: reuses the already-seeded `OPS` action set (`Create`,
--   `Edit`, `Override`) -- no new `app.permissions` row, no new module code.
--   `Override` (an existing `OPS` workflow action, not new) is the concrete
--   mechanism behind Prompt 224 §26's "managers approve configured overrides."
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its
--   own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC`
--   statement before its final grants, the standing per-migration convention since
--   `PLT-118`.

-- === Widen the shared job queue for the one new domain job_type this task needs ===

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry',
    'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing',
    'integration_sync', 'route_load_planning'
  )
);

create or replace function app.enqueue_job(
  p_tenant_id uuid,
  p_job_type text,
  p_payload jsonb,
  p_priority integer,
  p_idempotency_key text,
  p_max_attempts integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning'
  ];
begin
  if not app.check_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_type in ('import', 'export') then
    raise exception 'job_type_requires_dedicated_entrypoint: % jobs must be created via app.create_import_export_job()', p_job_type
      using errcode = 'check_violation';
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'job_invalid_type: % is not a known generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_payload, '{}'::jsonb)) then
    raise exception 'job_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_max_attempts, 3) <= 0 then
    raise exception 'job_invalid_max_attempts: max_attempts must be positive'
      using errcode = 'check_violation';
  end if;

  insert into app.jobs (
    tenant_id, job_type, payload, priority, max_attempts, idempotency_key,
    requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_job_type, coalesce(p_payload, '{}'::jsonb), coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_job;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type)
  );

  return v_job;
end;
$$;

-- === Schema ===

create table app.route_planning_scenarios (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  idempotency_key text not null,
  status text not null default 'draft',
  requested_weight_kg numeric,
  requested_volume_cbm numeric,
  job_id uuid references app.jobs (job_id),
  canonical_position_snapshot jsonb,
  canonical_position_captured_at timestamptz,
  owner_user_id uuid references auth.users (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint route_planning_scenarios_status_check check (status in ('draft', 'validated', 'executing', 'ready', 'selected', 'cancelled', 'failed')),
  constraint route_planning_scenarios_requested_weight_check check (requested_weight_kg is null or requested_weight_kg >= 0),
  constraint route_planning_scenarios_requested_volume_check check (requested_volume_cbm is null or requested_volume_cbm >= 0),
  constraint route_planning_scenarios_tenant_shipment_idempotency_unique unique (tenant_id, shipment_order_id, idempotency_key)
);

comment on table app.route_planning_scenarios is
  'ATW-224: one route/load planning request against one Shipment Order. Never mutates app.shipment_legs -- planning is decision support only (Prompt 224 §24). canonical_position_snapshot is captured (honest, currently always not_tracked/no_position -- see this migration''s own header) at app.validate_route_planning_scenario time.';

create index route_planning_scenarios_tenant_shipment_idx on app.route_planning_scenarios (tenant_id, shipment_order_id);
create index route_planning_scenarios_tenant_status_idx on app.route_planning_scenarios (tenant_id, status);

create function app.touch_route_planning_scenarios_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger route_planning_scenarios_touch_row
  before update on app.route_planning_scenarios
  for each row
  execute function app.touch_route_planning_scenarios_row();

create table app.route_planning_stops (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scenario_id uuid not null references app.route_planning_scenarios (id),
  stop_sequence integer not null,
  stop_type text not null,
  location_name text not null,
  address text,
  location_geog geography (point, 4326),
  time_window_start timestamptz,
  time_window_end timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  constraint route_planning_stops_type_check check (stop_type in ('pickup', 'transfer', 'delivery')),
  constraint route_planning_stops_sequence_positive_check check (stop_sequence > 0),
  constraint route_planning_stops_geog_check check (location_geog is null or app.validate_geography_point(location_geog)),
  constraint route_planning_stops_time_window_check check (time_window_start is null or time_window_end is null or time_window_end >= time_window_start),
  constraint route_planning_stops_tenant_scenario_sequence_unique unique (tenant_id, scenario_id, stop_sequence)
);

comment on table app.route_planning_stops is
  'ATW-224: one ordered stop within one planning scenario. Only addable while the owning scenario is still draft (app.add_route_planning_stop). location_geog follows the PLT-134 convention (geography(Point,4326), via app.geojson_point_to_geography).';

create index route_planning_stops_tenant_scenario_idx on app.route_planning_stops (tenant_id, scenario_id);
create index route_planning_stops_geog_idx on app.route_planning_stops using gist (location_geog);

create table app.route_planning_constraints (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scenario_id uuid not null references app.route_planning_scenarios (id),
  constraint_type text not null,
  constraint_key text not null,
  constraint_value jsonb not null,
  created_by text,
  created_at timestamptz not null default now(),
  constraint route_planning_constraints_type_check check (constraint_type in ('hard', 'soft')),
  constraint route_planning_constraints_key_check check (constraint_key in (
    'max_weight_kg', 'max_volume_cbm', 'max_distance_km', 'required_vehicle_master_id',
    'required_driver_master_id', 'earliest_departure_at', 'latest_arrival_at'
  )),
  constraint route_planning_constraints_tenant_scenario_key_unique unique (tenant_id, scenario_id, constraint_key)
);

comment on table app.route_planning_constraints is
  'ATW-224: one constraint (hard or soft) within one planning scenario, one row per constraint_key (upsert via app.add_route_planning_constraint). constraint_value shape depends on constraint_key: numeric keys carry {"value": number}, resource-reference keys carry {"master_id": uuid}, timestamp keys carry {"at": timestamptz}.';

create index route_planning_constraints_tenant_scenario_idx on app.route_planning_constraints (tenant_id, scenario_id);

create table app.route_planning_candidate_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scenario_id uuid not null references app.route_planning_scenarios (id),
  plan_rank integer not null,
  algorithm_version text not null default 'baseline-v1',
  feasible boolean not null,
  infeasibility_reasons jsonb,
  vehicle_master_id uuid references app.master_records (id),
  driver_master_id uuid references app.master_records (id),
  total_distance_km numeric,
  estimated_duration_minutes numeric,
  capacity_utilization_pct numeric,
  generated_at timestamptz not null default now(),
  constraint route_planning_candidate_plans_rank_positive_check check (plan_rank > 0),
  constraint route_planning_candidate_plans_distance_check check (total_distance_km is null or total_distance_km >= 0),
  constraint route_planning_candidate_plans_duration_check check (estimated_duration_minutes is null or estimated_duration_minutes >= 0),
  constraint route_planning_candidate_plans_utilization_check check (capacity_utilization_pct is null or capacity_utilization_pct >= 0),
  constraint route_planning_candidate_plans_tenant_scenario_rank_unique unique (tenant_id, scenario_id, plan_rank)
);

comment on table app.route_planning_candidate_plans is
  'ATW-224: one deterministic baseline-planner candidate for one scenario (app.generate_route_planning_candidates, bounded to at most 3 feasible candidates plus, when nothing is feasible, exactly one infeasible placeholder). plan_rank 1 is the best-ranked candidate (tightest sufficient capacity fit) -- never claimed globally optimal (Prompt 224 §33 "no false optimality").';

create index route_planning_candidate_plans_tenant_scenario_idx on app.route_planning_candidate_plans (tenant_id, scenario_id);

create table app.route_planning_score_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  candidate_plan_id uuid not null references app.route_planning_candidate_plans (id),
  component_key text not null,
  component_value numeric,
  created_at timestamptz not null default now(),
  constraint route_planning_score_components_key_check check (component_key in ('total_distance_km', 'estimated_duration_minutes', 'capacity_utilization_pct')),
  constraint route_planning_score_components_tenant_candidate_key_unique unique (tenant_id, candidate_plan_id, component_key)
);

comment on table app.route_planning_score_components is
  'ATW-224: the explainability breakdown behind each candidate plan''s own summary columns (Prompt 224 §4 "explainable route and load planning") -- one row per scored dimension, never collapsed into a single opaque number.';

create index route_planning_score_components_tenant_candidate_idx on app.route_planning_score_components (tenant_id, candidate_plan_id);

create table app.route_planning_selected_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scenario_id uuid not null references app.route_planning_scenarios (id),
  candidate_plan_id uuid not null references app.route_planning_candidate_plans (id),
  is_current boolean not null default true,
  superseded_by_id uuid references app.route_planning_selected_plans (id),
  is_override boolean not null default false,
  override_reason text,
  selected_by text,
  selected_at timestamptz not null default now(),
  constraint route_planning_selected_plans_override_reason_check check (not is_override or (override_reason is not null and length(trim(override_reason)) > 0))
);

comment on table app.route_planning_selected_plans is
  'ATW-224: the human selection decision for one scenario -- never overwritten in place, always superseded (is_current/superseded_by_id, identical to app.device_vehicle_assignments'' own history-preservation precedent, ATW-223). is_override marks a selection made via app.override_route_planning_selection (OPS:Override authority, a non-empty override_reason always required).';

create index route_planning_selected_plans_tenant_scenario_idx on app.route_planning_selected_plans (tenant_id, scenario_id);
create unique index route_planning_selected_plans_current_scenario_unique on app.route_planning_selected_plans (scenario_id) where is_current;

create table app.route_planning_replan_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scenario_id uuid not null references app.route_planning_scenarios (id),
  previous_scenario_id uuid not null references app.route_planning_scenarios (id),
  trigger_reason text not null,
  canonical_position_snapshot jsonb,
  triggered_by text,
  triggered_at timestamptz not null default now(),
  constraint route_planning_replan_events_reason_check check (length(trim(trigger_reason)) > 0)
);

comment on table app.route_planning_replan_events is
  'ATW-224: append-only replan lineage -- one row per app.replan_route_planning_scenario call, linking the freshly created draft scenario back to the one it replaced. trigger_reason is a disclosed, audited free-text justification only (ATW-228''s own structured exception trigger does not exist yet -- see this migration''s own header).';

create index route_planning_replan_events_tenant_scenario_idx on app.route_planning_replan_events (tenant_id, scenario_id);
create index route_planning_replan_events_previous_scenario_idx on app.route_planning_replan_events (previous_scenario_id);

-- === Governed constants ===

create function app.route_planning_default_speed_kmh()
returns numeric
language sql
immutable
as $$
  select 40::numeric;
$$;

comment on function app.route_planning_default_speed_kmh is
  'ATW-224: the one governed default speed (km/h) app.generate_route_planning_candidates uses to label estimated_duration_minutes -- a disclosed reasoned default (this migration''s own header), a coarse human-review label, never a routing-engine claim.';

create function app.route_planning_position_staleness_tolerance_seconds()
returns integer
language sql
immutable
as $$
  select 300::integer;
$$;

comment on function app.route_planning_position_staleness_tolerance_seconds is
  'ATW-224: the governed freshness tolerance (seconds) app.get_canonical_position_for_planning applies -- a disclosed reasoned default matching the same class as app.route_planning_default_speed_kmh(). Currently unreachable in practice: app.shipment_tracking_health has no live writer yet (ATW-226F), so every read reports not_tracked/unknown and this tolerance is never the deciding factor.';

-- === Canonical position input contract ===

-- The one governed read path for location-dependent planning input (Prompt 224 §6/
-- §14). Reads app.shipment_tracking_health (ATW-222) directly -- never a second
-- position surface. Honest by construction: until ATW-226F ships a live writer,
-- every row is absent and this function reports the same not_tracked/unknown
-- projection app.shipment_tracking_health already reports everywhere else.
create function app.get_canonical_position_for_planning(p_shipment_order_id uuid)
returns table (
  tracking_status text,
  freshness_status text,
  accuracy_meters numeric,
  last_position_at timestamptz,
  authoritative_source_type text,
  tracking_entitled boolean,
  is_usable boolean
)
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select
    coalesce(th.tracking_status, 'not_tracked') as tracking_status,
    th.freshness_status,
    th.accuracy_meters,
    th.last_position_at,
    th.authoritative_source_type,
    app.is_shipment_tracking_entitled(so.tenant_id) as tracking_entitled,
    (
      coalesce(th.tracking_status, 'not_tracked') = 'tracked'
      and th.freshness_status = 'fresh'
      and th.last_position_at is not null
      and th.last_position_at >= now() - (app.route_planning_position_staleness_tolerance_seconds() || ' seconds')::interval
    ) as is_usable
  from app.shipment_orders so
  left join app.shipment_tracking_health th on th.shipment_order_id = so.id
  where so.id = p_shipment_order_id;
$$;

comment on function app.get_canonical_position_for_planning is
  'ATW-224: the sole canonical-position read path for planning. is_usable is the concrete stale-position policy (Prompt 224 §24 "stale positions are rejected or explicitly degraded") -- false whenever tracking_status/freshness_status/last_position_at do not together prove a fresh, in-tolerance position, which is every row today (ATW-226F has not shipped). security invoker: relies on the caller''s own RLS on app.shipment_tracking_health/app.shipment_orders, matching every other plain projection function in this repository.';

-- === Mutations ===

-- app.prepare_route_planning_scenario -- creates an empty draft scenario. Idempotent
-- on (tenant_id, shipment_order_id, idempotency_key).
create function app.prepare_route_planning_scenario(
  p_shipment_order_id uuid,
  p_idempotency_key text,
  p_requested_weight_kg numeric,
  p_requested_volume_cbm numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_scenarios
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.route_planning_scenarios;
  v_scenario app.route_planning_scenarios;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.route_planning_scenarios
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
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

  if p_requested_weight_kg is not null and p_requested_weight_kg < 0 then
    raise exception 'invalid_requested_weight: requested_weight_kg must not be negative' using errcode = 'check_violation';
  end if;
  if p_requested_volume_cbm is not null and p_requested_volume_cbm < 0 then
    raise exception 'invalid_requested_volume: requested_volume_cbm must not be negative' using errcode = 'check_violation';
  end if;

  begin
    insert into app.route_planning_scenarios (
      tenant_id, shipment_order_id, idempotency_key, requested_weight_kg, requested_volume_cbm, owner_user_id, created_by
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, p_idempotency_key, p_requested_weight_kg, p_requested_volume_cbm, v_shipment.owner_user_id, p_actor_label
    )
    returning * into v_scenario;
  exception
    when unique_violation then
      select * into v_scenario from app.route_planning_scenarios
        where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
      return v_scenario;
  end;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id)
  );

  return v_scenario;
end;
$$;

comment on function app.prepare_route_planning_scenario is
  'ATW-224: idempotent on (tenant_id, shipment_order_id, idempotency_key). Creates an empty draft scenario -- stops/constraints are added afterward via app.add_route_planning_stop/app.add_route_planning_constraint.';

-- app.add_route_planning_stop -- only while the owning scenario is draft.
create function app.add_route_planning_stop(
  p_scenario_id uuid,
  p_stop_sequence integer,
  p_stop_type text,
  p_location_name text,
  p_address text,
  p_longitude numeric,
  p_latitude numeric,
  p_time_window_start timestamptz,
  p_time_window_end timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_stops
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_stop app.route_planning_stops;
  v_geog geography;
begin
  if p_stop_type not in ('pickup', 'transfer', 'delivery') then
    raise exception 'invalid_stop_type: % is not a supported stop type', p_stop_type using errcode = 'check_violation';
  end if;

  if p_stop_sequence is null or p_stop_sequence <= 0 then
    raise exception 'invalid_sequence: stop_sequence must be a positive integer' using errcode = 'check_violation';
  end if;

  if p_location_name is null or length(trim(p_location_name)) = 0 then
    raise exception 'location_name_required: a non-empty location_name is required' using errcode = 'check_violation';
  end if;

  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.status <> 'draft' then
    raise exception 'scenario_not_mutable: scenario % is % and its stops can only be edited while draft', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_longitude is not null and p_latitude is not null then
    v_geog := app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(p_longitude, p_latitude)));
  end if;

  insert into app.route_planning_stops (
    tenant_id, scenario_id, stop_sequence, stop_type, location_name, address, location_geog, time_window_start, time_window_end, created_by
  ) values (
    v_scenario.tenant_id, p_scenario_id, p_stop_sequence, p_stop_type, p_location_name, p_address, v_geog, p_time_window_start, p_time_window_end, p_actor_label
  )
  returning * into v_stop;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_route_planning_stop',
    'app.route_planning_stops', v_stop.id, 'success', null, null,
    jsonb_build_object('scenario_id', p_scenario_id, 'stop_sequence', p_stop_sequence, 'stop_type', p_stop_type)
  );

  return v_stop;
end;
$$;

comment on function app.add_route_planning_stop is
  'ATW-224: only while the owning scenario is draft. location_geog is built via app.geojson_point_to_geography (PLT-134 convention) when longitude/latitude are both supplied.';

-- app.add_route_planning_constraint -- upsert on (scenario_id, constraint_key), only
-- while the owning scenario is draft.
create function app.add_route_planning_constraint(
  p_scenario_id uuid,
  p_constraint_type text,
  p_constraint_key text,
  p_constraint_value jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_constraints
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_constraint app.route_planning_constraints;
begin
  if p_constraint_type not in ('hard', 'soft') then
    raise exception 'invalid_constraint_type: % is not a supported constraint type', p_constraint_type using errcode = 'check_violation';
  end if;

  if p_constraint_key not in (
    'max_weight_kg', 'max_volume_cbm', 'max_distance_km', 'required_vehicle_master_id',
    'required_driver_master_id', 'earliest_departure_at', 'latest_arrival_at'
  ) then
    raise exception 'invalid_constraint_key: % is not a supported constraint key', p_constraint_key using errcode = 'check_violation';
  end if;

  if p_constraint_key in ('max_weight_kg', 'max_volume_cbm', 'max_distance_km') then
    if p_constraint_value is null or jsonb_typeof(p_constraint_value -> 'value') <> 'number' or (p_constraint_value ->> 'value')::numeric <= 0 then
      raise exception 'invalid_constraint_value: % requires {"value": <positive number>}', p_constraint_key using errcode = 'check_violation';
    end if;
  elsif p_constraint_key in ('required_vehicle_master_id', 'required_driver_master_id') then
    if p_constraint_value is null or jsonb_typeof(p_constraint_value -> 'master_id') <> 'string' then
      raise exception 'invalid_constraint_value: % requires {"master_id": <uuid>}', p_constraint_key using errcode = 'check_violation';
    end if;
  else
    if p_constraint_value is null or jsonb_typeof(p_constraint_value -> 'at') <> 'string' then
      raise exception 'invalid_constraint_value: % requires {"at": <timestamptz>}', p_constraint_key using errcode = 'check_violation';
    end if;
  end if;

  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.status <> 'draft' then
    raise exception 'scenario_not_mutable: scenario % is % and its constraints can only be edited while draft', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.route_planning_constraints (tenant_id, scenario_id, constraint_type, constraint_key, constraint_value, created_by)
  values (v_scenario.tenant_id, p_scenario_id, p_constraint_type, p_constraint_key, p_constraint_value, p_actor_label)
  on conflict (tenant_id, scenario_id, constraint_key) do update set
    constraint_type = excluded.constraint_type,
    constraint_value = excluded.constraint_value
  returning * into v_constraint;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_route_planning_constraint',
    'app.route_planning_constraints', v_constraint.id, 'success', null, null,
    jsonb_build_object('scenario_id', p_scenario_id, 'constraint_key', p_constraint_key, 'constraint_type', p_constraint_type)
  );

  return v_constraint;
end;
$$;

comment on function app.add_route_planning_constraint is
  'ATW-224: one constraint per constraint_key (upsert), only while the owning scenario is draft. Structural value-shape validation only here -- resource-reference existence and distance/time feasibility are checked later (app.validate_route_planning_scenario / app.generate_route_planning_candidates), disclosed in this migration''s own header.';

-- app.validate_route_planning_scenario (Prompt 224 §20 "define hard/soft constraints
-- and stale-position policy"). Requires >=2 stops forming a contiguous 1..N
-- sequence, resolves any resource-reference hard constraint, and captures the
-- canonical-position snapshot (honest, currently always degraded -- see header).
create function app.validate_route_planning_scenario(
  p_scenario_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_scenarios
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_stop_count integer;
  v_max_sequence integer;
  v_distinct_sequence_count integer;
  v_constraint record;
  v_position record;
  v_snapshot jsonb;
begin
  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status <> 'draft' then
    raise exception 'scenario_not_mutable: scenario % is % and can only be validated from draft', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*), max(stop_sequence), count(distinct stop_sequence)
    into v_stop_count, v_max_sequence, v_distinct_sequence_count
  from app.route_planning_stops where scenario_id = p_scenario_id;

  if v_stop_count < 2 then
    raise exception 'stops_insufficient: scenario % has % stop(s), at least 2 are required', p_scenario_id, v_stop_count
      using errcode = 'check_violation';
  end if;
  if v_distinct_sequence_count <> v_stop_count or v_max_sequence <> v_stop_count then
    raise exception 'stop_sequence_gap: scenario % stops must form a contiguous 1..% sequence with no gap or duplicate', p_scenario_id, v_stop_count
      using errcode = 'check_violation';
  end if;

  for v_constraint in select * from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_type = 'hard'
  loop
    if v_constraint.constraint_key = 'required_vehicle_master_id' then
      if not exists (
        select 1 from app.vehicle_operational_profiles
        where vehicle_master_id = (v_constraint.constraint_value ->> 'master_id')::uuid
          and tenant_id = v_scenario.tenant_id and status = 'active'
      ) then
        raise exception 'required_vehicle_not_found: % is not a known active vehicle operational profile for tenant %', v_constraint.constraint_value ->> 'master_id', v_scenario.tenant_id
          using errcode = 'no_data_found';
      end if;
    elsif v_constraint.constraint_key = 'required_driver_master_id' then
      if not exists (
        select 1 from app.driver_operational_profiles
        where driver_master_id = (v_constraint.constraint_value ->> 'master_id')::uuid
          and tenant_id = v_scenario.tenant_id and status = 'active'
      ) then
        raise exception 'required_driver_not_found: % is not a known active driver operational profile for tenant %', v_constraint.constraint_value ->> 'master_id', v_scenario.tenant_id
          using errcode = 'no_data_found';
      end if;
    end if;
  end loop;

  select * into v_position from app.get_canonical_position_for_planning(v_scenario.shipment_order_id);
  v_snapshot := jsonb_build_object(
    'tracking_status', v_position.tracking_status,
    'freshness_status', v_position.freshness_status,
    'accuracy_meters', v_position.accuracy_meters,
    'last_position_at', v_position.last_position_at,
    'authoritative_source_type', v_position.authoritative_source_type,
    'tracking_entitled', v_position.tracking_entitled,
    'is_usable', v_position.is_usable
  );

  update app.route_planning_scenarios
  set status = 'validated', canonical_position_snapshot = v_snapshot, canonical_position_captured_at = now()
  where id = p_scenario_id and record_version = p_expected_version
  returning * into v_scenario;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'validate_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null,
    jsonb_build_object('stop_count', v_stop_count, 'position_usable', v_position.is_usable)
  );

  return v_scenario;
end;
$$;

comment on function app.validate_route_planning_scenario is
  'ATW-224: requires a contiguous 1..N stop sequence (>=2 stops) and resolves any required_vehicle/driver_master_id hard constraint against an active operational profile. Captures the canonical-position snapshot via app.get_canonical_position_for_planning -- never blocks on an unusable/absent position (Prompt 224 §22''s own "plan manually" alternative flow), only records it honestly.';

-- app.execute_route_planning_scenario -- enqueues the deterministic planner as an
-- async app.jobs row (job_type = 'route_load_planning').
create function app.execute_route_planning_scenario(
  p_scenario_id uuid,
  p_expected_version integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_scenarios
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_job app.jobs;
begin
  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status <> 'validated' then
    raise exception 'scenario_not_mutable: scenario % is % and can only execute from validated', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_job := app.enqueue_job(
    v_shipment.tenant_id, 'route_load_planning', jsonb_build_object('scenario_id', p_scenario_id), 0,
    p_idempotency_key, 3, p_actor_auth_user_id, p_actor_label
  );

  update app.route_planning_scenarios
  set status = 'executing', job_id = v_job.job_id
  where id = p_scenario_id and record_version = p_expected_version
  returning * into v_scenario;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id)
  );

  return v_scenario;
end;
$$;

comment on function app.execute_route_planning_scenario is
  'ATW-224: validated -> executing. Enqueues one app.jobs row (job_type = route_load_planning) via app.enqueue_job; app.run_next_route_planning_job is the real worker entry point that later claims and runs it.';

-- app.generate_route_planning_candidates -- the deterministic baseline planner
-- (Prompt 224 §20 task 3). Internal to app.run_next_route_planning_job, but granted
-- execute like every other function in this migration (matching
-- app.next_shipment_leg_custody_sequence's own precedent, ATW-221).
create function app.generate_route_planning_candidates(
  p_scenario_id uuid,
  p_actor_label text
)
returns setof app.route_planning_candidate_plans
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_scenario app.route_planning_scenarios;
  v_total_distance_km numeric;
  v_distance_known boolean := true;
  v_prev_geog geography;
  v_cur_geog geography;
  v_first_stop app.route_planning_stops;
  v_last_stop app.route_planning_stops;
  v_max_weight numeric;
  v_max_volume numeric;
  v_max_distance numeric;
  v_required_vehicle uuid;
  v_required_driver uuid;
  v_earliest_departure timestamptz;
  v_latest_arrival timestamptz;
  v_effective_weight numeric;
  v_effective_volume numeric;
  v_reasons jsonb := '[]'::jsonb;
  v_vehicle record;
  v_drivers uuid[];
  v_driver_count integer;
  v_rank integer := 0;
  v_candidate app.route_planning_candidate_plans;
  v_duration numeric;
  v_utilization numeric;
  v_vehicle_exists boolean;
  r record;
begin
  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  delete from app.route_planning_score_components where candidate_plan_id in (
    select id from app.route_planning_candidate_plans where scenario_id = p_scenario_id
  );
  delete from app.route_planning_candidate_plans where scenario_id = p_scenario_id;

  v_total_distance_km := 0;
  v_prev_geog := null;
  for r in select * from app.route_planning_stops where scenario_id = p_scenario_id order by stop_sequence asc
  loop
    if v_prev_geog is not null then
      if r.location_geog is null then
        v_distance_known := false;
      else
        v_total_distance_km := v_total_distance_km + (ST_Distance(v_prev_geog, r.location_geog) / 1000.0);
      end if;
    end if;
    v_prev_geog := r.location_geog;
  end loop;
  if not v_distance_known then
    v_total_distance_km := null;
  end if;

  select * into v_first_stop from app.route_planning_stops where scenario_id = p_scenario_id order by stop_sequence asc limit 1;
  select * into v_last_stop from app.route_planning_stops where scenario_id = p_scenario_id order by stop_sequence desc limit 1;

  select (constraint_value ->> 'value')::numeric into v_max_weight from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'max_weight_kg' and constraint_type = 'hard';
  select (constraint_value ->> 'value')::numeric into v_max_volume from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'max_volume_cbm' and constraint_type = 'hard';
  select (constraint_value ->> 'value')::numeric into v_max_distance from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'max_distance_km' and constraint_type = 'hard';
  select (constraint_value ->> 'master_id')::uuid into v_required_vehicle from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'required_vehicle_master_id' and constraint_type = 'hard';
  select (constraint_value ->> 'master_id')::uuid into v_required_driver from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'required_driver_master_id' and constraint_type = 'hard';
  select (constraint_value ->> 'at')::timestamptz into v_earliest_departure from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'earliest_departure_at' and constraint_type = 'hard';
  select (constraint_value ->> 'at')::timestamptz into v_latest_arrival from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'latest_arrival_at' and constraint_type = 'hard';

  v_effective_weight := coalesce(v_max_weight, v_scenario.requested_weight_kg);
  v_effective_volume := coalesce(v_max_volume, v_scenario.requested_volume_cbm);

  if v_max_distance is not null and v_total_distance_km is not null and v_total_distance_km > v_max_distance then
    v_reasons := v_reasons || jsonb_build_array('max_distance_exceeded');
  end if;
  if v_earliest_departure is not null and v_first_stop.time_window_start is not null and v_first_stop.time_window_start < v_earliest_departure then
    v_reasons := v_reasons || jsonb_build_array('earliest_departure_violated');
  end if;
  if v_latest_arrival is not null and v_last_stop.time_window_end is not null and v_last_stop.time_window_end > v_latest_arrival then
    v_reasons := v_reasons || jsonb_build_array('latest_arrival_violated');
  end if;

  select array_agg(driver_master_id order by driver_master_id) into v_drivers
  from app.driver_operational_profiles
  where tenant_id = v_scenario.tenant_id and status = 'active'
    and (v_required_driver is null or driver_master_id = v_required_driver);
  v_driver_count := coalesce(array_length(v_drivers, 1), 0);

  if v_driver_count = 0 then
    v_reasons := v_reasons || jsonb_build_array(case when v_required_driver is not null then 'required_driver_unavailable' else 'no_eligible_driver' end);
  end if;

  select exists (
    select 1 from app.vehicle_operational_profiles
    where tenant_id = v_scenario.tenant_id and status = 'active'
      and (v_required_vehicle is null or vehicle_master_id = v_required_vehicle)
      and (v_effective_weight is null or capacity_weight_kg is null or capacity_weight_kg >= v_effective_weight)
      and (v_effective_volume is null or capacity_volume_cbm is null or capacity_volume_cbm >= v_effective_volume)
  ) into v_vehicle_exists;

  if not v_vehicle_exists then
    v_reasons := v_reasons || jsonb_build_array(case when v_required_vehicle is not null then 'required_vehicle_unavailable' else 'no_eligible_vehicle' end);
  end if;

  if jsonb_array_length(v_reasons) > 0 then
    insert into app.route_planning_candidate_plans (tenant_id, scenario_id, plan_rank, feasible, infeasibility_reasons, total_distance_km)
    values (v_scenario.tenant_id, p_scenario_id, 1, false, v_reasons, v_total_distance_km)
    returning * into v_candidate;

    insert into app.route_planning_score_components (tenant_id, candidate_plan_id, component_key, component_value)
    values (v_scenario.tenant_id, v_candidate.id, 'total_distance_km', v_total_distance_km);

    update app.route_planning_scenarios set status = 'ready' where id = p_scenario_id;

    perform app.capture_audit_event(
      v_scenario.tenant_id, null, p_actor_label, 'generate_route_planning_candidates',
      'app.route_planning_scenarios', p_scenario_id, 'success', null, null,
      jsonb_build_object('feasible_count', 0)
    );

    return query select * from app.route_planning_candidate_plans where scenario_id = p_scenario_id;
    return;
  end if;

  for v_vehicle in
    select * from app.vehicle_operational_profiles
    where tenant_id = v_scenario.tenant_id and status = 'active'
      and (v_required_vehicle is null or vehicle_master_id = v_required_vehicle)
      and (v_effective_weight is null or capacity_weight_kg is null or capacity_weight_kg >= v_effective_weight)
      and (v_effective_volume is null or capacity_volume_cbm is null or capacity_volume_cbm >= v_effective_volume)
    order by capacity_weight_kg asc nulls last, vehicle_master_id asc
    limit 3
  loop
    v_rank := v_rank + 1;

    v_duration := case when v_total_distance_km is not null then round(v_total_distance_km / app.route_planning_default_speed_kmh() * 60, 1) else null end;
    v_utilization := case when v_effective_weight is not null and v_vehicle.capacity_weight_kg is not null and v_vehicle.capacity_weight_kg > 0
      then round(v_effective_weight / v_vehicle.capacity_weight_kg * 100, 1) else null end;

    insert into app.route_planning_candidate_plans (
      tenant_id, scenario_id, plan_rank, feasible, vehicle_master_id, driver_master_id,
      total_distance_km, estimated_duration_minutes, capacity_utilization_pct
    ) values (
      v_scenario.tenant_id, p_scenario_id, v_rank, true, v_vehicle.vehicle_master_id, v_drivers[1 + ((v_rank - 1) % v_driver_count)],
      v_total_distance_km, v_duration, v_utilization
    )
    returning * into v_candidate;

    insert into app.route_planning_score_components (tenant_id, candidate_plan_id, component_key, component_value) values
      (v_scenario.tenant_id, v_candidate.id, 'total_distance_km', v_total_distance_km),
      (v_scenario.tenant_id, v_candidate.id, 'estimated_duration_minutes', v_duration),
      (v_scenario.tenant_id, v_candidate.id, 'capacity_utilization_pct', v_utilization);
  end loop;

  update app.route_planning_scenarios set status = 'ready' where id = p_scenario_id;

  perform app.capture_audit_event(
    v_scenario.tenant_id, null, p_actor_label, 'generate_route_planning_candidates',
    'app.route_planning_scenarios', p_scenario_id, 'success', null, null,
    jsonb_build_object('feasible_count', v_rank)
  );

  return query select * from app.route_planning_candidate_plans where scenario_id = p_scenario_id order by plan_rank asc;
end;
$$;

comment on function app.generate_route_planning_candidates is
  'ATW-224: the deterministic baseline planner. Bounded to at most 3 feasible candidates (best-fit capacity match, tightest sufficient app.vehicle_operational_profiles.capacity_weight_kg first) or exactly one infeasible placeholder when no eligible vehicle/driver pair or a hard distance/time constraint is violated. Every candidate shares the identical stop sequence and app.route_planning_default_speed_kmh() -- resource capacity fit is the only real differentiator (this migration''s own header).';

-- app.run_next_route_planning_job -- the real, directly-invokable domain worker
-- entry point (Prompt 224 §20 "async jobs"). No live continuous poller exists yet
-- (NOT_RUN, this migration's own header) -- this function is what a future poller
-- would call in a loop; proven here by direct invocation.
create function app.run_next_route_planning_job(
  p_worker_id text
)
returns app.route_planning_scenarios
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_scenario_id uuid;
  v_scenario app.route_planning_scenarios;
begin
  v_job := app.claim_next_job(p_worker_id, array['route_load_planning'], 300);
  if v_job is null then
    return null;
  end if;

  v_scenario_id := (v_job.payload ->> 'scenario_id')::uuid;

  begin
    select * into v_scenario from app.route_planning_scenarios where id = v_scenario_id;
    if not found then
      raise exception 'scenario_not_found: %', v_scenario_id using errcode = 'no_data_found';
    end if;

    -- Cooperative cancellation: a scenario cancelled after being enqueued is left
    -- untouched by the planner (this migration's own header) -- the job still
    -- completes successfully, it simply has nothing left to do.
    if v_scenario.status = 'executing' then
      perform app.generate_route_planning_candidates(v_scenario_id, p_worker_id);
    end if;

    perform app.complete_job(v_job.job_id, p_worker_id, null, p_worker_id);
  exception
    when others then
      update app.route_planning_scenarios set status = 'failed' where id = v_scenario_id and status = 'executing';
      perform app.record_job_failure(v_job.job_id, SQLERRM, null, p_worker_id);
  end;

  select * into v_scenario from app.route_planning_scenarios where id = v_scenario_id;
  return v_scenario;
end;
$$;

comment on function app.run_next_route_planning_job is
  'ATW-224: claims the next pending route_load_planning app.jobs row (app.claim_next_job) and runs app.generate_route_planning_candidates on its scenario, completing or failing the job accordingly. Returns null when no job is due. The live continuous polling loop that would call this repeatedly is disclosed NOT_RUN (this migration''s own header, matching PLT-132''s own precedent).';

-- app.cancel_route_planning_scenario (Prompt 224 §32 "cancel incomplete planning
-- jobs, retain prior selected plan").
create function app.cancel_route_planning_scenario(
  p_scenario_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_scenarios
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a scenario' using errcode = 'check_violation';
  end if;

  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status in ('selected', 'cancelled') then
    raise exception 'scenario_not_mutable: scenario % is % and cannot be cancelled', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.route_planning_scenarios set status = 'cancelled' where id = p_scenario_id and record_version = p_expected_version
  returning * into v_scenario;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_scenario;
end;
$$;

comment on function app.cancel_route_planning_scenario is
  'ATW-224: allowed from any non-terminal, non-selected status. A cancelled scenario''s own already-enqueued job (if any) is cooperatively skipped by app.run_next_route_planning_job, never force-preempted (this migration''s own header). A prior selected plan on a different scenario is untouched -- selection lives on app.route_planning_selected_plans, not on this row.';

-- app.select_route_planning_plan -- the human decision-support selection (Prompt 224
-- §24 "human commitment is required"). Never mutates app.shipment_legs.
create function app.select_route_planning_plan(
  p_scenario_id uuid,
  p_candidate_plan_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_selected_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_candidate app.route_planning_candidate_plans;
  v_prior app.route_planning_selected_plans;
  v_selection app.route_planning_selected_plans;
begin
  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status not in ('ready', 'selected') then
    raise exception 'scenario_not_selectable: scenario % is % and has no candidates to select from', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  select * into v_candidate from app.route_planning_candidate_plans where id = p_candidate_plan_id and scenario_id = p_scenario_id;
  if not found then
    raise exception 'candidate_not_found: % is not a candidate of scenario %', p_candidate_plan_id, p_scenario_id using errcode = 'no_data_found';
  end if;

  if not v_candidate.feasible then
    raise exception 'candidate_infeasible: candidate % is infeasible and requires app.override_route_planning_selection', p_candidate_plan_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Update-before-insert ordering (app.reassign_resource's own precedent, OPS-172,
  -- also followed by app.assign_device_to_vehicle, ATW-223): inserting the new
  -- is_current row before marking the prior one false would transiently double-book
  -- the partial unique index route_planning_selected_plans_current_scenario_unique.
  select * into v_prior from app.route_planning_selected_plans where scenario_id = p_scenario_id and is_current;
  if v_prior.id is not null then
    update app.route_planning_selected_plans set is_current = false where id = v_prior.id;
  end if;

  insert into app.route_planning_selected_plans (tenant_id, scenario_id, candidate_plan_id, selected_by)
  values (v_scenario.tenant_id, p_scenario_id, p_candidate_plan_id, p_actor_label)
  returning * into v_selection;

  if v_prior.id is not null then
    update app.route_planning_selected_plans set superseded_by_id = v_selection.id where id = v_prior.id;
  end if;

  update app.route_planning_scenarios set status = 'selected' where id = p_scenario_id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'select_route_planning_plan',
    'app.route_planning_selected_plans', v_selection.id, 'success', null, null,
    jsonb_build_object('scenario_id', p_scenario_id, 'candidate_plan_id', p_candidate_plan_id)
  );

  return v_selection;
end;
$$;

comment on function app.select_route_planning_plan is
  'ATW-224: only a feasible candidate; an infeasible one requires app.override_route_planning_selection. History-preserving (is_current/superseded_by_id, ATW-223''s own precedent) -- re-selecting a different candidate supersedes, never overwrites, the prior selection.';

-- app.override_route_planning_selection -- manager-authority override (OPS:Override).
create function app.override_route_planning_selection(
  p_scenario_id uuid,
  p_candidate_plan_id uuid,
  p_override_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_selected_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_candidate app.route_planning_candidate_plans;
  v_prior app.route_planning_selected_plans;
  v_selection app.route_planning_selected_plans;
begin
  if p_override_reason is null or length(trim(p_override_reason)) = 0 then
    raise exception 'override_reason_required: a non-empty reason is required to override a selection' using errcode = 'check_violation';
  end if;

  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.record_version <> p_expected_version then
    raise exception 'stale_version: scenario % expected version % but found %', p_scenario_id, p_expected_version, v_scenario.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_scenario.status not in ('ready', 'selected') then
    raise exception 'scenario_not_selectable: scenario % is % and has no candidates to select from', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  select * into v_candidate from app.route_planning_candidate_plans where id = p_candidate_plan_id and scenario_id = p_scenario_id;
  if not found then
    raise exception 'candidate_not_found: % is not a candidate of scenario %', p_candidate_plan_id, p_scenario_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Update-before-insert ordering (see app.select_route_planning_plan's own
  -- identical comment above -- the same transient partial-unique-index violation
  -- applies here).
  select * into v_prior from app.route_planning_selected_plans where scenario_id = p_scenario_id and is_current;
  if v_prior.id is not null then
    update app.route_planning_selected_plans set is_current = false where id = v_prior.id;
  end if;

  insert into app.route_planning_selected_plans (tenant_id, scenario_id, candidate_plan_id, is_override, override_reason, selected_by)
  values (v_scenario.tenant_id, p_scenario_id, p_candidate_plan_id, true, p_override_reason, p_actor_label)
  returning * into v_selection;

  if v_prior.id is not null then
    update app.route_planning_selected_plans set superseded_by_id = v_selection.id where id = v_prior.id;
  end if;

  update app.route_planning_scenarios set status = 'selected' where id = p_scenario_id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_route_planning_selection',
    'app.route_planning_selected_plans', v_selection.id, 'success', null, null,
    jsonb_build_object('scenario_id', p_scenario_id, 'candidate_plan_id', p_candidate_plan_id, 'override_reason', p_override_reason, 'was_feasible', v_candidate.feasible)
  );

  return v_selection;
end;
$$;

comment on function app.override_route_planning_selection is
  'ATW-224: OPS:Override authority (Prompt 224 §26 "managers approve configured overrides"), non-empty override_reason always required. The one path that may select an infeasible candidate. History-preserving, identical to app.select_route_planning_plan.';

-- app.replan_route_planning_scenario (Prompt 224 §22 alternative flow). Copies the
-- prior scenario's own stops/constraints into a fresh draft scenario.
create function app.replan_route_planning_scenario(
  p_scenario_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.route_planning_scenarios
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_prior app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_new app.route_planning_scenarios;
  v_leg_count integer;
  v_replannable_leg_count integer;
  v_position record;
  v_snapshot jsonb;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'replan_reason_required: a non-empty reason is required to replan a scenario' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_prior from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_prior.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_prior.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_leg_count from app.shipment_legs where shipment_order_id = v_prior.shipment_order_id and leg_status <> 'cancelled';
  if v_leg_count > 0 then
    select count(*) into v_replannable_leg_count from app.shipment_legs
      where shipment_order_id = v_prior.shipment_order_id and leg_status = 'planned';
    if v_replannable_leg_count = 0 then
      raise exception 'nothing_to_replan: every leg of shipment order % has already left planned -- no unstarted leg remains to replan', v_prior.shipment_order_id
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.route_planning_scenarios (tenant_id, shipment_order_id, idempotency_key, requested_weight_kg, requested_volume_cbm, owner_user_id, created_by)
  values (v_prior.tenant_id, v_prior.shipment_order_id, p_idempotency_key, v_prior.requested_weight_kg, v_prior.requested_volume_cbm, v_prior.owner_user_id, p_actor_label)
  returning * into v_new;

  insert into app.route_planning_stops (tenant_id, scenario_id, stop_sequence, stop_type, location_name, address, location_geog, time_window_start, time_window_end, created_by)
  select v_new.tenant_id, v_new.id, stop_sequence, stop_type, location_name, address, location_geog, time_window_start, time_window_end, p_actor_label
  from app.route_planning_stops where scenario_id = p_scenario_id;

  insert into app.route_planning_constraints (tenant_id, scenario_id, constraint_type, constraint_key, constraint_value, created_by)
  select v_new.tenant_id, v_new.id, constraint_type, constraint_key, constraint_value, p_actor_label
  from app.route_planning_constraints where scenario_id = p_scenario_id;

  select * into v_position from app.get_canonical_position_for_planning(v_prior.shipment_order_id);
  v_snapshot := jsonb_build_object(
    'tracking_status', v_position.tracking_status,
    'freshness_status', v_position.freshness_status,
    'accuracy_meters', v_position.accuracy_meters,
    'last_position_at', v_position.last_position_at,
    'authoritative_source_type', v_position.authoritative_source_type,
    'tracking_entitled', v_position.tracking_entitled,
    'is_usable', v_position.is_usable
  );

  insert into app.route_planning_replan_events (tenant_id, scenario_id, previous_scenario_id, trigger_reason, canonical_position_snapshot, triggered_by)
  values (v_prior.tenant_id, v_new.id, p_scenario_id, p_reason, v_snapshot, p_actor_label);

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'replan_route_planning_scenario',
    'app.route_planning_scenarios', v_new.id, 'success', null, null,
    jsonb_build_object('previous_scenario_id', p_scenario_id, 'reason', p_reason)
  );

  return v_new;
end;
$$;

comment on function app.replan_route_planning_scenario is
  'ATW-224: creates a fresh draft scenario copying the prior scenario''s own stops/constraints, linked via app.route_planning_replan_events. Blocks only when every one of the shipment''s own legs has already left planned (nothing left to replan) -- p_reason is a disclosed, audited free-text justification, not yet a verified ATW-228 exception record (this migration''s own header).';

-- app.get_route_planning_stops -- GeoJSON projection, mirroring
-- app.get_shipment_leg_stops (ATW-221) exactly.
create function app.get_route_planning_stops(p_scenario_id uuid)
returns table (
  id uuid,
  tenant_id uuid,
  scenario_id uuid,
  stop_sequence integer,
  stop_type text,
  location_name text,
  address text,
  location_geojson jsonb,
  time_window_start timestamptz,
  time_window_end timestamptz,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public, pg_temp
as $$
  select
    s.id, s.tenant_id, s.scenario_id, s.stop_sequence, s.stop_type, s.location_name, s.address,
    app.geography_to_geojson_point(s.location_geog), s.time_window_start, s.time_window_end, s.created_at
  from app.route_planning_stops s
  where s.scenario_id = p_scenario_id
  order by s.stop_sequence asc;
$$;

comment on function app.get_route_planning_stops is
  'ATW-224: security invoker (relies on the caller''s own RLS on app.route_planning_stops) -- serializes location_geog to GeoJSON, never returning the raw geography wire format.';

-- === RLS ===

alter table app.route_planning_scenarios enable row level security;
alter table app.route_planning_stops enable row level security;
alter table app.route_planning_constraints enable row level security;
alter table app.route_planning_candidate_plans enable row level security;
alter table app.route_planning_score_components enable row level security;
alter table app.route_planning_selected_plans enable row level security;
alter table app.route_planning_replan_events enable row level security;

create policy route_planning_scenarios_select_scoped on app.route_planning_scenarios
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = route_planning_scenarios.shipment_order_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy route_planning_stops_select_scoped on app.route_planning_stops
  for select to authenticated
  using (
    exists (
      select 1 from app.route_planning_scenarios sc
      join app.shipment_orders so on so.id = sc.shipment_order_id
      where sc.id = route_planning_stops.scenario_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy route_planning_constraints_select_scoped on app.route_planning_constraints
  for select to authenticated
  using (
    exists (
      select 1 from app.route_planning_scenarios sc
      join app.shipment_orders so on so.id = sc.shipment_order_id
      where sc.id = route_planning_constraints.scenario_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy route_planning_candidate_plans_select_scoped on app.route_planning_candidate_plans
  for select to authenticated
  using (
    exists (
      select 1 from app.route_planning_scenarios sc
      join app.shipment_orders so on so.id = sc.shipment_order_id
      where sc.id = route_planning_candidate_plans.scenario_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy route_planning_score_components_select_scoped on app.route_planning_score_components
  for select to authenticated
  using (
    exists (
      select 1 from app.route_planning_candidate_plans cp
      join app.route_planning_scenarios sc on sc.id = cp.scenario_id
      join app.shipment_orders so on so.id = sc.shipment_order_id
      where cp.id = route_planning_score_components.candidate_plan_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy route_planning_selected_plans_select_scoped on app.route_planning_selected_plans
  for select to authenticated
  using (
    exists (
      select 1 from app.route_planning_scenarios sc
      join app.shipment_orders so on so.id = sc.shipment_order_id
      where sc.id = route_planning_selected_plans.scenario_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy route_planning_replan_events_select_scoped on app.route_planning_replan_events
  for select to authenticated
  using (
    exists (
      select 1 from app.route_planning_scenarios sc
      join app.shipment_orders so on so.id = sc.shipment_order_id
      where sc.id = route_planning_replan_events.scenario_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

-- === Grants ===

revoke execute on all functions in schema app from public;

grant select on app.route_planning_scenarios to authenticated, service_role;
grant insert, update, delete on app.route_planning_scenarios to service_role;
grant select on app.route_planning_stops to authenticated, service_role;
grant insert, update, delete on app.route_planning_stops to service_role;
grant select on app.route_planning_constraints to authenticated, service_role;
grant insert, update, delete on app.route_planning_constraints to service_role;
grant select on app.route_planning_candidate_plans to authenticated, service_role;
grant insert, update, delete on app.route_planning_candidate_plans to service_role;
grant select on app.route_planning_score_components to authenticated, service_role;
grant insert, update, delete on app.route_planning_score_components to service_role;
grant select on app.route_planning_selected_plans to authenticated, service_role;
grant insert, update, delete on app.route_planning_selected_plans to service_role;
grant select on app.route_planning_replan_events to authenticated, service_role;
grant insert, update, delete on app.route_planning_replan_events to service_role;

grant execute on function app.enqueue_job(uuid, text, jsonb, integer, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.route_planning_default_speed_kmh() to authenticated, service_role;
grant execute on function app.route_planning_position_staleness_tolerance_seconds() to authenticated, service_role;
grant execute on function app.get_canonical_position_for_planning(uuid) to authenticated, service_role;
grant execute on function app.prepare_route_planning_scenario(uuid, text, numeric, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.add_route_planning_stop(uuid, integer, text, text, text, numeric, numeric, timestamptz, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.add_route_planning_constraint(uuid, text, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.validate_route_planning_scenario(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.execute_route_planning_scenario(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.generate_route_planning_candidates(uuid, text) to authenticated, service_role;
grant execute on function app.run_next_route_planning_job(text) to authenticated, service_role;
grant execute on function app.cancel_route_planning_scenario(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.select_route_planning_plan(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.override_route_planning_selection(uuid, uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.replan_route_planning_scenario(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_route_planning_stops(uuid) to authenticated, service_role;
