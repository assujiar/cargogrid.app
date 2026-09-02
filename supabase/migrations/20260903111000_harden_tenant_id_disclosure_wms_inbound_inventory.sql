-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 2 of 3 -- WMS master data and inbound flow: warehouses & zones, bin/racking locations,
-- item/UOM master, inbound orders, the inventory ledger, receiving, putaway, and
-- lot/batch/serial/expiry control.
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
--   (A) 32 functions -- the canonical shape: the disclosing SELECT is already
--       followed by its own `if not found then raise ... no_data_found; end if;`, so the
--       membership check is folded straight into that existing branch.
--   (B) 1 function -- a two-step lookup: an already-guarded child row is fetched by
--       bare id, then its parent (the row whose tenant_id is disclosed) is fetched by that
--       child's FK with no not-found branch of its own, because the FK guarantees the parent
--       exists. For these a NEW guard is added immediately after that parent SELECT, reusing
--       VERBATIM the message and errcode of the child's own not-found raise one statement
--       above it, so both failure paths stay byte-identical from the caller's point of view.
--
-- Every function below is CREATE OR REPLACE against its CURRENT, live body, read via
-- pg_get_functiondef from a disposable database built by applying all 479 committed
-- migrations in order -- not reconstructed by hand from a possibly-superseded migration
-- file. Signatures, volatility, SECURITY DEFINER, search_path and grants are unchanged
-- throughout, so no grant or wrapper is affected.
--
-- Scope of this part: 33 functions (33 raise sites).

