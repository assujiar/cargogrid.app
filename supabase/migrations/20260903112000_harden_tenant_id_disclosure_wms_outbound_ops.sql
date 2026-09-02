-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 3 of 3 -- WMS outbound flow and warehouse operations: outbound orders, picking, packing,
-- outbound shipments, cycle counting & adjustments, label/barcode operations, warehouse
-- billing events, and claim/incident operations.
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
--   (A) 64 functions -- the canonical shape: the disclosing SELECT is already
--       followed by its own `if not found then raise ... no_data_found; end if;`, so the
--       membership check is folded straight into that existing branch.
--   (B) 2 functions -- a two-step lookup: an already-guarded child row is fetched by
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
-- Scope of this part: 66 functions (66 raise sites).

CREATE OR REPLACE FUNCTION app.add_claim_item(p_case_id uuid, p_item_type text, p_linked_inventory_movement_id uuid, p_linked_wms_outbound_shipment_id uuid, p_item_master_id uuid, p_declared_quantity numeric, p_uom_code text, p_declared_value numeric, p_currency text, p_description text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
  v_item app.claim_items;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if p_item_type not in ('inventory', 'package', 'cargo_general') then
    raise exception 'claim_invalid_item_type: % is not a supported item type', p_item_type using errcode = 'check_violation';
  end if;
  if p_declared_quantity is null or p_declared_quantity <= 0 then
    raise exception 'claim_invalid_declared_quantity: declared_quantity must be positive' using errcode = 'check_violation';
  end if;
  if not app.validate_uom_code(p_uom_code) then
    raise exception 'invalid_uom_code: % is not a registered UOM code', p_uom_code using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'claim_item_description_required: a non-empty description is required' using errcode = 'check_violation';
  end if;
  if (p_declared_value is null) <> (p_currency is null) then
    raise exception 'claim_value_currency_shape_invalid: declared_value and currency must both be set or both be null' using errcode = 'check_violation';
  end if;
  if p_declared_value is not null then
    if p_declared_value < 0 then
      raise exception 'claim_invalid_declared_value: declared_value must not be negative' using errcode = 'check_violation';
    end if;
    if not app.validate_currency_code(p_currency) then
      raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
    end if;
  end if;

  if p_linked_inventory_movement_id is not null and not exists (
    select 1 from app.inventory_movements where id = p_linked_inventory_movement_id and tenant_id = v_case.tenant_id
  ) then
    raise exception 'claim_evidence_not_found: inventory_movement % not found in tenant %', p_linked_inventory_movement_id, v_case.tenant_id using errcode = 'no_data_found';
  end if;
  if p_linked_wms_outbound_shipment_id is not null then
    if not exists (select 1 from app.wms_outbound_shipments where id = p_linked_wms_outbound_shipment_id and tenant_id = v_case.tenant_id) then
      raise exception 'claim_evidence_not_found: wms_outbound_shipment % not found in tenant %', p_linked_wms_outbound_shipment_id, v_case.tenant_id using errcode = 'no_data_found';
    end if;
    -- Same-tenant/cross-customer check (see migration header design note 3):
    -- owner_account_id must match this claim case's own shipment order's
    -- shipper_account_id.
    if (select owner_account_id from app.wms_outbound_shipments where id = p_linked_wms_outbound_shipment_id)
      <> (select shipper_account_id from app.shipment_orders where id = v_exception.shipment_order_id)
    then
      raise exception 'claim_evidence_scope_mismatch: wms_outbound_shipment % belongs to a different customer account than this claim case''s own shipment order', p_linked_wms_outbound_shipment_id
        using errcode = 'check_violation';
    end if;
  end if;
  if p_item_master_id is not null and not exists (
    select 1 from app.item_masters where id = p_item_master_id and tenant_id = v_case.tenant_id
  ) then
    raise exception 'claim_evidence_not_found: item_master % not found in tenant %', p_item_master_id, v_case.tenant_id using errcode = 'no_data_found';
  end if;

  insert into app.claim_items (
    tenant_id, claim_case_id, item_type, linked_inventory_movement_id, linked_wms_outbound_shipment_id, item_master_id,
    declared_quantity, uom_code, declared_value, currency, description, created_by
  ) values (
    v_case.tenant_id, p_case_id, p_item_type, p_linked_inventory_movement_id, p_linked_wms_outbound_shipment_id, p_item_master_id,
    p_declared_quantity, p_uom_code, p_declared_value, p_currency, p_description, p_actor_label
  )
  returning * into v_item;

  perform app.advance_claim_case_stage(p_case_id, 'evidence_gathering');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_claim_item',
    'app.claim_items', v_item.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'item_type', p_item_type, 'declared_quantity', p_declared_quantity)
  );

  return v_item;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.add_wms_outbound_order_line(p_outbound_order_id uuid, p_item_master_id uuid, p_requested_uom_code text, p_requested_quantity numeric, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_order_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_item app.item_masters;
  v_next_line integer;
  v_line app.wms_outbound_order_lines;
begin
  -- Design note 9(b): lock the header row for update BEFORE the status check and
  -- before computing the next line_number -- serializes concurrent add-line calls (and
  -- a concurrent confirm/cancel) against the SAME order, closing the cross-row
  -- aggregate race (ATW-016 lesson e) that an unlocked coalesce(max(line_number), 0) + 1
  -- read would otherwise be exposed to.
  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id for update;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'outbound_order_not_found: %', p_outbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit outbound order %', p_actor_auth_user_id, p_outbound_order_id using errcode = 'insufficient_privilege';
  end if;

  if v_order.status <> 'draft' then
    raise exception 'outbound_not_draft: % is not draft -- lines may only be added while draft', p_outbound_order_id using errcode = 'check_violation';
  end if;
  if p_requested_quantity is null or p_requested_quantity <= 0 then
    raise exception 'invalid_quantity: requested_quantity must be greater than zero' using errcode = 'check_violation';
  end if;
  if not app.validate_uom_code(p_requested_uom_code) then
    raise exception 'invalid_uom: % is not a registered active UOM code', p_requested_uom_code using errcode = 'check_violation';
  end if;

  select * into v_item from app.item_masters
    where id = p_item_master_id and tenant_id = v_order.tenant_id and owner_account_id = v_order.owner_account_id and status = 'active';
  if not found then
    raise exception 'item_not_eligible: % is not an active item master owned by the outbound order''s own account', p_item_master_id using errcode = 'check_violation';
  end if;

  select coalesce(max(line_number), 0) + 1 into v_next_line from app.wms_outbound_order_lines where outbound_order_id = p_outbound_order_id;

  insert into app.wms_outbound_order_lines (
    tenant_id, outbound_order_id, line_number, item_master_id, requested_uom_code, requested_quantity,
    lot_controlled, serial_controlled, expiry_controlled, notes
  ) values (
    v_order.tenant_id, p_outbound_order_id, v_next_line, p_item_master_id, p_requested_uom_code, p_requested_quantity,
    v_item.lot_controlled, v_item.serial_controlled, v_item.expiry_controlled, p_notes
  )
  returning * into v_line;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_wms_outbound_order_line',
    'app.wms_outbound_order_lines', v_line.id, 'success', null, null,
    jsonb_build_object('outbound_order_id', p_outbound_order_id, 'item_master_id', p_item_master_id, 'requested_quantity', p_requested_quantity)
  );

  return v_line;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.assign_cycle_count_scope_item(p_scope_item_id uuid, p_assignee_auth_user_id uuid, p_assignee_label text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.cycle_count_scope_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_can_see_expected boolean;
begin
  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot assign scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to assign scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  if v_item.status not in ('pending', 'recount_required') then
    raise exception 'task_not_assignable: scope item % is % -- only a pending or recount_required item may be assigned', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;

  update app.cycle_count_scope_items set
    status = 'assigned', assigned_to_auth_user_id = p_assignee_auth_user_id, assigned_to_label = p_assignee_label, assigned_at = now()
  where id = p_scope_item_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_cycle_count_scope_item',
    'app.cycle_count_scope_items', v_item.id, 'success', null, null, jsonb_build_object('assigned_to', p_assignee_label)
  );

  -- Findings review (HIGH #1/#3): blind-count redaction (design note 6) -- a plain
  -- OPS:Edit-only counter self-assigning a scope item must never learn the true
  -- expected quantity before ever entering a count.
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
  if not v_can_see_expected then
    v_item.snapshot_expected_quantity := null;
    v_item.variance_quantity := null;
    v_item.variance_pct := null;
    v_item.snapshot_record_version := null;
  end if;

  return v_item;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_cycle_count_plan(p_plan_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.cycle_count_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_plan app.cycle_count_plans;
  v_warehouse app.warehouses;
  v_scope_item app.cycle_count_scope_items;
  v_cancelled_count integer := 0;
begin
  select * into v_plan from app.cycle_count_plans where id = p_plan_id for update;
  if not found or not app.has_active_tenant_membership(v_plan.tenant_id, p_actor_auth_user_id) then
    raise exception 'plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_plan.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot cancel plan %', p_actor_auth_user_id, p_plan_id using errcode = 'insufficient_privilege';
  end if;

  if v_plan.status not in ('draft', 'active') then
    raise exception 'invalid_transition: plan % is % -- only a draft or active plan may be cancelled', p_plan_id, v_plan.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a cycle count plan' using errcode = 'check_violation';
  end if;
  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version using errcode = 'check_violation';
  end if;

  -- Design note (Prompt 239 section 32): a real loop, each row individually locked and
  -- updated -- never a bare bulk UPDATE -- so each scope item's own touch trigger fires
  -- correctly. Approved (adjusted) movements are permanent and never touched here.
  for v_scope_item in
    select * from app.cycle_count_scope_items where plan_id = p_plan_id and status not in ('adjusted', 'no_variance_closed', 'cancelled') for update
  loop
    update app.cycle_count_scope_items set status = 'cancelled' where id = v_scope_item.id;
    v_cancelled_count := v_cancelled_count + 1;
  end loop;

  update app.cycle_count_plans set status = 'cancelled' where id = p_plan_id returning * into v_plan;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_cycle_count_plan',
    'app.cycle_count_plans', v_plan.id, 'success', p_reason, null, jsonb_build_object('scope_items_cancelled', v_cancelled_count)
  );

  return v_plan;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_cycle_count_scope_item(p_scope_item_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.cycle_count_scope_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
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
    raise exception 'insufficient_authority: identity % cannot cancel scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to cancel scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority is confirmed above, never before.
  if v_item.status = 'cancelled' then
    return v_item;
  end if;
  if v_item.status in ('adjusted', 'no_variance_closed') then
    raise exception 'scope_item_already_resolved: scope item % is % -- a resolved item may never be cancelled (approved movements are permanent, Prompt 239 section 32)', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a cycle count scope item' using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;

  update app.cycle_count_scope_items set status = 'cancelled' where id = p_scope_item_id returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_cycle_count_scope_item',
    'app.cycle_count_scope_items', v_item.id, 'success', p_reason, null, null
  );

  return v_item;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_wms_outbound_order(p_outbound_order_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_pick_progress_count integer;
begin
  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id for update;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'outbound_order_not_found: %', p_outbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit outbound order %', p_actor_auth_user_id, p_outbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: outbound order % expected version % but found %', p_outbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;

  -- Idempotent no-op -- only after authority/version are confirmed above, never
  -- before (design lesson a).
  if v_order.status = 'cancelled' then
    return v_order;
  end if;

  -- ATW-017 widening (design note 13, obligated by ATW-016A's own design note 8):
  -- Picking now exists as a live capability. Block cancellation while any
  -- non-cancelled app.wms_pick_tasks row (regardless of its own progress) still
  -- references one of this order's own lines -- each such task's own live app.
  -- inventory_reservations row would otherwise become orphaned against a demand
  -- order that no longer exists.
  select count(*) into v_pick_progress_count
    from app.wms_pick_tasks t
    join app.wms_outbound_order_lines l on l.id = t.outbound_order_line_id
    where l.outbound_order_id = p_outbound_order_id and t.status <> 'cancelled';
  if v_pick_progress_count > 0 then
    raise exception 'has_pick_progress: outbound order % has % non-cancelled pick task(s) -- cancel each pick task first', p_outbound_order_id, v_pick_progress_count
      using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel an outbound order' using errcode = 'check_violation';
  end if;

  update app.wms_outbound_orders set status = 'cancelled', cancelled_reason = p_reason where id = p_outbound_order_id returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_outbound_order',
    'app.wms_outbound_orders', v_order.id, 'success', p_reason, null, null
  );

  return v_order;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_wms_outbound_shipment(p_shipment_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
begin
  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id for update;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_not_found: %', p_shipment_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_shipment.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_shipment.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit shipment %', p_actor_auth_user_id, p_shipment_id using errcode = 'insufficient_privilege';
  end if;
  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment % expected version % but found %', p_shipment_id, p_expected_version, v_shipment.record_version using errcode = 'check_violation';
  end if;

  -- Idempotent no-op -- only after authority/version are confirmed above, never before
  -- (bug class a).
  if v_shipment.status = 'cancelled' then
    return v_shipment;
  end if;
  if v_shipment.status <> 'staging' then
    raise exception 'shipment_not_cancellable: % is % -- only an uncommitted (staging) shipment may be cancelled here; a real transfer has already posted for a loaded shipment (rollback/recovery note: correct through governed return/adjustment)', p_shipment_id, v_shipment.status
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a shipment' using errcode = 'check_violation';
  end if;

  delete from app.wms_shipment_packages where shipment_id = p_shipment_id;

  update app.wms_outbound_shipments set
    status = 'cancelled', cancelled_at = now(), cancelled_by_auth_user_id = p_actor_auth_user_id, cancelled_by_label = p_actor_label, cancelled_reason = p_reason
  where id = p_shipment_id
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_outbound_shipment',
    'app.wms_outbound_shipments', v_shipment.id, 'success', p_reason, null, null
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.cancel_wms_pick_task(p_task_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_pick_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit pick task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority is confirmed above, never before.
  if v_task.status = 'cancelled' then
    return v_task;
  end if;

  -- Design note 8: only a task with genuinely zero progress may be cancelled -- the
  -- one case where the SHARED app.release_inventory_reservation (full, un-decremented
  -- amount) is correct and safe to call directly.
  if v_task.picked_quantity > 0 or v_task.short_quantity > 0 then
    raise exception 'has_pick_progress: task % has already picked % and shorted % unit(s) -- a task with real progress may never be cancelled, only completed or reassigned', p_task_id, v_task.picked_quantity, v_task.short_quantity
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a pick task' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: pick task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  perform app.release_inventory_reservation(v_task.reservation_id, 'wms_pick_task_cancelled: ' || p_reason, p_actor_auth_user_id, p_actor_label);

  update app.wms_pick_tasks set status = 'cancelled' where id = p_task_id returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_pick_task',
    'app.wms_pick_tasks', v_task.id, 'success', p_reason, null, null
  );

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.claim_wms_pick_task(p_task_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_pick_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE (FOR UPDATE) -- the real
  -- concurrent-claim-race guard (mirrors app.claim_wms_putaway_task, ATW-014).
  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot claim pick task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  if v_task.status = 'claimed' and v_task.claimed_by_auth_user_id = p_actor_auth_user_id then
    return v_task;
  end if;

  if v_task.status <> 'unclaimed' then
    raise exception 'task_already_claimed: task % is % (claimed_by=%) -- only an unclaimed task may be claimed', p_task_id, v_task.status, v_task.claimed_by_label
      using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: pick task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  update app.wms_pick_tasks set
    status = 'claimed', claimed_by_auth_user_id = p_actor_auth_user_id, claimed_by_label = p_actor_label, claimed_at = now()
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'claim_wms_pick_task',
    'app.wms_pick_tasks', v_task.id, 'success', null, null, jsonb_build_object('claimed_by', p_actor_label)
  );

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.close_cycle_count_plan(p_plan_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.cycle_count_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_plan app.cycle_count_plans;
  v_warehouse app.warehouses;
  v_unresolved_count integer;
begin
  select * into v_plan from app.cycle_count_plans where id = p_plan_id for update;
  if not found or not app.has_active_tenant_membership(v_plan.tenant_id, p_actor_auth_user_id) then
    raise exception 'plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_plan.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot close plan %', p_actor_auth_user_id, p_plan_id using errcode = 'insufficient_privilege';
  end if;

  if v_plan.status <> 'active' then
    raise exception 'invalid_transition: plan % is % -- only an active plan may be closed', p_plan_id, v_plan.status using errcode = 'check_violation';
  end if;
  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version using errcode = 'check_violation';
  end if;

  select count(*) into v_unresolved_count from app.cycle_count_scope_items
    where plan_id = p_plan_id and status not in ('adjusted', 'no_variance_closed', 'cancelled');
  if v_unresolved_count > 0 then
    raise exception 'plan_has_unresolved_scope_items: plan % has % unresolved scope item(s) -- every scope item must be adjusted, no_variance_closed or cancelled before the plan may close', p_plan_id, v_unresolved_count
      using errcode = 'check_violation';
  end if;

  update app.cycle_count_plans set status = 'closed', closed_at = now() where id = p_plan_id returning * into v_plan;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_cycle_count_plan',
    'app.cycle_count_plans', v_plan.id, 'success', null, null, null
  );

  return v_plan;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.confirm_wms_outbound_order(p_outbound_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_readiness app.wms_outbound_readiness;
begin
  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id for update;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'outbound_order_not_found: %', p_outbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit outbound order %', p_actor_auth_user_id, p_outbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: outbound order % expected version % but found %', p_outbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status <> 'draft' then
    raise exception 'invalid_transition: % must be draft to confirm, is %', p_outbound_order_id, v_order.status using errcode = 'check_violation';
  end if;

  v_readiness := app.get_wms_outbound_readiness(p_outbound_order_id, p_actor_auth_user_id);
  if not v_readiness.ready then
    raise exception 'outbound_not_ready: % is not ready to confirm (has_lines=%, warehouse_active=%, owner_active=%, source_shipment_valid=%, invalid_line_count=%)',
      p_outbound_order_id, v_readiness.has_lines, v_readiness.warehouse_active, v_readiness.owner_active, v_readiness.source_shipment_valid, v_readiness.invalid_line_count
      using errcode = 'check_violation';
  end if;

  update app.wms_outbound_orders set status = 'confirmed' where id = p_outbound_order_id returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_wms_outbound_order',
    'app.wms_outbound_orders', v_order.id, 'success', null, null, null
  );

  return v_order;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.correct_warehouse_billing_event(p_original_event_id uuid, p_expected_version integer, p_new_quantity numeric, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_original app.warehouse_billing_events;
  v_existing app.warehouse_billing_events;
  v_new app.warehouse_billing_events;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to correct a billing event' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to correct a billing event' using errcode = 'check_violation';
  end if;
  if p_new_quantity is null or p_new_quantity <= 0 then
    raise exception 'invalid_quantity: the corrected quantity must be positive' using errcode = 'check_violation';
  end if;

  select * into v_original from app.warehouse_billing_events where id = p_original_event_id for update;
  if not found or not app.has_active_tenant_membership(v_original.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_billing_event_not_found: %', p_original_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_original.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_original.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_original.warehouse_id, v_original.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot correct billing event %', p_actor_auth_user_id, p_original_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_original.tenant_id, v_original.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_original_event_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before, and ALWAYS validating the found row's own real corrects_event_id matches.
  select * into v_existing from app.warehouse_billing_events where tenant_id = v_original.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.corrects_event_id = p_original_event_id then
      return v_existing;
    end if;
    raise exception 'idempotency_key_conflict: idempotency key % was already used for a different correction', p_idempotency_key using errcode = 'unique_violation';
  end if;

  if v_original.status in ('corrected', 'reversed') then
    raise exception 'already_corrected: billing event % is already %', p_original_event_id, v_original.status using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.warehouse_billing_events where corrects_event_id = p_original_event_id) then
    raise exception 'already_corrected: billing event % already has a correcting event', p_original_event_id using errcode = 'check_violation';
  end if;
  -- The established optimistic-concurrency contract every other lifecycle-mutating RPC
  -- in this migration applies (bug class b) -- protects against a client acting on
  -- stale business context that the already_corrected checks above do not cover (e.g.
  -- correcting an event the client believed was still plain approved when it has since
  -- been placed on_hold by another actor in the interim).
  if v_original.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_original_event_id, p_expected_version, v_original.record_version using errcode = 'check_violation';
  end if;

  -- Callable regardless of the original's own status (including handed_off --
  -- correcting an already-handed-off event is the whole point of this RPC). A
  -- correction is a fresh financial fact -- the new row still needs its own real
  -- calculate/review/approve/handoff cycle, so it starts genuinely draft.
  begin
    insert into app.warehouse_billing_events (
      tenant_id, warehouse_id, owner_account_id, activity_type, source_type, source_id, source_version,
      uom_code, activity_date, contract_id, rate_component_id, quantity, status, corrects_event_id, correction_reason, idempotency_key, created_by
    ) values (
      v_original.tenant_id, v_original.warehouse_id, v_original.owner_account_id, v_original.activity_type, v_original.source_type, v_original.source_id, v_original.source_version,
      v_original.uom_code, v_original.activity_date, v_original.contract_id, v_original.rate_component_id, p_new_quantity, 'draft', p_original_event_id, p_reason, p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      select * into v_existing from app.warehouse_billing_events where tenant_id = v_original.tenant_id and idempotency_key = p_idempotency_key;
      if found and v_existing.corrects_event_id = p_original_event_id then
        return v_existing;
      end if;
      -- The idempotency_key may be genuinely fresh here -- the unique_violation can
      -- also come from the new warehouse_billing_events_one_correction_per_original_idx
      -- (a concurrent correction of the SAME original under a different key), mirroring
      -- app.reverse_warehouse_billing_event's own identical fallback exactly.
      raise exception 'already_corrected: billing event % already has a correcting event (concurrent request)', p_original_event_id using errcode = 'check_violation';
  end;

  -- A lifecycle marker only -- the ORIGINAL's own base_amount/tax_amount/total_amount/
  -- calculation_explanation are never touched (proving no in-place rewrite).
  update app.warehouse_billing_events set status = 'corrected' where id = p_original_event_id and record_version = p_expected_version;

  perform app.capture_audit_event(
    v_original.tenant_id, p_actor_auth_user_id, p_actor_label, 'correct_warehouse_billing_event',
    'app.warehouse_billing_events', v_new.id, 'success', p_reason,
    jsonb_build_object('original_event_id', p_original_event_id, 'original_quantity', v_original.quantity),
    jsonb_build_object('new_quantity', p_new_quantity)
  );

  return v_new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.create_label_template_version_draft(p_template_id uuid, p_content_template text, p_allowed_variables text[], p_symbology text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.label_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_template app.label_templates;
  v_version app.label_template_versions;
  v_symbology text;
  v_allowed text[];
  v_match text[];
  v_var text;
  v_next_version integer;
begin
  select * into v_template from app.label_templates where id = p_template_id;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_content_template is null or length(trim(p_content_template)) = 0 then
    raise exception 'invalid_content_template: content_template is required' using errcode = 'check_violation';
  end if;
  v_symbology := coalesce(p_symbology, 'code128');
  if v_symbology not in ('code128', 'code39', 'qr', 'datamatrix') then
    raise exception 'invalid_symbology: % is not a recognized symbology', v_symbology using errcode = 'check_violation';
  end if;
  v_allowed := coalesce(p_allowed_variables, '{}'::text[]);

  -- Fail as early as possible (design note in table 2's own comment): every {{name}}
  -- placeholder in content_template must already be whitelisted at DRAFT time, never
  -- deferred to generate/preview time.
  for v_match in select regexp_matches(p_content_template, '\{\{([a-zA-Z0-9_]+)\}\}', 'g') loop
    v_var := v_match[1];
    if not (v_var = any (v_allowed)) then
      raise exception 'unwhitelisted_template_variable: % is used in content_template but is not present in allowed_variables', v_var
        using errcode = 'check_violation';
    end if;
  end loop;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.label_template_versions where template_id = p_template_id;

  insert into app.label_template_versions (
    tenant_id, template_id, version_number, content_template, allowed_variables, symbology, created_by
  ) values (
    v_template.tenant_id, p_template_id, v_next_version, p_content_template, v_allowed, v_symbology, p_actor_label
  )
  returning * into v_version;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_label_template_version_draft',
    'app.label_template_versions', v_version.id, 'success', null, null,
    jsonb_build_object('template_id', p_template_id, 'version_number', v_version.version_number)
  );

  return v_version;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.create_warehouse_billing_rate_component(p_contract_id uuid, p_warehouse_id uuid, p_activity_type text, p_rate_basis text, p_rate_uom_code text, p_unit_rate numeric, p_minimum_amount numeric, p_currency text, p_tier_schedule jsonb, p_time_basis_unit text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_rate_components
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_contract app.customer_contracts;
  v_warehouse app.warehouses;
  v_component app.warehouse_billing_rate_components;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found or not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  -- COM:Edit only -- no separate record-scope check, matching app.customer_contracts'
  -- own real mutation precedent directly (see this migration's own header, correction 4).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'rate_component_requires_draft_contract: contract % is % -- rate components may only be added while the contract is draft', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  if p_warehouse_id is not null then
    select * into v_warehouse from app.warehouses where id = p_warehouse_id;
    if not found or v_warehouse.tenant_id <> v_contract.tenant_id then
      raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, v_contract.tenant_id using errcode = 'no_data_found';
    end if;
  end if;

  if p_activity_type not in ('storage', 'receiving', 'handling', 'putaway', 'pick', 'pack', 'outbound', 'value_added') then
    raise exception 'invalid_activity_type: % is not a recognized activity type', p_activity_type using errcode = 'check_violation';
  end if;
  if p_rate_basis not in ('flat', 'per_unit', 'tiered', 'time_basis') then
    raise exception 'invalid_rate_basis: % is not a recognized rate basis', p_rate_basis using errcode = 'check_violation';
  end if;
  if p_unit_rate is null or p_unit_rate < 0 then
    raise exception 'invalid_unit_rate: unit_rate must be non-negative' using errcode = 'check_violation';
  end if;
  if p_minimum_amount is not null and p_minimum_amount < 0 then
    raise exception 'invalid_minimum_amount: minimum_amount must be non-negative' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
  end if;

  if p_rate_basis = 'flat' then
    if p_rate_uom_code is not null then
      raise exception 'invalid_rate_uom_for_basis: rate_uom_code must be null for rate_basis=flat' using errcode = 'check_violation';
    end if;
  else
    if p_rate_uom_code is null then
      raise exception 'invalid_rate_uom_for_basis: rate_uom_code is required for rate_basis=%', p_rate_basis using errcode = 'check_violation';
    end if;
    if not app.validate_uom_code(p_rate_uom_code) then
      raise exception 'invalid_uom_code: % is not a registered UOM code', p_rate_uom_code using errcode = 'check_violation';
    end if;
  end if;

  if p_rate_basis = 'tiered' then
    if not app.validate_warehouse_billing_tier_schedule(p_tier_schedule) then
      raise exception 'invalid_tier_schedule: tier_schedule must be a non-empty array of {threshold, rate} objects with strictly ascending threshold' using errcode = 'check_violation';
    end if;
  elsif p_tier_schedule is not null then
    raise exception 'invalid_tier_schedule: tier_schedule is only meaningful for rate_basis=tiered' using errcode = 'check_violation';
  end if;

  if p_rate_basis = 'time_basis' then
    if p_time_basis_unit is null or length(trim(p_time_basis_unit)) = 0 then
      raise exception 'invalid_time_basis_unit: time_basis_unit is required for rate_basis=time_basis' using errcode = 'check_violation';
    end if;
  elsif p_time_basis_unit is not null then
    raise exception 'invalid_time_basis_unit: time_basis_unit is only meaningful for rate_basis=time_basis' using errcode = 'check_violation';
  end if;

  begin
    insert into app.warehouse_billing_rate_components (
      tenant_id, contract_id, warehouse_id, activity_type, rate_basis, rate_uom_code, unit_rate, minimum_amount, currency,
      tier_schedule, time_basis_unit, created_by
    ) values (
      v_contract.tenant_id, p_contract_id, p_warehouse_id, p_activity_type, p_rate_basis, p_rate_uom_code, p_unit_rate, p_minimum_amount, p_currency,
      p_tier_schedule, p_time_basis_unit, p_actor_label
    )
    returning * into v_component;
  exception
    when unique_violation then
      raise exception 'rate_component_scope_conflict: contract % already has a % rate component for % (warehouse %)', p_contract_id, p_activity_type, p_activity_type, coalesce(p_warehouse_id::text, 'tenant-wide')
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_warehouse_billing_rate_component',
    'app.warehouse_billing_rate_components', v_component.id, 'success', null, null,
    jsonb_build_object('contract_id', p_contract_id, 'activity_type', p_activity_type, 'rate_basis', p_rate_basis)
  );

  return v_component;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.evaluate_claim_settlement_readiness(p_case_id uuid, p_reevaluation_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_settlement_readiness_evaluations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_existing app.claim_settlement_readiness_evaluations;
  v_has_existing boolean;
  v_blockers jsonb := '[]'::jsonb;
  v_item_count integer;
  v_review app.claim_responsibility_reviews;
  v_recovery_count integer;
  v_evaluated_status text;
  v_evidence jsonb;
  v_new app.claim_settlement_readiness_evaluations;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed and cannot be re-evaluated for settlement readiness', p_case_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.claim_settlement_readiness_evaluations where claim_case_id = p_case_id and is_current;
  v_has_existing := found;
  if v_has_existing and (p_reevaluation_reason is null or length(trim(p_reevaluation_reason)) = 0) then
    raise exception 'claim_settlement_reevaluation_reason_required: a non-empty reason is required to reevaluate a claim case that already has a current settlement-readiness evaluation'
      using errcode = 'check_violation';
  end if;

  select count(*) into v_item_count from app.claim_items where claim_case_id = p_case_id and status = 'active';
  if v_item_count = 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_claim_items'));
  end if;

  select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
  if not found or v_review.status = 'proposed' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_approved_responsibility_decision'));
  elsif v_review.status = 'denied' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_finalized_reserve', 'reviewStatus', 'denied'));
  elsif v_review.status in ('approved', 'amended') then
    if v_review.final_reserve_amount is null then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_finalized_reserve', 'reviewStatus', v_review.status));
    elsif v_review.final_responsibility_party is distinct from 'internal' and v_review.final_reserve_amount > 0 then
      select count(*) into v_recovery_count from app.claim_recovery_records where claim_case_id = p_case_id;
      if v_recovery_count = 0 then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_recovery_records_yet', 'finalResponsibilityParty', v_review.final_responsibility_party));
      end if;
    end if;
  end if;

  v_evaluated_status := case when jsonb_array_length(v_blockers) = 0 then 'ready' else 'not_ready' end;
  v_evidence := jsonb_build_object(
    'claimItemCount', v_item_count,
    'currentReviewId', v_review.id,
    'currentReviewStatus', v_review.status,
    'finalResponsibilityParty', v_review.final_responsibility_party,
    'finalReserveAmount', v_review.final_reserve_amount
  );

  if v_has_existing then
    update app.claim_settlement_readiness_evaluations set is_current = false where id = v_existing.id;
  end if;

  insert into app.claim_settlement_readiness_evaluations (
    tenant_id, claim_case_id, version_number, evaluated_status, blockers, evidence,
    reevaluation_reason, supersedes_evaluation_id, evaluated_by_auth_user_id, evaluated_by, created_by
  ) values (
    v_case.tenant_id, p_case_id, coalesce(v_existing.version_number, 0) + 1, v_evaluated_status, v_blockers, v_evidence,
    p_reevaluation_reason, v_existing.id, p_actor_auth_user_id, p_actor_label, p_actor_label
  )
  returning * into v_new;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_claim_settlement_readiness',
    'app.claim_settlement_readiness_evaluations', v_new.id, 'success', p_reevaluation_reason, null,
    jsonb_build_object('evaluated_status', v_new.evaluated_status, 'blockers', v_new.blockers)
  );

  return v_new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.freeze_cycle_count_scope(p_plan_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS SETOF app.cycle_count_scope_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_plan app.cycle_count_plans;
  v_warehouse app.warehouses;
  v_balance app.inventory_balances;
  v_item app.item_masters;
  v_existing_scope_item app.cycle_count_scope_items;
  v_created_ids uuid[] := '{}';
  v_scope_item app.cycle_count_scope_items;
  v_can_see_expected boolean;
begin
  select * into v_plan from app.cycle_count_plans where id = p_plan_id for update;
  if not found or not app.has_active_tenant_membership(v_plan.tenant_id, p_actor_auth_user_id) then
    raise exception 'plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_plan.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot freeze plan %', p_actor_auth_user_id, p_plan_id using errcode = 'insufficient_privilege';
  end if;

  if v_plan.status <> 'draft' then
    raise exception 'freeze_already_done: plan % is % -- only a draft plan may be frozen', p_plan_id, v_plan.status using errcode = 'check_violation';
  end if;
  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version using errcode = 'check_violation';
  end if;

  -- Design note 3/9: locks each matching balance row FOR UPDATE as it scans -- a real
  -- point-in-time snapshot, and the structural mechanism that serializes two
  -- concurrent freezes against an overlapping balance set. Only existing app.
  -- inventory_balances rows (status='on_hand') are eligible -- a location the ledger
  -- has never touched is out of scope (design note 9), a deliberate boundary.
  for v_balance in
    select b.* from app.inventory_balances b
    where b.tenant_id = v_plan.tenant_id
      and b.warehouse_id = v_plan.warehouse_id
      and b.status = 'on_hand'
      and (v_plan.scope_filter_location_id is null or b.location_id = v_plan.scope_filter_location_id)
      and (v_plan.scope_filter_item_master_id is null or b.item_master_id = v_plan.scope_filter_item_master_id)
      and (v_plan.scope_filter_owner_account_id is null or b.owner_account_id = v_plan.scope_filter_owner_account_id)
      and (
        v_plan.scope_filter_zone_id is null
        or exists (select 1 from app.warehouse_locations l where l.id = b.location_id and l.zone_id = v_plan.scope_filter_zone_id)
      )
    order by b.id
    for update
  loop
    select * into v_existing_scope_item from app.cycle_count_scope_items
      where snapshot_balance_id = v_balance.id and status not in ('adjusted', 'no_variance_closed', 'cancelled');
    if found then
      raise exception 'balance_already_in_active_count: balance % is already part of an active cycle count scope item %', v_balance.id, v_existing_scope_item.id
        using errcode = 'check_violation';
    end if;

    select * into v_item from app.item_masters where id = v_balance.item_master_id;

    -- Design note 7 (defense-in-depth, findings review): the preceding scan-and-check
    -- plus this loop's own FOR UPDATE lock on each matching balance row make this race
    -- structurally unreachable today, but a raw unique_violation is still translated to
    -- the same friendly error the pre-check above raises, rather than left to propagate
    -- unhandled -- identical convention to app.create_cycle_count_plan/app.record_
    -- cycle_count_observation's own idempotency-key unique_violation handlers.
    begin
      insert into app.cycle_count_scope_items (
        tenant_id, plan_id, warehouse_id, owner_account_id, item_master_id, location_id, lot_number, serial_number,
        uom_code, snapshot_balance_id, snapshot_expected_quantity, snapshot_record_version
      ) values (
        v_plan.tenant_id, p_plan_id, v_plan.warehouse_id, v_balance.owner_account_id, v_balance.item_master_id, v_balance.location_id, v_balance.lot_number, v_balance.serial_number,
        v_item.base_uom_code, v_balance.id, v_balance.on_hand, v_balance.record_version
      )
      returning * into v_scope_item;
    exception
      when unique_violation then
        select * into v_existing_scope_item from app.cycle_count_scope_items
          where snapshot_balance_id = v_balance.id and status not in ('adjusted', 'no_variance_closed', 'cancelled');
        if found then
          raise exception 'balance_already_in_active_count: balance % is already part of an active cycle count scope item % (concurrent freeze)', v_balance.id, v_existing_scope_item.id
            using errcode = 'check_violation';
        end if;
        raise exception 'balance_already_in_active_count: balance % is already part of an active cycle count scope item (concurrent freeze)', v_balance.id
          using errcode = 'check_violation';
    end;

    v_created_ids := v_created_ids || v_scope_item.id;
  end loop;

  update app.cycle_count_plans set status = 'active', frozen_at = now() where id = p_plan_id;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'freeze_cycle_count_scope',
    'app.cycle_count_plans', p_plan_id, 'success', null, null, jsonb_build_object('scope_item_count', coalesce(array_length(v_created_ids, 1), 0))
  );

  -- Findings review (HIGH #1/#3): blind-count redaction (design note 6) applies to
  -- every RPC that returns a scope item row, mutation or read alike -- a plain
  -- OPS:Edit-only counter must never see snapshot_expected_quantity/variance_quantity/
  -- variance_pct/snapshot_record_version, including via a self-triggered freeze.
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'Override')).allowed;
  for v_scope_item in select * from app.cycle_count_scope_items where id = any(v_created_ids) loop
    if not v_can_see_expected then
      v_scope_item.snapshot_expected_quantity := null;
      v_scope_item.variance_quantity := null;
      v_scope_item.variance_pct := null;
      v_scope_item.snapshot_record_version := null;
    end if;
    return next v_scope_item;
  end loop;
  return;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_claim_case(p_case_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.claim_case_extensions
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  return v_case;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_claim_investigation_history(p_case_id uuid, p_actor_auth_user_id uuid)
 RETURNS SETOF app.claim_investigation_findings
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.claim_investigation_findings where claim_case_id = p_case_id order by created_at asc;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_claim_responsibility_review(p_case_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.claim_responsibility_reviews
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_review app.claim_responsibility_reviews;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
  if not found then
    raise exception 'claim_responsibility_review_not_found: claim case % has no responsibility review yet', p_case_id using errcode = 'no_data_found';
  end if;

  return app.mask_claim_responsibility_review_amounts(v_review, not app.has_view_exception_cost(v_case.tenant_id, p_actor_auth_user_id));
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_claim_settlement_readiness(p_case_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.claim_settlement_readiness_evaluations
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_evaluation app.claim_settlement_readiness_evaluations;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_evaluation from app.claim_settlement_readiness_evaluations where claim_case_id = p_case_id and is_current;
  if not found then
    raise exception 'claim_settlement_not_evaluated: claim case % has never had a settlement-readiness evaluation', p_case_id using errcode = 'no_data_found';
  end if;

  return app.mask_claim_settlement_readiness_evaluation_amounts(v_evaluation, not app.has_view_exception_cost(v_case.tenant_id, p_actor_auth_user_id));
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_cycle_count_plan(p_plan_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.cycle_count_plans
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_plan app.cycle_count_plans;
  v_warehouse app.warehouses;
begin
  select * into v_plan from app.cycle_count_plans where id = p_plan_id;
  if not found or not app.has_active_tenant_membership(v_plan.tenant_id, p_actor_auth_user_id) then
    raise exception 'plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_plan.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view plan %', p_actor_auth_user_id, p_plan_id using errcode = 'insufficient_privilege';
  end if;

  return v_plan;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_cycle_count_scope_item(p_scope_item_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.cycle_count_scope_items
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_can_see_expected boolean;
begin
  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Design note 6: blind-count redaction, computed server-side from the actor's own
  -- real RBAC grant -- there is no caller-supplied parameter that can defeat this.
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
  if not v_can_see_expected then
    v_item.snapshot_expected_quantity := null;
    v_item.variance_quantity := null;
    v_item.variance_pct := null;
    v_item.snapshot_record_version := null;
  end if;

  return v_item;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_label_instance(p_label_instance_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.label_instances
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_label app.label_instances;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id;
  if not found or not app.has_active_tenant_membership(v_label.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_label.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_label.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.label_subject_record_scope_ok(p_actor_auth_user_id, v_label.tenant_id, v_label.subject_type, v_label.subject_id) then
    raise exception 'insufficient_authority: identity % cannot view label %', p_actor_auth_user_id, p_label_instance_id using errcode = 'insufficient_privilege';
  end if;

  return v_label;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_label_template(p_template_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.label_templates
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_template app.label_templates;
begin
  select * into v_template from app.label_templates where id = p_template_id;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_template;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_warehouse_billing_event(p_event_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id;
  if not found or not app.has_active_tenant_membership(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  return app.mask_warehouse_billing_event_amounts(v_event, not app.has_view_selling_price(v_event.tenant_id, p_actor_auth_user_id));
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_warehouse_billing_handoff(p_handoff_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.warehouse_billing_handoffs
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_handoff app.warehouse_billing_handoffs;
  v_event app.warehouse_billing_events;
  v_decision app.rbac_decision;
begin
  select * into v_handoff from app.warehouse_billing_handoffs where id = p_handoff_id;
  if not found or not app.has_active_tenant_membership(v_handoff.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_billing_handoff_not_found: %', p_handoff_id using errcode = 'no_data_found';
  end if;
  select * into v_event from app.warehouse_billing_events where id = v_handoff.billing_event_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_handoff.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_handoff.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view billing handoff %', p_actor_auth_user_id, p_handoff_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_handoff.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view billing handoff %', p_actor_auth_user_id, p_handoff_id using errcode = 'insufficient_privilege';
  end if;

  return v_handoff;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_billing_eligibility_event(p_event_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_billing_eligibility_events
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.wms_billing_eligibility_events;
  v_warehouse app.warehouses;
begin
  select * into v_event from app.wms_billing_eligibility_events where id = p_event_id;
  if not found or not app.has_active_tenant_membership(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'billing_eligibility_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_event.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_event.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view billing eligibility event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view billing eligibility event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  return v_event;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_outbound_order(p_outbound_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_outbound_orders
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'outbound_order_not_found: %', p_outbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view outbound order %', p_actor_auth_user_id, p_outbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_order.tenant_id, v_order.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view outbound order %', p_actor_auth_user_id, p_outbound_order_id using errcode = 'insufficient_privilege';
  end if;

  return v_order;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_outbound_readiness(p_outbound_order_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_outbound_readiness
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_account app.accounts;
  v_shipment app.shipment_orders;
  v_result app.wms_outbound_readiness;
  v_line_count integer;
  v_invalid_line_count integer;
begin
  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'outbound_order_not_found: %', p_outbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view outbound order %', p_actor_auth_user_id, p_outbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_order.tenant_id, v_order.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view outbound order %', p_actor_auth_user_id, p_outbound_order_id using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_line_count from app.wms_outbound_order_lines where outbound_order_id = p_outbound_order_id;
  select count(*) into v_invalid_line_count
    from app.wms_outbound_order_lines l
    join app.item_masters m on m.id = l.item_master_id
    where l.outbound_order_id = p_outbound_order_id and m.status <> 'active';
  select * into v_account from app.accounts where id = v_order.owner_account_id;

  v_result.has_lines := v_line_count > 0;
  v_result.warehouse_active := v_warehouse.status = 'active';
  v_result.owner_active := v_account.status = 'active';

  if v_order.source_type = 'shipment_order' then
    select * into v_shipment from app.shipment_orders where id = v_order.source_shipment_order_id;
    v_result.source_shipment_valid := found and v_shipment.status = 'confirmed';
  else
    v_result.source_shipment_valid := true;
  end if;

  v_result.invalid_line_count := v_invalid_line_count;
  v_result.ready := v_result.has_lines and v_result.warehouse_active and v_result.owner_active and v_result.source_shipment_valid and v_invalid_line_count = 0;

  return v_result;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_outbound_shipment(p_shipment_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_outbound_shipments
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
begin
  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_not_found: %', p_shipment_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_shipment.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_shipment.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view shipment %', p_actor_auth_user_id, p_shipment_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view shipment %', p_actor_auth_user_id, p_shipment_id using errcode = 'insufficient_privilege';
  end if;

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_package(p_package_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
begin
  select * into v_package from app.wms_packages where id = p_package_id;
  if not found or not app.has_active_tenant_membership(v_package.tenant_id, p_actor_auth_user_id) then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_package.tenant_id, v_package.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  return v_package;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_packing_task(p_packing_task_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_packing_tasks
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_packing_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_packing_tasks where id = p_packing_task_id;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'packing_task_not_found: %', p_packing_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view packing task %', p_actor_auth_user_id, p_packing_task_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_task.tenant_id, v_task.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view packing task %', p_actor_auth_user_id, p_packing_task_id using errcode = 'insufficient_privilege';
  end if;

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_wms_pick_task(p_task_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.wms_pick_tasks
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_pick_tasks where id = p_task_id;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view pick task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_task.tenant_id, v_task.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view pick task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.handoff_claim_settlement_readiness(p_case_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_settlement_readiness_handoffs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_current app.claim_settlement_readiness_evaluations;
  v_handoff app.claim_settlement_readiness_handoffs;
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
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to hand off claim settlement readiness' using errcode = 'check_violation';
  end if;

  select * into v_current from app.claim_settlement_readiness_evaluations where claim_case_id = p_case_id and is_current;
  if not found then
    raise exception 'claim_settlement_not_evaluated: claim case % has never had a settlement-readiness evaluation', p_case_id using errcode = 'no_data_found';
  end if;
  if v_current.evaluated_status <> 'ready' then
    raise exception 'claim_settlement_not_ready: claim case % is not ready for Finance settlement handoff', p_case_id using errcode = 'check_violation';
  end if;

  begin
    insert into app.claim_settlement_readiness_handoffs (
      tenant_id, claim_case_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by
    ) values (
      v_case.tenant_id, p_case_id, v_current.id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    )
    returning * into v_handoff;
  exception
    when unique_violation then
      select * into v_handoff from app.claim_settlement_readiness_handoffs
      where tenant_id = v_case.tenant_id and claim_case_id = p_case_id and idempotency_key = p_idempotency_key;
      return v_handoff;
  end;

  perform app.advance_claim_case_stage(p_case_id, 'finance_handoff');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'handoff_claim_settlement_readiness',
    'app.claim_settlement_readiness_handoffs', v_handoff.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'evaluation_id', v_current.id, 'idempotency_key', p_idempotency_key)
  );

  return v_handoff;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.handoff_warehouse_billing_event(p_event_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_handoffs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
  v_existing app.warehouse_billing_handoffs;
  v_handoff app.warehouse_billing_handoffs;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to hand off a billing event' using errcode = 'check_violation';
  end if;

  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found or not app.has_active_tenant_membership(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- Release-authority already spent at approve -- handoff itself is mechanical
  -- (mirrors OPS-181's own identical Override-then-Edit tiering between
  -- override_billing_readiness and handoff_billing_readiness).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot hand off billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before, and ALWAYS validating the found handoff's own real target (billing_event_id)
  -- matches the current call's target before treating it as a safe replay (the
  -- ATW-020/021 lesson, again -- the third RPC in this migration where it applies).
  select * into v_existing from app.warehouse_billing_handoffs where tenant_id = v_event.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.billing_event_id = p_event_id then
      return v_existing;
    end if;
    raise exception 'idempotency_key_conflict: idempotency key % was already used for a different billing event''s handoff', p_idempotency_key using errcode = 'unique_violation';
  end if;

  if v_event.status <> 'approved' then
    raise exception 'invalid_transition: billing event % is % -- only approved may be handed off', p_event_id, v_event.status using errcode = 'check_violation';
  end if;

  begin
    insert into app.warehouse_billing_handoffs (tenant_id, billing_event_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by_label)
    values (v_event.tenant_id, p_event_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label)
    returning * into v_handoff;
  exception
    when unique_violation then
      select * into v_existing from app.warehouse_billing_handoffs where tenant_id = v_event.tenant_id and idempotency_key = p_idempotency_key;
      if found and v_existing.billing_event_id = p_event_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent handoff', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.warehouse_billing_events set status = 'handed_off' where id = p_event_id;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'handoff_warehouse_billing_event',
    'app.warehouse_billing_handoffs', v_handoff.id, 'success', null, null, jsonb_build_object('billing_event_id', p_event_id)
  );

  return v_handoff;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.link_claim_evidence(p_case_id uuid, p_evidence_type text, p_evidence_id uuid, p_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_evidence_links
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
  v_leg app.shipment_legs;
  v_custody app.shipment_leg_custody_events;
  v_epod app.epod_captures;
  v_movement app.inventory_movements;
  v_shipment app.wms_outbound_shipments;
  v_file app.files;
  v_access_log app.file_access_logs;
  v_link app.claim_evidence_links;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if p_evidence_type not in ('shipment_leg', 'shipment_leg_custody_event', 'inventory_movement', 'wms_outbound_shipment', 'epod_capture', 'file') then
    raise exception 'claim_invalid_evidence_type: % is not a supported evidence type', p_evidence_type using errcode = 'check_violation';
  end if;

  if p_evidence_type = 'shipment_leg' then
    select * into v_leg from app.shipment_legs where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: shipment_leg % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_leg.tenant_id <> v_case.tenant_id or v_leg.shipment_order_id <> v_exception.shipment_order_id then
      raise exception 'claim_evidence_scope_mismatch: shipment_leg % does not belong to this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'shipment_leg_custody_event' then
    select ce.* into v_custody from app.shipment_leg_custody_events ce where ce.id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: shipment_leg_custody_event % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    select * into v_leg from app.shipment_legs where id = v_custody.shipment_leg_id;
    if v_leg.tenant_id <> v_case.tenant_id or v_leg.shipment_order_id <> v_exception.shipment_order_id then
      raise exception 'claim_evidence_scope_mismatch: shipment_leg_custody_event % does not belong to this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'epod_capture' then
    select * into v_epod from app.epod_captures where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: epod_capture % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_epod.tenant_id <> v_case.tenant_id or v_epod.shipment_order_id <> v_exception.shipment_order_id then
      raise exception 'claim_evidence_scope_mismatch: epod_capture % does not belong to this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'inventory_movement' then
    -- app.inventory_movements carries no shipment_order_id (warehouse-scoped by
    -- design, ATW-015, verified directly) -- tenant match only (see migration header).
    select * into v_movement from app.inventory_movements where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: inventory_movement % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_movement.tenant_id <> v_case.tenant_id then
      raise exception 'claim_evidence_scope_mismatch: inventory_movement % does not belong to this claim case''s own tenant', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'wms_outbound_shipment' then
    -- app.wms_outbound_shipments carries no shipment_order_id either (verified
    -- directly, ATW-019) -- tenant AND owner_account_id match (see migration
    -- header design note 3: owner_account_id must equal this claim case's own
    -- shipment order's shipper_account_id, closing the same-tenant/cross-customer
    -- gap caught on adversarial review).
    select * into v_shipment from app.wms_outbound_shipments where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: wms_outbound_shipment % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_shipment.tenant_id <> v_case.tenant_id then
      raise exception 'claim_evidence_scope_mismatch: wms_outbound_shipment % does not belong to this claim case''s own tenant', p_evidence_id using errcode = 'check_violation';
    end if;
    if v_shipment.owner_account_id <> (select shipper_account_id from app.shipment_orders where id = v_exception.shipment_order_id) then
      raise exception 'claim_evidence_scope_mismatch: wms_outbound_shipment % belongs to a different customer account than this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;

  elsif p_evidence_type = 'file' then
    select * into v_file from app.files where id = p_evidence_id;
    if not found then
      raise exception 'claim_evidence_not_found: file % not found', p_evidence_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_case.tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> v_exception.shipment_order_id then
      raise exception 'claim_evidence_scope_mismatch: file % does not belong to this claim case''s own shipment order', p_evidence_id using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'claim_evidence_file_unsafe: file % has scan status % -- only clean evidence may be linked to a claim', p_evidence_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
    -- Reuse app.authorize_file_access DIRECTLY for a real, additional file-access
    -- audit entry (never a second file-security mechanism) -- see migration header.
    v_access_log := app.authorize_file_access(p_evidence_id, 'metadata_view', p_actor_auth_user_id, p_case_id);
    if v_access_log.result = 'denied' then
      raise exception 'claim_evidence_file_access_denied: file % access denied (%)', p_evidence_id, v_access_log.reason using errcode = 'insufficient_privilege';
    end if;
  end if;

  begin
    insert into app.claim_evidence_links (tenant_id, claim_case_id, evidence_type, evidence_id, note, added_by_auth_user_id, added_by)
    values (v_case.tenant_id, p_case_id, p_evidence_type, p_evidence_id, p_note, p_actor_auth_user_id, p_actor_label)
    returning * into v_link;
  exception
    when unique_violation then
      -- Idempotent replay on the SAME (claim_case_id, evidence_type, evidence_id)
      -- tuple -- a resubmission whose own note differs from the original is
      -- rejected as a real conflict rather than silently discarded (mirrors app.
      -- create_label_printer, ATW-021; adversarial review caught an earlier draft
      -- that silently discarded a mismatched note here).
      select * into v_link from app.claim_evidence_links where claim_case_id = p_case_id and evidence_type = p_evidence_type and evidence_id = p_evidence_id;
      if v_link.note is distinct from p_note then
        raise exception 'claim_evidence_link_conflict: evidence % (%) is already linked to claim case % with a different note', p_evidence_id, p_evidence_type, p_case_id
          using errcode = 'unique_violation';
      end if;
      return v_link;
  end;

  perform app.advance_claim_case_stage(p_case_id, 'evidence_gathering');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_claim_evidence',
    'app.claim_evidence_links', v_link.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'evidence_type', p_evidence_type, 'evidence_id', p_evidence_id)
  );

  return v_link;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_claim_evidence(p_case_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 RETURNS SETOF app.claim_evidence_links
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.claim_evidence_links where claim_case_id = p_case_id order by added_at desc limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_claim_items(p_case_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 RETURNS SETOF app.claim_items
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select (app.mask_claim_item_amounts(i, not app.has_view_exception_cost(v_case.tenant_id, p_actor_auth_user_id))).*
  from app.claim_items i
  where i.claim_case_id = p_case_id
  order by i.created_at desc
  limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_claim_recovery_records(p_case_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 RETURNS SETOF app.claim_recovery_records
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select (app.mask_claim_recovery_record_amounts(r, not app.has_view_exception_cost(v_case.tenant_id, p_actor_auth_user_id))).*
  from app.claim_recovery_records r
  where r.claim_case_id = p_case_id
  order by r.recovered_at desc
  limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_claim_settlement_readiness_handoffs(p_case_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 RETURNS SETOF app.claim_settlement_readiness_handoffs
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot view claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.claim_settlement_readiness_handoffs where claim_case_id = p_case_id order by handoff_seq desc limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_label_template_versions(p_template_id uuid, p_actor_auth_user_id uuid, p_status_filter text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS SETOF app.label_template_versions
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_template app.label_templates;
  v_limit integer;
begin
  select * into v_template from app.label_templates where id = p_template_id;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select * from app.label_template_versions v
  where v.template_id = p_template_id
    and (p_status_filter is null or v.status = p_status_filter)
  order by v.version_number desc
  limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.list_warehouse_billing_rate_components(p_contract_id uuid, p_actor_auth_user_id uuid, p_activity_type text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS SETOF app.warehouse_billing_rate_components
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found or not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select rc.* from app.warehouse_billing_rate_components rc
  where rc.contract_id = p_contract_id
    and (p_activity_type is null or rc.activity_type = p_activity_type)
  order by rc.created_at desc
  limit v_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.mark_wms_pick_task_exception(p_task_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_pick_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_override app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit pick task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority is confirmed above, never before.
  if v_task.status = 'exception' then
    return v_task;
  end if;

  if v_task.status not in ('claimed', 'partial') then
    raise exception 'invalid_transition: task % is % -- only a claimed or partially-picked task may be marked exception', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to mark a pick task exception' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: pick task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  if v_task.claimed_by_auth_user_id <> p_actor_auth_user_id then
    v_override := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Override');
    if not v_override.allowed then
      raise exception 'insufficient_authority: identity % is neither the claimant of task % nor holds OPS:Override', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
    end if;
  end if;

  update app.wms_pick_tasks set status = 'exception', exception_reason = p_reason where id = p_task_id returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'mark_wms_pick_task_exception',
    'app.wms_pick_tasks', v_task.id, 'success', p_reason, null, null
  );

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.open_claim_case(p_operational_exception_id uuid, p_claimant_type text, p_claimant_account_id uuid, p_claimant_label text, p_contact_snapshot jsonb, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_case_extensions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
  v_existing app.claim_case_extensions;
  v_case app.claim_case_extensions;
begin
  select * into v_exception from app.operational_exceptions where id = p_operational_exception_id;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'operational_exception_not_found: %', p_operational_exception_id using errcode = 'no_data_found';
  end if;

  if p_claimant_type not in ('customer', 'carrier', 'vendor', 'third_party', 'internal') then
    raise exception 'claim_invalid_claimant_type: % is not a supported claimant type', p_claimant_type using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_exception.tenant_id, v_exception.id) then
    raise exception 'insufficient_authority: identity % cannot access exception %', p_actor_auth_user_id, p_operational_exception_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above,
  -- never before (the established ATW-020/021/022 lesson). A resubmission whose own
  -- non-key content (claimant_type/claimant_account_id/claimant_label/
  -- contact_snapshot) differs from the original open is rejected as a real conflict
  -- rather than silently discarded and the stale original returned -- the same
  -- check-a-mismatch-and-raise pattern ATW-021's own app.create_label_printer
  -- already established (adversarial review caught an earlier draft that silently
  -- discarded a mismatched resubmission here).
  select * into v_existing from app.claim_case_extensions where operational_exception_id = p_operational_exception_id;
  if found then
    if v_existing.claimant_type <> p_claimant_type
      or v_existing.claimant_account_id is distinct from p_claimant_account_id
      or v_existing.claimant_label is distinct from p_claimant_label
      or v_existing.contact_snapshot is distinct from p_contact_snapshot
    then
      raise exception 'claim_case_open_conflict: exception % already has an open claim case with different claimant details', p_operational_exception_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_exception.type not in ('damage', 'loss', 'incident', 'delay') then
    raise exception 'claim_ineligible_exception_type: exception % is type % which is not eligible for a claim case', p_operational_exception_id, v_exception.type
      using errcode = 'check_violation';
  end if;

  if p_claimant_account_id is not null and not exists (select 1 from app.accounts where id = p_claimant_account_id and tenant_id = v_exception.tenant_id) then
    raise exception 'claim_claimant_account_not_found: % is not an account of tenant %', p_claimant_account_id, v_exception.tenant_id using errcode = 'no_data_found';
  end if;
  if p_claimant_type <> 'internal' and p_claimant_account_id is null and (p_claimant_label is null or length(trim(p_claimant_label)) = 0) then
    raise exception 'claim_claimant_identification_required: a non-internal claimant requires either claimant_account_id or a non-empty claimant_label' using errcode = 'check_violation';
  end if;
  if p_contact_snapshot is not null and not app.validate_claim_contact_snapshot(p_contact_snapshot) then
    raise exception 'claim_invalid_contact_snapshot: contact_snapshot must contain only name/phone/email keys' using errcode = 'check_violation';
  end if;

  begin
    insert into app.claim_case_extensions (
      tenant_id, operational_exception_id, claimant_type, claimant_account_id, claimant_label, contact_snapshot, opened_by, created_by
    ) values (
      v_exception.tenant_id, p_operational_exception_id, p_claimant_type, p_claimant_account_id, p_claimant_label, p_contact_snapshot, p_actor_label, p_actor_label
    )
    returning * into v_case;
  exception
    when unique_violation then
      -- A genuinely concurrent duplicate open lost the race -- apply the identical
      -- mismatch check as the early short-circuit above (a true race can reach this
      -- branch with content that was never compared against the winner).
      select * into v_case from app.claim_case_extensions where operational_exception_id = p_operational_exception_id;
      if v_case.claimant_type <> p_claimant_type
        or v_case.claimant_account_id is distinct from p_claimant_account_id
        or v_case.claimant_label is distinct from p_claimant_label
        or v_case.contact_snapshot is distinct from p_contact_snapshot
      then
        raise exception 'claim_case_open_conflict: exception % already has an open claim case with different claimant details', p_operational_exception_id
          using errcode = 'unique_violation';
      end if;
      return v_case;
  end;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'open_claim_case',
    'app.claim_case_extensions', v_case.id, 'success', null, null,
    jsonb_build_object('operational_exception_id', p_operational_exception_id, 'claimant_type', p_claimant_type)
  );

  return v_case;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.override_wms_package_qc_hold(p_package_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found or not app.has_active_tenant_membership(v_package.tenant_id, p_actor_auth_user_id) then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot override QC on package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if v_package.qc_status not in ('fail', 'hold') then
    raise exception 'invalid_transition: package % QC status is % -- only a failed or held package may be overridden', p_package_id, v_package.qc_status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to override a QC hold' using errcode = 'check_violation';
  end if;

  update app.wms_packages set
    qc_override_reason = p_reason, qc_override_by_auth_user_id = p_actor_auth_user_id, qc_override_by_label = p_actor_label, qc_override_at = now()
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_wms_package_qc_hold',
    'app.wms_packages', v_package.id, 'success', p_reason, null, jsonb_build_object('overridden_qc_status', v_package.qc_status)
  );

  return v_package;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.preview_label(p_template_version_id uuid, p_variables jsonb, p_actor_auth_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.label_template_versions;
begin
  select * into v_version from app.label_template_versions where id = p_template_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_template_version_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.render_label_content(v_version.content_template, v_version.allowed_variables, coalesce(p_variables, '{}'::jsonb));
end;
$function$
;

CREATE OR REPLACE FUNCTION app.print_label(p_label_instance_id uuid, p_printer_id uuid, p_copies integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.label_print_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_label app.label_instances;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id;
  if not found or not app.has_active_tenant_membership(v_label.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_label.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_label.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.execute_label_print(p_label_instance_id, p_printer_id, p_copies, false, null, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reassign_wms_pick_task(p_task_id uuid, p_new_claimant_auth_user_id uuid, p_new_claimant_label text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_pick_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
  v_new_status text;
begin
  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot override pick task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  if v_task.status in ('picked', 'short', 'cancelled') then
    raise exception 'invalid_transition: task % is % -- an already-resolved or cancelled task may not be reassigned', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reassign or release a pick task' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: pick task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  if p_new_claimant_auth_user_id is null then
    v_new_status := 'unclaimed';
  elsif v_task.picked_quantity > 0 or v_task.short_quantity > 0 then
    v_new_status := 'partial';
  else
    v_new_status := 'claimed';
  end if;

  update app.wms_pick_tasks set
    status = v_new_status,
    claimed_by_auth_user_id = p_new_claimant_auth_user_id,
    claimed_by_label = p_new_claimant_label,
    claimed_at = (case when p_new_claimant_auth_user_id is null then null else now() end),
    exception_reason = (case when v_new_status = 'unclaimed' then null else exception_reason end)
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_wms_pick_task',
    'app.wms_pick_tasks', v_task.id, 'success', p_reason, null, jsonb_build_object('new_claimant', p_new_claimant_label, 'new_status', v_new_status)
  );

  return v_task;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_claim_investigation_finding(p_case_id uuid, p_finding_text text, p_evidence_sufficiency text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_investigation_findings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_exception app.operational_exceptions;
  v_decision app.rbac_decision;
  v_finding app.claim_investigation_findings;
begin
  select * into v_case from app.claim_case_extensions where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'claim_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if v_case.claim_stage = 'closed' then
    raise exception 'claim_case_closed: claim case % is closed -- reopen it first via app.reopen_claim_case', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_exception from app.operational_exceptions where id = v_case.operational_exception_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.claim_case_record_scope_ok(p_actor_auth_user_id, v_case.tenant_id, v_case.operational_exception_id) then
    raise exception 'insufficient_authority: identity % cannot access claim case %', p_actor_auth_user_id, p_case_id using errcode = 'insufficient_privilege';
  end if;
  if v_exception.owner_user_id is null or v_exception.owner_user_id <> p_actor_auth_user_id then
    raise exception 'claim_not_investigator: identity % is not the assigned investigator (owner) of exception %', p_actor_auth_user_id, v_exception.id
      using errcode = 'insufficient_privilege';
  end if;

  if p_finding_text is null or length(trim(p_finding_text)) = 0 then
    raise exception 'claim_finding_text_required: a non-empty finding_text is required' using errcode = 'check_violation';
  end if;
  if p_evidence_sufficiency not in ('sufficient', 'insufficient', 'pending') then
    raise exception 'claim_invalid_evidence_sufficiency: % is not a supported evidence_sufficiency value', p_evidence_sufficiency using errcode = 'check_violation';
  end if;

  insert into app.claim_investigation_findings (tenant_id, claim_case_id, investigator_auth_user_id, finding_text, evidence_sufficiency, created_by)
  values (v_case.tenant_id, p_case_id, p_actor_auth_user_id, p_finding_text, p_evidence_sufficiency, p_actor_label)
  returning * into v_finding;

  perform app.advance_claim_case_stage(p_case_id, 'investigating');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_claim_investigation_finding',
    'app.claim_investigation_findings', v_finding.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'evidence_sufficiency', p_evidence_sufficiency)
  );

  return v_finding;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_claim_recovery(p_case_id uuid, p_recovered_from text, p_recovered_amount numeric, p_currency text, p_recovered_at timestamp with time zone, p_reference text, p_corrects_recovery_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.claim_recovery_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.claim_case_extensions;
  v_decision app.rbac_decision;
  v_review app.claim_responsibility_reviews;
  v_original app.claim_recovery_records;
  v_record app.claim_recovery_records;
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

  select * into v_review from app.claim_responsibility_reviews where claim_case_id = p_case_id and is_current;
  if not found or v_review.status not in ('approved', 'amended') then
    raise exception 'claim_recovery_requires_decision: claim case % has no approved/amended responsibility decision yet', p_case_id using errcode = 'check_violation';
  end if;

  if p_recovered_from not in ('carrier', 'vendor', 'customer', 'insurance') then
    raise exception 'claim_invalid_recovered_from: % is not a supported recovery source', p_recovered_from using errcode = 'check_violation';
  end if;
  if p_recovered_amount is null or p_recovered_amount <= 0 then
    raise exception 'claim_invalid_recovered_amount: recovered_amount must be positive' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
  end if;
  if p_corrects_recovery_id is not null then
    select * into v_original from app.claim_recovery_records where id = p_corrects_recovery_id;
    if not found or v_original.claim_case_id <> p_case_id then
      raise exception 'claim_recovery_not_found: corrects_recovery_id % does not reference a recovery record of this same claim case', p_corrects_recovery_id
        using errcode = 'no_data_found';
    end if;
  end if;

  insert into app.claim_recovery_records (
    tenant_id, claim_case_id, recovered_from, recovered_amount, currency, recovered_at, reference, corrects_recovery_id, recorded_by_auth_user_id, recorded_by
  ) values (
    v_case.tenant_id, p_case_id, p_recovered_from, p_recovered_amount, p_currency, coalesce(p_recovered_at, now()), p_reference, p_corrects_recovery_id, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_record;

  perform app.advance_claim_case_stage(p_case_id, 'recovering');

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_claim_recovery',
    'app.claim_recovery_records', v_record.id, 'success', null, null,
    jsonb_build_object('claim_case_id', p_case_id, 'recovered_from', p_recovered_from, 'recovered_amount', p_recovered_amount, 'corrects_recovery_id', p_corrects_recovery_id)
  );

  return v_record;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_cycle_count_observation(p_scope_item_id uuid, p_observed_quantity numeric, p_observed_uom_code text, p_scanned_location_id uuid, p_scanned_item_master_id uuid, p_scanned_lot_number text, p_scanned_serial_number text, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.cycle_count_scope_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_existing_observation app.cycle_count_observations;
  v_converted_quantity numeric;
  v_new_attempt integer;
  v_variance numeric;
  v_variance_pct numeric;
  v_plan app.cycle_count_plans;
  v_new_status text;
  v_was_first_attempt boolean;
  v_can_see_expected boolean;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to record a cycle count observation' using errcode = 'check_violation';
  end if;

  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot record an observation for scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to record an observation for scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before. Findings review (MEDIUM #5): matches on (tenant_id, idempotency_key) alone
  -- is not enough -- a key collision against a DIFFERENT scope item must be rejected,
  -- never silently treated as "nothing to do" for the caller's own real target item.
  select * into v_existing_observation from app.cycle_count_observations where tenant_id = v_item.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing_observation.scope_item_id <> p_scope_item_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different observation for scope item % (not %)', p_idempotency_key, v_existing_observation.scope_item_id, p_scope_item_id
        using errcode = 'unique_violation';
    end if;
    -- Findings review (HIGH #1/#3): blind-count redaction (design note 6) applies to
    -- the idempotent-replay response identically to a fresh submission's own response.
    v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
    if not v_can_see_expected then
      v_item.snapshot_expected_quantity := null;
      v_item.variance_quantity := null;
      v_item.variance_pct := null;
      v_item.snapshot_record_version := null;
    end if;
    return v_item;
  end if;

  if v_item.status <> 'assigned' then
    raise exception 'task_not_assigned: scope item % is % -- only an assigned item may be counted', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.assigned_to_auth_user_id <> p_actor_auth_user_id then
    raise exception 'not_scope_item_claimant: identity % is not the assigned counter of scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;
  if p_observed_quantity is null or p_observed_quantity < 0 then
    raise exception 'invalid_quantity: observed quantity must be zero or greater' using errcode = 'check_violation';
  end if;

  -- Design note: scan verification is data-integrity only, never an authorization
  -- bypass -- authority was already fully established above.
  if p_scanned_location_id is distinct from v_item.location_id then
    raise exception 'location_mismatch: scanned location % does not match scope item %''s own location %', p_scanned_location_id, p_scope_item_id, v_item.location_id using errcode = 'check_violation';
  end if;
  if p_scanned_item_master_id is distinct from v_item.item_master_id then
    raise exception 'item_mismatch: scanned item % does not match scope item %''s own item %', p_scanned_item_master_id, p_scope_item_id, v_item.item_master_id using errcode = 'check_violation';
  end if;
  if v_item.lot_number is not null and coalesce(p_scanned_lot_number, '') <> v_item.lot_number then
    raise exception 'lot_mismatch: scanned lot % does not match scope item %''s own lot %', p_scanned_lot_number, p_scope_item_id, v_item.lot_number using errcode = 'check_violation';
  end if;
  if v_item.serial_number is not null and coalesce(p_scanned_serial_number, '') <> v_item.serial_number then
    raise exception 'serial_mismatch: scanned serial % does not match scope item %''s own serial %', p_scanned_serial_number, p_scope_item_id, v_item.serial_number using errcode = 'check_violation';
  end if;

  -- Converts to the scope item's own governed uom_code (its item's base_uom_code at
  -- freeze time) when the caller scanned in a different, but convertible, UOM.
  -- app.convert_uom_quantity raises uom_conversion_not_registered naturally when no
  -- path exists -- deliberately allowed to propagate, never guessed.
  v_converted_quantity := app.convert_uom_quantity(p_observed_quantity, p_observed_uom_code, v_item.uom_code);

  v_was_first_attempt := (v_item.count_attempt_number = 0);
  v_new_attempt := v_item.count_attempt_number + 1;

  begin
    insert into app.cycle_count_observations (
      tenant_id, scope_item_id, attempt_number, observed_quantity, observed_uom_code, scanned_location_id, scanned_item_master_id,
      scanned_lot_number, scanned_serial_number, idempotency_key, counted_by_auth_user_id, counted_by_label
    ) values (
      v_item.tenant_id, p_scope_item_id, v_new_attempt, p_observed_quantity, p_observed_uom_code, p_scanned_location_id, p_scanned_item_master_id,
      p_scanned_lot_number, p_scanned_serial_number, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      select * into v_existing_observation from app.cycle_count_observations where tenant_id = v_item.tenant_id and idempotency_key = p_idempotency_key;
      -- Findings review (MEDIUM #5): the same cross-item collision check applies to the
      -- genuine-race path, not only the pre-check above.
      if found and v_existing_observation.scope_item_id = p_scope_item_id then
        v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
        if not v_can_see_expected then
          v_item.snapshot_expected_quantity := null;
          v_item.variance_quantity := null;
          v_item.variance_pct := null;
          v_item.snapshot_record_version := null;
        end if;
        return v_item;
      end if;
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent observation request', p_idempotency_key using errcode = 'unique_violation';
  end;

  v_variance := v_converted_quantity - v_item.snapshot_expected_quantity;
  v_variance_pct := case
    when v_item.snapshot_expected_quantity = 0 then (case when v_converted_quantity = 0 then 0 else 100 end)
    else abs(v_variance) / v_item.snapshot_expected_quantity * 100
  end;

  select * into v_plan from app.cycle_count_plans where id = v_item.plan_id;

  -- Design note: exactly one recount cycle is ever possible -- a first attempt (was_
  -- first_attempt) whose variance exceeds the plan's own recount_threshold_pct goes to
  -- recount_required; every subsequent attempt (2nd+) can only land on pending_review
  -- or no_variance_closed, never recount_required again.
  --
  -- Findings review (MEDIUM #2): variance_threshold_pct is the plan's own configured
  -- materiality tolerance -- a nonzero variance that still falls at or below it is
  -- immaterial by the plan's own definition and auto-resolves exactly like a zero
  -- variance (no manual review, no ledger adjustment posted), checked before the
  -- recount escalation so a generous variance_threshold_pct always wins over a
  -- stricter recount_threshold_pct for the same observation.
  v_new_status := case
    when v_variance = 0 then 'no_variance_closed'
    when abs(v_variance_pct) <= v_plan.variance_threshold_pct then 'no_variance_closed'
    when abs(v_variance_pct) > v_plan.recount_threshold_pct and v_was_first_attempt then 'recount_required'
    else 'pending_review'
  end;

  update app.cycle_count_scope_items set
    count_attempt_number = v_new_attempt,
    last_observed_quantity = v_converted_quantity,
    variance_quantity = v_variance,
    variance_pct = v_variance_pct,
    status = v_new_status
  where id = p_scope_item_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_cycle_count_observation',
    'app.cycle_count_scope_items', v_item.id, 'success', null, null,
    jsonb_build_object('attempt_number', v_new_attempt, 'observed_quantity', v_converted_quantity, 'variance_quantity', v_variance, 'status', v_new_status)
  );

  -- Findings review (HIGH #1/#3): blind-count redaction (design note 6) -- the RPC a
  -- counter is required to call to submit their own blind count must never hand back
  -- the true expected quantity/variance in the same response.
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
  if not v_can_see_expected then
    v_item.snapshot_expected_quantity := null;
    v_item.variance_quantity := null;
    v_item.variance_pct := null;
    v_item.snapshot_record_version := null;
  end if;

  return v_item;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_wms_package_measurements(p_package_id uuid, p_weight_value numeric, p_weight_uom_code text, p_length_value numeric, p_width_value numeric, p_height_value numeric, p_dimension_uom_code text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_before jsonb;
  v_weight_category text;
  v_dimension_category text;
  v_dims_provided integer;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found or not app.has_active_tenant_membership(v_package.tenant_id, p_actor_auth_user_id) then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot measure package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;

  if p_weight_value is null or p_weight_value <= 0 then
    raise exception 'invalid_weight: weight_value must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_weight_uom_code is null or not app.validate_uom_code(p_weight_uom_code) then
    raise exception 'invalid_uom: % is not a registered active UOM code', p_weight_uom_code using errcode = 'check_violation';
  end if;
  select unit_category into v_weight_category from app.uoms where code = p_weight_uom_code;
  if v_weight_category <> 'weight' then
    raise exception 'invalid_uom_category: % is a % UOM, weight is required for weight_uom_code', p_weight_uom_code, v_weight_category using errcode = 'check_violation';
  end if;

  v_dims_provided := (case when p_length_value is not null then 1 else 0 end)
    + (case when p_width_value is not null then 1 else 0 end)
    + (case when p_height_value is not null then 1 else 0 end);
  if v_dims_provided not in (0, 3) then
    raise exception 'invalid_dimensions: length/width/height must be supplied together or not at all' using errcode = 'check_violation';
  end if;
  if v_dims_provided = 3 then
    if p_length_value <= 0 or p_width_value <= 0 or p_height_value <= 0 then
      raise exception 'invalid_dimensions: length/width/height must each be greater than zero' using errcode = 'check_violation';
    end if;
    if p_dimension_uom_code is null or not app.validate_uom_code(p_dimension_uom_code) then
      raise exception 'invalid_uom: % is not a registered active UOM code', p_dimension_uom_code using errcode = 'check_violation';
    end if;
    select unit_category into v_dimension_category from app.uoms where code = p_dimension_uom_code;
    if v_dimension_category <> 'length' then
      raise exception 'invalid_uom_category: % is a % UOM, length is required for dimension_uom_code', p_dimension_uom_code, v_dimension_category using errcode = 'check_violation';
    end if;
  end if;

  v_before := jsonb_build_object(
    'weight_value', v_package.weight_value, 'weight_uom_code', v_package.weight_uom_code,
    'length_value', v_package.length_value, 'width_value', v_package.width_value, 'height_value', v_package.height_value, 'dimension_uom_code', v_package.dimension_uom_code
  );

  update app.wms_packages set
    weight_value = p_weight_value, weight_uom_code = p_weight_uom_code,
    length_value = p_length_value, width_value = p_width_value, height_value = p_height_value, dimension_uom_code = p_dimension_uom_code
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_package_measurements',
    'app.wms_packages', v_package.id, 'success', null, v_before,
    jsonb_build_object('weight_value', p_weight_value, 'weight_uom_code', p_weight_uom_code, 'length_value', p_length_value, 'width_value', p_width_value, 'height_value', p_height_value, 'dimension_uom_code', p_dimension_uom_code)
  );

  return v_package;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_wms_package_qc(p_package_id uuid, p_qc_status text, p_qc_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found or not app.has_active_tenant_membership(v_package.tenant_id, p_actor_auth_user_id) then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot record QC on package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if p_qc_status not in ('pass', 'fail', 'hold') then
    raise exception 'invalid_qc_status: % is not a recognized QC outcome', p_qc_status using errcode = 'check_violation';
  end if;
  if p_qc_status in ('fail', 'hold') and (p_qc_reason is null or length(trim(p_qc_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required for a % QC outcome', p_qc_status using errcode = 'check_violation';
  end if;

  -- A fresh QC event always supersedes any prior override (design note 7) -- the
  -- override applied to the PREVIOUS outcome, never automatically to a new one.
  update app.wms_packages set
    qc_status = p_qc_status, qc_reason = p_qc_reason, qc_by_auth_user_id = p_actor_auth_user_id, qc_by_label = p_actor_label, qc_at = now(),
    qc_override_reason = null, qc_override_by_auth_user_id = null, qc_override_by_label = null, qc_override_at = null
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_package_qc',
    'app.wms_packages', v_package.id, 'success', p_qc_reason, null, jsonb_build_object('qc_status', p_qc_status)
  );

  return v_package;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.record_wms_package_seal(p_package_id uuid, p_seal_number text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found or not app.has_active_tenant_membership(v_package.tenant_id, p_actor_auth_user_id) then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot seal package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if p_seal_number is null or length(trim(p_seal_number)) = 0 then
    raise exception 'invalid_seal: a non-empty seal number is required' using errcode = 'check_violation';
  end if;

  update app.wms_packages set
    seal_number = p_seal_number, sealed_by_auth_user_id = p_actor_auth_user_id, sealed_by_label = p_actor_label, sealed_at = now()
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_package_seal',
    'app.wms_packages', v_package.id, 'success', null, null, jsonb_build_object('seal_number', p_seal_number)
  );

  return v_package;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.remove_package_from_shipment(p_shipment_id uuid, p_package_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
  v_deleted integer;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to remove a package from a shipment' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id for update;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_not_found: %', p_shipment_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_shipment.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_shipment.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit shipment %', p_actor_auth_user_id, p_shipment_id using errcode = 'insufficient_privilege';
  end if;
  if v_shipment.status <> 'staging' then
    raise exception 'shipment_not_staging: % is % -- packages may only be removed while staging', p_shipment_id, v_shipment.status using errcode = 'check_violation';
  end if;

  delete from app.wms_shipment_packages where shipment_id = p_shipment_id and package_id = p_package_id;
  get diagnostics v_deleted = row_count;

  -- Idempotent no-op -- removing a package that is not currently staged (never added,
  -- or already removed by a prior call) is treated as an already-achieved end state,
  -- never an error (bug class a's own spirit, applied to a delete-shaped mutation).
  if v_deleted = 0 then
    return true;
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_package_from_shipment',
    'app.wms_outbound_shipments', v_shipment.id, 'success', p_reason, null, jsonb_build_object('package_id', p_package_id)
  );

  return true;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.remove_wms_outbound_order_line(p_line_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_outbound_order_lines;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_line from app.wms_outbound_order_lines where id = p_line_id for update;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_order from app.wms_outbound_orders where id = v_line.outbound_order_id for update;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  -- RBAC/record-scope checks run BEFORE the status check so an unauthorized (or
  -- cross-tenant) actor cannot learn the order's draft/non-draft state via the
  -- error-message oracle before authorization is established.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit outbound order %', p_actor_auth_user_id, v_order.id using errcode = 'insufficient_privilege';
  end if;
  if v_order.status <> 'draft' then
    raise exception 'outbound_not_draft: % is not draft -- lines may only change while draft', v_order.id using errcode = 'check_violation';
  end if;
  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version
      using errcode = 'check_violation';
  end if;

  delete from app.wms_outbound_order_lines where id = p_line_id;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_wms_outbound_order_line',
    'app.wms_outbound_order_lines', p_line_id, 'success', null, null, null
  );

  return true;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reopen_wms_package(p_package_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_before jsonb;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reopen a confirmed package' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found or not app.has_active_tenant_membership(v_package.tenant_id, p_actor_auth_user_id) then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reopen package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status <> 'confirmed' then
    raise exception 'not_confirmed: package % is % -- only a confirmed package may be reopened', p_package_id, v_package.status using errcode = 'check_violation';
  end if;

  -- ATW-019 widening (design note 6, obligated by this checkpoint's own new capability):
  -- a package already linked to ANY app.wms_shipment_packages row (staged, loaded or
  -- shipped) may no longer be reopened -- real ledger/traceability records may already
  -- reference its exact contents. Remove it from its shipment first (only possible
  -- while that shipment is still staging).
  if exists (select 1 from app.wms_shipment_packages where package_id = p_package_id) then
    raise exception 'package_staged_for_shipment: package % is already staged for an outbound shipment -- remove it from the shipment before reopening', p_package_id using errcode = 'check_violation';
  end if;

  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;

  v_before := jsonb_build_object(
    'status', v_package.status, 'confirmed_at', v_package.confirmed_at, 'qc_status', v_package.qc_status, 'seal_number', v_package.seal_number
  );

  update app.wms_packages set
    status = 'open',
    confirmed_at = null, confirmed_by_auth_user_id = null, confirmed_by_label = null,
    qc_status = 'pending', qc_reason = null, qc_by_auth_user_id = null, qc_by_label = null, qc_at = null,
    qc_override_reason = null, qc_override_by_auth_user_id = null, qc_override_by_label = null, qc_override_at = null,
    seal_number = null, sealed_by_auth_user_id = null, sealed_by_label = null, sealed_at = null,
    reopen_count = reopen_count + 1, reopened_at = now(), reopened_by_auth_user_id = p_actor_auth_user_id, reopened_by_label = p_actor_label, reopened_reason = p_reason
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_wms_package',
    'app.wms_packages', v_package.id, 'success', p_reason, v_before, jsonb_build_object('status', v_package.status, 'reopen_count', v_package.reopen_count)
  );

  return v_package;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reparent_wms_package(p_package_id uuid, p_new_parent_package_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_new_parent app.wms_packages;
  v_walk app.wms_packages;
  v_depth integer := 0;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found or not app.has_active_tenant_membership(v_package.tenant_id, p_actor_auth_user_id) then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reparent package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;

  if p_new_parent_package_id is not null then
    if p_new_parent_package_id = p_package_id then
      raise exception 'cycle_rejected: package % cannot be its own parent', p_package_id using errcode = 'check_violation';
    end if;

    select * into v_new_parent from app.wms_packages where id = p_new_parent_package_id for update;
    if not found or v_new_parent.packing_task_id <> v_package.packing_task_id then
      raise exception 'parent_package_not_found: % is not a package of packing task %', p_new_parent_package_id, v_package.packing_task_id using errcode = 'no_data_found';
    end if;
    if v_new_parent.status = 'confirmed' then
      raise exception 'parent_package_confirmed: % has already been confirmed -- reopen it before nesting under it', p_new_parent_package_id using errcode = 'check_violation';
    end if;

    -- Design note 2b: a real, bounded ancestor walk upward from the proposed new
    -- parent -- if the package being moved is ever encountered, it is already an
    -- ancestor of its own proposed new parent, which is exactly a cycle.
    --
    -- Every node visited by the walk is locked FOR UPDATE (not just the moved
    -- package and its immediate new parent), matching the "row-locked from first
    -- read through final UPDATE" discipline this function already applies to
    -- p_package_id/p_new_parent_package_id above. Without this, two concurrent
    -- reparent calls whose locked row pairs are disjoint (e.g. reparent(A, new
    -- parent=D) and reparent(C, new parent=B), where each call's own ancestor
    -- walk only ever reads rows the other call hasn't locked) can each pass
    -- their own cycle check against pre-race state and both commit, together
    -- forming a real cycle -- reproduced live against two concurrent psql
    -- sessions prior to this fix. Locking every walked row instead means any
    -- such overlapping pair of concurrent reparents now contends on a real row
    -- lock somewhere in the two walks; Postgres's own deadlock detector aborts
    -- one of them (the caller sees a normal 'deadlock detected' error and can
    -- retry), and the survivor's walk always observes fully-committed state, so
    -- no cycle can ever be persisted.
    v_walk := v_new_parent;
    loop
      v_depth := v_depth + 1;
      if v_depth > 100 then
        raise exception 'cycle_rejected: package hierarchy exceeds the maximum supported depth (100) while checking for a cycle' using errcode = 'check_violation';
      end if;
      if v_walk.id = p_package_id then
        raise exception 'cycle_rejected: reparenting package % under % would create a cycle', p_package_id, p_new_parent_package_id using errcode = 'check_violation';
      end if;
      exit when v_walk.parent_package_id is null;
      select * into v_walk from app.wms_packages where id = v_walk.parent_package_id for update;
    end loop;
  end if;

  update app.wms_packages set parent_package_id = p_new_parent_package_id where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'reparent_wms_package',
    'app.wms_packages', v_package.id, 'success', null, null, jsonb_build_object('new_parent_package_id', p_new_parent_package_id)
  );

  return v_package;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reprint_label(p_label_instance_id uuid, p_printer_id uuid, p_copies integer, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.label_print_jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_label app.label_instances;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id;
  if not found or not app.has_active_tenant_membership(v_label.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_label.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_label.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.execute_label_print(p_label_instance_id, p_printer_id, p_copies, true, p_reason, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reverse_warehouse_billing_event(p_original_event_id uuid, p_expected_version integer, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_original app.warehouse_billing_events;
  v_existing app.warehouse_billing_events;
  v_new app.warehouse_billing_events;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to reverse a billing event' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reverse a billing event' using errcode = 'check_violation';
  end if;

  select * into v_original from app.warehouse_billing_events where id = p_original_event_id for update;
  if not found or not app.has_active_tenant_membership(v_original.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_billing_event_not_found: %', p_original_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_original.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_original.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_original.warehouse_id, v_original.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reverse billing event %', p_actor_auth_user_id, p_original_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_original.tenant_id, v_original.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_original_event_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before, and ALWAYS validating the found row's own real reverses_event_id matches.
  select * into v_existing from app.warehouse_billing_events where tenant_id = v_original.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.reverses_event_id = p_original_event_id then
      return v_existing;
    end if;
    raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reversal', p_idempotency_key using errcode = 'unique_violation';
  end if;

  if v_original.status not in ('approved', 'handed_off') then
    raise exception 'invalid_transition: billing event % is % -- only an approved or handed-off event may be reversed', p_original_event_id, v_original.status using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.warehouse_billing_events where reverses_event_id = p_original_event_id) then
    raise exception 'already_reversed: billing event % already has a reversing event', p_original_event_id using errcode = 'check_violation';
  end if;
  -- The established optimistic-concurrency contract every other lifecycle-mutating RPC
  -- in this migration applies (bug class b) -- see app.correct_warehouse_billing_event's
  -- own identical rationale.
  if v_original.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_original_event_id, p_expected_version, v_original.record_version using errcode = 'check_violation';
  end if;

  -- A reversal does NOT recalculate -- it exactly negates the original's own already-
  -- calculated values. status is inserted as pending_review, not draft: see this
  -- migration's own header design-decision note for why (skips calculate entirely,
  -- proceeds straight through review/approve/handoff, matching Prompt 241's own
  -- described cycle for a reversal and avoiding a structural risk of the negation
  -- being silently overwritten by a later calculate call).
  begin
    insert into app.warehouse_billing_events (
      tenant_id, warehouse_id, owner_account_id, activity_type, source_type, source_id, source_version,
      uom_code, activity_date, contract_id, rate_component_id, quantity,
      base_amount, tax_code, tax_rule_version_id, tax_amount, total_amount, currency, rounding_mode, calculation_explanation,
      status, reverses_event_id, correction_reason, idempotency_key, created_by
    ) values (
      v_original.tenant_id, v_original.warehouse_id, v_original.owner_account_id, v_original.activity_type, v_original.source_type, v_original.source_id, v_original.source_version,
      v_original.uom_code, v_original.activity_date, v_original.contract_id, v_original.rate_component_id, v_original.quantity,
      -v_original.base_amount, v_original.tax_code, v_original.tax_rule_version_id, -coalesce(v_original.tax_amount, 0), -v_original.total_amount, v_original.currency, v_original.rounding_mode,
      jsonb_build_object('reversalOfEventId', v_original.id, 'originalCalculationExplanation', v_original.calculation_explanation),
      'pending_review', p_original_event_id, p_reason, p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      select * into v_existing from app.warehouse_billing_events where tenant_id = v_original.tenant_id and idempotency_key = p_idempotency_key;
      if found and v_existing.reverses_event_id = p_original_event_id then
        return v_existing;
      end if;
      raise exception 'already_reversed: billing event % already has a reversing event (concurrent request)', p_original_event_id using errcode = 'check_violation';
  end;

  -- A lifecycle marker only -- mirrors app.correct_warehouse_billing_event's own
  -- identical "flip the original's status, never touch its own already-calculated
  -- amount columns" pattern. Without this, the original stays 'approved'/'handed_off'
  -- forever and can be legitimately handed off to Finance a second time after being
  -- reversed (the exact bug this statement closes).
  update app.warehouse_billing_events set status = 'reversed' where id = p_original_event_id and record_version = p_expected_version;

  perform app.capture_audit_event(
    v_original.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_warehouse_billing_event',
    'app.warehouse_billing_events', v_new.id, 'success', p_reason,
    jsonb_build_object('original_event_id', p_original_event_id, 'original_total_amount', v_original.total_amount),
    jsonb_build_object('new_total_amount', v_new.total_amount)
  );

  return v_new;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.set_label_printer_status(p_printer_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.label_printers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_printer app.label_printers;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid printer status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_printer from app.label_printers where id = p_printer_id for update;
  if not found or not app.has_active_tenant_membership(v_printer.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_printer_not_found: %', p_printer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_printer.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_printer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_printer.status = p_new_status then
    return v_printer;
  end if;

  if v_printer.record_version <> p_expected_version then
    raise exception 'stale_version: label printer % expected version % but found %', p_printer_id, p_expected_version, v_printer.record_version
      using errcode = 'check_violation';
  end if;
  if p_new_status = 'inactive' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to deactivate a printer' using errcode = 'check_violation';
  end if;

  update app.label_printers set status = p_new_status where id = p_printer_id returning * into v_printer;

  perform app.capture_audit_event(
    v_printer.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_label_printer_status',
    'app.label_printers', v_printer.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_printer;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.set_label_template_version_status(p_version_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.label_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.label_template_versions;
begin
  if p_new_status <> 'archived' then
    raise exception 'invalid_status_transition: this function only supports transitioning to archived -- use app.create_label_template_version_draft/app.publish_label_template_version for draft/published'
      using errcode = 'check_violation';
  end if;

  select * into v_version from app.label_template_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_template_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status = 'archived' then
    return v_version;
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: label template version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to archive a label template version' using errcode = 'check_violation';
  end if;

  update app.label_template_versions set status = 'archived' where id = p_version_id returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_label_template_version_status',
    'app.label_template_versions', v_version.id, 'success', p_reason, null, jsonb_build_object('new_status', 'archived')
  );

  return v_version;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.set_wms_shipment_dock_location(p_shipment_id uuid, p_dock_location_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
  v_location app.warehouse_locations;
begin
  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id for update;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_not_found: %', p_shipment_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_shipment.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_shipment.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit shipment %', p_actor_auth_user_id, p_shipment_id using errcode = 'insufficient_privilege';
  end if;
  if v_shipment.status <> 'staging' then
    raise exception 'shipment_not_staging: % is % -- the dock location is fixed once loading has physically occurred', p_shipment_id, v_shipment.status using errcode = 'check_violation';
  end if;
  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment % expected version % but found %', p_shipment_id, p_expected_version, v_shipment.record_version using errcode = 'check_violation';
  end if;

  select * into v_location from app.warehouse_locations where id = p_dock_location_id;
  if not found then
    raise exception 'location_not_found: %', p_dock_location_id using errcode = 'no_data_found';
  end if;
  if v_location.warehouse_id <> v_shipment.warehouse_id then
    raise exception 'incompatible_location: dock % does not belong to warehouse %', p_dock_location_id, v_shipment.warehouse_id using errcode = 'check_violation';
  end if;
  if v_location.location_type <> 'dock' then
    raise exception 'incompatible_location: % is a % -- a real dock location is required', p_dock_location_id, v_location.location_type using errcode = 'check_violation';
  end if;
  if v_location.status <> 'active' then
    raise exception 'blocked_destination: dock % is not active', p_dock_location_id using errcode = 'check_violation';
  end if;

  update app.wms_outbound_shipments set dock_location_id = p_dock_location_id where id = p_shipment_id returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_wms_shipment_dock_location',
    'app.wms_outbound_shipments', v_shipment.id, 'success', null, null, jsonb_build_object('dock_location_id', p_dock_location_id)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.set_wms_shipment_vehicle_ref(p_shipment_id uuid, p_vehicle_ref text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
begin
  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id for update;
  if not found or not app.has_active_tenant_membership(v_shipment.tenant_id, p_actor_auth_user_id) then
    raise exception 'shipment_not_found: %', p_shipment_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_shipment.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_shipment.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit shipment %', p_actor_auth_user_id, p_shipment_id using errcode = 'insufficient_privilege';
  end if;
  if v_shipment.status not in ('staging', 'loaded') then
    raise exception 'shipment_locked: % is % -- the vehicle reference may only change before ship-confirm', p_shipment_id, v_shipment.status using errcode = 'check_violation';
  end if;
  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment % expected version % but found %', p_shipment_id, p_expected_version, v_shipment.record_version using errcode = 'check_violation';
  end if;

  update app.wms_outbound_shipments set vehicle_ref = p_vehicle_ref where id = p_shipment_id returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_wms_shipment_vehicle_ref',
    'app.wms_outbound_shipments', v_shipment.id, 'success', null, null, jsonb_build_object('vehicle_ref', p_vehicle_ref)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.update_wms_outbound_order_line(p_line_id uuid, p_requested_quantity numeric, p_notes text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_order_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_outbound_order_lines;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_line from app.wms_outbound_order_lines where id = p_line_id for update;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  -- Design note 9(b): also lock the header row, so a concurrent confirm/cancel cannot
  -- flip status out of draft between this check and the line UPDATE below.
  select * into v_order from app.wms_outbound_orders where id = v_line.outbound_order_id for update;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  -- RBAC/record-scope checks run BEFORE the status check so an unauthorized (or
  -- cross-tenant) actor cannot learn the order's draft/non-draft state via the
  -- error-message oracle before authorization is established.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit outbound order %', p_actor_auth_user_id, v_order.id using errcode = 'insufficient_privilege';
  end if;

  if v_order.status <> 'draft' then
    raise exception 'outbound_not_draft: % is not draft -- lines may only change while draft', v_order.id using errcode = 'check_violation';
  end if;

  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version
      using errcode = 'check_violation';
  end if;
  if p_requested_quantity is null or p_requested_quantity <= 0 then
    raise exception 'invalid_quantity: requested_quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  update app.wms_outbound_order_lines set requested_quantity = p_requested_quantity, notes = p_notes
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_wms_outbound_order_line',
    'app.wms_outbound_order_lines', v_line.id, 'success', null, null,
    jsonb_build_object('requested_quantity', p_requested_quantity)
  );

  return v_line;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.void_label(p_label_instance_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.label_instances
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_label app.label_instances;
begin
  select * into v_label from app.label_instances where id = p_label_instance_id for update;
  if not found or not app.has_active_tenant_membership(v_label.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_instance_not_found: %', p_label_instance_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_label.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_label.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.label_subject_record_scope_ok(p_actor_auth_user_id, v_label.tenant_id, v_label.subject_type, v_label.subject_id) then
    raise exception 'insufficient_authority: identity % cannot void label %', p_actor_auth_user_id, p_label_instance_id using errcode = 'insufficient_privilege';
  end if;

  if v_label.status = 'void' then
    raise exception 'already_void: label instance % is already void', p_label_instance_id using errcode = 'check_violation';
  end if;

  if v_label.record_version <> p_expected_version then
    raise exception 'stale_version: label instance % expected version % but found %', p_label_instance_id, p_expected_version, v_label.record_version
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to void a label' using errcode = 'check_violation';
  end if;

  update app.label_instances set
    status = 'void',
    void_reason = p_reason,
    voided_by_auth_user_id = p_actor_auth_user_id,
    voided_by_label = p_actor_label,
    voided_at = now()
  where id = p_label_instance_id
  returning * into v_label;

  perform app.capture_audit_event(
    v_label.tenant_id, p_actor_auth_user_id, p_actor_label, 'void_label',
    'app.label_instances', v_label.id, 'success', p_reason, null, jsonb_build_object('new_status', 'void')
  );

  return v_label;
end;
$function$
;
