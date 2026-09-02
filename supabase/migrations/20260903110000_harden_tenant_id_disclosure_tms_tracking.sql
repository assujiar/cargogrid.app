-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 1 of 3 -- Advanced TMS: multi-leg shipments, fleet/device/SIM assignment, route & load
-- planning, mile orchestration & leg tracking, driver-mobile tracking, third-party provider
-- adapters, geofence/route-deviation signals, milestone & exception telemetry.
--
-- Continues the already-established, already-precedented remediation of this defect class
-- (ISS-2026-043 / ISS-2026-048 / ISS-2026-054, and the eight 20260902* parts that fixed
-- Finance, HRIS, Procurement, Ticketing, Platform Core, Commercial and Operations). See
-- docs/runtime/KNOWN_ISSUES.md's own ISS-2026-146 entry for the full disclosure history.
--
-- Root cause (unchanged from the original disclosure): each function below looks a record
-- up by its own bare `id` (the caller does not yet know which tenant owns it), THEN
-- evaluates the actor's authority against the looked-up row's own real tenant_id, and on
-- denial raises 'insufficient_authority: ... for tenant %', interpolating that real,
-- genuine tenant_id -- disclosing it to a caller who has not yet been shown to have any
-- relationship to that tenant at all.
--
-- The fix, identical in shape to every prior part: fold
-- `app.has_active_tenant_membership(<row>.tenant_id, p_actor_auth_user_id)` into the SAME
-- not-found branch the row-miss case already raises, reusing that branch's identical
-- generic message and errcode = 'no_data_found'. A caller with zero relationship to the
-- record's real tenant now gets exactly the error a genuinely nonexistent id already
-- produces. A genuine member of that tenant who merely lacks the ROLE authority is
-- completely unaffected and still reaches the specific insufficient_authority raise below
-- it, with the same insufficient_privilege errcode as before -- preserving that
-- distinction is the whole point of the fix.
--
-- No permission check is weakened anywhere. app.evaluate_permission -- the single authority
-- door all 121 functions in this batch pass through -- has itself returned
-- `not_active_tenant_member` (allowed = false) for a zero-membership actor since HDN-373
-- (ISS-2026-180). So every actor newly short-circuited by the membership pre-check below was
-- ALREADY being refused; only the SHAPE of that refusal changes (a generic not-found instead
-- of a specific insufficient_privilege carrying a real foreign UUID). No caller who was
-- previously allowed is denied by this migration.
--
-- Three shapes appear below:
--   (A) 7 functions -- the canonical shape: the disclosing SELECT is already
--       followed by its own `if not found then raise ... no_data_found; end if;`, so the
--       membership check is folded straight into that existing branch.
--   (B) 14 functions -- a two-step lookup: an already-guarded child row is fetched by
--       bare id, then its parent (the row whose tenant_id is disclosed) is fetched by that
--       child's FK with no not-found branch of its own, because the FK guarantees the parent
--       exists. For these a NEW guard is added immediately after that parent SELECT, reusing
--       VERBATIM the message and errcode of the child's own not-found raise one statement
--       above it, so both failure paths stay byte-identical from the caller's point of view.
--   (C) 1 function -- app.end_leg_tracking_session, which carries a deliberate second
--       authority path: a driver-mobile session token, where "token possession IS the
--       authority" and the driver is NOT required to be a tenant member (226_*.md sec.26).
--       That branch raises no tenant_id-bearing message at all. An unconditional gate would
--       have broken a real, legitimate caller, so the guard is placed at the top of the
--       `else` (RBAC) branch instead -- the only branch that discloses a tenant_id. The
--       driver-mobile path is byte-for-byte untouched.
--
-- Every function below is CREATE OR REPLACE against its CURRENT, live body, read via
-- pg_get_functiondef from a disposable database built by applying all 479 committed
-- migrations in order -- not reconstructed by hand from a possibly-superseded migration
-- file. Signatures, volatility, SECURITY DEFINER, search_path and grants are unchanged
-- throughout, so no grant or wrapper is affected.
--
-- Scope of this part: 22 functions (23 raise sites).

