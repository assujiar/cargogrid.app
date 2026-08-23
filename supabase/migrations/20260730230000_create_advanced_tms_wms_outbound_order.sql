-- Advanced TMS/WMS capability ATW-016A (CG-S10-ATW-016A, inserted, no source prompt
-- number -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1, once the
-- orchestrating session records it there). Capability name: "WMS Outbound Order."
--
-- Why this checkpoint exists (disclosed, mirrors the ATW-011A precedent exactly):
-- Prompt 236 (WMS Picking, ATW-017) §9 names "ATW-234..235 and a confirmed outbound
-- demand contract" as its own upstream dependency. The only WBS-designated producer of
-- that contract is Prompt 238 (WMS Outbound, ATW-019) -- but Prompt 238 §9 itself lists
-- ATW-231..237 (i.e. Picking and Packing) as ITS OWN upstream, and its own §21 main flow
-- requires "stock is allocated/picked/packed" before ship-confirmation. This is a real,
-- documented circular dependency (docs/runtime/KNOWN_ISSUES.md ISS-2026-011 Part 2), not
-- a build oversight: no existing repository entity (app.shipment_orders, Operations/
-- Phase 3, already VERIFIED) carries any item/SKU-level line detail -- only aggregate
-- basis_quantity/basis_weight_kg/basis_volume_cbm -- so there is genuinely no existing
-- "confirmed outbound demand" with real per-item quantities anywhere in this repository
-- before this migration.
--
-- This migration extracts and builds ONLY the "outbound order/demand creation and
-- confirmation" slice of Prompt 238's own §13 database-impact scope -- "outbound
-- root/version/number, customer owner/source order/shipment, lines/UOM" -- deliberately
-- EXCLUDING everything else Prompt 238 §13 names: "allocation/pick/pack references,
-- staging/dock/load/custody, canonical [ship] lifecycle, idempotent ship-confirm
-- inventory movements and billing-event eligibility." Those remain the real Prompt 238/
-- ATW-019 checkpoint's own later job, once Picking (ATW-017) and Packing (ATW-018) exist
-- to compose against -- this migration's own job is only to produce a correct, real
-- "demand" stage that chain can later reconcile against (Prompt 238 §24: "Outbound
-- quantity reconciles demand -> allocation -> pick -> pack -> load -> issue").
--
-- Design boundary (disclosed):
--
-- 1. **`app.wms_outbound_orders`/`app.wms_outbound_order_lines` mirror `app.
--    wms_inbound_orders`/`app.wms_inbound_order_lines` (`ATW-012`) near-exactly**,
--    adapted for the outbound/demand-only side -- the identical header/lines shape,
--    numbering-counter mechanism, add/update/remove line RPCs plus a bounded bulk-add
--    RPC, and a readiness projection. Deliberately NOT mirrored: `ATW-012`'s own
--    `appointment_window_start`/`appointment_window_end`/`schedule_wms_inbound_
--    appointment`/`reschedule_wms_inbound_appointment` -- dock-appointment scheduling is
--    about staging/loading physical dispatch, not demand capture, and stays Prompt 238's
--    own later job. This checkpoint's own lifecycle is therefore the simpler
--    `draft` -> `confirmed` -> `cancelled` (three states, mirroring `app.
--    shipment_orders`' own lifecycle exactly) -- `confirmed` is the exact state Prompt
--    236 §9 means by "confirmed outbound demand contract."
-- 2. **Owner scope is tenant + customer-owner + warehouse company-org-unit**, the
--    identical shape `ATW-012`'s own header note 1 already established -- an outbound
--    order is a warehouse-operational record, scoped by `app.lead_record_scope_org_
--    unit_ids(warehouse.company_org_unit_id)`, not tenant-wide. `owner_account_id` is a
--    mandatory `uuid references app.accounts (id)`, inherited from `app.shipment_
--    orders.shipper_account_id` when prepared from a source shipment, or supplied
--    directly for a manual outbound order.
-- 3. **`source_type` is a real closed CHECK enum (`shipment_order`/`manual`),
--    deliberately excluding `import`.** `ATW-012`'s own `add_wms_inbound_order_lines`
--    bulk RPC already covers the bounded "import many lines at once" need without a
--    third source_type -- this migration's own `app.add_wms_outbound_order_lines`
--    mirrors it verbatim for the same reason (Scope decisions, task brief). `source_
--    shipment_order_id` is populated if and only if `source_type = 'shipment_order'`; a
--    manual outbound order requires a non-empty `source_reason`, mirroring `ATW-012`'s
--    own governed manual-entry-exception convention exactly.
-- 4. **Sourcing from a shipment order requires the shipment order's own `status =
--    'confirmed'` at prepare time (a real, stricter check than `ATW-012`'s own "not
--    cancelled")** -- outbound demand should never be prepared against a shipment still
--    in draft, since a draft shipment's own aggregate basis_quantity/weight/volume are
--    not yet authoritative. Duplicate-source prevention is the identical real partial
--    unique index shape `ATW-012` established: at most one non-cancelled outbound order
--    per `(tenant_id, source_shipment_order_id)`, and per `(tenant_id, idempotency_key)`
--    for manual sources -- a cancelled order frees its own source/key for a fresh
--    attempt, never permanently exhausts it.
-- 5. **A bounded, disclosed alternative to the full Configurable Numbering Engine
--    (`PLT-125`)** -- `app.wms_outbound_order_number_counters` + `app.next_wms_
--    outbound_order_number`, the identical per-tenant monotonic-counter shape `app.
--    next_wms_inbound_order_number` (`ATW-012`) already established, reused rather than
--    a fourth bespoke mechanism.
-- 6. **Line items snapshot `lot_controlled`/`serial_controlled`/`expiry_controlled`
--    from `app.item_masters` at add-time**, the identical "governed snapshot, never
--    silently re-derived" precedent `ATW-012`'s own `app.wms_inbound_order_lines`
--    already established -- Picking (`ATW-017`, the next checkpoint) needs these
--    snapshots to know which lines require lot/serial/expiry-aware allocation, without
--    joining live back to `app.item_masters`. Lines carry only `requested_quantity` --
--    never an allocated/reserved/picked quantity column, since allocation/reservation
--    against inventory is explicitly Picking's own job (Scope decisions, task brief), not
--    this checkpoint's.
-- 7. **`app.confirm_wms_outbound_order` re-validates full readiness rather than trusting
--    a stale prior check** (mirrors `app.confirm_wms_inbound` exactly), and additionally
--    re-checks that a shipment-order-sourced order's own source shipment order is STILL
--    `confirmed` at confirm time, not merely at prepare time -- `app.wms_outbound_
--    readiness.source_shipment_valid` makes this explicit and inspectable before
--    confirming, the identical "readiness preview matches exactly what confirm itself
--    blocks on" shape `ATW-012`'s own `app.get_wms_inbound_readiness` already
--    established. This is a genuinely new validation `ATW-012` itself does not need
--    (an inbound order has no analogous "still valid at confirm time" upstream
--    source-order state to re-check).
-- 8. **`app.cancel_wms_outbound_order` does NOT check for any downstream-progress guard
--    (e.g. an in-progress pick/pack) -- deliberately, and for a different reason than
--    `ATW-012`'s own identical-looking omission.** `ATW-012`'s own `app.cancel_wms_
--    inbound` omitted a receiving-progress guard because no receiving-progress table
--    existed yet AT ALL at that checkpoint (later widened by `ATW-013` once WMS Receiving
--    went live). Here, Picking (`ATW-017`) does not exist as a live capability yet EITHER
--    -- there is genuinely nothing yet that could reference a confirmed outbound order,
--    so there is no guard to omit or defer; a future Picking checkpoint (`ATW-017`) is
--    the one obligated to widen this cancel RPC itself once it exists, exactly mirroring
--    how `ATW-013` widened `ATW-012`'s own cancel RPC once WMS Receiving went live.
-- 9. **Two known-bug-class fixes applied proactively, beyond what `ATW-012`'s own
--    (earlier, not-yet-hardened) migration literally does** -- since this checkpoint is
--    authored after `ATW-013`/`ATW-014`/`ATW-016` already established these lessons the
--    hard way:
--    (a) `app.prepare_wms_outbound_from_shipment`/`app.create_manual_wms_outbound_order`
--        wrap their own INSERT in a nested `begin/exception` block catching
--        `unique_violation`, re-selecting and returning the winning row -- `ATW-012`'s
--        own `prepare_wms_inbound_from_shipment`/`create_manual_wms_inbound` do NOT do
--        this (a genuine, if narrow, race window between the pre-check `select` and the
--        `insert`), the identical create-once-idempotency race lesson `app.register_
--        lot_identity`/`app.register_serial_identity` (`ATW-016`) already fixed.
--    (b) `app.add_wms_outbound_order_line` locks the header row (`select ... for
--        update`) BEFORE computing `coalesce(max(line_number), 0) + 1` and before its
--        own status='draft' check, serializing concurrent add-line calls against the
--        SAME order -- `ATW-012`'s own `app.add_wms_inbound_order_line` does not lock
--        the header at all, leaving both the line-number computation and the
--        status-still-draft check exposed to the identical CROSS-ROW AGGREGATE race
--        `ATW-016`'s own header design lesson (e) names explicitly. `app.update_wms_
--        outbound_order_line`/`app.remove_wms_outbound_order_line`/`app.confirm_wms_
--        outbound_order`/`app.cancel_wms_outbound_order` all likewise lock the header
--        (and, for line mutations, the line row too) on first read, held through the
--        final `UPDATE`/`DELETE`, with `record_version` compared under that same lock.
-- 10. **Owner-account read scoping (the sixth `ATW-016` lesson) is applied to every
--     read RPC below** -- `app.wms_outbound_orders`/`app.wms_outbound_order_lines` are
--     owner-account-specific (`owner_account_id`), so `app.get_wms_outbound_order`/
--     `app.list_wms_outbound_orders`/`app.list_wms_outbound_order_lines`/`app.get_wms_
--     outbound_readiness` all call `app.actor_can_view_owner_scoped_row` (`ATW-016`,
--     reused directly, never re-derived) IN ADDITION TO the tenant-wide RBAC (`OPS:View`)
--     and warehouse-record-scope (`app.can_access_record`) checks `ATW-012`'s own reads
--     already perform. RLS SELECT policies on both new tables carry the identical
--     predicate, not just tenant/warehouse scope. Every `app.can_access_record` call
--     below (mutation and read alike) also passes the order's own `owner_account_id`
--     (as text) into `p_customer_account_ref` -- `app.can_access_record`'s own 5th
--     parameter, the exact mechanism `app.get_lot_trace`/`app.get_serial_trace`
--     (`ATW-016`) already established for letting a `customer_user`-layer actor with no
--     `org_unit_id` membership at all still pass the record-scope check on their own
--     owner's row. `ATW-012`'s own calls pass `null` here (predating owner-scoping
--     entirely); this migration does not repeat that gap, since a customer_user actor
--     scoped only by `app.actor_can_view_owner_scoped_row` would otherwise be rejected
--     by `app.can_access_record` first regardless, making the owner-scope check below it
--     unreachable for exactly the actor class it exists to admit.
-- 11. **No UI route, no REST/GraphQL surface, no dock/load/ship-confirm** -- matches
--     every prior WMS checkpoint's own disclosed "read surface first" precedent, and
--     Scope decisions in the task brief.
-- 12. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON ALL
--     FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Numbering (design note 5).
create table app.wms_outbound_order_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.wms_outbound_order_number_counters is
  'ATW-016A: one atomic, tenant-scoped monotonic counter for app.next_wms_outbound_order_number() -- a bounded, disclosed alternative to the full Configurable Numbering Engine (PLT-125), mirroring app.wms_inbound_order_number_counters (ATW-012) exactly.';

create function app.next_wms_outbound_order_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.wms_outbound_order_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.wms_outbound_order_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'WMSOUT-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

-- 2. Outbound order header (design notes 1-4).
create table app.wms_outbound_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  owner_account_id uuid not null references app.accounts (id),
  outbound_number text not null,
  source_type text not null,
  source_shipment_order_id uuid references app.shipment_orders (id),
  source_reason text,
  idempotency_key text,
  requested_ship_date date,
  status text not null default 'draft',
  cancelled_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_outbound_orders_number_unique unique (tenant_id, outbound_number),
  constraint wms_outbound_orders_source_type_check check (source_type in ('shipment_order', 'manual')),
  constraint wms_outbound_orders_status_check check (status in ('draft', 'confirmed', 'cancelled')),
  constraint wms_outbound_orders_source_shipment_shape_check check (
    (source_type = 'shipment_order' and source_shipment_order_id is not null)
    or (source_type <> 'shipment_order' and source_shipment_order_id is null)
  ),
  constraint wms_outbound_orders_manual_reason_check check (source_type <> 'manual' or (source_reason is not null and length(trim(source_reason)) > 0)),
  constraint wms_outbound_orders_cancelled_reason_check check (status <> 'cancelled' or (cancelled_reason is not null and length(trim(cancelled_reason)) > 0))
);

comment on table app.wms_outbound_orders is
  'ATW-016A: canonical warehouse outbound (demand) order header -- the "confirmed outbound demand contract" Prompt 236 (WMS Picking, ATW-017) section 9 names as its own upstream. owner_account_id/source_type/source_shipment_order_id/idempotency_key are immutable once created (no RPC below ever changes them). Lifecycle is bounded to draft -> confirmed (or cancelled from either) -- design note 1, no dock/staging/load/ship state; Prompt 238 (ATW-019) owns whatever state a confirmed outbound order transitions into once physical staging/load/ship begins. Carries no allocated/picked/packed quantity column (design note 6) -- ATW-017/ATW-018 own those.';

create unique index wms_outbound_orders_source_shipment_unique on app.wms_outbound_orders (tenant_id, source_shipment_order_id) where source_type = 'shipment_order' and status <> 'cancelled';
create unique index wms_outbound_orders_idempotency_unique on app.wms_outbound_orders (tenant_id, idempotency_key) where idempotency_key is not null and status <> 'cancelled';
create index wms_outbound_orders_tenant_warehouse_status_idx on app.wms_outbound_orders (tenant_id, warehouse_id, status);
create index wms_outbound_orders_tenant_owner_idx on app.wms_outbound_orders (tenant_id, owner_account_id);

create function app.touch_wms_outbound_orders_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_outbound_orders_touch_row
  before update on app.wms_outbound_orders
  for each row
  execute function app.touch_wms_outbound_orders_row();

-- 3. Outbound order lines (design note 6).
create table app.wms_outbound_order_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  outbound_order_id uuid not null references app.wms_outbound_orders (id),
  line_number integer not null,
  item_master_id uuid not null references app.item_masters (id),
  requested_uom_code text not null references app.uoms (code),
  requested_quantity numeric not null,
  lot_controlled boolean not null default false,
  serial_controlled boolean not null default false,
  expiry_controlled boolean not null default false,
  notes text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_outbound_order_lines_number_unique unique (outbound_order_id, line_number),
  constraint wms_outbound_order_lines_quantity_check check (requested_quantity > 0)
);

comment on table app.wms_outbound_order_lines is
  'ATW-016A: item_master_id/requested_uom_code are immutable once created; lot_controlled/serial_controlled/expiry_controlled are a governed snapshot of app.item_masters at add-time (design note 6, mirrors app.wms_inbound_order_lines exactly), never live-recomputed -- Picking (ATW-017) reads these to know which lines require lot/serial/expiry-aware allocation. requested_quantity only -- never an allocated/reserved/picked column (Picking''s own job).';

create index wms_outbound_order_lines_order_idx on app.wms_outbound_order_lines (outbound_order_id);

create function app.touch_wms_outbound_order_lines_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_outbound_order_lines_touch_row
  before update on app.wms_outbound_order_lines
  for each row
  execute function app.touch_wms_outbound_order_lines_row();

-- 4. Readiness preview composite type (mirrors app.wms_inbound_readiness's own
-- preview-matches-what-the-mutation-blocks-on shape, ATW-012), plus design note 7's own
-- new source_shipment_valid field.
create type app.wms_outbound_readiness as (
  has_lines boolean,
  warehouse_active boolean,
  owner_active boolean,
  source_shipment_valid boolean,
  invalid_line_count integer,
  ready boolean
);

-- 5. Mutations. Every mutation is RBAC-gated (OPS:Create/Edit) and record-scope-gated
-- (app.can_access_record against the order's own warehouse's company org unit, design
-- note 2), and audited. Row locks per design note 9(b): the header (and, for line
-- mutations, the line row too) is locked on first read, held through the final
-- UPDATE/DELETE, with record_version compared under that same lock.

create function app.prepare_wms_outbound_from_shipment(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_warehouse_id uuid,
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
  v_shipment app.shipment_orders;
  v_warehouse app.warehouses;
  v_existing app.wms_outbound_orders;
  v_order app.wms_outbound_orders;
  v_number text;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'shipment_order_not_found: % is not a shipment order of tenant %', p_shipment_order_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status <> 'confirmed' then
    raise exception 'source_not_confirmed: shipment order % is % (must be confirmed) -- design note 4', p_shipment_order_id, v_shipment.status using errcode = 'check_violation';
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
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_shipment.shipper_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot create an outbound order under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (design lesson a).
  select * into v_existing from app.wms_outbound_orders
    where tenant_id = p_tenant_id and source_type = 'shipment_order' and source_shipment_order_id = p_shipment_order_id and status <> 'cancelled';
  if found then
    return v_existing;
  end if;

  v_number := app.next_wms_outbound_order_number(p_tenant_id);

  -- Design note 9(a): a nested begin/exception unique_violation recovery -- a genuine
  -- race between the select above and this insert (two concurrent callers both prepare
  -- from the same shipment order) is resolved by re-selecting and returning the winner,
  -- never a raised error on a legitimate concurrent retry.
  begin
    insert into app.wms_outbound_orders (
      tenant_id, warehouse_id, owner_account_id, outbound_number, source_type, source_shipment_order_id, created_by
    ) values (
      p_tenant_id, p_warehouse_id, v_shipment.shipper_account_id, v_number, 'shipment_order', p_shipment_order_id, p_actor_label
    )
    returning * into v_order;
  exception
    when unique_violation then
      select * into v_existing from app.wms_outbound_orders
        where tenant_id = p_tenant_id and source_type = 'shipment_order' and source_shipment_order_id = p_shipment_order_id and status <> 'cancelled';
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_wms_outbound_from_shipment',
    'app.wms_outbound_orders', v_order.id, 'success', null, null,
    jsonb_build_object('source_shipment_order_id', p_shipment_order_id, 'warehouse_id', p_warehouse_id, 'outbound_number', v_number)
  );

  return v_order;
end;
$$;

comment on function app.prepare_wms_outbound_from_shipment is
  'ATW-016A: idempotent on (tenant_id, source_shipment_order_id) among non-cancelled rows, including under a genuine race (design note 9a). owner_account_id is inherited from the shipment order''s own shipper_account_id. Requires the source shipment order''s own status = confirmed (design note 4), stricter than app.prepare_wms_inbound_from_shipment''s own "not cancelled" check.';

create function app.create_manual_wms_outbound_order(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_owner_account_id uuid,
  p_source_reason text,
  p_idempotency_key text,
  p_requested_ship_date date,
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
  v_warehouse app.warehouses;
  v_account app.accounts;
  v_existing app.wms_outbound_orders;
  v_order app.wms_outbound_orders;
  v_number text;
begin
  if p_source_reason is null or length(trim(p_source_reason)) = 0 then
    raise exception 'invalid_reason: a source reason is required for a manual outbound order' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required for a manual outbound order' using errcode = 'check_violation';
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
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), p_owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot create an outbound order under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (design lesson a).
  select * into v_existing from app.wms_outbound_orders
    where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key and status <> 'cancelled';
  if found then
    return v_existing;
  end if;

  v_number := app.next_wms_outbound_order_number(p_tenant_id);

  -- Design note 9(a): nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_outbound_orders (
      tenant_id, warehouse_id, owner_account_id, outbound_number, source_type, source_reason, idempotency_key, requested_ship_date, created_by
    ) values (
      p_tenant_id, p_warehouse_id, p_owner_account_id, v_number, 'manual', p_source_reason, p_idempotency_key, p_requested_ship_date, p_actor_label
    )
    returning * into v_order;
  exception
    when unique_violation then
      select * into v_existing from app.wms_outbound_orders
        where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key and status <> 'cancelled';
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_manual_wms_outbound_order',
    'app.wms_outbound_orders', v_order.id, 'success', p_source_reason, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'owner_account_id', p_owner_account_id, 'outbound_number', v_number)
  );

  return v_order;
end;
$$;

comment on function app.create_manual_wms_outbound_order is
  'ATW-016A: the governed manual-entry exception path -- requires a non-empty source_reason. Idempotent on (tenant_id, idempotency_key) among non-cancelled rows, including under a genuine race (design note 9a).';

create function app.add_wms_outbound_order_line(
  p_outbound_order_id uuid,
  p_item_master_id uuid,
  p_requested_uom_code text,
  p_requested_quantity numeric,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_order_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
$$;

comment on function app.add_wms_outbound_order_line is
  'ATW-016A: only while the header is draft. item_master_id must be an active item owned by the same account as the outbound order -- rejects a foreign-owner item rather than silently accepting it. line_number auto-assigns sequentially under the header row lock (design note 9b).';

create function app.add_wms_outbound_order_lines(
  p_outbound_order_id uuid,
  p_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.wms_outbound_order_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_line_input jsonb;
  v_line app.wms_outbound_order_lines;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'invalid_lines: p_lines must be a non-empty JSON array' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(p_lines) > 200 then
    raise exception 'too_many_lines: at most 200 lines per bulk-add call, got %', jsonb_array_length(p_lines) using errcode = 'check_violation';
  end if;

  for v_line_input in select * from jsonb_array_elements(p_lines) loop
    v_line := app.add_wms_outbound_order_line(
      p_outbound_order_id,
      (v_line_input ->> 'item_master_id')::uuid,
      v_line_input ->> 'requested_uom_code',
      (v_line_input ->> 'requested_quantity')::numeric,
      v_line_input ->> 'notes',
      p_actor_auth_user_id,
      p_actor_label
    );
    return next v_line;
  end loop;

  return;
end;
$$;

comment on function app.add_wms_outbound_order_lines is
  'ATW-016A: the bounded bulk-add alt flow (mirrors app.add_wms_inbound_order_lines, ATW-012) -- a direct bulk RPC, not the full generic Import/Export Job Framework (PLT-131), covering the bounded "import many lines" need without a third source_type (design note 3). Each element reuses app.add_wms_outbound_order_line verbatim (identical validation and locking, no duplicated logic); a bad element aborts the whole call (all-or-nothing), never a partial import.';

create function app.update_wms_outbound_order_line(
  p_line_id uuid,
  p_requested_quantity numeric,
  p_notes text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_order_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
$$;

comment on function app.update_wms_outbound_order_line is
  'ATW-016A: mutable fields only -- item_master_id/requested_uom_code/control-flag snapshots are immutable once created. Optimistic-concurrency gated (record_version), compared under the row lock (design note 9b). Only while the header is draft.';

create function app.remove_wms_outbound_order_line(
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
  v_line app.wms_outbound_order_lines;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_line from app.wms_outbound_order_lines where id = p_line_id for update;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_order from app.wms_outbound_orders where id = v_line.outbound_order_id for update;
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
$$;

comment on function app.remove_wms_outbound_order_line is
  'ATW-016A: only while the header is draft. Optimistic-concurrency gated, compared under the row lock (design note 9b).';

-- 6. Reads. Owner-account scoping (design note 10) applied to every read below, IN
-- ADDITION TO tenant-wide RBAC (OPS:View) and warehouse-record-scope.

create function app.get_wms_outbound_readiness(p_outbound_order_id uuid, p_actor_auth_user_id uuid)
returns app.wms_outbound_readiness
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.get_wms_outbound_readiness is
  'ATW-016A: read-only preview of exactly what app.confirm_wms_outbound_order itself will block on (mirrors app.get_wms_inbound_readiness, ATW-012), plus design note 7''s own source_shipment_valid -- false if the source shipment order (when source_type = shipment_order) is no longer confirmed.';

create function app.confirm_wms_outbound_order(
  p_outbound_order_id uuid,
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
  v_readiness app.wms_outbound_readiness;
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
$$;

comment on function app.confirm_wms_outbound_order is
  'ATW-016A: draft -> confirmed only, re-validates full readiness (app.get_wms_outbound_readiness), including that a shipment-order-sourced order''s own source shipment order is STILL confirmed at confirm time (design note 7), not merely at prepare time. A confirmed outbound order is exactly the "confirmed outbound demand contract" Prompt 236 (WMS Picking, ATW-017) section 9 names as its own upstream.';

create function app.cancel_wms_outbound_order(
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

  -- Idempotent no-op -- only after authority/version are confirmed above, never before
  -- (design lesson a).
  if v_order.status = 'cancelled' then
    return v_order;
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
  'ATW-016A: does not check for any downstream (pick/pack) progress guard -- deliberately, since Picking (ATW-017) does not exist as a live capability yet at this checkpoint, so there is nothing yet that could reference a confirmed outbound order (design note 8, a different reason than app.cancel_wms_inbound''s identical-looking omission). ATW-017, once live, is obligated to widen this cancel RPC itself, exactly mirroring how ATW-013 widened ATW-012''s own cancel RPC.';

create function app.get_wms_outbound_order(p_outbound_order_id uuid, p_actor_auth_user_id uuid)
returns app.wms_outbound_orders
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id;
  if not found then
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
$$;

comment on function app.get_wms_outbound_order is
  'ATW-016A: owner-account read scoping (design note 10) applied in addition to tenant-wide OPS:View and warehouse-record-scope.';

create function app.list_wms_outbound_order_lines(p_outbound_order_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_outbound_order_lines
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_order app.wms_outbound_orders;
begin
  v_order := app.get_wms_outbound_order(p_outbound_order_id, p_actor_auth_user_id);

  return query
  select * from app.wms_outbound_order_lines where outbound_order_id = p_outbound_order_id order by line_number;
end;
$$;

comment on function app.list_wms_outbound_order_lines is
  'ATW-016A: reuses app.get_wms_outbound_order for its own authority/record-scope/owner-scope gate rather than duplicating the checks.';

create function app.list_wms_outbound_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.wms_outbound_orders
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
  select o.* from app.wms_outbound_orders o
  join app.warehouses w on w.id = o.warehouse_id
  where o.tenant_id = p_tenant_id
    and (p_warehouse_id is null or o.warehouse_id = p_warehouse_id)
    and (p_owner_account_id is null or o.owner_account_id = p_owner_account_id)
    and (p_status_filter is null or o.status = p_status_filter)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), o.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, o.owner_account_id)
  order by o.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_outbound_orders is
  'ATW-016A: bounded read (p_limit default 50, hard-capped 200), record-scoped per row by the order''s own warehouse company org unit AND owner-account-scoped (design note 10) -- not tenant-wide.';

-- 7. RLS -- record scope AND owner scope enforced in the database (design note 10), not
-- UI-only.

alter table app.wms_outbound_orders enable row level security;

create policy wms_outbound_orders_select_scoped on app.wms_outbound_orders
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = wms_outbound_orders.warehouse_id
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), wms_outbound_orders.owner_account_id::text)
    )
    and app.actor_can_view_owner_scoped_row((select auth.uid()), wms_outbound_orders.tenant_id, wms_outbound_orders.owner_account_id)
  );

alter table app.wms_outbound_order_lines enable row level security;

create policy wms_outbound_order_lines_select_scoped on app.wms_outbound_order_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_outbound_orders o
      join app.warehouses w on w.id = o.warehouse_id
      where o.id = wms_outbound_order_lines.outbound_order_id
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), o.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), o.tenant_id, o.owner_account_id)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.wms_outbound_orders, app.wms_outbound_order_lines to authenticated, service_role;
grant insert, update, delete on app.wms_outbound_orders, app.wms_outbound_order_lines to service_role;
grant insert, update on app.wms_outbound_order_number_counters to service_role;

grant execute on function app.next_wms_outbound_order_number(uuid) to service_role;
grant execute on function app.prepare_wms_outbound_from_shipment(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.create_manual_wms_outbound_order(uuid, uuid, uuid, text, text, date, uuid, text) to authenticated, service_role;
grant execute on function app.add_wms_outbound_order_line(uuid, uuid, text, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_wms_outbound_order_lines(uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.update_wms_outbound_order_line(uuid, numeric, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.remove_wms_outbound_order_line(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_outbound_readiness(uuid, uuid) to authenticated, service_role;
grant execute on function app.confirm_wms_outbound_order(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_wms_outbound_order(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_outbound_order(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_outbound_order_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_outbound_orders(uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
