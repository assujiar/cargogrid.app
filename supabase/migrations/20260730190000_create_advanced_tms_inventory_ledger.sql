-- Advanced TMS/WMS capability ATW-015 (CG-S10-ATW-015, Prompt 234, "Inventory
-- Ledger" -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1).
-- Implements this prompt's own §4 objective: "the canonical idempotent inventory
-- movement ledger and derived balance/reservation model for all WMS stock changes."
--
-- Sequencing note (disclosed, not a silent deviation): Prompt 234 §9 itself names
-- "ATW-229..233" as upstream, including `ATW-232`/`233` (WMS Receiving/Putaway) --
-- but those in turn both require posting real ledger movements (their own §4/§21),
-- creating exactly the circular dependency this session's own gap audit recorded as
-- `ISS-2026-011`. The operator's own explicit instruction ("jalankan prompt 231, 234,
-- 232, 233, 235... hingga 238") resolves it by building this capability immediately
-- after `ATW-231` and before `232`/`233` -- this migration's own real upstream is
-- therefore `ATW-229..231`/`011A` ("approved item/UOM/owner/status identity," §9's
-- own substantive clause), not `232`/`233` themselves, which do not exist yet.
--
-- Design boundary (disclosed):
--
-- 1. **A real, race-safe balance upsert via `INSERT ... ON CONFLICT DO UPDATE`**,
--    mirroring `app.arbitrate_and_project_vehicle_position`'s own current-position
--    upsert pattern (`ATW-226F`) verbatim -- Postgres serializes concurrent upserts
--    against the same conflict target at the row level, making this structurally
--    race-safe regardless of caller concurrency. `ISS-2026-014`
--    (`docs/runtime/KNOWN_ISSUES.md`) already discloses that no multi-session test
--    harness exists yet to *prove* this under real concurrent load -- this migration
--    reasons about and structurally relies on Postgres's own guarantee, but does not
--    claim load-tested evidence it does not have.
-- 2. **Lot/serial/expiry are real, nullable dimension columns on movement lines and
--    balances now, not deferred to `ATW-235`** -- `app.item_masters` (`ATW-011A`)
--    already carries `lot_controlled`/`serial_controlled`/`expiry_controlled` flags;
--    the ledger must carry the matching dimension columns from day one so `ATW-235`
--    (Lot, Batch, Serial and Expiry, the very next task in this session's own
--    sequence) can *govern* them (a dedicated control/identity table, uniqueness,
--    lifecycle) rather than retrofit a schema change onto an already-`VERIFIED`
--    ledger. They are plain `text`/`date` columns here, not yet foreign-keyed to any
--    lot/serial identity table -- none exists yet at this checkpoint.
-- 3. **Balance uniqueness uses a `coalesce`-normalized functional unique index**, not
--    a bare column-list unique constraint -- PostgreSQL's own `UNIQUE` semantics treat
--    every `NULL` as distinct from every other `NULL`, so a bare unique index on
--    `(..., lot_number, serial_number)` would silently allow multiple `on_hand` rows
--    for the same item/location when both are `NULL` (the common no-lot/no-serial
--    case). `coalesce(lot_number, '')`/`coalesce(serial_number, '')` in the index
--    expression closes that gap structurally, not by convention.
-- 4. **`app.post_inventory_movement` is the one generic posting primitive every
--    future WMS capability composes, not a movement-type-specific wrapper per
--    capability.** `ATW-232`/`233`/`236`/`239` (Receiving/Putaway/Picking/Cycle
--    Count) are each expected to call this function with their own
--    `movement_type`/`source_type`/`source_id`, never to insert into
--    `app.inventory_movements`/`app.inventory_balances` directly -- the structural
--    mechanism behind Prompt 234 §24's own "normal roles never patch balance."
-- 5. **`location_id` is mandatory** (`references app.warehouse_locations`, not
--    nullable) -- `ATW-230`'s own six-value `location_type` taxonomy already
--    includes `dock`/`staging`, so a receipt not yet put away still has a real
--    location (the dock/staging area itself), never a null placeholder.
-- 6. **A `transfer` movement must balance to exactly zero across its own lines**
--    (Prompt 234 §23: "unbalanced transfer") -- enforced as a real runtime check in
--    `app.post_inventory_movement`, not merely documented.
-- 7. **Reservation is a distinct ledger-adjacent table (`app.inventory_reservations`),
--    not a derived count** -- mirrors `ATW-227`'s own `app.vehicle_capacity_
--    reservations` shape (reserve/consume/release, `status` lifecycle, idempotent on
--    source), the closest proven precedent for exactly this pattern in this
--    repository. Consuming a reservation posts a real negative movement atomically in
--    the same function call, never a bare balance decrement.
-- 8. **Customer-owner-scoped read projections (Prompt 234 §26: "customers see
--    owner-scoped balance/ledger projections only") are explicitly deferred** --
--    `ATW-242` (Customer Inventory Access Contract) does not exist yet; this
--    migration's own reads are staff-facing (`OPS:View`, warehouse-record-scoped)
--    only, the identical disclosed boundary `ATW-229`'s own customer-eligibility
--    ledger already used for its own future consumer.
-- 9. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--    ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Movement header (append-only -- no UPDATE/DELETE grant to any non-service_role
-- caller anywhere in this migration; a correction is always a new, linked movement).
create table app.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  movement_type text not null,
  source_type text not null,
  source_id uuid,
  idempotency_key text not null,
  corrects_movement_id uuid references app.inventory_movements (id),
  reason text,
  occurred_at timestamptz not null default now(),
  posted_by text,
  created_at timestamptz not null default now(),
  constraint inventory_movements_type_check check (movement_type in ('receipt', 'transfer', 'consumption', 'adjustment', 'opening_balance', 'reversal')),
  constraint inventory_movements_source_type_check check (source_type in ('wms_inbound_order', 'reservation', 'manual', 'opening_balance', 'reversal')),
  constraint inventory_movements_reason_check check (movement_type not in ('adjustment', 'reversal') or (reason is not null and length(trim(reason)) > 0)),
  constraint inventory_movements_correction_shape_check check (movement_type <> 'reversal' or corrects_movement_id is not null),
  constraint inventory_movements_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.inventory_movements is
  'ATW-015: the canonical, append-only inventory movement header. Every balance change in this repository is derived exclusively from this table and app.inventory_movement_lines via app.post_inventory_movement -- no other function or direct table write ever changes app.inventory_balances.';

create index inventory_movements_tenant_warehouse_idx on app.inventory_movements (tenant_id, warehouse_id, occurred_at desc);
create index inventory_movements_source_idx on app.inventory_movements (source_type, source_id);

-- 2. Movement lines -- the full dimension tuple + exact signed quantity.
-- warehouse_id is a denormalized copy of the parent movement's own warehouse_id
-- (set exclusively by app.post_inventory_movement, never a caller-supplied value) --
-- avoids a join for every warehouse-scoped dimension lookup (Prompt 234 §17's own
-- "tenant-aware composite indexes" requirement), the same denormalization class
-- app.shipment_orders.cargo_service_snapshot already uses for a governed copy.
create table app.inventory_movement_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  movement_id uuid not null references app.inventory_movements (id),
  warehouse_id uuid not null references app.warehouses (id),
  owner_account_id uuid not null references app.accounts (id),
  item_master_id uuid not null references app.item_masters (id),
  location_id uuid not null references app.warehouse_locations (id),
  uom_code text not null references app.uoms (code),
  signed_quantity numeric not null,
  lot_number text,
  serial_number text,
  expiry_date date,
  status text not null default 'on_hand',
  created_at timestamptz not null default now(),
  constraint inventory_movement_lines_quantity_check check (signed_quantity <> 0),
  constraint inventory_movement_lines_status_check check (status in ('on_hand', 'held', 'damaged', 'expired'))
);

comment on table app.inventory_movement_lines is
  'ATW-015: lot_number/serial_number/expiry_date are real, nullable dimension columns (design note 2) -- not yet foreign-keyed to any lot/serial identity table (ATW-235 is the very next task and owns that governance layer).';

create index inventory_movement_lines_movement_idx on app.inventory_movement_lines (movement_id);
create index inventory_movement_lines_dimension_idx on app.inventory_movement_lines (tenant_id, warehouse_id, item_master_id);

-- 3. Derived balances -- written exclusively by app.post_inventory_movement's own
-- upsert (design note 1); never a direct target of any other function or grant.
create table app.inventory_balances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  owner_account_id uuid not null references app.accounts (id),
  item_master_id uuid not null references app.item_masters (id),
  location_id uuid not null references app.warehouse_locations (id),
  lot_number text,
  serial_number text,
  status text not null default 'on_hand',
  on_hand numeric not null default 0,
  reserved numeric not null default 0,
  held numeric not null default 0,
  available numeric generated always as (on_hand - reserved - held) stored,
  record_version integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint inventory_balances_status_check check (status in ('on_hand', 'held', 'damaged', 'expired')),
  constraint inventory_balances_on_hand_check check (on_hand >= 0),
  constraint inventory_balances_reserved_check check (reserved >= 0),
  constraint inventory_balances_held_check check (held >= 0),
  constraint inventory_balances_reserved_held_bound_check check (reserved + held <= on_hand)
);

comment on table app.inventory_balances is
  'ATW-015: derived balance, one row per dimension tuple (design note 3''s own coalesce-normalized unique index below). available is a real STORED generated column (on_hand - reserved - held), never computed ad hoc by a caller. Written exclusively by app.post_inventory_movement/app.reserve_inventory/app.release_inventory_reservation/app.consume_inventory_reservation -- no other function or grant may write it.';

create unique index inventory_balances_dimension_unique on app.inventory_balances (
  tenant_id, warehouse_id, owner_account_id, item_master_id, location_id,
  coalesce(lot_number, ''), coalesce(serial_number, ''), status
);
create index inventory_balances_tenant_item_idx on app.inventory_balances (tenant_id, item_master_id);
create index inventory_balances_tenant_owner_idx on app.inventory_balances (tenant_id, owner_account_id);

-- 4. Reservations -- a distinct ledger-adjacent table (design note 7), mirroring
-- app.vehicle_capacity_reservations' own reserve/consume/release shape (ATW-227).
create table app.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  balance_id uuid not null references app.inventory_balances (id),
  reserved_quantity numeric not null,
  status text not null default 'active',
  source_type text not null,
  source_id uuid,
  idempotency_key text not null,
  released_reason text,
  consumed_movement_id uuid references app.inventory_movements (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inventory_reservations_status_check check (status in ('active', 'consumed', 'released')),
  constraint inventory_reservations_quantity_check check (reserved_quantity > 0),
  constraint inventory_reservations_source_type_check check (source_type in ('wms_inbound_order', 'manual')),
  constraint inventory_reservations_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.inventory_reservations is
  'ATW-015: reserved_quantity is the amount originally reserved and never mutated in place -- app.consume_inventory_reservation/app.release_inventory_reservation each transition status exactly once (active -> consumed|released), append-only in spirit even though this is a mutable header row (mirrors app.vehicle_capacity_reservations, ATW-227).';

create index inventory_reservations_balance_idx on app.inventory_reservations (balance_id, status);

create function app.touch_inventory_reservations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger inventory_reservations_touch_row
  before update on app.inventory_reservations
  for each row
  execute function app.touch_inventory_reservations_row();

-- 5. app.post_inventory_movement -- the one generic posting primitive (design note 4).
create function app.post_inventory_movement(
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

  insert into app.inventory_movements (tenant_id, warehouse_id, movement_type, source_type, source_id, idempotency_key, reason, posted_by, corrects_movement_id)
  values (p_tenant_id, p_warehouse_id, p_movement_type, p_source_type, p_source_id, p_idempotency_key, p_reason, p_actor_label, p_corrects_movement_id)
  returning * into v_movement;

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
  'ATW-015: idempotent on (tenant_id, idempotency_key) -- a retry returns the identical header, never re-posts lines or double-counts balances. Every line''s own item/location/UOM/owner is independently validated; a transfer''s own lines must sum to exactly zero (design note 6); a resulting negative on_hand or a serial exceeding 1 both fail the whole call (all lines already inserted this transaction are rolled back with it).';

-- 6. Reservation lifecycle.
create function app.reserve_inventory(
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

  update app.inventory_balances set reserved = reserved + p_quantity where id = v_balance.id;

  insert into app.inventory_reservations (tenant_id, balance_id, reserved_quantity, source_type, source_id, idempotency_key, created_by)
  values (p_tenant_id, v_balance.id, p_quantity, p_source_type, p_source_id, p_idempotency_key, p_actor_label)
  returning * into v_reservation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'reserve_inventory',
    'app.inventory_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('balance_id', v_balance.id, 'quantity', p_quantity)
  );

  return v_reservation;
end;
$$;

comment on function app.reserve_inventory is
  'ATW-015: idempotent on (tenant_id, idempotency_key). Locks the target balance row (SELECT ... FOR UPDATE) before checking availability, serializing concurrent reservation attempts against the identical dimension.';

create function app.release_inventory_reservation(
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

  update app.inventory_balances set reserved = reserved - v_reservation.reserved_quantity where id = v_reservation.balance_id;
  update app.inventory_reservations set status = 'released', released_reason = p_reason where id = p_reservation_id returning * into v_reservation;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_inventory_reservation',
    'app.inventory_reservations', v_reservation.id, 'success', p_reason, null, null
  );

  return v_reservation;
end;
$$;

create function app.consume_inventory_reservation(
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

  update app.inventory_balances set reserved = reserved - v_reservation.reserved_quantity where id = v_reservation.balance_id;
  update app.inventory_reservations set status = 'consumed', consumed_movement_id = v_movement.id where id = p_reservation_id returning * into v_reservation;

  return v_reservation;
end;
$$;

comment on function app.consume_inventory_reservation is
  'ATW-015: posts a real negative app.post_inventory_movement (movement_type=consumption) atomically with the reservation status transition -- never a bare balance decrement. Idempotent on the caller-supplied p_idempotency_key (delegated to app.post_inventory_movement''s own idempotency); a same-reservation retry after the first success is additionally a direct no-op (status already consumed).';

-- 7. Reversal -- posts a new movement with exactly negated lines, never edits history.
create function app.reverse_inventory_movement(
  p_movement_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.inventory_movements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_original app.inventory_movements;
  v_lines jsonb;
begin
  select * into v_original from app.inventory_movements where id = p_movement_id;
  if not found then
    raise exception 'movement_not_found: %', p_movement_id using errcode = 'no_data_found';
  end if;
  if v_original.movement_type = 'reversal' then
    raise exception 'invalid_reversal: a reversal movement may not itself be reversed' using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.inventory_movements where corrects_movement_id = p_movement_id) then
    raise exception 'already_reversed: movement % has already been reversed', p_movement_id using errcode = 'check_violation';
  end if;

  select jsonb_agg(jsonb_build_object(
    'owner_account_id', owner_account_id, 'item_master_id', item_master_id, 'location_id', location_id,
    'uom_code', uom_code, 'signed_quantity', -signed_quantity, 'lot_number', lot_number, 'serial_number', serial_number,
    'expiry_date', expiry_date, 'status', status
  )) into v_lines
  from app.inventory_movement_lines where movement_id = p_movement_id;

  return app.post_inventory_movement(
    v_original.tenant_id, v_original.warehouse_id, 'reversal', 'reversal', p_movement_id, p_idempotency_key, p_reason,
    v_lines, p_actor_auth_user_id, p_actor_label, p_movement_id
  );
end;
$$;

comment on function app.reverse_inventory_movement is
  'ATW-015: a governed correction, never a delete or in-place edit (design note in app.inventory_movements'' own comment). Rejects reversing an already-reversed movement or a reversal itself -- a correction chain never doubles back on itself.';

-- 8. Reads.

create function app.get_inventory_balance(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_owner_account_id uuid,
  p_item_master_id uuid,
  p_location_id uuid,
  p_lot_number text,
  p_serial_number text,
  p_status text,
  p_actor_auth_user_id uuid
)
returns app.inventory_balances
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_balance app.inventory_balances;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_balance from app.inventory_balances
    where tenant_id = p_tenant_id and warehouse_id = p_warehouse_id and owner_account_id = p_owner_account_id
      and item_master_id = p_item_master_id and location_id = p_location_id
      and coalesce(lot_number, '') = coalesce(p_lot_number, '') and coalesce(serial_number, '') = coalesce(p_serial_number, '')
      and status = p_status;
  if not found then
    raise exception 'balance_not_found: no balance exists for the requested dimension' using errcode = 'no_data_found';
  end if;

  return v_balance;
end;
$$;

create function app.list_inventory_balances(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_owner_account_id uuid default null,
  p_item_master_id uuid default null,
  p_limit integer default 50
)
returns setof app.inventory_balances
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
  select b.* from app.inventory_balances b
  join app.warehouses w on w.id = b.warehouse_id
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_owner_account_id is null or b.owner_account_id = p_owner_account_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
  order by b.updated_at desc
  limit v_limit;
end;
$$;

comment on function app.list_inventory_balances is
  'ATW-015: bounded read (p_limit default 50, hard-capped 200), record-scoped per row by the balance''s own warehouse company org unit. Excludes all-zero rows (a fully depleted/never-touched dimension) from the default view.';

create function app.list_inventory_movements(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_movement_type text default null,
  p_source_type text default null,
  p_limit integer default 50
)
returns setof app.inventory_movements
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
  select m.* from app.inventory_movements m
  join app.warehouses w on w.id = m.warehouse_id
  where m.tenant_id = p_tenant_id
    and (p_warehouse_id is null or m.warehouse_id = p_warehouse_id)
    and (p_movement_type is null or m.movement_type = p_movement_type)
    and (p_source_type is null or m.source_type = p_source_type)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
  order by m.occurred_at desc
  limit v_limit;
end;
$$;

create function app.list_inventory_movement_lines(p_movement_id uuid, p_actor_auth_user_id uuid)
returns setof app.inventory_movement_lines
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_movement app.inventory_movements;
  v_warehouse app.warehouses;
  v_decision app.rbac_decision;
begin
  select * into v_movement from app.inventory_movements where id = p_movement_id;
  if not found then
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
$$;

-- 9. RLS -- record scope enforced in the database (mirrors app.warehouses/
-- app.wms_inbound_orders), not UI-only.

alter table app.inventory_movements enable row level security;

create policy inventory_movements_select_scoped on app.inventory_movements
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = inventory_movements.warehouse_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.inventory_movement_lines enable row level security;

create policy inventory_movement_lines_select_scoped on app.inventory_movement_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = inventory_movement_lines.warehouse_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.inventory_balances enable row level security;

create policy inventory_balances_select_scoped on app.inventory_balances
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = inventory_balances.warehouse_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.inventory_reservations enable row level security;

create policy inventory_reservations_select_scoped on app.inventory_reservations
  for select to authenticated
  using (
    exists (
      select 1 from app.inventory_balances b
      join app.warehouses w on w.id = b.warehouse_id
      where b.id = inventory_reservations.balance_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.inventory_movements, app.inventory_movement_lines, app.inventory_balances, app.inventory_reservations to authenticated, service_role;
grant insert, update, delete on app.inventory_movements, app.inventory_movement_lines, app.inventory_balances, app.inventory_reservations to service_role;

grant execute on function app.post_inventory_movement(uuid, uuid, text, text, uuid, text, text, jsonb, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.reserve_inventory(uuid, uuid, uuid, uuid, uuid, text, text, numeric, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.release_inventory_reservation(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.consume_inventory_reservation(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.reverse_inventory_movement(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_inventory_balance(uuid, uuid, uuid, uuid, uuid, text, text, text, uuid) to authenticated, service_role;
grant execute on function app.list_inventory_balances(uuid, uuid, uuid, uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.list_inventory_movements(uuid, uuid, uuid, text, text, integer) to authenticated, service_role;
grant execute on function app.list_inventory_movement_lines(uuid, uuid) to authenticated, service_role;