CREATE OR REPLACE FUNCTION app.add_route_planning_constraint(p_scenario_id uuid, p_constraint_type text, p_constraint_key text, p_constraint_value jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_constraints
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION app.assign_device_to_vehicle(p_device_id uuid, p_vehicle_profile_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.device_vehicle_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_device app.gps_devices;
  v_profile app.vehicle_operational_profiles;
  v_decision app.rbac_decision;
  v_prior app.device_vehicle_assignments;
  v_had_prior boolean := false;
  v_assignment app.device_vehicle_assignments;
begin
  select * into v_device from app.gps_devices where id = p_device_id;
  if not found or not app.has_active_tenant_membership(v_device.tenant_id, p_actor_auth_user_id) then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;
  if v_device.status = 'retired' then
    raise exception 'device_retired: device % is retired and cannot be assigned', p_device_id using errcode = 'check_violation';
  end if;

  select * into v_profile from app.vehicle_operational_profiles where id = p_vehicle_profile_id;
  if not found then
    raise exception 'vehicle_profile_not_found: %', p_vehicle_profile_id using errcode = 'no_data_found';
  end if;
  if v_profile.tenant_id <> v_device.tenant_id then
    raise exception 'tenant_mismatch: device % and vehicle profile % belong to different tenants', p_device_id, p_vehicle_profile_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prior from app.device_vehicle_assignments where device_id = p_device_id and is_current;
  v_had_prior := found;
  if v_had_prior and v_prior.vehicle_operational_profile_id = p_vehicle_profile_id then
    return v_prior;
  end if;

  if v_had_prior then
    update app.device_vehicle_assignments
    set is_current = false, effective_to = now()
    where id = v_prior.id;
  end if;

  insert into app.device_vehicle_assignments (tenant_id, device_id, vehicle_operational_profile_id, reason, created_by)
  values (v_device.tenant_id, p_device_id, p_vehicle_profile_id, p_reason, p_actor_label)
  returning * into v_assignment;

  if v_had_prior then
    update app.device_vehicle_assignments
    set superseded_by_id = v_assignment.id
    where id = v_prior.id;
  end if;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_device_to_vehicle',
    'app.device_vehicle_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('device_id', p_device_id, 'vehicle_operational_profile_id', p_vehicle_profile_id)
  );

  return v_assignment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.assign_sim_to_device(p_sim_id uuid, p_device_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sim_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_sim app.sim_cards;
  v_device app.gps_devices;
  v_decision app.rbac_decision;
begin
  select * into v_sim from app.sim_cards where id = p_sim_id;
  if not found or not app.has_active_tenant_membership(v_sim.tenant_id, p_actor_auth_user_id) then
    raise exception 'sim_not_found: %', p_sim_id using errcode = 'no_data_found';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;
  if v_device.tenant_id <> v_sim.tenant_id then
    raise exception 'tenant_mismatch: sim % and device % belong to different tenants', p_sim_id, p_device_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_sim.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_sim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if exists (select 1 from app.sim_cards where current_device_id = p_device_id and id <> p_sim_id) then
    raise exception 'device_already_has_sim: device % already has a different SIM assigned', p_device_id using errcode = 'check_violation';
  end if;

  update app.sim_cards set current_device_id = p_device_id, status = 'assigned'
  where id = p_sim_id
  returning * into v_sim;

  perform app.capture_audit_event(
    v_sim.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_sim_to_device',
    'app.sim_cards', v_sim.id, 'success', null, null, jsonb_build_object('device_id', p_device_id)
  );

  return v_sim;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.confirm_exception_signal(p_signal_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.operational_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_signal_not_found: %', p_signal_id using errcode = 'no_data_found';
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION app.confirm_milestone_candidate(p_candidate_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_override_event_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_override_conflict boolean DEFAULT false)
 RETURNS app.milestone_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'milestone_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION app.dismiss_exception_signal(p_signal_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_review_note text)
 RETURNS app.shipment_exception_signals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_signal_not_found: %', p_signal_id using errcode = 'no_data_found';
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION app.dismiss_milestone_candidate(p_candidate_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_review_note text)
 RETURNS app.shipment_milestone_candidates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'milestone_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION app.end_leg_tracking_session(p_shipment_leg_id uuid, p_end_reason text, p_reason_note text, p_actor_auth_user_id uuid, p_actor_label text, p_driver_mobile_session_id uuid DEFAULT NULL::uuid)
 RETURNS app.shipment_leg_tracking_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_session app.shipment_leg_tracking_sessions;
begin
  if p_end_reason not in ('leg_completed', 'manual_stop', 'unauthorized_override') then
    raise exception 'invalid_end_reason: % is not a supported end reason for a direct end call', p_end_reason using errcode = 'check_violation';
  end if;
  if p_end_reason = 'manual_stop' and (p_reason_note is null or length(trim(p_reason_note)) = 0) then
    raise exception 'end_reason_required: a non-empty reason is required to manually stop a tracking session' using errcode = 'check_violation';
  end if;
  if p_end_reason = 'unauthorized_override' and (p_reason_note is null or length(trim(p_reason_note)) = 0) then
    raise exception 'override_reason_required: a non-empty reason is required to force-end a tracking session' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if p_driver_mobile_session_id is not null then
    -- Driver-initiated stop via an already-validated mobile session token -- token
    -- possession IS the authority for this one session (226_*.md §26: "drivers
    -- control only their assigned mobile session"). Never a blanket bypass: only
    -- manual_stop, and only when the given token genuinely maps to this leg's own
    -- current tracking session.
    if p_end_reason <> 'manual_stop' then
      raise exception 'invalid_end_reason: a driver-mobile-initiated stop must use manual_stop' using errcode = 'check_violation';
    end if;
    if not exists (
      select 1 from app.driver_mobile_tracking_sessions dms
      join app.shipment_leg_tracking_sessions slts on slts.id = dms.shipment_leg_tracking_session_id
      where dms.id = p_driver_mobile_session_id and slts.shipment_leg_id = p_shipment_leg_id and slts.is_current
    ) then
      raise exception 'driver_mobile_session_mismatch: % does not map to the current tracking session for leg %', p_driver_mobile_session_id, p_shipment_leg_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
      raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
    end if;
    if p_end_reason = 'unauthorized_override' then
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Override');
      if not v_decision.allowed then
        raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
          using errcode = 'insufficient_privilege';
      end if;
    else
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
      if not v_decision.allowed then
        raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
          using errcode = 'insufficient_privilege';
      end if;
    end if;
    if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
      raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  select * into v_session from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if not found then
    raise exception 'no_active_session: leg % has no active tracking session to end', p_shipment_leg_id using errcode = 'check_violation';
  end if;

  update app.shipment_leg_tracking_sessions
  set is_current = false, status = 'ended', ended_at = now(), end_reason = p_end_reason
  where id = v_session.id
  returning * into v_session;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, coalesce(p_actor_label, 'driver-mobile'), 'end_leg_tracking_session',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', p_reason_note, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'end_reason', p_end_reason, 'driver_mobile_session_id', p_driver_mobile_session_id)
  );

  return v_session;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.evaluate_leg_no_signal_escalation(p_shipment_leg_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_leg_tracking_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION app.get_shipment_leg_eta_projection(p_shipment_leg_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.shipment_leg_eta_projection
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION app.get_shipment_leg_route_deviation_state(p_shipment_leg_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.shipment_leg_route_deviation_states
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
  select * from app.shipment_leg_route_deviation_states where shipment_leg_id = p_shipment_leg_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.handoff_leg_tracking_session(p_shipment_leg_id uuid, p_source_type text, p_resource_kind text, p_resource_master_id uuid, p_device_id uuid, p_handoff_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_leg_tracking_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.shipment_leg_tracking_policies;
  v_prior app.shipment_leg_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
begin
  if p_source_type not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'invalid_source_type: % is not a supported tracking source', p_source_type using errcode = 'check_violation';
  end if;
  if p_resource_kind not in ('vehicle', 'driver') then
    raise exception 'invalid_resource_kind: % is not a supported resource kind', p_resource_kind using errcode = 'check_violation';
  end if;
  if p_handoff_reason is null or length(trim(p_handoff_reason)) = 0 then
    raise exception 'handoff_reason_required: a non-empty reason is required to hand off a tracking session' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
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

  select * into v_policy from app.shipment_leg_tracking_policies where shipment_leg_id = p_shipment_leg_id;
  if not found or not v_policy.tracking_required then
    raise exception 'tracking_not_required: leg % has no tracking-required policy to hand off', p_shipment_leg_id using errcode = 'check_violation';
  end if;
  if not (p_source_type = any (v_policy.allowed_sources)) then
    raise exception 'source_not_allowed: % is not among the policy''s own allowed_sources for leg %', p_source_type, p_shipment_leg_id using errcode = 'check_violation';
  end if;

  select * into v_prior from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if not found then
    raise exception 'no_active_session: leg % has no active tracking session to hand off -- use start instead', p_shipment_leg_id using errcode = 'check_violation';
  end if;

  if not app.check_leg_tracking_source_eligible(p_shipment_leg_id, p_source_type, p_resource_kind, p_resource_master_id, p_device_id) then
    raise exception 'source_not_eligible: % (%) is not currently eligible to track leg %', p_source_type, p_resource_master_id, p_shipment_leg_id
      using errcode = 'check_violation';
  end if;

  update app.shipment_leg_tracking_sessions set is_current = false, status = 'ended', ended_at = now(), end_reason = 'handoff' where id = v_prior.id;

  insert into app.shipment_leg_tracking_sessions (
    tenant_id, shipment_leg_id, policy_id, source_type, resource_kind, resource_master_id, device_id, tracking_entitled_at_start, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_leg_id, v_policy.id, p_source_type, p_resource_kind, p_resource_master_id, p_device_id,
    app.is_shipment_tracking_entitled(v_shipment.tenant_id), p_actor_label
  )
  returning * into v_session;

  update app.shipment_leg_tracking_sessions set superseded_by_id = v_session.id where id = v_prior.id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'handoff_leg_tracking_session',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'from_session_id', v_prior.id, 'to_source_type', p_source_type, 'reason', p_handoff_reason)
  );

  return v_session;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.migrate_legacy_shipment_to_leg_network(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_legs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_legs;
  v_leg app.shipment_legs;
  v_leg_status text;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.shipment_legs where shipment_order_id = p_shipment_order_id order by sequence_no asc limit 1;
  if found then
    return v_existing;
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

  v_leg_status := case
    when v_shipment.status in ('delivered', 'epod', 'closed') then 'completed'
    when v_shipment.status in ('dispatched', 'in_transit') then v_shipment.status
    else 'planned'
  end;

  insert into app.shipment_legs (
    tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, is_legacy_compat,
    planned_departure_at, planned_arrival_at, owner_user_id, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, 1, 'legacy-compat:' || p_shipment_order_id::text, v_shipment.mode, v_leg_status, true,
    v_shipment.planned_pickup_at, v_shipment.planned_delivery_at, v_shipment.owner_user_id, p_actor_label
  )
  returning * into v_leg;

  insert into app.shipment_leg_stops (tenant_id, shipment_leg_id, stop_sequence, stop_type, location_name, planned_at, created_by)
  values
    (v_shipment.tenant_id, v_leg.id, 1, 'pickup', v_shipment.origin, v_shipment.planned_pickup_at, p_actor_label),
    (v_shipment.tenant_id, v_leg.id, 2, 'delivery', v_shipment.destination, v_shipment.planned_delivery_at, p_actor_label);

  insert into app.shipment_leg_cargo_allocations (tenant_id, shipment_leg_id, allocated_quantity, allocated_weight_kg, allocated_volume_cbm, created_by)
  values (v_shipment.tenant_id, v_leg.id, v_shipment.allocated_quantity, v_shipment.allocated_weight_kg, v_shipment.allocated_volume_cbm, p_actor_label);

  update app.shipment_orders set leg_network_status = 'confirmed' where id = p_shipment_order_id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'migrate_legacy_shipment_to_leg_network',
    'app.shipment_legs', v_leg.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'leg_status', v_leg_status)
  );

  return v_leg;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_shipment_leg_custody_event(p_shipment_leg_id uuid, p_event_type text, p_from_party_snapshot jsonb, p_to_party_snapshot jsonb, p_occurred_at timestamp with time zone, p_evidence jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_leg_custody_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_event app.shipment_leg_custody_events;
  v_sequence integer;
begin
  if p_event_type not in ('custody_transfer', 'handoff_confirmed') then
    raise exception 'invalid_event_type: % is not a supported custody event type', p_event_type using errcode = 'check_violation';
  end if;

  if p_to_party_snapshot is null then
    raise exception 'to_party_required: a custody event must name the party that now holds custody' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
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

  v_sequence := app.next_shipment_leg_custody_sequence(p_shipment_leg_id);

  insert into app.shipment_leg_custody_events (
    tenant_id, shipment_leg_id, sequence_no, event_type, from_party_snapshot, to_party_snapshot, occurred_at, evidence, recorded_by
  ) values (
    v_leg.tenant_id, p_shipment_leg_id, v_sequence, p_event_type, p_from_party_snapshot, p_to_party_snapshot, p_occurred_at, p_evidence, p_actor_label
  )
  returning * into v_event;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_shipment_leg_custody_event',
    'app.shipment_leg_custody_events', v_event.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'event_type', p_event_type, 'sequence_no', v_sequence)
  );

  return v_event;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.replan_route_planning_scenario(p_scenario_id uuid, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
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
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION app.start_driver_mobile_session(p_shipment_leg_tracking_session_id uuid, p_validity_hours integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS TABLE(driver_mobile_session_id uuid, raw_token text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_session app.shipment_leg_tracking_sessions;
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_raw_token text;
  v_token_hash text;
  v_expires_at timestamptz;
  v_row app.driver_mobile_tracking_sessions;
begin
  select * into v_session from app.shipment_leg_tracking_sessions where id = p_shipment_leg_tracking_session_id;
  if not found then
    raise exception 'tracking_session_not_found: %', p_shipment_leg_tracking_session_id using errcode = 'no_data_found';
  end if;
  if v_session.source_type <> 'driver_mobile' then
    raise exception 'not_a_driver_mobile_session: % has source_type %, not driver_mobile', p_shipment_leg_tracking_session_id, v_session.source_type
      using errcode = 'check_violation';
  end if;
  if not v_session.is_current or v_session.status <> 'active' then
    raise exception 'tracking_session_not_active: % is not the current active tracking session', p_shipment_leg_tracking_session_id
      using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = v_session.shipment_leg_id;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'tracking_session_not_found: %', p_shipment_leg_tracking_session_id using errcode = 'no_data_found';
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

  if exists (select 1 from app.driver_mobile_tracking_sessions where shipment_leg_tracking_session_id = p_shipment_leg_tracking_session_id and status = 'active') then
    raise exception 'driver_mobile_session_already_issued: % already has an active mobile session token -- revoke it first to issue a new one', p_shipment_leg_tracking_session_id
      using errcode = 'unique_violation';
  end if;

  if coalesce(p_validity_hours, 0) <= 0 or p_validity_hours > 168 then
    raise exception 'invalid_validity_hours: validity_hours must be between 1 and 168 (7 days)' using errcode = 'check_violation';
  end if;

  v_raw_token := 'dmt_' || encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');
  v_expires_at := now() + (p_validity_hours || ' hours')::interval;

  insert into app.driver_mobile_tracking_sessions (tenant_id, shipment_leg_tracking_session_id, token_hash, expires_at, created_by)
  values (v_shipment.tenant_id, p_shipment_leg_tracking_session_id, v_token_hash, v_expires_at, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_driver_mobile_session',
    'app.driver_mobile_tracking_sessions', v_row.id, 'success', null, null,
    jsonb_build_object('shipment_leg_tracking_session_id', p_shipment_leg_tracking_session_id, 'expires_at', v_expires_at)
  );

  return query select v_row.id, v_raw_token, v_row.expires_at;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.start_leg_tracking_session(p_shipment_leg_id uuid, p_source_type text, p_resource_kind text, p_resource_master_id uuid, p_device_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_leg_tracking_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.shipment_leg_tracking_policies;
  v_existing app.shipment_leg_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
begin
  if p_source_type not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'invalid_source_type: % is not a supported tracking source', p_source_type using errcode = 'check_violation';
  end if;
  if p_resource_kind not in ('vehicle', 'driver') then
    raise exception 'invalid_resource_kind: % is not a supported resource kind', p_resource_kind using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
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

  select * into v_policy from app.shipment_leg_tracking_policies where shipment_leg_id = p_shipment_leg_id;
  if not found then
    raise exception 'policy_not_defined: leg % has no tracking policy defined yet', p_shipment_leg_id using errcode = 'check_violation';
  end if;
  if not v_policy.tracking_required then
    raise exception 'tracking_not_required: leg % is explicitly not tracking-required', p_shipment_leg_id using errcode = 'check_violation';
  end if;
  if not (p_source_type = any (v_policy.allowed_sources)) then
    raise exception 'source_not_allowed: % is not among the policy''s own allowed_sources for leg %', p_source_type, p_shipment_leg_id using errcode = 'check_violation';
  end if;

  select * into v_existing from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if found then
    raise exception 'session_already_active: leg % already has an active tracking session -- use handoff instead', p_shipment_leg_id using errcode = 'check_violation';
  end if;

  if not app.check_leg_tracking_source_eligible(p_shipment_leg_id, p_source_type, p_resource_kind, p_resource_master_id, p_device_id) then
    raise exception 'source_not_eligible: % (%) is not currently eligible to track leg %', p_source_type, p_resource_master_id, p_shipment_leg_id
      using errcode = 'check_violation';
  end if;

  insert into app.shipment_leg_tracking_sessions (
    tenant_id, shipment_leg_id, policy_id, source_type, resource_kind, resource_master_id, device_id, tracking_entitled_at_start, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_leg_id, v_policy.id, p_source_type, p_resource_kind, p_resource_master_id, p_device_id,
    app.is_shipment_tracking_entitled(v_shipment.tenant_id), p_actor_label
  )
  returning * into v_session;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_leg_tracking_session',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'source_type', p_source_type, 'resource_master_id', p_resource_master_id)
  );

  return v_session;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.unassign_device_from_vehicle(p_device_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.device_vehicle_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_device app.gps_devices;
  v_decision app.rbac_decision;
  v_current app.device_vehicle_assignments;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'unassign_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found or not app.has_active_tenant_membership(v_device.tenant_id, p_actor_auth_user_id) then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current from app.device_vehicle_assignments where device_id = p_device_id and is_current;
  if not found then
    raise exception 'no_current_assignment: device % has no current vehicle assignment to release', p_device_id using errcode = 'check_violation';
  end if;

  update app.device_vehicle_assignments set is_current = false, effective_to = now(), reason = p_reason
  where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'unassign_device_from_vehicle',
    'app.device_vehicle_assignments', v_current.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_current;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.unassign_sim_from_device(p_sim_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sim_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_sim app.sim_cards;
  v_decision app.rbac_decision;
begin
  select * into v_sim from app.sim_cards where id = p_sim_id;
  if not found or not app.has_active_tenant_membership(v_sim.tenant_id, p_actor_auth_user_id) then
    raise exception 'sim_not_found: %', p_sim_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_sim.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_sim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.sim_cards set current_device_id = null, status = 'stock'
  where id = p_sim_id
  returning * into v_sim;

  perform app.capture_audit_event(
    v_sim.tenant_id, p_actor_auth_user_id, p_actor_label, 'unassign_sim_from_device',
    'app.sim_cards', v_sim.id, 'success', null, null, null
  );

  return v_sim;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.update_third_party_provider_poll_cursor(p_connection_id uuid, p_cursor jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.third_party_provider_connections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found or not app.has_active_tenant_membership(v_conn.tenant_id, p_actor_auth_user_id) then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_conn.integration_mode <> 'poll' then
    raise exception 'not_a_poll_connection: % is a % connection, has no poll cursor to update', p_connection_id, v_conn.integration_mode
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.third_party_provider_connections set poll_cursor = p_cursor where id = p_connection_id
  returning * into v_conn;

  return v_conn;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.upsert_shipment_leg_tracking_policy(p_shipment_leg_id uuid, p_tracking_required boolean, p_allowed_sources text[], p_preferred_source text, p_fallback_order text[], p_freshness_tolerance_seconds integer, p_accuracy_tolerance_meters numeric, p_ping_interval_seconds integer, p_start_trigger text, p_end_trigger text, p_geofence_policy jsonb, p_customer_visible boolean, p_no_signal_escalation_seconds integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_leg_tracking_policies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.shipment_leg_tracking_policies;
begin
  if p_start_trigger not in ('leg_dispatch', 'first_stop_arrival') then
    raise exception 'invalid_start_trigger: % is not a supported start trigger', p_start_trigger using errcode = 'check_violation';
  end if;
  if p_end_trigger not in ('last_stop_arrival', 'leg_complete') then
    raise exception 'invalid_end_trigger: % is not a supported end trigger', p_end_trigger using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;
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

  insert into app.shipment_leg_tracking_policies (
    tenant_id, shipment_leg_id, tracking_required, allowed_sources, preferred_source, fallback_order,
    freshness_tolerance_seconds, accuracy_tolerance_meters, ping_interval_seconds, start_trigger, end_trigger,
    geofence_policy, customer_visible, no_signal_escalation_seconds, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_leg_id, p_tracking_required, coalesce(p_allowed_sources, '{}'), p_preferred_source, coalesce(p_fallback_order, '{}'),
    p_freshness_tolerance_seconds, p_accuracy_tolerance_meters, p_ping_interval_seconds, p_start_trigger, p_end_trigger,
    p_geofence_policy, coalesce(p_customer_visible, false), p_no_signal_escalation_seconds, p_actor_label
  )
  on conflict (shipment_leg_id) do update set
    tracking_required = excluded.tracking_required,
    allowed_sources = excluded.allowed_sources,
    preferred_source = excluded.preferred_source,
    fallback_order = excluded.fallback_order,
    freshness_tolerance_seconds = excluded.freshness_tolerance_seconds,
    accuracy_tolerance_meters = excluded.accuracy_tolerance_meters,
    ping_interval_seconds = excluded.ping_interval_seconds,
    start_trigger = excluded.start_trigger,
    end_trigger = excluded.end_trigger,
    geofence_policy = excluded.geofence_policy,
    customer_visible = excluded.customer_visible,
    no_signal_escalation_seconds = excluded.no_signal_escalation_seconds
  returning * into v_policy;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'upsert_shipment_leg_tracking_policy',
    'app.shipment_leg_tracking_policies', v_policy.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'tracking_required', p_tracking_required, 'policy_version', v_policy.policy_version)
  );

  return v_policy;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.verify_gps_device_installation(p_installation_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.gps_device_installations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_installation app.gps_device_installations;
  v_decision app.rbac_decision;
begin
  select * into v_installation from app.gps_device_installations where id = p_installation_id;
  if not found or not app.has_active_tenant_membership(v_installation.tenant_id, p_actor_auth_user_id) then
    raise exception 'installation_not_found: %', p_installation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_installation.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_installation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.gps_device_installations
  set verified_by_auth_user_id = p_actor_auth_user_id, verified_at = now()
  where id = p_installation_id
  returning * into v_installation;

  perform app.capture_audit_event(
    v_installation.tenant_id, p_actor_auth_user_id, p_actor_label, 'verify_gps_device_installation',
    'app.gps_device_installations', v_installation.id, 'success', null, null, jsonb_build_object('verified_at', v_installation.verified_at)
  );

  return v_installation;
end;
$function$
;
