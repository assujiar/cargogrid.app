-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 1 of 4 -- Operations: multi-leg shipments, route/load planning, fleet & GPS telematics, vehicle capacity reservations, and claim cases
--
-- Continues the already-established, already-precedented repository fix pass for this
-- defect class (ISS-2026-043 / ISS-2026-048 / ISS-2026-054, and the eight 20260902*
-- harden_tenant_id_disclosure_* migrations immediately preceding these four). Root cause
-- unchanged: a SECURITY DEFINER function looks a record up by its own bare id (the caller
-- does not yet know which tenant owns it), THEN evaluates the actor's authority against
-- the looked-up row's own real tenant_id, and on denial raises
-- 'insufficient_authority: ... for tenant %' interpolating that real tenant_id -- handing
-- it to a caller who has not yet been shown to have ANY relationship to that tenant.
--
-- The fix, identical in shape to 20260902100000_harden_tenant_id_disclosure_finance.sql:
-- fold app.has_active_tenant_membership(<row>.tenant_id, p_actor_auth_user_id) into the
-- SAME not-found branch the row-miss case already raises, reusing that branch's identical
-- generic message and errcode = 'no_data_found'. A caller with zero membership in the
-- row's real tenant now gets byte-for-byte the error a nonexistent id already produced.
--
-- What is deliberately NOT changed: the authority check itself (evaluate_permission /
-- check_*_authority / can_access_record) is untouched, and a genuine member of that same
-- tenant who merely lacks the specific ROLE authority still reaches the original
-- insufficient_authority raise, with the same insufficient_privilege errcode and the same
-- message text, exactly as before. Preserving that distinction is the point of the fix:
-- only the zero-relationship caller's error shape changes. app.has_active_tenant_membership
-- is itself supreme-admin- and support-grant-aware (20260716111315_create_support_access),
-- so platform administrators and live support grants are unaffected.
--
-- Why this cannot deny a caller who was previously allowed: since
-- 20260810300000_harden_rbac_evaluator_tenant_membership_check, app.evaluate_permission
-- ITSELF refuses to return allowed=true without app.has_active_tenant_membership on the
-- same tenant, and the check_*_authority helpers wrap it. The gate added below is
-- therefore strictly implied by every authority check that already had to pass -- it only
-- moves WHEN the refusal is decided, never WHETHER it is.
--
-- 30 functions in this part. Every definition below is CREATE OR REPLACE against the
-- function's CURRENT live body -- the last migration that defines it, verified per
-- function, not an earlier superseded text. Signatures, volatility, security attribute and
-- search_path are copied verbatim and unchanged, so grants are unaffected.


-- app.add_route_planning_stop
create or replace function app.add_route_planning_stop(p_scenario_id uuid, p_stop_sequence integer, p_stop_type text, p_location_name text, p_address text, p_longitude numeric, p_latitude numeric, p_time_window_start timestamp with time zone, p_time_window_end timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.route_planning_stops
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
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
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

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
$function$;


-- app.add_shipment_leg
create or replace function app.add_shipment_leg(p_shipment_order_id uuid, p_idempotency_key text, p_sequence_no integer, p_mode text, p_carrier_master_id uuid, p_planned_departure_at timestamp with time zone, p_planned_arrival_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_legs;
  v_leg app.shipment_legs;
  v_sequence_taken boolean;
begin
  if p_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode', p_mode using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  if p_sequence_no is null or p_sequence_no <= 0 then
    raise exception 'invalid_sequence: sequence_no must be a positive integer' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.shipment_legs
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.sequence_no is distinct from p_sequence_no or v_existing.mode is distinct from p_mode then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment leg (sequence %/mode %, not sequence %/mode %)', p_idempotency_key, v_existing.sequence_no, v_existing.mode, p_sequence_no, p_mode
        using errcode = 'unique_violation';
    end if;
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

  select exists (
    select 1 from app.shipment_legs where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and sequence_no = p_sequence_no and leg_status <> 'cancelled'
  ) into v_sequence_taken;
  if v_sequence_taken then
    raise exception 'leg_sequence_duplicate: sequence % is already used by an active leg of shipment order %', p_sequence_no, p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if p_carrier_master_id is not null then
    if not exists (
      select 1 from app.master_records
      where id = p_carrier_master_id and master_type_code in ('vendor', 'fleet') and canonical_status = 'active'
        and (tenant_id = v_shipment.tenant_id or tenant_id is null)
    ) then
      raise exception 'carrier_not_found: % is not a known active vendor/fleet reference for tenant %', p_carrier_master_id, v_shipment.tenant_id
        using errcode = 'no_data_found';
    end if;
  end if;

  begin
    insert into app.shipment_legs (
      tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, carrier_master_id,
      planned_departure_at, planned_arrival_at, owner_user_id, created_by
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, p_sequence_no, p_idempotency_key, p_mode, p_carrier_master_id,
      p_planned_departure_at, p_planned_arrival_at, v_shipment.owner_user_id, p_actor_label
    )
    returning * into v_leg;
  exception
    when unique_violation then
      select * into v_leg from app.shipment_legs
        where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
      return v_leg;
  end;

  if v_shipment.leg_network_status = 'confirmed' then
    update app.shipment_orders set leg_network_status = 'draft' where id = p_shipment_order_id;
  elsif v_shipment.leg_network_status is null then
    update app.shipment_orders set leg_network_status = 'draft' where id = p_shipment_order_id;
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'sequence_no', p_sequence_no, 'mode', p_mode)
  );

  return v_leg;