CREATE OR REPLACE FUNCTION app.add_wms_inbound_order_line(p_inbound_order_id uuid, p_item_master_id uuid, p_expected_uom_code text, p_expected_quantity numeric, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_order_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_item app.item_masters;
  v_next_line integer;
  v_line app.wms_inbound_order_lines;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  if v_order.status <> 'draft' then
    raise exception 'inbound_not_draft: % is not draft -- lines may only be added while draft', p_inbound_order_id using errcode = 'check_violation';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;

  if p_expected_quantity is null or p_expected_quantity <= 0 then
    raise exception 'invalid_quantity: expected_quantity must be greater than zero' using errcode = 'check_violation';
  end if;
  if not app.validate_uom_code(p_expected_uom_code) then
    raise exception 'invalid_uom: % is not a registered active UOM code', p_expected_uom_code using errcode = 'check_violation';
  end if;

  select * into v_item from app.item_masters
    where id = p_item_master_id and tenant_id = v_order.tenant_id and owner_account_id = v_order.owner_account_id and status = 'active';
  if not found then
    raise exception 'item_not_eligible: % is not an active item master owned by the inbound order''s own account', p_item_master_id using errcode = 'check_violation';
  end if;

  select coalesce(max(line_number), 0) + 1 into v_next_line from app.wms_inbound_order_lines where inbound_order_id = p_inbound_order_id;

  insert into app.wms_inbound_order_lines (
    tenant_id, inbound_order_id, line_number, item_master_id, expected_uom_code, expected_quantity,
    lot_controlled, serial_controlled, expiry_controlled, notes
  ) values (
    v_order.tenant_id, p_inbound_order_id, v_next_line, p_item_master_id, p_expected_uom_code, p_expected_quantity,
    v_item.lot_controlled, v_item.serial_controlled, v_item.expiry_controlled, p_notes
  )
  returning * into v_line;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_wms_inbound_order_line',
    'app.wms_inbound_order_lines', v_line.id, 'success', null, null,
    jsonb_build_object('inbound_order_id', p_inbound_order_id, 'item_master_id', p_item_master_id, 'expected_quantity', p_expected_quantity)
  );

  return v_line;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.approve_wms_receipt_overage(p_line_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_receipt_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
begin
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found or not app.has_active_tenant_membership(v_line.tenant_id, p_actor_auth_user_id) then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot approve overage on receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: receipt line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version using errcode = 'check_violation';
  end if;
  if v_line.status = 'committed' then
    raise exception 'line_already_committed: % has already been committed to inventory', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.over_quantity <= 0 then
    raise exception 'no_overage_to_approve: receipt line % has no overage (over_quantity=%)', p_line_id, v_line.over_quantity using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to approve an overage' using errcode = 'check_violation';
  end if;

  update app.wms_receipt_lines set
    over_approved = true, over_approved_reason = p_reason, over_approved_by = p_actor_label, over_approved_at = now()
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_wms_receipt_overage',
    'app.wms_receipt_lines', v_line.id, 'success', p_reason, null, jsonb_build_object('over_quantity', v_line.over_quantity)
  );

  return v_line;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_wms_putaway_task(p_task_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_putaway_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority/tenant-scope is confirmed above, never
  -- before (design note (a)).
  if v_task.status = 'cancelled' then
    return v_task;
  end if;

  if v_task.confirmed_quantity > 0 then
    raise exception 'has_confirmed_quantity: task % has already confirmed % unit(s) -- a task with real posted movements may never be cancelled, only completed or reassigned', p_task_id, v_task.confirmed_quantity
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a putaway task' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  update app.wms_putaway_tasks set status = 'cancelled' where id = p_task_id returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', p_reason, null, null
  );

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_wms_receipt_session(p_session_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_receipt_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_committed_count integer;
begin
  select * into v_session from app.wms_receipt_sessions where id = p_session_id for update;
  if not found or not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_session.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit receipt session %', p_actor_auth_user_id, p_session_id using errcode = 'insufficient_privilege';
  end if;

  if v_session.record_version <> p_expected_version then
    raise exception 'stale_version: receipt session % expected version % but found %', p_session_id, p_expected_version, v_session.record_version using errcode = 'check_violation';
  end if;
  if v_session.status = 'cancelled' then
    return v_session;
  end if;
  if v_session.status = 'completed' then
    raise exception 'session_not_in_progress: % is completed -- a completed receipt session may never be cancelled, only reversed through governed inventory movements', p_session_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a receipt session' using errcode = 'check_violation';
  end if;

  select count(*) into v_committed_count from app.wms_receipt_lines where receipt_session_id = p_session_id and status = 'committed';
  if v_committed_count > 0 then
    raise exception 'has_committed_lines: session % has % already-committed line(s) -- complete the session instead of cancelling once inventory has been posted', p_session_id, v_committed_count
      using errcode = 'check_violation';
  end if;

  update app.wms_receipt_sessions set status = 'cancelled', cancelled_reason = p_reason where id = p_session_id returning * into v_session;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_receipt_session',
    'app.wms_receipt_sessions', v_session.id, 'success', p_reason, null, null
  );

  return v_session;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.claim_wms_putaway_task(p_task_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_putaway_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE (FOR UPDATE) -- a second
  -- concurrent claim attempt on the same unclaimed task blocks here until the first
  -- transaction commits, then observes status='claimed' with a different claimant and
  -- is correctly rejected (the real concurrent-claim-race guard Prompt 233 section 23
  -- names: "two staff cannot both claim the same task").
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot claim putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is confirmed
  -- above, never before (design note (a)). A same-claimant re-claim is a harmless
  -- no-op; a different claimant hits the real race guard below.
  if v_task.status = 'claimed' and v_task.claimed_by_auth_user_id = p_actor_auth_user_id then
    return v_task;
  end if;

  if v_task.status <> 'unclaimed' then
    raise exception 'task_already_claimed: task % is % (claimed_by=%) -- only an unclaimed task may be claimed', p_task_id, v_task.status, v_task.claimed_by_label
      using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  update app.wms_putaway_tasks set
    status = 'claimed', claimed_by_auth_user_id = p_actor_auth_user_id, claimed_by_label = p_actor_label, claimed_at = now()
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'claim_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', null, null, jsonb_build_object('claimed_by', p_actor_label)
  );

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.complete_wms_receipt_session(p_session_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_receipt_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_uncommitted_count integer;
begin
  select * into v_session from app.wms_receipt_sessions where id = p_session_id for update;
  if not found or not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_session.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit receipt session %', p_actor_auth_user_id, p_session_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is
  -- confirmed above, never before (an already-completed session must never be
  -- readable by a caller who could not otherwise access it).
  if v_session.status = 'completed' then
    return v_session;
  end if;

  if v_session.record_version <> p_expected_version then
    raise exception 'stale_version: receipt session % expected version % but found %', p_session_id, p_expected_version, v_session.record_version using errcode = 'check_violation';
  end if;
  if v_session.status <> 'in_progress' then
    raise exception 'session_not_in_progress: % is % -- only an in_progress session may be completed', p_session_id, v_session.status using errcode = 'check_violation';
  end if;

  select count(*) into v_uncommitted_count from app.wms_receipt_lines where receipt_session_id = p_session_id and status <> 'committed';
  if v_uncommitted_count > 0 then
    raise exception 'lines_not_committed: % line(s) on session % are not yet committed', v_uncommitted_count, p_session_id using errcode = 'check_violation';
  end if;

  update app.wms_receipt_sessions set status = 'completed', completed_at = now() where id = p_session_id returning * into v_session;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_wms_receipt_session',
    'app.wms_receipt_sessions', v_session.id, 'success', null, null, null
  );

  return v_session;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.create_item_control_policy_version_draft(p_item_master_id uuid, p_allocation_rule text, p_hold_on_unknown_lot boolean, p_near_expiry_warning_days integer, p_effective_from timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.item_control_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
  v_rule text;
  v_policy app.item_control_policy_versions;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_rule := coalesce(p_allocation_rule, 'fifo');
  if v_rule not in ('fifo', 'fefo') then
    raise exception 'invalid_allocation_rule: % is not a recognized allocation rule', v_rule using errcode = 'check_violation';
  end if;
  if v_rule = 'fefo' and not v_item.expiry_controlled then
    raise exception 'invalid_allocation_rule: fefo requires item % to be expiry-controlled', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_near_expiry_warning_days is not null and not v_item.expiry_controlled then
    raise exception 'invalid_near_expiry_warning_days: item % is not expiry-controlled -- near_expiry_warning_days is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_near_expiry_warning_days is not null and p_near_expiry_warning_days < 0 then
    raise exception 'invalid_near_expiry_warning_days: % must be non-negative', p_near_expiry_warning_days using errcode = 'check_violation';
  end if;

  insert into app.item_control_policy_versions (
    tenant_id, item_master_id, owner_account_id, allocation_rule, hold_on_unknown_lot, near_expiry_warning_days, effective_from, created_by
  ) values (
    v_item.tenant_id, p_item_master_id, v_item.owner_account_id, v_rule, coalesce(p_hold_on_unknown_lot, true), p_near_expiry_warning_days, coalesce(p_effective_from, now()), p_actor_label
  )
  returning * into v_policy;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_item_control_policy_version_draft',
    'app.item_control_policy_versions', v_policy.id, 'success', null, null,
    jsonb_build_object('item_master_id', p_item_master_id, 'allocation_rule', v_rule, 'hold_on_unknown_lot', v_policy.hold_on_unknown_lot)
  );

  return v_policy;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.create_warehouse_location(p_warehouse_id uuid, p_zone_id uuid, p_parent_id uuid, p_code text, p_name text, p_location_type text, p_sequence integer, p_capacity_value numeric, p_capacity_uom text, p_environment jsonb, p_restrictions jsonb, p_barcode text, p_pick_enabled boolean, p_putaway_enabled boolean, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_zone app.warehouse_zones;
  v_existing app.warehouse_locations;
  v_location app.warehouse_locations;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_location_type not in ('rack', 'shelf', 'floor', 'staging', 'dock', 'bin') then
    raise exception 'invalid_location_type: % is not a valid location type', p_location_type using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found or not app.has_active_tenant_membership(v_warehouse.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;
  if v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active -- cannot add a location to it', p_warehouse_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create a location under warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if p_zone_id is not null then
    select * into v_zone from app.warehouse_zones where id = p_zone_id;
    if not found or v_zone.warehouse_id <> p_warehouse_id then
      raise exception 'incompatible_zone: zone % does not belong to warehouse %', p_zone_id, p_warehouse_id using errcode = 'check_violation';
    end if;
    if v_zone.status <> 'active' then
      raise exception 'incompatible_zone: zone % is not active', p_zone_id using errcode = 'check_violation';
    end if;
  end if;

  if p_capacity_value is not null and p_capacity_value < 0 then
    raise exception 'invalid_capacity: capacity_value must not be negative' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.warehouse_locations where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and code = p_code;
  if found then
    if v_existing.location_type <> p_location_type or v_existing.parent_id is distinct from p_parent_id then
      raise exception 'location_code_conflict: code % already exists for warehouse % with a different type/parent', p_code, p_warehouse_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.warehouse_locations (
      tenant_id, warehouse_id, zone_id, parent_id, code, name, location_type, sequence,
      capacity_value, capacity_uom, environment, restrictions, barcode, pick_enabled, putaway_enabled, created_by
    ) values (
      v_warehouse.tenant_id, p_warehouse_id, p_zone_id, p_parent_id, p_code, p_name, p_location_type, coalesce(p_sequence, 0),
      p_capacity_value, p_capacity_uom, coalesce(p_environment, '{}'::jsonb), coalesce(p_restrictions, '{}'::jsonb),
      p_barcode, coalesce(p_pick_enabled, false), coalesce(p_putaway_enabled, false), p_actor_label
    )
    returning * into v_location;
  exception
    when unique_violation then
      if p_barcode is not null and exists (select 1 from app.warehouse_locations where tenant_id = v_warehouse.tenant_id and barcode = p_barcode) then
        raise exception 'duplicate_barcode: barcode % is already assigned within this tenant', p_barcode using errcode = 'unique_violation';
      end if;
      select * into v_location from app.warehouse_locations where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and code = p_code;
      if found then
        return v_location;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_warehouse_location',
    'app.warehouse_locations', v_location.id, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'zone_id', p_zone_id, 'parent_id', p_parent_id, 'code', p_code, 'location_type', p_location_type)
  );

  return v_location;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.create_warehouse_zone(p_warehouse_id uuid, p_code text, p_name text, p_zone_type text, p_environment jsonb, p_capacity_value numeric, p_capacity_uom text, p_restrictions jsonb, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_zones
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_existing app.warehouse_zones;
  v_zone app.warehouse_zones;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_zone_type is null or length(trim(p_zone_type)) = 0 then
    raise exception 'invalid_zone_type: zone_type is required' using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found or not app.has_active_tenant_membership(v_warehouse.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;
  if v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active -- cannot add a zone to it', p_warehouse_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create a zone under warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if p_effective_from is not null and p_effective_to is not null and p_effective_to <= p_effective_from then
    raise exception 'invalid_effective_window: effective_to must be after effective_from' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.warehouse_zones where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and code = p_code;
  if found then
    if v_existing.zone_type <> p_zone_type then
      raise exception 'zone_code_conflict: code % already exists for warehouse % with a different zone type', p_code, p_warehouse_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.warehouse_zones (
      tenant_id, warehouse_id, code, name, zone_type, environment, capacity_value, capacity_uom, restrictions, effective_from, effective_to, created_by
    ) values (
      v_warehouse.tenant_id, p_warehouse_id, p_code, p_name, p_zone_type, coalesce(p_environment, '{}'::jsonb), p_capacity_value, p_capacity_uom, coalesce(p_restrictions, '{}'::jsonb), p_effective_from, p_effective_to, p_actor_label
    )
    returning * into v_zone;
  exception
    when unique_violation then
      select * into v_zone from app.warehouse_zones where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and code = p_code;
      if found then
        return v_zone;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_warehouse_zone',
    'app.warehouse_zones', v_zone.id, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'code', p_code, 'zone_type', p_zone_type)
  );

  return v_zone;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_item_control_policy(p_item_master_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.item_control_policy_versions
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
  v_policy app.item_control_policy_versions;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_policy from app.item_control_policy_versions where item_master_id = p_item_master_id and status = 'published' and effective_from <= now();
  if not found then
    raise exception 'policy_version_not_found: item % has no published control policy currently in effect', p_item_master_id using errcode = 'no_data_found';
  end if;

  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_policy.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view item %''s control policy', p_actor_auth_user_id, p_item_master_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_policy;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_item_master(p_item_master_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.item_masters
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_item;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_lot_identity(p_lot_identity_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.lot_identities
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_lot app.lot_identities;
begin
  select * into v_lot from app.lot_identities where id = p_lot_identity_id;
  if not found or not app.has_active_tenant_membership(v_lot.tenant_id, p_actor_auth_user_id) then
    raise exception 'lot_identity_not_found: %', p_lot_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lot.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lot.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_lot.tenant_id, v_lot.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view lot identity %', p_actor_auth_user_id, p_lot_identity_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_lot;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_lot_trace(p_lot_identity_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 RETURNS TABLE(movement_id uuid, movement_type text, source_type text, source_id uuid, occurred_at timestamp with time zone, warehouse_id uuid, location_id uuid, signed_quantity numeric, line_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lot app.lot_identities;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_lot from app.lot_identities where id = p_lot_identity_id;
  if not found or not app.has_active_tenant_membership(v_lot.tenant_id, p_actor_auth_user_id) then
    raise exception 'lot_identity_not_found: %', p_lot_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lot.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lot.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select ml.movement_id, m.movement_type, m.source_type, m.source_id, m.occurred_at, ml.warehouse_id, ml.location_id, ml.signed_quantity, ml.status
  from app.inventory_movement_lines ml
  join app.inventory_movements m on m.id = ml.movement_id
  join app.warehouses w on w.id = ml.warehouse_id
  where ml.tenant_id = v_lot.tenant_id
    and ml.owner_account_id = v_lot.owner_account_id
    and ml.item_master_id = v_lot.item_master_id
    and ml.lot_number = v_lot.lot_number
    and app.can_access_record(p_actor_auth_user_id, v_lot.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), v_lot.owner_account_id::text)
  order by m.occurred_at asc
  limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_serial_identity(p_serial_identity_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.serial_identities
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_serial app.serial_identities;
begin
  select * into v_serial from app.serial_identities where id = p_serial_identity_id;
  if not found or not app.has_active_tenant_membership(v_serial.tenant_id, p_actor_auth_user_id) then
    raise exception 'serial_identity_not_found: %', p_serial_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_serial.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_serial.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_serial.tenant_id, v_serial.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view serial identity %', p_actor_auth_user_id, p_serial_identity_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_serial;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_serial_trace(p_serial_identity_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 RETURNS TABLE(movement_id uuid, movement_type text, source_type text, source_id uuid, occurred_at timestamp with time zone, warehouse_id uuid, location_id uuid, signed_quantity numeric, line_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_serial app.serial_identities;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_serial from app.serial_identities where id = p_serial_identity_id;
  if not found or not app.has_active_tenant_membership(v_serial.tenant_id, p_actor_auth_user_id) then
    raise exception 'serial_identity_not_found: %', p_serial_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_serial.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_serial.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select ml.movement_id, m.movement_type, m.source_type, m.source_id, m.occurred_at, ml.warehouse_id, ml.location_id, ml.signed_quantity, ml.status
  from app.inventory_movement_lines ml
  join app.inventory_movements m on m.id = ml.movement_id
  join app.warehouses w on w.id = ml.warehouse_id
  where ml.tenant_id = v_serial.tenant_id
    and ml.owner_account_id = v_serial.owner_account_id
    and ml.item_master_id = v_serial.item_master_id
    and ml.serial_number = v_serial.serial_number
    and app.can_access_record(p_actor_auth_user_id, v_serial.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), v_serial.owner_account_id::text)
  order by m.occurred_at asc
  limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_warehouse_deactivation_impact(p_warehouse_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.warehouse_deactivation_impact
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_result app.warehouse_deactivation_impact;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found or not app.has_active_tenant_membership(v_warehouse.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select count(*) filter (where status = 'active'), count(*) filter (where status = 'on_hold')
    into v_result.active_zone_count, v_result.on_hold_zone_count
    from app.warehouse_zones where warehouse_id = p_warehouse_id;
  select count(*) into v_result.active_customer_eligibility_count
    from app.warehouse_customer_eligibility where warehouse_id = p_warehouse_id and status = 'active';

  return v_result;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_warehouse_location_deactivation_impact(p_location_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.warehouse_location_deactivation_impact
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
  v_result app.warehouse_location_deactivation_impact;
begin
  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found or not app.has_active_tenant_membership(v_location.tenant_id, p_actor_auth_user_id) then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  select count(*) filter (where status = 'active'), count(*) filter (where status = 'draft')
    into v_result.active_child_count, v_result.draft_child_count
    from app.warehouse_locations where parent_id = p_location_id;

  return v_result;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_inbound_readiness(p_inbound_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_inbound_readiness
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_account app.accounts;
  v_result app.wms_inbound_readiness;
  v_line_count integer;
  v_invalid_line_count integer;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_line_count from app.wms_inbound_order_lines where inbound_order_id = p_inbound_order_id;
  select count(*) into v_invalid_line_count
    from app.wms_inbound_order_lines l
    join app.item_masters m on m.id = l.item_master_id
    where l.inbound_order_id = p_inbound_order_id and m.status <> 'active';
  select * into v_account from app.accounts where id = v_order.owner_account_id;

  v_result.has_lines := v_line_count > 0;
  v_result.warehouse_active := v_warehouse.status = 'active';
  v_result.owner_active := v_account.status = 'active';
  v_result.invalid_line_count := v_invalid_line_count;
  v_result.ready := v_result.has_lines and v_result.warehouse_active and v_result.owner_active and v_invalid_line_count = 0;

  return v_result;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_putaway_task(p_task_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_putaway_tasks
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_putaway_tasks where id = p_task_id;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_receipt_session(p_session_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_receipt_sessions
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
begin
  select * into v_session from app.wms_receipt_sessions where id = p_session_id;
  if not found or not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_session.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view receipt session %', p_actor_auth_user_id, p_session_id using errcode = 'insufficient_privilege';
  end if;

  return v_session;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.grant_warehouse_customer_eligibility(p_warehouse_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_customer_eligibility
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_account app.accounts;
  v_existing app.warehouse_customer_eligibility;
  v_row app.warehouse_customer_eligibility;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found or not app.has_active_tenant_membership(v_warehouse.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.accounts where id = p_customer_account_id and tenant_id = v_warehouse.tenant_id;
  if not found then
    raise exception 'account_not_found: % is not an account of tenant %', p_customer_account_id, v_warehouse.tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.warehouse_customer_eligibility
    where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and customer_account_id = p_customer_account_id;
  if found then
    if v_existing.status = 'active' then
      return v_existing;
    end if;
    update app.warehouse_customer_eligibility
      set status = 'active', granted_by = p_actor_label, granted_at = now(), revoked_at = null, revoked_reason = null
      where id = v_existing.id
      returning * into v_row;
  else
    begin
      insert into app.warehouse_customer_eligibility (tenant_id, warehouse_id, customer_account_id, granted_by)
      values (v_warehouse.tenant_id, p_warehouse_id, p_customer_account_id, p_actor_label)
      returning * into v_row;
    exception
      when unique_violation then
        select * into v_row from app.warehouse_customer_eligibility
          where tenant_id = v_warehouse.tenant_id and warehouse_id = p_warehouse_id and customer_account_id = p_customer_account_id;
        if not found then
          raise;
        end if;
    end;
  end if;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'grant_warehouse_customer_eligibility',
    'app.warehouse_customer_eligibility', v_row.id, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'customer_account_id', p_customer_account_id)
  );

  return v_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_inventory_movement_lines(p_movement_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.inventory_movement_lines
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_movement app.inventory_movements;
  v_warehouse app.warehouses;
  v_decision app.rbac_decision;
begin
  select * into v_movement from app.inventory_movements where id = p_movement_id;
  if not found or not app.has_active_tenant_membership(v_movement.tenant_id, p_actor_auth_user_id) then
    raise exception 'movement_not_found: %', p_movement_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_movement.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_movement.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_movement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_movement.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view movement %', p_actor_auth_user_id, p_movement_id using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.inventory_movement_lines where movement_id = p_movement_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_warehouse_customer_eligibility(p_warehouse_id uuid, p_actor_auth_user_id uuid)
 RETURNS TABLE(id uuid, warehouse_id uuid, customer_account_id uuid, customer_legal_name text, status text, granted_by text, granted_at timestamp with time zone, revoked_at timestamp with time zone, revoked_reason text, record_version integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
begin
  -- Table-qualified (not a bare "where id = ...") -- this function's own RETURNS
  -- TABLE column named "id" would otherwise make a bare "id" reference ambiguous
  -- with app.warehouses.id inside this plpgsql body.
  select w.* into v_warehouse from app.warehouses w where w.id = p_warehouse_id;
  if not found or not app.has_active_tenant_membership(v_warehouse.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  return query
  select e.id, e.warehouse_id, e.customer_account_id, a.legal_name, e.status, e.granted_by, e.granted_at, e.revoked_at, e.revoked_reason, e.record_version
  from app.warehouse_customer_eligibility e
  join app.accounts a on a.id = e.customer_account_id
  where e.warehouse_id = p_warehouse_id
  order by a.legal_name;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_warehouse_locations(p_warehouse_id uuid, p_actor_auth_user_id uuid, p_parent_id uuid DEFAULT NULL::uuid, p_status_filter text DEFAULT NULL::text)
 RETURNS SETOF app.warehouse_locations
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found or not app.has_active_tenant_membership(v_warehouse.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.warehouse_locations l
  where l.warehouse_id = p_warehouse_id
    and l.parent_id is not distinct from p_parent_id
    and (p_status_filter is null or l.status = p_status_filter)
  order by l.sequence, l.code;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_warehouse_zones(p_warehouse_id uuid, p_actor_auth_user_id uuid, p_status_filter text DEFAULT NULL::text)
 RETURNS SETOF app.warehouse_zones
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found or not app.has_active_tenant_membership(v_warehouse.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.warehouse_zones z
  where z.warehouse_id = p_warehouse_id and (p_status_filter is null or z.status = p_status_filter)
  order by z.code;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.mark_wms_putaway_task_exception(p_task_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_putaway_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_override app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority/tenant-scope is confirmed above, never
  -- before (design note (a)).
  if v_task.status = 'exception' then
    return v_task;
  end if;

  if v_task.status not in ('claimed', 'partial') then
    raise exception 'invalid_transition: task % is % -- only a claimed or partially-confirmed task may be marked exception', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to mark a putaway task exception' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  -- Only the task's own claimant, or a supervisor holding OPS:Override, may record a
  -- blocker on it (design note 7).
  if v_task.claimed_by_auth_user_id <> p_actor_auth_user_id then
    v_override := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Override');
    if not v_override.allowed then
      raise exception 'insufficient_authority: identity % is neither the claimant of task % nor holds OPS:Override', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
    end if;
  end if;

  update app.wms_putaway_tasks set status = 'exception', exception_reason = p_reason where id = p_task_id returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'mark_wms_putaway_task_exception',
    'app.wms_putaway_tasks', v_task.id, 'success', p_reason, null, null
  );

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reassign_wms_putaway_task(p_task_id uuid, p_new_claimant_auth_user_id uuid, p_new_claimant_label text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_putaway_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
  v_new_status text;
begin
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot override putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  if v_task.status in ('confirmed', 'cancelled') then
    raise exception 'invalid_transition: task % is % -- a confirmed or cancelled task may not be reassigned', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reassign or release a putaway task' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  if p_new_claimant_auth_user_id is null then
    v_new_status := 'unclaimed';
  elsif v_task.confirmed_quantity > 0 then
    v_new_status := 'partial';
  else
    v_new_status := 'claimed';
  end if;

  update app.wms_putaway_tasks set
    status = v_new_status,
    claimed_by_auth_user_id = p_new_claimant_auth_user_id,
    claimed_by_label = p_new_claimant_label,
    claimed_at = (case when p_new_claimant_auth_user_id is null then null else now() end),
    exception_reason = (case when v_new_status = 'unclaimed' then null else exception_reason end)
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', p_reason, null,
    jsonb_build_object('new_claimant', p_new_claimant_label, 'new_status', v_new_status)
  );

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_wms_receipt_line_count(p_line_id uuid, p_uom_code text, p_counted_quantity numeric, p_accepted_quantity numeric, p_damaged_quantity numeric, p_held_quantity numeric, p_rejected_quantity numeric, p_lot_number text, p_serial_number text, p_expiry_date date, p_condition_notes text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_receipt_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_uom_code text;
  v_counted numeric;
  v_accepted numeric;
  v_damaged numeric;
  v_held numeric;
  v_rejected numeric;
begin
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found or not app.has_active_tenant_membership(v_line.tenant_id, p_actor_auth_user_id) then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  if v_session.status <> 'in_progress' then
    raise exception 'session_not_in_progress: session % is % -- counts may only be recorded while in_progress', v_session.id, v_session.status using errcode = 'check_violation';
  end if;
  if v_line.status = 'committed' then
    raise exception 'line_already_committed: % has already been committed to inventory', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: receipt line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version using errcode = 'check_violation';
  end if;

  if p_counted_quantity is null or p_counted_quantity < 0
     or p_accepted_quantity is null or p_accepted_quantity < 0
     or p_damaged_quantity is null or p_damaged_quantity < 0
     or p_held_quantity is null or p_held_quantity < 0
     or p_rejected_quantity is null or p_rejected_quantity < 0 then
    raise exception 'invalid_quantity: counted/accepted/damaged/held/rejected quantities must all be non-negative' using errcode = 'check_violation';
  end if;

  v_uom_code := coalesce(p_uom_code, v_line.expected_uom_code);
  if not app.validate_uom_code(v_uom_code) then
    raise exception 'invalid_uom: % is not a registered active UOM code', v_uom_code using errcode = 'check_violation';
  end if;

  if v_uom_code = v_line.expected_uom_code then
    v_counted := p_counted_quantity;
    v_accepted := p_accepted_quantity;
    v_damaged := p_damaged_quantity;
    v_held := p_held_quantity;
    v_rejected := p_rejected_quantity;
  else
    v_counted := app.convert_uom_quantity(p_counted_quantity, v_uom_code, v_line.expected_uom_code);
    v_accepted := app.convert_uom_quantity(p_accepted_quantity, v_uom_code, v_line.expected_uom_code);
    v_damaged := app.convert_uom_quantity(p_damaged_quantity, v_uom_code, v_line.expected_uom_code);
    v_held := app.convert_uom_quantity(p_held_quantity, v_uom_code, v_line.expected_uom_code);
    v_rejected := app.convert_uom_quantity(p_rejected_quantity, v_uom_code, v_line.expected_uom_code);
  end if;

  if v_accepted + v_damaged + v_held + v_rejected <> v_counted then
    raise exception 'invalid_equation: accepted (%) + damaged (%) + held (%) + rejected (%) must equal counted (%)', v_accepted, v_damaged, v_held, v_rejected, v_counted
      using errcode = 'check_violation';
  end if;

  if v_line.lot_controlled and v_counted > 0 and (p_lot_number is null or length(trim(p_lot_number)) = 0) then
    raise exception 'missing_lot: item % is lot-controlled -- a lot number is required for a non-zero count', v_line.item_master_id using errcode = 'check_violation';
  end if;
  if v_line.expiry_controlled and v_counted > 0 and p_expiry_date is null then
    raise exception 'missing_expiry: item % is expiry-controlled -- an expiry date is required for a non-zero count', v_line.item_master_id using errcode = 'check_violation';
  end if;
  if v_line.serial_controlled and v_counted > 0 then
    if p_serial_number is null or length(trim(p_serial_number)) = 0 then
      raise exception 'missing_serial: item % is serial-controlled -- a serial number is required for a non-zero count', v_line.item_master_id using errcode = 'check_violation';
    end if;
    if v_counted > 1 then
      raise exception 'serial_quantity_exceeded: a single receipt line may record at most 1 unit of a serial-controlled item, got %', v_counted using errcode = 'check_violation';
    end if;
  end if;

  update app.wms_receipt_lines set
    counted_uom_code = v_uom_code,
    counted_quantity = v_counted,
    accepted_quantity = v_accepted,
    damaged_quantity = v_damaged,
    held_quantity = v_held,
    rejected_quantity = v_rejected,
    lot_number = p_lot_number,
    serial_number = p_serial_number,
    expiry_date = p_expiry_date,
    condition_notes = p_condition_notes,
    status = 'counted',
    over_approved = false,
    over_approved_reason = null,
    over_approved_by = null,
    over_approved_at = null
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_receipt_line_count',
    'app.wms_receipt_lines', v_line.id, 'success', p_condition_notes, null,
    jsonb_build_object('counted_quantity', v_counted, 'accepted_quantity', v_accepted, 'damaged_quantity', v_damaged, 'held_quantity', v_held, 'rejected_quantity', v_rejected)
  );

  return v_line;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.register_lot_identity(p_item_master_id uuid, p_lot_number text, p_manufacture_date date, p_expiry_date date, p_source_type text, p_source_id uuid, p_parent_lot_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.lot_identities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
  v_existing app.lot_identities;
  v_parent app.lot_identities;
  v_policy app.item_control_policy_versions;
  v_hold_default boolean;
  v_status text;
  v_hold_reason text;
  v_lot app.lot_identities;
begin
  select * into v_item from app.item_masters where id = p_item_master_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay by natural key -- only after authority is confirmed above,
  -- never before.
  select * into v_existing from app.lot_identities
    where tenant_id = v_item.tenant_id and owner_account_id = v_item.owner_account_id and item_master_id = p_item_master_id and lot_number = p_lot_number;
  if found then
    return v_existing;
  end if;

  if not v_item.lot_controlled then
    raise exception 'item_not_lot_controlled: item % is not lot-controlled -- a lot identity is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_lot_number is null or length(trim(p_lot_number)) = 0 then
    raise exception 'invalid_lot_number: a lot number is required' using errcode = 'check_violation';
  end if;
  if coalesce(p_source_type, 'receipt') not in ('receipt', 'manual', 'split') then
    raise exception 'invalid_source_type: % is not a recognized lot source type', p_source_type using errcode = 'check_violation';
  end if;
  if p_manufacture_date is not null and p_expiry_date is not null and p_expiry_date < p_manufacture_date then
    raise exception 'invalid_date_order: expiry_date % precedes manufacture_date %', p_expiry_date, p_manufacture_date using errcode = 'check_violation';
  end if;
  if p_expiry_date is not null and not v_item.expiry_controlled then
    raise exception 'expiry_date_not_applicable: item % is not expiry-controlled -- an expiry date is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;

  if p_parent_lot_id is not null then
    if coalesce(p_source_type, 'receipt') <> 'split' then
      raise exception 'genealogy_mismatch: a parent_lot_id may only be set when source_type is split' using errcode = 'check_violation';
    end if;
    select * into v_parent from app.lot_identities where id = p_parent_lot_id;
    if not found then
      raise exception 'parent_lot_not_found: %', p_parent_lot_id using errcode = 'no_data_found';
    end if;
    if v_parent.tenant_id <> v_item.tenant_id or v_parent.owner_account_id <> v_item.owner_account_id or v_parent.item_master_id <> p_item_master_id then
      raise exception 'genealogy_mismatch: parent lot % does not share the same tenant/owner/item as the new lot', p_parent_lot_id using errcode = 'check_violation';
    end if;
  end if;

  select * into v_policy from app.item_control_policy_versions where item_master_id = p_item_master_id and status = 'published' and effective_from <= now();
  v_hold_default := coalesce(v_policy.hold_on_unknown_lot, true);
  if v_hold_default then
    v_status := 'held';
    v_hold_reason := 'hold_on_unknown_lot_policy_default';
  else
    v_status := 'active';
    v_hold_reason := null;
  end if;

  begin
    insert into app.lot_identities (
      tenant_id, owner_account_id, item_master_id, lot_number, manufacture_date, expiry_date, status, hold_reason,
      parent_lot_id, source_type, source_id, created_by
    ) values (
      v_item.tenant_id, v_item.owner_account_id, p_item_master_id, p_lot_number, p_manufacture_date, p_expiry_date, v_status, v_hold_reason,
      p_parent_lot_id, coalesce(p_source_type, 'receipt'), p_source_id, p_actor_label
    )
    returning * into v_lot;
  exception
    when unique_violation then
      select * into v_existing from app.lot_identities
        where tenant_id = v_item.tenant_id and owner_account_id = v_item.owner_account_id and item_master_id = p_item_master_id and lot_number = p_lot_number;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'register_lot_identity',
    'app.lot_identities', v_lot.id, 'success', null, null,
    jsonb_build_object('item_master_id', p_item_master_id, 'lot_number', p_lot_number, 'status', v_status)
  );

  return v_lot;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.remove_wms_inbound_order_line(p_line_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_inbound_order_lines;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_line from app.wms_inbound_order_lines where id = p_line_id;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_order from app.wms_inbound_orders where id = v_line.inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  if v_order.status <> 'draft' then
    raise exception 'inbound_not_draft: % is not draft -- lines may only change while draft', v_order.id using errcode = 'check_violation';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, v_order.id using errcode = 'insufficient_privilege';
  end if;
  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version
      using errcode = 'check_violation';
  end if;

  delete from app.wms_inbound_order_lines where id = p_line_id;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_wms_inbound_order_line',
    'app.wms_inbound_order_lines', p_line_id, 'success', null, null, null
  );

  return true;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.resolve_wms_receipt_hold(p_line_id uuid, p_resolution text, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_receipt_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_movement app.inventory_movements;
  v_target_status text;
begin
  -- Row-locked from this first read through commit/rollback (FOR UPDATE), the
  -- identical reasoning app.commit_wms_receipt_line''s own lock documents: a second
  -- concurrent call on the same line cannot read the pre-resolution state, build its
  -- own adjustment movement, and call app.post_inventory_movement a second time
  -- before the first call''s UPDATE has landed.
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found or not app.has_active_tenant_membership(v_line.tenant_id, p_actor_auth_user_id) then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot resolve a hold on receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is
  -- confirmed above, never before (an already-resolved hold's disposition must never
  -- be readable by a caller who could not otherwise access it).
  if v_line.hold_resolved then
    return v_line;
  end if;

  if v_line.status <> 'committed' then
    raise exception 'line_not_committed: % must be committed to inventory before its held quantity may be resolved', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.held_quantity <= 0 then
    raise exception 'no_held_quantity: receipt line % has no held quantity to resolve', p_line_id using errcode = 'check_violation';
  end if;
  if p_resolution not in ('release_to_stock', 'confirm_damaged') then
    raise exception 'invalid_resolution: % is not a recognized hold resolution', p_resolution using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to resolve a QC hold' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to resolve a QC hold' using errcode = 'check_violation';
  end if;

  v_target_status := case p_resolution when 'release_to_stock' then 'on_hand' else 'damaged' end;

  v_movement := app.post_inventory_movement(
    v_line.tenant_id, v_session.warehouse_id, 'adjustment', 'wms_inbound_order', v_session.inbound_order_id, p_idempotency_key, p_reason,
    jsonb_build_array(
      jsonb_build_object('owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
        'uom_code', v_line.expected_uom_code, 'signed_quantity', -v_line.held_quantity,
        'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'held'),
      jsonb_build_object('owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
        'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.held_quantity,
        'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', v_target_status)
    ),
    p_actor_auth_user_id, p_actor_label
  );

  update app.wms_receipt_lines set
    hold_resolved = true, hold_resolution = p_resolution, hold_resolved_reason = p_reason, hold_resolved_by = p_actor_label, hold_resolved_at = now(),
    resolution_movement_id = v_movement.id
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_wms_receipt_hold',
    'app.wms_receipt_lines', v_line.id, 'success', p_reason, null, jsonb_build_object('resolution', p_resolution, 'movement_id', v_movement.id)
  );

  return v_line;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.set_lot_identity_status(p_lot_identity_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.lot_identities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_lot app.lot_identities;
begin
  if p_new_status not in ('active', 'held', 'quarantined', 'expired', 'consumed') then
    raise exception 'invalid_status: % is not a recognized lot identity status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_lot from app.lot_identities where id = p_lot_identity_id for update;
  if not found or not app.has_active_tenant_membership(v_lot.tenant_id, p_actor_auth_user_id) then
    raise exception 'lot_identity_not_found: %', p_lot_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lot.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lot.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority is confirmed above, never before.
  if v_lot.status = p_new_status then
    return v_lot;
  end if;

  if v_lot.record_version <> p_expected_version then
    raise exception 'stale_version: lot identity % expected version % but found %', p_lot_identity_id, p_expected_version, v_lot.record_version using errcode = 'check_violation';
  end if;
  if v_lot.status = 'consumed' then
    raise exception 'invalid_transition: lot identity % is consumed -- a terminal status, no further transition is permitted', p_lot_identity_id using errcode = 'check_violation';
  end if;
  if p_new_status <> 'active' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required to set lot identity status to %', p_new_status using errcode = 'check_violation';
  end if;

  update app.lot_identities set
    status = p_new_status,
    hold_reason = (case when p_new_status = 'active' then null else p_reason end)
  where id = p_lot_identity_id
  returning * into v_lot;

  perform app.capture_audit_event(
    v_lot.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_lot_identity_status',
    'app.lot_identities', v_lot.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_lot;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.set_serial_identity_status(p_serial_identity_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.serial_identities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_serial app.serial_identities;
begin
  if p_new_status not in ('active', 'held', 'quarantined', 'expired', 'consumed') then
    raise exception 'invalid_status: % is not a recognized serial identity status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_serial from app.serial_identities where id = p_serial_identity_id for update;
  if not found or not app.has_active_tenant_membership(v_serial.tenant_id, p_actor_auth_user_id) then
    raise exception 'serial_identity_not_found: %', p_serial_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_serial.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_serial.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority is confirmed above, never before.
  if v_serial.status = p_new_status then
    return v_serial;
  end if;

  if v_serial.record_version <> p_expected_version then
    raise exception 'stale_version: serial identity % expected version % but found %', p_serial_identity_id, p_expected_version, v_serial.record_version using errcode = 'check_violation';
  end if;
  if v_serial.status = 'consumed' then
    raise exception 'invalid_transition: serial identity % is consumed -- a terminal status, no further transition is permitted', p_serial_identity_id using errcode = 'check_violation';
  end if;
  if p_new_status <> 'active' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required to set serial identity status to %', p_new_status using errcode = 'check_violation';
  end if;

  update app.serial_identities set
    status = p_new_status,
    hold_reason = (case when p_new_status = 'active' then null else p_reason end)
  where id = p_serial_identity_id
  returning * into v_serial;

  perform app.capture_audit_event(
    v_serial.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_serial_identity_status',
    'app.serial_identities', v_serial.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_serial;
end;
$function$
;
