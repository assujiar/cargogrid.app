-- Advanced TMS/WMS capability ATW-019 (CG-S10-ATW-019, Prompt 238, "WMS Outbound" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). This is the FINAL
-- checkpoint in the operator's own explicit 231-238 range for this session.
--
-- SCOPE NARROWING (disclosed, mirrors the ATW-016A precedent exactly, in reverse):
-- Prompt 238 §13 database impact names, as one undifferentiated scope, "outbound
-- root/version/number, customer owner/source order/shipment, lines/UOM, allocation/
-- pick/pack references, staging/dock/load/custody, canonical lifecycle, idempotent
-- ship-confirm inventory movements and billing-event eligibility." The FIRST clause
-- ("outbound root/version/number, customer owner/source order/shipment, lines/UOM")
-- was already built as an inserted checkpoint, ATW-016A (`app.wms_outbound_orders`/
-- `app.wms_outbound_order_lines`, supabase/migrations/
-- 20260730230000_create_advanced_tms_wms_outbound_order.sql), specifically to resolve
-- ISS-2026-011 Part 2 (a real circular dependency: Picking, ATW-017, needed a real
-- "confirmed outbound demand contract" that did not otherwise exist). THIS migration
-- builds only the REMAINDER: allocation/pick/pack REFERENCES (never re-derived
-- allocation itself -- that stays ATW-017/018's own job), staging/dock/load/custody, the
-- canonical SHIP-EXECUTION lifecycle, idempotent ship-confirm inventory movements, and
-- billing-event eligibility. `app.wms_outbound_orders`/`app.wms_outbound_order_lines`
-- and their own draft/confirmed/cancelled lifecycle are consumed as a fixed, external
-- upstream contract here -- never edited, never re-litigated. A CONFIRMED outbound
-- order (and its own confirmed lines) is this migration's own real demand/source input,
-- exactly as Picking (ATW-017) already treats it.
--
-- Direct upstream: ATW-015 (Inventory Ledger -- app.post_inventory_movement, composed
-- directly; app.consume_inventory_reservation is deliberately NEVER called here, see
-- design note 1 below, a genuine correction of this checkpoint's own original task
-- brief), ATW-016A (WMS Outbound Order -- the demand/source contract), ATW-017 (WMS
-- Picking -- app.wms_pick_tasks.reservation_id/actual_destination_location_id, read
-- only, never mutated; app.wms_pick_record_scope_ok, reused directly a third time),
-- ATW-018 (WMS Packing -- app.wms_packages/app.wms_package_lines, a CONFIRMED package
-- is this migration's own real "pack" input; app.reopen_wms_package is widened, design
-- note 8).
--
-- Design boundary (disclosed):
--
-- 1. **`app.consume_inventory_reservation` (ATW-015) is deliberately NEVER called by
--    this migration -- a genuine, load-bearing correction of this checkpoint's own
--    original task brief, which assumed it was the right terminal-issue mechanism.**
--    Direct inspection of ATW-017's own already-applied `app.confirm_wms_pick_task`
--    (design notes 4/5 of that migration's own header) shows that once a pick task's
--    own `remaining_quantity` reaches zero (fully picked, fully short, or a mix), ATW-017
--    performs a RAW `UPDATE app.inventory_reservations SET status = 'released', ...`
--    against that task's own `reservation_id` -- NOT `'consumed'`, and NOT via
--    `app.consume_inventory_reservation`/`app.release_inventory_reservation`, both of
--    which assume a one-shot full-amount transition incompatible with ATW-017's own
--    incremental per-confirm-event decrement of `app.inventory_balances.reserved`. By
--    the time a picked/packed line reaches this migration, its own backing
--    `app.inventory_reservations` row is therefore already `status = 'released'` in the
--    overwhelmingly normal case (a fully resolved pick task) -- calling `app.
--    consume_inventory_reservation` on it would hit that function's own `invalid_
--    transition` guard (`status <> 'active'`) and hard-fail every ordinary ship-confirm.
--    Worse, for the rarer case of a still-`'partial'` task (reservation still `'active'`),
--    `app.consume_inventory_reservation` posts a negative movement for the
--    reservation's own ORIGINAL, never-mutated `reserved_quantity` (ATW-015's own
--    design, "reserved_quantity ... stays exactly as originally set") against the
--    reservation's own ORIGINAL `balance_id` (the SOURCE rack location) -- both wrong
--    for a partially-picked task: it would over-consume (the full original demand, not
--    merely what was actually picked/packed/loaded) at the wrong location (the source
--    rack, not wherever the picked stock has actually physically moved to). Calling it
--    here would therefore be a real correctness defect, not merely a style deviation.
--    Instead, this migration posts a REAL, DIRECT `app.post_inventory_movement`
--    (`movement_type = 'consumption'`) at `app.ship_confirm_wms_outbound_shipment`
--    (design note 4), built set-based from the EXACT `app.wms_package_lines` rows
--    actually included in the shipment being confirmed -- the precise, already-verified
--    packed quantity, at the precise physical location that quantity now sits at
--    (`app.wms_outbound_shipments.dock_location_id`, moved there by this migration's
--    own real `app.load_wms_outbound_shipment` transfer, design note 3). Traceability
--    back to the original pick-task reservation (the task brief's own explicit
--    requirement) is preserved via a dedicated, append-only `app.wms_shipment_
--    issue_lines` evidence table (one row per issued package line, carrying both
--    `pick_task_id` and `reservation_id`) rather than via a consume-reservation call
--    this data model no longer supports at this stage of the pipeline.
-- 2. **The ship-execution entity is a separate table, `app.wms_outbound_shipments`, one
--    row per ship-execution attempt (`staging` -> `loaded` -> `shipped`, or `cancelled`
--    from `staging`), referencing `outbound_order_id` -- never a widening of `app.
--    wms_outbound_orders`' own closed `draft`/`confirmed`/`cancelled` CHECK.** Mirrors
--    how ATW-014/017/018 each added their own task-level table referencing an upstream
--    header rather than mutating the upstream's own status column. Chosen over
--    widening because (a) the task brief's own scope narrowing explicitly forbids
--    re-litigating `app.wms_outbound_orders`' own lifecycle, and (b) an order may
--    legitimately ship in SEVERAL separate shipments over time under partial
--    fulfillment/backorder policy (§22) -- a real one-to-many relationship a single
--    status column on the order header could never represent. `app.wms_outbound_orders.
--    status` is therefore never written by this migration at all.
-- 3. **Staging performs NO physical relocation; loading does -- a disclosed, physically-
--    reasoned split of the two options the task brief itself named.** By the time a
--    package is `confirmed` (ATW-018), its own contents already physically sit at
--    whichever `location_type = 'staging'` destination ATW-017's own `app.confirm_wms_
--    pick_task` moved them to (that migration's own design note 10) -- re-modeling a
--    transfer AT the "stage" step would be a redundant, physically-fictional second
--    movement of stock that never actually moved again. `app.load_wms_outbound_
--    shipment` is instead the first genuinely NEW physical relocation this capability
--    introduces: a real `app.post_inventory_movement` (`movement_type = 'transfer'`)
--    from each package line's own source (`app.wms_pick_tasks.actual_destination_
--    location_id`) to a real, validated `location_type = 'dock'` location
--    (`app.wms_outbound_shipments.dock_location_id`) -- mirroring Putaway's own real
--    transfer-movement precedent, attached at the transition point where a real
--    relocation actually, physically happens.
-- 4. **`app.ship_confirm_wms_outbound_shipment` is the one, atomic, idempotent terminal
--    step -- ship confirmation, the custody event and the inventory issue all commit
--    together inside ONE PL/pgSQL function invocation (one Postgres transaction), gated
--    by ONE `(tenant_id, idempotency_key)`** (§24's own business rule, verbatim). Custody
--    evidence (`p_custody_confirmed_by_label`/`p_custody_confirmed_reason`) is captured
--    as direct parameters of this same call, never a separate earlier RPC/idempotency
--    key -- avoiding exactly the "custody recorded but issue never followed, or vice
--    versa" split-brain window a two-call design would risk. **How a partially-issued
--    shipment is structurally prevented, even if one line's own consumption logic were
--    to fail partway through (the task brief's own required disclosure):** every line
--    to be issued is compiled into ONE single `app.post_inventory_movement` call (design
--    note 1) -- that function's own per-line loop already runs inside ITS OWN single
--    transaction context (this function's own enclosing transaction, since PL/pgSQL
--    functions do not open a nested transaction), so a failure on any one line (e.g.
--    `insufficient_stock`) raises an exception that unwinds EVERY line already
--    processed THIS call, the confirmation-evidence insert, the billing-eligibility
--    event insert and the shipment's own status UPDATE together, atomically, leaving
--    `app.wms_outbound_shipments.status` unchanged at `'loaded'` and the shipment safely
--    retryable -- there is no per-reservation loop with its own partial-completion
--    window to reason about at all, which is in fact a structural improvement over the
--    original per-reservation-consume-call design the task brief proposed.
-- 5. **The double-ship-confirm race (bug class (e), this checkpoint's own headline
--    instance, the task brief's own explicit call-out): `app.ship_confirm_wms_
--    outbound_shipment` locks the shipment header row (`SELECT ... FOR UPDATE`) BEFORE
--    computing the partial-fulfillment aggregate (how many of the order's own confirmed
--    packages remain unshipped) and before checking `status = 'loaded'`.** Two
--    concurrent ship-confirm calls against the SAME shipment (even under two DIFFERENT
--    idempotency keys, a genuine double-submit, not merely a safe retry) therefore
--    serialize: the second blocks on the header lock until the first commits, then
--    observes the first's own real, committed `status = 'shipped'` and is cleanly
--    rejected `invalid_transition` -- inventory is issued exactly once, never twice.
--    `app.load_wms_outbound_shipment`/`app.add_package_to_shipment` apply the identical
--    header-or-shared-row-lock-before-aggregate discipline for their own narrower races
--    (double-load, double-stage of the same package into two shipments).
-- 6. **`app.reopen_wms_package` (ATW-018) is widened via a same-signature `CREATE OR
--    REPLACE`** -- the identical technique ATW-013 used on ATW-012's own cancel
--    function and ATW-017 used on ATW-016A's own `app.cancel_wms_outbound_order` --
--    adding exactly one new guard: a package already linked to ANY `app.wms_shipment_
--    packages` row (staged, loaded or shipped) may no longer be reopened, closing the
--    gap where a package's own contents could silently change after this capability has
--    already committed real ledger/traceability records against it. A package must be
--    explicitly REMOVED from its shipment (`app.remove_package_from_shipment`, only
--    while that shipment is still `staging`) before it becomes reopenable again --
--    disclosed, intentional, mirrors "confirmed package changes require governed
--    reopen... not silent edit" one level up the pipeline.
-- 7. **Custody/evidence is bounded to a real actor-label + timestamp + reason (no
--    file-upload/photo/signature pipeline), matching the task brief's own disclosed
--    scope decision** -- `custody_confirmed_by_label`/`custody_confirmed_reason`/
--    `custody_confirmed_at` columns on `app.wms_outbound_shipments`, captured only at
--    real ship-confirm (design note 4).
-- 8. **Partial fulfillment/backorder (§22) is real and package-count-reconciled, never
--    silent.** At ship-confirm, this migration counts the order's own total `confirmed`
--    packages versus how many are already covered by shipments that are `'shipped'` OR
--    are THIS shipment being confirmed now; if any remain uncovered, the caller MUST
--    pass `p_is_partial_fulfillment = true` plus a non-empty `p_partial_fulfillment_
--    reason`, or the call is rejected `partial_fulfillment_not_acknowledged` -- never a
--    silently accepted incomplete ship. The stored `is_partial_fulfillment` value is
--    always the computed truth, never the caller's own unverified claim.
-- 9. **The billing-eligibility event (`app.wms_billing_eligibility_events`) is a real,
--    standalone, auditable event row -- no existing `app.billing_event` table exists
--    anywhere in this repository (confirmed by direct grep) -- carrying tenant/
--    warehouse/owner_account_id/outbound_order_id/shipment_id, package_count,
--    line_count, total_quantity, a genuine `weight_by_uom` JSONB aggregate (summed PER
--    weight UOM code actually recorded on the shipped packages, deliberately never a
--    single collapsed total that would silently mix incompatible units), a real
--    `shipped_at` timestamp and its own `(tenant_id, idempotency_key)`.** §24's own "
--    warehouse billing eligibility is an event; invoice/journal posting remains
--    Finance-owned" is honored literally: this migration never writes to any Finance
--    schema/table, and computes only facts already established by this pipeline itself
--    (counts/quantities/weights already on `app.wms_packages`/`app.wms_package_lines`),
--    deliberately leaving rate/currency/pricing entirely to the future Finance-domain
--    consumer.
-- 10. **Six known bug classes, applied proactively (this session's established
--     taxonomy; this is the seventh application):**
--     (a) every idempotent-replay short-circuit below runs strictly after authority/
--         tenant-scope confirmation, never before;
--     (b)/(c) `SELECT ... FOR UPDATE` on the first read of any row a mutation will
--         update, held through the final `UPDATE`/`INSERT`, `record_version` compared
--         only under that lock -- every shipment mutation below;
--     (d) every create-once `(tenant_id, idempotency_key)` INSERT below (`app.
--         create_wms_outbound_shipment`, `app.add_package_to_shipment`'s own membership
--         insert, `app.load_wms_outbound_shipment`'s own evidence insert, `app.ship_
--         confirm_wms_outbound_shipment`'s own confirmation AND billing-eligibility-event
--         inserts) is wrapped in a nested `begin/exception unique_violation` recovery;
--     (e) the cross-row-aggregate race -- design note 5, this checkpoint's own headline
--         instance (double-ship-confirm), PLUS a second instance in `app.add_package_
--         to_shipment` (locks the target `app.wms_packages` row before checking whether
--         it is already linked to any `app.wms_shipment_packages` row, preventing the
--         same package from being double-staged into two different shipments
--         concurrently). No hierarchical/tree-walking operation is introduced by this
--         migration at all (a package's own `parent_package_id` hierarchy, ATW-018, is
--         read-only here, never walked or mutated) -- deliberately avoiding inventing a
--         hierarchy this checkpoint's own bounded scope does not need;
--     (f) owner-account read scoping -- every read RPC below that returns shipment-
--         specific data calls `app.actor_can_view_owner_scoped_row` (`ATW-016`) IN
--         ADDITION to tenant-wide `OPS:View`/warehouse-record-scope, and every `app.
--         can_access_record` call below (mutation and read alike) passes the row's own
--         real `owner_account_id` (as text) into `p_customer_account_ref`, never `null`.
--         Every RLS SELECT policy below reuses `app.wms_pick_record_scope_ok` (`ATW-
--         017`) directly rather than nesting a raw, non-SECURITY-DEFINER subquery
--         against `app.warehouses` a fourth time.
-- 11. No UI route, no REST/GraphQL surface -- matches every prior WMS checkpoint's own
--     disclosed "read surface first" precedent, and the task brief's own scope
--     decisions.
-- 12. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Numbering (mirrors app.next_wms_outbound_order_number, ATW-016A, exactly).
create table app.wms_outbound_shipment_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

create function app.next_wms_outbound_shipment_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.wms_outbound_shipment_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.wms_outbound_shipment_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'WMSSHIP-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

-- 2. Ship-execution header (design notes 2/3/4/7/8).
create table app.wms_outbound_shipments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  outbound_order_id uuid not null references app.wms_outbound_orders (id),
  owner_account_id uuid not null references app.accounts (id),
  shipment_number text not null,
  idempotency_key text not null,
  status text not null default 'staging',
  dock_location_id uuid references app.warehouse_locations (id),
  vehicle_ref text,
  loaded_at timestamptz,
  loaded_by_auth_user_id uuid references auth.users (id),
  loaded_by_label text,
  load_movement_id uuid references app.inventory_movements (id),
  custody_confirmed_by_label text,
  custody_confirmed_reason text,
  custody_confirmed_at timestamptz,
  shipped_at timestamptz,
  shipped_by_auth_user_id uuid references auth.users (id),
  shipped_by_label text,
  consumption_movement_id uuid references app.inventory_movements (id),
  is_partial_fulfillment boolean not null default false,
  partial_fulfillment_reason text,
  cancelled_at timestamptz,
  cancelled_by_auth_user_id uuid references auth.users (id),
  cancelled_by_label text,
  cancelled_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_outbound_shipments_number_unique unique (tenant_id, shipment_number),
  constraint wms_outbound_shipments_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_outbound_shipments_status_check check (status in ('staging', 'loaded', 'shipped', 'cancelled')),
  constraint wms_outbound_shipments_loaded_shape_check check (
    status not in ('loaded', 'shipped')
    or (dock_location_id is not null and loaded_at is not null and load_movement_id is not null)
  ),
  constraint wms_outbound_shipments_shipped_shape_check check (
    status <> 'shipped'
    or (shipped_at is not null and consumption_movement_id is not null and custody_confirmed_at is not null and custody_confirmed_by_label is not null)
  ),
  constraint wms_outbound_shipments_cancelled_shape_check check (
    status <> 'cancelled' or (cancelled_at is not null and cancelled_reason is not null and length(trim(cancelled_reason)) > 0)
  ),
  constraint wms_outbound_shipments_partial_reason_check check (
    not is_partial_fulfillment or (partial_fulfillment_reason is not null and length(trim(partial_fulfillment_reason)) > 0)
  )
);

comment on table app.wms_outbound_shipments is
  'ATW-019: one row per ship-execution attempt against a confirmed app.wms_outbound_orders row (design note 2) -- staging -> loaded -> shipped, or cancelled from staging. Multiple shipments per order are allowed (partial fulfillment/backorder over time, design note 8). app.wms_outbound_orders.status is never written by this migration.';

create index wms_outbound_shipments_tenant_warehouse_status_idx on app.wms_outbound_shipments (tenant_id, warehouse_id, status);
create index wms_outbound_shipments_tenant_owner_idx on app.wms_outbound_shipments (tenant_id, owner_account_id);
create index wms_outbound_shipments_outbound_order_idx on app.wms_outbound_shipments (outbound_order_id);

create function app.touch_wms_outbound_shipments_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_outbound_shipments_touch_row
  before update on app.wms_outbound_shipments
  for each row
  execute function app.touch_wms_outbound_shipments_row();

-- 3. Shipment package membership (design note 5's own second bug-class-(e) instance).
create table app.wms_shipment_packages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_id uuid not null references app.wms_outbound_shipments (id),
  package_id uuid not null references app.wms_packages (id),
  idempotency_key text not null,
  added_at timestamptz not null default now(),
  added_by_auth_user_id uuid references auth.users (id),
  added_by_label text,
  constraint wms_shipment_packages_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_shipment_packages_package_unique unique (package_id)
);

comment on table app.wms_shipment_packages is
  'ATW-019: real membership -- a package may belong to at most one shipment at a time, EVER once that shipment reaches loaded/shipped (rows are only ever deleted while the owning shipment is still staging, via app.remove_package_from_shipment). This is also the guard app.reopen_wms_package (ATW-018, widened design note 6) checks before allowing a package to be reopened.';

create index wms_shipment_packages_shipment_idx on app.wms_shipment_packages (shipment_id);

-- 4. Load evidence (append-only, idempotent app.load_wms_outbound_shipment).
create table app.wms_shipment_load_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_id uuid not null references app.wms_outbound_shipments (id),
  idempotency_key text not null,
  dock_location_id uuid not null references app.warehouse_locations (id),
  vehicle_ref text,
  movement_id uuid not null references app.inventory_movements (id),
  package_count_snapshot integer not null,
  loaded_by_auth_user_id uuid references auth.users (id),
  loaded_by_label text,
  loaded_at timestamptz not null default now(),
  constraint wms_shipment_load_events_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

create index wms_shipment_load_events_shipment_idx on app.wms_shipment_load_events (shipment_id);

-- 5. Ship-confirm evidence (append-only, idempotent app.ship_confirm_wms_outbound_shipment).
create table app.wms_shipment_confirmations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_id uuid not null references app.wms_outbound_shipments (id),
  idempotency_key text not null,
  movement_id uuid not null references app.inventory_movements (id),
  package_count_snapshot integer not null,
  line_count_snapshot integer not null,
  total_quantity_snapshot numeric not null,
  is_partial_fulfillment boolean not null,
  custody_confirmed_by_label text not null,
  custody_confirmed_reason text not null,
  confirmed_by_auth_user_id uuid references auth.users (id),
  confirmed_by_label text,
  confirmed_at timestamptz not null default now(),
  constraint wms_shipment_confirmations_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

create index wms_shipment_confirmations_shipment_idx on app.wms_shipment_confirmations (shipment_id);

-- 6. Issue-line traceability (append-only -- design note 1's own replacement for a
-- consume-reservation call this data model no longer supports at this pipeline stage).
create table app.wms_shipment_issue_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_id uuid not null references app.wms_outbound_shipments (id),
  package_id uuid not null references app.wms_packages (id),
  package_line_id uuid not null references app.wms_package_lines (id),
  pick_task_id uuid not null references app.wms_pick_tasks (id),
  reservation_id uuid not null references app.inventory_reservations (id),
  item_master_id uuid not null references app.item_masters (id),
  owner_account_id uuid not null references app.accounts (id),
  uom_code text not null references app.uoms (code),
  lot_number text,
  serial_number text,
  expiry_date date,
  quantity numeric not null,
  movement_id uuid not null references app.inventory_movements (id),
  created_at timestamptz not null default now(),
  constraint wms_shipment_issue_lines_shipment_package_line_unique unique (shipment_id, package_line_id),
  constraint wms_shipment_issue_lines_quantity_check check (quantity > 0)
);

comment on table app.wms_shipment_issue_lines is
  'ATW-019: one append-only row per app.wms_package_lines row actually issued at ship-confirm -- the real traceability chain back to pick_task_id/reservation_id (design note 1) that this migration deliberately does NOT establish via app.consume_inventory_reservation.';

create index wms_shipment_issue_lines_shipment_idx on app.wms_shipment_issue_lines (shipment_id);
create index wms_shipment_issue_lines_pick_task_idx on app.wms_shipment_issue_lines (pick_task_id);

-- 7. Billing-eligibility event (design note 9) -- a real, standalone, auditable event;
-- no existing app.billing_event table exists anywhere in this repository. Never
-- consumed by, or written into, any Finance schema/table by this migration.
create table app.wms_billing_eligibility_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  owner_account_id uuid not null references app.accounts (id),
  outbound_order_id uuid not null references app.wms_outbound_orders (id),
  shipment_id uuid not null references app.wms_outbound_shipments (id),
  idempotency_key text not null,
  package_count integer not null,
  line_count integer not null,
  total_quantity numeric not null,
  weight_by_uom jsonb not null default '{}'::jsonb,
  shipped_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint wms_billing_eligibility_events_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_billing_eligibility_events_shipment_unique unique (shipment_id),
  constraint wms_billing_eligibility_events_package_count_check check (package_count > 0),
  constraint wms_billing_eligibility_events_line_count_check check (line_count > 0),
  constraint wms_billing_eligibility_events_total_quantity_check check (total_quantity > 0)
);

comment on table app.wms_billing_eligibility_events is
  'ATW-019: design note 9. weight_by_uom is a genuine per-weight-UOM-code JSONB aggregate (e.g. {"KG": 120.5}), deliberately never a single collapsed total that would silently mix incompatible units. A future Finance-domain capability is the only intended consumer -- this table is never written to by, nor writes to, any Finance invoice/journal table (section 24: "billing eligibility is an event; invoice/journal posting remains Finance-owned").';

create index wms_billing_eligibility_events_tenant_owner_idx on app.wms_billing_eligibility_events (tenant_id, owner_account_id);
create index wms_billing_eligibility_events_outbound_order_idx on app.wms_billing_eligibility_events (outbound_order_id);

-- 8. Mutations.

create function app.create_wms_outbound_shipment(
  p_outbound_order_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_shipments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.create_wms_outbound_shipment is
  'ATW-019: idempotent on (tenant_id, idempotency_key), including under a genuine race (bug class d). Multiple shipments per order are allowed (design note 2/8) -- no one-per-order guard, unlike app.start_wms_packing_task.';

create function app.add_package_to_shipment(
  p_shipment_id uuid,
  p_package_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_shipments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.add_package_to_shipment is
  'ATW-019: rejects package_not_confirmed/wrong_order/wrong_owner/package_already_staged. Idempotent on (tenant_id, idempotency_key). A package may belong to at most one shipment at a time (unique package_id, bug class e''s own second instance).';

create function app.remove_package_from_shipment(
  p_shipment_id uuid,
  p_package_id uuid,
  p_reason text,
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
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
  v_deleted integer;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to remove a package from a shipment' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id for update;
  if not found then
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
$$;

comment on function app.remove_package_from_shipment is
  'ATW-019: only while the shipment is staging. Frees the package (app.wms_shipment_packages_package_unique) for staging into a different shipment, and makes app.reopen_wms_package (design note 6) reachable again.';

create function app.set_wms_shipment_vehicle_ref(
  p_shipment_id uuid,
  p_vehicle_ref text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_shipments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
begin
  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id for update;
  if not found then
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
$$;

comment on function app.set_wms_shipment_vehicle_ref is
  'ATW-019: a plain, disclosed text/reference field (task brief scope decision) -- no live dispatch/capacity integration with ATW-227. Changeable while staging OR loaded (the alt-flow "change dock/vehicle before confirm", section 22), never once shipped/cancelled.';

create function app.set_wms_shipment_dock_location(
  p_shipment_id uuid,
  p_dock_location_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_shipments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
  v_location app.warehouse_locations;
begin
  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id for update;
  if not found then
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
$$;

comment on function app.set_wms_shipment_dock_location is
  'ATW-019: a real app.warehouse_locations FK (location_type = dock), distinct from the plain-text vehicle_ref field. Only settable/changeable while staging (design note 3) -- once app.load_wms_outbound_shipment posts its own real transfer, the dock is physically fixed.';

create function app.load_wms_outbound_shipment(
  p_shipment_id uuid,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_shipments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.load_wms_outbound_shipment is
  'ATW-019: the one and only path that ever posts a transfer movement for a shipment (design note 3). staging -> loaded only. Idempotent on (tenant_id, idempotency_key), including under a genuine race (bug class d).';

create function app.ship_confirm_wms_outbound_shipment(
  p_shipment_id uuid,
  p_custody_confirmed_by_label text,
  p_custody_confirmed_reason text,
  p_is_partial_fulfillment boolean,
  p_partial_fulfillment_reason text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_shipments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.ship_confirm_wms_outbound_shipment is
  'ATW-019: the atomic terminal step (design note 4) -- ship confirmation, custody event and inventory issue (a single batched consumption movement, design note 1) commit together in one transaction, idempotent on (tenant_id, idempotency_key). loaded -> shipped only; a genuine concurrent double-confirm (design note 5) is rejected invalid_transition once the first winner commits. Requires explicit p_is_partial_fulfillment acknowledgment (design note 8) whenever real confirmed packages of the order remain unshipped. Creates exactly one app.wms_billing_eligibility_events row.';

create function app.cancel_wms_outbound_shipment(
  p_shipment_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_outbound_shipments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
begin
  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id for update;
  if not found then
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
$$;

comment on function app.cancel_wms_outbound_shipment is
  'ATW-019: only while staging (before any real ledger movement has posted) -- frees every staged package (app.wms_shipment_packages rows deleted) for a future shipment attempt. A loaded shipment is not cancellable via this RPC (rollback/recovery note, section 32).';

-- 9. Widen app.reopen_wms_package (ATW-018) -- design note 6. Same-signature CREATE OR
-- REPLACE, the identical technique ATW-013 used on ATW-012's own cancel function and
-- ATW-017 used on ATW-016A's own app.cancel_wms_outbound_order. Every line below other
-- than the new guard (marked) is copied verbatim from the already-applied ATW-018
-- migration -- never edited in place there.
create or replace function app.reopen_wms_package(
  p_package_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
  if not found then
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
$$;

comment on function app.reopen_wms_package is
  'ATW-018, widened by ATW-019 (design note 6): OPS:Override-gated (supervisor-only). The ONLY path back from confirmed -- resets QC/seal, preserves packed line contents, records a full before/after audit event. ATW-019 adds package_staged_for_shipment: a package already linked to any app.wms_shipment_packages row may not be reopened until removed from its shipment.';

-- 10. Reads. Owner-account scoping (bug class f) applied to every read below, IN
-- ADDITION to tenant-wide RBAC (OPS:View) and warehouse-record-scope.

create function app.get_wms_outbound_shipment(p_shipment_id uuid, p_actor_auth_user_id uuid)
returns app.wms_outbound_shipments
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.wms_outbound_shipments;
  v_warehouse app.warehouses;
begin
  select * into v_shipment from app.wms_outbound_shipments where id = p_shipment_id;
  if not found then
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
$$;

comment on function app.get_wms_outbound_shipment is
  'ATW-019: owner-account read scoping (bug class f) applied in addition to tenant-wide OPS:View and warehouse-record-scope.';

create function app.list_wms_outbound_shipments(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_outbound_order_id uuid default null,
  p_warehouse_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.wms_outbound_shipments
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
  select s.* from app.wms_outbound_shipments s
  join app.warehouses w on w.id = s.warehouse_id
  where s.tenant_id = p_tenant_id
    and (p_outbound_order_id is null or s.outbound_order_id = p_outbound_order_id)
    and (p_warehouse_id is null or s.warehouse_id = p_warehouse_id)
    and (p_owner_account_id is null or s.owner_account_id = p_owner_account_id)
    and (p_status_filter is null or s.status = p_status_filter)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), s.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, s.owner_account_id)
  order by s.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_outbound_shipments is
  'ATW-019: bounded read (p_limit default 50, hard-capped 200), record-scoped per row by the shipment''s own warehouse company org unit AND owner-account-scoped (bug class f).';

create function app.list_wms_shipment_packages(p_shipment_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_shipment_packages
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_outbound_shipment(p_shipment_id, p_actor_auth_user_id);
  return query select * from app.wms_shipment_packages where shipment_id = p_shipment_id order by added_at;
end;
$$;

comment on function app.list_wms_shipment_packages is
  'ATW-019: reuses app.get_wms_outbound_shipment for its own authority/record-scope/owner-scope gate rather than duplicating the checks.';

create function app.list_wms_shipment_issue_lines(p_shipment_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_shipment_issue_lines
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_outbound_shipment(p_shipment_id, p_actor_auth_user_id);
  return query select * from app.wms_shipment_issue_lines where shipment_id = p_shipment_id order by created_at;
end;
$$;

comment on function app.list_wms_shipment_issue_lines is
  'ATW-019: the real traceability read (design note 1) -- one row per issued package line, carrying pick_task_id/reservation_id. Reuses app.get_wms_outbound_shipment for its own gate.';

create function app.get_wms_billing_eligibility_event(p_event_id uuid, p_actor_auth_user_id uuid)
returns app.wms_billing_eligibility_events
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.wms_billing_eligibility_events;
  v_warehouse app.warehouses;
begin
  select * into v_event from app.wms_billing_eligibility_events where id = p_event_id;
  if not found then
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
$$;

comment on function app.get_wms_billing_eligibility_event is
  'ATW-019: owner-account read scoping (bug class f) applied in addition to tenant-wide OPS:View and warehouse-record-scope. Staff-facing only (mirrors ATW-015''s own disclosed customer-projection boundary) -- a future Finance-domain capability is the intended real consumer.';

create function app.list_wms_billing_eligibility_events(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_outbound_order_id uuid default null,
  p_owner_account_id uuid default null,
  p_limit integer default 50
)
returns setof app.wms_billing_eligibility_events
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
  select e.* from app.wms_billing_eligibility_events e
  join app.warehouses w on w.id = e.warehouse_id
  where e.tenant_id = p_tenant_id
    and (p_outbound_order_id is null or e.outbound_order_id = p_outbound_order_id)
    and (p_owner_account_id is null or e.owner_account_id = p_owner_account_id)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), e.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, e.owner_account_id)
  order by e.shipped_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_billing_eligibility_events is
  'ATW-019: bounded read (p_limit default 50, hard-capped 200), record-scoped AND owner-account-scoped (bug class f).';

-- 11. RLS -- record scope AND owner scope enforced in the database (bug class f), not
-- UI-only. Reuses app.wms_pick_record_scope_ok (ATW-017) directly.

alter table app.wms_outbound_shipments enable row level security;

create policy wms_outbound_shipments_select_scoped on app.wms_outbound_shipments
  for select to authenticated
  using (
    app.wms_pick_record_scope_ok((select auth.uid()), wms_outbound_shipments.warehouse_id, wms_outbound_shipments.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row((select auth.uid()), wms_outbound_shipments.tenant_id, wms_outbound_shipments.owner_account_id)
  );

alter table app.wms_shipment_packages enable row level security;

create policy wms_shipment_packages_select_scoped on app.wms_shipment_packages
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_outbound_shipments s
      where s.id = wms_shipment_packages.shipment_id
        and app.wms_pick_record_scope_ok((select auth.uid()), s.warehouse_id, s.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), s.tenant_id, s.owner_account_id)
    )
  );

alter table app.wms_shipment_load_events enable row level security;

create policy wms_shipment_load_events_select_scoped on app.wms_shipment_load_events
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_outbound_shipments s
      where s.id = wms_shipment_load_events.shipment_id
        and app.wms_pick_record_scope_ok((select auth.uid()), s.warehouse_id, s.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), s.tenant_id, s.owner_account_id)
    )
  );

alter table app.wms_shipment_confirmations enable row level security;

create policy wms_shipment_confirmations_select_scoped on app.wms_shipment_confirmations
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_outbound_shipments s
      where s.id = wms_shipment_confirmations.shipment_id
        and app.wms_pick_record_scope_ok((select auth.uid()), s.warehouse_id, s.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), s.tenant_id, s.owner_account_id)
    )
  );

alter table app.wms_shipment_issue_lines enable row level security;

create policy wms_shipment_issue_lines_select_scoped on app.wms_shipment_issue_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_outbound_shipments s
      where s.id = wms_shipment_issue_lines.shipment_id
        and app.wms_pick_record_scope_ok((select auth.uid()), s.warehouse_id, s.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), s.tenant_id, s.owner_account_id)
    )
  );

alter table app.wms_billing_eligibility_events enable row level security;

create policy wms_billing_eligibility_events_select_scoped on app.wms_billing_eligibility_events
  for select to authenticated
  using (
    app.wms_pick_record_scope_ok((select auth.uid()), wms_billing_eligibility_events.warehouse_id, wms_billing_eligibility_events.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row((select auth.uid()), wms_billing_eligibility_events.tenant_id, wms_billing_eligibility_events.owner_account_id)
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.wms_outbound_shipments, app.wms_shipment_packages, app.wms_shipment_load_events, app.wms_shipment_confirmations, app.wms_shipment_issue_lines, app.wms_billing_eligibility_events to authenticated, service_role;
grant insert, update, delete on app.wms_outbound_shipments, app.wms_shipment_packages, app.wms_shipment_load_events, app.wms_shipment_confirmations, app.wms_shipment_issue_lines, app.wms_billing_eligibility_events to service_role;
grant insert, update on app.wms_outbound_shipment_number_counters to service_role;

grant execute on function app.next_wms_outbound_shipment_number(uuid) to service_role;
grant execute on function app.create_wms_outbound_shipment(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_package_to_shipment(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_package_from_shipment(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_wms_shipment_vehicle_ref(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_wms_shipment_dock_location(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.load_wms_outbound_shipment(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.ship_confirm_wms_outbound_shipment(uuid, text, text, boolean, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_wms_outbound_shipment(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_wms_package(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_outbound_shipment(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_outbound_shipments(uuid, uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.list_wms_shipment_packages(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_shipment_issue_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_wms_billing_eligibility_event(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_billing_eligibility_events(uuid, uuid, uuid, uuid, integer) to authenticated, service_role;