end;
$function$;


-- app.add_shipment_leg_stop
create or replace function app.add_shipment_leg_stop(p_shipment_leg_id uuid, p_stop_sequence integer, p_stop_type text, p_location_name text, p_address text, p_longitude numeric, p_latitude numeric, p_planned_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.shipment_leg_stops
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_stop app.shipment_leg_stops;
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

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and its stops can only be edited while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_longitude is not null and p_latitude is not null then
    v_geog := app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(p_longitude, p_latitude)));
  end if;

  insert into app.shipment_leg_stops (
    tenant_id, shipment_leg_id, stop_sequence, stop_type, location_name, address, location_geog, planned_at, created_by
  ) values (
    v_leg.tenant_id, p_shipment_leg_id, p_stop_sequence, p_stop_type, p_location_name, p_address, v_geog, p_planned_at, p_actor_label
  )
  returning * into v_stop;

  perform app.capture_audit_event(
    v_leg.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_shipment_leg_stop',
    'app.shipment_leg_stops', v_stop.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'stop_sequence', p_stop_sequence, 'stop_type', p_stop_type)
  );

  return v_stop;
end;
$function$;


-- app.allocate_shipment_leg_cargo
create or replace function app.allocate_shipment_leg_cargo(p_shipment_leg_id uuid, p_allocated_quantity numeric, p_allocated_weight_kg numeric, p_allocated_volume_cbm numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_leg_cargo_allocations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_other_qty numeric;
  v_other_weight numeric;
  v_other_volume numeric;
  v_allocation app.shipment_leg_cargo_allocations;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id for update;
  -- ATW-032: the per-leg allocation aggregate is checked against the parent shipment's
  -- own allocated_* basis, but nothing held the parent while that check ran. Two legs of
  -- the SAME shipment allocating concurrently could each pass and together exceed it --
  -- the leg-level UNIQUE(shipment_leg_id) does not help, since they are different legs.
  -- Locking the parent serialises them, the same remedy ATW-017 used for the pick-task
  -- double-allocation guard.
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and its cargo allocation can only be edited while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(sum(a.allocated_quantity), 0), coalesce(sum(a.allocated_weight_kg), 0), coalesce(sum(a.allocated_volume_cbm), 0)
    into v_other_qty, v_other_weight, v_other_volume
  from app.shipment_leg_cargo_allocations a
  join app.shipment_legs sl on sl.id = a.shipment_leg_id
  where sl.shipment_order_id = v_leg.shipment_order_id and sl.leg_status <> 'cancelled' and a.shipment_leg_id <> p_shipment_leg_id;

  if v_shipment.allocated_quantity is not null and (v_other_qty + coalesce(p_allocated_quantity, 0)) > v_shipment.allocated_quantity then
    raise exception 'cargo_over_allocated: allocated_quantity % across legs exceeds shipment allocation %', (v_other_qty + coalesce(p_allocated_quantity, 0)), v_shipment.allocated_quantity
      using errcode = 'check_violation';
  end if;
  if v_shipment.allocated_weight_kg is not null and (v_other_weight + coalesce(p_allocated_weight_kg, 0)) > v_shipment.allocated_weight_kg then
    raise exception 'cargo_over_allocated: allocated_weight_kg % across legs exceeds shipment allocation %', (v_other_weight + coalesce(p_allocated_weight_kg, 0)), v_shipment.allocated_weight_kg
      using errcode = 'check_violation';
  end if;
  if v_shipment.allocated_volume_cbm is not null and (v_other_volume + coalesce(p_allocated_volume_cbm, 0)) > v_shipment.allocated_volume_cbm then
    raise exception 'cargo_over_allocated: allocated_volume_cbm % across legs exceeds shipment allocation %', (v_other_volume + coalesce(p_allocated_volume_cbm, 0)), v_shipment.allocated_volume_cbm
      using errcode = 'check_violation';
  end if;

  insert into app.shipment_leg_cargo_allocations (tenant_id, shipment_leg_id, allocated_quantity, allocated_weight_kg, allocated_volume_cbm, created_by)
  values (v_leg.tenant_id, p_shipment_leg_id, p_allocated_quantity, p_allocated_weight_kg, p_allocated_volume_cbm, p_actor_label)
  on conflict (shipment_leg_id) do update set
    allocated_quantity = excluded.allocated_quantity,
    allocated_weight_kg = excluded.allocated_weight_kg,
    allocated_volume_cbm = excluded.allocated_volume_cbm
  returning * into v_allocation;

  perform app.capture_audit_event(
    v_leg.tenant_id, p_actor_auth_user_id, p_actor_label, 'allocate_shipment_leg_cargo',
    'app.shipment_leg_cargo_allocations', v_allocation.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'allocated_quantity', p_allocated_quantity, 'allocated_weight_kg', p_allocated_weight_kg, 'allocated_volume_cbm', p_allocated_volume_cbm)
  );

  return v_allocation;
end;
$function$;


