-- Advanced TMS/WMS capability ATW-017 (CG-S10-ATW-017, Prompt 236, "WMS Picking" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). Implements this
-- prompt's own §4 objective: "exact reservation and scan-confirmed picking from
-- eligible inventory for outbound demand, including partial, short and governed
-- substitution."
--
-- Direct upstream (Prompt 236 §9's own "ATW-234..235 and a confirmed outbound demand
-- contract"): ATW-015 (Inventory Ledger -- app.reserve_inventory/app.release_
-- inventory_reservation/app.post_inventory_movement, composed, never re-implemented),
-- ATW-016 (Lot/Batch/Serial/Expiry -- app.list_allocation_candidates/app.
-- actor_can_view_owner_scoped_row, composed directly), ATW-016A (WMS Outbound Order,
-- an inserted checkpoint built immediately before this one in this same session
-- specifically to resolve Prompt 236 §9's own named circular dependency --
-- app.wms_outbound_orders/app.wms_outbound_order_lines is the real "confirmed outbound
-- demand contract" this migration allocates/picks against), ATW-014 (WMS Putaway --
-- the closest structural precedent for this migration's own task lifecycle shape).
--
-- Design boundary (disclosed):
--
-- 1. **One pick task per (outbound order line, allocated balance/reservation)
--    generation call, never a single header row with a caller-opaque array of source
--    lines** -- mirrors ATW-014's own design note 1 exactly, one level up: a line
--    requiring 3 units split across 2 lots becomes 2 pick tasks, each independently
--    claimable/confirmable, each idempotent on its own (tenant_id, idempotency_key).
-- 2. **"Batch compatible lines into a wave" (Prompt 236 §22) is a lightweight,
--    STATE-MACHINE-FREE grouping header (`app.wms_pick_waves`), not a full lifecycle
--    entity.** A wave carries only a real, tenant-scoped monotonic `wave_number` (the
--    identical counter-table idiom `app.next_wms_outbound_order_number`, ATW-016A,
--    already established) and no `status` column at all -- a wave's own completion
--    state is always DERIVED by querying its member `app.wms_pick_tasks` rows'
--    statuses, never tracked as a second, potentially-inconsistent source of truth.
--    This is the simpler of the two shapes the task brief names, chosen because a
--    wave here is purely a caller-visible grouping/routing label (real referential
--    integrity via a genuine `wave_id` foreign key, unlike a bare freeform uuid
--    column), never an approval or release gate a task's own lifecycle depends on.
-- 3. **The double-allocation lock (Prompt 236 §33's own headline acceptance
--    criterion, "concurrent orders cannot double-allocate stock"): `app.generate_
--    wms_pick_task` locks the target `app.wms_outbound_order_lines` row itself
--    (`SELECT ... FOR UPDATE`) BEFORE computing `sum(task_quantity - short_quantity)`
--    across that line's own already-generated, non-cancelled pick tasks.** This is
--    the exact bug-class-(e) fix the task brief names: an unlocked cross-row
--    aggregate read of "how much is already allocated" would let two concurrent
--    generation calls against the SAME line both observe the same stale "0 already
--    allocated" and both reserve the full requested_quantity, double-allocating.
--    Locking the LINE row (mirrors `app.generate_wms_putaway_task`'s own receipt-line
--    lock, `ATW-014`, one level up the entity graph) serializes concurrent generation
--    attempts against that line: the second caller blocks until the first commits (or
--    rolls back), then observes the first's own real, committed `task_quantity` in its
--    own aggregate read. `app.reserve_inventory`'s own per-balance-row `FOR UPDATE`
--    lock (`ATW-015`) closes a DIFFERENT, narrower race (two reservations against the
--    identical balance dimension) -- it does not by itself prevent two pick tasks from
--    each independently reserving the line's own full remaining quantity against TWO
--    DIFFERENT balance dimensions (e.g. two different lots of the same item), which is
--    exactly the gap the line-row lock closes. `short_quantity` is subtracted in the
--    aggregate (design note 9 below) so a released short quantity is correctly
--    available for re-generation, never permanently "stuck" as allocated.
-- 4. **The pick-confirm transfer's own interaction with `app.inventory_balances.
--    reserved` (the task brief's own required disclosure) -- exact statement order,
--    inside `app.confirm_wms_pick_task`'s own single transaction:**
--    (1) lock the task row (`FOR UPDATE`, held from the function's first statement);
--    (2) lock the reservation row, then its own backing `app.inventory_balances` row
--        (`FOR UPDATE`);
--    (3) `UPDATE app.inventory_balances SET reserved = reserved - p_quantity ...` --
--        FIRST, strictly BEFORE the transfer;
--    (4) only then call `app.post_inventory_movement` (`movement_type = 'transfer'`),
--        whose own per-line loop decrements the SAME source balance row's `on_hand` by
--        the identical `p_quantity`.
--    This order is load-bearing, not stylistic: `app.inventory_balances`' own
--    `reserved + held <= on_hand` CHECK is evaluated immediately after EVERY
--    individual `UPDATE` (not deferred). Before step (3), the invariant `reserved <=
--    on_hand` already held (system-wide, always true); reducing `reserved` by
--    `p_quantity` FIRST only widens that slack (`reserved - p_quantity <= on_hand`
--    trivially, since `reserved <= on_hand`already). Only THEN does step (4) reduce
--    `on_hand` by the identical `p_quantity` -- since both sides of the inequality
--    shrink by the SAME amount, `(reserved - p_quantity) + held <= (on_hand -
--    p_quantity)` reduces algebraically to the already-true `reserved + held <=
--    on_hand`, so the CHECK constraint is satisfied at every intermediate statement.
--    Reversing this order (transfer first, reserved-decrement second) would transiently
--    violate the CHECK the moment `on_hand` drops while `reserved` still reflects the
--    old, larger value -- exactly the failure mode the task brief's own reasoning
--    names. `p_quantity <= v_task.remaining_quantity` (checked earlier, over-pick hard
--    rejection) guarantees this task's own live contribution to `reserved` is always
--    `>= p_quantity`, so the decrement in step (3) never drives `reserved` negative for
--    this task's own share.
--    `app.consume_inventory_reservation` (`ATW-015`) is deliberately never called here
--    -- picked stock has only moved to a staging/pack location, it has not left the
--    warehouse (Prompt 238/`ATW-019`'s own later ship-confirm job), so a negative
--    `consumption` movement here would be a real scope/semantics error, per the task
--    brief's own explicit instruction.
-- 5. **Reservation bookkeeping is intentionally decoupled from `app.inventory_
--    reservations.reserved_quantity`, which stays exactly as originally set (`ATW-015`'s
--    own "never mutated in place" design), while the LIVE `app.inventory_balances.
--    reserved` is decremented incrementally, once per confirm/short event, as
--    described in design note 4/9.** Neither `app.release_inventory_reservation` nor
--    `app.consume_inventory_reservation` is ever called mid-pick (both assume a
--    ONE-SHOT full-amount transition and would double-decrement `reserved` against my
--    own incremental decrements). Once a task's own `remaining_quantity` reaches zero
--    (fully picked, fully short, or a mix), this migration performs one direct, raw
--    `UPDATE app.inventory_reservations SET status = 'released', released_reason = ...`
--    -- reusing the identical terminal-status value `app.release_inventory_reservation`
--    itself uses (`'released'`, the more accurate of the two closed enum values here,
--    since no `consumption` ledger movement was ever posted by this mechanism), but
--    via a raw statement rather than the shared function, to avoid its own
--    full-original-amount re-decrement. `app.cancel_wms_pick_task`, by contrast, is
--    only ever callable on a task with ZERO progress (design note 8) -- exactly the one
--    case where the shared `app.release_inventory_reservation` (full, un-decremented
--    amount) is correct and safe to call directly, and it is the ONLY place in this
--    migration that does.
-- 6. **Short-pick handling (task brief's own required disclosure): confirming LESS
--    than a task's own `remaining_quantity` is a legitimate, ordinary partial pick
--    (`status = 'partial'`), never an error.** A picker who cannot find the remaining
--    quantity at all calls the DISTINCT `app.record_wms_pick_task_short` action (Prompt
--    236 §22's own separate "record short" alt-flow, not folded into confirm) --
--    `short_quantity` increases, and that exact amount is released from `app.
--    inventory_balances.reserved` immediately (design note 5), making it available
--    again for a fresh `app.generate_wms_pick_task` call against the same line (a
--    supervisor may re-allocate the shortfall against a different lot/location; design
--    note 3's own aggregate formula already excludes `short_quantity`, so this is
--    structurally free to re-allocate, never double-counted as still-outstanding).
--    Confirming MORE than `remaining_quantity` (whether via a fresh pick or a short
--    request) is a hard, structural rejection (`exceeds_remaining_quantity`) in both
--    `app.confirm_wms_pick_task` and `app.record_wms_pick_task_short` -- never
--    silently clamped.
-- 7. **A pick task references its own outbound order line's governed `lot_controlled`/
--    `serial_controlled`/`expiry_controlled` snapshot (`ATW-016A` design note 6),
--    copied onto the task at generation time.** `app.confirm_wms_pick_task`'s own scan
--    verification requires an exact-matching `p_scanned_lot_number`/`p_scanned_serial_
--    number` if and only if the task's own snapshot says the item is lot/serial
--    controlled (mirrors `app.confirm_wms_putaway_task`'s own identical lot/serial
--    mismatch gate, `ATW-014`) -- an uncontrolled item never demands an irrelevant
--    scan field, matching Prompt 235 §33's own "uncontrolled items avoid unnecessary
--    fields" precedent this session has already established. A scanned SOURCE
--    LOCATION is always required and must exactly match the task's own `source_
--    location_id` (`location_mismatch` otherwise) -- picking, unlike putaway, has a
--    fixed, already-reserved SOURCE (chosen authoritatively at generation time, design
--    note 10), so the source is verified, not merely a destination suggested.
-- 8. **`app.cancel_wms_pick_task` is only ever callable while a task has made
--    genuinely ZERO progress (`picked_quantity = 0 AND short_quantity = 0`)** --
--    mirrors `app.cancel_wms_putaway_task`'s own "has_confirmed_quantity" guard
--    exactly, one level up. Only in this exact case is the task's own backing `app.
--    inventory_reservations` row's `reserved_quantity` still identical to what remains
--    outstanding, so calling the SHARED `app.release_inventory_reservation` directly
--    (full, un-decremented amount) is correct (design note 5). A task with any real
--    progress can only be resolved forward (picked/short) or handed off via `app.
--    reassign_wms_pick_task`, never cancelled -- Prompt 236 §32's own "release only
--    unpicked reservations/tasks, preserve confirmed movements."
-- 9. **Governed substitution (task brief's own disclosed bound): a REAL, bounded
--    feature, not a substitution-rules engine.** `app.approve_wms_pick_substitution`
--    is `OPS:Override`-gated (supervisor-only), callable ONLY while a task has zero
--    progress (mirrors design note 8's own precondition, avoiding any need to unwind a
--    partially-posted transfer), requires the caller-nominated substitute item to
--    share the SAME `base_uom_code` as the task's own `uom_code` (a disclosed,
--    bounded restriction -- no cross-UOM conversion is attempted), releases the
--    original reservation in FULL via the shared `app.release_inventory_reservation`
--    (safe here for the identical zero-progress reason design note 8 names), reserves
--    fresh stock against the substitute item via `app.reserve_inventory`, and inserts
--    one real, append-only, auditable `app.wms_pick_substitution_approvals` row
--    linking the original and substitute item/reservation and the approving
--    supervisor -- never a silent re-run of allocation against a different item with
--    no trace. `substituted_from_item_master_id` on the task always preserves the
--    ORIGINAL item across possibly-repeated substitutions (never the immediately-prior
--    one), and every approval remains individually queryable via `app.list_wms_pick_
--    substitution_approvals`. No auto-suggested-substitute engine is built -- the
--    substitute item is always caller/supervisor-nominated, per the task brief.
-- 10. **The SOURCE of a pick, unlike `ATW-014`'s own putaway DESTINATION, is
--     authoritative at generation time, never merely decision support.** `app.
--     reserve_inventory` (`ATW-015`) is a real commitment the moment it succeeds, so
--     `app.generate_wms_pick_task` either (a) resolves a caller-supplied `p_location_
--     id`/`p_lot_number`/`p_serial_number` candidate, independently re-verified for
--     genuine eligibility (see design note 11 -- `app.reserve_inventory` itself does
--     NOT check lot/serial hold/quarantine/expiry status), or (b) auto-selects the
--     first FIFO/FEFO-ordered, still-eligible candidate returned by `app.list_
--     allocation_candidates` (`ATW-016`, reused directly, never re-queried a second
--     way). The pick-confirm DESTINATION (a staging location), by contrast, mirrors
--     `ATW-014`'s own suggested/actual split exactly: `suggested_destination_location_
--     id` is real decision support only (auto-suggested or caller-supplied, sanity-
--     checked for same-warehouse/`location_type = 'staging'` only), and `app.confirm_
--     wms_pick_task` alone performs the one authoritative destination eligibility/
--     capacity check, at first real confirm, exactly like `app.confirm_wms_putaway_
--     task`'s own design note 5.
-- 11. **A proactively-found-and-fixed gap, disclosed per the task brief's own
--     instruction to report any new defect found while authoring:** `app.reserve_
--     inventory` (`ATW-015`) only checks that a balance row exists with sufficient
--     `available` quantity -- it does NOT check the backing `app.lot_identities`/`app.
--     serial_identities` row's own `status`/`expiry_date` at all (that governance
--     layer, `ATW-016`, postdates `ATW-015`). A caller who supplies an explicit `p_
--     location_id`/`p_lot_number`/`p_serial_number` to `app.generate_wms_pick_task`
--     (bypassing `app.list_allocation_candidates`' own decision-support exclusion of
--     held/quarantined/expired stock) could therefore otherwise reserve and pick
--     blocked or expired stock outright, directly contradicting Prompt 236 §23's own
--     "block ... expired/held stock" exception flow and §25's own "reject ...
--     mismatch" validation rule. `app.generate_wms_pick_task` independently
--     re-verifies eligibility for a caller-supplied candidate using the IDENTICAL
--     predicate `app.list_allocation_candidates` itself uses (lot/serial `status =
--     'active'` and `expiry_date` not yet passed, when a governing identity row
--     exists) before ever calling `app.reserve_inventory` -- closing this gap
--     structurally rather than trusting the caller. The identical, already-governed
--     `pick_enabled` column on `app.warehouse_locations` (`ATW-013`, previously unused
--     by any capability until now, the identical "reuse an already-governed field"
--     precedent `ATW-014`'s own design note 4 already used for `putaway_enabled`) is
--     also enforced for BOTH the caller-supplied and auto-selected source location --
--     `app.list_allocation_candidates` itself does not join `app.warehouse_locations`
--     at all, so this migration's own auto-select loop walks its ordered candidate
--     rows and skips any whose own location is not `pick_enabled`/`active`, taking the
--     first that is.
-- 12. **Two already-applied migrations' own closed `source_type` CHECK enums did not
--     anticipate an outbound-driven reservation/movement** (`app.inventory_
--     reservations_source_type_check`: `wms_inbound_order`/`manual` only; `app.
--     inventory_movements_source_type_check`: `wms_inbound_order`/`reservation`/
--     `manual`/`opening_balance`/`reversal`, `ATW-015`, an already-applied migration,
--     never edited). `ATW-014`'s own design note 6 chose to REUSE `wms_inbound_order`
--     for its own (genuinely inbound-lineage) putaway transfer rather than widen the
--     constraint -- that reuse would be actively MISLEADING here (an outbound pick
--     reservation is not inbound-lineage), and Prompt 236 §33's own acceptance
--     criterion ("every pick is scan/source/ledger traceable") weighs directly against
--     overloading an inaccurate existing value. This migration instead performs a
--     real, disclosed, ADDITIVE expand-migration (`ALTER TABLE ... DROP CONSTRAINT ...
--     ADD CONSTRAINT ...`, the identical pattern `20260727110000_create_operations_
--     shipment_lifecycle.sql` already used to widen `app.shipment_orders_status_
--     check`) to add a genuine `'wms_outbound_order'` member to BOTH enums -- never
--     editing the original `ATW-015` migration file itself, fully additive, and
--     directly serving traceability rather than working around it.
-- 13. **`app.cancel_wms_outbound_order` (`ATW-016A`) is widened via a same-signature
--     `CREATE OR REPLACE`, exactly as `ATW-016A`'s own design note 8 obligates this
--     checkpoint to do** (mirrors `ATW-013`'s own identical widening of `ATW-012`'s
--     `app.cancel_wms_inbound` once WMS Receiving went live). Cancellation of a
--     confirmed outbound order is now blocked while ANY non-cancelled `app.wms_pick_
--     tasks` row (regardless of its own progress) still references one of that
--     order's own lines -- each such task's own live `app.inventory_reservations` row
--     would otherwise become orphaned/unreconciled against a demand order that no
--     longer exists (Prompt 236 §24's own "reservation ... remains reconciled to
--     outbound demand"; §32's own "release only unpicked reservations/tasks"). Every
--     pick task must be individually cancelled first (releasing its own reservation)
--     before the order itself may be cancelled. This migration's own blanket `REVOKE
--     EXECUTE ... FROM PUBLIC` (design note 14) does not affect the `authenticated`/
--     `service_role` EXECUTE grants `ATW-016A`'s own migration already issued for this
--     function (grants are tied to the function's OID, unaffected by a same-signature
--     `CREATE OR REPLACE`, and untouched by a `... FROM PUBLIC` revoke) -- no re-grant
--     is needed or issued here.
-- 14. **Six known bug classes, applied proactively (this session's now-established
--     taxonomy, `ATW-013`/`014`/`016`/`016A`, and this is the fifth application):**
--     (a) every idempotent-replay short-circuit below runs strictly after authority/
--         tenant-scope confirmation, never before;
--     (b)/(c) `SELECT ... FOR UPDATE` on the first read of any row a mutation will
--         update, held through the final `UPDATE`/`INSERT`, `record_version` compared
--         under that same lock -- the outbound order line (design note 3), every task
--         row, and the reservation/balance pair (design note 4);
--     (d) `app.generate_wms_pick_task`/`app.create_wms_pick_wave`'s own create-once
--         `(tenant_id, idempotency_key)` INSERTs are wrapped in a nested `begin/
--         exception unique_violation` recovery, re-selecting and returning the winner
--         (mirrors `app.generate_wms_putaway_task`, `ATW-014`) -- and (per design note 0b,
--         a real gap found and closed by adversarial review) every create-once INSERT
--         this migration's own functions compose one level down (`app.reserve_
--         inventory`'s own reservation insert, `app.post_inventory_movement`'s own
--         header insert, and this migration's own `app.wms_pick_task_confirmations`/
--         `app.wms_pick_task_shorts`/`app.wms_pick_substitution_approvals` inserts) now
--         carries the identical recovery too, converting a genuine cross-operation
--         idempotency-key-reuse race from a raw, uncaught duplicate-key error into a
--         clean, classified `idempotency_key_conflict` exception;
--     (e) the cross-row-aggregate double-allocation race -- design note 3, this
--         checkpoint's own headline instance of the class;
--     (f) owner-account read scoping -- every read RPC below that returns pick-task
--         data (owner-account-specific, inherited from the outbound order line's own
--         header) calls `app.actor_can_view_owner_scoped_row` (`ATW-016`, reused
--         directly) IN ADDITION to tenant-wide `OPS:View`/warehouse-record-scope, and
--         every `app.can_access_record` call below (mutation and read alike) passes
--         the task's own `owner_account_id` (as text) into `p_customer_account_ref`,
--         never `null` -- `ATW-016A`'s own convention, applied here from the start.
-- 15. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 0. Design note 12: additive widening of two already-applied enums (never editing
-- the original ATW-015 migration file).
alter table app.inventory_reservations drop constraint inventory_reservations_source_type_check;
alter table app.inventory_reservations add constraint inventory_reservations_source_type_check check (
  source_type in ('wms_inbound_order', 'wms_outbound_order', 'manual')
);

alter table app.inventory_movements drop constraint inventory_movements_source_type_check;
alter table app.inventory_movements add constraint inventory_movements_source_type_check check (
  source_type in ('wms_inbound_order', 'wms_outbound_order', 'reservation', 'manual', 'opening_balance', 'reversal')
);

-- 0b. Real defect found and fixed by adversarial review: this migration''s own
-- generate_wms_pick_task/create_wms_pick_wave create-once INSERTs are wrapped in a
-- nested begin/exception unique_violation recovery (design note 14d), but the create-
-- once INSERTs those functions (and confirm_wms_pick_task/record_wms_pick_task_short/
-- approve_wms_pick_substitution) compose one level down -- app.reserve_inventory's own
-- insert into app.inventory_reservations, and app.post_inventory_movement's own insert
-- into app.inventory_movements (both ATW-015, already-applied) -- carry NO such recovery
-- at all. A genuine two-process race that shares one caller-supplied idempotency_key
-- across two DIFFERENT, non-lock-contending operations (proven live: two different
-- app.wms_outbound_order_lines, no shared FOR UPDATE lock, generate_wms_pick_task fired
-- concurrently with the identical idempotency_key) makes the losing process's call abort
-- with a raw, uncaught "duplicate key value violates unique constraint" straight out of
-- app.reserve_inventory/app.post_inventory_movement, never the graceful idempotent-replay
-- every top-of-function check in this migration otherwise promises. Same-entity retries
-- (identical line_id/task_id AND identical idempotency_key) remain unaffected -- those
-- already serialize on that row''s own FOR UPDATE lock and are caught by the existing
-- top-of-function idempotent-replay check before ever reaching either insert.
--
-- Fixed here via a same-signature CREATE OR REPLACE (never editing the original ATW-015
-- migration file itself, the identical technique design note 13 below already uses for
-- app.cancel_wms_outbound_order): the previously-unguarded balance-reserve/insert pair in
-- app.reserve_inventory, and the previously-unguarded header insert in app.post_
-- inventory_movement, are each now wrapped in their own nested begin/exception
-- unique_violation block. On conflict, the block's own implicit savepoint rolls back
-- that block's own not-yet-committed mutations (the reserve''s own `reserved + p_quantity`
-- balance update in app.reserve_inventory; nothing else has run yet in app.post_
-- inventory_movement), and a clean, classified `idempotency_key_conflict` exception is
-- raised in place of the raw internal constraint-violation message -- this still aborts
-- the caller''s own enclosing transaction (correct: no partial reservation/movement/
-- balance effect survives), it just does so legibly. This widens BOTH shared functions
-- for every composer across the whole app schema (putaway/receiving/picking/etc.), not
-- only this migration's own callers.
create or replace function app.reserve_inventory(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_owner_account_id uuid,
  p_item_master_id uuid,
  p_location_id uuid,
  p_lot_number text,
  p_serial_number text,
  p_quantity numeric,
  p_source_type text,
  p_source_id uuid,
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

  -- Bug class (d), widened (design note 0b): a nested begin/exception unique_violation
  -- recovery around BOTH the reserved-balance mutation and the reservation insert -- the
  -- block's own implicit savepoint cleanly undoes the reserved-balance increment too, so
  -- no partial effect survives a losing race.
  begin
    update app.inventory_balances set reserved = reserved + p_quantity where id = v_balance.id;

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
$$;

comment on function app.reserve_inventory is
  'ATW-015, widened by ATW-017 design note 0b: idempotent on (tenant_id, idempotency_key). Locks the target balance row (SELECT ... FOR UPDATE) before checking availability, serializing concurrent reservation attempts against the identical dimension. A genuine race that reaches the reserved-balance-update/insert pair under a SHARED idempotency key but a DIFFERENT (non-lock-contending) balance dimension now fails cleanly with idempotency_key_conflict (savepoint-rolled-back, no partial reserved-balance mutation survives) instead of a raw, uncaught duplicate-key error.';

-- Design note 0b (continued): the identical fix, applied to app.post_inventory_movement's
-- own previously-unguarded header insert (composed by app.confirm_wms_pick_task below).
create or replace function app.post_inventory_movement(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_movement_type text,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_corrects_movement_id uuid default null
)
returns app.inventory_movements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
      select id, on_hand into v_balance_id, v_current_on_hand
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
      select on_hand into v_serial_on_hand from app.inventory_balances
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
$$;

comment on function app.post_inventory_movement is
  'ATW-015, widened by ATW-017 design note 0b: idempotent on (tenant_id, idempotency_key) -- a retry returns the identical header, never re-posts lines or double-counts balances. Every line''s own item/location/UOM/owner is independently validated; a transfer''s own lines must sum to exactly zero (design note 6); a resulting negative on_hand or a serial exceeding 1 both fail the whole call (all lines already inserted this transaction are rolled back with it). A genuine race that reaches the header insert under a SHARED idempotency key but a DIFFERENT (non-lock-contending) movement now fails cleanly with idempotency_key_conflict instead of a raw, uncaught duplicate-key error.';

-- 1. Wave numbering + header (design note 2).
create table app.wms_pick_wave_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

create function app.next_wms_pick_wave_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.wms_pick_wave_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.wms_pick_wave_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'WMSWAVE-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

create table app.wms_pick_waves (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  wave_number text not null,
  idempotency_key text not null,
  created_by text,
  created_at timestamptz not null default now(),
  constraint wms_pick_waves_number_unique unique (tenant_id, wave_number),
  constraint wms_pick_waves_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.wms_pick_waves is
  'ATW-017: a lightweight, state-machine-free grouping label (design note 2) -- no status column; a wave''s own completion state is always derived from its member app.wms_pick_tasks rows, never separately tracked.';

create index wms_pick_waves_tenant_warehouse_idx on app.wms_pick_waves (tenant_id, warehouse_id);

create function app.create_wms_pick_wave(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_waves
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_existing app.wms_pick_waves;
  v_wave app.wms_pick_waves;
  v_number text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to create a pick wave' using errcode = 'check_violation';
  end if;

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
    raise exception 'insufficient_authority: identity % cannot create a pick wave under warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_pick_waves where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  v_number := app.next_wms_pick_wave_number(p_tenant_id);

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_pick_waves (tenant_id, warehouse_id, wave_number, idempotency_key, created_by)
    values (p_tenant_id, p_warehouse_id, v_number, p_idempotency_key, p_actor_label)
    returning * into v_wave;
  exception
    when unique_violation then
      select * into v_existing from app.wms_pick_waves where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_wms_pick_wave',
    'app.wms_pick_waves', v_wave.id, 'success', null, null, jsonb_build_object('warehouse_id', p_warehouse_id, 'wave_number', v_number)
  );

  return v_wave;
end;
$$;

comment on function app.create_wms_pick_wave is
  'ATW-017: idempotent on (tenant_id, idempotency_key), including under a genuine race (bug class d).';

-- 2. Pick tasks -- one row per (outbound order line, allocated balance/reservation)
-- generation call (design note 1).
create table app.wms_pick_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  outbound_order_id uuid not null references app.wms_outbound_orders (id),
  outbound_order_line_id uuid not null references app.wms_outbound_order_lines (id),
  wave_id uuid references app.wms_pick_waves (id),
  owner_account_id uuid not null references app.accounts (id),
  item_master_id uuid not null references app.item_masters (id),
  uom_code text not null references app.uoms (code),
  lot_controlled boolean not null default false,
  serial_controlled boolean not null default false,
  expiry_controlled boolean not null default false,
  source_location_id uuid not null references app.warehouse_locations (id),
  lot_number text,
  serial_number text,
  expiry_date date,
  reservation_id uuid not null references app.inventory_reservations (id),
  task_quantity numeric not null,
  picked_quantity numeric not null default 0,
  short_quantity numeric not null default 0,
  remaining_quantity numeric generated always as (task_quantity - picked_quantity - short_quantity) stored,
  suggested_destination_location_id uuid references app.warehouse_locations (id),
  suggested_destination_reason text,
  actual_destination_location_id uuid references app.warehouse_locations (id),
  status text not null default 'unclaimed',
  claimed_by_auth_user_id uuid references auth.users (id),
  claimed_by_label text,
  claimed_at timestamptz,
  exception_reason text,
  substituted_from_item_master_id uuid references app.item_masters (id),
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_pick_tasks_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_pick_tasks_reservation_unique unique (reservation_id),
  constraint wms_pick_tasks_status_check check (status in ('unclaimed', 'claimed', 'partial', 'picked', 'short', 'exception', 'cancelled')),
  constraint wms_pick_tasks_task_quantity_check check (task_quantity > 0),
  constraint wms_pick_tasks_picked_quantity_check check (picked_quantity >= 0),
  constraint wms_pick_tasks_short_quantity_check check (short_quantity >= 0),
  constraint wms_pick_tasks_progress_bound_check check (picked_quantity + short_quantity <= task_quantity),
  constraint wms_pick_tasks_claimed_shape_check check (
    (status = 'unclaimed' and claimed_by_auth_user_id is null and claimed_at is null)
    or (status not in ('unclaimed', 'cancelled') and claimed_by_auth_user_id is not null and claimed_at is not null)
    or (status = 'cancelled')
  ),
  constraint wms_pick_tasks_actual_destination_shape_check check (picked_quantity = 0 or actual_destination_location_id is not null),
  constraint wms_pick_tasks_exception_reason_check check (status <> 'exception' or (exception_reason is not null and length(trim(exception_reason)) > 0)),
  constraint wms_pick_tasks_cancelled_shape_check check (status <> 'cancelled' or (picked_quantity = 0 and short_quantity = 0))
);

comment on table app.wms_pick_tasks is
  'ATW-017: one task per (outbound order line, allocated balance/reservation) generation call (design note 1). status: unclaimed -> claimed -> partial -> picked|short (derived exclusively from picked_quantity/short_quantity vs task_quantity, never a directly caller-set value) with a real exception/cancelled escape. source_location_id/lot_number/serial_number are authoritative from generation (design note 10, unlike putaway''s decision-support destination) -- actual_destination_location_id is only ever set at first real confirm.';

create index wms_pick_tasks_tenant_warehouse_status_idx on app.wms_pick_tasks (tenant_id, warehouse_id, status);
create index wms_pick_tasks_outbound_order_line_idx on app.wms_pick_tasks (outbound_order_line_id);
create index wms_pick_tasks_outbound_order_idx on app.wms_pick_tasks (outbound_order_id);
create index wms_pick_tasks_claimed_by_idx on app.wms_pick_tasks (claimed_by_auth_user_id);
create index wms_pick_tasks_wave_idx on app.wms_pick_tasks (wave_id);
create index wms_pick_tasks_tenant_owner_idx on app.wms_pick_tasks (tenant_id, owner_account_id);

create function app.touch_wms_pick_tasks_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_pick_tasks_touch_row
  before update on app.wms_pick_tasks
  for each row
  execute function app.touch_wms_pick_tasks_row();

-- 3. Pick confirmations -- append-only evidence, one row per real confirm-scan event.
create table app.wms_pick_task_confirmations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  task_id uuid not null references app.wms_pick_tasks (id),
  idempotency_key text not null,
  quantity numeric not null,
  scanned_location_id uuid not null references app.warehouse_locations (id),
  scanned_item_master_id uuid not null references app.item_masters (id),
  scanned_lot_number text,
  scanned_serial_number text,
  actual_destination_location_id uuid not null references app.warehouse_locations (id),
  movement_id uuid not null references app.inventory_movements (id),
  confirmed_by_auth_user_id uuid references auth.users (id),
  confirmed_by_label text,
  confirmed_at timestamptz not null default now(),
  constraint wms_pick_task_confirmations_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_pick_task_confirmations_quantity_check check (quantity > 0)
);

comment on table app.wms_pick_task_confirmations is
  'ATW-017: append-only evidence, one row per real (or idempotently replayed) app.confirm_wms_pick_task call -- Prompt 236 section 18''s own "scans, exact quantities... movement IDs" audit trail. Never updated or deleted by any grant in this migration.';

create index wms_pick_task_confirmations_task_idx on app.wms_pick_task_confirmations (task_id);

-- 4. Short-pick evidence -- append-only, one row per real recorded short event
-- (design note 6).
create table app.wms_pick_task_shorts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  task_id uuid not null references app.wms_pick_tasks (id),
  idempotency_key text not null,
  quantity numeric not null,
  reason text not null,
  recorded_by_auth_user_id uuid references auth.users (id),
  recorded_by_label text,
  recorded_at timestamptz not null default now(),
  constraint wms_pick_task_shorts_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_pick_task_shorts_quantity_check check (quantity > 0),
  constraint wms_pick_task_shorts_reason_check check (length(trim(reason)) > 0)
);

comment on table app.wms_pick_task_shorts is
  'ATW-017: append-only evidence, one row per real recorded short event (design note 6) -- distinct from a partial confirm; the quantity here is released from app.inventory_balances.reserved, never transferred.';

create index wms_pick_task_shorts_task_idx on app.wms_pick_task_shorts (task_id);

-- 5. Substitution approvals -- append-only, one row per governed substitution
-- (design note 9).
create table app.wms_pick_substitution_approvals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  task_id uuid not null references app.wms_pick_tasks (id),
  original_item_master_id uuid not null references app.item_masters (id),
  substitute_item_master_id uuid not null references app.item_masters (id),
  original_reservation_id uuid not null references app.inventory_reservations (id),
  new_reservation_id uuid not null references app.inventory_reservations (id),
  reason text not null,
  idempotency_key text not null,
  approved_by_auth_user_id uuid references auth.users (id),
  approved_by_label text,
  approved_at timestamptz not null default now(),
  constraint wms_pick_substitution_approvals_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_pick_substitution_approvals_reason_check check (length(trim(reason)) > 0),
  constraint wms_pick_substitution_approvals_not_same_item check (original_item_master_id <> substitute_item_master_id)
);

comment on table app.wms_pick_substitution_approvals is
  'ATW-017: append-only, real, auditable evidence of a governed substitution (design note 9, OPS:Override-gated) -- links the original and substitute item/reservation and the approving supervisor. Never a silent re-run of allocation with no trace.';

create index wms_pick_substitution_approvals_task_idx on app.wms_pick_substitution_approvals (task_id);

-- 6. Mutations. Every mutation is RBAC-gated (OPS:Create/Edit/Override) and
-- record-scope-gated (app.can_access_record against the task's own warehouse's
-- company org unit AND owner_account_id, bug class f), and audited.

create function app.generate_wms_pick_task(
  p_outbound_order_line_id uuid,
  p_quantity numeric,
  p_wave_id uuid,
  p_location_id uuid,
  p_lot_number text,
  p_serial_number text,
  p_suggested_destination_location_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.generate_wms_pick_task is
  'ATW-017: real, synchronous, idempotent RPC (no scheduler/worker runtime exists yet, ISS-2026-015, the identical disclosed boundary every prior Phase 5 checkpoint has used). Locks the outbound order line row (FOR UPDATE) before computing already-allocated quantity -- the double-allocation guard (design note 3). Resolves and reserves an authoritative source (design note 10), independently re-verifying held/expired/pick-enabled eligibility for a caller-supplied candidate (design note 11). Idempotent on (tenant_id, idempotency_key), including under a genuine race.';

create function app.claim_wms_pick_task(
  p_task_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE (FOR UPDATE) -- the real
  -- concurrent-claim-race guard (mirrors app.claim_wms_putaway_task, ATW-014).
  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found then
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
$$;

comment on function app.claim_wms_pick_task is
  'ATW-017: row-locked (SELECT ... FOR UPDATE) so a genuine concurrent double-claim cannot both succeed -- the second caller blocks, then observes status=claimed under a different claimant and is rejected task_already_claimed. Idempotent no-op on a same-claimant re-claim, but only after OPS:Edit/record-scope authority is confirmed -- never before.';

create function app.confirm_wms_pick_task(
  p_task_id uuid,
  p_quantity numeric,
  p_scanned_location_id uuid,
  p_scanned_item_master_id uuid,
  p_scanned_lot_number text,
  p_scanned_serial_number text,
  p_actual_destination_location_id uuid,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.confirm_wms_pick_task is
  'ATW-017: the one and only path that ever calls app.post_inventory_movement (movement_type=transfer) for this task. Reduces app.inventory_balances.reserved BEFORE posting the transfer (design note 4, the exact statement order the reserved+held<=on_hand CHECK constraint requires). Idempotent per-confirm-event on (tenant_id, idempotency_key); only the task''s own claimant may confirm it. Confirming less than remaining_quantity is a legitimate partial pick (design note 6), confirming more is a hard rejection. Requires an exact-matching p_scanned_item_master_id (item_mismatch otherwise) -- a location alone never proves the picker grabbed the task''s own item, since app.warehouse_locations carries no item binding and one bin may hold several distinct items'' balances.';

create function app.record_wms_pick_task_short(
  p_task_id uuid,
  p_short_quantity numeric,
  p_reason text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.record_wms_pick_task_short is
  'ATW-017: Prompt 236 section 22''s own distinct "record short" alt-flow (design note 6) -- releases exactly the short quantity from app.inventory_balances.reserved, making it available again for a fresh app.generate_wms_pick_task call against the same line. Confirming a short beyond remaining_quantity is a hard rejection.';

create function app.mark_wms_pick_task_exception(
  p_task_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_override app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found then
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
$$;

comment on function app.mark_wms_pick_task_exception is
  'ATW-017: Prompt 236 section 23''s own exception flow ("block wrong/blocked/full/incompatible destination... record blocker... never hide or bypass failure"). Callable by the task''s own claimant or a supervisor holding OPS:Override. Row-locked; idempotent no-op on an already-exception task, only after authority is confirmed.';

create function app.reassign_wms_pick_task(
  p_task_id uuid,
  p_new_claimant_auth_user_id uuid,
  p_new_claimant_label text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
  v_new_status text;
begin
  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found then
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
$$;

comment on function app.reassign_wms_pick_task is
  'ATW-017: OPS:Override-gated supervisor reassign/release, mirrors app.reassign_wms_putaway_task exactly. A null new claimant releases the task back to unclaimed; a non-null one reassigns it. Never callable on an already-resolved (picked/short) or cancelled task.';

create function app.cancel_wms_pick_task(
  p_task_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_pick_tasks where id = p_task_id for update;
  if not found then
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
$$;

comment on function app.cancel_wms_pick_task is
  'ATW-017: only while zero of the task''s own picked_quantity/short_quantity has posted (design note 8) -- releases the FULL original reservation via the shared app.release_inventory_reservation, safe only in this zero-progress case. Cancelling frees the outbound order line''s own remaining requested_quantity for a fresh app.generate_wms_pick_task call.';

create function app.approve_wms_pick_substitution(
  p_task_id uuid,
  p_substitute_item_master_id uuid,
  p_location_id uuid,
  p_lot_number text,
  p_serial_number text,
  p_reason text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_pick_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.approve_wms_pick_substitution is
  'ATW-017: OPS:Override-gated governed substitution (design note 9), only while a task has genuinely zero progress. Releases the original reservation in full and reserves fresh stock against the caller-nominated substitute item (same base_uom_code required), recording one real, auditable app.wms_pick_substitution_approvals row. substituted_from_item_master_id always preserves the ORIGINAL item across repeated substitutions.';

-- 7. Design note 13: widen app.cancel_wms_outbound_order (ATW-016A) via a
-- same-signature CREATE OR REPLACE, obligated by ATW-016A's own design note 8.
create or replace function app.cancel_wms_outbound_order(
  p_outbound_order_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_pick_progress_count integer;
begin
  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id for update;
  if not found then
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
$$;

comment on function app.cancel_wms_outbound_order is
  'ATW-016A/ATW-017: widened by ATW-017 (Picking, design note 13) per ATW-016A''s own design note 8 -- now blocks cancellation while any non-cancelled app.wms_pick_tasks row references one of this order''s own lines (has_pick_progress), mirroring ATW-013''s own widening of app.cancel_wms_inbound. Idempotent no-op on an already-cancelled order (still checked only after authority/version, design lesson a).';

-- 8. Reads. Owner-account scoping (bug class f) applied to every read below, IN
-- ADDITION to tenant-wide RBAC (OPS:View) and warehouse-record-scope.

create function app.get_wms_pick_task(p_task_id uuid, p_actor_auth_user_id uuid)
returns app.wms_pick_tasks
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_pick_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_pick_tasks where id = p_task_id;
  if not found then
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
$$;

comment on function app.get_wms_pick_task is
  'ATW-017: owner-account read scoping (bug class f) applied in addition to tenant-wide OPS:View and warehouse-record-scope.';

create function app.list_wms_pick_task_confirmations(p_task_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_pick_task_confirmations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_pick_task(p_task_id, p_actor_auth_user_id);
  return query select * from app.wms_pick_task_confirmations where task_id = p_task_id order by confirmed_at;
end;
$$;

comment on function app.list_wms_pick_task_confirmations is
  'ATW-017: reuses app.get_wms_pick_task for its own authority/record-scope/owner-scope gate rather than duplicating the checks.';

create function app.list_wms_pick_task_shorts(p_task_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_pick_task_shorts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_pick_task(p_task_id, p_actor_auth_user_id);
  return query select * from app.wms_pick_task_shorts where task_id = p_task_id order by recorded_at;
end;
$$;

create function app.list_wms_pick_substitution_approvals(p_task_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_pick_substitution_approvals
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_pick_task(p_task_id, p_actor_auth_user_id);
  return query select * from app.wms_pick_substitution_approvals where task_id = p_task_id order by approved_at;
end;
$$;

create function app.list_wms_pick_tasks(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_outbound_order_id uuid default null,
  p_outbound_order_line_id uuid default null,
  p_wave_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_claimed_by_auth_user_id uuid default null,
  p_limit integer default 50
)
returns setof app.wms_pick_tasks
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select t.* from app.wms_pick_tasks t
  join app.warehouses w on w.id = t.warehouse_id
  where t.tenant_id = p_tenant_id
    and (p_warehouse_id is null or t.warehouse_id = p_warehouse_id)
    and (p_outbound_order_id is null or t.outbound_order_id = p_outbound_order_id)
    and (p_outbound_order_line_id is null or t.outbound_order_line_id = p_outbound_order_line_id)
    and (p_wave_id is null or t.wave_id = p_wave_id)
    and (p_owner_account_id is null or t.owner_account_id = p_owner_account_id)
    and (p_status_filter is null or t.status = p_status_filter)
    and (p_claimed_by_auth_user_id is null or t.claimed_by_auth_user_id = p_claimed_by_auth_user_id)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), t.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, t.owner_account_id)
  order by t.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_pick_tasks is
  'ATW-017: bounded read (p_limit default 50, hard-capped 200), record-scoped per row by the task''s own warehouse company org unit AND owner-account-scoped (bug class f).';

create function app.list_wms_pick_waves(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_limit integer default 50
)
returns setof app.wms_pick_waves
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select v.* from app.wms_pick_waves v
  join app.warehouses w on w.id = v.warehouse_id
  where v.tenant_id = p_tenant_id
    and (p_warehouse_id is null or v.warehouse_id = p_warehouse_id)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
  order by v.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_pick_waves is
  'ATW-017: bounded read; a wave is warehouse-scoped only (design note 2), never owner-scoped -- it may legitimately group tasks across multiple owners.';

-- 9. RLS -- record scope AND owner scope enforced in the database (bug class f), not
-- UI-only.
--
-- Real defect found and fixed by adversarial review: app.warehouses' own RLS SELECT
-- policy (20260730140000) always calls app.can_access_record(..., p_customer_account_ref
-- => null) -- a warehouse itself is never owner-scoped, so that policy never grants a
-- customer_user-layer actor a row, by design. A raw, non-SECURITY-DEFINER `select 1 from
-- app.warehouses w where ...` nested inside an OWNER-SCOPED table's own RLS USING clause
-- (as ATW-016A''s app.wms_outbound_orders policy already does, and this migration would
-- otherwise repeat here) therefore always evaluates as authenticated/customer_user and is
-- ALWAYS filtered out by app.warehouses' own policy first -- making the outer EXISTS
-- always false for a customer_user actor, even for their own genuinely owned row,
-- regardless of the real p_customer_account_ref this migration''s own policy passes.
-- This silently breaks the "real owner-scoped SELECT policy... in the database, not
-- UI-only" guarantee this design note claims (Prompt 236 section 26, "customers see only
-- permitted fulfillment status") for any future direct-table read; every current read
-- path composes only the SECURITY DEFINER RPCs below (which read app.warehouses directly,
-- bypassing its RLS as the function owner), so this is currently latent/unreachable, not
-- yet a live leak -- but the bug is real and is fixed here rather than carried forward.
-- Fix: resolve the warehouse's own tenant_id/company_org_unit_id through a small,
-- dedicated SECURITY DEFINER helper (bypasses app.warehouses' own RLS the same way every
-- SECURITY DEFINER RPC in this migration already does), so the owner-scoped policies
-- below evaluate app.can_access_record's real p_customer_account_ref instead of being
-- silently pre-filtered to zero rows by an unrelated table's own RLS policy.
create function app.wms_pick_record_scope_ok(p_auth_user_id uuid, p_warehouse_id uuid, p_owner_account_ref text)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select coalesce((
    select app.can_access_record(p_auth_user_id, w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), p_owner_account_ref)
    from app.warehouses w
    where w.id = p_warehouse_id
  ), false);
$$;

comment on function app.wms_pick_record_scope_ok is
  'ATW-017: SECURITY DEFINER helper used ONLY by this migration''s own RLS policies below -- resolves a warehouse''s tenant_id/company_org_unit_id and evaluates app.can_access_record against it while bypassing app.warehouses'' own RLS (which always passes p_customer_account_ref=null and therefore always denies a customer_user actor, even one who legitimately owns the outer row). Fixes a real, proactively-found defect: a raw non-SECURITY-DEFINER "select 1 from app.warehouses" nested inside an owner-scoped policy''s own USING clause would otherwise always evaluate false for a customer_user actor regardless of true ownership (the same latent, inherited pattern already present in ATW-016A''s app.wms_outbound_orders policy, not repeated here).';

alter table app.wms_pick_waves enable row level security;

create policy wms_pick_waves_select_scoped on app.wms_pick_waves
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = wms_pick_waves.warehouse_id
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.wms_pick_tasks enable row level security;

create policy wms_pick_tasks_select_scoped on app.wms_pick_tasks
  for select to authenticated
  using (
    app.wms_pick_record_scope_ok((select auth.uid()), wms_pick_tasks.warehouse_id, wms_pick_tasks.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row((select auth.uid()), wms_pick_tasks.tenant_id, wms_pick_tasks.owner_account_id)
  );

alter table app.wms_pick_task_confirmations enable row level security;

create policy wms_pick_task_confirmations_select_scoped on app.wms_pick_task_confirmations
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_pick_tasks t
      where t.id = wms_pick_task_confirmations.task_id
        and app.wms_pick_record_scope_ok((select auth.uid()), t.warehouse_id, t.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), t.tenant_id, t.owner_account_id)
    )
  );

alter table app.wms_pick_task_shorts enable row level security;

create policy wms_pick_task_shorts_select_scoped on app.wms_pick_task_shorts
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_pick_tasks t
      where t.id = wms_pick_task_shorts.task_id
        and app.wms_pick_record_scope_ok((select auth.uid()), t.warehouse_id, t.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), t.tenant_id, t.owner_account_id)
    )
  );

alter table app.wms_pick_substitution_approvals enable row level security;

create policy wms_pick_substitution_approvals_select_scoped on app.wms_pick_substitution_approvals
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_pick_tasks t
      where t.id = wms_pick_substitution_approvals.task_id
        and app.wms_pick_record_scope_ok((select auth.uid()), t.warehouse_id, t.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), t.tenant_id, t.owner_account_id)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant. Design note 13: this does NOT
-- undo the authenticated/service_role EXECUTE grant ATW-016A's own migration already
-- issued for app.cancel_wms_outbound_order (grants are tied to the function's OID,
-- unaffected by the same-signature CREATE OR REPLACE above) -- no re-grant is issued
-- for it here.
revoke execute on all functions in schema app from public;

grant select on app.wms_pick_waves, app.wms_pick_tasks, app.wms_pick_task_confirmations, app.wms_pick_task_shorts, app.wms_pick_substitution_approvals to authenticated, service_role;
grant insert, update, delete on app.wms_pick_waves, app.wms_pick_tasks, app.wms_pick_task_confirmations, app.wms_pick_task_shorts, app.wms_pick_substitution_approvals to service_role;
grant insert, update on app.wms_pick_wave_number_counters to service_role;

grant execute on function app.next_wms_pick_wave_number(uuid) to service_role;
grant execute on function app.wms_pick_record_scope_ok(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.create_wms_pick_wave(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.generate_wms_pick_task(uuid, numeric, uuid, uuid, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.claim_wms_pick_task(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.confirm_wms_pick_task(uuid, numeric, uuid, uuid, text, text, uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.record_wms_pick_task_short(uuid, numeric, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.mark_wms_pick_task_exception(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reassign_wms_pick_task(uuid, uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_wms_pick_task(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.approve_wms_pick_substitution(uuid, uuid, uuid, text, text, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_pick_task(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_pick_task_confirmations(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_pick_task_shorts(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_pick_substitution_approvals(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_pick_tasks(uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_wms_pick_waves(uuid, uuid, uuid, integer) to authenticated, service_role;

-- 15. Widening ATW-016A's own app.wms_outbound_orders/app.wms_outbound_order_lines RLS
-- SELECT policies (already-applied, never edited directly -- only DROP POLICY/CREATE
-- POLICY here, the same widening technique already used for app.cancel_wms_outbound_order
-- above). The security-authority review lens found the identical fail-closed defect this
-- migration's own design note 12 already fixed for its own new tables also exists there:
-- a raw, non-SECURITY-DEFINER "select 1 from app.warehouses" nested inside an
-- owner-scoped policy's own USING clause always evaluates false for a customer_user
-- actor (app.warehouses' own RLS policy always passes p_customer_account_ref = null to
-- app.can_access_record, denying that branch unconditionally), even for a row that actor
-- genuinely owns. Currently latent/unreachable there too (every real read path composes
-- only the SECURITY DEFINER RPCs, never a raw table read) -- fixed now that the generic
-- app.wms_pick_record_scope_ok helper already exists, rather than left as a second,
-- separately-tracked known issue alongside this migration's own now-fixed instance of the
-- identical bug.
drop policy if exists wms_outbound_orders_select_scoped on app.wms_outbound_orders;
create policy wms_outbound_orders_select_scoped on app.wms_outbound_orders
  for select to authenticated
  using (
    app.wms_pick_record_scope_ok((select auth.uid()), wms_outbound_orders.warehouse_id, wms_outbound_orders.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row((select auth.uid()), wms_outbound_orders.tenant_id, wms_outbound_orders.owner_account_id)
  );

drop policy if exists wms_outbound_order_lines_select_scoped on app.wms_outbound_order_lines;
create policy wms_outbound_order_lines_select_scoped on app.wms_outbound_order_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_outbound_orders o
      where o.id = wms_outbound_order_lines.outbound_order_id
        and app.wms_pick_record_scope_ok((select auth.uid()), o.warehouse_id, o.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), o.tenant_id, o.owner_account_id)
    )
  );
