-- CG-AUDIT-2026-09-02 E5 (ETA speed-constant bounded core): the audit's own E5
-- finding covered "ETA is straight-line/40kmh" as one item; a dedicated
-- re-verification pass split it in two. The DISTANCE half (straight-line, no
-- road-network/traffic awareness) genuinely needs a mapping-API/routing-engine
-- integration and stays DEFERRED_LARGE, untouched by this migration. The SPEED
-- half -- a single hardcoded 40km/h constant (app.route_planning_default_
-- speed_kmh, ATW-224's own "governed default", never redefined since its
-- original migration) shared by exactly two consumers
-- (app._compute_shipment_leg_eta and app.generate_route_planning_candidates,
-- both confirmed via grep to have never been redefined since
-- 20260901150000_harden_relocate_postgis_out_of_public.sql, their only later
-- redefinition) -- has a real, bounded, zero-external-API fix: this codebase
-- already ingests and stores real per-vehicle telemetry
-- (app.canonical_telemetry_events.speed_kmh, ATW-226F, fed live by the direct-
-- device and third-party-platform ingestion paths, hardened across 8+
-- subsequent migrations) that a flat national constant simply never used.
--
-- Fix: a new internal helper, app._route_planning_effective_speed_kmh,
-- computes a vehicle's own recent observed average speed from real telemetry
-- (last 30 days, speed_kmh in (0, 200] to exclude idle/parked readings and
-- implausible GPS glitches, requiring >=5 qualifying samples before trusting
-- it), falling back to the unchanged app.route_planning_default_speed_kmh()
-- constant for a cold-start/insufficiently-tracked vehicle -- purely additive,
-- never worse than the pre-fix behavior. Swapped into the two consumers' own
-- one call site each (verified via a mechanical diff against each function's
-- current body that this is the ONLY line changed in either). This
-- personalizes the ETA assumption per vehicle (implicitly capturing vehicle
-- class, typical routes, and driver behavior) but does not fix the underlying
-- straight-line-distance approximation -- honestly, only a partial accuracy
-- improvement, disclosed as such, not a claim of solved ETA.
--
-- Internal helper only (leading underscore, no public.* wrapper, granted only
-- to service_role) -- matches app._compute_shipment_leg_eta's own established
-- convention for a function called only from within other SECURITY DEFINER
-- functions, never a direct RPC target; confirmed via grep that no
-- underscore-prefixed function in this schema has ever received a public.*
-- wrapper.

create function app._route_planning_effective_speed_kmh(p_vehicle_master_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_avg_speed numeric;
  v_sample_count integer;
begin
  select avg(speed_kmh), count(*)
  into v_avg_speed, v_sample_count
  from app.canonical_telemetry_events
  where vehicle_master_id = p_vehicle_master_id
    and event_at >= now() - interval '30 days'
    and speed_kmh is not null
    and speed_kmh > 0
    and speed_kmh <= 200;

  if v_sample_count < 5 or v_avg_speed is null then
    return app.route_planning_default_speed_kmh();
  end if;

  return round(v_avg_speed, 1);
end;
$$;

comment on function app._route_planning_effective_speed_kmh is
  'CG-AUDIT-2026-09-02 E5 (ETA speed-constant bounded core): personalizes app.route_planning_default_speed_kmh()''s flat 40km/h ETA assumption per vehicle, using that vehicle''s own real, already-populated telemetry (app.canonical_telemetry_events.speed_kmh, live device-reported speed, ATW-226F) rather than a mapping-API/road-network integration -- ATW-224''s own governed default remains the untouched cold-start/insufficient-history fallback (fewer than 5 qualifying samples in the last 30 days). Internal helper (underscore-prefixed, no public.* wrapper, matching app._compute_shipment_leg_eta''s own convention) -- called only from within this migration''s two already-security-definer consumers, never a direct RPC target.';

revoke execute on function app._route_planning_effective_speed_kmh(uuid) from public;
grant execute on function app._route_planning_effective_speed_kmh(uuid) to service_role;

-- The following two functions are mechanically patched, verbatim-except-one-
-- line copies of their current (and, in each case, only-ever-redefined) body
-- -- confirmed via a Python difflib diff against the live migration file
-- before this file was written that ONLY the app.route_planning_default_
-- speed_kmh() call site changed in each.

create or replace function app._compute_shipment_leg_eta(p_shipment_leg_id uuid)
 returns app.shipment_leg_eta_projection
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
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
  v_result.estimated_arrival_at := now() + (v_result.remaining_distance_km / app._route_planning_effective_speed_kmh(v_vehicle_master_id)) * interval '1 hour';
  if v_leg.planned_arrival_at is not null then
    v_result.delay_minutes := round(extract(epoch from (v_result.estimated_arrival_at - v_leg.planned_arrival_at)) / 60, 1);
  end if;
  v_result.computable := true;
  v_result.reason := null;
  return v_result;
end;
$function$;

create or replace function app.generate_route_planning_candidates(p_scenario_id uuid, p_actor_label text)
 returns SETOF app.route_planning_candidate_plans
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
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

    v_duration := case when v_total_distance_km is not null then round(v_total_distance_km / app._route_planning_effective_speed_kmh(v_vehicle.vehicle_master_id) * 60, 1) else null end;
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
$function$;