-- app.cancel_route_planning_scenario
create or replace function app.cancel_route_planning_scenario(p_scenario_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_route_planning_scenario target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_scenario;
end;
$function$
;


-- app.cancel_shipment_leg
create or replace function app.cancel_shipment_leg(p_shipment_leg_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a leg' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  if v_leg.record_version <> p_expected_version then
    raise exception 'stale_version: leg % expected version % but found %', p_shipment_leg_id, p_expected_version, v_leg.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and can only be cancelled while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_legs set leg_status = 'cancelled' where id = p_shipment_leg_id and record_version = p_expected_version
  returning * into v_leg;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_shipment_leg target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.leg_network_status = 'confirmed' then
    update app.shipment_orders set leg_network_status = 'draft' where id = v_leg.shipment_order_id;
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_leg;
end;
$function$
;


-- app.close_claim_case
create or replace function app.close_claim_case(p_case_id uuid, p_expected_version integer, p_exception_expected_version integer, p_closure_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_case_extensions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_latest_handoff app.claim_settlement_readiness_handoffs;
  v_review app.claim_responsibility_reviews;
  v_closure_basis text;
  v_exception app.operational_exceptions;
  v_resolved app.operational_exceptions;
  v_updated app.claim_case_extensions;
begin
  if p_closure_note is null or length(trim(p_closure_note)) = 0 then
    raise exception 'claim_closure_note_required: a non-empty closure_note is required to close a claim case' using errcode = 'check_violation';
  end if;

  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_already_closed: claim case % is already closed', p_case_id using errcode = 'check_violation';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: claim case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Close');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Close (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  -- Exact closure gate (disclosed precisely in the migration header, design point 8).
  -- Ordered by handoff_seq (a real identity column), never handed_off_at -- see
  -- app.claim_settlement_readiness_handoffs' own comment for why.
  select * into v_latest_handoff from app.claim_settlement_readiness_handoffs where claim_case_id = p_case_id order by handoff_seq desc limit 1;
  if found and v_latest_handoff.reconciliation_status = 'reconciled' then
    v_closure_basis := 'finance_reconciled';
  else
    select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
    if found and (v_review.status = 'denied' or (v_review.status in ('approved', 'amended') and coalesce(v_review.final_reserve_amount, 0) = 0)) then
      v_closure_basis := 'no_handoff_required';
    else
      raise exception 'claim_case_not_reconciled: claim case % is not yet finance-reconciled and does not qualify for the no-handoff-required closure path (a decided denial or a zero-reserve decision) -- hand off to Finance and obtain a reconciled outcome, or decide/deny the claim, before closing', p_case_id
        using errcode = 'check_violation';
    end if;
  end if;

  -- Drive the underlying app.operational_exceptions row through ITS OWN real
  -- resolve/close RPCs -- never a direct table write (see migration header).
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;
  if v_exception.status in ('open', 'acknowledged', 'reopened') then
    v_resolved := app.resolve_exception(v_exception.id, p_exception_expected_version, p_closure_note, p_actor_auth_user_id, p_actor_label);
    perform app.close_exception(v_resolved.id, v_resolved.record_version, p_actor_auth_user_id, p_actor_label);
  elsif v_exception.status = 'resolved' then
    perform app.close_exception(v_exception.id, p_exception_expected_version, p_actor_auth_user_id, p_actor_label);
  end if;
  -- status = 'closed' already -- no-op, its own closure precondition already holds.

  update app.claim_case_extensions
  set claim_stage = 'closed', closure_basis = v_closure_basis, closure_note = p_closure_note, closed_at = now(), closed_by = p_actor_label
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: close_claim_case target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_claim_case',
    'app.claim_case_extensions', v_updated.id, 'success', p_closure_note, null,
    jsonb_build_object('closure_basis', v_closure_basis)
  );

  return v_updated;
end;
$function$
;


-- app.confirm_shipment_leg_network
create or replace function app.confirm_shipment_leg_network(p_shipment_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_leg_count integer;
  v_max_sequence integer;
  v_distinct_sequence_count integer;
  v_unallocated_count integer;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*), max(sequence_no), count(distinct sequence_no)
    into v_leg_count, v_max_sequence, v_distinct_sequence_count
  from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status <> 'cancelled';

  if v_leg_count = 0 then
    raise exception 'network_empty: shipment order % has no active leg to confirm', p_shipment_order_id using errcode = 'check_violation';
  end if;

  if v_distinct_sequence_count <> v_leg_count or v_max_sequence <> v_leg_count then
    raise exception 'network_sequence_gap: shipment order % legs must form a contiguous 1..% sequence with no gap or duplicate', p_shipment_order_id, v_leg_count
      using errcode = 'check_violation';
  end if;

  select count(*) into v_unallocated_count
  from app.shipment_legs sl
  where sl.shipment_order_id = p_shipment_order_id and sl.leg_status <> 'cancelled'
    and not exists (select 1 from app.shipment_leg_cargo_allocations a where a.shipment_leg_id = sl.id);
  if v_unallocated_count > 0 then
    raise exception 'network_cargo_incomplete: % leg(s) of shipment order % have no cargo allocation', v_unallocated_count, p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  update app.shipment_orders set leg_network_status = 'confirmed' where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: confirm_shipment_leg_network target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_shipment_leg_network',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('leg_count', v_leg_count)
  );

  return v_shipment;
end;
$function$
;


-- app.consume_vehicle_capacity_reservation
create or replace function app.consume_vehicle_capacity_reservation(p_reservation_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vehicle_capacity_reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_reservation app.vehicle_capacity_reservations;
begin
  select * into v_reservation from app.vehicle_capacity_reservations where id = p_reservation_id for update;
  if not found or not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
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
$function$;


-- app.decide_claim_responsibility
create or replace function app.decide_claim_responsibility(p_review_id uuid, p_expected_version integer, p_decision text, p_final_responsibility_party text, p_final_reserve_amount numeric, p_final_currency text, p_decision_notes text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_responsibility_reviews
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_review app.claim_responsibility_reviews;
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_currency text;
  v_updated app.claim_responsibility_reviews;
begin
  select * into v_review from app.claim_responsibility_reviews where id = p_review_id;
  if not found then
    raise exception 'claim_responsibility_review_not_found: %', p_review_id using errcode = 'no_data_found';
  end if;
  select * into v_case from app.claim_case_extensions where id = v_review.claim_case_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_responsibility_review_not_found: %', p_review_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', v_case.id using errcode = 'check_violation';
  end if;

  -- A governed liability/reserve decision -- OPS:Override (OPS has no dedicated
  -- 'Approve' action; mirrors app.approve_warehouse_billing_event's own identical
  -- choice, ATW-022, see migration header).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, v_case.id using errcode = 'insufficient_privilege';
  end if;

  if v_review.status <> 'proposed' then
    raise exception 'invalid_transition: claim responsibility review % is % and cannot be decided', p_review_id, v_review.status using errcode = 'check_violation';
  end if;
  if v_review.record_version <> p_expected_version then
    raise exception 'stale_version: claim responsibility review % expected version % but found %', p_review_id, p_expected_version, v_review.record_version
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'denied', 'amended') then
    raise exception 'claim_invalid_decision: % is not one of approved/denied/amended', p_decision using errcode = 'check_violation';
  end if;

  -- Separation of duties -- the EXACT existing self_approval_not_allowed
  -- convention app.approve_warehouse_billing_event already established (ATW-022).
  if v_review.proposed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % proposed claim responsibility review % and may not also decide it', p_actor_auth_user_id, p_review_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision in ('approved', 'amended') then
    if p_final_responsibility_party is null or p_final_responsibility_party not in ('carrier', 'vendor', 'customer', 'internal', 'unknown') then
      raise exception 'claim_invalid_responsibility_party: % is not a supported responsibility party', p_final_responsibility_party using errcode = 'check_violation';
    end if;
    if p_final_reserve_amount is null or p_final_reserve_amount < 0 then
      raise exception 'claim_invalid_reserve_amount: final_reserve_amount is required and must not be negative for an approved/amended decision' using errcode = 'check_violation';
    end if;
    v_currency := coalesce(p_final_currency, v_review.proposed_currency);
    if v_currency is null or not app.validate_currency_code(v_currency) then
      raise exception 'invalid_currency: a valid final currency is required for an approved/amended decision' using errcode = 'check_violation';
    end if;
    -- Prompt 244 §23 "block ... missing custody/quantity evidence" (see migration
    -- header design note 5) -- closes the "propose zero, amend to a real positive
    -- number" bypass a propose-time-only gate would leave open.
    if p_final_reserve_amount > 0 and not exists (select 1 from app.claim_items where claim_case_id = v_case.id and status = 'active')
      and not exists (select 1 from app.claim_evidence_links where claim_case_id = v_case.id)
    then
      raise exception 'claim_evidence_required: claim case % is being decided with a positive final reserve amount but has no itemized claim_items or linked evidence yet', v_case.id
        using errcode = 'check_violation';
    end if;
  else
    if p_final_responsibility_party is not null or p_final_reserve_amount is not null then
      raise exception 'claim_denied_decision_shape_invalid: a denied decision must not carry a final_responsibility_party/final_reserve_amount' using errcode = 'check_violation';
    end if;
    v_currency := null;
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'claim_decision_notes_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  update app.claim_responsibility_reviews
  set status = p_decision,
      decided_by_auth_user_id = p_actor_auth_user_id,
      decided_by = p_actor_label,
      decided_at = now(),
      final_responsibility_party = case when p_decision in ('approved', 'amended') then p_final_responsibility_party else null end,
      final_reserve_amount = case when p_decision in ('approved', 'amended') then p_final_reserve_amount else null end,
      final_currency = case when p_decision in ('approved', 'amended') then v_currency else null end,
      decision_notes = p_decision_notes
  where id = p_review_id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: decide_claim_responsibility target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.advance_claim_case_stage(v_case.id, 'decided');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_claim_responsibility',
    'app.claim_responsibility_reviews', v_updated.id, 'success', p_decision_notes,
    jsonb_build_object('status', v_review.status),
    jsonb_build_object('status', v_updated.status, 'final_responsibility_party', v_updated.final_responsibility_party, 'final_reserve_amount', v_updated.final_reserve_amount)
  );

  return v_updated;
end;
$function$
;


-- app.deregister_gps_device
create or replace function app.deregister_gps_device(p_device_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.gps_devices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_device app.gps_devices;
  v_decision app.rbac_decision;
  v_previous_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'deregister_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found or not app.has_active_tenant_membership(v_device.tenant_id, p_actor_auth_user_id) then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;

  if v_device.record_version <> p_expected_version then
    raise exception 'stale_version: device % expected version % but found %', p_device_id, p_expected_version, v_device.record_version
      using errcode = 'serialization_failure';
  end if;

  -- OPS:Override, evaluated against the DEVICE'S OWN tenant (mirrors app.evaluate_
  -- permission's already-established supreme_admin exception, RPD-022 -- see this
  -- migration's own header design note 1(b)). A tenant's own OPS:Override holder may
  -- self-service-deregister their OWN device (the "legitimately-retired" case), but
  -- clearing a DIFFERENT tenant's spurious/malicious row (this finding's actual
  -- cross-tenant remediation target) always requires a real supreme_admin, since ordinary
  -- tenant-scoped role assignment structurally cannot span a tenant boundary.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_device.status = 'retired' then
    return v_device;
  end if;

  v_previous_status := v_device.status;

  update app.gps_devices
  set status = 'retired'
  where id = p_device_id and record_version = p_expected_version
  returning * into v_device;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: deregister_gps_device target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'deregister_gps_device',
    'app.gps_devices', v_device.id, 'success', p_reason, jsonb_build_object('status', v_previous_status), jsonb_build_object('status', 'retired')
  );

  return v_device;
