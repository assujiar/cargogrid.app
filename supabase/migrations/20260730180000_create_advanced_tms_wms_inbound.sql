-- Advanced TMS/WMS capability ATW-012 (CG-S10-ATW-012, Prompt 231, "WMS Inbound" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). Implements this
-- prompt's own §4 objective: "canonical warehouse inbound orders that inherit
-- customer/SKU/shipment/source data and drive receiving without redundant entry."
--
-- Design boundary (disclosed):
--
-- 1. **Owner scope is tenant + customer-owner + warehouse company-org-unit, mirroring
--    `app.warehouses`' own record-scope shape (`ATW-229`) exactly** -- an inbound
--    order is a warehouse-operational record, not a Commercial-adjacent reference
--    identity like `app.item_masters` (`ATW-011A`), so it is scoped by
--    `app.lead_record_scope_org_unit_ids(warehouse.company_org_unit_id)`, not
--    tenant-wide.
-- 2. **`owner_account_id` is a mandatory `uuid references app.accounts (id)`**,
--    inherited from `app.shipment_orders.shipper_account_id` when prepared from a
--    source shipment, or supplied directly for a manual inbound -- the identical
--    proven FK shape `ATW-011A`'s own `app.item_masters.owner_account_id` already
--    established, reused rather than re-derived.
-- 3. **`source_type` is a real closed CHECK enum (`shipment_order`/`manual`/
--    `import`), deliberately excluding `purchase_order`.** Prompt 231 §24 itself
--    states "Future PO/vendor linkage does not implement Step 11 lifecycle" -- adding
--    a `purchase_order` value now, with no Procurement-phase vendor/PO table to
--    reference, would fabricate a business capability this prompt explicitly
--    disclaims. `source_shipment_order_id` is populated if and only if
--    `source_type = 'shipment_order'`; a manual inbound requires a non-empty
--    `source_reason` (Prompt 231 §24: "manual re-entry requires governed exception").
-- 4. **Duplicate-source prevention is a real partial unique index, not merely an
--    application-level check** (Prompt 231 §23: "Block duplicate source"): at most
--    one non-cancelled inbound order per `(tenant_id, source_shipment_order_id)`, and
--    per `(tenant_id, idempotency_key)` for manual/import sources -- a cancelled
--    order frees its own source/key for a fresh attempt, never permanently exhausts
--    it.
-- 5. **A bounded, disclosed alternative to the full Configurable Numbering Engine
--    (`PLT-125`)** -- `app.wms_inbound_order_number_counters` +
--    `app.next_wms_inbound_order_number`, the identical per-tenant monotonic-counter
--    shape `app.next_job_order_number` (`OPS-168`) and `app.next_quotation_number`
--    (`COM-151`) already established, reused rather than a third bespoke mechanism.
-- 6. **Line items snapshot `lot_controlled`/`serial_controlled`/`expiry_controlled`
--    from `app.item_masters` at add-time**, the identical "governed snapshot, never
--    silently re-derived" precedent `app.shipment_orders.cargo_service_snapshot`
--    (`OPS-169`) already established -- a later change to the item master's own
--    control flags does not retroactively alter an already-added line.
-- 7. **No on-hand/allocated/received quantity column exists anywhere in this
--    migration.** Prompt 231 §24 itself: "Expected quantity is not on-hand
--    inventory; stock changes only through receiving ledger movements" -- those are
--    `ATW-234`'s (Inventory Ledger) own derived-balance columns, never duplicated
--    here.
-- 8. **The lifecycle this migration owns is bounded to `draft` -> `scheduled` ->
--    `confirmed` (or `cancelled` from any of those three)** -- Prompt 231's own §4
--    objective is to "drive receiving," not perform it; `ATW-232` (WMS Receiving) is
--    the next task and owns whatever state a confirmed inbound order transitions
--    into once physical receiving begins. `app.cancel_wms_inbound_order` does not
--    check for real receiving progress against any table, since none exists yet at
--    this checkpoint -- disclosed, `ATW-232` (or whichever future capability first
--    adds a real receiving-progress table) is the one obligated to wire that guard
--    before it lets a partially-received inbound order cancel, the identical
--    deferred-obligation boundary `ATW-229`/`ATW-230`/`ATW-011B` already used.
-- 9. **Document attachment reuses `app.files`' own generic polymorphic
--    `record_type`/`record_id` reference (`PLT-128`) directly** -- `record_type =
--    'wms_inbound_order'` needs no new migration code, the same "mechanism proven,
--    live wiring deferred" posture already used for `app.warehouse_customer_
--    eligibility` (`ATW-229`). A dedicated, WMS-specific document-*requirement*/
--    completeness tracker (mirroring `OPS-176`'s own shipment-scoped checklist) is
--    explicitly **not** built here -- `OPS-176`'s own tables are shipment-specific,
--    not generically reusable, and inventing a second, WMS-specific requirement
--    taxonomy with no source document naming exact required document types would
--    fabricate a business rule beyond what Prompt 231 actually specifies.
-- 10. **Staged/bulk line import is a direct bulk RPC
--     (`app.add_wms_inbound_order_lines`), not the full generic Import/Export Job
--     Framework (`PLT-131`).** `ISS-2026-013` (`docs/runtime/KNOWN_ISSUES.md`)
--     already named this checkpoint as the framework's obligated first real adopter
--     if it were used; a bounded direct bulk-insert RPC satisfies Prompt 231 §22's
--     own "import staged lines" alt flow without pulling in the full staged-job/
--     commit-adapter machinery for a capability this size, the same proportionate-
--     effort reasoning `COM-151`'s own header already used for bypassing the full
--     Numbering Engine.
-- 11. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Numbering (design note 5).
create table app.wms_inbound_order_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.wms_inbound_order_number_counters is
  'ATW-012: one atomic, tenant-scoped monotonic counter for app.next_wms_inbound_order_number() -- a bounded, disclosed alternative to the full Configurable Numbering Engine (PLT-125), mirroring app.job_order_number_counters (OPS-168) exactly.';

create function app.next_wms_inbound_order_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.wms_inbound_order_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.wms_inbound_order_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'WMSIN-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

-- 2. Inbound order header.
create table app.wms_inbound_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  owner_account_id uuid not null references app.accounts (id),
  inbound_number text not null,
  source_type text not null,
  source_shipment_order_id uuid references app.shipment_orders (id),
  source_reason text,
  idempotency_key text,
  expected_date date,
  appointment_window_start timestamptz,
  appointment_window_end timestamptz,
  status text not null default 'draft',
  cancelled_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_inbound_orders_number_unique unique (tenant_id, inbound_number),
  constraint wms_inbound_orders_source_type_check check (source_type in ('shipment_order', 'manual', 'import')),
  constraint wms_inbound_orders_status_check check (status in ('draft', 'scheduled', 'confirmed', 'cancelled')),
  constraint wms_inbound_orders_source_shipment_shape_check check (
    (source_type = 'shipment_order' and source_shipment_order_id is not null)
    or (source_type <> 'shipment_order' and source_shipment_order_id is null)
  ),
  constraint wms_inbound_orders_manual_reason_check check (source_type <> 'manual' or (source_reason is not null and length(trim(source_reason)) > 0)),
  constraint wms_inbound_orders_appointment_window_check check (appointment_window_start is null or appointment_window_end is null or appointment_window_end > appointment_window_start),
  constraint wms_inbound_orders_cancelled_reason_check check (status <> 'cancelled' or (cancelled_reason is not null and length(trim(cancelled_reason)) > 0))
);

comment on table app.wms_inbound_orders is
  'ATW-012: canonical warehouse inbound order header. owner_account_id/source_type/source_shipment_order_id/idempotency_key are immutable once created (no RPC below ever changes them). Carries no on-hand/received quantity column (design note 7) -- ATW-234 owns derived balances.';

create unique index wms_inbound_orders_source_shipment_unique on app.wms_inbound_orders (tenant_id, source_shipment_order_id) where source_type = 'shipment_order' and status <> 'cancelled';
create unique index wms_inbound_orders_idempotency_unique on app.wms_inbound_orders (tenant_id, idempotency_key) where idempotency_key is not null and status <> 'cancelled';
create index wms_inbound_orders_tenant_warehouse_status_idx on app.wms_inbound_orders (tenant_id, warehouse_id, status);
create index wms_inbound_orders_tenant_owner_idx on app.wms_inbound_orders (tenant_id, owner_account_id);

create function app.touch_wms_inbound_orders_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_inbound_orders_touch_row
  before update on app.wms_inbound_orders
  for each row
  execute function app.touch_wms_inbound_orders_row();

-- 3. Inbound order lines.
create table app.wms_inbound_order_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  inbound_order_id uuid not null references app.wms_inbound_orders (id),
  line_number integer not null,
  item_master_id uuid not null references app.item_masters (id),
  expected_uom_code text not null references app.uoms (code),
  expected_quantity numeric not null,
  lot_controlled boolean not null default false,
  serial_controlled boolean not null default false,
  expiry_controlled boolean not null default false,
  notes text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_inbound_order_lines_number_unique unique (inbound_order_id, line_number),
  constraint wms_inbound_order_lines_quantity_check check (expected_quantity > 0)
);

comment on table app.wms_inbound_order_lines is
  'ATW-012: item_master_id/expected_uom_code are immutable once created; lot_controlled/serial_controlled/expiry_controlled are a governed snapshot of app.item_masters at add-time (design note 6), never live-recomputed.';

create index wms_inbound_order_lines_order_idx on app.wms_inbound_order_lines (inbound_order_id);

create function app.touch_wms_inbound_order_lines_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_inbound_order_lines_touch_row
  before update on app.wms_inbound_order_lines
  for each row
  execute function app.touch_wms_inbound_order_lines_row();

-- 4. Readiness preview composite type (mirrors app.warehouse_deactivation_impact's
-- own preview-matches-what-the-mutation-blocks-on shape, ATW-229).
create type app.wms_inbound_readiness as (
  has_lines boolean,
  warehouse_active boolean,
  owner_active boolean,
  invalid_line_count integer,
  ready boolean
);

-- 5. Mutations. Every mutation is RBAC-gated (OPS:Create/Edit/View) and
-- record-scope-gated (app.can_access_record against the order's own warehouse's
-- company org unit, design note 1), and audited.

create function app.prepare_wms_inbound_from_shipment(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_warehouse_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.shipment_orders;
  v_warehouse app.warehouses;
  v_existing app.wms_inbound_orders;
  v_order app.wms_inbound_orders;
  v_number text;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'shipment_order_not_found: % is not a shipment order of tenant %', p_shipment_order_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status = 'cancelled' then
    raise exception 'stale_source: shipment order % is cancelled', p_shipment_order_id using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active', p_warehouse_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create an inbound order under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.wms_inbound_orders
    where tenant_id = p_tenant_id and source_type = 'shipment_order' and source_shipment_order_id = p_shipment_order_id and status <> 'cancelled';
  if found then
    return v_existing;
  end if;

  v_number := app.next_wms_inbound_order_number(p_tenant_id);
  insert into app.wms_inbound_orders (
    tenant_id, warehouse_id, owner_account_id, inbound_number, source_type, source_shipment_order_id, created_by
  ) values (
    p_tenant_id, p_warehouse_id, v_shipment.shipper_account_id, v_number, 'shipment_order', p_shipment_order_id, p_actor_label
  )
  returning * into v_order;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_wms_inbound_from_shipment',
    'app.wms_inbound_orders', v_order.id, 'success', null, null,
    jsonb_build_object('source_shipment_order_id', p_shipment_order_id, 'warehouse_id', p_warehouse_id, 'inbound_number', v_number)
  );

  return v_order;
end;
$$;

comment on function app.prepare_wms_inbound_from_shipment is
  'ATW-012: idempotent on (tenant_id, source_shipment_order_id) among non-cancelled rows -- a retry returns the identical row. owner_account_id is inherited from the shipment order''s own shipper_account_id, never re-entered.';

create function app.create_manual_wms_inbound(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_owner_account_id uuid,
  p_source_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_account app.accounts;
  v_existing app.wms_inbound_orders;
  v_order app.wms_inbound_orders;
  v_number text;
begin
  if p_source_reason is null or length(trim(p_source_reason)) = 0 then
    raise exception 'invalid_reason: a source reason is required for a manual inbound order' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required for a manual inbound order' using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active', p_warehouse_id using errcode = 'check_violation';
  end if;

  select * into v_account from app.accounts where id = p_owner_account_id and tenant_id = p_tenant_id and status = 'active';
  if not found then
    raise exception 'owner_account_not_found: % is not an active account of tenant %', p_owner_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create an inbound order under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.wms_inbound_orders
    where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key and status <> 'cancelled';
  if found then
    return v_existing;
  end if;

  v_number := app.next_wms_inbound_order_number(p_tenant_id);
  insert into app.wms_inbound_orders (
    tenant_id, warehouse_id, owner_account_id, inbound_number, source_type, source_reason, idempotency_key, created_by
  ) values (
    p_tenant_id, p_warehouse_id, p_owner_account_id, v_number, 'manual', p_source_reason, p_idempotency_key, p_actor_label
  )
  returning * into v_order;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_manual_wms_inbound',
    'app.wms_inbound_orders', v_order.id, 'success', p_source_reason, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'owner_account_id', p_owner_account_id, 'inbound_number', v_number)
  );

  return v_order;
end;
$$;

comment on function app.create_manual_wms_inbound is
  'ATW-012: the governed manual-entry exception path (Prompt 231 §24) -- requires a non-empty source_reason. Idempotent on (tenant_id, idempotency_key) among non-cancelled rows.';

create function app.add_wms_inbound_order_line(
  p_inbound_order_id uuid,
  p_item_master_id uuid,
  p_expected_uom_code text,
  p_expected_quantity numeric,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_order_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_item app.item_masters;
  v_next_line integer;
  v_line app.wms_inbound_order_lines;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
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
$$;

comment on function app.add_wms_inbound_order_line is
  'ATW-012: only while the header is draft. item_master_id must be an active item owned by the same account as the inbound order (design note 2) -- rejects a foreign-owner item rather than silently accepting it. line_number auto-assigns sequentially.';

create function app.add_wms_inbound_order_lines(
  p_inbound_order_id uuid,
  p_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.wms_inbound_order_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_line_input jsonb;
  v_line app.wms_inbound_order_lines;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'invalid_lines: p_lines must be a non-empty JSON array' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(p_lines) > 200 then
    raise exception 'too_many_lines: at most 200 lines per bulk-import call, got %', jsonb_array_length(p_lines) using errcode = 'check_violation';
  end if;

  for v_line_input in select * from jsonb_array_elements(p_lines) loop
    v_line := app.add_wms_inbound_order_line(
      p_inbound_order_id,
      (v_line_input ->> 'item_master_id')::uuid,
      v_line_input ->> 'expected_uom_code',
      (v_line_input ->> 'expected_quantity')::numeric,
      v_line_input ->> 'notes',
      p_actor_auth_user_id,
      p_actor_label
    );
    return next v_line;
  end loop;

  return;
end;
$$;

comment on function app.add_wms_inbound_order_lines is
  'ATW-012: the bounded bulk/staged-import alt flow (Prompt 231 §22, design note 10) -- a direct bulk RPC, not the full generic Import/Export Job Framework (PLT-131). Each element reuses app.add_wms_inbound_order_line verbatim (identical validation, no duplicated logic); a bad element aborts the whole call (all-or-nothing), never a partial import.';

create function app.update_wms_inbound_order_line(
  p_line_id uuid,
  p_expected_quantity numeric,
  p_notes text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_order_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
$$;

comment on function app.update_wms_inbound_order_line is
  'ATW-012: mutable fields only -- item_master_id/expected_uom_code/control-flag snapshots are immutable once created. Optimistic-concurrency gated (record_version). Only while the header is draft.';

create function app.remove_wms_inbound_order_line(
  p_line_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns boolean
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
$$;

create function app.schedule_wms_inbound_appointment(
  p_inbound_order_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_line_count integer;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
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
$$;

comment on function app.schedule_wms_inbound_appointment is
  'ATW-012: draft -> scheduled only, requires at least one line to already exist. Reschedule (Prompt 231 §22 alt flow) reuses this same function -- calling it again while still draft is not possible once scheduled; see app.reschedule_wms_inbound_appointment for the scheduled-state reschedule path.';

create function app.reschedule_wms_inbound_appointment(
  p_inbound_order_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
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
$$;

comment on function app.reschedule_wms_inbound_appointment is
  'ATW-012: the reschedule alt flow (Prompt 231 §22) -- scheduled or confirmed only, status itself never changes (a reschedule is not a lifecycle transition).';

create function app.get_wms_inbound_readiness(p_inbound_order_id uuid, p_actor_auth_user_id uuid)
returns app.wms_inbound_readiness
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.get_wms_inbound_readiness is
  'ATW-012: read-only preview of exactly what app.confirm_wms_inbound itself will block on (mirrors app.get_warehouse_deactivation_impact''s own preview-matches-mutation shape, ATW-229).';

create function app.confirm_wms_inbound(
  p_inbound_order_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_readiness app.wms_inbound_readiness;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
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
$$;

comment on function app.confirm_wms_inbound is
  'ATW-012: scheduled -> confirmed only, re-validates full readiness (app.get_wms_inbound_readiness) rather than trusting a stale prior check. A confirmed inbound order is what ATW-232 (WMS Receiving) is expected to consume next.';

create function app.cancel_wms_inbound(
  p_inbound_order_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
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
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status = 'cancelled' then
    return v_order;
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
$$;

comment on function app.cancel_wms_inbound is
  'ATW-012: does not check for real receiving progress against any table (design note 8) -- none exists yet at this checkpoint. ATW-232 (WMS Receiving), or whichever future capability first adds a real receiving-progress table, is obligated to wire a real "cancellation after receipt" guard before it lets a partially-received inbound order cancel.';

-- 6. Reads.

create function app.get_wms_inbound_order(p_inbound_order_id uuid, p_actor_auth_user_id uuid)
returns app.wms_inbound_orders
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
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

  return v_order;
end;
$$;

create function app.list_wms_inbound_order_lines(p_inbound_order_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_inbound_order_lines
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_order app.wms_inbound_orders;
begin
  v_order := app.get_wms_inbound_order(p_inbound_order_id, p_actor_auth_user_id);

  return query
  select * from app.wms_inbound_order_lines where inbound_order_id = p_inbound_order_id order by line_number;
end;
$$;

comment on function app.list_wms_inbound_order_lines is
  'ATW-012: reuses app.get_wms_inbound_order for its own authority/record-scope gate rather than duplicating the check.';

create function app.list_wms_inbound_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.wms_inbound_orders
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
  select o.* from app.wms_inbound_orders o
  join app.warehouses w on w.id = o.warehouse_id
  where o.tenant_id = p_tenant_id
    and (p_warehouse_id is null or o.warehouse_id = p_warehouse_id)
    and (p_owner_account_id is null or o.owner_account_id = p_owner_account_id)
    and (p_status_filter is null or o.status = p_status_filter)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
  order by o.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_inbound_orders is
  'ATW-012: bounded read (p_limit default 50, hard-capped 200), record-scoped per row by the order''s own warehouse company org unit -- mirrors app.list_tenant_warehouses'' own record-scoped list shape (ATW-229), not tenant-wide.';

-- 7. RLS -- record scope enforced in the database (mirrors app.warehouses, ATW-229),
-- not UI-only.

alter table app.wms_inbound_orders enable row level security;

create policy wms_inbound_orders_select_scoped on app.wms_inbound_orders
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = wms_inbound_orders.warehouse_id
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.wms_inbound_order_lines enable row level security;

create policy wms_inbound_order_lines_select_scoped on app.wms_inbound_order_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_inbound_orders o
      join app.warehouses w on w.id = o.warehouse_id
      where o.id = wms_inbound_order_lines.inbound_order_id
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.wms_inbound_orders, app.wms_inbound_order_lines to authenticated, service_role;
grant insert, update, delete on app.wms_inbound_orders, app.wms_inbound_order_lines to service_role;
grant insert, update on app.wms_inbound_order_number_counters to service_role;

grant execute on function app.next_wms_inbound_order_number(uuid) to service_role;
grant execute on function app.prepare_wms_inbound_from_shipment(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.create_manual_wms_inbound(uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_wms_inbound_order_line(uuid, uuid, text, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_wms_inbound_order_lines(uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.update_wms_inbound_order_line(uuid, numeric, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.remove_wms_inbound_order_line(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.schedule_wms_inbound_appointment(uuid, timestamptz, timestamptz, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reschedule_wms_inbound_appointment(uuid, timestamptz, timestamptz, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_inbound_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.confirm_wms_inbound(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_wms_inbound(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_inbound_order(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_inbound_order_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_inbound_orders(uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
