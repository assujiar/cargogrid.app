-- Phase 8 capability CPL-301 (CG-S13-CPL-003, Prompt 301, "Customer Portal
-- Dashboard"). Read docs/adr/ADR-0024-phase8-customer-portal-access-and-
-- transport-pattern.md and supabase/migrations/
-- 20260801010000_create_customer_portal_account_scope.sql (CPL-300) in full
-- before this migration was written -- this is the second Phase 8 capability,
-- and it follows CPL-300's own established shape exactly: deny-by-default,
-- SECURITY DEFINER, no raw RLS reopened, actor-identity cross-check first.
--
-- ===========================================================================
-- Design decisions (cited, not re-derived -- orchestrator task text and
-- 00_EXECUTION_INDEX.md §5's own dependency-graph note that CPL-301's cards
-- "deep-link into every scoped flow; no flow trusts the dashboard itself")
-- ===========================================================================
--
-- 1. **No new dashboard read-model/cache/snapshot table.** The source prompt's
--    own §13 phrase "pre-aggregated dashboard read models" is implemented as a
--    LIVE aggregating SECURITY DEFINER RPC, never a persisted cache -- this
--    repository has no scheduler/job-refresh infrastructure to keep a cache
--    fresh (confirmed: `app.jobs`/PLT-132 runs on-demand/event-triggered
--    batches, never a time-based cron-style refresh), and building one would
--    be new, out-of-scope infrastructure this task's own instruction
--    explicitly declines. `app.get_customer_portal_dashboard_summary` is
--    `stable` (no write, no schedule, computed fresh on every call) and
--    returns one row per card: `card_key text, available boolean,
--    source_updated_at timestamptz, degraded boolean, summary jsonb,
--    detail_path text`.
-- 2. **Composes ONLY real, already-existing customer-facing data sources --
--    never fabricates.** As of this checkpoint the only three are: (a)
--    CPL-300's own `app.get_customer_portal_scope_context` (account/site
--    list) for the `accounts` card; (b) ATW-023's `app.list_customer_
--    inventory_balances` / `app.list_customer_outbound_orders`
--    (`20260730310000_create_advanced_tms_customer_inventory_access.sql`) for
--    ONE combined `warehouse_inventory` card (the source prompt's own
--    "e.g. counts by status" framing, not two separate cards -- ATW-023
--    itself already covers both sources under one design-note umbrella); (c)
--    HRT-287's own `app.list_customer_tickets`
--    (`20260731080000_extend_ticketing_customer_channel.sql`) for the
--    `tickets` card (open-ticket count). Every OTHER card the source prompt's
--    own §15 UI/UX text names -- `bookings`, `shipments`, `invoices`,
--    `payments`, `loyalty` -- has NO real customer-facing RPC yet (Prompts
--    302-323's own future job, per `00_EXECUTION_INDEX.md` §4/§5's own
--    workstream map) and is returned with `available = false`, an honest
--    `summary = '{}'::jsonb`, and `detail_path = null` -- never sample/fake
--    data. `alerts` (also named in §15, but not named in the orchestrator
--    task's own explicit stub-card enumeration) is included as a ninth stub
--    card for the identical reason (taxonomy class C-23: a named spec item
--    must either be built or explicitly disclosed as out of scope, never
--    silently dropped) -- disclosed in the build log as cross-cutting rather
--    than owned by any single future capability (a shipment exception alert
--    is CPL-306's own eventual job; an SLA-breach alert is CPL-313's own).
--    `available = true` is reserved exclusively for a card whose data source
--    genuinely exists and was queried (even if the real count is zero for
--    this caller) -- it is never a proxy for "the UI has something to show."
-- 3. **Anti-enumeration/scope (ADR-0024 Part A).** `app.assert_actor_is_
--    session_identity(p_auth_user_id)` is the first statement, exactly
--    mirroring every read RPC CPL-300's own Tier C review fixed. The
--    canonical resolver, `app.resolve_customer_account_scope(p_auth_user_id,
--    p_tenant_id)`, is called directly (never cached/passed in from a
--    caller) and used as a genuine, additional per-row filter on top of what
--    each composed RPC below already enforces internally -- not decorative.
--    This RPC takes no `p_account_id`/entity-id parameter of any kind, so
--    there is no client-supplied scope value to distrust in the first place;
--    the extra `= any(v_scope)` filter is belt-and-suspenders defense in
--    depth on top of each composed RPC's own internal deny-by-default gate,
--    catching the theoretical case where a future change desynchronizes the
--    two resolvers CPL-300's own design decision 4 already keeps in lockstep
--    today (its own Tier C Finding 2 fix: revoke/suspend through the new
--    grant table already drives the legacy `app.principal_memberships`
--    marker `app.list_customer_inventory_balances`/`app.list_customer_
--    outbound_orders`/`app.list_customer_tickets` still resolve scope from).
-- 4. **Two of the three composed RPCs (`app.list_customer_inventory_
--    balances`, `app.list_customer_outbound_orders`) do not call `app.
--    assert_actor_is_session_identity` themselves** -- verified by direct
--    read of `20260730310000_create_advanced_tms_customer_inventory_
--    access.sql` (that migration predates `app.assert_actor_is_session_
--    identity`'s own introduction, `20260730440000_harden_actor_identity_
--    session_crosscheck.sql`, and was never retrofitted). This migration
--    never widens their exposure: `p_actor_auth_user_id` is always this
--    function's own already-cross-checked `p_auth_user_id`, never a second,
--    independently-supplied identity, so no new forgery surface is opened by
--    composing them here. The underlying gap is real, pre-existing, and NOT
--    caused by this task -- disclosed (not fixed, per `AGENTS.md` "fix only
--    task-caused failures") as `ISS-2026-117` in `docs/runtime/
--    KNOWN_ISSUES.md`, an applied migration is never edited to retrofit it.
--    `app.list_customer_tickets` (HRT-287) DOES already call it -- see that
--    migration for confirmation.
-- 5. **Per-card resilience -- one source's failure must never blank the
--    others (source prompt §22 alternative flow).** Each of the three real
--    cards' own composed-RPC call is wrapped in its own nested `BEGIN ...
--    EXCEPTION WHEN OTHERS ... END` block, marking that ONE card `degraded =
--    true` with safe zero/`null` defaults on failure while every sibling
--    card's own block is unaffected -- PL/pgSQL's own per-block implicit
--    savepoint means a caught exception here rolls back only that nested
--    block's own (read-only, so nothing to roll back) work, never the
--    surrounding transaction. This is a deliberate, disclosed use of a broad
--    `WHEN OTHERS` handler -- distinct from the recurring-defect-taxonomy
--    C-09 concern (a handler that WRONGLY discriminates/recovers a specific
--    constraint), since no recovery/business decision is made here: every
--    branch degrades to the identical safe "zero, marked degraded" shape
--    regardless of the real underlying SQLSTATE, and the caller (this
--    function's own single top-level caller, the dashboard page) already
--    treats `degraded = true` as "show this card as degraded," not as a
--    signal to branch further. Live-proven, not reasoned about: a scratch
--    reproduction (session-scoped `ALTER FUNCTION ... RENAME` immediately
--    reverted, never committed to any migration) confirmed a genuinely
--    absent composed function in a FRESH backend (no cached plan) is caught
--    by exactly one card's own block while the sibling cards' own blocks
--    still return correctly -- reproduced again, live, in this checkpoint's
--    own db-test (`scripts/db-tests/customer-portal-dashboard.sql`).
-- 6. **Bounded, disclosed-approximate counts (source prompt §17 performance
--    impact: "no `SELECT *`... pre-aggregated... where justified").** No
--    dedicated count-only RPC exists for either ATW-023 source or HRT-287's
--    ticket list, so each real card's own count is computed by paging the
--    existing list RPC at its own hard cap (200, matching every composed
--    RPC's own established `least(greatest(...,1),200)` ceiling) and
--    counting the returned (and `v_scope`-filtered) rows -- exact below 200,
--    and explicitly flagged `...Capped = true` (never silently reported as
--    exact) when the raw page itself returned exactly 200 rows, meaning more
--    may exist beyond this one bounded read. A true exact count beyond 200
--    is left to whichever future capability (Prompt 309/310) builds a
--    dedicated count/aggregate RPC for these sources -- disclosed, not a
--    silently wrong number.
-- 7. **`source_updated_at` reflects the real underlying data's own recency
--    where the composed RPC exposes one** (`updated_at` on the balance/
--    outbound-order/ticket rows themselves, `GREATEST` of the two halves for
--    the combined `warehouse_inventory` card) -- never a synthetic value.
--    `app.get_customer_portal_scope_context` (CPL-300, an already-applied
--    migration this task may not edit) exposes no per-row timestamp of its
--    own, and this migration deliberately does NOT open a second, competing
--    raw-table read path against `app.customer_portal_account_memberships`
--    to manufacture one (CPL-300's own header: "the RPCs... are the only
--    sanctioned access path" -- growing a ninth direct reader outside that
--    set is exactly the "second, independently-evolving enforcement point"
--    ATW-023's own design note 6 already rejected as a pattern) -- the
--    `accounts` card's own `source_updated_at` is therefore `now()`, an
--    honest "computed live, this instant" value for an RPC with no cache to
--    go stale, not a fabricated per-row timestamp.
-- 8. **Every card's own `detail_path` is a real, already-`VERIFIED` route
--    that re-authorizes itself server-side, or `null`.** `accounts` ->
--    `'customer-portal'` (CPL-300's own scope-preview page, same guard
--    family). `tickets` -> `'customer-tickets'` (HRT-287's own bounded
--    customer ticket route, its own separate guard). `warehouse_inventory`
--    -> `null`: ATW-023's own migration design note 12 is explicit that it
--    built "No UI route, no REST/GraphQL surface" for its RPCs -- that UI is
--    Prompt 309/310's own chartered scope (Warehouse Inventory/Order
--    Visibility), not this dashboard's, and this migration does not build it
--    to avoid the forbidden "duplicate... warehouse... root" this task's own
--    instruction names. The real counts are shown today; the "view details"
--    action appears only once a real route exists to point at -- never a
--    dead link (source prompt §15's own explicit "no dead action"). Every
--    stub card (`bookings`/`shipments`/`invoices`/`payments`/`loyalty`/
--    `alerts`) also carries `detail_path = null` for the identical reason --
--    no route exists for any of them yet.
-- 9. **No mutation, no idempotency key.** A pure, `stable` read -- nothing in
--    this migration writes, so no idempotency/optimistic-concurrency
--    machinery applies (recurring-defect-taxonomy C-01/C-03/C-04: N/A, no
--    such construct in this diff).
-- 10. **ATW-032 authority-surface sweep (`scripts/db-tests/
--     rbac-enforcement.sql`) compliance, planned up front.** This function's
--     own body directly calls `app.resolve_customer_account_scope(...)` --
--     already a recognized base-regex authority primitive (CPL-300's own
--     widening of that sweep's keyword list) -- so this new function is
--     credited automatically via the sweep's own substring-match `base`
--     classification, with no further edit to that shared test file
--     required. Verified directly: re-ran the sweep's own query shape against
--     this function's `prosrc` before shipping (see db-test).
--
-- ===========================================================================
-- app.get_customer_portal_dashboard_summary
-- ===========================================================================

create function app.get_customer_portal_dashboard_summary(p_auth_user_id uuid, p_tenant_id uuid)
returns table (
  card_key text,
  available boolean,
  source_updated_at timestamptz,
  degraded boolean,
  summary jsonb,
  detail_path text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];

  v_account_count integer := 0;
  v_primary_account_name text := null;
  v_accounts_degraded boolean := false;

  v_balance_count integer := 0;
  v_balance_capped boolean := false;
  v_balance_updated_at timestamptz := null;
  v_balance_degraded boolean := false;

  v_outbound_count integer := 0;
  v_outbound_capped boolean := false;
  v_outbound_updated_at timestamptz := null;
  v_outbound_degraded boolean := false;

  v_ticket_count integer := 0;
  v_ticket_capped boolean := false;
  v_ticket_updated_at timestamptz := null;
  v_tickets_degraded boolean := false;

  v_wh_updated_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  -- Design decision 3: the canonical resolver, re-derived directly (never
  -- trusted from a client-supplied value -- there is none here) and used
  -- below as a genuine additional per-row filter, not merely called for a
  -- side effect.
  v_scope := app.resolve_customer_account_scope(p_auth_user_id, p_tenant_id);

  -- Card: accounts/scope (design decision 2a) -----------------------------
  begin
    select count(*), max(account_name) filter (where is_primary)
      into v_account_count, v_primary_account_name
    from app.get_customer_portal_scope_context(p_auth_user_id, p_tenant_id);
  exception when others then
    v_accounts_degraded := true;
    v_account_count := 0;
    v_primary_account_name := null;
  end;

  -- Card: warehouse/inventory, balance half (design decision 2b/6) ---------
  begin
    with page as (
      select owner_account_id, updated_at
      from app.list_customer_inventory_balances(p_tenant_id, p_auth_user_id, null, null, null, null, 200)
    )
    select
      count(*) filter (where owner_account_id = any (v_scope)),
      count(*) = 200,
      max(updated_at) filter (where owner_account_id = any (v_scope))
    into v_balance_count, v_balance_capped, v_balance_updated_at
    from page;
  exception when others then
    v_balance_degraded := true;
    v_balance_count := 0;
    v_balance_capped := false;
    v_balance_updated_at := null;
  end;

  -- Card: warehouse/inventory, outbound-order half (design decision 2b/6) --
  begin
    with page as (
      select owner_account_id, status, updated_at
      from app.list_customer_outbound_orders(p_tenant_id, p_auth_user_id, null, null, null, null, 200)
    )
    select
      count(*) filter (where owner_account_id = any (v_scope) and status <> 'cancelled'),
      count(*) = 200,
      max(updated_at) filter (where owner_account_id = any (v_scope))
    into v_outbound_count, v_outbound_capped, v_outbound_updated_at
    from page;
  exception when others then
    v_outbound_degraded := true;
    v_outbound_count := 0;
    v_outbound_capped := false;
    v_outbound_updated_at := null;
  end;

  -- Card: tickets (design decision 2c) -------------------------------------
  begin
    with page as (
      select account_id, status, updated_at
      from app.list_customer_tickets(p_tenant_id, p_auth_user_id, null, null, 200, null)
    )
    select
      count(*) filter (where account_id = any (v_scope) and status not in ('resolved', 'closed', 'cancelled')),
      count(*) = 200,
      max(updated_at) filter (where account_id = any (v_scope))
    into v_ticket_count, v_ticket_capped, v_ticket_updated_at
    from page;
  exception when others then
    v_tickets_degraded := true;
    v_ticket_count := 0;
    v_ticket_capped := false;
    v_ticket_updated_at := null;
  end;

  v_wh_updated_at := greatest(v_balance_updated_at, v_outbound_updated_at);

  return query
  select * from (values
    ('accounts'::text, true, now(), v_accounts_degraded,
      jsonb_build_object('activeAccountCount', v_account_count, 'primaryAccountName', v_primary_account_name),
      'customer-portal'::text),
    ('warehouse_inventory'::text, true, v_wh_updated_at, (v_balance_degraded or v_outbound_degraded),
      jsonb_build_object(
        'activeInventoryBalanceCount', v_balance_count, 'activeInventoryBalanceCountCapped', v_balance_capped,
        'openOutboundOrderCount', v_outbound_count, 'openOutboundOrderCountCapped', v_outbound_capped
      ),
      null::text),
    ('tickets'::text, true, v_ticket_updated_at, v_tickets_degraded,
      jsonb_build_object('openTicketCount', v_ticket_count, 'openTicketCountCapped', v_ticket_capped),
      'customer-tickets'::text),
    ('bookings'::text, false, null::timestamptz, false, '{}'::jsonb, null::text),
    ('shipments'::text, false, null::timestamptz, false, '{}'::jsonb, null::text),
    ('invoices'::text, false, null::timestamptz, false, '{}'::jsonb, null::text),
    ('payments'::text, false, null::timestamptz, false, '{}'::jsonb, null::text),
    ('loyalty'::text, false, null::timestamptz, false, '{}'::jsonb, null::text),
    ('alerts'::text, false, null::timestamptz, false, '{}'::jsonb, null::text)
  ) as t(card_key, available, source_updated_at, degraded, summary, detail_path);
end;
$$;

comment on function app.get_customer_portal_dashboard_summary is
  'CPL-301: the live-aggregating customer portal dashboard summary -- one row per card, never a persisted cache (design decision 1). Calls app.assert_actor_is_session_identity(p_auth_user_id) first, then app.resolve_customer_account_scope as a genuine additional per-row filter on every composed real card (design decision 3). Composes ONLY app.get_customer_portal_scope_context (CPL-300), app.list_customer_inventory_balances/app.list_customer_outbound_orders (ATW-023), and app.list_customer_tickets (HRT-287) -- the only three real customer-facing data sources that exist as of this checkpoint. Every other named card (bookings/shipments/invoices/payments/loyalty/alerts) is returned with available=false, summary={}, detail_path=null -- never fake data (design decision 2). Each real card''s own composed-RPC call is independently wrapped so one source''s failure marks only that card degraded, never the others (design decision 5). Counts are bounded at 200 (matching every composed RPC''s own hard cap) and flagged *Capped when the true count may exceed that bound (design decision 6).';

-- ===========================================================================
-- Grants
-- ===========================================================================

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default before any role-specific grant (standing
-- per-migration convention since PLT-118).
revoke execute on all functions in schema app from public;

grant execute on function app.get_customer_portal_dashboard_summary(uuid, uuid) to authenticated, service_role;
