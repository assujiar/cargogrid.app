-- CG-S10-ATW-032 (post-Prompt-248 audit) — ten verified findings across operations,
-- inventory, WMS and tracking. Every one was re-derived from the live post-migration
-- catalogue and the ratified design before being treated as a defect; the claims from the
-- same batch that did NOT survive are recorded at the bottom of this header rather than
-- quietly dropped.
--
-- 1. **`app.cancel_shipment_order` admitted out-of-matrix edges.** Its guard was "not already
--    cancelled", which was COMPLETE at OPS-169 when the status CHECK only allowed
--    draft/confirmed/cancelled. OPS-170 widened that constraint to eleven statuses without
--    widening the guard, so an `OPS:Edit` holder could drive a settled, CLOSED shipment
--    straight to terminal `cancelled` — defeating `app.transition_shipment_order`'s own
--    `RPD-022` rule that touching a closed shipment requires Supreme Admin. Now restricted to
--    the matrix's genuinely cancellable, pre-ePOD statuses.
--
-- 2. **`app.reserve_inventory`'s replay guard ignored the reserved dimension.**
--    `(source_type, source_id)` is ONE outbound order shared by every line and every
--    substitution on it, so it is not the reservation's identity — the balance and the
--    quantity are. A key first consumed by `approve_wms_pick_substitution` was handed back to
--    a later `generate_wms_pick_task` for a different line of the same order (each caller's
--    own replay guard reads a different table, so neither sees the other's key); that line's
--    stock was never reserved, and `confirm_wms_pick_task` then decremented the
--    substitution's balance instead. `ATW-031`'s own rule — a replay lookup broader than the
--    identity of the request is the defect — was not met.
--
-- 3. **The serial-uniqueness guard read one row instead of summing.** Its scope is
--    deliberately warehouse-wide (no location predicate) because a serial must be unique
--    across the warehouse, but a non-strict `SELECT INTO` over several rows keeps only the
--    first — so one serial standing at two locations read back as `on_hand = 1` and the guard
--    never fired. The function's committed comment promises "a serial exceeding 1 fails the
--    whole call"; only `sum()` makes that true. The existing db-test missed it because it
--    posted both movements to the same location, hence the same balance row.
--
-- 4. **A `reserved + held` breach surfaced as a raw 23514.** `app.inventory_balances` carries
--    a non-deferrable `(reserved + held) <= on_hand` CHECK that nothing in
--    `post_inventory_movement` ever tested. A cycle-count variance approved against stock
--    reserved BEFORE the freeze passes every guard and dies on an unclassified constraint
--    violation — the exact shape `20260730280000`'s header named as the thing to avoid. It
--    now raises `insufficient_unreserved_stock`.
--
-- 5. **`app.complete_epod_capture` was the one member of its family without a row lock.**
--    `20260730480000` swept on the parameter name `p_expected_version`; this function calls
--    its own `p_expected_capture_version` and was invisible to that sweep.
--
-- 6/7. **The two tenant-wide Fleet Control Tower queues skipped `app.can_access_record`**
--    while their own per-shipment siblings enforce it, and so does the architecturally
--    identical `app.get_ops_dashboard_exception_queue`. Both tables have RLS enabled with
--    ZERO policies and no `authenticated` grant, so the `SECURITY DEFINER` function IS the
--    whole access control — an `OPS:View` holder in one branch read every other branch's
--    shipment numbers, exception descriptions and GPS positions.
--    `06_RLS_RBAC_WORKSTREAM.md` §4 places these in the `branch_scoped` family and states
--    that "every export/list/detail query uses the same policy family as its underlying
--    table". The write paths (`confirm_`/`dismiss_`) were already record-scoped, so this was
--    read disclosure, not a write hole.
--
-- 8. **`app.evaluate_geofence_and_deviation_signals` resolved at most one leg per vehicle.**
--    `resource_assignments` is unique per SHIPMENT ORDER, not per resource, so one vehicle is
--    legitimately assigned several concurrent shipments — `20260730320000`'s header says so
--    outright, and the block it added to this function's own caller loops over all of them.
--    `limit 1` over `order by sl.sequence_no` picked one out of a genuine tie, so dwell
--    accumulation and sustained-deviation windows saw a non-deterministic subset of events
--    and the other shipments' signals were dropped entirely.
--
-- 9. **The job-order allocation basis was written and read by two disagreeing rules.** It is
--    WRITTEN when no non-cancelled sibling exists, but READ from the first shipment order
--    ever created "regardless of that row's own current status". Cancel SO#1 and SO#2
--    legitimately declares a new basis the reader never sees. If SO#1 declared a null basis,
--    every later over-allocation check is skipped permanently while the operator sees a
--    declared basis on SO#2. The basis lookup also gains `so.id` as a tiebreak, since
--    `created_at` is the transaction timestamp and not a total order.
--
-- 10. **Direct-device telemetry had no replay dedup, and the gateway guarantees re-delivery.**
--    Its sibling `app.third_party_telemetry_reports` carries
--    `unique (connection_id, provider_event_id)` explicitly "for idempotent replay defense".
--    Any ingest error outside `services/gps-gateway/src/buffer.ts`'s permanent-failure
--    allowlist — a read timeout after the transaction already committed, for instance — is
--    treated as transient and the whole batch is re-sent verbatim. Because the replay creates
--    NEW raw row ids, `arbitrate_and_project_vehicle_position`'s `(source_type,
--    source_report_id)` dedup could not recognise it, so duplicates were canonicalized again
--    and recorded as `stale_event_time` — a wrong reason on a real row — while
--    `accepted_count` reported double the real fix count.
--
-- ===========================================================================
-- Claims from the same batch that did NOT survive verification
-- ===========================================================================
--
-- * "`generate_wms_pick_task` auto-select ignores available stock" — **by design.**
--   `20260730240000` design note 10 ratifies auto-selecting the first FIFO/FEFO candidate,
--   and note 11 enumerates what is re-verified (lot/serial status, expiry, `pick_enabled`),
--   never quantity. Skipping a small oldest lot for a large newer one is precisely what FEFO
--   exists to prevent, and the path is not wedged: `list_allocation_candidates` filters
--   `available > 0`, so the next call returns the next location.
-- * "19 WMS policies admit a `customer_user` actor" — **ratified deferral.**
--   `20260730311000`'s own closing paragraph scopes that migration to the four live-implicated
--   tables and hands the remaining sweep to `ISS-2026-010` / Phase 8. No live `customer_user`
--   principal exists.
-- * "Rejected telemetry still advances `vehicle_source_health.last_location`" —
--   **already fixed** by `20260730430000`.
-- * "Ten forged-signature webhook posts disable a connection" — **by design.**
--   `20260730110000`'s header names forged-signature probing as the triggering condition it
--   was written to respond to, and ships `reenable_third_party_provider_connection` as the
--   recovery path.
--
-- Additive: eleven `CREATE OR REPLACE FUNCTION` on identical signatures. No table, column,
-- constraint, policy or grant is touched, and no already-applied migration file is edited.
-- No grant block: `CREATE OR REPLACE` preserves an existing ACL, so there is nothing to
-- restore, and a blanket re-grant in a mechanical sweep is how an internal helper quietly
-- becomes a public API.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public`.

