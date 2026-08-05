-- CG-S10-ATW-032 (post-Prompt-248 audit) — closes `ISS-2026-016`.
--
-- ===========================================================================
-- The gap
-- ===========================================================================
--
-- `app.register_lot_identity` and `app.register_serial_identity` (`ATW-016`, Prompt 235) are
-- real, correct, tested, independently-callable RPCs — and NOTHING in this system has ever
-- called them. A repository-wide search finds no caller outside their own definition, their
-- own db-test, and prose. Receiving continued to store lot and serial as plain, ungoverned
-- text exactly as it did before they existed.
--
-- The consequence is not cosmetic. `app.list_allocation_candidates`' held / expired /
-- duplicate-serial exclusion is correct code, but it can only exclude an identity that was
-- registered — so against live receiving traffic it had nothing to exclude. Prompt 235 §33's
-- "expired/held or duplicate-serial stock cannot be allocated silently" did not hold
-- end-to-end. `ATW-016` disclosed this as a deliberate scope boundary rather than an
-- oversight, and `ISS-2026-016` has held the obligation open since. This is the wiring.
--
-- ===========================================================================
-- Why this is a wiring change and not a capability change
-- ===========================================================================
--
-- Everything the registry needs is ALREADY on the row being committed.
-- `app.wms_receipt_lines` carries `lot_number`, `serial_number` and `expiry_date`, plus the
-- `lot_controlled` / `serial_controlled` / `expiry_controlled` flags that say which of them
-- apply. `app.commit_wms_receipt_line` already holds all of it in `v_line` and already passes
-- the same three values into `app.post_inventory_movement`. So: no signature change, no new
-- column, no new function, no new authority.
--
-- **The authority question was checked rather than assumed.** The registry RPCs gate on
-- `OPS:Create` while `commit_wms_receipt_line` gates on `OPS:Edit`, which looks like it would
-- lock out an Edit-only clerk. It cannot: `app.start_wms_receipt_session` already requires
-- `OPS:Create` (`20260730200000:303`), so a line cannot reach commit unless its session was
-- started by someone holding exactly that permission. No gate is widened here, and none needed
-- to be.
--
-- ===========================================================================
-- Ordering, chosen by testing it both ways
-- ===========================================================================
--
-- Registration runs AFTER the inventory movement. Registering first put
-- `register_serial_identity`'s `duplicate_serial` ahead of `app.post_inventory_movement`'s own
-- `serial_conflict` guard, changing the error a caller already handles for the same wrong
-- thing — `advanced-tms-wms-receiving.sql` asserts exactly that rejection when a second line
-- reuses a serial already on hand, and it caught the change immediately. Registering first
-- also buys nothing: everything here runs in one transaction, so nothing outside can observe
-- a balance before its identity in either order. After the movement, the ledger's own guard
-- stays the first line of defence and only lines that genuinely posted are recorded.
--
-- Both RPCs return the existing row when the identity is already registered, so a multi-line
-- receipt of one lot registers once and every later line is a no-op — and a replayed commit
-- registers nothing new. The serial call additionally carries
-- `'wms-receipt-line-' || v_line.id` as its idempotency key: the receipt line is the natural
-- target, since one committed line registers one serial.
--
-- Guarded on the line's own control flags, so a plain item registers nothing and an item that
-- is lot-controlled but not expiry-controlled registers its lot without an expiry —
-- `register_lot_identity` rejects an expiry date on an item that is not expiry-controlled, and
-- receiving may legitimately hold neither value.
--
-- ===========================================================================
-- A verification that was compensating for this gap
-- ===========================================================================
--
-- `advanced-tms-wms-critical-path-verification.sql` called both registry RPCs by hand, and it
-- had to: nothing registered identities, so the live receiving chain it exercises produced
-- balances with no governed identity behind them and the test had to manufacture one before it
-- could assert anything. Those manual calls are now redundant — and the serial one correctly
-- began raising `duplicate_serial` against the identity receiving had just created. It now
-- reads what the chain itself produced and asserts on that, which is the assertion that
-- verification was always reaching for.
--
-- Additive: one same-signature function replacement. No table, column, constraint, policy or
-- grant is touched, and no already-applied migration file is edited. No grant block:
-- `CREATE OR REPLACE` preserves the existing ACL.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public`.

CREATE OR REPLACE FUNCTION app.commit_wms_receipt_line(p_line_id uuid, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  v_lines jsonb := '[]'::jsonb;
  v_movement app.inventory_movements;
begin
  -- Row-locked from this first read through commit/rollback (FOR UPDATE) so a second
  -- concurrent call on the same line -- e.g. a client retry that regenerates a fresh
  -- idempotency key after a slow/timed-out first response -- cannot read the
  -- pre-commit status, build its own movement lines, and call
  -- app.post_inventory_movement a second time before the first call's UPDATE has
  -- landed. The second caller instead blocks here until the first transaction
  -- commits, then observes status='committed' and takes the idempotent short-circuit
  -- below -- never a second real ledger movement for the same physical receipt.
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found then
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
    raise exception 'insufficient_authority: identity % cannot commit receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is
  -- confirmed above, never before (an already-committed record must never be
  -- readable by a caller who could not otherwise access it).
  if v_line.status = 'committed' then
    return v_line;
  end if;

  if v_session.status <> 'in_progress' then
    raise exception 'session_not_in_progress: session % is % -- lines may only be committed while in_progress', v_session.id, v_session.status using errcode = 'check_violation';
  end if;
  if v_line.status <> 'counted' then
    raise exception 'line_not_counted: % must have a recorded count before it can be committed', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: receipt line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version using errcode = 'check_violation';
  end if;
  if v_line.over_quantity > 0 and not v_line.over_approved then
    raise exception 'unapproved_overage: receipt line % counted % over the expected % without supervisor approval', p_line_id, v_line.over_quantity, v_line.expected_quantity using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to commit a receipt line' using errcode = 'check_violation';
  end if;

  if v_line.accepted_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.accepted_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'on_hand'
    ));
  end if;
  if v_line.damaged_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.damaged_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'damaged'
    ));
  end if;
  if v_line.held_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.held_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'held'
    ));
  end if;

  if jsonb_array_length(v_lines) > 0 then
    v_movement := app.post_inventory_movement(
      v_line.tenant_id, v_session.warehouse_id, 'receipt', 'wms_inbound_order', v_session.inbound_order_id, p_idempotency_key, v_line.condition_notes,
      v_lines, p_actor_auth_user_id, p_actor_label
    );
  end if;

  -- ATW-032 (closes ISS-2026-016). app.register_lot_identity / app.register_serial_identity
  -- (ATW-016) were real, tested, independently-callable RPCs that NOTHING in the system ever
  -- called. Receiving stored lot and serial as plain, ungoverned text exactly as it had before
  -- they existed, so app.list_allocation_candidates' hold/expiry/duplicate-serial exclusion --
  -- Prompt 235 §33's "expired/held or duplicate-serial stock cannot be allocated silently" --
  -- was correct code with nothing registered for it to exclude. This is the wiring.
  --
  -- Everything it needs is already on the row: app.wms_receipt_lines carries lot_number,
  -- serial_number, expiry_date AND the lot_controlled/serial_controlled/expiry_controlled
  -- flags. No signature changes, no new column, no new authority. The registry RPCs gate on
  -- OPS:Create, which cannot lock anyone out here because app.start_wms_receipt_session
  -- already requires OPS:Create -- a line cannot reach commit without its session having been
  -- started under that same permission.
  --
  -- Registration runs AFTER the movement, deliberately. Placing it before would put
  -- register_serial_identity's duplicate_serial ahead of app.post_inventory_movement's own
  -- serial_conflict guard, changing the error a caller already handles for the same wrong
  -- thing -- and it buys nothing, because both are in one transaction so nothing outside can
  -- observe a balance before its identity either way. After the movement, the ledger's own
  -- guard stays the first line of defence and only lines that genuinely posted are recorded.
  --
  -- Both RPCs return the existing row when the identity is already registered, so a
  -- multi-line receipt of one lot registers once and every later line is a no-op.
  if v_line.lot_controlled and v_line.lot_number is not null and length(trim(v_line.lot_number)) > 0 then
    perform app.register_lot_identity(
      v_line.item_master_id, v_line.lot_number, null,
      -- expiry_date only when the item is expiry-controlled: register_lot_identity rejects an
      -- expiry on an item that is not, and receiving may legitimately hold neither.
      case when v_line.expiry_controlled then v_line.expiry_date else null end,
      'receipt', v_line.id, null, p_actor_auth_user_id, p_actor_label
    );
  end if;

  if v_line.serial_controlled and v_line.serial_number is not null and length(trim(v_line.serial_number)) > 0 then
    perform app.register_serial_identity(
      v_line.item_master_id, v_line.serial_number,
      case when v_line.lot_controlled then v_line.lot_number else null end,
      null,
      case when v_line.expiry_controlled then v_line.expiry_date else null end,
      'receipt', v_line.id,
      -- The receipt line is the natural idempotency target: one committed line registers one
      -- serial, and a replay of that commit must not be a second registration.
      'wms-receipt-line-' || v_line.id::text,
      p_actor_auth_user_id, p_actor_label
    );
  end if;

  update app.wms_receipt_lines set status = 'committed', movement_id = v_movement.id
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_wms_receipt_line',
    'app.wms_receipt_lines', v_line.id, 'success', null, null,
    jsonb_build_object('movement_id', v_movement.id, 'accepted_quantity', v_line.accepted_quantity, 'damaged_quantity', v_line.damaged_quantity, 'held_quantity', v_line.held_quantity)
  );

  return v_line;
end;
$function$
;

revoke execute on all functions in schema app from public;
