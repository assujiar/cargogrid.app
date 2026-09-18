-- CG-AUDIT-2026-09-02 E3 (bounded core, piece 1 of 2): a real, live,
-- reachable cross-UOM balance-corruption bug in app.post_inventory_movement
-- -- found by a dedicated research pass, the same "verify before trusting a
-- deferred label" discipline that found B7's/B2a's/E6's/B4's/A2b's own real
-- bounded cores. The original finding ("No UoM on stock; free-text
-- locations; warehouse billing has no invoice FK") was carried as one
-- undivided DEFERRED_LARGE item and turned out to bundle three genuinely
-- different, independently-verifiable claims.
--
-- "No UoM on stock" was itself overstated -- a real, governed UOM registry
-- (app.uoms/app.uom_conversions/app.convert_uom_quantity, ATW-011A,
-- 20260730160000) and app.item_masters.base_uom_code have existed since
-- before this audit was even written, and app.inventory_movement_lines.
-- uom_code is already `not null references app.uoms(code)`, validated on
-- every post. But a real bug survives inside that framing: app.post_
-- inventory_movement (confirmed via a case-insensitive search this time --
-- the true current version last redefined in 20260730530000_harden_
-- operations_inventory_tracking_record_scope.sql) validates p_lines[].
-- uom_code is a real, ACTIVE registered code (app.validate_uom_code), but
-- never checks it matches the item's own base_uom_code, and never converts
-- -- it adds the raw signed_quantity straight onto app.inventory_balances.
-- on_hand. app.inventory_balances' own dimension key does not include
-- uom_code at all, so two movements against the identical balance row
-- (same tenant/warehouse/owner/item/location/lot/serial/status) posted in
-- DIFFERENT UOMs are summed as if they were the same unit -- 5 DOZ + 50 PCS
-- reads back as on_hand=55, not the true 110 PCS (or 9.1666 DOZ).
--
-- This is not a theoretical edge case. Most existing callers happen to
-- pre-normalize into a single UOM before calling the primitive, which is
-- why this has not been caught before -- but 20260831260000_create_
-- inventory_and_leave_opening_balance_import_adapters.sql (this session's
-- own A4 work) passes the import file's raw, user-chosen uom_code straight
-- through to app.post_inventory_movement after only checking it is a
-- registered ACTIVE code (never that it matches the item's own
-- base_uom_code), and that adapter's own header confirms it "writes no
-- inventory row itself... every guard, balance rule... this primitive
-- enforces applies to an imported row unchanged" -- so fixing the one
-- shared primitive closes the gap for every caller uniformly, the import
-- path included, matching this repository's own "single point of truth"
-- posting-primitive convention (the identical shape B4's own AR/AP
-- exposure-summary fix, and B6's own GL-posting fix, both already
-- established this session).
--
-- "Free-text locations," the second half of E3's own original bundled
-- claim, is FALSE for warehouse locations as re-verified here: app.
-- warehouse_locations is a fully structured, hierarchical, FK-enforced
-- table (code/name/location_type/parent_id/path/depth/zone/capacity),
-- confirmed unchanged and already correct -- not touched by this
-- migration. The genuine free-text-location gap the original audit
-- paragraph actually described (app.shipment_orders.origin/.destination,
-- plain `text not null` columns) is a separate, TMS-side finding, not part
-- of this WMS-scoped bounded core, and stays out of scope here.
--
-- Fix: app.post_inventory_movement now converts each line's as-posted
-- quantity into the item's own base_uom_code via the already-existing,
-- already-proven app.convert_uom_quantity (ATW-011A) BEFORE it is used in
-- any on_hand arithmetic -- inventory_balances.on_hand is now always
-- expressed consistently in the item's own base unit, regardless of which
-- registered unit any individual movement was posted in. app.inventory_
-- movement_lines' own signed_quantity/uom_code columns are UNCHANGED --
-- they remain the as-posted, as-reported transaction record (the correct
-- audit-trail semantic), never silently rewritten. A movement posted in
-- the item's own base_uom_code (confirmed the overwhelming common case by
-- the research above) is a complete no-op: app.convert_uom_quantity's own
-- early-return short-circuits `p_from_uom_code = p_to_uom_code` to the
-- identical raw quantity, so this fix changes zero observable behavior for
-- every existing caller already using the item's base unit. A genuine
-- cross-category mismatch (e.g. posting a weight-category UOM against a
-- count-controlled item) now fails closed with the already-established,
-- already-descriptive uom_conversion_not_registered error rather than
-- silently corrupting the balance -- a strict hardening, never a new
-- capability.
--
-- CREATE OR REPLACE FUNCTION, not DROP+CREATE (the return type app.
-- inventory_movements is unchanged) -- the existing grant set is preserved
-- automatically, no revoke/re-grant needed.

