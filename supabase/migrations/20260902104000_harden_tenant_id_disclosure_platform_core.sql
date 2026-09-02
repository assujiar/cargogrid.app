-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 5 of 5 of a representative repository-wide fix pass (Platform Core).
-- See 20260902100000_harden_tenant_id_disclosure_finance.sql for the full rationale
-- (same fix pattern, same repository-wide precedent, applied here to Platform Core).
-- Every function below is CREATE OR REPLACE against its CURRENT, live body -- signatures
-- are unchanged throughout, so grants are unaffected.

CREATE OR REPLACE FUNCTION app.approve_cycle_count_variance(p_scope_item_id uuid, p_expected_version integer, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.cycle_count_scope_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_plan app.cycle_count_plans;
  v_last_observation app.cycle_count_observations;
  v_balance app.inventory_balances;
  v_movement app.inventory_movements;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to approve a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot approve scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to approve scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before. Never re-posts a second ledger movement for an already-adjusted item.
  if v_item.status = 'adjusted' and v_item.adjustment_movement_id is not null then
    return v_item;
  end if;

  if v_item.status <> 'pending_review' then
    raise exception 'task_not_pending_review: scope item % is % -- only a pending_review item may be approved', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to approve a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_plan from app.cycle_count_plans where id = v_item.plan_id;

  if v_plan.requires_separate_approver then
    select * into v_last_observation from app.cycle_count_observations
      where scope_item_id = p_scope_item_id
      order by attempt_number desc
      limit 1;
    -- ISS-2026-213 fix: coalesce(..., true) -- a null v_last_observation.counted_by_
    -- auth_user_id (structurally unreachable today, see this migration's own header) now
    -- denies rather than silently passing.
    if found and coalesce(v_last_observation.counted_by_auth_user_id = p_actor_auth_user_id, true) then
      raise exception 'self_approval_not_allowed: identity % submitted the most recent count for scope item % and may not also approve its own variance', p_actor_auth_user_id, p_scope_item_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Design note 4: stale-snapshot detection -- re-lock the CURRENT balance row and
  -- compare its live record_version against the snapshot's own captured version.
  select * into v_balance from app.inventory_balances where id = v_item.snapshot_balance_id for update;
  if not found then
    raise exception 'balance_not_found: snapshot balance % no longer exists', v_item.snapshot_balance_id using errcode = 'no_data_found';
  end if;
  if v_balance.record_version <> v_item.snapshot_record_version then
    raise exception 'balance_changed_since_snapshot: balance % has changed since scope item %''s own snapshot was taken (expected version %, found %) -- cancel this scope item and refreeze rather than post a now-incorrect adjustment', v_item.snapshot_balance_id, p_scope_item_id, v_item.snapshot_record_version, v_balance.record_version
      using errcode = 'check_violation';
  end if;

  -- The one and only place a cycle count ever changes on_hand -- via the canonical
  -- app.post_inventory_movement primitive, never a direct balance write (Prompt 239
  -- section 24, this task's own objective).
  v_movement := app.post_inventory_movement(
    v_item.tenant_id, v_item.warehouse_id, 'adjustment', 'cycle_count', p_scope_item_id, p_idempotency_key, p_reason,
    jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_item.owner_account_id, 'item_master_id', v_item.item_master_id, 'location_id', v_item.location_id,
      'uom_code', v_item.uom_code, 'signed_quantity', v_item.variance_quantity, 'lot_number', v_item.lot_number, 'serial_number', v_item.serial_number, 'status', 'on_hand'
    )),
    p_actor_auth_user_id, p_actor_label
  );

  -- Findings review (HIGH #4): app.post_inventory_movement's own idempotency dedups
  -- purely on (tenant_id, idempotency_key) -- it has no way to know this call's own
  -- scope item. If p_idempotency_key was already used by a DIFFERENT scope item's
  -- approval, the call above silently returns THAT item's already-posted movement
  -- unchanged. Attaching it to the CURRENT item here would mark it adjusted with a
  -- movement that reflects a completely different item/location/lot/quantity, and its
  -- own real variance would never be posted -- reject instead, exactly like a genuine
  -- idempotency-key collision anywhere else in this migration.
  if v_movement.source_type <> 'cycle_count' or v_movement.source_id <> p_scope_item_id then
    raise exception 'idempotency_key_conflict: idempotency key % was already used by a different movement (source_type=%, source_id=%), not scope item %', p_idempotency_key, v_movement.source_type, v_movement.source_id, p_scope_item_id
      using errcode = 'unique_violation';
  end if;

  update app.cycle_count_scope_items set
    adjustment_movement_id = v_movement.id,
    status = 'adjusted',
    reviewed_by_auth_user_id = p_actor_auth_user_id,
    reviewed_by_label = p_actor_label,
    reviewed_at = now(),
    review_reason = p_reason
  where id = p_scope_item_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_cycle_count_variance',
    'app.cycle_count_scope_items', v_item.id, 'success', p_reason, null,
    jsonb_build_object('movement_id', v_movement.id, 'variance_quantity', v_item.variance_quantity)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_dedicated_deployment_qualification(p_deployment_record_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.tenant_deployment_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id and status = 'pending_qualification' for update;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'deployment_record_not_pending_qualification: % is not a pending-qualification deployment record', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-213 fix: coalesce(..., true) -- a null v_record.created_by_auth_user_id
  -- (structurally unreachable today, see this migration's own header) now denies rather
  -- than silently passing.
  if coalesce(v_record.created_by_auth_user_id = p_actor_auth_user_id, true) then
    raise exception 'deployment_self_approval_forbidden: identity % cannot approve a dedicated deployment qualification they themselves requested', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.tenant_deployment_records
  set status = 'qualified', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, approved_at = now()
  where id = p_deployment_record_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_dedicated_deployment_qualification',
    'app.tenant_deployment_records', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_region_assignment(p_region_assignment_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.tenant_region_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_record app.tenant_region_assignments;
  v_decision app.rbac_decision;
  v_category text;
  v_supported boolean;
  v_has_exception boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_region_assignments where id = p_region_assignment_id and status = 'pending_review' for update;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'region_assignment_not_pending_review: % is not a pending-review region assignment', p_region_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-213 fix: coalesce(..., true) -- a null v_record.created_by_auth_user_id
  -- (structurally unreachable today, see this migration's own header) now denies rather
  -- than silently passing.
  if coalesce(v_record.created_by_auth_user_id = p_actor_auth_user_id, true) then
    raise exception 'region_self_approval_forbidden: identity % cannot approve a region assignment they themselves requested', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if app.resolve_tenant_deployment_type(v_record.tenant_id) <> 'dedicated' then
    raise exception 'region_requires_dedicated_deployment: tenant % has no active dedicated deployment (RPD-013 -- dedicated region requires dedicated deployment)', v_record.tenant_id
      using errcode = 'check_violation';
  end if;

  foreach v_category in array array['database', 'secrets', 'backup', 'files', 'observability', 'ai_provider']
  loop
    select supported into v_supported from app.region_service_capabilities where region_code = v_record.region_code and service_category = v_category;
    if not coalesce(v_supported, false) then
      select exists(
        select 1 from app.region_capability_exceptions
        where region_assignment_id = v_record.id and service_category = v_category
      ) into v_has_exception;
      if not v_has_exception then
        raise exception 'region_capability_gap_unresolved: % is not supported in % and no exception has been registered', v_category, v_record.region_code
          using errcode = 'check_violation';
      end if;
    end if;
  end loop;

  update app.tenant_region_assignments
  set status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, approved_at = now()
  where id = p_region_assignment_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_region_assignment',
    'app.tenant_region_assignments', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_warehouse_billing_event(p_event_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found or not app.has_active_tenant_membership(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- A governed release-to-Finance decision -- OPS:Override.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot approve billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'reviewed' then
    raise exception 'invalid_transition: billing event % is % -- only reviewed may be approved', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  -- Segregation of duties (mirrors ATW-020's own established self_approval_not_allowed
  -- pattern): the same identity that reviewed an event may not also approve it.
  -- ISS-2026-213 fix: coalesce(..., true) -- a null v_event.reviewed_by_auth_user_id
  -- (structurally unreachable today, see this migration's own header) now denies rather
  -- than silently passing.
  if coalesce(v_event.reviewed_by_auth_user_id = p_actor_auth_user_id, true) then
    raise exception 'self_approval_not_allowed: identity % reviewed billing event % and may not also approve it', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  update app.warehouse_billing_events set
    status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by_label = p_actor_label, approved_at = now()
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034), preserved verbatim from the true latest body: the version
  -- predicate above already PREVENTS the lost update -- the loser's UPDATE simply
  -- matches no row -- but execution must not fall straight through with a NULL
  -- composite (which would both fabricate a 'success' audit row with a NULL tenant_id
  -- and hand the caller an all-NULL record instead of this function's own documented
  -- stale_version error).
  if not found then
    raise exception 'stale_version: approve_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$function$;

CREATE OR REPLACE FUNCTION app.list_deployment_environment_refs(p_deployment_record_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.tenant_deployment_environment_refs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'deployment_record_not_found: %', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.tenant_deployment_environment_refs where deployment_record_id = p_deployment_record_id order by environment_category asc;
end;
$function$;

CREATE OR REPLACE FUNCTION app.register_region_capability_exception(p_region_assignment_id uuid, p_service_category text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.region_capability_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_record app.tenant_region_assignments;
  v_decision app.rbac_decision;
  v_supported boolean;
  v_exception app.region_capability_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_region_assignments where id = p_region_assignment_id;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'region_assignment_not_found: %', p_region_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_service_category not in ('database', 'secrets', 'backup', 'files', 'observability', 'ai_provider') then
    raise exception 'region_invalid_service_category: %', p_service_category using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'region_exception_reason_required: a real accepted-risk reason must be stated' using errcode = 'check_violation';
  end if;

  select supported into v_supported from app.region_service_capabilities where region_code = v_record.region_code and service_category = p_service_category;
  if coalesce(v_supported, false) then
    raise exception 'region_capability_exception_not_needed: % is already supported in % -- no exception is meaningful', p_service_category, v_record.region_code
      using errcode = 'check_violation';
  end if;

  insert into app.region_capability_exceptions (region_assignment_id, service_category, reason, approved_by_auth_user_id, approved_by, approved_at)
  values (p_region_assignment_id, p_service_category, p_reason, p_actor_auth_user_id, p_actor_label, now())
  on conflict (region_assignment_id, service_category) do update
    set reason = excluded.reason, approved_by_auth_user_id = excluded.approved_by_auth_user_id, approved_by = excluded.approved_by, approved_at = excluded.approved_at
  returning * into v_exception;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'register_region_capability_exception',
    'app.region_capability_exceptions', v_exception.id, 'success', null, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reject_cycle_count_variance(p_scope_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.cycle_count_scope_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_plan app.cycle_count_plans;
  v_last_observation app.cycle_count_observations;
begin
  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reject scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to reject scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  if v_item.status <> 'pending_review' then
    raise exception 'task_not_pending_review: scope item % is % -- only a pending_review item may be rejected', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reject a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_plan from app.cycle_count_plans where id = v_item.plan_id;
  if v_plan.requires_separate_approver then
    select * into v_last_observation from app.cycle_count_observations
      where scope_item_id = p_scope_item_id
      order by attempt_number desc
      limit 1;
    -- ISS-2026-213 fix: coalesce(..., true) -- see app.approve_cycle_count_variance's own
    -- identical fix above, applied here to its sibling reject path.
    if found and coalesce(v_last_observation.counted_by_auth_user_id = p_actor_auth_user_id, true) then
      raise exception 'self_approval_not_allowed: identity % submitted the most recent count for scope item % and may not also reject its own variance', p_actor_auth_user_id, p_scope_item_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Design note 7: reviewed_by_auth_user_id/reviewed_at/review_reason are reserved for
  -- a real adjusted resolution (cycle_count_scope_items_adjusted_requires_review_check)
  -- -- never set here. Who rejected and why is captured in the audit event below.
  update app.cycle_count_scope_items set status = 'recount_required' where id = p_scope_item_id returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_cycle_count_variance',
    'app.cycle_count_scope_items', v_item.id, 'success', p_reason, null, null
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_deployment_environment_ref(p_deployment_record_id uuid, p_environment_category text, p_reference_value text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.tenant_deployment_environment_refs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
  v_ref app.tenant_deployment_environment_refs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'deployment_record_not_found: %', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_environment_category not in ('database', 'secrets', 'backup', 'observability') then
    raise exception 'deployment_invalid_environment_category: %', p_environment_category using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_reference_value), '') = '' then
    raise exception 'deployment_reference_value_required: a real reference value must be stated' using errcode = 'check_violation';
  end if;

  insert into app.tenant_deployment_environment_refs (deployment_record_id, environment_category, reference_value, verified_by_auth_user_id, verified_by, verified_at, created_by)
  values (p_deployment_record_id, p_environment_category, p_reference_value, p_actor_auth_user_id, p_actor_label, now(), p_actor_label)
  on conflict (deployment_record_id, environment_category) do update
    set reference_value = excluded.reference_value, verified_by_auth_user_id = excluded.verified_by_auth_user_id, verified_by = excluded.verified_by, verified_at = excluded.verified_at
  returning * into v_ref;

  return v_ref;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_deployment_provisioning_status(p_deployment_record_id uuid, p_new_status text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.tenant_deployment_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
  v_valid_transition boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id for update;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'deployment_record_not_found: %', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_valid_transition := (v_record.status, p_new_status) in (
    ('qualified', 'provisioning'),
    ('provisioning', 'active'),
    ('active', 'decommissioned')
  );
  if not v_valid_transition then
    raise exception 'deployment_invalid_transition: % -> % is not a valid provisioning transition', v_record.status, p_new_status
      using errcode = 'check_violation';
  end if;

  update app.tenant_deployment_records
  set status = p_new_status,
      provisioned_at = case when p_new_status = 'active' then now() else provisioned_at end,
      decommissioned_at = case when p_new_status = 'decommissioned' then now() else decommissioned_at end
  where id = p_deployment_record_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_deployment_provisioning_status',
    'app.tenant_deployment_records', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_region_assignment_status(p_region_assignment_id uuid, p_new_status text, p_rejection_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.tenant_region_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_record app.tenant_region_assignments;
  v_decision app.rbac_decision;
  v_valid_transition boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_region_assignments where id = p_region_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'region_assignment_not_found: %', p_region_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_valid_transition := (v_record.status, p_new_status) in (
    ('pending_review', 'rejected'),
    ('approved', 'active'),
    ('active', 'decommissioned')
  );
  if not v_valid_transition then
    raise exception 'region_invalid_transition: % -> % is not a valid region assignment transition', v_record.status, p_new_status
      using errcode = 'check_violation';
  end if;

  if p_new_status = 'rejected' and coalesce(trim(p_rejection_reason), '') = '' then
    raise exception 'region_rejection_reason_required: a real rejection reason must be stated' using errcode = 'check_violation';
  end if;

  update app.tenant_region_assignments
  set status = p_new_status,
      rejected_at = case when p_new_status = 'rejected' then now() else rejected_at end,
      rejection_reason = case when p_new_status = 'rejected' then p_rejection_reason else rejection_reason end,
      activated_at = case when p_new_status = 'active' then now() else activated_at end,
      decommissioned_at = case when p_new_status = 'decommissioned' then now() else decommissioned_at end
  where id = p_region_assignment_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_region_assignment_status',
    'app.tenant_region_assignments', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$function$;

CREATE OR REPLACE FUNCTION app.set_scaling_recommendation_status(p_recommendation_id uuid, p_new_status text, p_dismissed_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.scaling_recommendations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_record app.scaling_recommendations;
  v_decision app.rbac_decision;
  v_valid_transition boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.scaling_recommendations where id = p_recommendation_id for update;
  if not found or not app.has_active_tenant_membership(v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'scaling_recommendation_not_found: %', p_recommendation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'MON', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks MON:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_valid_transition := (v_record.status, p_new_status) in (
    ('open', 'acknowledged'),
    ('open', 'dismissed'),
    ('acknowledged', 'dismissed'),
    ('acknowledged', 'implemented')
  );
  if not v_valid_transition then
    raise exception 'scaling_recommendation_invalid_transition: % -> % is not a valid transition', v_record.status, p_new_status
      using errcode = 'check_violation';
  end if;

  if p_new_status = 'dismissed' and coalesce(trim(p_dismissed_reason), '') = '' then
    raise exception 'scaling_recommendation_dismissed_reason_required: a real dismissal reason must be stated' using errcode = 'check_violation';
  end if;

  update app.scaling_recommendations
  set status = p_new_status,
      acknowledged_by_auth_user_id = case when p_new_status = 'acknowledged' then p_actor_auth_user_id else acknowledged_by_auth_user_id end,
      acknowledged_by = case when p_new_status = 'acknowledged' then p_actor_label else acknowledged_by end,
      acknowledged_at = case when p_new_status = 'acknowledged' then now() else acknowledged_at end,
      dismissed_reason = case when p_new_status = 'dismissed' then p_dismissed_reason else dismissed_reason end
  where id = p_recommendation_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_scaling_recommendation_status',
    'app.scaling_recommendations', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$function$;

