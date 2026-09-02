-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 2 of 4 -- WMS and warehouse master data: inbound/putaway/picking/packing/outbound, inventory reservations, warehouse & item masters, and warehouse billing events
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
-- 41 functions in this part. Every definition below is CREATE OR REPLACE against the
-- function's CURRENT live body -- the last migration that defines it, verified per
-- function, not an earlier superseded text. Signatures, volatility, security attribute and
-- search_path are copied verbatim and unchanged, so grants are unaffected.


-- app.add_package_to_shipment
create or replace function app.add_package_to_shipment(p_shipment_id uuid, p_package_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
  v_package app.wms_packages;
  v_existing app.wms_shipment_packages;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to add a package to a shipment' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
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

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_shipment_packages where tenant_id = v_shipment.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.shipment_id <> p_shipment_id or v_existing.package_id <> p_package_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment package link (shipment %/package %, not shipment %/package %)', p_idempotency_key, v_existing.shipment_id, v_existing.package_id, p_shipment_id, p_package_id
        using errcode = 'unique_violation';
    end if;
    return v_shipment;
  end if;

  if v_shipment.status <> 'staging' then
    raise exception 'shipment_not_staging: % is % -- packages may only be added while staging', p_shipment_id, v_shipment.status using errcode = 'check_violation';
  end if;

  -- Design note 5/bug class (e)'s own second instance: locking the package row here
  -- serializes any concurrent add-attempt against the SAME package (whether targeting
  -- this shipment or a different one) before the "already staged elsewhere" check below.
  select * into v_package from app.wms_packages where id = p_package_id and tenant_id = v_shipment.tenant_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  if v_package.status <> 'confirmed' then
    raise exception 'package_not_confirmed: package % is % -- only a confirmed package may be staged for shipment', p_package_id, v_package.status using errcode = 'check_violation';
  end if;
  if v_package.outbound_order_id <> v_shipment.outbound_order_id then
    raise exception 'wrong_order: package % belongs to outbound order %, not this shipment''s own outbound order %', p_package_id, v_package.outbound_order_id, v_shipment.outbound_order_id
      using errcode = 'check_violation';
  end if;
  if v_package.owner_account_id <> v_shipment.owner_account_id then
    raise exception 'wrong_owner: package % belongs to owner account %, not this shipment''s own owner account %', p_package_id, v_package.owner_account_id, v_shipment.owner_account_id
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.wms_shipment_packages where package_id = p_package_id) then
    raise exception 'package_already_staged: package % is already staged for a different shipment', p_package_id using errcode = 'check_violation';
  end if;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_shipment_packages (tenant_id, shipment_id, package_id, idempotency_key, added_by_auth_user_id, added_by_label)
    values (v_shipment.tenant_id, p_shipment_id, p_package_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
  exception
    when unique_violation then
      -- Either this exact idempotency key won a genuine race (return the shipment
      -- unchanged, matching the ordinary replay path) or the package_id unique guard
      -- fired (a genuine double-stage race) -- distinguish and respond accordingly.
      select * into v_existing from app.wms_shipment_packages where tenant_id = v_shipment.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
        -- replay -- returning the earlier target's own row here silently misattributed
        -- this request to it (or silently discarded it entirely).
        if v_existing.shipment_id <> p_shipment_id or v_existing.package_id <> p_package_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment package link (shipment %/package %, not shipment %/package %)', p_idempotency_key, v_existing.shipment_id, v_existing.package_id, p_shipment_id, p_package_id
            using errcode = 'unique_violation';
        end if;
        return v_shipment;
      end if;
      raise exception 'package_already_staged: package % is already staged for a different shipment', p_package_id using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_package_to_shipment',
    'app.wms_outbound_shipments', v_shipment.id, 'success', null, null, jsonb_build_object('package_id', p_package_id)
  );

  return v_shipment;
end;
$function$;