CREATE OR REPLACE FUNCTION app.cancel_shipment_order(p_shipment_order_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a Shipment Order' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  -- ATW-032 (ISS-2026-034). This guard was written at OPS-169, when the status CHECK
  -- constraint only admitted draft/confirmed/cancelled -- so "not already cancelled" WAS
  -- complete. OPS-170 widened that constraint to eleven statuses and did not widen this
  -- guard, and the function's own committed comment still scopes it to "draft/confirmed ->
  -- cancelled". The result was an out-of-matrix edge: an OPS:Edit holder could drive a
  -- settled, CLOSED shipment straight to the terminal 'cancelled' state, defeating
  -- app.transition_shipment_order's own RPD-022 rule that reopening a closed shipment
  -- requires Supreme Admin. epod is excluded for the same reason -- delivery evidence has
  -- been captured by then.
  if v_shipment.status not in ('draft', 'confirmed', 'planned', 'assigned', 'dispatched', 'in_transit', 'held', 'delivered') then
    raise exception 'invalid_transition: shipment order % is % -- only a pre-ePOD, non-terminal shipment order may be cancelled', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
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

  update app.shipment_orders
  set status = 'cancelled'
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: cancel_shipment_order target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_shipment_order',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.reserve_inventory(p_tenant_id uuid, p_warehouse_id uuid, p_owner_account_id uuid, p_item_master_id uuid, p_location_id uuid, p_lot_number text, p_serial_number text, p_quantity numeric, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.inventory_reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_balance app.inventory_balances;
  v_existing app.inventory_reservations;
  v_reservation app.inventory_reservations;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot reserve stock under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: reservation quantity must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.inventory_reservations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    -- ATW-032 (ISS-2026-034): (source_type, source_id) is ONE outbound order shared by every
    -- line and every substitution on it, so it is not the reservation's identity -- the
    -- balance earmarked and the quantity earmarked are. Without those two, a key first used
    -- by approve_wms_pick_substitution was handed straight back to a later
    -- generate_wms_pick_task for a different line of the same order (each caller's own replay
    -- guard reads a different table, so neither sees the other's key), and that line's stock
    -- was never reserved while confirm_wms_pick_task went on to decrement the substitution's
    -- balance. ATW-031's own stated rule: a replay lookup broader than the identity of the
    -- request is the defect.
    if v_existing.source_type is distinct from p_source_type
       or v_existing.source_id is distinct from p_source_id
       or v_existing.reserved_quantity is distinct from p_quantity
       or v_existing.balance_id is distinct from (
            select b.id from app.inventory_balances b
            where b.tenant_id = p_tenant_id and b.warehouse_id = p_warehouse_id
              and b.owner_account_id = p_owner_account_id and b.item_master_id = p_item_master_id
              and b.location_id = p_location_id
              and coalesce(b.lot_number, '') = coalesce(p_lot_number, '')
              and coalesce(b.serial_number, '') = coalesce(p_serial_number, '')
              and b.status = 'on_hand') then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different inventory reservation (source % %, balance %, quantity %)', p_idempotency_key, v_existing.source_type, v_existing.source_id, v_existing.balance_id, v_existing.reserved_quantity
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_balance from app.inventory_balances
    where tenant_id = p_tenant_id and warehouse_id = p_warehouse_id and owner_account_id = p_owner_account_id
      and item_master_id = p_item_master_id and location_id = p_location_id
      and coalesce(lot_number, '') = coalesce(p_lot_number, '') and coalesce(serial_number, '') = coalesce(p_serial_number, '')
      and status = 'on_hand'
    for update;
  if not found then
    raise exception 'balance_not_found: no on-hand balance exists for the requested dimension' using errcode = 'no_data_found';
  end if;
  if v_balance.available < p_quantity then
    raise exception 'insufficient_available_stock: % available but % requested', v_balance.available, p_quantity using errcode = 'check_violation';
  end if;

  -- Bug class (d), widened by ATW-017 design note 0b: a nested begin/exception
  -- unique_violation recovery around BOTH the reserved-balance mutation and the
  -- reservation insert -- the block's own implicit savepoint cleanly undoes the
  -- reserved-balance increment too, so no partial effect survives a losing race.
  -- Hardening (this migration, on top of ATW-017's own fix): the reserved-balance
  -- UPDATE now also bumps record_version/updated_at identically to app.post_inventory_
  -- movement's own on_hand UPDATE, so a reservation placed against this balance is no
  -- longer invisible to any caller's own optimistic-concurrency check (e.g. ATW-020's
  -- app.approve_cycle_count_variance).
  begin
    update app.inventory_balances set reserved = reserved + p_quantity, updated_at = now(), record_version = record_version + 1 where id = v_balance.id;

    insert into app.inventory_reservations (tenant_id, balance_id, reserved_quantity, source_type, source_id, idempotency_key, created_by)
    values (p_tenant_id, v_balance.id, p_quantity, p_source_type, p_source_id, p_idempotency_key, p_actor_label)
    returning * into v_reservation;
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent reservation request', p_idempotency_key using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'reserve_inventory',
    'app.inventory_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('balance_id', v_balance.id, 'quantity', p_quantity)
  );

  return v_reservation;
end;
$function$
;

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
        v_new_on_hand := v_current_on_hand + v_signed_quantity;
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
        v_new_on_hand := v_signed_quantity;
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
      v_transfer_sum := v_transfer_sum + v_signed_quantity;
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

CREATE OR REPLACE FUNCTION app.complete_epod_capture(p_capture_id uuid, p_expected_capture_version integer, p_shipment_expected_version integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.epod_captures
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.epod_captures;
begin
  -- ATW-032 (ISS-2026-034): 20260730480000 gave this family its row locks by sweeping for
  -- the parameter name p_expected_version; this function calls its own p_expected_capture_
  -- version and was the one member the sweep could not see. Not exploitable today (from
  -- 'approved' no other writer exists), but leaving one sibling unlocked is how the next
  -- writer inherits a race.
  select * into v_capture from app.epod_captures where id = p_capture_id for update;
  if not found then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_capture_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_capture_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status <> 'approved' then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be completed', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  perform app.transition_shipment_order(v_capture.shipment_order_id, 'epod', p_shipment_expected_version, null, p_capture_id::text, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  update app.epod_captures
  set status = 'completed'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$
;
CREATE OR REPLACE FUNCTION app.get_tenant_pending_exception_signals(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, shipment_order_id uuid, shipment_number text, shipment_leg_id uuid, signal_type text, exception_type text, severity text, detected_at timestamp with time zone, description text, location_geojson jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ATW-032 (ISS-2026-034): the tenant-wide queue read the whole tenant while its own
  -- per-shipment sibling (app.get_shipment_exception_signals / _milestone_candidates) gates
  -- on app.can_access_record, and so does the architecturally identical
  -- app.get_ops_dashboard_exception_queue. 06_RLS_RBAC_WORKSTREAM.md §4 places these OPS
  -- tables in the branch_scoped family and states plainly that "every export/list/detail
  -- query uses the same policy family as its underlying table" -- a record-scoped detail
  -- query beside a tenant-wide list query is exactly the divergence that forbids. These
  -- tables have RLS on with zero policies and no authenticated grant, so this definer
  -- function IS the whole access control.
  return query
  select
    s.id, s.shipment_order_id, so.shipment_number, s.shipment_leg_id,
    s.signal_type, s.exception_type, s.severity, s.detected_at, s.description,
    case when s.location is not null then ST_AsGeoJSON(s.location)::jsonb else null end
  from app.shipment_exception_signals s
  join app.shipment_orders so on so.id = s.shipment_order_id
  where s.tenant_id = p_tenant_id and s.status = 'pending'
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id,
          app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  order by s.detected_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_tenant_pending_milestone_candidates(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, shipment_order_id uuid, shipment_number text, shipment_leg_id uuid, shipment_leg_stop_id uuid, milestone_code text, candidate_event_time timestamp with time zone, detected_at timestamp with time zone, location_geojson jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ATW-032 (ISS-2026-034): the tenant-wide queue read the whole tenant while its own
  -- per-shipment sibling (app.get_shipment_exception_signals / _milestone_candidates) gates
  -- on app.can_access_record, and so does the architecturally identical
  -- app.get_ops_dashboard_exception_queue. 06_RLS_RBAC_WORKSTREAM.md §4 places these OPS
  -- tables in the branch_scoped family and states plainly that "every export/list/detail
  -- query uses the same policy family as its underlying table" -- a record-scoped detail
  -- query beside a tenant-wide list query is exactly the divergence that forbids. These
  -- tables have RLS on with zero policies and no authenticated grant, so this definer
  -- function IS the whole access control.
  return query
  select
    c.id, c.shipment_order_id, so.shipment_number, c.shipment_leg_id, c.shipment_leg_stop_id,
    c.milestone_code, c.candidate_event_time, c.detected_at,
    case when c.location is not null then ST_AsGeoJSON(c.location)::jsonb else null end
  from app.shipment_milestone_candidates c
  join app.shipment_orders so on so.id = c.shipment_order_id
  where c.tenant_id = p_tenant_id and c.status = 'pending'
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id,
          app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  order by c.detected_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$function$
;
CREATE OR REPLACE FUNCTION app.evaluate_geofence_and_deviation_signals(p_tenant_id uuid, p_vehicle_master_id uuid, p_canonical_event_id uuid, p_location geography, p_event_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_policy app.shipment_leg_tracking_policies;
begin
  if p_location is null then
    return;
  end if;

  -- ATW-032 (ISS-2026-034). resource_assignments' uniqueness is per SHIPMENT ORDER
  -- (`unique (tenant_id, shipment_order_id, role) where is_current`), not per resource, so one
  -- vehicle is legitimately the current assignee on several shipments at once --
  -- 20260730320000's own header states it outright ("there may legitimately be zero, one, or
  -- more than one active shipment concurrently assigned the same vehicle -- no 'exactly one'
  -- assumption"), and the block that migration added to the very caller of this function
  -- loops over all of them. `limit 1` on `order by sl.sequence_no` therefore picked one leg
  -- out of a genuine tie -- sequence_no is unique only within a shipment order -- so
  -- evaluate_stop_geofence's dwell accumulation and evaluate_route_deviation's sustained-
  -- deviation window each saw a non-deterministic subset of a vehicle's events, and the other
  -- shipments' geofence and deviation signals were dropped entirely.
  for v_leg in
    select sl.*
    from app.resource_assignments ra
    join app.shipment_legs sl on sl.shipment_order_id = ra.shipment_order_id and sl.leg_status in ('dispatched', 'in_transit')
    where ra.role = 'vehicle' and ra.resource_id = p_vehicle_master_id and ra.is_current and ra.status = 'active'
    order by sl.shipment_order_id, sl.sequence_no, sl.id
  loop
    select * into v_policy from app.shipment_leg_tracking_policies where shipment_leg_id = v_leg.id;
    if found and v_policy.status = 'active' and v_policy.tracking_required and v_policy.geofence_policy is not null
       and app.safe_jsonb_boolean(v_policy.geofence_policy, 'enabled', true) then
      perform app.evaluate_stop_geofence(p_tenant_id, v_leg.id, p_canonical_event_id, p_location, p_event_at, v_policy.geofence_policy);
      perform app.evaluate_route_deviation(p_tenant_id, v_leg.id, p_canonical_event_id, p_location, p_event_at, v_policy.geofence_policy);
    end if;
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.get_job_shipment_allocation_balance(p_job_order_id uuid, p_actor_auth_user_id uuid DEFAULT auth.uid())
 RETURNS TABLE(basis_quantity numeric, basis_weight_kg numeric, basis_volume_cbm numeric, allocated_quantity numeric, allocated_weight_kg numeric, allocated_volume_cbm numeric, remaining_quantity numeric, remaining_weight_kg numeric, remaining_volume_cbm numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_basis_qty numeric;
  v_basis_weight numeric;
  v_basis_volume numeric;
  v_alloc_qty numeric;
  v_alloc_weight numeric;
  v_alloc_volume numeric;
begin
  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- The basis is declared once, on the very first Shipment Order ever created for
  -- this Job Order -- looked up across every row regardless of its own current
  -- status, since a later cancellation of that first row must never erase the
  -- basis it already declared.
  select so.basis_quantity, so.basis_weight_kg, so.basis_volume_cbm
    into v_basis_qty, v_basis_weight, v_basis_volume
  from app.shipment_orders so
  where so.job_order_id = p_job_order_id
  -- ATW-032 (ISS-2026-034): created_at alone is not a total order (it is the transaction
  -- timestamp), so "the very first Shipment Order ever created" was ambiguous for any two
  -- rows sharing it. so.id breaks the tie deterministically.
  order by so.created_at asc, so.id asc
  limit 1;

  select coalesce(sum(so.allocated_quantity), 0), coalesce(sum(so.allocated_weight_kg), 0), coalesce(sum(so.allocated_volume_cbm), 0)
    into v_alloc_qty, v_alloc_weight, v_alloc_volume
  from app.shipment_orders so
  where so.job_order_id = p_job_order_id and so.status <> 'cancelled';

  return query select
    v_basis_qty, v_basis_weight, v_basis_volume,
    v_alloc_qty, v_alloc_weight, v_alloc_volume,
    case when v_basis_qty is null then null else v_basis_qty - v_alloc_qty end,
    case when v_basis_weight is null then null else v_basis_weight - v_alloc_weight end,
    case when v_basis_volume is null then null else v_basis_volume - v_alloc_volume end;
end;
$function$
;
CREATE OR REPLACE FUNCTION app.create_shipment_order_from_job(p_job_order_id uuid, p_idempotency_key text, p_consignee jsonb, p_notify_party jsonb, p_service_type text, p_mode text, p_origin text, p_destination text, p_planned_pickup_at timestamp with time zone, p_planned_delivery_at timestamp with time zone, p_allocated_quantity numeric, p_allocated_weight_kg numeric, p_allocated_volume_cbm numeric, p_basis_quantity numeric, p_basis_weight_kg numeric, p_basis_volume_cbm numeric, p_split_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_orders;
  v_shipment app.shipment_orders;
  v_number text;
  v_existing_count integer;
  v_any_count integer;
  v_balance record;
  v_basis_quantity numeric;
  v_basis_weight_kg numeric;
  v_basis_volume_cbm numeric;
begin
  if p_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode' , p_mode using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_job from app.job_orders where id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'confirmed' then
    raise exception 'job_order_not_confirmed: job order % is % and is not eligible for Shipment Order creation', p_job_order_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.shipment_orders where tenant_id = v_job.tenant_id and job_order_id = p_job_order_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
    -- conflict, never a replay. Returning the earlier target's row here silently
    -- misattributed this request to it (or silently discarded it entirely).
    if v_existing.mode is distinct from p_mode or v_existing.origin is distinct from p_origin or v_existing.destination is distinct from p_destination or v_existing.service_type is distinct from p_service_type then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different shipment order split (mode %/route %->%, not mode %/route %->%)', p_idempotency_key, v_existing.mode, v_existing.origin, v_existing.destination, p_mode, p_origin, p_destination
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_existing_count from app.shipment_orders where job_order_id = p_job_order_id and status <> 'cancelled';
  -- ATW-032 (ISS-2026-034): the basis is WRITTEN when no NON-CANCELLED sibling exists, but
  -- app.get_job_shipment_allocation_balance READS it from the very first shipment order ever
  -- created for the job, "regardless of that row's own current status" (its own committed
  -- comment). Cancel SO#1 and SO#2 legitimately declares a new basis -- which the reader then
  -- never sees, because it is still resolving SO#1. If SO#1 declared a null basis, every
  -- later over-allocation check is skipped permanently while the operator sees a declared
  -- basis on SO#2. v_any_count matches the reader's scope exactly; v_existing_count keeps its
  -- own, different and correct, job: deciding whether a split_reason is required.
  select count(*) into v_any_count from app.shipment_orders where job_order_id = p_job_order_id;
  if v_existing_count > 0 and (p_split_reason is null or length(trim(p_split_reason)) = 0) then
    raise exception 'split_reason_required: a non-empty split_reason is required when another Shipment Order already exists for job order %', p_job_order_id
      using errcode = 'check_violation';
  end if;

  if v_any_count > 0 then
    select * into v_balance from app.get_job_shipment_allocation_balance(p_job_order_id, p_actor_auth_user_id);
    if v_balance.basis_quantity is not null and coalesce(p_allocated_quantity, 0) > coalesce(v_balance.remaining_quantity, 0) then
      raise exception 'over_allocation: allocated_quantity % exceeds remaining % for job order %', p_allocated_quantity, v_balance.remaining_quantity, p_job_order_id
        using errcode = 'check_violation';
    end if;
    if v_balance.basis_weight_kg is not null and coalesce(p_allocated_weight_kg, 0) > coalesce(v_balance.remaining_weight_kg, 0) then
      raise exception 'over_allocation: allocated_weight_kg % exceeds remaining % for job order %', p_allocated_weight_kg, v_balance.remaining_weight_kg, p_job_order_id
        using errcode = 'check_violation';
    end if;
    if v_balance.basis_volume_cbm is not null and coalesce(p_allocated_volume_cbm, 0) > coalesce(v_balance.remaining_volume_cbm, 0) then
      raise exception 'over_allocation: allocated_volume_cbm % exceeds remaining % for job order %', p_allocated_volume_cbm, v_balance.remaining_volume_cbm, p_job_order_id
        using errcode = 'check_violation';
    end if;
  end if;

  if v_any_count = 0 then
    v_basis_quantity := p_basis_quantity;
    v_basis_weight_kg := p_basis_weight_kg;
    v_basis_volume_cbm := p_basis_volume_cbm;
  end if;

  v_number := app.next_shipment_number(v_job.tenant_id);

  begin
    insert into app.shipment_orders (
      tenant_id, job_order_id, shipment_number, idempotency_key, shipper_account_id,
      consignee_snapshot, notify_party_snapshot, cargo_service_snapshot,
      service_type, mode, origin, destination, planned_pickup_at, planned_delivery_at,
      basis_quantity, basis_weight_kg, basis_volume_cbm,
      allocated_quantity, allocated_weight_kg, allocated_volume_cbm, split_reason,
      owner_user_id, created_by
    ) values (
      v_job.tenant_id, p_job_order_id, v_number, p_idempotency_key, v_job.account_id,
      coalesce(p_consignee, v_job.customer_snapshot), p_notify_party, v_job.cargo_service_snapshot,
      p_service_type, p_mode, p_origin, p_destination, p_planned_pickup_at, p_planned_delivery_at,
      v_basis_quantity, v_basis_weight_kg, v_basis_volume_cbm,
      p_allocated_quantity, p_allocated_weight_kg, p_allocated_volume_cbm, p_split_reason,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_shipment;
  exception
    when unique_violation then
      select * into v_shipment from app.shipment_orders where tenant_id = v_job.tenant_id and job_order_id = p_job_order_id and idempotency_key = p_idempotency_key;
      return v_shipment;
  end;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_shipment_order_from_job',
    'app.shipment_orders', v_shipment.id, 'success', null, null,
    jsonb_build_object('job_order_id', p_job_order_id, 'shipment_number', v_number, 'split_reason', p_split_reason)
  );

  return v_shipment;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.ingest_direct_device_telemetry_batch(p_raw_api_key text, p_device_id uuid, p_reports jsonb, p_gateway_instance_label text)
 RETURNS TABLE(device_id uuid, tenant_id uuid, accepted_count integer, device_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_auth record;
  v_device app.gps_devices;
  v_report jsonb;
  v_report_type text;
  v_event_at timestamptz;
  v_lon numeric;
  v_lat numeric;
  v_geojson jsonb;
  v_geog geography;
  v_accepted integer := 0;
  v_max_event_at timestamptz;
  v_new_status text;
  v_label text;
  v_report_id uuid;
  v_received_at timestamptz;
  v_vehicle_master_id uuid;
begin
  if p_device_id is null then
    raise exception 'device_id_required: a device_id is required' using errcode = 'check_violation';
  end if;
  if p_reports is null or jsonb_typeof(p_reports) <> 'array' or jsonb_array_length(p_reports) = 0 then
    raise exception 'reports_required: at least one report is required' using errcode = 'check_violation';
  end if;

  select * into v_auth from app.authenticate_api_key(p_raw_api_key);

  if not app.api_key_has_scope(v_auth.api_key_id, 'OPS:Edit') then
    raise exception 'insufficient_authority: presented API key lacks OPS:Edit scope required for GPS gateway operation'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;
  if v_device.tenant_id <> v_auth.tenant_id then
    raise exception 'tenant_mismatch: device % belongs to a different tenant than the presented API key', p_device_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_device.status not in ('installed', 'active', 'offline') then
    raise exception 'device_not_ingestible: device % is % and cannot accept telemetry', p_device_id, v_device.status
      using errcode = 'check_violation';
  end if;

  v_label := coalesce(p_gateway_instance_label, 'gps-gateway') || ':' || v_device.imei;
  v_max_event_at := v_device.last_telemetry_at;
  v_vehicle_master_id := app.resolve_vehicle_for_gps_device(v_device.id);

  for v_report in select * from jsonb_array_elements(p_reports)
  loop
    v_report_type := v_report ->> 'report_type';
    if v_report_type not in ('location', 'heartbeat') then
      raise exception 'invalid_report_type: % is not a supported report type', v_report_type using errcode = 'check_violation';
    end if;

    v_event_at := (v_report ->> 'event_at')::timestamptz;
    if v_event_at is null then
      raise exception 'event_at_required: every report requires event_at' using errcode = 'check_violation';
    end if;

    v_geog := null;
    if v_report_type = 'location' then
      v_lon := (v_report ->> 'longitude')::numeric;
      v_lat := (v_report ->> 'latitude')::numeric;
      if v_lon is null or v_lat is null then
        raise exception 'location_required: a location report requires longitude and latitude' using errcode = 'check_violation';
      end if;
      v_geojson := jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(v_lon, v_lat));
      v_geog := app.geojson_point_to_geography(v_geojson);
    end if;

    -- ATW-032 (ISS-2026-034): this ingest had no replay defence at all, while its sibling
    -- app.third_party_telemetry_reports carries `unique (connection_id, provider_event_id)`
    -- explicitly "for idempotent replay defense". The gateway GUARANTEES re-delivery: any
    -- ingest error outside services/gps-gateway/src/buffer.ts's permanent-failure allowlist
    -- -- a read timeout after the transaction already committed, for instance -- is treated
    -- as transient, the batch stays in the durable buffer and the whole batch is re-sent
    -- verbatim on the next flush. Because the replay produces NEW raw row ids,
    -- arbitrate_and_project_vehicle_position's own (source_type, source_report_id) dedup
    -- cannot recognise it, so every duplicate was canonicalized again and recorded as
    -- 'stale_event_time' -- a wrong reason on a real row -- while accepted_count reported
    -- double the real fix count on the audit trail. A device cannot produce two distinct
    -- reports of the same type at the same event_at, so this is a safe identity.
    -- Aliased: this function's own OUT parameters are named device_id/tenant_id, so an
    -- unqualified column reference here is ambiguous between the variable and the column.
    if exists (
      select 1 from app.direct_device_telemetry_reports r
      where r.device_id = v_device.id and r.event_at = v_event_at and r.report_type = v_report_type
    ) then
      continue;
    end if;

    -- received_at uses clock_timestamp(), not the column's own now()-based default --
    -- a single batch call inserts every one of its reports inside one transaction, and
    -- now() is frozen at transaction start (identical for every row in the loop);
    -- clock_timestamp() genuinely advances per iteration, so "newest first" ordering
    -- downstream (app.get_direct_device_telemetry_reports) stays meaningful even for
    -- reports that share one ingestion batch.
    v_received_at := clock_timestamp();
    insert into app.direct_device_telemetry_reports (
      tenant_id, device_id, report_type, event_at, received_at, location,
      altitude_meters, heading_degrees, speed_kmh, satellite_count, raw_codec_id, io_elements
    ) values (
      v_device.tenant_id, v_device.id, v_report_type, v_event_at, v_received_at, v_geog,
      (v_report ->> 'altitude_meters')::numeric, (v_report ->> 'heading_degrees')::numeric,
      (v_report ->> 'speed_kmh')::numeric, (v_report ->> 'satellite_count')::integer,
      coalesce(v_report ->> 'raw_codec_id', '8E'), coalesce(v_report -> 'io_elements', '{}'::jsonb)
    )
    returning id into v_report_id;

    v_accepted := v_accepted + 1;
    if v_max_event_at is null or v_event_at > v_max_event_at then
      v_max_event_at := v_event_at;
    end if;

    -- ATW-226F: canonicalize -- never raises, never blocks the already-committed raw insert above.
    if v_vehicle_master_id is not null then
      perform app.arbitrate_and_project_vehicle_position(
        v_device.tenant_id, v_vehicle_master_id, 'direct_device', v_report_id, v_event_at, v_received_at,
        v_geog, (v_report ->> 'speed_kmh')::numeric, (v_report ->> 'heading_degrees')::numeric, null::numeric
      );
    end if;
  end loop;

  v_new_status := v_device.status;
  if v_device.status in ('installed', 'offline') then
    v_new_status := 'active';
  end if;

  update app.gps_devices
  set last_telemetry_at = v_max_event_at,
      status = v_new_status
  where id = v_device.id
  returning * into v_device;

  perform app.capture_audit_event(
    v_device.tenant_id, null, v_label, 'ingest_direct_device_telemetry_batch',
    'app.gps_devices', v_device.id, 'success', null, null,
    jsonb_build_object('device_id', v_device.id, 'accepted_count', v_accepted, 'device_status', v_new_status)
  );

  return query select v_device.id, v_device.tenant_id, v_accepted, v_device.status;
end;
$function$
;

revoke execute on all functions in schema app from public;
