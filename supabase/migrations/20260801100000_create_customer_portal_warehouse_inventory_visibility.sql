-- Phase 8 capability CPL-309 (CG-S13-CPL-011, Prompt 309, "Warehouse Inventory
-- Visibility"). Closes the scope-composition gap ISS-2026-117 disclosed
-- (docs/runtime/KNOWN_ISSUES.md) between two already-shipped, already-VERIFIED
-- inventory-visibility layers that were never composed together:
--
-- 1. ATW-023 (Phase 5, supabase/migrations/
--    20260730310000_create_advanced_tms_customer_inventory_access.sql) built the
--    first genuine customer-facing inventory-read RPC surface, but every one of
--    its RPCs resolves customer scope via app.resolve_customer_owner_account_scope,
--    which reads ONLY the legacy single-account app.principal_memberships.
--    customer_account_ref marker (ATW-016's own design).
-- 2. CPL-300 (Phase 8, supabase/migrations/
--    20260801010000_create_customer_portal_account_scope.sql) introduced a NEW
--    real many-to-many grant table, app.customer_portal_account_memberships, and
--    a NEW resolver, app.resolve_customer_account_scope, which returns the UNION
--    of the legacy marker AND the new multi-account grant table.
--
-- A customer_portal user granted access to a SECOND account only through CPL-300's
-- new grant table (never through the legacy marker) is invisible to every ATW-023
-- RPC -- app.resolve_customer_owner_account_scope has no way to see a grant that
-- exists only in the new table -- and would incorrectly get ZERO rows for that
-- account's own inventory. This is an under-scoping (false-negative) gap, not an
-- over-scoping (leak) gap: no customer ever sees another customer's data through
-- this gap: the RPC just wrongly denies data that account IS entitled to. Already
-- registered as ISS-2026-117 (Medium, OPEN, disclosed at CPL-301 as "composed
-- around, not fixed" -- the dashboard's own new RPC never relayed a second,
-- independently-supplied identity into either ATW-023 function, so it introduced
-- no NEW exposure, but the underlying gap remained open for any future capability
-- that needed the widened scope). This migration is that fix, scoped exactly to
-- warehouse/inventory visibility per Prompt 309's own charter.
--
-- ===========================================================================
-- Design decisions
-- ===========================================================================
--
-- 1. **ADR-0024 Part A governs the shape**: every Phase 8 customer-facing read is
--    a new SECURITY DEFINER RPC composing (i) a scope resolver and (ii) a
--    domain-specific eligibility predicate, deny-by-default, anti-enumerating,
--    keyset-paginated. Raw-table RLS is never reopened. This migration follows
--    that pattern exactly, as every Phase 8 capability from CPL-300 onward has.
-- 2. **The fix is NOT editing ATW-023's already-applied migration** (forbidden --
--    AGENTS.md "never edit an applied migration"; the prompt's own explicit
--    instruction). It is NOT re-deriving a third, independent copy of the
--    owner+eligibility predicate either -- that would be exactly the
--    "second, independently-evolving enforcement point" ATW-023's own design
--    note 6 already named and rejected once. Instead this migration composes
--    two already-verified, unmodified primitives that were simply never wired
--    together: CPL-300's app.resolve_customer_account_scope (the widened
--    resolver) and ATW-023's app.customer_warehouse_eligibility_active (the
--    warehouse-eligibility predicate, reused byte-for-byte, no new table).
--    A NEW, narrow, single-purpose gate function --
--    app.evaluate_customer_portal_inventory_access -- is the one place these two
--    are composed, mirroring ATW-023's own app.evaluate_customer_inventory_access
--    shape exactly (same two-check AND, same signature), swapping only which
--    scope resolver it calls.
-- 3. **This migration's own RPC surface mirrors ATW-023's RPC surface exactly,
--    projection-for-projection**, so a portal UI built against either surface
--    sees byte-identical columns: app.get_customer_portal_inventory_balance /
--    app.list_customer_portal_inventory_balances mirror app.get_customer_
--    inventory_balance / app.list_customer_inventory_balances (id/warehouse_id/
--    owner_account_id/item_master_id/location_id/lot_number/serial_number/
--    status/on_hand/reserved/held/available/record_version/updated_at, the same
--    all-zero-row exclusion on the list, the same per-row/per-warehouse
--    decomposition for list-level performance: the owner-scope array is resolved
--    ONCE per call, never once per row, while the warehouse-eligibility check
--    genuinely varies per row and is evaluated per row). app.list_customer_
--    portal_warehouse_eligibility mirrors app.list_customer_warehouse_eligibility
--    (same columns including revoked_reason, no OPS RBAC gate at all -- purely
--    resolved-owner-scope).
-- 4. **Every RPC below calls app.assert_actor_is_session_identity(p_actor_auth_
--    user_id)/(p_auth_user_id) as its OWN literal first statement** -- not merely
--    relying on the transitive check already inside app.resolve_customer_
--    account_scope (which itself calls it, CPL-300 design). This is the explicit,
--    repeated lesson from every Phase 8 batch so far (CPL-300 Tier C Finding 1;
--    CPL-305/307/308's own identical first-statement discipline) applied here
--    from the first draft, not retrofitted after a review finding.
-- 5. **Anti-enumeration (mirrors ATW-023 design note 5 exactly)**: app.get_
--    customer_portal_inventory_balance raises the IDENTICAL `record_not_found`
--    (errcode no_data_found) whether p_balance_id genuinely does not exist,
--    belongs to a different tenant, or exists but fails app.evaluate_customer_
--    portal_inventory_access -- never a distinguishable insufficient_authority.
-- 6. **No new denial-audit RPC** -- app.record_customer_inventory_access_denial
--    (ATW-023) is reused exactly as-is (it is generic: actor/resource-type/
--    resource-id only, already granted to authenticated, not tied to either
--    resolver). The TS service layer (server/queries/customer-portal-inventory.ts)
--    calls it the same way server/queries/customer-inventory-access.ts already
--    does: a SEPARATE follow-up RPC call, in a NEW transaction, after catching
--    the get RPC's own anti-enumerating record_not_found -- never inside the same
--    transaction as the RAISE (ATW-023 design note 9's own proven constraint: an
--    audit INSERT cannot survive the subsequent RAISE within the same
--    transaction).
-- 7. **RLS on app.inventory_balances and app.warehouse_customer_eligibility is
--    UNCHANGED BY THIS MIGRATION** -- confirmed by direct read of each table's
--    own already-applied RLS SELECT policy before writing a single line of this
--    migration, not assumed from this prompt's own brief:
--      - app.inventory_balances_select_scoped
--        (20260730190000_create_advanced_tms_inventory_ledger.sql:851-859) passes
--        `null` as app.can_access_record's own p_customer_account_ref argument --
--        no owner-scope branch at all, staff-only via org-unit membership. A
--        customer_user actor (no org_unit_id) is unconditionally denied at RLS.
--      - app.warehouse_customer_eligibility_select_scoped
--        (20260730140000_create_advanced_tms_warehouse_zone.sql:1040-1048) is the
--        identical shape -- `null` customer_account_ref, staff-only, a
--        customer_user actor unconditionally denied.
--    Both tables already deny-by-default for a customer_user actor at the RLS
--    layer, exactly like every other Phase 8 capability's own base-table RLS
--    disclosure (CPL-307/308's own "zero table touched" notes) -- this migration
--    is the sole new sanctioned read path on top, adding no new grant, no new
--    policy, no widening of either table's own already-applied RLS.
-- 8. **No table this migration touches gains a new RLS policy; zero new table.**
--    A projection over app.inventory_balances (ATW-015) and app.warehouse_
--    customer_eligibility (ATW-229), both already read (unmodified) by ATW-023.
-- 9. **Movement-summary drill-down, lot/serial identity drill-down, and export
--    are explicitly OUT OF SCOPE for this prompt** (Prompt 309's own instruction)
--    -- the required UI columns (SKU/item, lot, on-hand/reserved/held/available,
--    location, aging) are already satisfiable from the balance projection alone
--    via lot_number/serial_number and updated_at (aging/freshness). Disclosed as
--    a new sequential KNOWN_ISSUES.md entry (ISS-2026-119, Low, deliberate scope
--    decision, mirrors ISS-2026-118's own structure), never silently dropped.
-- 10. **No "freshness/staleness" table or column is fabricated.** Every RPC below
--     reads app.inventory_balances live, on every call, never a cached snapshot
--     (there is no persisted projection anywhere in this migration to go stale).
--     "Aging"/"freshness" for the UI (Prompt 309 §22 Alternative flow) is derived
--     entirely from each row's own real `updated_at` -- never a fabricated
--     separate source-version field, mirroring the prompt's own explicit
--     instruction and CPL-301's own established "no persisted dashboard cache"
--     precedent (design decision 1, 20260801020000_create_customer_portal_
--     dashboard_summary.sql) for the identical reason: this repository has no
--     scheduler/job-refresh infrastructure to keep a separate cache fresh, so a
--     live read is the only honest freshness signal available.
-- 11. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--     Component fetch + UI only, no `app/api/` HTTP route -- identical in kind to
--     CPL-300..308's own disclosed residual gap.
-- 12. **No edit to scripts/db-tests/rbac-enforcement.sql required** -- verified by
--     direct analysis of that file's own closure sweep (section 3, the `base`/
--     `edge`/`closure` CTEs), not merely assumed: `base` already recognizes any
--     function whose prosrc contains the literal substrings
--     `resolve_customer_account_scope` or `customer_warehouse_eligibility_active`
--     (both already-recognized keywords since CPL-300/ATW-023). app.evaluate_
--     customer_portal_inventory_access's own body calls both directly, so it
--     lands in `base` directly; app.list_customer_portal_inventory_balances and
--     app.list_customer_portal_warehouse_eligibility both call app.resolve_
--     customer_account_scope directly, landing in `base` directly too; app.get_
--     customer_portal_inventory_balance calls app.evaluate_customer_portal_
--     inventory_access (itself in `base`), so it is covered transitively via the
--     `edge`/`closure` recursion. All four are STABLE (not VOLATILE), exempting
--     them from the separate side-effecting-actor-authority sweep further down
--     the same file.
-- 13. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its
--     own explicit `revoke execute on all functions in schema app from public`
--     statement before its final grants, the standing per-migration convention.

-- ===========================================================================
-- 1. app.evaluate_customer_portal_inventory_access -- the new gate primitive.
-- Identical shape to app.evaluate_customer_inventory_access (ATW-023), except it
-- calls app.resolve_customer_account_scope (CPL-300, the widened resolver)
-- instead of app.resolve_customer_owner_account_scope, still composed with the
-- EXISTING, UNCHANGED app.customer_warehouse_eligibility_active (design decision 2).
-- ===========================================================================

create function app.evaluate_customer_portal_inventory_access(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_owner_account_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    p_owner_account_id = any(app.resolve_customer_account_scope(p_auth_user_id, p_tenant_id))
    and app.customer_warehouse_eligibility_active(p_tenant_id, p_warehouse_id, p_owner_account_id);
$$;

comment on function app.evaluate_customer_portal_inventory_access is
  'CPL-309 (ISS-2026-117 fix, scoped to warehouse inventory): true only if BOTH hold -- (a) p_owner_account_id is in app.resolve_customer_account_scope''s own result for (p_auth_user_id, p_tenant_id) -- the CPL-300 widened resolver, UNION of the legacy app.principal_memberships.customer_account_ref marker AND the new app.customer_portal_account_memberships grant table; (b) an ACTIVE app.warehouse_customer_eligibility row for (tenant_id, warehouse_id, p_owner_account_id) via app.customer_warehouse_eligibility_active (ATW-023, reused verbatim). Identical shape to app.evaluate_customer_inventory_access (ATW-023) -- the only difference is which scope resolver is composed. app.resolve_customer_account_scope itself calls app.assert_actor_is_session_identity first (CPL-300), so this function inherits that check transitively; every RPC below additionally calls it as its own literal first statement (design decision 4), never relying on the transitive check alone.';

-- ===========================================================================
-- 2. app.get_customer_portal_inventory_balance -- single permitted balance row,
-- anti-enumerating not-found (design decision 5). Mirrors app.get_customer_
-- inventory_balance (ATW-023) exactly, gated via the new function above.
-- ===========================================================================

create function app.get_customer_portal_inventory_balance(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_balance_id uuid
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  status text,
  on_hand numeric,
  reserved numeric,
  held numeric,
  available numeric,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_balance app.inventory_balances;
begin
  -- Own literal first statement (design decision 4) -- not merely relying on
  -- the transitive check inside app.resolve_customer_account_scope.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_balance from app.inventory_balances b where b.id = p_balance_id and b.tenant_id = p_tenant_id;
  if not found then
    raise exception 'record_not_found: no permitted inventory balance exists for %', p_balance_id using errcode = 'no_data_found';
  end if;

  if not app.evaluate_customer_portal_inventory_access(p_actor_auth_user_id, p_tenant_id, v_balance.warehouse_id, v_balance.owner_account_id) then
    raise exception 'record_not_found: no permitted inventory balance exists for %', p_balance_id using errcode = 'no_data_found';
  end if;

  return query
  select v_balance.id, v_balance.warehouse_id, v_balance.owner_account_id, v_balance.item_master_id, v_balance.location_id,
    v_balance.lot_number, v_balance.serial_number, v_balance.status, v_balance.on_hand, v_balance.reserved, v_balance.held,
    v_balance.available, v_balance.record_version, v_balance.updated_at;
end;
$$;

comment on function app.get_customer_portal_inventory_balance is
  'CPL-309: raises the identical record_not_found (errcode no_data_found) whether p_balance_id genuinely does not exist, belongs to a different tenant, or exists but fails app.evaluate_customer_portal_inventory_access -- design decision 5. Not self-audited on the denial branch (an audit insert cannot survive the subsequent RAISE within the same transaction, ATW-023 design note 9); stays a pure, stable read. The TS service layer durably records the denial via a separate app.record_customer_inventory_access_denial call (ATW-023, reused as-is) in a new transaction after catching this RPC''s own error -- design decision 6.';

-- ===========================================================================
-- 3. app.list_customer_portal_inventory_balances -- cursor-paginated, excludes
-- all-zero rows exactly as app.list_customer_inventory_balances (ATW-023)
-- already does. Same per-row/per-warehouse decomposition for list-level
-- performance: the owner-scope array is resolved ONCE per call, the warehouse-
-- eligibility check runs per row (design decision 3).
-- ===========================================================================

create function app.list_customer_portal_inventory_balances(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  status text,
  on_hand numeric,
  reserved numeric,
  held numeric,
  available numeric,
  record_version integer,
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
  -- otherwise silently filter out every row (a non-null-vs-null row comparison
  -- evaluates to unknown, which WHERE treats as false), returning an empty page
  -- instead of surfacing the caller's own malformed-cursor bug. Fails loud
  -- instead, mirroring ATW-023's own identical validation.
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select b.id, b.warehouse_id, b.owner_account_id, b.item_master_id, b.location_id, b.lot_number, b.serial_number,
    b.status, b.on_hand, b.reserved, b.held, b.available, b.record_version, b.updated_at
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id)
    and (p_cursor_id is null or (b.updated_at, b.id) < (p_cursor_updated_at, p_cursor_id))
  order by b.updated_at desc, b.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_inventory_balances is
  'CPL-309: bounded (p_limit default 50, hard-capped 200), keyset-paginated on (updated_at desc, id desc), never OFFSET. Excludes all-zero (on_hand=reserved=held=0) rows, mirroring app.list_customer_inventory_balances (ATW-023)/app.list_inventory_balances (ATW-015). A caller whose resolved scope (app.resolve_customer_account_scope, CPL-300 widened resolver) is empty gets zero rows, never an error. THE KEY REGRESSION FIX (ISS-2026-117): an owner_account_id granted ONLY through CPL-300''s new app.customer_portal_account_memberships table -- never through the legacy app.principal_memberships.customer_account_ref marker -- now appears in v_scope and this list, where app.list_customer_inventory_balances (ATW-023) would have wrongly returned zero rows for that account.';

-- ===========================================================================
-- 4. app.list_customer_portal_warehouse_eligibility -- "no OPS RBAC gate,
-- purely resolved-owner-scope" shape (mirrors app.list_customer_warehouse_
-- eligibility, ATW-023), resolving v_scope via app.resolve_customer_account_scope
-- instead of the old resolver. This is what the portal UI uses to build its
-- warehouse/site filter.
-- ===========================================================================

create function app.list_customer_portal_warehouse_eligibility(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  warehouse_id uuid,
  customer_account_id uuid,
  status text,
  granted_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);

  return query
  select wce.id, wce.warehouse_id, wce.customer_account_id, wce.status, wce.granted_at, wce.revoked_at, wce.revoked_reason, wce.record_version
  from app.warehouse_customer_eligibility wce
  where wce.tenant_id = p_tenant_id
    and wce.customer_account_id = any(v_scope)
  order by wce.granted_at desc;
end;
$$;

comment on function app.list_customer_portal_warehouse_eligibility is
  'CPL-309: no OPS RBAC gate -- purely resolved-owner-scope (app.resolve_customer_account_scope, the CPL-300 widened resolver), matching ATW-023''s own app.list_customer_warehouse_eligibility shape. Columns exclude granted_by (a staff label) and include revoked_reason (a customer legitimately needs to know why a warehouse eligibility grant was revoked). This is what the portal UI composes to build its warehouse/site filter -- an account granted only through the new CPL-300 grant table now sees its own warehouse eligibility grants here too, closing the same ISS-2026-117 gap for the filter surface, not just the balance list.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.evaluate_customer_portal_inventory_access(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_customer_portal_inventory_balance(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_portal_inventory_balances(uuid, uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_warehouse_eligibility(uuid, uuid) to authenticated, service_role;