-- app.add_wms_package_line
create or replace function app.add_wms_package_line(p_package_id uuid, p_pick_task_id uuid, p_quantity numeric, p_scanned_item_master_id uuid, p_scanned_lot_number text, p_scanned_serial_number text, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_packing_task app.wms_packing_tasks;
  v_task app.wms_pick_tasks;
  v_existing_scan app.wms_package_line_scans;
  v_already_packed numeric;
  v_remaining_packable numeric;
  v_line app.wms_package_lines;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to add a package line' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  -- Package locked BEFORE the pick task (design note 3''s own deliberate lock order).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found or not app.has_active_tenant_membership(v_package.tenant_id, p_actor_auth_user_id) then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;
  select * into v_packing_task from app.wms_packing_tasks where id = v_package.packing_task_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot add a line to package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing_scan from app.wms_package_line_scans where tenant_id = v_package.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing_scan.package_id <> p_package_id or v_existing_scan.event_type <> 'add' then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different package line scan (package %/event %, not package %/event add)', p_idempotency_key, v_existing_scan.package_id, v_existing_scan.event_type, p_package_id
        using errcode = 'unique_violation';
    end if;
    return v_package;
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: line quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  -- Design note 3 / bug class (e): the pick task row is locked FOR UPDATE from this
  -- point, held through the aggregate read and the line insert/update below --
  -- exactly mirroring app.generate_wms_pick_task''s own outbound-order-line lock.
  select * into v_task from app.wms_pick_tasks where id = p_pick_task_id for update;
  if not found or v_task.tenant_id <> v_package.tenant_id then
    raise exception 'task_not_found: %', p_pick_task_id using errcode = 'no_data_found';
  end if;

  -- Design note 4: wrong order / wrong owner -- defense-in-depth, both checked
  -- explicitly rather than relying on one implying the other.
  if v_task.outbound_order_id <> v_packing_task.outbound_order_id then
    raise exception 'wrong_order: pick task % belongs to outbound order %, not this package''s own outbound order %', p_pick_task_id, v_task.outbound_order_id, v_packing_task.outbound_order_id
      using errcode = 'check_violation';
  end if;
  if v_task.owner_account_id <> v_package.owner_account_id then
    raise exception 'wrong_owner: pick task % belongs to owner account %, not this package''s own owner account %', p_pick_task_id, v_task.owner_account_id, v_package.owner_account_id
      using errcode = 'check_violation';
  end if;

  if p_scanned_item_master_id is distinct from v_task.item_master_id then
    raise exception 'item_mismatch: scanned item % does not match pick task %''s own item %', p_scanned_item_master_id, p_pick_task_id, v_task.item_master_id using errcode = 'check_violation';
  end if;
  if v_task.lot_controlled and coalesce(p_scanned_lot_number, '') <> coalesce(v_task.lot_number, '') then
    if p_scanned_lot_number is null then
      raise exception 'missing_lot: pick task % is lot-controlled (lot %) -- a matching lot number is required', p_pick_task_id, v_task.lot_number using errcode = 'check_violation';
    end if;
    raise exception 'lot_mismatch: scanned lot % does not match pick task %''s own lot %', p_scanned_lot_number, p_pick_task_id, v_task.lot_number using errcode = 'check_violation';
  end if;
  if v_task.serial_controlled and coalesce(p_scanned_serial_number, '') <> coalesce(v_task.serial_number, '') then
    if p_scanned_serial_number is null then
      raise exception 'missing_serial: pick task % is serial-controlled (serial %) -- a matching serial number is required', p_pick_task_id, v_task.serial_number using errcode = 'check_violation';
    end if;
    raise exception 'serial_mismatch: scanned serial % does not match pick task %''s own serial %', p_scanned_serial_number, p_pick_task_id, v_task.serial_number using errcode = 'check_violation';
  end if;

  -- The headline aggregate, computed strictly under the task lock above (design note 3):
  -- how much of this task has already been packed, across ALL packages, not merely
  -- this one.
  select coalesce(sum(quantity), 0) into v_already_packed from app.wms_package_lines where pick_task_id = p_pick_task_id;
  v_remaining_packable := v_task.picked_quantity - v_already_packed;
  if p_quantity > v_remaining_packable then
    raise exception 'over_pack_rejected: % of % picked units remain unpacked for pick task %, requested %', v_remaining_packable, v_task.picked_quantity, p_pick_task_id, p_quantity
      using errcode = 'check_violation';
  end if;

  select * into v_line from app.wms_package_lines where package_id = p_package_id and pick_task_id = p_pick_task_id for update;
  if found then
    update app.wms_package_lines set quantity = quantity + p_quantity where id = v_line.id;
  else
    -- Bug class (d): a nested begin/exception unique_violation recovery.
    begin
      insert into app.wms_package_lines (
        tenant_id, package_id, pick_task_id, owner_account_id, item_master_id, uom_code, lot_number, serial_number, expiry_date, quantity, first_added_by_auth_user_id, first_added_by_label
      ) values (
        v_package.tenant_id, p_package_id, p_pick_task_id, v_task.owner_account_id, v_task.item_master_id, v_task.uom_code, v_task.lot_number, v_task.serial_number, v_task.expiry_date, p_quantity, p_actor_auth_user_id, p_actor_label
      );
    exception
      when unique_violation then
        update app.wms_package_lines set quantity = quantity + p_quantity where package_id = p_package_id and pick_task_id = p_pick_task_id;
    end;
  end if;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_package_line_scans (
      tenant_id, package_id, pick_task_id, event_type, quantity, scanned_item_master_id, scanned_lot_number, scanned_serial_number, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_package.tenant_id, p_package_id, p_pick_task_id, 'add', p_quantity, p_scanned_item_master_id, p_scanned_lot_number, p_scanned_serial_number, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent add-line request', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_packages set
    line_count = (select count(*) from app.wms_package_lines where package_id = p_package_id),
    total_packed_quantity = (select coalesce(sum(quantity), 0) from app.wms_package_lines where package_id = p_package_id)
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_wms_package_line',
    'app.wms_packages', v_package.id, 'success', null, null,
    jsonb_build_object('pick_task_id', p_pick_task_id, 'quantity', p_quantity)
  );

  return v_package;
end;
$function$;


-- app.approve_wms_pick_substitution
create or replace function app.approve_wms_pick_substitution(p_task_id uuid, p_substitute_item_master_id uuid, p_location_id uuid, p_lot_number text, p_serial_number text, p_reason text, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_pick_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
  v_existing app.wms_pick_substitution_approvals;
  v_substitute app.item_masters;
  v_lot app.lot_identities;
  v_serial app.serial_identities;
  v_loc_pick_enabled boolean;
  v_loc_status text;
  v_loc_warehouse_id uuid;
  v_candidate record;
  v_resolved_location_id uuid;
  v_resolved_lot_number text;
  v_resolved_serial_number text;
  v_resolved_expiry_date date;
  v_new_reservation app.inventory_reservations;
  v_approval app.wms_pick_substitution_approvals;
  v_original_item_master_id uuid;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to approve a pick substitution' using errcode = 'check_violation';
  end if;

  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found or not app.has_active_tenant_membership(v_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  -- Design note 9: OPS:Override-gated -- supervisor-only.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot override pick task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_pick_substitution_approvals where tenant_id = v_task.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.task_id <> p_task_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different substitution approval (task %, not %)', p_idempotency_key, v_existing.task_id, p_task_id
        using errcode = 'unique_violation';
    end if;
    return v_task;
  end if;

  -- Design note 9: only while a task has genuinely zero progress.
  if v_task.status not in ('unclaimed', 'claimed') or v_task.picked_quantity > 0 or v_task.short_quantity > 0 then
    raise exception 'substitution_not_allowed: task % is % (picked=%/short=%) -- a substitution may only be approved before any real progress', p_task_id, v_task.status, v_task.picked_quantity, v_task.short_quantity
      using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: pick task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to approve a pick substitution' using errcode = 'check_violation';
  end if;
  if p_substitute_item_master_id = v_task.item_master_id then
    raise exception 'invalid_substitution: substitute item % must differ from the task''s own current item', p_substitute_item_master_id using errcode = 'check_violation';
  end if;

  select * into v_substitute from app.item_masters
    where id = p_substitute_item_master_id and tenant_id = v_task.tenant_id and owner_account_id = v_task.owner_account_id and status = 'active';
  if not found then
    raise exception 'substitute_item_not_eligible: % is not an active item master owned by the task''s own account', p_substitute_item_master_id using errcode = 'check_violation';
  end if;
  if v_substitute.base_uom_code <> v_task.uom_code then
    raise exception 'substitute_item_not_eligible: substitute item % base UOM % does not match task uom %', p_substitute_item_master_id, v_substitute.base_uom_code, v_task.uom_code using errcode = 'check_violation';
  end if;

  -- Resolve the substitute source -- identical caller-supplied/auto-select shape and
  -- eligibility re-verification as app.generate_wms_pick_task (design note 10/11).
  if p_location_id is not null then
    select pick_enabled, status, warehouse_id into v_loc_pick_enabled, v_loc_status, v_loc_warehouse_id from app.warehouse_locations where id = p_location_id;
    if v_loc_warehouse_id is null or v_loc_warehouse_id <> v_task.warehouse_id then
      raise exception 'location_not_eligible: % is not a location of warehouse %', p_location_id, v_task.warehouse_id using errcode = 'check_violation';
    end if;
    if not v_loc_pick_enabled then
      raise exception 'location_not_eligible: % is not pick_enabled', p_location_id using errcode = 'check_violation';
    end if;
    if v_loc_status <> 'active' then
      raise exception 'blocked_location: % is not active', p_location_id using errcode = 'check_violation';
    end if;
    if not exists (
      select 1 from app.inventory_balances b
      where b.tenant_id = v_task.tenant_id and b.warehouse_id = v_task.warehouse_id and b.owner_account_id = v_task.owner_account_id
        and b.item_master_id = p_substitute_item_master_id and b.location_id = p_location_id
        and coalesce(b.lot_number, '') = coalesce(p_lot_number, '') and coalesce(b.serial_number, '') = coalesce(p_serial_number, '')
        and b.status = 'on_hand' and b.available >= v_task.task_quantity
    ) then
      raise exception 'balance_not_found: no on-hand balance with sufficient available stock exists for the requested substitute pick dimension' using errcode = 'no_data_found';
    end if;
    if p_lot_number is not null then
      select * into v_lot from app.lot_identities where tenant_id = v_task.tenant_id and owner_account_id = v_task.owner_account_id and item_master_id = p_substitute_item_master_id and lot_number = p_lot_number;
      if found and (v_lot.status <> 'active' or (v_lot.expiry_date is not null and v_lot.expiry_date < current_date)) then
        raise exception 'ineligible_stock: lot % is % (or expired) -- not eligible for picking', p_lot_number, v_lot.status using errcode = 'check_violation';
      end if;
    end if;
    if p_serial_number is not null then
      select * into v_serial from app.serial_identities where tenant_id = v_task.tenant_id and owner_account_id = v_task.owner_account_id and item_master_id = p_substitute_item_master_id and serial_number = p_serial_number;
      if found and (v_serial.status <> 'active' or (v_serial.expiry_date is not null and v_serial.expiry_date < current_date)) then
        raise exception 'ineligible_stock: serial % is % (or expired) -- not eligible for picking', p_serial_number, v_serial.status using errcode = 'check_violation';
      end if;
    end if;
    v_resolved_location_id := p_location_id;
    v_resolved_lot_number := p_lot_number;
    v_resolved_serial_number := p_serial_number;
    v_resolved_expiry_date := coalesce(v_lot.expiry_date, v_serial.expiry_date);
  else
    for v_candidate in
      select * from app.list_allocation_candidates(v_task.tenant_id, v_task.warehouse_id, p_substitute_item_master_id, v_task.owner_account_id, p_actor_auth_user_id, null, 20)
    loop
      if v_candidate.available < v_task.task_quantity then
        continue;
      end if;
      select pick_enabled, status into v_loc_pick_enabled, v_loc_status from app.warehouse_locations where id = v_candidate.location_id;
      if v_loc_pick_enabled and v_loc_status = 'active' then
        v_resolved_location_id := v_candidate.location_id;
        v_resolved_lot_number := v_candidate.lot_number;
        v_resolved_serial_number := v_candidate.serial_number;
        v_resolved_expiry_date := v_candidate.expiry_date;
        exit;
      end if;
    end loop;
    if v_resolved_location_id is null then
      raise exception 'no_eligible_pick_location: no eligible substitute candidate with sufficient available stock found for item % under warehouse %', p_substitute_item_master_id, v_task.warehouse_id
        using errcode = 'no_data_found';
    end if;
  end if;

  -- Release the original reservation in full (design note 8/9 -- safe here for the
  -- identical zero-progress reason), then reserve fresh stock against the substitute.
  perform app.release_inventory_reservation(v_task.reservation_id, 'substituted: ' || p_reason, p_actor_auth_user_id, p_actor_label);

  v_new_reservation := app.reserve_inventory(
    v_task.tenant_id, v_task.warehouse_id, v_task.owner_account_id, p_substitute_item_master_id,
    v_resolved_location_id, v_resolved_lot_number, v_resolved_serial_number, v_task.task_quantity,
    'wms_outbound_order', v_task.outbound_order_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );

  v_original_item_master_id := coalesce(v_task.substituted_from_item_master_id, v_task.item_master_id);

  -- Real defect found and fixed by adversarial review (design note 0b): identical
  -- reasoning as the two inserts above -- the original reservation has already been
  -- released and a fresh one reserved (via app.reserve_inventory, itself now hardened
  -- the same way) for THIS task; a conflicting key here can only mean p_idempotency_key
  -- was reused across a different (different-task) substitution approval, so a clean,
  -- classified exception aborts and rolls back this call's own release/re-reserve
  -- together with the failed insert.
  begin
    insert into app.wms_pick_substitution_approvals (
      tenant_id, task_id, original_item_master_id, substitute_item_master_id, original_reservation_id, new_reservation_id, reason, idempotency_key, approved_by_auth_user_id, approved_by_label
    ) values (
      v_task.tenant_id, p_task_id, v_task.item_master_id, p_substitute_item_master_id, v_task.reservation_id, v_new_reservation.id, p_reason, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    )
    returning * into v_approval;
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent substitution approval request', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_pick_tasks set
    item_master_id = p_substitute_item_master_id,
    lot_controlled = v_substitute.lot_controlled,
    serial_controlled = v_substitute.serial_controlled,
    expiry_controlled = v_substitute.expiry_controlled,
    source_location_id = v_resolved_location_id,
    lot_number = v_resolved_lot_number,
    serial_number = v_resolved_serial_number,
    expiry_date = v_resolved_expiry_date,
    reservation_id = v_new_reservation.id,
    substituted_from_item_master_id = v_original_item_master_id
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_wms_pick_substitution',
    'app.wms_pick_tasks', v_task.id, 'success', p_reason, null,
    jsonb_build_object('original_item_master_id', v_original_item_master_id, 'substitute_item_master_id', p_substitute_item_master_id, 'approval_id', v_approval.id)
  );

  return v_task;
end;
$function$;


-- app.calculate_warehouse_billing_event
create or replace function app.calculate_warehouse_billing_event(p_event_id uuid, p_expected_version integer, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
  v_rate app.warehouse_billing_rate_components;
  v_calc jsonb;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found or not app.has_active_tenant_membership(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'draft' then
    raise exception 'already_calculated: billing event % is % -- use app.recalculate_warehouse_billing_event instead', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  -- as_of = the event's own activity_date, never now() (Prompt 241's own explicit rule).
  v_rate := app.get_effective_warehouse_billing_rate(v_event.tenant_id, v_event.owner_account_id, v_event.warehouse_id, v_event.activity_type, v_event.activity_date, p_actor_auth_user_id);
  v_calc := app.compute_warehouse_billing_breakdown(v_event.tenant_id, v_rate, v_event.quantity, v_event.uom_code, v_event.activity_date, p_tax_code, p_actor_auth_user_id);

  update app.warehouse_billing_events set
    contract_id = v_rate.contract_id,
    rate_component_id = v_rate.id,
    base_amount = (v_calc ->> 'baseAmount')::numeric,
    tax_code = p_tax_code,
    tax_rule_version_id = (v_calc ->> 'taxRuleVersionId')::uuid,
    tax_amount = (v_calc ->> 'taxAmount')::numeric,
    total_amount = (v_calc ->> 'totalAmount')::numeric,
    currency = v_calc ->> 'currency',
    rounding_mode = v_calc ->> 'roundingMode',
    calculation_explanation = v_calc -> 'calculationExplanation',
    status = 'pending_review'
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: calculate_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null,
    jsonb_build_object('total_amount', v_event.total_amount, 'contract_id', v_event.contract_id, 'rate_component_id', v_event.rate_component_id)
  );

  return v_event;
end;
$function$
;


-- app.cancel_wms_inbound
create or replace function app.cancel_wms_inbound(p_inbound_order_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status = 'cancelled' then
    return v_order;
  end if;

  if exists (select 1 from app.wms_receipt_sessions where inbound_order_id = p_inbound_order_id and status <> 'cancelled') then
    raise exception 'has_receipt_progress: inbound order % has an active or completed receipt session -- cancel or reconcile it first', p_inbound_order_id
      using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel an inbound order' using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set status = 'cancelled', cancelled_reason = p_reason where id = p_inbound_order_id returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_inbound',
    'app.wms_inbound_orders', v_order.id, 'success', p_reason, null, null
  );

  return v_order;
end;
$function$;


-- app.confirm_wms_inbound
create or replace function app.confirm_wms_inbound(p_inbound_order_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_readiness app.wms_inbound_readiness;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status <> 'scheduled' then
    raise exception 'invalid_transition: % must be scheduled to confirm, is %', p_inbound_order_id, v_order.status using errcode = 'check_violation';
  end if;

  v_readiness := app.get_wms_inbound_readiness(p_inbound_order_id, p_actor_auth_user_id);
  if not v_readiness.ready then
    raise exception 'inbound_not_ready: % is not ready to confirm (has_lines=%, warehouse_active=%, owner_active=%, invalid_line_count=%)',
      p_inbound_order_id, v_readiness.has_lines, v_readiness.warehouse_active, v_readiness.owner_active, v_readiness.invalid_line_count
      using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set status = 'confirmed' where id = p_inbound_order_id returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_wms_inbound',
    'app.wms_inbound_orders', v_order.id, 'success', null, null, null
  );

  return v_order;
end;
$function$;


-- app.confirm_wms_package
create or replace function app.confirm_wms_package(p_package_id uuid, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_existing_confirmation app.wms_package_confirmations;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to confirm a package' using errcode = 'check_violation';
  end if;

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
    raise exception 'insufficient_authority: identity % cannot confirm package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing_confirmation from app.wms_package_confirmations where tenant_id = v_package.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing_confirmation.package_id <> p_package_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different package confirmation (package %, not %)', p_idempotency_key, v_existing_confirmation.package_id, p_package_id
        using errcode = 'unique_violation';
    end if;
    return v_package;
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'package_already_confirmed: package % has already been confirmed', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;

  if v_package.line_count = 0 then
    raise exception 'empty_package_rejected: package % has no packed contents', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.weight_value is null then
    raise exception 'missing_measurement: package % has no recorded weight -- record measurements before confirming', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.qc_status <> 'pass' and v_package.qc_override_at is null then
    if v_package.qc_status = 'pending' then
      raise exception 'missing_qc: package % has not yet been QC-inspected', p_package_id using errcode = 'check_violation';
    end if;
    raise exception 'qc_hold_unresolved: package % QC outcome is % -- resolve or override before confirming', p_package_id, v_package.qc_status using errcode = 'check_violation';
  end if;
  if v_package.parent_package_id is null and (v_package.seal_number is null or length(trim(v_package.seal_number)) = 0) then
    raise exception 'missing_seal: root package % has no recorded seal', p_package_id using errcode = 'check_violation';
  end if;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_package_confirmations (tenant_id, package_id, idempotency_key, line_count_snapshot, total_quantity_snapshot, confirmed_by_auth_user_id, confirmed_by_label)
    values (v_package.tenant_id, p_package_id, p_idempotency_key, v_package.line_count, v_package.total_packed_quantity, p_actor_auth_user_id, p_actor_label);
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent confirm request', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_packages set status = 'confirmed', confirmed_at = now(), confirmed_by_auth_user_id = p_actor_auth_user_id, confirmed_by_label = p_actor_label
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_wms_package',
    'app.wms_packages', v_package.id, 'success', null, null,
    jsonb_build_object('line_count', v_package.line_count, 'total_packed_quantity', v_package.total_packed_quantity)
  );

  return v_package;
end;
$function$;


-- app.confirm_wms_pick_task
create or replace function app.confirm_wms_pick_task(p_task_id uuid, p_quantity numeric, p_scanned_location_id uuid, p_scanned_item_master_id uuid, p_scanned_lot_number text, p_scanned_serial_number text, p_actual_destination_location_id uuid, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_pick_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
  v_existing_confirmation app.wms_pick_task_confirmations;
  v_destination app.warehouse_locations;
  v_occupied numeric;
  v_reservation app.inventory_reservations;
  v_balance app.inventory_balances;
  v_movement app.inventory_movements;
  v_new_picked numeric;
  v_new_remaining numeric;
  v_new_status text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to confirm a pick task' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE (FOR UPDATE) -- bug
  -- class (b)/(c).
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
    raise exception 'insufficient_authority: identity % cannot confirm pick task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a). Per-confirm-event idempotency.
  select * into v_existing_confirmation from app.wms_pick_task_confirmations where tenant_id = v_task.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing_confirmation.task_id <> p_task_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different pick confirmation (task %, not %)', p_idempotency_key, v_existing_confirmation.task_id, p_task_id
        using errcode = 'unique_violation';
    end if;
    return v_task;
  end if;

  if v_task.status = 'unclaimed' then
    raise exception 'task_not_claimed: task % must be claimed before it can be confirmed', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.status in ('picked', 'short') then
    raise exception 'task_already_resolved: task % has already been fully resolved (%)', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if v_task.status = 'exception' then
    raise exception 'task_exception: task % is under an unresolved exception -- reassign it before confirming', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.status = 'cancelled' then
    raise exception 'task_cancelled: task % has been cancelled', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.claimed_by_auth_user_id <> p_actor_auth_user_id then
    raise exception 'not_task_claimant: identity % is not the assigned claimant of task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: pick task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: confirm quantity must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_quantity > v_task.remaining_quantity then
    raise exception 'exceeds_remaining_quantity: task % has % remaining but % was requested', p_task_id, v_task.remaining_quantity, p_quantity using errcode = 'check_violation';
  end if;

  -- Design note 7: the source is always scan-verified (unlike putaway, a pick task''s
  -- source is fixed/authoritative from generation, design note 10).
  if p_scanned_location_id is distinct from v_task.source_location_id then
    raise exception 'location_mismatch: scanned location % does not match task %''s own source location %', p_scanned_location_id, p_task_id, v_task.source_location_id using errcode = 'check_violation';
  end if;
  -- Real defect found and fixed by adversarial review: app.warehouse_locations carries
  -- no item/SKU binding and app.inventory_balances allows multiple distinct
  -- item_master_id rows to share one location_id (a picking rack routinely holds
  -- several different items in the same bin) -- verifying the scanned LOCATION alone
  -- never proves the picker actually grabbed the task''s own ITEM out of that bin. A
  -- required, exact-matching scanned item id closes this -- Prompt 236 section 21''s own
  -- main-flow "scans exact location/item/control IDs/quantity" and section 23''s own
  -- exception flow "block ... wrong location/item/lot/serial/owner" both name item
  -- explicitly alongside location/lot/serial.
  if p_scanned_item_master_id is distinct from v_task.item_master_id then
    raise exception 'item_mismatch: scanned item % does not match task %''s own item %', p_scanned_item_master_id, p_task_id, v_task.item_master_id using errcode = 'check_violation';
  end if;
  if v_task.lot_controlled and coalesce(p_scanned_lot_number, '') <> coalesce(v_task.lot_number, '') then
    if p_scanned_lot_number is null then
      raise exception 'missing_lot: task % is lot-controlled (lot %) -- a matching lot number is required', p_task_id, v_task.lot_number using errcode = 'check_violation';
    end if;
    raise exception 'lot_mismatch: scanned lot % does not match task %''s own lot %', p_scanned_lot_number, p_task_id, v_task.lot_number using errcode = 'check_violation';
  end if;
  if v_task.serial_controlled and coalesce(p_scanned_serial_number, '') <> coalesce(v_task.serial_number, '') then
    if p_scanned_serial_number is null then
      raise exception 'missing_serial: task % is serial-controlled (serial %) -- a matching serial number is required', p_task_id, v_task.serial_number using errcode = 'check_violation';
    end if;
    raise exception 'serial_mismatch: scanned serial % does not match task %''s own serial %', p_scanned_serial_number, p_task_id, v_task.serial_number using errcode = 'check_violation';
  end if;

  -- Destination validation: the one authoritative check in this capability (design
  -- note 10, mirrors app.confirm_wms_putaway_task's own design note 5).
  if v_task.actual_destination_location_id is not null then
    if p_actual_destination_location_id <> v_task.actual_destination_location_id then
      raise exception 'destination_mismatch: task % has already begun picking to %, cannot confirm against a different location %', p_task_id, v_task.actual_destination_location_id, p_actual_destination_location_id
        using errcode = 'check_violation';
    end if;
    select * into v_destination from app.warehouse_locations where id = p_actual_destination_location_id for update;
    if not found then
      raise exception 'location_not_found: %', p_actual_destination_location_id using errcode = 'no_data_found';
    end if;
  else
    select * into v_destination from app.warehouse_locations where id = p_actual_destination_location_id for update;
    if not found then
      raise exception 'location_not_found: %', p_actual_destination_location_id using errcode = 'no_data_found';
    end if;
    if v_destination.warehouse_id <> v_task.warehouse_id then
      raise exception 'incompatible_location: destination % does not belong to warehouse %', p_actual_destination_location_id, v_task.warehouse_id using errcode = 'check_violation';
    end if;
    if v_destination.location_type <> 'staging' then
      raise exception 'incompatible_location: destination % is a % -- picked stock must land on a staging location, never a final rack/shelf/bin/dock/floor', p_actual_destination_location_id, v_destination.location_type
        using errcode = 'check_violation';
    end if;
    if v_destination.status <> 'active' then
      raise exception 'blocked_destination: destination % is not active', p_actual_destination_location_id using errcode = 'check_violation';
    end if;
  end if;

  if v_destination.capacity_value is not null then
    select coalesce(sum(on_hand), 0) into v_occupied from app.inventory_balances where location_id = p_actual_destination_location_id and status = 'on_hand';
    if v_occupied + p_quantity > v_destination.capacity_value then
      raise exception 'destination_full: destination % has % of % capacity occupied -- % more would exceed it', p_actual_destination_location_id, v_occupied, v_destination.capacity_value, p_quantity
        using errcode = 'check_violation';
    end if;
  end if;

  -- Design note 4: the exact statement order the reservation/transfer interaction
  -- requires -- reduce reserved FIRST, then post the transfer.
  select * into v_reservation from app.inventory_reservations where id = v_task.reservation_id for update;
  select * into v_balance from app.inventory_balances where id = v_reservation.balance_id for update;

  update app.inventory_balances set reserved = reserved - p_quantity where id = v_balance.id;

  v_movement := app.post_inventory_movement(
    v_task.tenant_id, v_task.warehouse_id, 'transfer', 'wms_outbound_order', v_task.outbound_order_id, p_idempotency_key,
    'pick task ' || p_task_id::text,
    jsonb_build_array(
      jsonb_build_object('owner_account_id', v_task.owner_account_id, 'item_master_id', v_task.item_master_id, 'location_id', v_task.source_location_id,
        'uom_code', v_task.uom_code, 'signed_quantity', -p_quantity, 'lot_number', v_task.lot_number, 'serial_number', v_task.serial_number, 'expiry_date', v_task.expiry_date, 'status', 'on_hand'),
      jsonb_build_object('owner_account_id', v_task.owner_account_id, 'item_master_id', v_task.item_master_id, 'location_id', p_actual_destination_location_id,
        'uom_code', v_task.uom_code, 'signed_quantity', p_quantity, 'lot_number', v_task.lot_number, 'serial_number', v_task.serial_number, 'expiry_date', v_task.expiry_date, 'status', 'on_hand')
    ),
    p_actor_auth_user_id, p_actor_label
  );

  -- Real defect found and fixed by adversarial review (design note 0b): this create-once
  -- insert had no unique_violation recovery at all. By this point the reserved-balance
  -- decrement and the real transfer movement above have already been posted for THIS
  -- task under p_idempotency_key -- a conflicting key here can only mean the caller
  -- reused p_idempotency_key across a genuinely different confirm request (a different
  -- task, since the task row itself is locked FOR UPDATE from the top of this function),
  -- never a safe same-request retry (that case is already caught by the idempotent
  -- replay short-circuit above, before any mutation runs). Raising a clean, classified
  -- exception here aborts this call's own enclosing transaction, cleanly rolling back
  -- the balance decrement and posted movement together with the failed insert -- no
  -- partial ledger effect survives.
  begin
    insert into app.wms_pick_task_confirmations (
      tenant_id, task_id, idempotency_key, quantity, scanned_location_id, scanned_item_master_id, scanned_lot_number, scanned_serial_number, actual_destination_location_id, movement_id, confirmed_by_auth_user_id, confirmed_by_label
    ) values (
      v_task.tenant_id, p_task_id, p_idempotency_key, p_quantity, p_scanned_location_id, p_scanned_item_master_id, p_scanned_lot_number, p_scanned_serial_number, p_actual_destination_location_id, v_movement.id, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent confirm request', p_idempotency_key using errcode = 'unique_violation';
  end;

  v_new_picked := v_task.picked_quantity + p_quantity;
  v_new_remaining := v_task.task_quantity - v_new_picked - v_task.short_quantity;
  v_new_status := case when v_new_remaining <= 0 then (case when v_task.short_quantity > 0 then 'short' else 'picked' end) else 'partial' end;

  update app.wms_pick_tasks set
    picked_quantity = v_new_picked, actual_destination_location_id = p_actual_destination_location_id, status = v_new_status
  where id = p_task_id
  returning * into v_task;

  if v_new_status in ('picked', 'short') then
    -- Design note 5: a raw terminal-status UPDATE, never the shared app.release_
    -- inventory_reservation (which would re-decrement the FULL original amount).
    update app.inventory_reservations set status = 'released', released_reason = 'wms_pick_task_resolved: picked=' || v_new_picked || ' short=' || v_task.short_quantity
      where id = v_reservation.id and status = 'active';
  end if;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_wms_pick_task',
    'app.wms_pick_tasks', v_task.id, 'success', null, null,
    jsonb_build_object('quantity', p_quantity, 'actual_destination_location_id', p_actual_destination_location_id, 'movement_id', v_movement.id, 'status', v_task.status)
  );

  return v_task;
end;
$function$;


-- app.confirm_wms_putaway_task
create or replace function app.confirm_wms_putaway_task(p_task_id uuid, p_quantity numeric, p_actual_location_id uuid, p_lot_number text, p_serial_number text, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_putaway_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
  v_existing_confirmation app.wms_putaway_confirmations;
  v_destination app.warehouse_locations;
  v_occupied numeric;
  v_new_confirmed numeric;
  v_new_status text;
  v_movement app.inventory_movements;
  v_inbound_order_id uuid;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to confirm a putaway task' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final INSERT/UPDATE (FOR UPDATE) --
  -- a second concurrent confirm on the same task cannot read the pre-confirm
  -- confirmed_quantity, post its own transfer movement and race the first caller past
  -- task_quantity (design note (b)/(c)); it blocks until the first transaction
  -- commits, then observes the updated confirmed_quantity/status.
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
    raise exception 'insufficient_authority: identity % cannot confirm putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is confirmed
  -- above, never before (design note (a)). Per-confirm-event idempotency (design
  -- note 2): a same-idempotency-key retry (e.g. a client resend after a slow/
  -- timed-out first response) returns the current task state unchanged, never posts
  -- a second transfer movement.
  select * into v_existing_confirmation from app.wms_putaway_confirmations where tenant_id = v_task.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing_confirmation.task_id <> p_task_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different putaway confirmation (task %, not %)', p_idempotency_key, v_existing_confirmation.task_id, p_task_id
        using errcode = 'unique_violation';
    end if;
    return v_task;
  end if;

  if v_task.status = 'unclaimed' then
    raise exception 'task_not_claimed: task % must be claimed before it can be confirmed', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.status = 'confirmed' then
    raise exception 'task_already_confirmed: task % has already been fully confirmed', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.status = 'exception' then
    raise exception 'task_exception: task % is under an unresolved exception -- reassign it before confirming', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.status = 'cancelled' then
    raise exception 'task_cancelled: task % has been cancelled', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.claimed_by_auth_user_id <> p_actor_auth_user_id then
    raise exception 'not_task_claimant: identity % is not the assigned claimant of task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: confirm quantity must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_quantity > v_task.remaining_quantity then
    raise exception 'exceeds_remaining_quantity: task % has % remaining but % was requested', p_task_id, v_task.remaining_quantity, p_quantity using errcode = 'check_violation';
  end if;

  if v_task.lot_controlled and coalesce(p_lot_number, '') <> coalesce(v_task.lot_number, '') then
    if p_lot_number is null then
      raise exception 'missing_lot: task % is lot-controlled (lot %) -- a matching lot number is required', p_task_id, v_task.lot_number using errcode = 'check_violation';
    end if;
    raise exception 'lot_mismatch: scanned lot % does not match task %''s own lot %', p_lot_number, p_task_id, v_task.lot_number using errcode = 'check_violation';
  end if;
  if v_task.serial_controlled and coalesce(p_serial_number, '') <> coalesce(v_task.serial_number, '') then
    if p_serial_number is null then
      raise exception 'missing_serial: task % is serial-controlled (serial %) -- a matching serial number is required', p_task_id, v_task.serial_number using errcode = 'check_violation';
    end if;
    raise exception 'serial_mismatch: scanned serial % does not match task %''s own serial %', p_serial_number, p_task_id, v_task.serial_number using errcode = 'check_violation';
  end if;

  -- Destination validation: the one authoritative check in this whole capability
  -- (design note 5). Once a task has any confirmed quantity, every subsequent
  -- confirm must land on the identical actual_location_id -- a task never splits its
  -- own execution across two different real destinations.
  --
  -- Locked (SELECT ... FOR UPDATE) on this first read of the destination and held
  -- through the capacity check below -- closing a cross-task TOCTOU class design note
  -- (b)/(c) did not originally cover: app.wms_putaway_tasks' own FOR UPDATE lock
  -- (above) only serializes two confirms against the *same task row*, and
  -- app.post_inventory_movement's own balance lock is keyed per (item/lot/serial/
  -- location) dimension tuple, not per location -- so two *different* putaway tasks
  -- (different items, or the same item with different lots) racing the same
  -- capacity-limited destination previously could both read the same stale occupancy
  -- and jointly overshoot capacity_value before either had posted its own transfer
  -- movement. Locking the destination location row here means a second concurrent
  -- confirm targeting the same destination blocks until the first transaction
  -- commits (or rolls back), then its own occupancy SELECT (a fresh READ COMMITTED
  -- statement, issued only after the lock is granted) observes the first transfer's
  -- real committed effect.
  if v_task.actual_location_id is not null then
    if p_actual_location_id <> v_task.actual_location_id then
      raise exception 'destination_mismatch: task % has already begun putaway at %, cannot confirm against a different location %', p_task_id, v_task.actual_location_id, p_actual_location_id
        using errcode = 'check_violation';
    end if;
    select * into v_destination from app.warehouse_locations where id = p_actual_location_id for update;
    if not found then
      raise exception 'location_not_found: %', p_actual_location_id using errcode = 'no_data_found';
    end if;
  else
    select * into v_destination from app.warehouse_locations where id = p_actual_location_id for update;
    if not found then
      raise exception 'location_not_found: %', p_actual_location_id using errcode = 'no_data_found';
    end if;
    if v_destination.warehouse_id <> v_task.warehouse_id then
      raise exception 'incompatible_location: destination % does not belong to warehouse %', p_actual_location_id, v_task.warehouse_id using errcode = 'check_violation';
    end if;
    if v_destination.location_type not in ('rack', 'shelf', 'bin') then
      raise exception 'incompatible_location: destination % is a % -- putaway must land on a rack, shelf or bin, not a final dock/staging/floor location', p_actual_location_id, v_destination.location_type
        using errcode = 'check_violation';
    end if;
    if not v_destination.putaway_enabled then
      raise exception 'incompatible_location: destination % is not putaway_enabled', p_actual_location_id using errcode = 'check_violation';
    end if;
    if v_destination.status <> 'active' then
      raise exception 'blocked_destination: destination % is not active', p_actual_location_id using errcode = 'check_violation';
    end if;
  end if;

  if v_destination.capacity_value is not null then
    select coalesce(sum(on_hand), 0) into v_occupied from app.inventory_balances where location_id = p_actual_location_id and status = 'on_hand';
    if v_occupied + p_quantity > v_destination.capacity_value then
      raise exception 'destination_full: destination % has % of % capacity occupied -- % more would exceed it', p_actual_location_id, v_occupied, v_destination.capacity_value, p_quantity
        using errcode = 'check_violation';
    end if;
  end if;

  select s.inbound_order_id into v_inbound_order_id from app.wms_receipt_lines l join app.wms_receipt_sessions s on s.id = l.receipt_session_id where l.id = v_task.receipt_line_id;

  -- The balanced transfer movement (Prompt 233 section 24: "source decrease equals
  -- destination increase in one balanced inventory transfer movement") -- two lines,
  -- identical owner/item/uom/lot/serial/status dimension, signed_quantity summing to
  -- exactly zero (app.post_inventory_movement's own design note 6 enforcement,
  -- ATW-015). A resulting negative on_hand at the source is caught by that function's
  -- own insufficient_stock check -- the real, reused safety net for "insufficient
  -- source balance" (Prompt 233 section 25), never re-implemented here.
  v_movement := app.post_inventory_movement(
    v_task.tenant_id, v_task.warehouse_id, 'transfer', 'wms_inbound_order', v_inbound_order_id, p_idempotency_key,
    'putaway task ' || p_task_id::text,
    jsonb_build_array(
      jsonb_build_object('owner_account_id', v_task.owner_account_id, 'item_master_id', v_task.item_master_id, 'location_id', v_task.source_location_id,
        'uom_code', v_task.uom_code, 'signed_quantity', -p_quantity, 'lot_number', v_task.lot_number, 'serial_number', v_task.serial_number, 'expiry_date', v_task.expiry_date, 'status', 'on_hand'),
      jsonb_build_object('owner_account_id', v_task.owner_account_id, 'item_master_id', v_task.item_master_id, 'location_id', p_actual_location_id,
        'uom_code', v_task.uom_code, 'signed_quantity', p_quantity, 'lot_number', v_task.lot_number, 'serial_number', v_task.serial_number, 'expiry_date', v_task.expiry_date, 'status', 'on_hand')
    ),
    p_actor_auth_user_id, p_actor_label
  );

  insert into app.wms_putaway_confirmations (
    tenant_id, task_id, idempotency_key, quantity, actual_location_id, movement_id, lot_number, serial_number, expiry_date, confirmed_by_auth_user_id, confirmed_by_label
  ) values (
    v_task.tenant_id, p_task_id, p_idempotency_key, p_quantity, p_actual_location_id, v_movement.id, p_lot_number, p_serial_number, v_task.expiry_date, p_actor_auth_user_id, p_actor_label
  );

  v_new_confirmed := v_task.confirmed_quantity + p_quantity;
  v_new_status := case when v_new_confirmed >= v_task.task_quantity then 'confirmed' else 'partial' end;

  update app.wms_putaway_tasks set
    confirmed_quantity = v_new_confirmed, actual_location_id = p_actual_location_id, status = v_new_status
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', null, null,
    jsonb_build_object('quantity', p_quantity, 'actual_location_id', p_actual_location_id, 'movement_id', v_movement.id, 'status', v_task.status)
  );

  return v_task;
end;
$function$;


-- app.consume_inventory_reservation
create or replace function app.consume_inventory_reservation(
  p_reservation_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.inventory_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.inventory_reservations;
  v_balance app.inventory_balances;
  v_warehouse app.warehouses;
  v_movement app.inventory_movements;
begin
  select * into v_reservation from app.inventory_reservations where id = p_reservation_id;
  if not found or not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
    raise exception 'reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;
  if v_reservation.status = 'consumed' then
    return v_reservation;
  end if;
  select * into v_balance from app.inventory_balances where id = v_reservation.balance_id;
  select * into v_warehouse from app.warehouses where id = v_balance.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_reservation.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot consume reservation %', p_actor_auth_user_id, p_reservation_id using errcode = 'insufficient_privilege';
  end if;
  if v_reservation.status <> 'active' then
    raise exception 'invalid_transition: reservation % is % -- only an active reservation may be consumed', p_reservation_id, v_reservation.status using errcode = 'check_violation';
  end if;

  v_movement := app.post_inventory_movement(
    v_reservation.tenant_id, v_balance.warehouse_id, 'consumption', 'reservation', v_reservation.id, p_idempotency_key, null,
    jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_balance.owner_account_id, 'item_master_id', v_balance.item_master_id, 'location_id', v_balance.location_id,
      'uom_code', (select base_uom_code from app.item_masters where id = v_balance.item_master_id),
      'signed_quantity', -v_reservation.reserved_quantity, 'lot_number', v_balance.lot_number, 'serial_number', v_balance.serial_number, 'status', v_balance.status
    )),
    p_actor_auth_user_id, p_actor_label
  );

  -- Hardening (this migration): see app.reserve_inventory's own comment above. Note
  -- app.post_inventory_movement above already bumped record_version once for its own
  -- on_hand change to this same row; this second, independent bump for the reserved
  -- decrement is correct and expected -- two real changes to the row, two bumps.
  update app.inventory_balances set reserved = reserved - v_reservation.reserved_quantity, updated_at = now(), record_version = record_version + 1 where id = v_reservation.balance_id;
  update app.inventory_reservations set status = 'consumed', consumed_movement_id = v_movement.id where id = p_reservation_id returning * into v_reservation;

  return v_reservation;
end;
$$;


-- app.create_wms_outbound_shipment
create or replace function app.create_wms_outbound_shipment(p_outbound_order_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_existing app.wms_outbound_shipments;
  v_shipment app.wms_outbound_shipments;
  v_number text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to create a shipment' using errcode = 'check_violation';
  end if;

  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'outbound_order_not_found: %', p_outbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot create a shipment under warehouse %', p_actor_auth_user_id, v_order.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_outbound_shipments where tenant_id = v_order.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.outbound_order_id <> p_outbound_order_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different outbound shipment (outbound order %, not %)', p_idempotency_key, v_existing.outbound_order_id, p_outbound_order_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_order.status <> 'confirmed' then
    raise exception 'outbound_order_not_confirmed: % is % -- only confirmed outbound demand may be shipped against', v_order.id, v_order.status using errcode = 'check_violation';
  end if;

  v_number := app.next_wms_outbound_shipment_number(v_order.tenant_id);

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_outbound_shipments (tenant_id, warehouse_id, outbound_order_id, owner_account_id, shipment_number, idempotency_key, created_by)
    values (v_order.tenant_id, v_order.warehouse_id, v_order.id, v_order.owner_account_id, v_number, p_idempotency_key, p_actor_label)
    returning * into v_shipment;
  exception
    when unique_violation then
      select * into v_existing from app.wms_outbound_shipments where tenant_id = v_order.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
        -- replay -- returning the earlier target's own row here silently misattributed
        -- this request to it (or silently discarded it entirely).
        if v_existing.outbound_order_id <> p_outbound_order_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different outbound shipment (outbound order %, not %)', p_idempotency_key, v_existing.outbound_order_id, p_outbound_order_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_wms_outbound_shipment',
    'app.wms_outbound_shipments', v_shipment.id, 'success', null, null,
    jsonb_build_object('outbound_order_id', p_outbound_order_id, 'shipment_number', v_number)
  );

  return v_shipment;
end;
$function$;


-- app.create_wms_package
create or replace function app.create_wms_package(p_packing_task_id uuid, p_parent_package_id uuid, p_package_type text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_packing_task app.wms_packing_tasks;
  v_warehouse app.warehouses;
  v_parent app.wms_packages;
  v_existing app.wms_packages;
  v_package app.wms_packages;
  v_number text;
  v_type text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to create a package' using errcode = 'check_violation';
  end if;

  select * into v_packing_task from app.wms_packing_tasks where id = p_packing_task_id;
  if not found or not app.has_active_tenant_membership(v_packing_task.tenant_id, p_actor_auth_user_id) then
    raise exception 'packing_task_not_found: %', p_packing_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_packing_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_packing_task.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_packing_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_packing_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_packing_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot create a package under packing task %', p_actor_auth_user_id, p_packing_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_packages where tenant_id = v_packing_task.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.packing_task_id <> p_packing_task_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different package (packing task %, not %)', p_idempotency_key, v_existing.packing_task_id, p_packing_task_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  v_type := coalesce(p_package_type, 'carton');
  if v_type not in ('carton', 'box', 'pallet', 'crate', 'container', 'envelope', 'other') then
    raise exception 'invalid_package_type: % is not a recognized package type', v_type using errcode = 'check_violation';
  end if;

  if p_parent_package_id is not null then
    -- Design note 2a: cycle-safe by construction -- the new package''s own id does not
    -- exist yet, so this can only ever reference an already-existing, already-acyclic
    -- package.
    select * into v_parent from app.wms_packages where id = p_parent_package_id for update;
    if not found or v_parent.packing_task_id <> p_packing_task_id then
      raise exception 'parent_package_not_found: % is not a package of packing task %', p_parent_package_id, p_packing_task_id using errcode = 'no_data_found';
    end if;
    if v_parent.status = 'confirmed' then
      raise exception 'parent_package_confirmed: % has already been confirmed -- reopen it before nesting a new child under it', p_parent_package_id using errcode = 'check_violation';
    end if;
  end if;

  v_number := app.next_wms_package_number(v_packing_task.tenant_id);

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_packages (
      tenant_id, warehouse_id, packing_task_id, outbound_order_id, owner_account_id, parent_package_id,
      package_number, package_type, idempotency_key, created_by
    ) values (
      v_packing_task.tenant_id, v_packing_task.warehouse_id, p_packing_task_id, v_packing_task.outbound_order_id, v_packing_task.owner_account_id, p_parent_package_id,
      v_number, v_type, p_idempotency_key, p_actor_label
    )
    returning * into v_package;
  exception
    when unique_violation then
      select * into v_existing from app.wms_packages where tenant_id = v_packing_task.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
        -- replay -- returning the earlier target's own row here silently misattributed
        -- this request to it (or silently discarded it entirely).
        if v_existing.packing_task_id <> p_packing_task_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different package (packing task %, not %)', p_idempotency_key, v_existing.packing_task_id, p_packing_task_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_packing_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_wms_package',
    'app.wms_packages', v_package.id, 'success', null, null,
    jsonb_build_object('packing_task_id', p_packing_task_id, 'parent_package_id', p_parent_package_id, 'package_number', v_number, 'package_type', v_type)
  );

  return v_package;
end;
$function$;


-- app.generate_wms_pick_task
create or replace function app.generate_wms_pick_task(p_outbound_order_line_id uuid, p_quantity numeric, p_wave_id uuid, p_location_id uuid, p_lot_number text, p_serial_number text, p_suggested_destination_location_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_pick_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_outbound_order_lines;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_wave app.wms_pick_waves;
  v_existing app.wms_pick_tasks;
  v_task app.wms_pick_tasks;
  v_allocated numeric;
  v_remaining numeric;
  v_balance app.inventory_balances;
  v_lot app.lot_identities;
  v_serial app.serial_identities;
  v_loc_pick_enabled boolean;
  v_loc_status text;
  v_loc_warehouse_id uuid;
  v_candidate record;
  v_resolved_location_id uuid;
  v_resolved_lot_number text;
  v_resolved_serial_number text;
  v_resolved_expiry_date date;
  v_reservation app.inventory_reservations;
  v_suggested app.warehouse_locations;
  v_suggested_reason text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to generate a pick task' using errcode = 'check_violation';
  end if;

  -- Design note 3 / bug class (e): the outbound order line is locked FOR UPDATE from
  -- this first read, held through the final INSERT -- the double-allocation guard.
  select * into v_line from app.wms_outbound_order_lines where id = p_outbound_order_line_id for update;
  if not found or not app.has_active_tenant_membership(v_line.tenant_id, p_actor_auth_user_id) then
    raise exception 'outbound_order_line_not_found: %', p_outbound_order_line_id using errcode = 'no_data_found';
  end if;
  select * into v_order from app.wms_outbound_orders where id = v_line.outbound_order_id;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot generate a pick task under warehouse %', p_actor_auth_user_id, v_order.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_pick_tasks where tenant_id = v_line.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.outbound_order_line_id <> p_outbound_order_line_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different pick task (outbound order line %, not %)', p_idempotency_key, v_existing.outbound_order_line_id, p_outbound_order_line_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_order.status <> 'confirmed' then
    raise exception 'outbound_order_not_confirmed: % is % -- only confirmed outbound demand may be picked against', v_order.id, v_order.status using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: pick task quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  if p_wave_id is not null then
    select * into v_wave from app.wms_pick_waves where id = p_wave_id;
    if not found or v_wave.tenant_id <> v_line.tenant_id or v_wave.warehouse_id <> v_order.warehouse_id then
      raise exception 'wave_not_found: % is not a pick wave of warehouse %', p_wave_id, v_order.warehouse_id using errcode = 'no_data_found';
    end if;
  end if;

  -- Design note 3: the double-allocation guard's own aggregate, computed under the
  -- line row lock above. short_quantity is subtracted -- a released short quantity is
  -- correctly available again for re-generation (design note 6).
  select coalesce(sum(task_quantity - short_quantity), 0) into v_allocated
    from app.wms_pick_tasks where outbound_order_line_id = p_outbound_order_line_id and status <> 'cancelled';
  v_remaining := v_line.requested_quantity - v_allocated;
  if p_quantity > v_remaining then
    raise exception 'insufficient_remaining_quantity: % of % requested units remain unallocated for outbound order line %, requested %', v_remaining, v_line.requested_quantity, p_outbound_order_line_id, p_quantity
      using errcode = 'check_violation';
  end if;

  -- Design note 10/11: resolve the SOURCE -- authoritative, never merely suggested.
  if p_location_id is not null then
    -- Location-level eligibility (pick_enabled/active/same-warehouse) is checked
    -- BEFORE the balance lookup -- a purely location-level gate, independent of any
    -- specific item's stock, so it is checked first regardless of whether a balance
    -- happens to exist there.
    select pick_enabled, status, warehouse_id into v_loc_pick_enabled, v_loc_status, v_loc_warehouse_id from app.warehouse_locations where id = p_location_id;
    if v_loc_warehouse_id is null or v_loc_warehouse_id <> v_order.warehouse_id then
      raise exception 'location_not_eligible: % is not a location of warehouse %', p_location_id, v_order.warehouse_id using errcode = 'check_violation';
    end if;
    if not v_loc_pick_enabled then
      raise exception 'location_not_eligible: % is not pick_enabled', p_location_id using errcode = 'check_violation';
    end if;
    if v_loc_status <> 'active' then
      raise exception 'blocked_location: % is not active', p_location_id using errcode = 'check_violation';
    end if;

    select * into v_balance from app.inventory_balances
      where tenant_id = v_line.tenant_id and warehouse_id = v_order.warehouse_id and owner_account_id = v_order.owner_account_id
        and item_master_id = v_line.item_master_id and location_id = p_location_id
        and coalesce(lot_number, '') = coalesce(p_lot_number, '') and coalesce(serial_number, '') = coalesce(p_serial_number, '')
        and status = 'on_hand';
    if not found then
      raise exception 'balance_not_found: no on-hand balance exists for the requested pick dimension' using errcode = 'no_data_found';
    end if;
    if v_balance.available <= 0 then
      raise exception 'insufficient_available_stock: % available for the requested pick dimension', v_balance.available using errcode = 'check_violation';
    end if;

    -- Design note 11: independently re-verify held/quarantined/expired eligibility --
    -- app.reserve_inventory itself does not check this. Mirrors app.list_allocation_
    -- candidates' own predicate exactly.
    if p_lot_number is not null then
      select * into v_lot from app.lot_identities where tenant_id = v_line.tenant_id and owner_account_id = v_order.owner_account_id and item_master_id = v_line.item_master_id and lot_number = p_lot_number;
      if found and (v_lot.status <> 'active' or (v_lot.expiry_date is not null and v_lot.expiry_date < current_date)) then
        raise exception 'ineligible_stock: lot % is % (or expired) -- not eligible for picking', p_lot_number, v_lot.status using errcode = 'check_violation';
      end if;
    end if;
    if p_serial_number is not null then
      select * into v_serial from app.serial_identities where tenant_id = v_line.tenant_id and owner_account_id = v_order.owner_account_id and item_master_id = v_line.item_master_id and serial_number = p_serial_number;
      if found and (v_serial.status <> 'active' or (v_serial.expiry_date is not null and v_serial.expiry_date < current_date)) then
        raise exception 'ineligible_stock: serial % is % (or expired) -- not eligible for picking', p_serial_number, v_serial.status using errcode = 'check_violation';
      end if;
    end if;

    v_resolved_location_id := p_location_id;
    v_resolved_lot_number := p_lot_number;
    v_resolved_serial_number := p_serial_number;
    v_resolved_expiry_date := coalesce(v_lot.expiry_date, v_serial.expiry_date);
  else
    -- Auto-select: walk app.list_allocation_candidates' own FIFO/FEFO-ordered rows
    -- (ATW-016, reused directly) and take the first whose own location is ALSO
    -- pick_enabled/active (design note 11 -- that function does not join warehouse_
    -- locations at all).
    for v_candidate in
      select * from app.list_allocation_candidates(v_line.tenant_id, v_order.warehouse_id, v_line.item_master_id, v_order.owner_account_id, p_actor_auth_user_id, null, 20)
    loop
      select pick_enabled, status into v_loc_pick_enabled, v_loc_status from app.warehouse_locations where id = v_candidate.location_id;
      if v_loc_pick_enabled and v_loc_status = 'active' then
        v_resolved_location_id := v_candidate.location_id;
        v_resolved_lot_number := v_candidate.lot_number;
        v_resolved_serial_number := v_candidate.serial_number;
        v_resolved_expiry_date := v_candidate.expiry_date;
        exit;
      end if;
    end loop;

    if v_resolved_location_id is null then
      raise exception 'no_eligible_pick_location: no eligible (pick-enabled, active, on-hand, non-held/expired) candidate found for item % under warehouse %', v_line.item_master_id, v_order.warehouse_id
        using errcode = 'no_data_found';
    end if;
  end if;

  -- Design note 12: reuses the real, widened wms_outbound_order source_type member.
  v_reservation := app.reserve_inventory(
    v_line.tenant_id, v_order.warehouse_id, v_order.owner_account_id, v_line.item_master_id,
    v_resolved_location_id, v_resolved_lot_number, v_resolved_serial_number, p_quantity,
    'wms_outbound_order', v_order.id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );

  -- Destination is real decision support only (design note 10), mirrors app.
  -- generate_wms_putaway_task's own suggestion shape.
  if p_suggested_destination_location_id is not null then
    select * into v_suggested from app.warehouse_locations where id = p_suggested_destination_location_id;
    if not found or v_suggested.warehouse_id <> v_order.warehouse_id then
      raise exception 'incompatible_location: suggested destination % does not belong to warehouse %', p_suggested_destination_location_id, v_order.warehouse_id using errcode = 'check_violation';
    end if;
    v_suggested_reason := 'caller_supplied';
  else
    select l.* into v_suggested
      from app.warehouse_locations l
      where l.warehouse_id = v_order.warehouse_id and l.status = 'active' and l.location_type = 'staging'
      order by l.sequence, l.code
      limit 1;
    if found then
      v_suggested_reason := 'auto_suggested_first_eligible_staging';
    else
      v_suggested := null;
      v_suggested_reason := 'no_eligible_destination_found';
    end if;
  end if;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_pick_tasks (
      tenant_id, warehouse_id, outbound_order_id, outbound_order_line_id, wave_id, owner_account_id, item_master_id, uom_code,
      lot_controlled, serial_controlled, expiry_controlled, source_location_id, lot_number, serial_number, expiry_date,
      reservation_id, task_quantity, suggested_destination_location_id, suggested_destination_reason, idempotency_key, created_by
    ) values (
      v_line.tenant_id, v_order.warehouse_id, v_order.id, p_outbound_order_line_id, p_wave_id, v_order.owner_account_id, v_line.item_master_id, v_line.requested_uom_code,
      v_line.lot_controlled, v_line.serial_controlled, v_line.expiry_controlled, v_resolved_location_id, v_resolved_lot_number, v_resolved_serial_number, v_resolved_expiry_date,
      v_reservation.id, p_quantity, (case when v_suggested is null then null else v_suggested.id end), v_suggested_reason, p_idempotency_key, p_actor_label
    )
    returning * into v_task;
  exception
    when unique_violation then
      select * into v_existing from app.wms_pick_tasks where tenant_id = v_line.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
        -- replay -- returning the earlier target's own row here silently misattributed
        -- this request to it (or silently discarded it entirely).
        if v_existing.outbound_order_line_id <> p_outbound_order_line_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different pick task (outbound order line %, not %)', p_idempotency_key, v_existing.outbound_order_line_id, p_outbound_order_line_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_wms_pick_task',
    'app.wms_pick_tasks', v_task.id, 'success', null, null,
    jsonb_build_object('outbound_order_line_id', p_outbound_order_line_id, 'task_quantity', p_quantity, 'reservation_id', v_reservation.id, 'source_location_id', v_resolved_location_id)
  );

  return v_task;
end;
$function$;


-- app.generate_wms_putaway_task
create or replace function app.generate_wms_putaway_task(p_receipt_line_id uuid, p_quantity numeric, p_suggested_location_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_putaway_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_existing app.wms_putaway_tasks;
  v_task app.wms_putaway_tasks;
  v_allocated numeric;
  v_remaining numeric;
  v_suggested app.warehouse_locations;
  v_suggested_reason text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to generate a putaway task' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final INSERT (FOR UPDATE) -- computing
  -- "remaining un-put-away quantity" (accepted_quantity minus every already-generated,
  -- non-cancelled task's own task_quantity) under this lock closes the same TOCTOU
  -- class design note (b)/(c) names: two concurrent generation calls against the same
  -- receipt line can never jointly over-allocate its accepted_quantity.
  select * into v_line from app.wms_receipt_lines where id = p_receipt_line_id for update;
  if not found or not app.has_active_tenant_membership(v_line.tenant_id, p_actor_auth_user_id) then
    raise exception 'receipt_line_not_found: %', p_receipt_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot generate a putaway task under warehouse %', p_actor_auth_user_id, v_session.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is confirmed
  -- above, never before (design note (a)).
  select * into v_existing from app.wms_putaway_tasks where tenant_id = v_line.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.receipt_line_id <> p_receipt_line_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different putaway task (receipt line %, not %)', p_idempotency_key, v_existing.receipt_line_id, p_receipt_line_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_line.status <> 'committed' then
    raise exception 'receipt_line_not_committed: % must be committed before putaway tasks may be generated for it', p_receipt_line_id using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: putaway task quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  select coalesce(sum(task_quantity), 0) into v_allocated from app.wms_putaway_tasks where receipt_line_id = p_receipt_line_id and status <> 'cancelled';
  v_remaining := v_line.accepted_quantity - v_allocated;
  if p_quantity > v_remaining then
    raise exception 'insufficient_remaining_quantity: % of % accepted units remain un-put-away for receipt line %, requested %', v_remaining, v_line.accepted_quantity, p_receipt_line_id, p_quantity
      using errcode = 'check_violation';
  end if;

  -- Suggestion is decision support only (design note 5) -- a caller-supplied
  -- suggestion is sanity-checked for existence/same-warehouse only, never full
  -- eligibility; the one authoritative destination validation happens exclusively at
  -- app.confirm_wms_putaway_task.
  if p_suggested_location_id is not null then
    select * into v_suggested from app.warehouse_locations where id = p_suggested_location_id;
    if not found or v_suggested.warehouse_id <> v_session.warehouse_id then
      raise exception 'incompatible_location: suggested location % does not belong to warehouse %', p_suggested_location_id, v_session.warehouse_id using errcode = 'check_violation';
    end if;
    v_suggested_reason := 'caller_supplied';
  else
    select l.* into v_suggested
      from app.warehouse_locations l
      where l.warehouse_id = v_session.warehouse_id
        and l.status = 'active'
        and l.putaway_enabled
        and l.location_type in ('rack', 'shelf', 'bin')
        and (l.capacity_value is null or l.capacity_value >= p_quantity + coalesce((select sum(b2.on_hand) from app.inventory_balances b2 where b2.location_id = l.id and b2.status = 'on_hand'), 0))
      order by l.sequence, l.code
      limit 1;
    if found then
      v_suggested_reason := 'auto_suggested_first_eligible_capacity_headroom';
    else
      v_suggested := null;
      v_suggested_reason := 'no_eligible_destination_found';
    end if;
  end if;

  begin
    insert into app.wms_putaway_tasks (
      tenant_id, warehouse_id, receipt_line_id, source_location_id, item_master_id, owner_account_id, uom_code,
      lot_controlled, serial_controlled, expiry_controlled, lot_number, serial_number, expiry_date,
      task_quantity, suggested_location_id, suggested_reason, idempotency_key, created_by
    ) values (
      v_line.tenant_id, v_session.warehouse_id, p_receipt_line_id, v_session.receiving_location_id, v_line.item_master_id, v_line.owner_account_id, v_line.expected_uom_code,
      v_line.lot_controlled, v_line.serial_controlled, v_line.expiry_controlled, v_line.lot_number, v_line.serial_number, v_line.expiry_date,
      p_quantity, (case when v_suggested is null then null else v_suggested.id end), v_suggested_reason, p_idempotency_key, p_actor_label
    )
    returning * into v_task;
  exception
    when unique_violation then
      -- Design note (d): a concurrent caller won the (tenant_id, idempotency_key)
      -- race on the unlocked pre-insert existence check above; gracefully return the
      -- winner rather than surface a raw unique_violation (mirrors
      -- app.start_wms_receipt_session, which itself mirrors app.capture_lead).
      select * into v_existing from app.wms_putaway_tasks where tenant_id = v_line.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
        -- replay -- returning the earlier target's own row here silently misattributed
        -- this request to it (or silently discarded it entirely).
        if v_existing.receipt_line_id <> p_receipt_line_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different putaway task (receipt line %, not %)', p_idempotency_key, v_existing.receipt_line_id, p_receipt_line_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', null, null,
    jsonb_build_object('receipt_line_id', p_receipt_line_id, 'task_quantity', p_quantity, 'suggested_location_id', v_task.suggested_location_id, 'suggested_reason', v_suggested_reason)
  );

  return v_task;
end;
$function$;


-- app.hold_warehouse_billing_event
create or replace function app.hold_warehouse_billing_event(p_event_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot hold billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status not in ('pending_review', 'reviewed') then
    raise exception 'invalid_transition: billing event % is % -- only pending_review or reviewed may be held', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to hold a billing event' using errcode = 'check_violation';
  end if;

  update app.warehouse_billing_events set status = 'on_hold', hold_reason = p_reason where id = p_event_id and record_version = p_expected_version returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: hold_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', p_reason, null, null
  );

  return v_event;
end;
$function$
;


-- app.load_wms_outbound_shipment
create or replace function app.load_wms_outbound_shipment(p_shipment_id uuid, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
  v_existing_load app.wms_shipment_load_events;
  v_lines jsonb;
  v_package_count integer;
  v_movement app.inventory_movements;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to load a shipment' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
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

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing_load from app.wms_shipment_load_events where tenant_id = v_shipment.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing_load.shipment_id <> p_shipment_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment load event (shipment %, not %)', p_idempotency_key, v_existing_load.shipment_id, p_shipment_id
        using errcode = 'unique_violation';
    end if;
    return v_shipment;
  end if;

  if v_shipment.status <> 'staging' then
    raise exception 'invalid_transition: % must be staging to load, is %', p_shipment_id, v_shipment.status using errcode = 'check_violation';
  end if;
  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment % expected version % but found %', p_shipment_id, p_expected_version, v_shipment.record_version using errcode = 'check_violation';
  end if;
  if v_shipment.dock_location_id is null then
    raise exception 'dock_location_not_set: set a dock location (app.set_wms_shipment_dock_location) before loading' using errcode = 'check_violation';
  end if;

  select count(*) into v_package_count from app.wms_shipment_packages where shipment_id = p_shipment_id;
  if v_package_count = 0 then
    raise exception 'empty_shipment_rejected: shipment % has no staged packages', p_shipment_id using errcode = 'check_violation';
  end if;

  -- Design note 3: the real physical relocation this capability introduces -- one
  -- paired (source-negative/dock-positive) transfer line per app.wms_package_lines
  -- row, source resolved from that line's own pick task's actual_destination_location_id
  -- (where ATW-017's own confirm_wms_pick_task already, physically, left it).
  select jsonb_agg(x) into v_lines from (
    select jsonb_build_object(
      'owner_account_id', pl.owner_account_id, 'item_master_id', pl.item_master_id, 'location_id', pt.actual_destination_location_id,
      'uom_code', pl.uom_code, 'signed_quantity', -pl.quantity, 'lot_number', pl.lot_number, 'serial_number', pl.serial_number,
      'expiry_date', pl.expiry_date, 'status', 'on_hand'
    ) as x
    from app.wms_package_lines pl
    join app.wms_pick_tasks pt on pt.id = pl.pick_task_id
    where pl.package_id in (select package_id from app.wms_shipment_packages where shipment_id = p_shipment_id)
    union all
    select jsonb_build_object(
      'owner_account_id', pl.owner_account_id, 'item_master_id', pl.item_master_id, 'location_id', v_shipment.dock_location_id,
      'uom_code', pl.uom_code, 'signed_quantity', pl.quantity, 'lot_number', pl.lot_number, 'serial_number', pl.serial_number,
      'expiry_date', pl.expiry_date, 'status', 'on_hand'
    ) as x
    from app.wms_package_lines pl
    join app.wms_pick_tasks pt on pt.id = pl.pick_task_id
    where pl.package_id in (select package_id from app.wms_shipment_packages where shipment_id = p_shipment_id)
  ) t;

  if v_lines is null or jsonb_array_length(v_lines) = 0 then
    raise exception 'empty_shipment_rejected: shipment % has no packed contents to load', p_shipment_id using errcode = 'check_violation';
  end if;

  v_movement := app.post_inventory_movement(
    v_shipment.tenant_id, v_shipment.warehouse_id, 'transfer', 'wms_outbound_order', v_shipment.outbound_order_id, p_idempotency_key,
    'wms outbound shipment ' || p_shipment_id::text || ' load to dock', v_lines, p_actor_auth_user_id, p_actor_label
  );

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_shipment_load_events (tenant_id, shipment_id, idempotency_key, dock_location_id, vehicle_ref, movement_id, package_count_snapshot, loaded_by_auth_user_id, loaded_by_label)
    values (v_shipment.tenant_id, p_shipment_id, p_idempotency_key, v_shipment.dock_location_id, v_shipment.vehicle_ref, v_movement.id, v_package_count, p_actor_auth_user_id, p_actor_label);
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent load request', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_outbound_shipments set
    status = 'loaded', loaded_at = now(), loaded_by_auth_user_id = p_actor_auth_user_id, loaded_by_label = p_actor_label, load_movement_id = v_movement.id
  where id = p_shipment_id
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'load_wms_outbound_shipment',
    'app.wms_outbound_shipments', v_shipment.id, 'success', null, null,
    jsonb_build_object('movement_id', v_movement.id, 'dock_location_id', v_shipment.dock_location_id, 'package_count', v_package_count)
  );

  return v_shipment;
end;
$function$;


-- app.move_warehouse_location
create or replace function app.move_warehouse_location(p_location_id uuid, p_new_parent_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_current app.warehouse_locations;
  v_updated app.warehouse_locations;
  v_warehouse app.warehouses;
  v_old_path_prefix uuid[];
  v_new_path_prefix uuid[];
  v_depth_delta integer;
begin
  select * into v_current from app.warehouse_locations where id = p_location_id;
  if not found or not app.has_active_tenant_membership(v_current.tenant_id, p_actor_auth_user_id) then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_current.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_current.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_current.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_current.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot move location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;
  if v_current.status <> 'draft' then
    raise exception 'location_not_draft: % is % -- only a draft (empty, unused) location may be moved', p_location_id, v_current.status
      using errcode = 'check_violation';
  end if;

  v_old_path_prefix := v_current.path || v_current.id;

  update app.warehouse_locations
  set parent_id = p_new_parent_id
  where id = p_location_id
  returning * into v_updated;

  v_new_path_prefix := v_updated.path || v_updated.id;
  v_depth_delta := v_updated.depth - v_current.depth;

  update app.warehouse_locations d
  set path = v_new_path_prefix || d.path[array_length(v_old_path_prefix, 1) + 1 : array_length(d.path, 1)],
      depth = d.depth + v_depth_delta
  where d.path @> array[p_location_id];

  perform app.capture_audit_event(
    v_current.tenant_id, p_actor_auth_user_id, p_actor_label, 'move_warehouse_location',
    'app.warehouse_locations', v_updated.id, 'success', null,
    jsonb_build_object('parent_id', v_current.parent_id), jsonb_build_object('parent_id', p_new_parent_id)
  );

  return v_updated;
end;
$function$;


-- app.publish_item_control_policy_version
create or replace function app.publish_item_control_policy_version(p_policy_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.item_control_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_policy app.item_control_policy_versions;
  v_superseded app.item_control_policy_versions;
begin
  select * into v_policy from app.item_control_policy_versions where id = p_policy_version_id;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'policy_version_not_found: %', p_policy_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_policy.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: policy version % expected version % but found %', p_policy_version_id, p_expected_version, v_policy.record_version
      using errcode = 'check_violation';
  end if;
  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: policy version % is % and cannot be published', p_policy_version_id, v_policy.status using errcode = 'check_violation';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.item_control_policy_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'superseded_policy_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.item_master_id <> v_policy.item_master_id then
      raise exception 'invalid_supersede: superseded policy must share the same item_master_id' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded policy % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;
    update app.item_control_policy_versions set status = 'archived', updated_at = now(), record_version = record_version + 1 where id = p_supersedes_version_id;
  end if;

  begin
    update app.item_control_policy_versions
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_policy_version_id and record_version = p_expected_version
    returning * into v_policy;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: publish_item_control_policy_version target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  exception
    when unique_violation then
      raise exception 'active_policy_exists: item % already has a published control policy -- supply p_supersedes_version_id to replace it', v_policy.item_master_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_item_control_policy_version',
    'app.item_control_policy_versions', v_policy.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_policy;
end;
$function$
;


-- app.publish_label_template_version
create or replace function app.publish_label_template_version(p_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.label_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.label_template_versions;
  v_superseded app.label_template_versions;
begin
  select * into v_version from app.label_template_versions where id = p_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'label_template_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: label template version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'check_violation';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: label template version % is % and cannot be published', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  if p_supersedes_version_id is not null then
    -- `for update` (findings review LOW #7): locks the row between this read and the
    -- archive UPDATE below so a concurrent modification cannot slip in between them.
    select * into v_superseded from app.label_template_versions where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'superseded_version_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.template_id <> v_version.template_id then
      raise exception 'invalid_supersede: superseded version must share the same template_id' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded version % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;
    update app.label_template_versions set status = 'archived' where id = p_supersedes_version_id and status = 'published';
  end if;

  begin
    update app.label_template_versions
    set status = 'published', supersedes_version_id = p_supersedes_version_id
    where id = p_version_id and record_version = p_expected_version
    returning * into v_version;
    -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
    -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
    -- execution fell straight through with a NULL composite, so the audit trail gained a
    -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
    -- record instead of the 'stale_version' its own error contract already handles.
    if not found then
      raise exception 'stale_version: publish_label_template_version target row was concurrently modified (expected version %)', p_expected_version
        using errcode = 'serialization_failure';
    end if;
  exception
    when unique_violation then
      raise exception 'active_template_version_exists: template % already has a published version -- supply p_supersedes_version_id to replace it', v_version.template_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_label_template_version',
    'app.label_template_versions', v_version.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$function$
;


-- app.recalculate_warehouse_billing_event
create or replace function app.recalculate_warehouse_billing_event(p_event_id uuid, p_expected_version integer, p_reason text, p_tax_code text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_billing_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
  v_rate app.warehouse_billing_rate_components;
  v_calc jsonb;
  v_before_total numeric;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found or not app.has_active_tenant_membership(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- A governed re-calculation -- OPS:Override, requiring a reason (Prompt 241 section
  -- 14's own "recalculate-with-version" distinct API surface).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status not in ('pending_review', 'reviewed') then
    raise exception 'invalid_transition: billing event % is % -- only pending_review or reviewed may be recalculated (use correct/reverse for approved/handed-off events)', p_event_id, v_event.status
      using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to recalculate a billing event' using errcode = 'check_violation';
  end if;

  v_before_total := v_event.total_amount;

  v_rate := app.get_effective_warehouse_billing_rate(v_event.tenant_id, v_event.owner_account_id, v_event.warehouse_id, v_event.activity_type, v_event.activity_date, p_actor_auth_user_id);
  v_calc := app.compute_warehouse_billing_breakdown(v_event.tenant_id, v_rate, v_event.quantity, v_event.uom_code, v_event.activity_date, p_tax_code, p_actor_auth_user_id);

  -- Re-runs the IDENTICAL calculation logic app.calculate_warehouse_billing_event uses
  -- (the shared internal function), IN PLACE on the same row -- legitimate pre-
  -- approval iteration, not a "silent amount rewrite after handoff" (nothing has been
  -- approved/handed off yet at pending_review/reviewed). A recalculation always
  -- resets any prior review to pending_review -- the reviewer must look again.
  update app.warehouse_billing_events set
    contract_id = v_rate.contract_id,
    rate_component_id = v_rate.id,
    base_amount = (v_calc ->> 'baseAmount')::numeric,
    tax_code = p_tax_code,
    tax_rule_version_id = (v_calc ->> 'taxRuleVersionId')::uuid,
    tax_amount = (v_calc ->> 'taxAmount')::numeric,
    total_amount = (v_calc ->> 'totalAmount')::numeric,
    currency = v_calc ->> 'currency',
    rounding_mode = v_calc ->> 'roundingMode',
    calculation_explanation = v_calc -> 'calculationExplanation',
    status = 'pending_review'
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: recalculate_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'recalculate_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', p_reason,
    jsonb_build_object('total_amount', v_before_total), jsonb_build_object('total_amount', v_event.total_amount)
  );

  return v_event;
end;
$function$
;


-- app.record_wms_pick_task_short
create or replace function app.record_wms_pick_task_short(p_task_id uuid, p_short_quantity numeric, p_reason text, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  v_existing app.wms_pick_task_shorts;
  v_reservation app.inventory_reservations;
  v_balance app.inventory_balances;
  v_new_short numeric;
  v_new_remaining numeric;
  v_new_status text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to record a pick short' using errcode = 'check_violation';
  end if;

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

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_pick_task_shorts where tenant_id = v_task.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.task_id <> p_task_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different pick short (task %, not %)', p_idempotency_key, v_existing.task_id, p_task_id
        using errcode = 'unique_violation';
    end if;
    return v_task;
  end if;

  if v_task.status not in ('claimed', 'partial') then
    raise exception 'invalid_transition: task % is % -- only a claimed or partially-picked task may record a short', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  -- Only the task's own claimant, or a supervisor holding OPS:Override, may record a
  -- short on it (mirrors app.mark_wms_putaway_task_exception's own access rule).
  if v_task.claimed_by_auth_user_id <> p_actor_auth_user_id then
    v_override := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Override');
    if not v_override.allowed then
      raise exception 'insufficient_authority: identity % is neither the claimant of task % nor holds OPS:Override', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
    end if;
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: pick task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;
  if p_short_quantity is null or p_short_quantity <= 0 then
    raise exception 'invalid_quantity: short quantity must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_short_quantity > v_task.remaining_quantity then
    raise exception 'exceeds_remaining_quantity: task % has % remaining but a short of % was requested', p_task_id, v_task.remaining_quantity, p_short_quantity using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to record a pick short' using errcode = 'check_violation';
  end if;

  -- Design note 5/6: release exactly the short quantity from reserved -- the stock
  -- physically stays put (no transfer), only its earmark is removed.
  select * into v_reservation from app.inventory_reservations where id = v_task.reservation_id for update;
  select * into v_balance from app.inventory_balances where id = v_reservation.balance_id for update;
  update app.inventory_balances set reserved = reserved - p_short_quantity where id = v_balance.id;

  -- Real defect found and fixed by adversarial review (design note 0b): identical
  -- reasoning as app.confirm_wms_pick_task's own insert above -- the reserved-balance
  -- release just above has already happened for THIS task; a conflicting key here can
  -- only mean p_idempotency_key was reused across a different (different-task) short
  -- request, so a clean, classified exception aborts and rolls back this call's own
  -- reserved-balance release together with the failed insert.
  begin
    insert into app.wms_pick_task_shorts (tenant_id, task_id, idempotency_key, quantity, reason, recorded_by_auth_user_id, recorded_by_label)
    values (v_task.tenant_id, p_task_id, p_idempotency_key, p_short_quantity, p_reason, p_actor_auth_user_id, p_actor_label);
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent short request', p_idempotency_key using errcode = 'unique_violation';
  end;

  v_new_short := v_task.short_quantity + p_short_quantity;
  v_new_remaining := v_task.task_quantity - v_task.picked_quantity - v_new_short;
  v_new_status := case when v_new_remaining <= 0 then 'short' else 'partial' end;

  update app.wms_pick_tasks set short_quantity = v_new_short, status = v_new_status where id = p_task_id returning * into v_task;

  if v_new_status = 'short' then
    update app.inventory_reservations set status = 'released', released_reason = 'wms_pick_task_resolved: picked=' || v_task.picked_quantity || ' short=' || v_new_short
      where id = v_reservation.id and status = 'active';
  end if;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_pick_task_short',
    'app.wms_pick_tasks', v_task.id, 'success', p_reason, null, jsonb_build_object('short_quantity', p_short_quantity, 'status', v_task.status)
  );

  return v_task;
end;
$function$;


-- app.register_serial_identity
create or replace function app.register_serial_identity(p_item_master_id uuid, p_serial_number text, p_lot_number text, p_manufacture_date date, p_expiry_date date, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.serial_identities
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
  v_existing app.serial_identities;
  v_policy app.item_control_policy_versions;
  v_hold_default boolean;
  v_status text;
  v_hold_reason text;
  v_serial app.serial_identities;
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

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to register a serial identity' using errcode = 'check_violation';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before.
  select * into v_existing from app.serial_identities where tenant_id = v_item.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.item_master_id <> p_item_master_id or v_existing.serial_number is distinct from p_serial_number then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different serial identity (item %/serial %, not item %/serial %)', p_idempotency_key, v_existing.item_master_id, v_existing.serial_number, p_item_master_id, p_serial_number
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if not v_item.serial_controlled then
    raise exception 'item_not_serial_controlled: item % is not serial-controlled -- a serial identity is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_serial_number is null or length(trim(p_serial_number)) = 0 then
    raise exception 'invalid_serial_number: a serial number is required' using errcode = 'check_violation';
  end if;
  if coalesce(p_source_type, 'receipt') not in ('receipt', 'manual') then
    raise exception 'invalid_source_type: % is not a recognized serial source type', p_source_type using errcode = 'check_violation';
  end if;
  if p_lot_number is not null and not v_item.lot_controlled then
    raise exception 'item_not_lot_controlled: item % is not lot-controlled -- a lot_number on a serial identity is not relevant', p_item_master_id using errcode = 'check_violation';
  end if;
  if p_manufacture_date is not null and p_expiry_date is not null and p_expiry_date < p_manufacture_date then
    raise exception 'invalid_date_order: expiry_date % precedes manufacture_date %', p_expiry_date, p_manufacture_date using errcode = 'check_violation';
  end if;
  if p_expiry_date is not null and not v_item.expiry_controlled then
    raise exception 'expiry_date_not_applicable: item % is not expiry-controlled -- an expiry date is not relevant', p_item_master_id using errcode = 'check_violation';
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
    insert into app.serial_identities (
      tenant_id, owner_account_id, item_master_id, serial_number, lot_number, manufacture_date, expiry_date, status, hold_reason,
      source_type, source_id, idempotency_key, created_by
    ) values (
      v_item.tenant_id, v_item.owner_account_id, p_item_master_id, p_serial_number, p_lot_number, p_manufacture_date, p_expiry_date, v_status, v_hold_reason,
      coalesce(p_source_type, 'receipt'), p_source_id, p_idempotency_key, p_actor_label
    )
    returning * into v_serial;
  exception
    when unique_violation then
      -- Design note 3: disambiguate a race on idempotency_key (re-select and return
      -- the winner, the real idempotent-replay guarantee) from a genuine duplicate
      -- serial tripping the separate governed-scope natural-key unique index.
      select * into v_existing from app.serial_identities where tenant_id = v_item.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
        -- replay -- returning the earlier target's own row here silently misattributed
        -- this request to it (or silently discarded it entirely).
        if v_existing.item_master_id <> p_item_master_id or v_existing.serial_number is distinct from p_serial_number then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different serial identity (item %/serial %, not item %/serial %)', p_idempotency_key, v_existing.item_master_id, v_existing.serial_number, p_item_master_id, p_serial_number
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      end if;
      raise exception 'duplicate_serial: serial % is already registered for item % (owner %) in tenant %', p_serial_number, p_item_master_id, v_item.owner_account_id, v_item.tenant_id
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'register_serial_identity',
    'app.serial_identities', v_serial.id, 'success', null, null,
    jsonb_build_object('item_master_id', p_item_master_id, 'serial_number', p_serial_number, 'status', v_status)
  );

  return v_serial;
end;
$function$;


-- app.release_inventory_reservation
create or replace function app.release_inventory_reservation(
  p_reservation_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.inventory_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.inventory_reservations;
  v_balance app.inventory_balances;
  v_warehouse app.warehouses;
begin
  select * into v_reservation from app.inventory_reservations where id = p_reservation_id;
  if not found or not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
    raise exception 'reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;
  select * into v_balance from app.inventory_balances where id = v_reservation.balance_id;
  select * into v_warehouse from app.warehouses where id = v_balance.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_reservation.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot release reservation %', p_actor_auth_user_id, p_reservation_id using errcode = 'insufficient_privilege';
  end if;
  if v_reservation.status <> 'active' then
    raise exception 'invalid_transition: reservation % is % -- only an active reservation may be released', p_reservation_id, v_reservation.status using errcode = 'check_violation';
  end if;

  -- Hardening (this migration): see app.reserve_inventory's own comment above.
  update app.inventory_balances set reserved = reserved - v_reservation.reserved_quantity, updated_at = now(), record_version = record_version + 1 where id = v_reservation.balance_id;
  update app.inventory_reservations set status = 'released', released_reason = p_reason where id = p_reservation_id returning * into v_reservation;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_inventory_reservation',
    'app.inventory_reservations', v_reservation.id, 'success', p_reason, null, null
  );

  return v_reservation;
end;
$$;


-- app.release_warehouse_billing_event_hold
create or replace function app.release_warehouse_billing_event_hold(p_event_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot release billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'on_hold' then
    raise exception 'invalid_transition: billing event % is % -- only on_hold may be released', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  -- Always back to pending_review, never directly to reviewed/approved -- a held
  -- event must be looked at again from the start.
  update app.warehouse_billing_events set status = 'pending_review' where id = p_event_id and record_version = p_expected_version returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: release_warehouse_billing_event_hold target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_warehouse_billing_event_hold',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$function$
;


-- app.remove_wms_package_line
create or replace function app.remove_wms_package_line(p_package_id uuid, p_pick_task_id uuid, p_quantity numeric, p_reason text, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_existing_scan app.wms_package_line_scans;
  v_line app.wms_package_lines;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to remove a package line' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to remove a package line' using errcode = 'check_violation';
  end if;

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
    raise exception 'insufficient_authority: identity % cannot remove a line from package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing_scan from app.wms_package_line_scans where tenant_id = v_package.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing_scan.package_id <> p_package_id or v_existing_scan.event_type <> 'remove' then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different package line scan (package %/event %, not package %/event remove)', p_idempotency_key, v_existing_scan.package_id, v_existing_scan.event_type, p_package_id
        using errcode = 'unique_violation';
    end if;
    return v_package;
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: remove quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  select * into v_line from app.wms_package_lines where package_id = p_package_id and pick_task_id = p_pick_task_id for update;
  if not found then
    raise exception 'line_not_found: pick task % is not currently packed into package %', p_pick_task_id, p_package_id using errcode = 'no_data_found';
  end if;
  if p_quantity > v_line.quantity then
    raise exception 'exceeds_line_quantity: package % only has % of pick task % packed, cannot remove %', p_package_id, v_line.quantity, p_pick_task_id, p_quantity using errcode = 'check_violation';
  end if;

  if p_quantity = v_line.quantity then
    delete from app.wms_package_lines where id = v_line.id;
  else
    update app.wms_package_lines set quantity = quantity - p_quantity where id = v_line.id;
  end if;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_package_line_scans (
      tenant_id, package_id, pick_task_id, event_type, quantity, reason, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_package.tenant_id, p_package_id, p_pick_task_id, 'remove', p_quantity, p_reason, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent remove-line request', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_packages set
    line_count = (select count(*) from app.wms_package_lines where package_id = p_package_id),
    total_packed_quantity = (select coalesce(sum(quantity), 0) from app.wms_package_lines where package_id = p_package_id)
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_wms_package_line',
    'app.wms_packages', v_package.id, 'success', p_reason, null,
    jsonb_build_object('pick_task_id', p_pick_task_id, 'quantity', p_quantity)
  );

  return v_package;
end;
$function$;


-- app.reschedule_wms_inbound_appointment
create or replace function app.reschedule_wms_inbound_appointment(p_inbound_order_id uuid, p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status not in ('scheduled', 'confirmed') then
    raise exception 'invalid_transition: % must be scheduled or confirmed to reschedule, is %', p_inbound_order_id, v_order.status using errcode = 'check_violation';
  end if;
  if p_window_start is null or p_window_end is null or p_window_end <= p_window_start then
    raise exception 'invalid_appointment_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set
    appointment_window_start = p_window_start,
    appointment_window_end = p_window_end,
    expected_date = p_window_start::date
  where id = p_inbound_order_id
  returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'reschedule_wms_inbound_appointment',
    'app.wms_inbound_orders', v_order.id, 'success', null, null,
    jsonb_build_object('window_start', p_window_start, 'window_end', p_window_end)
  );

  return v_order;
end;
$function$;


-- app.review_warehouse_billing_event
create or replace function app.review_warehouse_billing_event(p_event_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot review billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'pending_review' then
    raise exception 'invalid_transition: billing event % is % -- only pending_review may be reviewed', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  update app.warehouse_billing_events set
    status = 'reviewed', reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_by_label = p_actor_label, reviewed_at = now()
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: review_warehouse_billing_event target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$function$
;


-- app.revoke_warehouse_customer_eligibility
create or replace function app.revoke_warehouse_customer_eligibility(p_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_customer_eligibility
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_row app.warehouse_customer_eligibility;
  v_warehouse app.warehouses;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revoke warehouse customer eligibility' using errcode = 'check_violation';
  end if;

  select * into v_row from app.warehouse_customer_eligibility where id = p_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'eligibility_not_found: %', p_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_row.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_row.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, v_row.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: eligibility % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'check_violation';
  end if;
  if v_row.status = 'revoked' then
    raise exception 'invalid_transition: eligibility % is already revoked', p_id using errcode = 'check_violation';
  end if;

  update app.warehouse_customer_eligibility set status = 'revoked', revoked_at = now(), revoked_reason = p_reason where id = p_id returning * into v_row;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_warehouse_customer_eligibility',
    'app.warehouse_customer_eligibility', v_row.id, 'success', p_reason, null,
    jsonb_build_object('warehouse_id', v_row.warehouse_id, 'customer_account_id', v_row.customer_account_id)
  );

  return v_row;
end;
$function$;


-- app.schedule_wms_inbound_appointment
create or replace function app.schedule_wms_inbound_appointment(p_inbound_order_id uuid, p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_line_count integer;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status <> 'draft' then
    raise exception 'invalid_transition: % must be draft to schedule an appointment, is %', p_inbound_order_id, v_order.status using errcode = 'check_violation';
  end if;
  if p_window_start is null or p_window_end is null or p_window_end <= p_window_start then
    raise exception 'invalid_appointment_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  select count(*) into v_line_count from app.wms_inbound_order_lines where inbound_order_id = p_inbound_order_id;
  if v_line_count = 0 then
    raise exception 'no_lines: % has no lines -- add at least one line before scheduling', p_inbound_order_id using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set
    appointment_window_start = p_window_start,
    appointment_window_end = p_window_end,
    expected_date = p_window_start::date,
    status = 'scheduled'
  where id = p_inbound_order_id
  returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'schedule_wms_inbound_appointment',
    'app.wms_inbound_orders', v_order.id, 'success', null, null,
    jsonb_build_object('window_start', p_window_start, 'window_end', p_window_end)
  );

  return v_order;
end;
$function$;


-- app.set_item_master_status
create or replace function app.set_item_master_status(p_item_master_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.item_masters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid item master status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_item from app.item_masters where id = p_item_master_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: item master % expected version % but found %', p_item_master_id, p_expected_version, v_item.record_version
      using errcode = 'check_violation';
  end if;
  if v_item.status = p_new_status then
    return v_item;
  end if;
  if p_new_status = 'inactive' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a reason is required to deactivate an item master' using errcode = 'check_violation';
  end if;

  update app.item_masters set status = p_new_status where id = p_item_master_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_item_master_status',
    'app.item_masters', v_item.id, 'success', p_reason, null,
    jsonb_build_object('new_status', p_new_status)
  );

  return v_item;
end;
$function$;


-- app.set_warehouse_location_status
create or replace function app.set_warehouse_location_status(p_location_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
  v_active_child_count integer;
begin
  if p_new_status not in ('draft', 'active', 'inactive') then
    raise exception 'invalid_status: % is not a valid location status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found or not app.has_active_tenant_membership(v_location.tenant_id, p_actor_auth_user_id) then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_location.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_location.record_version
      using errcode = 'check_violation';
  end if;
  if v_location.status = p_new_status then
    return v_location;
  end if;

  if p_new_status = 'active' and v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active -- cannot activate a location under it', v_location.warehouse_id using errcode = 'check_violation';
  end if;

  if p_new_status = 'inactive' then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a non-empty reason is required to deactivate a location' using errcode = 'check_violation';
    end if;
    select count(*) into v_active_child_count from app.warehouse_locations where parent_id = p_location_id and status in ('draft', 'active');
    if v_active_child_count > 0 then
      raise exception 'location_has_active_children: % cannot be deactivated while % draft/active child location(s) exist', p_location_id, v_active_child_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouse_locations set status = p_new_status where id = p_location_id returning * into v_location;

  perform app.capture_audit_event(
    v_location.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_location_status',
    'app.warehouse_locations', v_location.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_location;
end;
$function$;


-- app.set_warehouse_status
create or replace function app.set_warehouse_status(p_warehouse_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_active_zone_count integer;
  v_active_location_count integer;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid warehouse status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id for update;
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

  if v_warehouse.record_version <> p_expected_version then
    raise exception 'stale_version: warehouse % expected version % but found %', p_warehouse_id, p_expected_version, v_warehouse.record_version
      using errcode = 'check_violation';
  end if;
  if v_warehouse.status = p_new_status then
    return v_warehouse;
  end if;

  if p_new_status = 'inactive' then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a non-empty reason is required to deactivate a warehouse' using errcode = 'check_violation';
    end if;
    select count(*) into v_active_zone_count from app.warehouse_zones where warehouse_id = p_warehouse_id and status in ('active', 'on_hold');
    if v_active_zone_count > 0 then
      raise exception 'warehouse_has_active_zones: % cannot be deactivated while % active/on-hold zone(s) exist', p_warehouse_id, v_active_zone_count
        using errcode = 'check_violation';
    end if;
    select count(*) into v_active_location_count
      from app.warehouse_locations where warehouse_id = p_warehouse_id and status in ('draft', 'active');
    if v_active_location_count > 0 then
      raise exception 'warehouse_has_active_locations: % cannot be deactivated while % draft/active location(s) exist (including zoneless root-level locations)', p_warehouse_id, v_active_location_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouses set status = p_new_status where id = p_warehouse_id returning * into v_warehouse;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_status',
    'app.warehouses', v_warehouse.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_warehouse;
end;
$function$;


-- app.set_warehouse_zone_status
create or replace function app.set_warehouse_zone_status(p_zone_id uuid, p_new_status text, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_zones
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_zone app.warehouse_zones;
  v_warehouse app.warehouses;
  v_active_location_count integer;
begin
  if p_new_status not in ('active', 'inactive', 'on_hold') then
    raise exception 'invalid_status: % is not a valid zone status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_zone from app.warehouse_zones where id = p_zone_id;
  if not found or not app.has_active_tenant_membership(v_zone.tenant_id, p_actor_auth_user_id) then
    raise exception 'zone_not_found: %', p_zone_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_zone.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_zone.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_zone.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_zone.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit zone %', p_actor_auth_user_id, p_zone_id using errcode = 'insufficient_privilege';
  end if;

  if v_zone.record_version <> p_expected_version then
    raise exception 'stale_version: zone % expected version % but found %', p_zone_id, p_expected_version, v_zone.record_version
      using errcode = 'check_violation';
  end if;
  if v_zone.status = p_new_status then
    return v_zone;
  end if;
  if p_new_status in ('inactive', 'on_hold') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to set a zone to %', p_new_status using errcode = 'check_violation';
  end if;

  if p_new_status = 'inactive' then
    select count(*) into v_active_location_count
      from app.warehouse_locations where zone_id = p_zone_id and status in ('draft', 'active');
    if v_active_location_count > 0 then
      raise exception 'zone_has_active_locations: % cannot be deactivated while % draft/active location(s) exist under it', p_zone_id, v_active_location_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouse_zones set status = p_new_status where id = p_zone_id returning * into v_zone;

  perform app.capture_audit_event(
    v_zone.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_zone_status',
    'app.warehouse_zones', v_zone.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_zone;
end;
$function$;


-- app.ship_confirm_wms_outbound_shipment
create or replace function app.ship_confirm_wms_outbound_shipment(p_shipment_id uuid, p_custody_confirmed_by_label text, p_custody_confirmed_reason text, p_is_partial_fulfillment boolean, p_partial_fulfillment_reason text, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_outbound_shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
  v_existing_confirmation app.wms_shipment_confirmations;
  v_total_confirmed_packages integer;
  v_already_covered_packages integer;
  v_is_partial boolean;
  v_lines jsonb;
  v_line_count integer;
  v_total_quantity numeric;
  v_package_count integer;
  v_movement app.inventory_movements;
  v_weight_by_uom jsonb;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to ship-confirm a shipment' using errcode = 'check_violation';
  end if;
  if p_custody_confirmed_by_label is null or length(trim(p_custody_confirmed_by_label)) = 0 then
    raise exception 'custody_required: a real custody-confirming actor label is required' using errcode = 'check_violation';
  end if;
  if p_custody_confirmed_reason is null or length(trim(p_custody_confirmed_reason)) = 0 then
    raise exception 'custody_required: a real custody confirmation reason is required' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c) AND
  -- design note 5's own headline bug-class-(e) instance (the double-ship-confirm race):
  -- this lock is acquired BEFORE the partial-fulfillment aggregate below and BEFORE the
  -- status check, so two concurrent ship-confirm calls against the SAME shipment
  -- (even under two different idempotency keys) fully serialize.
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

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing_confirmation from app.wms_shipment_confirmations where tenant_id = v_shipment.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing_confirmation.shipment_id <> p_shipment_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment confirmation (shipment %, not %)', p_idempotency_key, v_existing_confirmation.shipment_id, p_shipment_id
        using errcode = 'unique_violation';
    end if;
    return v_shipment;
  end if;

  if v_shipment.status <> 'loaded' then
    raise exception 'invalid_transition: % must be loaded to ship-confirm, is % -- a retry with a different idempotency key against an already-shipped shipment is rejected here, never double-issued', p_shipment_id, v_shipment.status
      using errcode = 'check_violation';
  end if;
  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment % expected version % but found %', p_shipment_id, p_expected_version, v_shipment.record_version using errcode = 'check_violation';
  end if;

  -- Cross-shipment serialization for the partial-fulfillment aggregate below: the
  -- header lock acquired above only serializes against another ship-confirm of the
  -- SAME shipment row (design note 5's own double-ship-confirm race). Two DIFFERENT
  -- sibling shipments of the SAME outbound order, ship-confirmed concurrently, are
  -- not covered by that row lock at all -- each would independently compute the
  -- aggregate below against the other's still-uncommitted 'loaded' status (never
  -- seeing it as 'shipped'), under-count the order's already-covered packages, and
  -- both could be spuriously rejected partial_fulfillment_not_acknowledged even
  -- though, combined, they fully complete the order. A session-transaction advisory
  -- lock keyed on the outbound order id fully serializes every ship-confirm of any
  -- shipment belonging to the same order -- released automatically at transaction end
  -- (commit or rollback), never explicitly unlocked -- so the aggregate below always
  -- observes either a fully-committed or a not-yet-started sibling confirm, never a
  -- concurrently in-flight one. Taken as a single lock per order (never per-pair of
  -- shipment rows), this cannot deadlock against itself the way locking sibling rows
  -- in caller-dependent order could.
  perform pg_advisory_xact_lock(hashtextextended(v_shipment.outbound_order_id::text, 0));

  -- Design note 8: partial-fulfillment/backorder reconciliation, package-count based --
  -- computed strictly under the header lock and the cross-shipment advisory lock
  -- acquired above.
  select count(*) into v_total_confirmed_packages from app.wms_packages where outbound_order_id = v_shipment.outbound_order_id and status = 'confirmed';
  select count(distinct sp.package_id) into v_already_covered_packages
    from app.wms_shipment_packages sp
    join app.wms_outbound_shipments s on s.id = sp.shipment_id
    where s.outbound_order_id = v_shipment.outbound_order_id and (s.id = p_shipment_id or s.status = 'shipped');
  v_is_partial := v_already_covered_packages < v_total_confirmed_packages;

  -- Prompt 238 section 26's own access rule ("supervisor approves partial/backorder/
  -- override"), mirroring app.record_wms_pick_task_short's claimant-or-OPS:Override
  -- precedent: a real partial/backorder ship (v_is_partial derived from the aggregate
  -- above, never the caller-supplied acknowledgment flag alone) additionally requires
  -- OPS:Override on top of the base OPS:Edit already checked above -- plain staff may
  -- stage/load/ship a complete order but may not unilaterally approve a short ship.
  if v_is_partial then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Override');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant % -- a partial/backorder ship requires supervisor approval', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_is_partial and not coalesce(p_is_partial_fulfillment, false) then
    raise exception 'partial_fulfillment_not_acknowledged: % of % confirmed packages for outbound order % remain unshipped -- pass p_is_partial_fulfillment=true with a reason to acknowledge a real partial/backorder ship',
      v_total_confirmed_packages - v_already_covered_packages, v_total_confirmed_packages, v_shipment.outbound_order_id using errcode = 'check_violation';
  end if;
  if v_is_partial and (p_partial_fulfillment_reason is null or length(trim(p_partial_fulfillment_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required to acknowledge a partial/backorder ship' using errcode = 'check_violation';
  end if;

  select count(*), coalesce(sum(pl.quantity), 0) into v_line_count, v_total_quantity
    from app.wms_package_lines pl
    where pl.package_id in (select package_id from app.wms_shipment_packages where shipment_id = p_shipment_id);
  select count(distinct package_id) into v_package_count from app.wms_shipment_packages where shipment_id = p_shipment_id;

  if v_line_count = 0 then
    raise exception 'empty_shipment_rejected: shipment % has no packed contents to issue', p_shipment_id using errcode = 'check_violation';
  end if;

  -- Design note 1/4: ONE batched app.post_inventory_movement call (movement_type =
  -- consumption) covering EVERY package line in this shipment -- never app.
  -- consume_inventory_reservation (see this migration's own header, design note 1).
  -- Physical stock already sits at dock_location_id (app.load_wms_outbound_shipment's
  -- own real transfer), so that is the one location this movement decrements.
  select jsonb_agg(jsonb_build_object(
    'owner_account_id', pl.owner_account_id, 'item_master_id', pl.item_master_id, 'location_id', v_shipment.dock_location_id,
    'uom_code', pl.uom_code, 'signed_quantity', -pl.quantity, 'lot_number', pl.lot_number, 'serial_number', pl.serial_number,
    'expiry_date', pl.expiry_date, 'status', 'on_hand'
  )) into v_lines
  from app.wms_package_lines pl
  where pl.package_id in (select package_id from app.wms_shipment_packages where shipment_id = p_shipment_id);

  v_movement := app.post_inventory_movement(
    v_shipment.tenant_id, v_shipment.warehouse_id, 'consumption', 'wms_outbound_order', v_shipment.outbound_order_id, p_idempotency_key,
    'wms outbound shipment ' || p_shipment_id::text || ' ship-confirm issue', v_lines, p_actor_auth_user_id, p_actor_label
  );

  -- Design note 1's own traceability replacement: one append-only row per issued
  -- package line, carrying pick_task_id/reservation_id back to ATW-017's own real
  -- allocation, never established via app.consume_inventory_reservation.
  insert into app.wms_shipment_issue_lines (
    tenant_id, shipment_id, package_id, package_line_id, pick_task_id, reservation_id, item_master_id, owner_account_id, uom_code,
    lot_number, serial_number, expiry_date, quantity, movement_id
  )
  select v_shipment.tenant_id, p_shipment_id, pl.package_id, pl.id, pl.pick_task_id, pt.reservation_id, pl.item_master_id, pl.owner_account_id, pl.uom_code,
    pl.lot_number, pl.serial_number, pl.expiry_date, pl.quantity, v_movement.id
  from app.wms_package_lines pl
  join app.wms_pick_tasks pt on pt.id = pl.pick_task_id
  where pl.package_id in (select package_id from app.wms_shipment_packages where shipment_id = p_shipment_id);

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_shipment_confirmations (
      tenant_id, shipment_id, idempotency_key, movement_id, package_count_snapshot, line_count_snapshot, total_quantity_snapshot,
      is_partial_fulfillment, custody_confirmed_by_label, custody_confirmed_reason, confirmed_by_auth_user_id, confirmed_by_label
    ) values (
      v_shipment.tenant_id, p_shipment_id, p_idempotency_key, v_movement.id, v_package_count, v_line_count, v_total_quantity,
      v_is_partial, p_custody_confirmed_by_label, p_custody_confirmed_reason, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent ship-confirm request', p_idempotency_key using errcode = 'unique_violation';
  end;

  select coalesce(jsonb_object_agg(weight_uom_code, total_weight), '{}'::jsonb) into v_weight_by_uom
  from (
    select weight_uom_code, sum(weight_value) as total_weight
    from app.wms_packages
    where id in (select package_id from app.wms_shipment_packages where shipment_id = p_shipment_id) and weight_value is not null
    group by weight_uom_code
  ) w;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_billing_eligibility_events (
      tenant_id, warehouse_id, owner_account_id, outbound_order_id, shipment_id, idempotency_key,
      package_count, line_count, total_quantity, weight_by_uom, shipped_at
    ) values (
      v_shipment.tenant_id, v_shipment.warehouse_id, v_shipment.owner_account_id, v_shipment.outbound_order_id, p_shipment_id, p_idempotency_key,
      v_package_count, v_line_count, v_total_quantity, v_weight_by_uom, now()
    );
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent billing-eligibility event', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_outbound_shipments set
    status = 'shipped', shipped_at = now(), shipped_by_auth_user_id = p_actor_auth_user_id, shipped_by_label = p_actor_label,
    consumption_movement_id = v_movement.id, custody_confirmed_by_label = p_custody_confirmed_by_label, custody_confirmed_reason = p_custody_confirmed_reason,
    custody_confirmed_at = now(), is_partial_fulfillment = v_is_partial, partial_fulfillment_reason = (case when v_is_partial then p_partial_fulfillment_reason else null end)
  where id = p_shipment_id
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'ship_confirm_wms_outbound_shipment',
    'app.wms_outbound_shipments', v_shipment.id, 'success', p_custody_confirmed_reason, null,
    jsonb_build_object('movement_id', v_movement.id, 'package_count', v_package_count, 'line_count', v_line_count, 'total_quantity', v_total_quantity, 'is_partial_fulfillment', v_is_partial)
  );

  return v_shipment;
end;
$function$;


-- app.start_wms_packing_task
create or replace function app.start_wms_packing_task(p_outbound_order_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_packing_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_existing app.wms_packing_tasks;
  v_task app.wms_packing_tasks;
  v_number text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to start a packing task' using errcode = 'check_violation';
  end if;

  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'outbound_order_not_found: %', p_outbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', v_order.warehouse_id, v_order.tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot start a packing task under warehouse %', p_actor_auth_user_id, v_order.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_packing_tasks where tenant_id = v_order.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.outbound_order_id <> p_outbound_order_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different packing task (outbound order %, not %)', p_idempotency_key, v_existing.outbound_order_id, p_outbound_order_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;
  select * into v_existing from app.wms_packing_tasks where tenant_id = v_order.tenant_id and outbound_order_id = p_outbound_order_id;
  if found then
    return v_existing;
  end if;

  if v_order.status <> 'confirmed' then
    raise exception 'outbound_order_not_confirmed: % is % -- only confirmed outbound demand may be packed against', v_order.id, v_order.status using errcode = 'check_violation';
  end if;

  v_number := app.next_wms_packing_task_number(v_order.tenant_id);

  -- Bug class (d): a nested begin/exception unique_violation recovery -- either unique
  -- constraint (idempotency_key or the one-per-order guard) can fire under a genuine
  -- concurrent race; either way, re-select and return the real winner.
  begin
    insert into app.wms_packing_tasks (tenant_id, warehouse_id, outbound_order_id, owner_account_id, packing_task_number, idempotency_key, created_by)
    values (v_order.tenant_id, v_order.warehouse_id, v_order.id, v_order.owner_account_id, v_number, p_idempotency_key, p_actor_label)
    returning * into v_task;
  exception
    when unique_violation then
      select * into v_existing from app.wms_packing_tasks where tenant_id = v_order.tenant_id and outbound_order_id = p_outbound_order_id;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_wms_packing_task',
    'app.wms_packing_tasks', v_task.id, 'success', null, null, jsonb_build_object('outbound_order_id', p_outbound_order_id, 'packing_task_number', v_number)
  );

  return v_task;
end;
$function$;


-- app.start_wms_receipt_session
create or replace function app.start_wms_receipt_session(p_inbound_order_id uuid, p_receiving_location_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_receipt_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_location app.warehouse_locations;
  v_existing app.wms_receipt_sessions;
  v_session app.wms_receipt_sessions;
  v_line app.wms_inbound_order_lines;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to start a receipt session' using errcode = 'check_violation';
  end if;

  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot start receiving under warehouse %', p_actor_auth_user_id, v_order.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.wms_receipt_sessions where tenant_id = v_order.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
    -- replay -- returning the earlier target's own row here silently misattributed
    -- this request to it (or silently discarded it entirely).
    if v_existing.inbound_order_id <> p_inbound_order_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different receipt session (inbound order %, not %)', p_idempotency_key, v_existing.inbound_order_id, p_inbound_order_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_existing from app.wms_receipt_sessions where tenant_id = v_order.tenant_id and inbound_order_id = p_inbound_order_id and status <> 'cancelled';
  if found then
    return v_existing;
  end if;

  if v_order.status <> 'confirmed' then
    raise exception 'inbound_not_confirmed: % must be confirmed to start receiving, is %', p_inbound_order_id, v_order.status using errcode = 'check_violation';
  end if;

  select * into v_location from app.warehouse_locations where id = p_receiving_location_id;
  if not found then
    raise exception 'location_not_found: %', p_receiving_location_id using errcode = 'no_data_found';
  end if;
  if v_location.warehouse_id <> v_order.warehouse_id then
    raise exception 'incompatible_location: location % does not belong to warehouse %', p_receiving_location_id, v_order.warehouse_id using errcode = 'check_violation';
  end if;
  if v_location.location_type not in ('dock', 'staging') then
    raise exception 'incompatible_location: location % is a % -- receiving must land on a dock or staging location, not a final storage location', p_receiving_location_id, v_location.location_type
      using errcode = 'check_violation';
  end if;
  if v_location.status <> 'active' then
    raise exception 'incompatible_location: location % is not active', p_receiving_location_id using errcode = 'check_violation';
  end if;

  insert into app.wms_receipt_sessions (tenant_id, warehouse_id, inbound_order_id, receiving_location_id, idempotency_key, started_by)
  values (v_order.tenant_id, v_order.warehouse_id, p_inbound_order_id, p_receiving_location_id, p_idempotency_key, p_actor_label)
  returning * into v_session;

  for v_line in select * from app.wms_inbound_order_lines where inbound_order_id = p_inbound_order_id order by line_number loop
    insert into app.wms_receipt_lines (
      tenant_id, receipt_session_id, inbound_order_line_id, line_number, item_master_id, owner_account_id,
      expected_uom_code, expected_quantity, lot_controlled, serial_controlled, expiry_controlled
    ) values (
      v_order.tenant_id, v_session.id, v_line.id, v_line.line_number, v_line.item_master_id, v_order.owner_account_id,
      v_line.expected_uom_code, v_line.expected_quantity, v_line.lot_controlled, v_line.serial_controlled, v_line.expiry_controlled
    );
  end loop;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_wms_receipt_session',
    'app.wms_receipt_sessions', v_session.id, 'success', null, null,
    jsonb_build_object('inbound_order_id', p_inbound_order_id, 'receiving_location_id', p_receiving_location_id)
  );

  return v_session;
exception
  when unique_violation then
    -- Two callers racing the unlocked pre-insert existence checks above (same
    -- idempotency_key, or same non-cancelled inbound_order_id) both pass and race on
    -- the INSERT; the real partial unique indexes (wms_receipt_sessions_tenant_
    -- idempotency_unique, wms_receipt_sessions_inbound_order_unique) correctly let only
    -- one INSERT win. The loser re-selects and gracefully returns the winner's row --
    -- the same documented idempotency guarantee this function promises on the
    -- non-racing path -- rather than surfacing a raw, unclassified unique_violation
    -- (mirrors app.capture_lead's own unique_violation recovery, COM-143).
    select * into v_existing from app.wms_receipt_sessions where tenant_id = v_order.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-030: a key already used for a DIFFERENT target is a conflict, never a
      -- replay -- returning the earlier target's own row here silently misattributed
      -- this request to it (or silently discarded it entirely).
      if v_existing.inbound_order_id <> p_inbound_order_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different receipt session (inbound order %, not %)', p_idempotency_key, v_existing.inbound_order_id, p_inbound_order_id
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
    select * into v_existing from app.wms_receipt_sessions where tenant_id = v_order.tenant_id and inbound_order_id = p_inbound_order_id and status <> 'cancelled';
    if found then
      return v_existing;
    end if;
    raise;
end;
$function$;


-- app.update_item_master
create or replace function app.update_item_master(p_item_master_id uuid, p_name text, p_description text, p_lot_controlled boolean, p_serial_controlled boolean, p_expiry_controlled boolean, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.item_masters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_item app.item_masters;
begin
  select * into v_item from app.item_masters where id = p_item_master_id for update;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'item_master_not_found: %', p_item_master_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: item master % expected version % but found %', p_item_master_id, p_expected_version, v_item.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;

  update app.item_masters set
    name = p_name,
    description = p_description,
    lot_controlled = coalesce(p_lot_controlled, false),
    serial_controlled = coalesce(p_serial_controlled, false),
    expiry_controlled = coalesce(p_expiry_controlled, false)
  where id = p_item_master_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_item_master',
    'app.item_masters', v_item.id, 'success', null, null,
    jsonb_build_object('name', p_name, 'lot_controlled', v_item.lot_controlled, 'serial_controlled', v_item.serial_controlled, 'expiry_controlled', v_item.expiry_controlled)
  );

  return v_item;
end;
$function$;


-- app.update_warehouse
create or replace function app.update_warehouse(p_warehouse_id uuid, p_name text, p_site_address text, p_timezone text, p_site_geojson jsonb, p_service_type_eligibility text[], p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.warehouses
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_geog geography;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id for update;
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

  if v_warehouse.record_version <> p_expected_version then
    raise exception 'stale_version: warehouse % expected version % but found %', p_warehouse_id, p_expected_version, v_warehouse.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_timezone is null or not app.validate_timezone_name(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_site_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_site_geojson);
  end if;

  update app.warehouses set
    name = p_name,
    site_address = p_site_address,
    timezone = p_timezone,
    site_geog = v_geog,
    service_type_eligibility = coalesce(p_service_type_eligibility, '{}'::text[])
  where id = p_warehouse_id
  returning * into v_warehouse;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse',
    'app.warehouses', v_warehouse.id, 'success', null, null,
    jsonb_build_object('name', p_name, 'timezone', p_timezone)
  );

  return v_warehouse;
end;
$function$;


-- app.update_warehouse_location
create or replace function app.update_warehouse_location(p_location_id uuid, p_name text, p_sequence integer, p_capacity_value numeric, p_capacity_uom text, p_environment jsonb, p_restrictions jsonb, p_barcode text, p_pick_enabled boolean, p_putaway_enabled boolean, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
begin
  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found or not app.has_active_tenant_membership(v_location.tenant_id, p_actor_auth_user_id) then
    raise exception 'location_not_found: %', p_location_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  if v_location.record_version <> p_expected_version then
    raise exception 'stale_version: location % expected version % but found %', p_location_id, p_expected_version, v_location.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_capacity_value is not null and p_capacity_value < 0 then
    raise exception 'invalid_capacity: capacity_value must not be negative' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  begin
    update app.warehouse_locations set
      name = p_name,
      sequence = coalesce(p_sequence, 0),
      capacity_value = p_capacity_value,
      capacity_uom = p_capacity_uom,
      environment = coalesce(p_environment, '{}'::jsonb),
      restrictions = coalesce(p_restrictions, '{}'::jsonb),
      barcode = p_barcode,
      pick_enabled = coalesce(p_pick_enabled, false),
      putaway_enabled = coalesce(p_putaway_enabled, false)
    where id = p_location_id
    returning * into v_location;
  exception
    when unique_violation then
      raise exception 'duplicate_barcode: barcode % is already assigned within this tenant', p_barcode using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_location.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse_location',
    'app.warehouse_locations', v_location.id, 'success', null, null, jsonb_build_object('name', p_name, 'barcode', p_barcode)
  );

  return v_location;
end;
$function$;


-- app.update_warehouse_zone
create or replace function app.update_warehouse_zone(p_zone_id uuid, p_name text, p_environment jsonb, p_capacity_value numeric, p_capacity_uom text, p_restrictions jsonb, p_effective_from timestamp with time zone, p_effective_to timestamp with time zone, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.warehouse_zones
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_zone app.warehouse_zones;
  v_warehouse app.warehouses;
begin
  select * into v_zone from app.warehouse_zones where id = p_zone_id;
  if not found or not app.has_active_tenant_membership(v_zone.tenant_id, p_actor_auth_user_id) then
    raise exception 'zone_not_found: %', p_zone_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_zone.warehouse_id for update;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_zone.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_zone.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_zone.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit zone %', p_actor_auth_user_id, p_zone_id using errcode = 'insufficient_privilege';
  end if;

  if v_zone.record_version <> p_expected_version then
    raise exception 'stale_version: zone % expected version % but found %', p_zone_id, p_expected_version, v_zone.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_effective_from is not null and p_effective_to is not null and p_effective_to <= p_effective_from then
    raise exception 'invalid_effective_window: effective_to must be after effective_from' using errcode = 'check_violation';
  end if;
  if (p_capacity_value is null) <> (p_capacity_uom is null) then
    raise exception 'invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted' using errcode = 'check_violation';
  end if;

  update app.warehouse_zones set
    name = p_name,
    environment = coalesce(p_environment, '{}'::jsonb),
    capacity_value = p_capacity_value,
    capacity_uom = p_capacity_uom,
    restrictions = coalesce(p_restrictions, '{}'::jsonb),
    effective_from = p_effective_from,
    effective_to = p_effective_to
  where id = p_zone_id
  returning * into v_zone;

  perform app.capture_audit_event(
    v_zone.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse_zone',
    'app.warehouse_zones', v_zone.id, 'success', null, null, jsonb_build_object('name', p_name)
  );

  return v_zone;
end;
$function$;


-- app.update_wms_inbound_order_line
create or replace function app.update_wms_inbound_order_line(p_line_id uuid, p_expected_quantity numeric, p_notes text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_inbound_order_lines
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
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_order.tenant_id, p_actor_auth_user_id) then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  if v_order.status <> 'draft' then
    raise exception 'inbound_not_draft: % is not draft -- lines may only change while draft', v_order.id using errcode = 'check_violation';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id for update;

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
  if p_expected_quantity is null or p_expected_quantity <= 0 then
    raise exception 'invalid_quantity: expected_quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  update app.wms_inbound_order_lines set expected_quantity = p_expected_quantity, notes = p_notes
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_wms_inbound_order_line',
    'app.wms_inbound_order_lines', v_line.id, 'success', null, null,
    jsonb_build_object('expected_quantity', p_expected_quantity)
  );

  return v_line;
end;
$function$;