end;
$function$
;


-- app.execute_route_planning_scenario
create or replace function app.execute_route_planning_scenario(p_scenario_id uuid, p_expected_version integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: execute_route_planning_scenario target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id)
  );

  return v_scenario;
end;
$function$
;


-- app.get_shipment_exception_signals
create or replace function app.get_shipment_exception_signals(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_status text DEFAULT 'pending'::text)
 returns TABLE(id uuid, tenant_id uuid, shipment_order_id uuid, shipment_leg_id uuid, signal_type text, exception_type text, severity text, detected_at timestamp with time zone, source_canonical_event_id uuid, location_geojson jsonb, description text, correlation_key text, status text, resulting_exception_id uuid, reviewed_by_user_id uuid, reviewed_at timestamp with time zone, review_note text, created_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
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
$function$;


-- app.get_shipment_leg_geofence_state
create or replace function app.get_shipment_leg_geofence_state(p_shipment_leg_id uuid, p_actor_auth_user_id uuid)
 returns TABLE(id uuid, tenant_id uuid, shipment_leg_stop_id uuid, shipment_leg_id uuid, radius_meters numeric, dwell_seconds_before_confirm numeric, state text, first_entered_at timestamp with time zone, confirmed_at timestamp with time zone, last_evaluated_at timestamp with time zone, last_evaluated_location_geojson jsonb, created_at timestamp with time zone, updated_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
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
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

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
$function$;


-- app.get_shipment_milestone_candidates
create or replace function app.get_shipment_milestone_candidates(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_status text DEFAULT 'pending'::text)
 returns TABLE(id uuid, tenant_id uuid, shipment_order_id uuid, shipment_leg_id uuid, shipment_leg_stop_id uuid, milestone_code text, candidate_event_time timestamp with time zone, detected_at timestamp with time zone, source_canonical_event_id uuid, location_geojson jsonb, status text, dedup_key text, resulting_milestone_event_id uuid, reviewed_by_user_id uuid, reviewed_at timestamp with time zone, review_note text, created_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
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
$function$;


-- app.override_route_planning_selection
create or replace function app.override_route_planning_selection(p_scenario_id uuid, p_candidate_plan_id uuid, p_override_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_selected_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id for update;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

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
$function$;


-- app.prepare_route_planning_scenario
create or replace function app.prepare_route_planning_scenario(p_shipment_order_id uuid, p_idempotency_key text, p_requested_weight_kg numeric, p_requested_volume_cbm numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.route_planning_scenarios
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.requested_weight_kg is distinct from p_requested_weight_kg or v_existing.requested_volume_cbm is distinct from p_requested_volume_cbm then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different route planning scenario (weight %/volume %, not weight %/volume %)', p_idempotency_key, v_existing.requested_weight_kg, v_existing.requested_volume_cbm, p_requested_weight_kg, p_requested_volume_cbm
        using errcode = 'unique_violation';
    end if;
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
$function$;


-- app.propose_claim_responsibility
create or replace function app.propose_claim_responsibility(p_case_id uuid, p_proposed_responsibility_party text, p_proposed_reserve_amount numeric, p_proposed_currency text, p_proposed_rationale text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_responsibility_reviews
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_current app.claim_responsibility_reviews;
  v_review app.claim_responsibility_reviews;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  if p_proposed_responsibility_party not in ('carrier', 'vendor', 'customer', 'internal', 'unknown') then
    raise exception 'claim_invalid_responsibility_party: % is not a supported responsibility party', p_proposed_responsibility_party using errcode = 'check_violation';
  end if;
  if p_proposed_rationale is null or length(trim(p_proposed_rationale)) = 0 then
    raise exception 'claim_rationale_required: a non-empty proposed_rationale is required' using errcode = 'check_violation';
  end if;
  if (p_proposed_reserve_amount is null) <> (p_proposed_currency is null) then
    raise exception 'claim_reserve_currency_shape_invalid: proposed_reserve_amount and proposed_currency must both be set or both be null' using errcode = 'check_violation';
  end if;
  if p_proposed_reserve_amount is not null then
    if p_proposed_reserve_amount < 0 then
      raise exception 'claim_invalid_reserve_amount: proposed_reserve_amount must not be negative' using errcode = 'check_violation';
    end if;
    if not app.validate_currency_code(p_proposed_currency) then
      raise exception 'invalid_currency: % is not a registered, active currency', p_proposed_currency using errcode = 'check_violation';
    end if;
  end if;

  select * into v_current from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;

  -- Optimistic concurrency (Prompt 244 §25 "reject ... stale mutation"; see
  -- migration header design note 5) -- a live-reproduced lost update on an earlier
  -- draft with no version check at all is fixed here. Covers BOTH the in-place
  -- update branch below (the exact bug that was reproduced) and the start-a-new-
  -- version branch (the caller must prove it read the case's current state, decided
  -- or not, before proposing again).
  if found then
    if p_expected_version is null or v_current.record_version <> p_expected_version then
      raise exception 'stale_version: claim responsibility review % expected version % but found %', v_current.id, p_expected_version, v_current.record_version
        using errcode = 'check_violation';
    end if;
  elsif p_expected_version is not null then
    raise exception 'stale_version: claim case % has no current responsibility review yet but expected_version % was supplied', p_case_id, p_expected_version
      using errcode = 'check_violation';
  end if;

  -- Prompt 244 §23 "block ... missing custody/quantity evidence" (see migration
  -- header design note 5) -- a positive proposed reserve requires at least one
  -- itemized claim_items row or linked evidence record on file; a genuinely
  -- zero/null reserve (no compensable loss) is exempt.
  if p_proposed_reserve_amount is not null and p_proposed_reserve_amount > 0 then
    if not exists (select 1 from app.claim_items where claim_case_id = p_case_id and status = 'active')
      and not exists (select 1 from app.claim_evidence_links where claim_case_id = p_case_id)
    then
      raise exception 'claim_evidence_required: claim case % proposes a positive reserve amount but has no itemized claim_items or linked evidence yet', p_case_id
        using errcode = 'check_violation';
    end if;
  end if;

  if found and v_current.status = 'proposed' then
    update app.claim_responsibility_reviews
    set proposed_responsibility_party = p_proposed_responsibility_party,
        proposed_reserve_amount = p_proposed_reserve_amount,
        proposed_currency = p_proposed_currency,
        proposed_rationale = p_proposed_rationale,
        proposed_by_auth_user_id = p_actor_auth_user_id,
        proposed_by = p_actor_label,
        proposed_at = now()
    where id = v_current.id and record_version = p_expected_version
    returning * into v_review;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: propose_claim_responsibility target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  else
    if found then
      update app.claim_responsibility_reviews set is_current = false where id = v_current.id and record_version = p_expected_version;
    end if;
    insert into app.claim_responsibility_reviews (
      tenant_id, claim_case_id, version_number, proposed_responsibility_party, proposed_reserve_amount, proposed_currency,
      proposed_rationale, proposed_by_auth_user_id, proposed_by, supersedes_review_id, created_by
    ) values (
      v_case.tenant_id, p_case_id, coalesce(v_current.version_number, 0) + 1, p_proposed_responsibility_party, p_proposed_reserve_amount, p_proposed_currency,
      p_proposed_rationale, p_actor_auth_user_id, p_actor_label, v_current.id, p_actor_label
    )
    returning * into v_review;
  end if;

  perform app.advance_claim_case_stage(p_case_id, 'pending_decision');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_claim_responsibility',
    'app.claim_responsibility_reviews', v_review.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'proposed_responsibility_party', p_proposed_responsibility_party, 'proposed_reserve_amount', p_proposed_reserve_amount)
  );

  return v_review;
end;
$function$
;


-- app.rebaseline_shipment_leg_schedule
create or replace function app.rebaseline_shipment_leg_schedule(p_shipment_leg_id uuid, p_new_planned_departure_at timestamp with time zone, p_new_planned_arrival_at timestamp with time zone, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: rebaseline_shipment_leg_schedule target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'rebaseline_shipment_leg_schedule',
    'app.shipment_legs', v_leg.id, 'success', null, v_before,
    jsonb_build_object('planned_departure_at', v_leg.planned_departure_at, 'planned_arrival_at', v_leg.planned_arrival_at, 'shipment_leg_id', p_shipment_leg_id, 'reason', p_reason)
  );

  return v_leg;
end;
$function$
;


-- app.release_vehicle_capacity_reservation
create or replace function app.release_vehicle_capacity_reservation(p_reservation_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vehicle_capacity_reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_reservation app.vehicle_capacity_reservations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to release a capacity reservation' using errcode = 'check_violation';
  end if;

  select * into v_reservation from app.vehicle_capacity_reservations where id = p_reservation_id for update;
  if not found or not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
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
$function$;


-- app.reopen_claim_case
create or replace function app.reopen_claim_case(p_case_id uuid, p_expected_version integer, p_exception_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_case_extensions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_updated app.claim_case_extensions;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reopening a claim case requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage <> 'closed' then
    raise exception 'invalid_transition: claim case % is % and cannot be reopened', p_case_id, v_case.claim_stage using errcode = 'check_violation';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: claim case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version using errcode = 'check_violation';
  end if;

  -- Mirrors app.reopen_exception''s own actual OPS:Edit precedent exactly (not the
  -- registered-but-unused OPS:Reopen action -- see migration header) so the claim
  -- extension and the base exception it wraps share the same authorization tier.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  perform app.reopen_exception(v_case.operational_exception_id, p_exception_expected_version, p_reason, p_actor_auth_user_id, p_actor_label);

  update app.claim_case_extensions
  set claim_stage = 'investigating', reopened_at = now(), reopened_by = p_actor_label, reopen_reason = p_reason
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reopen_claim_case target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_claim_case',
    'app.claim_case_extensions', v_updated.id, 'success', p_reason, null, null
  );

  return v_updated;
end;
$function$
;


-- app.reserve_vehicle_capacity
create or replace function app.reserve_vehicle_capacity(p_shipment_leg_id uuid, p_requested_weight_kg numeric, p_requested_volume_cbm numeric, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vehicle_capacity_reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_leg.tenant_id, p_actor_auth_user_id) then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.vehicle_capacity_reservations
    where tenant_id = v_leg.tenant_id and shipment_leg_id = p_shipment_leg_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.requested_weight_kg is distinct from p_requested_weight_kg or v_existing.requested_volume_cbm is distinct from p_requested_volume_cbm then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different capacity reservation (weight %/volume %, not weight %/volume %)', p_idempotency_key, v_existing.requested_weight_kg, v_existing.requested_volume_cbm, p_requested_weight_kg, p_requested_volume_cbm
        using errcode = 'unique_violation';
    end if;
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
        -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
        -- conflict, never a replay. Returning the earlier target's row here silently
        -- misattributed this request to it (or silently discarded it entirely).
        if v_existing.requested_weight_kg is distinct from p_requested_weight_kg or v_existing.requested_volume_cbm is distinct from p_requested_volume_cbm then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different capacity reservation (weight %/volume %, not weight %/volume %)', p_idempotency_key, v_existing.requested_weight_kg, v_existing.requested_volume_cbm, p_requested_weight_kg, p_requested_volume_cbm
            using errcode = 'unique_violation';
        end if;
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
$function$;


-- app.revoke_driver_mobile_session
create or replace function app.revoke_driver_mobile_session(
  p_shipment_leg_tracking_session_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.driver_mobile_tracking_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.driver_mobile_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_row from app.driver_mobile_tracking_sessions where shipment_leg_tracking_session_id = p_shipment_leg_tracking_session_id and status = 'active';
  if not found then
    raise exception 'driver_mobile_session_not_found: no active mobile session token for tracking session %', p_shipment_leg_tracking_session_id using errcode = 'no_data_found';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'revoke_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_session from app.shipment_leg_tracking_sessions where id = v_row.shipment_leg_tracking_session_id;
  select * into v_leg from app.shipment_legs where id = v_session.shipment_leg_id;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'driver_mobile_session_not_found: no active mobile session token for tracking session %', p_shipment_leg_tracking_session_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.driver_mobile_tracking_sessions
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = v_row.id
  returning * into v_row;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_driver_mobile_session',
    'app.driver_mobile_tracking_sessions', v_row.id, 'success', p_reason, null, null
  );

  -- ISS-2026-232 Tier C fix: mask token_hash on the returned composite.
  v_row.token_hash := null;
  return v_row;
end;
$$;


-- app.select_route_planning_plan
create or replace function app.select_route_planning_plan(p_scenario_id uuid, p_candidate_plan_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_selected_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id for update;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

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
$function$;


-- app.set_driver_mobile_tracking_consent
create or replace function app.set_driver_mobile_tracking_consent(p_driver_profile_id uuid, p_consent boolean, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.driver_operational_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_profile app.driver_operational_profiles;
  v_decision app.rbac_decision;
begin
  select * into v_profile from app.driver_operational_profiles where id = p_driver_profile_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'driver_profile_not_found: %', p_driver_profile_id using errcode = 'no_data_found';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: driver profile % expected version % but found %', p_driver_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.driver_operational_profiles
  set mobile_tracking_consent = p_consent, mobile_tracking_consent_at = case when p_consent then now() else null end
  where id = p_driver_profile_id and record_version = p_expected_version
  returning * into v_profile;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: set_driver_mobile_tracking_consent target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_driver_mobile_tracking_consent',
    'app.driver_operational_profiles', v_profile.id, 'success', null, null, jsonb_build_object('consent', p_consent)
  );

  return v_profile;
end;
$function$
;


-- app.set_vehicle_tracking_eligibility
create or replace function app.set_vehicle_tracking_eligibility(p_vehicle_profile_id uuid, p_mobile_eligible boolean, p_direct_device_eligible boolean, p_third_party_eligible boolean, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vehicle_operational_profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_profile app.vehicle_operational_profiles;
  v_decision app.rbac_decision;
begin
  select * into v_profile from app.vehicle_operational_profiles where id = p_vehicle_profile_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vehicle_profile_not_found: %', p_vehicle_profile_id using errcode = 'no_data_found';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vehicle profile % expected version % but found %', p_vehicle_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.vehicle_operational_profiles
  set mobile_tracking_eligible = p_mobile_eligible, direct_device_tracking_eligible = p_direct_device_eligible, third_party_tracking_eligible = p_third_party_eligible
  where id = p_vehicle_profile_id and record_version = p_expected_version
  returning * into v_profile;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: set_vehicle_tracking_eligibility target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_vehicle_tracking_eligibility',
    'app.vehicle_operational_profiles', v_profile.id, 'success', null, null,
    jsonb_build_object('mobile_tracking_eligible', p_mobile_eligible, 'direct_device_tracking_eligible', p_direct_device_eligible, 'third_party_tracking_eligible', p_third_party_eligible)
  );

  return v_profile;
end;
$function$
;


-- app.transition_gps_device_status
create or replace function app.transition_gps_device_status(p_device_id uuid, p_to_status text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.gps_devices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_device app.gps_devices;
  v_decision app.rbac_decision;
  v_allowed boolean := false;
begin
  select * into v_device from app.gps_devices where id = p_device_id;
  if not found or not app.has_active_tenant_membership(v_device.tenant_id, p_actor_auth_user_id) then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;

  if v_device.record_version <> p_expected_version then
    raise exception 'stale_version: device % expected version % but found %', p_device_id, p_expected_version, v_device.record_version
      using errcode = 'serialization_failure';
  end if;

  v_allowed := (v_device.status = 'stock' and p_to_status = 'assigned')
    or (v_device.status = 'assigned' and p_to_status = 'installed')
    or (v_device.status = 'installed' and p_to_status = 'active')
    or (v_device.status in ('active', 'offline') and p_to_status in ('active', 'offline', 'suspended', 'maintenance'))
    or (v_device.status in ('suspended', 'maintenance') and p_to_status = 'active')
    or (v_device.status <> 'retired' and p_to_status = 'retired');

  if not v_allowed then
    raise exception 'invalid_device_status_transition: device % cannot move from % to %', p_device_id, v_device.status, p_to_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.gps_devices set status = p_to_status where id = p_device_id and record_version = p_expected_version
  returning * into v_device;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_gps_device_status target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_gps_device_status',
    'app.gps_devices', v_device.id, 'success', null, jsonb_build_object('status', v_device.status), jsonb_build_object('status', p_to_status)
  );

  return v_device;
end;
$function$
;


-- app.transition_shipment_leg
create or replace function app.transition_shipment_leg(p_shipment_leg_id uuid, p_to_status text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_allowed boolean := false;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  if v_leg.record_version <> p_expected_version then
    raise exception 'stale_version: leg % expected version % but found %', p_shipment_leg_id, p_expected_version, v_leg.record_version
      using errcode = 'serialization_failure';
  end if;

  v_allowed := (v_leg.leg_status = 'planned' and p_to_status = 'dispatched')
    or (v_leg.leg_status = 'dispatched' and p_to_status = 'in_transit')
    or (v_leg.leg_status = 'in_transit' and p_to_status = 'arrived')
    or (v_leg.leg_status = 'arrived' and p_to_status = 'completed')
    or (v_leg.leg_status in ('planned', 'dispatched', 'in_transit', 'arrived') and p_to_status = 'cancelled');

  if not v_allowed then
    raise exception 'invalid_leg_status_transition: leg % cannot move from % to %', p_shipment_leg_id, v_leg.leg_status, p_to_status
      using errcode = 'check_violation';
  end if;

  if v_leg.leg_status = 'planned' and p_to_status = 'dispatched' and v_shipment.leg_network_status <> 'confirmed' then
    raise exception 'network_not_confirmed: shipment order % leg network must be confirmed before any leg can dispatch', v_leg.shipment_order_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_legs
  set leg_status = p_to_status,
      actual_departure_at = case when p_to_status = 'dispatched' and actual_departure_at is null then now() else actual_departure_at end,
      actual_arrival_at = case when p_to_status = 'arrived' and actual_arrival_at is null then now() else actual_arrival_at end
  where id = p_shipment_leg_id and record_version = p_expected_version
  returning * into v_leg;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: transition_shipment_leg target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, jsonb_build_object('leg_status', p_to_status), jsonb_build_object('leg_status', v_leg.leg_status)
  );

  return v_leg;
end;
$function$
;


-- app.validate_route_planning_scenario
create or replace function app.validate_route_planning_scenario(p_scenario_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_scenario.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

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
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: validate_route_planning_scenario target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'validate_route_planning_scenario',
    'app.route_planning_scenarios', v_scenario.id, 'success', null, null,
    jsonb_build_object('stop_count', v_stop_count, 'position_usable', v_position.is_usable)
  );

  return v_scenario;
end;
$function$
;


-- app.withdraw_claim_item
create or replace function app.withdraw_claim_item(p_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.claim_items;
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: withdrawing a claim item requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_item from app.claim_items where id = p_item_id;
  if not found then
    raise exception 'claim_item_not_found: %', p_item_id using errcode = 'no_data_found';
  end if;
  select * into v_case from app.claim_case_extensions where id = v_item.claim_case_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_item_not_found: %', p_item_id using errcode = 'no_data_found';
  end if;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim item %', p_actor_auth_user_id, p_item_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.status <> 'active' then
    raise exception 'invalid_transition: claim item % is % and cannot be withdrawn', p_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: claim item % expected version % but found %', p_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;

  update app.claim_items
  set status = 'withdrawn', withdrawn_at = now(), withdrawn_by = p_actor_label, withdrawal_reason = p_reason
  where id = p_item_id and record_version = p_expected_version
  returning * into v_item;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: withdraw_claim_item target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_claim_item',
    'app.claim_items', v_item.id, 'success', p_reason, null, null
  );

  return v_item;
end;
$function$
;
