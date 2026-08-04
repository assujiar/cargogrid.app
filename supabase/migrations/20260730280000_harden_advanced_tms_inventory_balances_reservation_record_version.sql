-- Advanced TMS/WMS hardening (inserted alongside `CG-S10-ATW-020`, no source prompt
-- number -- a real, currently-active defect found by this session's own adversarial
-- review of `ATW-020`'s cycle-count/adjustment implementation, root-caused one layer
-- down in the already-applied `ATW-015` inventory ledger migration).
--
-- `app.approve_cycle_count_variance` (`20260730270000_create_advanced_tms_cycle_
-- count_adjustment.sql`) detects a stale snapshot solely via `app.inventory_balances.
-- record_version`: it re-locks the balance row at approval time and rejects
-- `balance_changed_since_snapshot` if the live `record_version` no longer matches the
-- value captured at freeze time. That check is only as good as `record_version`'s own
-- guarantee of bumping on every real change to the balance row. `app.post_inventory_
-- movement`'s own on_hand-changing UPDATE already bumps it correctly
-- (`20260730190000_create_advanced_tms_inventory_ledger.sql` line ~364) -- but `app.
-- reserve_inventory`/`app.release_inventory_reservation`/`app.consume_inventory_
-- reservation` each mutate the identical row's own `reserved` column directly
-- (`update app.inventory_balances set reserved = ... where id = ...`) without ever
-- touching `record_version`. A real reservation placed against the exact same balance
-- between an `ATW-020` freeze and its approval is therefore completely invisible to
-- that staleness check -- either a silent, un-flagged approval proceeds despite the
-- intervening reservation change Prompt 239 section 23 requires blocking, or (if the
-- reservation is large enough) the approval aborts with a raw, unhandled Postgres
-- `inventory_balances_reserved_held_bound_check` violation instead of a clean, named
-- domain error, unlike every other rejection path in `ATW-020`'s own migration.
--
-- Per `AGENTS.md`'s own database rule ("Never edit an applied migration; add a new
-- migration") and this repository's own established `harden_*` convention (e.g.
-- `20260730170000_harden_advanced_tms_warehouse_zone_location_dependency.sql`),
-- `20260730190000` itself is never edited -- these three functions are widened here
-- via `CREATE OR REPLACE FUNCTION` with an identical signature, so every existing
-- caller and grant is unaffected. The fix is the minimal, correct one: each function's
-- own direct `reserved` mutation now also sets `record_version = record_version + 1`
-- and `updated_at = now()` -- the identical pair `app.post_inventory_movement`'s own
-- on_hand UPDATE already sets, so `app.inventory_balances.record_version` becomes a
-- true "this row changed" signal regardless of WHICH of the four balance-writing
-- functions (design note 1, `20260730190000`) made the change, not just the
-- on_hand-changing one. This closes the gap for `ATW-020`'s own staleness check
-- without adding a second, competing versioning scheme -- record_version remains the
-- one and only optimistic-concurrency signal for this table.
--
-- IMPORTANT baseline note: `app.reserve_inventory` was already widened once before,
-- by `20260730240000_create_advanced_tms_wms_picking.sql` design note 0b (a nested
-- `begin/exception unique_violation` recovery around the reserved-balance UPDATE and
-- the reservation INSERT, so a genuine idempotency-key race fails cleanly with
-- `idempotency_key_conflict` instead of a raw, uncaught duplicate-key error). This
-- migration's own `CREATE OR REPLACE` is based on THAT already-widened body, not the
-- original `20260730190000` one -- carrying the ATW-017 race fix forward and adding
-- this migration's own record_version/updated_at bump inside the identical nested
-- block, rather than silently reverting it. `app.release_inventory_reservation`/`app.
-- consume_inventory_reservation` were never touched by ATW-017, so their own baseline
-- here is unchanged from `20260730190000`.

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
$$;

comment on function app.reserve_inventory is
  'ATW-015, widened by ATW-017 design note 0b (idempotency-key race -> clean idempotency_key_conflict) and hardened again this checkpoint (harden migration 20260730280000): idempotent on (tenant_id, idempotency_key). Locks the target balance row (SELECT ... FOR UPDATE) before checking availability, serializing concurrent reservation attempts against the identical dimension. Its own reserved-quantity UPDATE now also bumps record_version/updated_at so a reservation is a visible, detectable change to any caller checking the balance''s own optimistic-concurrency version, not only an on_hand-changing movement -- both inside the identical nested begin/exception block ATW-017 already established, never reverting it.';

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
  if not found then
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

comment on function app.release_inventory_reservation is
  'ATW-015/hardened this checkpoint: its own reserved-quantity UPDATE now also bumps record_version/updated_at (harden migration 20260730280000), matching app.reserve_inventory.';

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
  if not found then
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

comment on function app.consume_inventory_reservation is
  'ATW-015/hardened this checkpoint: posts a real negative app.post_inventory_movement (movement_type=consumption) atomically with the reservation status transition -- never a bare balance decrement. Idempotent on the caller-supplied p_idempotency_key (delegated to app.post_inventory_movement''s own idempotency); a same-reservation retry after the first success is additionally a direct no-op (status already consumed). Its own reserved-quantity UPDATE now also bumps record_version/updated_at a second time on top of app.post_inventory_movement''s own on_hand bump (harden migration 20260730280000) -- two real changes to the balance row in the same call, two version bumps.';

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's PUBLIC-execute
-- default, the standing per-migration convention since PLT-118, re-applied here even
-- though this migration widens (not creates) functions -- CREATE OR REPLACE does not
-- reset a function's own grants, but this statement is cheap, idempotent, and keeps
-- the convention directly provable per-migration rather than relying on a prior
-- migration's own grant surviving unmodified.
revoke execute on all functions in schema app from public;

grant execute on function app.reserve_inventory(uuid, uuid, uuid, uuid, uuid, text, text, numeric, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.release_inventory_reservation(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.consume_inventory_reservation(uuid, text, uuid, text) to authenticated, service_role;