CREATE OR REPLACE FUNCTION app.post_inventory_movement(p_tenant_id uuid, p_warehouse_id uuid, p_movement_type text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_reason text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_corrects_movement_id uuid DEFAULT NULL::uuid)
 RETURNS app.inventory_movements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_existing app.inventory_movements;
  v_movement app.inventory_movements;
  v_line jsonb;
  v_owner_account_id uuid;
  v_item_master_id uuid;
  v_location_id uuid;
  v_uom_code text;
  v_signed_quantity numeric;
  v_base_quantity numeric;
  v_lot_number text;
  v_serial_number text;
  v_expiry_date date;
  v_status text;
  v_item app.item_masters;
  v_location app.warehouse_locations;
  v_line_count integer := 0;
  v_transfer_sum numeric := 0;
  v_new_on_hand numeric;
  v_serial_on_hand numeric;
  v_balance_id uuid;
  v_current_on_hand numeric;
  v_current_reserved numeric;
  v_current_held numeric;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot post a movement under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_movement_type not in ('receipt', 'transfer', 'consumption', 'adjustment', 'opening_balance', 'reversal') then
    raise exception 'invalid_movement_type: % is not a recognized movement type', p_movement_type using errcode = 'check_violation';
  end if;
  if p_movement_type in ('adjustment', 'reversal') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required for a % movement', p_movement_type using errcode = 'check_violation';
  end if;
  if p_movement_type = 'reversal' and p_corrects_movement_id is null then
    raise exception 'invalid_correction: a reversal movement requires p_corrects_movement_id' using errcode = 'check_violation';
  end if;
  if p_movement_type <> 'reversal' and p_corrects_movement_id is not null then
    raise exception 'invalid_correction: p_corrects_movement_id may only be set on a reversal movement' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'invalid_lines: p_lines must be a non-empty JSON array' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.inventory_movements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.warehouse_id is distinct from p_warehouse_id or v_existing.movement_type is distinct from p_movement_type or v_existing.source_type is distinct from p_source_type or v_existing.source_id is distinct from p_source_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different inventory movement (warehouse %/type %/source % %, not warehouse %/type %/source % %)', p_idempotency_key, v_existing.warehouse_id, v_existing.movement_type, v_existing.source_type, v_existing.source_id, p_warehouse_id, p_movement_type, p_source_type, p_source_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  -- Bug class (d), widened (design note 0b): a nested begin/exception unique_violation
  -- recovery -- nothing else has mutated yet at this point in the function, so the
  -- block's own implicit savepoint has nothing else to undo.
  begin
    insert into app.inventory_movements (tenant_id, warehouse_id, movement_type, source_type, source_id, idempotency_key, reason, posted_by, corrects_movement_id)
    values (p_tenant_id, p_warehouse_id, p_movement_type, p_source_type, p_source_id, p_idempotency_key, p_reason, p_actor_label, p_corrects_movement_id)
    returning * into v_movement;
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent movement request', p_idempotency_key using errcode = 'unique_violation';
  end;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_owner_account_id := (v_line ->> 'owner_account_id')::uuid;
    v_item_master_id := (v_line ->> 'item_master_id')::uuid;
    v_location_id := (v_line ->> 'location_id')::uuid;
    v_uom_code := v_line ->> 'uom_code';
    v_signed_quantity := (v_line ->> 'signed_quantity')::numeric;
    v_lot_number := v_line ->> 'lot_number';
    v_serial_number := v_line ->> 'serial_number';
    v_expiry_date := nullif(v_line ->> 'expiry_date', '')::date;
    v_status := coalesce(v_line ->> 'status', 'on_hand');

    if v_signed_quantity is null or v_signed_quantity = 0 then
      raise exception 'invalid_quantity: signed_quantity must be non-zero' using errcode = 'check_violation';
    end if;
    if v_status not in ('on_hand', 'held', 'damaged', 'expired') then
      raise exception 'invalid_status: % is not a recognized balance status', v_status using errcode = 'check_violation';
    end if;
    if not app.validate_uom_code(v_uom_code) then
      raise exception 'invalid_uom: % is not a registered active UOM code', v_uom_code using errcode = 'check_violation';
    end if;

    select * into v_item from app.item_masters where id = v_item_master_id and tenant_id = p_tenant_id and owner_account_id = v_owner_account_id and status = 'active';
    if not found then
      raise exception 'item_not_eligible: % is not an active item master owned by account %', v_item_master_id, v_owner_account_id using errcode = 'check_violation';
    end if;

    -- CG-AUDIT-2026-09-02 E3: app.inventory_balances carries no uom_code
    -- dimension of its own -- every on_hand arithmetic below must operate
    -- in one single, consistent unit per item, never the as-posted unit of
    -- whichever movement happens to run. app.convert_uom_quantity (ATW-
    -- 011A) is the already-governed, already-proven conversion path; its
    -- own early-return makes this a complete no-op when v_uom_code already
    -- equals the item's own base_uom_code (the common case), and it raises
    -- uom_conversion_not_registered (never a silent 1:1 fallback) for a
    -- genuine cross-category mismatch. app.inventory_movement_lines' own
    -- signed_quantity/uom_code below stay the as-posted, as-reported
    -- record -- only the balance arithmetic is normalized.
    v_base_quantity := app.convert_uom_quantity(v_signed_quantity, v_uom_code, v_item.base_uom_code);

    select * into v_location from app.warehouse_locations where id = v_location_id and warehouse_id = p_warehouse_id;
    if not found then
      raise exception 'location_not_eligible: % is not a location of warehouse %', v_location_id, p_warehouse_id using errcode = 'check_violation';
    end if;

    insert into app.inventory_movement_lines (
      tenant_id, movement_id, warehouse_id, owner_account_id, item_master_id, location_id, uom_code,
      signed_quantity, lot_number, serial_number, expiry_date, status
    ) values (
      p_tenant_id, v_movement.id, p_warehouse_id, v_owner_account_id, v_item_master_id, v_location_id, v_uom_code,
      v_signed_quantity, v_lot_number, v_serial_number, v_expiry_date, v_status
    );

    -- Race-safe read-then-write (design note 1, revised) -- deliberately NOT a single
    -- INSERT ... ON CONFLICT DO UPDATE: Postgres validates a table's own CHECK constraints
    -- against the raw candidate row *before* ON CONFLICT ever redirects to the UPDATE
    -- branch, so an upsert of a raw negative delta (e.g. -20 against an existing on_hand
    -- of 100) trips inventory_balances_on_hand_check on the doomed INSERT attempt even
    -- though the real, would-be-updated balance (80) is perfectly valid. SELECT ... FOR
    -- UPDATE against the coalesce-normalized dimension tuple locks the row first (or
    -- proves none exists), the resulting on_hand is computed here in PL/pgSQL, and only
    -- that already-validated value is ever written -- the table's own check constraint
    -- becomes a pure defense-in-depth backstop, never a value the write path can trip
    -- for a legitimate movement. A concurrent first-insert race is resolved by retrying
    -- through the same loop on unique_violation, exactly like app.create_warehouse_location's
    -- own precedent (ATW-014).
    loop
      select id, on_hand, reserved, held into v_balance_id, v_current_on_hand, v_current_reserved, v_current_held
        from app.inventory_balances
        where tenant_id = p_tenant_id and warehouse_id = p_warehouse_id and owner_account_id = v_owner_account_id
          and item_master_id = v_item_master_id and location_id = v_location_id
          and coalesce(lot_number, '') = coalesce(v_lot_number, '') and coalesce(serial_number, '') = coalesce(v_serial_number, '')
          and status = v_status
        for update;

      if found then
        v_new_on_hand := v_current_on_hand + v_base_quantity;
        if v_new_on_hand < 0 then
          raise exception 'insufficient_stock: movement would drive on_hand negative for item % at location %', v_item_master_id, v_location_id
            using errcode = 'check_violation';
        end if;
        -- ATW-032 (ISS-2026-034): app.inventory_balances carries a non-deferrable
        -- `(reserved + held) <= on_hand` CHECK, but nothing in this function ever tested it.
        -- A cycle-count variance approved against stock reserved BEFORE the freeze passes
        -- every guard here and then dies on a raw 23514 that no caller classifies --
        -- 20260730280000's own header named that exact shape as the thing to avoid ("a raw,
        -- unhandled Postgres inventory_balances_reserved_held_bound_check violation instead
        -- of a clean, named domain error, unlike every other rejection path"). It gets one.
        if v_new_on_hand < coalesce(v_current_reserved, 0) + coalesce(v_current_held, 0) then
          raise exception 'insufficient_unreserved_stock: movement would leave on_hand % below reserved % + held % for item % at location %', v_new_on_hand, coalesce(v_current_reserved, 0), coalesce(v_current_held, 0), v_item_master_id, v_location_id
            using errcode = 'check_violation';
        end if;
        update app.inventory_balances
          set on_hand = v_new_on_hand, updated_at = now(), record_version = record_version + 1
          where id = v_balance_id;
        exit;
      else
        v_new_on_hand := v_base_quantity;
        if v_new_on_hand < 0 then
          raise exception 'insufficient_stock: movement would drive on_hand negative for item % at location %', v_item_master_id, v_location_id
            using errcode = 'check_violation';
        end if;
        begin
          insert into app.inventory_balances (
            tenant_id, warehouse_id, owner_account_id, item_master_id, location_id, lot_number, serial_number, status, on_hand
          ) values (
            p_tenant_id, p_warehouse_id, v_owner_account_id, v_item_master_id, v_location_id, v_lot_number, v_serial_number, v_status, v_new_on_hand
          );
          exit;
        exception
          when unique_violation then
            -- Lost a concurrent first-insert race; loop back and take the update branch.
            continue;
        end;
      end if;
    end loop;

    if v_serial_number is not null and v_item.serial_controlled then
      -- ATW-032 (ISS-2026-034): the scope here is deliberately warehouse-wide (no
      -- location_id / owner_account_id predicate) because a serial must be unique across the
      -- whole warehouse -- but a non-strict SELECT INTO over several rows keeps only the
      -- FIRST, so one serial standing at two locations read back as on_hand = 1 and the guard
      -- never fired. The committed comment on this function promises "a serial exceeding 1
      -- fails the whole call"; only SUM makes that true. The existing db-test missed it
      -- because it posted both movements to the same location, hence the same balance row.
      select coalesce(sum(on_hand), 0) into v_serial_on_hand from app.inventory_balances
        where tenant_id = p_tenant_id and warehouse_id = p_warehouse_id and item_master_id = v_item_master_id and serial_number = v_serial_number and status = v_status;
      if v_serial_on_hand > 1 then
        raise exception 'serial_conflict: serial % of item % would exceed on-hand quantity 1', v_serial_number, v_item_master_id using errcode = 'check_violation';
      end if;
    end if;

    if p_movement_type = 'transfer' then
      v_transfer_sum := v_transfer_sum + v_base_quantity;
    end if;
    v_line_count := v_line_count + 1;
  end loop;

  if p_movement_type = 'transfer' and v_transfer_sum <> 0 then
    raise exception 'unbalanced_transfer: a transfer movement''s own lines must sum to exactly zero, got %', v_transfer_sum using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_inventory_movement',
    'app.inventory_movements', v_movement.id, 'success', p_reason, null,
    jsonb_build_object('movement_type', p_movement_type, 'source_type', p_source_type, 'line_count', v_line_count)
  );

  return v_movement;
end;
$function$
;

comment on function app.post_inventory_movement(uuid, uuid, text, text, uuid, text, text, jsonb, uuid, text, uuid) is
  'CG-AUDIT-2026-09-02 E3: on_hand arithmetic now operates on each line''s quantity converted into the item''s own base_uom_code (app.convert_uom_quantity, ATW-011A) rather than the raw as-posted quantity -- app.inventory_balances carries no uom_code dimension of its own, so summing raw quantities across different posted units silently corrupted on_hand. app.inventory_movement_lines'' own signed_quantity/uom_code remain the as-posted, as-reported record, unchanged. A no-op when the posted unit already equals the item''s base unit (the common case); raises uom_conversion_not_registered for a genuine cross-category mismatch rather than corrupting the balance.';
