-- Phase 8 capability CPL-310 (CG-S13-CPL-012, Prompt 310, "Warehouse Order and
-- Order Fulfillment Visibility"). First prompt of Batch 3 (CPL-310..314).
--
-- The gap this migration closes -- the SAME scope-model gap CPL-309
-- (`supabase/migrations/20260801100000_create_customer_portal_warehouse_inventory_
-- visibility.sql`) already closed for inventory balances, applied here to
-- warehouse orders: every one of ATW-023's own three order-visibility RPCs
-- (`app.get_customer_outbound_order`/`app.list_customer_outbound_order_lines`/
-- `app.list_customer_outbound_orders`, `supabase/migrations/
-- 20260730310000_create_advanced_tms_customer_inventory_access.sql`) still
-- resolves scope via `app.resolve_customer_owner_account_scope` -- the OLD,
-- legacy-marker-only resolver. A `customer_portal` user granted a second
-- account only through CPL-300's new `app.customer_portal_account_memberships`
-- grant table (never the legacy `app.principal_memberships.customer_account_ref`
-- marker) is invisible to all three of those RPCs, exactly the ISS-2026-117
-- under-scoping shape CPL-309 already proved and fixed for balances/eligibility.
--
-- ===========================================================================
-- Design decisions
-- ===========================================================================
--
-- 1. **ADR-0024 Part A governs the shape**: every Phase 8 customer-facing read
--    is a new SECURITY DEFINER RPC composing (i) a scope resolver and (ii) a
--    domain-specific eligibility predicate, deny-by-default, anti-enumerating,
--    keyset-paginated. Raw-table RLS is never reopened. This migration follows
--    that pattern exactly, as every Phase 8 capability from CPL-300 onward has.
-- 2. **No new gate primitive.** `app.evaluate_customer_portal_inventory_access`
--    (CPL-309, `p_auth_user_id, p_tenant_id, p_warehouse_id, p_owner_account_id`)
--    is fully generic -- it composes `app.resolve_customer_account_scope`
--    (CPL-300's widened resolver) AND `app.customer_warehouse_eligibility_active`
--    (ATW-023, unmodified), with no inventory-balance-specific logic anywhere in
--    its own body. `app.wms_outbound_orders` carries both `warehouse_id` and
--    `owner_account_id` -- exactly the shape that gate primitive already
--    expects. Reused here BYTE-FOR-BYTE, imported by reference (already applied,
--    already granted to `authenticated`) -- this migration's own file contains
--    zero `CREATE OR REPLACE FUNCTION` against any pre-existing function,
--    grep-confirmed.
-- 3. **This migration's own RPC surface mirrors ATW-023's three order RPCs
--    column-for-column**, so a portal UI built against either surface sees
--    byte-identical columns: `app.get_customer_portal_outbound_order` mirrors
--    `app.get_customer_outbound_order` (id/warehouse_id/owner_account_id/
--    outbound_number/source_type/requested_ship_date/status/cancelled_reason/
--    record_version/created_at/updated_at -- design note 10 of ATW-023's own
--    migration already excludes `source_shipment_order_id`/`source_reason`/
--    `idempotency_key`/`created_by` as internal correlation ids and an
--    operational free-text note this RPC surface gives no way to resolve/act
--    on, inherited here unchanged). `app.list_customer_portal_outbound_order_
--    lines` mirrors `app.list_customer_outbound_order_lines` exactly, including
--    its own deliberately tenant-id-less signature (`p_outbound_order_id,
--    p_actor_auth_user_id` only) and its own "delegate the gate to the get RPC
--    rather than duplicate it" shape -- reused here unchanged, delegating to
--    THIS migration's own `app.get_customer_portal_outbound_order` instead of
--    ATW-023's original. `app.list_customer_portal_outbound_orders` mirrors
--    `app.list_customer_outbound_orders`'s own cursor-pagination signature and
--    column projection, and its own per-row/per-warehouse decomposition for
--    list-level performance (the owner-scope array is resolved ONCE per call
--    via `app.resolve_customer_account_scope`; the warehouse-eligibility check
--    runs per row, since it genuinely varies per row and cannot be
--    precomputed) -- the identical decomposition CPL-309's own `app.list_
--    customer_portal_inventory_balances` already uses, confirmed by direct
--    read of `app.list_customer_outbound_orders`'s own body before writing this
--    migration (it decomposes rather than calling the two-check gate primitive
--    once per row).
-- 4. **Every RPC below calls `app.assert_actor_is_session_identity` as its OWN
--    literal first statement** -- not merely relying on the transitive check
--    already inside `app.resolve_customer_account_scope`/`app.evaluate_
--    customer_portal_inventory_access` (both of which call it themselves).
--    Applied from the first draft, per the explicit, repeated lesson from
--    every prior Phase 8 batch (CPL-300 Tier C Finding 1; CPL-305/307/308/309's
--    own identical discipline) and this task's own explicit instruction (the
--    single most common Critical defect class across Phase 8 so far).
-- 5. **Anti-enumeration mirrors ATW-023 design note 5 exactly** --
--    `app.get_customer_portal_outbound_order` raises the IDENTICAL
--    `record_not_found` (errcode `no_data_found`) whether the order genuinely
--    does not exist, belongs to a different tenant, or exists but fails the
--    gate. `app.list_customer_portal_outbound_order_lines` inherits this
--    exact shape by delegating to the get RPC rather than re-deriving it.
-- 6. **No new denial-audit RPC.** `app.record_customer_inventory_access_denial`
--    (ATW-023, generic actor/resource-type/resource-id, already granted to
--    `authenticated`) is reused exactly as-is -- the TS service layer calls it
--    with `resource_type = 'outbound_order'`, the SAME literal ATW-023's own
--    db-test (`scripts/db-tests/advanced-tms-customer-inventory-access.sql`)
--    already uses for this resource type, in a SEPARATE follow-up call/
--    transaction after catching the get RPC's own thrown `record_not_found`
--    (ATW-023 design note 9's own proven constraint: an audit INSERT cannot
--    survive the subsequent RAISE within the same transaction).
-- 7. **RLS on `app.wms_outbound_orders`/`app.wms_outbound_order_lines` is
--    UNCHANGED BY THIS MIGRATION, confirmed by direct read, not assumed.**
--    Both tables' own raw-RLS SELECT policy was already narrowed by
--    `20260730311000_harden_customer_inventory_access_rls_isolation.sql`
--    (a companion hardening migration to ATW-023 itself) to deny a
--    `customer_user`-layer actor outright at the RLS layer, for ALL SEVEN
--    tables that migration touches, `app.wms_outbound_orders`/`app.wms_
--    outbound_order_lines` included -- re-confirmed live by this migration's
--    own db-test (raw-table RLS defense-in-depth section below), not merely
--    asserted from the earlier migration's own text. This migration's three
--    new RPCs are the sole new sanctioned customer-facing read path on top;
--    zero `ALTER TABLE`/`CREATE POLICY`/`DROP POLICY` statement appears
--    anywhere in this file.
-- 8. **No new table; zero RLS policy added or changed anywhere in this
--    migration.** A projection over `app.wms_outbound_orders`/`app.wms_
--    outbound_order_lines` (ATW-016A), both already read (unmodified) by
--    ATW-023.
-- 9. **Status vocabulary (Prompt 310 §20 task 1: "Map WMS order lifecycle
--    status values into a customer-visible status vocabulary").** Direct read
--    of `app.wms_outbound_orders`'s own `wms_outbound_orders_status_check`
--    CHECK constraint (`20260730230000_create_advanced_tms_wms_outbound_
--    order.sql:195`) confirms exactly THREE real lifecycle values exist:
--    `draft` / `confirmed` / `cancelled` -- ATW-016A's own design note 1
--    deliberately keeps this table's own status closed at that boundary; the
--    later ship-EXECUTION lifecycle (`staging`/`loaded`/`shipped`, ATW-019's
--    own `app.wms_outbound_shipments`, a SEPARATE table referencing
--    `outbound_order_id`, never a widening of this CHECK) is a distinct entity
--    this checkpoint's own bounded RPC/file budget does not compose (see
--    decision 11 below). This migration therefore raises none of its own
--    status values at the database layer -- every RPC below returns
--    `app.wms_outbound_orders.status` verbatim, unchanged, so the mapping
--    into a customer-visible vocabulary lives entirely at the presentation
--    layer (`server/contracts/customer-portal-warehouse-order/customer-portal-
--    warehouse-order.ts`'s own `CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS`, the
--    UI's own status-badge label map) -- the identical "raw enum column,
--    friendly label at the UI layer only" shape CPL-309's own `BALANCE_STATUS_
--    LABEL` (`on_hand`/`held`/`damaged`/`expired` -> "On hand"/"Held"/
--    "Damaged"/"Expired") already established, never a fabricated fourth
--    status this table's own data does not actually carry.
-- 10. **`p_status_filter` accepts only the three real values** (validated at
--     the Zod contract layer, `server/contracts/customer-portal-warehouse-
--     order/customer-portal-warehouse-order.ts`'s own
--     `CustomerWarehouseOrderStatusSchema`) -- the RPC itself does not
--     validate it server-side beyond the plain equality filter (mirrors
--     ATW-023's own `app.list_customer_outbound_orders`, which does not
--     validate `p_status_filter` either: an unrecognized value simply matches
--     zero rows, never an error, the same deny-by-default-by-construction
--     shape every filter parameter in this migration's own list RPC uses).
-- 11. **Inbound-order visibility is explicitly OUT OF SCOPE for this
--     checkpoint -- a deliberate scope decision, not an oversight.** ATW-023
--     (Phase 5) itself never built a customer-facing inbound-order RPC to
--     mirror in the first place (grep-confirmed: zero `app.get_customer_
--     inbound_order`/`app.list_customer_inbound_orders` anywhere in this
--     repository, before or after this migration) -- unlike the movement-
--     summary/lot/serial/export RPCs ISS-2026-119 named (which DO already
--     exist for ATW-023's OWN resolver and were simply not yet mirrored onto
--     the widened one), there is no existing customer-facing inbound-order
--     surface of any kind for this checkpoint to widen. This task's own
--     explicit design section names exactly three RPCs to build, all
--     outbound, and this checkpoint's own file/migration budget (normally
--     5-15 files, at most 1-3 additive migrations) does not extend to
--     designing a wholly new inbound-order customer RPC surface from
--     scratch (`app.wms_inbound_orders` does carry `owner_account_id`,
--     confirmed by direct read, so such a surface is plausible future work,
--     not a structural impossibility). Disclosed as a new, sequential
--     `ISS-2026-120` entry in `docs/runtime/KNOWN_ISSUES.md`, mirroring
--     ISS-2026-119's own structure. The UI's own "inbound/outbound"
--     indicator is satisfied honestly by labeling every order shown as
--     "Outbound" (the only warehouse order type this checkpoint's own RPCs
--     can see) rather than fabricating an inbound row with no backing RPC.
-- 12. **"Fulfillment progress" does not compose Picking/Packing/ship-execution
--     detail.** `app.wms_pick_tasks` (ATW-017) and `app.wms_packages`
--     (ATW-018) both carry genuinely internal operational fields --
--     `claimed_by_auth_user_id`/`claimed_by_label` (worker identity),
--     `picked_quantity`/`task_quantity`/`remaining_quantity` (productivity),
--     `qc_by_auth_user_id`/`qc_by_label` (internal QC worker) -- exactly the
--     "pick/pack worker, productivity, internal task queue" fields Business
--     rule 2 requires hidden. This migration's three RPCs never join, select
--     from, or reference `app.wms_pick_tasks`/`app.wms_packages`/`app.wms_
--     outbound_shipments`/`app.wms_pick_waves`/`app.wms_packing_tasks` at
--     all -- grep-confirmed against this file's own text, and live-verified
--     by this checkpoint's own db-test (a structural `pg_proc.prosrc` check
--     that none of those internal table/column names appear in any of the
--     three new functions' own compiled source). "Fulfillment progress" for
--     the UI is therefore derived entirely from the order's own real
--     `status` (draft = order captured/preparing; confirmed = ready for
--     warehouse fulfillment; cancelled = cancelled) plus its own line count
--     and `requested_quantity` totals -- never a fabricated pick/pack
--     percentage this checkpoint has no permitted data source for.
-- 13. **Exception/ticket handoff reuses the existing HRT-287 customer-ticket
--     creation flow, per this task's own explicit instruction** ("if CPL-313
--     hasn't landed yet in this batch's own sequence, the action can point at
--     the existing HRT-287 customer-ticket creation flow already shipped in
--     this repository"). CPL-313 (Ticketing/Support Integration) has not
--     landed as of this checkpoint (`00_EXECUTION_INDEX.md` still shows it
--     `READY`, not `VERIFIED`, three prompts after this one in the same
--     batch's own sequence) -- the detail page's own exception/ticket action
--     point is a plain `<Link href="/${tenantSlug}/customer-tickets">`,
--     mirroring the IDENTICAL convention CPL-304/307's own detail panels
--     already use ("open a ticket" inline link, no deep entity-link wiring),
--     never a new ticket-linking mechanism this checkpoint has no mandate to
--     design.
-- 14. **Freshness indicator uses the row's own real `updated_at` only** --
--     every RPC below reads `app.wms_outbound_orders`/`app.wms_outbound_
--     order_lines` live, on every call, never a cached/persisted projection
--     (there is nothing here that could go stale beyond what `updated_at`
--     itself already discloses) -- mirrors CPL-309's own identical "no
--     fabricated freshness/staleness field" decision for the identical
--     reason: this repository has no scheduler/job-refresh infrastructure to
--     keep a separate cache fresh.
-- 15. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--     Component fetch + UI only, no `app/api/` HTTP route -- identical in
--     kind to CPL-300..309's own disclosed residual gap.
-- 16. **No edit to `scripts/db-tests/rbac-enforcement.sql` required** --
--     verified by direct analysis of that file's own closure sweep (`base`/
--     `edge`/`closure` CTEs), not merely assumed: `base` already recognizes
--     any function whose `prosrc` contains the literal substring `resolve_
--     customer_account_scope` (a recognized keyword since CPL-300).
--     `app.list_customer_portal_outbound_orders` calls it directly, landing
--     in `base` directly. `app.get_customer_portal_outbound_order` calls
--     `app.evaluate_customer_portal_inventory_access` (itself already in
--     `base` since CPL-309, since ITS OWN body calls `resolve_customer_
--     account_scope`), so it is covered transitively via the `edge`/
--     `closure` recursion. `app.list_customer_portal_outbound_order_lines`
--     calls `app.get_customer_portal_outbound_order` (already covered
--     transitively as above), so it too lands in the closure. All three are
--     `STABLE` (not `VOLATILE`), exempting them from the separate
--     side-effecting-actor-authority sweep further down the same file. Live
--     re-verified in this checkpoint's own scratch-database run (see build
--     log).
-- 17. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--     carries its own explicit `revoke execute on all functions in schema
--     app from public` statement before its final grants.

-- ===========================================================================
-- 1. app.get_customer_portal_outbound_order -- single permitted order row,
-- anti-enumerating not-found (design decision 5). Mirrors app.get_customer_
-- outbound_order (ATW-023) exactly, gated via CPL-309's own reused gate
-- function.
-- ===========================================================================

create function app.get_customer_portal_outbound_order(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_outbound_order_id uuid
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  outbound_number text,
  source_type text,
  requested_ship_date date,
  status text,
  cancelled_reason text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_order app.wms_outbound_orders;
begin
  -- Own literal first statement (design decision 4) -- not merely relying on
  -- the transitive check inside app.resolve_customer_account_scope/app.
  -- evaluate_customer_portal_inventory_access.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_order from app.wms_outbound_orders o where o.id = p_outbound_order_id and o.tenant_id = p_tenant_id;
  if not found then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  if not app.evaluate_customer_portal_inventory_access(p_actor_auth_user_id, p_tenant_id, v_order.warehouse_id, v_order.owner_account_id) then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  return query
  select v_order.id, v_order.warehouse_id, v_order.owner_account_id, v_order.outbound_number, v_order.source_type,
    v_order.requested_ship_date, v_order.status, v_order.cancelled_reason, v_order.record_version, v_order.created_at, v_order.updated_at;
end;
$$;

comment on function app.get_customer_portal_outbound_order is
  'CPL-310: mirrors app.get_customer_outbound_order (ATW-023) column-for-column, gated via app.evaluate_customer_portal_inventory_access (CPL-309, the CPL-300-widened resolver composed with the unmodified ATW-023 warehouse-eligibility predicate) rather than ATW-023''s own app.evaluate_customer_inventory_access -- the ISS-2026-117 fix, applied to warehouse orders. Raises the identical record_not_found (errcode no_data_found) whether p_outbound_order_id genuinely does not exist, belongs to a different tenant, or exists but fails the gate (design decision 5). Columns exclude source_shipment_order_id/source_reason/idempotency_key/created_by -- internal correlation ids and an operational free-text note this RPC surface gives no way to resolve/act on. Not self-audited on the denial branch (an audit insert cannot survive the subsequent RAISE within the same transaction, ATW-023 design note 9); the TS service layer durably records the denial via a separate app.record_customer_inventory_access_denial call (ATW-023, reused as-is, resource_type=''outbound_order'') in a new transaction after catching this RPC''s own error.';

-- ===========================================================================
-- 2. app.list_customer_portal_outbound_order_lines -- reuses app.get_customer_
-- portal_outbound_order for its own gate rather than duplicating it, exactly
-- as app.list_customer_outbound_order_lines (ATW-023) already does for its
-- own get RPC. Deliberately no p_tenant_id parameter -- mirrors ATW-023's own
-- signature exactly (design decision 3).
-- ===========================================================================

create function app.list_customer_portal_outbound_order_lines(p_outbound_order_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  outbound_order_id uuid,
  line_number integer,
  item_master_id uuid,
  requested_uom_code text,
  requested_quantity numeric,
  lot_controlled boolean,
  serial_controlled boolean,
  expiry_controlled boolean,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_order app.wms_outbound_orders;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_order from app.wms_outbound_orders o where o.id = p_outbound_order_id;
  if not found then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  -- Re-derives the gate (and its own identically-shaped anti-enumerating
  -- denial) through THIS migration's own app.get_customer_portal_outbound_
  -- order rather than duplicating it or delegating to ATW-023's original.
  perform app.get_customer_portal_outbound_order(v_order.tenant_id, p_actor_auth_user_id, p_outbound_order_id);

  return query
  select l.id, l.outbound_order_id, l.line_number, l.item_master_id, l.requested_uom_code, l.requested_quantity,
    l.lot_controlled, l.serial_controlled, l.expiry_controlled, l.record_version, l.updated_at
  from app.wms_outbound_order_lines l
  where l.outbound_order_id = p_outbound_order_id
  order by l.line_number;
end;
$$;

comment on function app.list_customer_portal_outbound_order_lines is
  'CPL-310: mirrors app.list_customer_outbound_order_lines (ATW-023) exactly, including its own deliberately tenant-id-less signature. Columns exclude notes (free-text, potentially staff-internal). Delegates its own authority/scope gate to THIS migration''s app.get_customer_portal_outbound_order (the ISS-2026-117-fixed gate), never ATW-023''s original get RPC.';

-- ===========================================================================
-- 3. app.list_customer_portal_outbound_orders -- bounded, cursor-paginated
-- list. Mirrors app.list_customer_outbound_orders (ATW-023)'s own signature/
-- column projection/decomposition exactly (design decision 3).
-- ===========================================================================

create function app.list_customer_portal_outbound_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  outbound_number text,
  source_type text,
  requested_ship_date date,
  status text,
  cancelled_reason text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- A cursor is a (timestamp, id) PAIR -- p_cursor_id supplied alone would
  -- otherwise silently filter out every row (a non-null-vs-null row
  -- comparison evaluates to unknown, which WHERE treats as false), returning
  -- an empty page instead of surfacing the caller's own malformed-cursor bug.
  -- Fails loud instead, mirroring ATW-023's own identical validation.
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  -- Resolved ONCE per call, not once per row (design decision 3) --
  -- app.resolve_customer_account_scope, the CPL-300 widened resolver.
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select o.id, o.warehouse_id, o.owner_account_id, o.outbound_number, o.source_type, o.requested_ship_date, o.status,
    o.cancelled_reason, o.record_version, o.created_at, o.updated_at
  from app.wms_outbound_orders o
  where o.tenant_id = p_tenant_id
    and (p_warehouse_id is null or o.warehouse_id = p_warehouse_id)
    and (p_status_filter is null or o.status = p_status_filter)
    and o.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, o.warehouse_id, o.owner_account_id)
    and (p_cursor_id is null or (o.updated_at, o.id) < (p_cursor_updated_at, p_cursor_id))
  order by o.updated_at desc, o.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_outbound_orders is
  'CPL-310: mirrors app.list_customer_outbound_orders (ATW-023)''s own signature/column projection/status-filter/cursor-pagination shape exactly, resolving scope via app.resolve_customer_account_scope (CPL-300 widened resolver) instead of app.resolve_customer_owner_account_scope -- the ISS-2026-117 fix. Bounded (p_limit default 50, hard-capped 200), keyset-paginated on (updated_at desc, id desc), never OFFSET. A caller whose resolved scope is empty gets zero rows, never an error. p_status_filter accepts app.wms_outbound_orders'' own three real status values (draft/confirmed/cancelled) -- an unrecognized value simply matches zero rows, never an error, mirroring ATW-023''s own identical non-validating filter shape.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.get_customer_portal_outbound_order(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_portal_outbound_order_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_portal_outbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
