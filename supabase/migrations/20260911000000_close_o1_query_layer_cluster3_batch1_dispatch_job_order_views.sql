-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 3 (operations-tms-core)
-- batch 1: Dispatch (Basic + Advanced Board) and Job Order / Job Order Lineage reads.
-- Continues the same Design->Verify->Fix adversarial pipeline established for cluster 0
-- (batches 1-5), cluster 1 (batch 1), and cluster 2 (batch 1): supabase/config.toml's
-- `schemas = ["public", "graphql_public"]` never exposes the "app" Postgres schema to
-- PostgREST, so every `.from()` read against an `app.*` table/view in
-- server/queries/*.ts has never worked in production. The fix is the Option-2 wrapper:
-- a new `app.<name>` SECURITY DEFINER function reproducing the read plus its
-- RLS-equivalent authority check in SQL, a thin `public.<name>` pass-through (the only
-- PostgREST-reachable surface), then the TS caller switches `.from()` -> `.rpc()`.
--
-- Closes 7 call sites across 4 tables/views (all of cluster 3 batch 1's scope):
--   app.shipment_orders (count only) + app.dispatch_ready_queue (view)  basic-dispatch.ts
--   app.dispatch_board_queue (view)                                    dispatch-board.ts
--   app.job_orders_directory (view, x3 call sites)                     job-order.ts
--   app.job_order_handoffs_directory (view, x2 call sites)             job-order-lineage.ts
--
-- 12 new function pairs (24 functions total):
--   app.count_dispatch_ready_shipment_orders / app.list_dispatch_ready_queue
--   app.count_dispatch_board_shipment_orders / app.list_dispatch_board
--   app.get_job_order / app.get_job_order_for_handoff / app.list_job_orders
--   app.get_job_order_handoff_for_quotation / app.list_job_order_handoffs
--
-- Both drafts below were produced independently (one per file-group) and each passed
-- its own adversarial verify pass before being concatenated into this migration --
-- see each section's own detailed RULE A/B/C research and disposition notes. Notable
-- findings from verify, both resolved before this migration was ever applied to any
-- database:
--   * dispatch_views.sql's own verify pass corrected a "for the two count functions"
--     scoping gap in the SECURITY DEFINER-vs-INVOKER justification (the BYPASSRLS
--     argument applies with EQUAL severity to the two list functions -- unfiltered ROWS,
--     not merely an unfiltered count, would leak to a service_role caller under
--     INVOKER), an off-by-one in the dispatch_board_queue projection-column count (10 ->
--     11), and a RULE B citation undercount (two files -> three, one of them prose-only).
--   * job_order_views.sql's own verify pass found and fixed a REAL cross-tenant-leak
--     risk: app.get_job_order_for_handoff and app.get_job_order_handoff_for_quotation
--     originally used a silent `order by created_at desc limit 1` fallback for a
--     hypothetical (schema-legal but application-unreachable today) multi-row match --
--     since such a match would mean two rows disagreeing about which TENANT a
--     handoff/quotation belongs to, silently picking "the newest" risked handing a
--     caller a different tenant's data. Both functions now COUNT matches and RAISE
--     `ambiguous_context` (`check_violation`) instead, matching `.maybeSingle()`'s own
--     throw-on-conflict contract and this codebase's established count-then-raise idiom
--     (app.resolve_access_context, PLT-108).
--
-- ===========================================================================
-- PART 1 of 2: DISPATCH (basic-dispatch.ts, dispatch-board.ts)
-- ===========================================================================

-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 3 (dispatch/tracking)
-- batch 1, dispatch half (this migration's own Part 1 of 2). Continues the same
-- Design->Verify->Fix adversarial pipeline cluster 0 (32 tables), cluster 1 (6 tables)
-- and cluster 2 (5 tables/7 call sites) already established: supabase/config.toml's
-- `schemas =
-- ["public", "graphql_public"]` never exposes "app" to PostgREST, so every `.from()`
-- read against an `app.*` relation in server/queries/*.ts has NEVER worked in
-- production.
--
-- Closes 2 of cluster 3's recorded call-site entries, both inside Basic/Advanced
-- Dispatch:
--   app.shipment_orders (base table, count only)  server/queries/basic-dispatch.ts:85-89
--       (listDispatchReadyQueue's exact-count HEAD request)
--   app.dispatch_ready_queue (view)                server/queries/basic-dispatch.ts:95-100
--       (listDispatchReadyQueue's paginated data read)
--   app.dispatch_board_queue (view)                server/queries/dispatch-board.ts:42-47
--       (listDispatchBoard's single count+data read)
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior O1 batch): a new `app.*`
-- SECURITY DEFINER function reimplementing each read with an explicit
-- `p_actor_auth_user_id` parameter and the record's CURRENT RLS-equivalent authority
-- predicate reproduced in SQL, plus a thin `public.*` pass-through wrapper (the only
-- PostgREST-reachable surface, since `app` itself is invisible) carrying an IDENTICAL
-- grant set -- never a reimplementation.
--
-- ===========================================================================
-- WHY FOUR NEW FUNCTIONS, NOT TWO (the count-design question this file's own task
-- brief explicitly flagged as an open call -- read this section before the verify
-- pass second-guesses the split)
-- ===========================================================================
--
-- The naive Option-2 port of a `{ count: "exact" }` PostgREST call is one new SQL
-- function that selects `*, count(*) over() as total_count` and lets the TS layer
-- read `total_count` off row 0 -- this is exactly app.list_portal_users' own
-- established shape (20260910010000:1383-1439) and is what this task's own brief
-- describes as "the established pattern." That shape is used below for NEITHER of
-- these two screens, and the reason is the same reason 20260907170000 (CG-AUDIT-2026
-- -09-02 F5) already exists:
--
-- Both app.dispatch_ready_queue and app.dispatch_board_queue are defined as
-- `select so.*, ... from app.shipment_orders so cross join lateral
-- app.evaluate_dispatch_readiness(so.id) as r where ...` (20260727160000:315-321,
-- 20260729300000:85-107) -- a real, non-trivial SECURITY DEFINER function
-- (app.evaluate_dispatch_readiness, ~40 lines, itself doing 3 further subqueries) is
-- invoked once per row that survives the WHERE clause, for every row the LATERAL join
-- produces. 20260907170000's own header derives the cost consequence in detail: a
-- `count: "exact"` pass over either view forces that function to run once per
-- MATCHING row (not merely once per PAGE), because a head-only exact count must scan
-- every row satisfying the WHERE clause regardless of any later LIMIT.
--
-- `count(*) over()` has the identical cost shape, not a different one: per the SQL
-- standard's own logical processing order, a window function is computed over every
-- row surviving FROM/WHERE *before* ORDER BY/LIMIT trims the output -- so a single
-- query shaped `select so.*, r.is_ready, r.blockers, count(*) over() as total_count
-- from app.shipment_orders so cross join lateral app.evaluate_dispatch_readiness(so.
-- id) as r where ... order by ... limit ... offset ...` still requires the lateral
-- join (hence the readiness function) to run once for every one of the N rows
-- matching the WHERE clause, even though only `page_size` of those N rows are ever
-- returned to the caller. It is a genuine improvement over the pre-F5 two-query bug
-- (one pass instead of two, so ~N instead of ~N+page_size lateral calls), but it is
-- still O(N) in the tenant's total matching-row count, precisely the class of cost
-- 20260907170000 was written to eliminate for this exact pair of views. Reproducing
-- that shape here would silently reintroduce, in brand-new code, the same defect
-- class an already-shipped, already-reasoned-about migration exists specifically to
-- prevent.
--
-- The fix mirrors 20260907170000's own resolution exactly: the exact count is taken
-- as a SEPARATE, plain query against app.shipment_orders directly -- filtered
-- identically (tenant_id + status predicate + the record-scope predicate below) but
-- with NO lateral join at all, so it costs one index-backed count, never a per-row
-- function call. The row filter alone (no readiness/tracking columns, no LATERAL, no
-- LEFT JOIN) can never disagree with a count taken "through" either view, by the same
-- equivalence argument 20260907170000's own header already makes for
-- app.dispatch_ready_queue: neither view's WHERE clause depends on anything the
-- LATERAL/LEFT JOIN produces, and app.dispatch_board_queue's own `left join app.
-- shipment_tracking_health` is keyed on a UNIQUE (shipment_order_id) column, so it
-- can never fan a matching so-row out into more than one output row or drop one --
-- omitting it from the count changes nothing about which rows are counted. The
-- paginated data query keeps its LATERAL join (it needs is_ready/blockers, or the
-- full tracking projection, in its own output) but, exactly like the current
-- (post-F5) `.range(from, to)` data read, is bounded by LIMIT/OFFSET against an
-- ORDER BY the partial covering index can satisfy -- so it costs roughly
-- offset+page_size lateral calls per page, not N.
--
-- app.dispatch_board_queue was not itself named by 20260907170000 (that migration's
-- own scope was exactly "the two screens the audit itself named and reproduced" --
-- shipment-order list and the BASIC dispatch queue) -- but its view body (confirmed
-- by re-reading 20260729300000:85-107 directly, not merely trusting its own header's
-- "RLS-scoped identically to app.dispatch_ready_queue" claim) reuses the identical
-- `cross join lateral app.evaluate_dispatch_readiness(so.id) as r` for every row
-- regardless of status (the `case when so.status = 'assigned' then r.is_ready else
-- null end` logic only changes which COLUMN VALUE is emitted, not whether the
-- LATERAL itself runs) -- so the identical O(N) argument applies to it verbatim, with
-- exactly the same fix. This is a deliberate extrapolation beyond the literal
-- precedent (there is no prior "app.count_dispatch_board_*" to point to -- this
-- endpoint never worked before today, so there is no live-production cost regression
-- to cite, only a newly-introduced one this draft is choosing not to introduce) --
-- **flagged here explicitly for the verify pass**: an alternative, more literal
-- reading of this task's own brief is to give app.list_dispatch_board the single-
-- query `count(*) over()` shape (matching app.list_portal_users verbatim, since nothing
-- in the brief named the board for the F5 treatment) and accept the O(N) cost as a new,
-- disclosed follow-up item instead. This draft's author judged the performance
-- argument strong enough (identical LATERAL, identical fix, zero extra functions of
-- meaningfully different shape) to apply it symmetrically rather than leave a twin
-- defect sitting next to its own fixed sibling -- but this is exactly the kind of
-- design call an adversarial verify pass exists to re-litigate, not something to
-- treat as settled by this draft alone.
--
-- ===========================================================================
-- SECURITY DEFINER vs SECURITY INVOKER for ALL FOUR new functions (this file's own
-- task brief's step 4 -- re-scoped by this verify pass: the draft's original header
-- titled this section "for the two new count functions" and argued only the `select
-- count(*) ...` shape explicitly, but the underlying BYPASSRLS argument below applies
-- identically, and with equal severity, to the two new LIST functions -- an INVOKER
-- app.list_dispatch_ready_queue/app.list_dispatch_board called by service_role would
-- leak full unfiltered ROWS across every tenant/actor, not merely an unfiltered count,
-- which is the more serious of the two failure modes, not a lesser one. All four
-- functions are SECURITY DEFINER in the SQL below; this section's scope is corrected
-- so the written justification actually covers what the code does.)
-- ===========================================================================
-- app.shipment_orders' own SELECT grant is a DIRECT table grant to `authenticated`
-- (20260727100000:494, `grant select on app.shipment_orders to authenticated;`) plus a
-- separate direct grant to `service_role` (line 495) -- RLS is enforced on top of that
-- grant via `shipment_orders_select_scoped` (see RULE B below), not instead of a
-- grant. A SECURITY INVOKER function reading `app.shipment_orders` directly would
-- therefore still have the table's own real grant to work with for an `authenticated`
-- caller, and Postgres's row-security engine would still apply
-- `shipment_orders_select_scoped` automatically for that role -- so far, invoker
-- would appear to "just work" for authenticated.
--
-- It is still the wrong choice, for one reason every other function in this
-- remediation series already shares: `service_role` is granted EXECUTE on every one of
-- these functions (ISS-2026-309/this series' own uniform convention, see GRANT PARITY
-- below), and Supabase's own `service_role` is provisioned with `BYPASSRLS` -- a
-- SECURITY INVOKER function called by a `service_role` session would run the bare
-- `select count(*) from app.shipment_orders where tenant_id = ... and status =
-- 'assigned'` (for the two count functions) or the equivalent unfiltered `select ...
-- from app.shipment_orders ...` (for the two list functions) with NO row-security
-- filtering applied at all (BYPASSRLS means the row-security engine never even
-- evaluates `shipment_orders_select_scoped` for that session), silently returning a
-- cross-actor, unscoped count OR a cross-actor, unscoped ROW SET to any service_role
-- caller regardless of the `p_actor_auth_user_id` it claims to be reading for. That
-- is a real disclosure defect, not a hypothetical one -- service_role is this
-- project's own backend/cron/support-tooling identity per this series' own established
-- reasoning (20260910010000:684-689, "every backend/admin tooling surface in this
-- codebase ... authenticates as service_role"). SECURITY DEFINER, with the record-
-- scope predicate reproduced explicitly against the caller-supplied
-- `p_actor_auth_user_id` (never relying on the session's own row-security state),
-- is therefore required for correctness, for BOTH the count and the list shape,
-- under this series' own uniform `authenticated, service_role` grant convention --
-- exactly the choice every other function in cluster 0-2 already made, for the
-- identical reason.
--
-- ===========================================================================
-- RULE B (RLS predicate currency) -- app.shipment_orders' own current SELECT policy
-- ===========================================================================
-- Repo-wide grep for BOTH `create policy`/`alter policy` naming app.shipment_orders
-- AND the bare policy name `shipment_orders_select_scoped`, across every file in
-- supabase/migrations/*.sql sorted by filename (re-run independently for this verify
-- pass -- the draft's own original claim of "exactly two files" undercounted this by
-- one; corrected below), finds exactly THREE files mentioning the policy name, and
-- only ONE `create policy`/`alter policy` statement naming it anywhere:
--   * 20260727100000_create_operations_shipment_order.sql:481-483 -- the ORIGINAL,
--     and only-ever, declaration:
--       create policy shipment_orders_select_scoped on app.shipment_orders
--         for select to authenticated
--         using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id,
--           app.lead_record_scope_org_unit_ids(org_unit_id), null));
--   * 20260801050000_create_customer_portal_shipment_order_access.sql:146-154 -- a
--     later migration's own header PROSE confirming (not rewriting) this same
--     predicate: "app.shipment_orders itself is completely untouched by this
--     migration -- no [row-security policy] on it is edited, narrowed, or widened; it
--     already correctly denies a customer_user-layer principal by default ... (its
--     own single shipment_orders_select_scoped [rule] tests app.can_access_record,
--     which fails closed for a customer_user-layer principal carrying no staff org-
--     unit/owner relationship -- re-verified live in this checkpoint's own db-test, not
--     merely assumed)."
--   * 20260907170000_fix_shipment_order_dispatch_double_scan_iss_f5.sql:32 -- also
--     bare-string PROSE only (this migration's own header, deriving the F5 index/
--     count-split fix from the same predicate) -- no `create policy`/`alter policy`
--     statement, no table/RLS change of any kind; it adds two covering indexes only
--     (verified by reading the full file: zero `policy` keyword occurrences outside
--     this one header line).
-- No fourth hit, and no second `create policy`/`alter policy` statement, exists
-- anywhere in the migration set -- there has never been a rewrite of this policy. The
-- predicate quoted above is therefore the CURRENT, ground-truth predicate, reproduced
-- verbatim (with the session-bound `(select auth.uid())` swapped for the explicit
-- `p_actor_auth_user_id` parameter every function in this series uses instead, per
-- RULE A) in every function below.
--
-- Both `app.dispatch_ready_queue` (20260727160000:315-321) and `app.
-- dispatch_board_queue` (20260729300000:85-107) already embed this identical
-- predicate directly in their own view bodies (`app.can_access_record(auth.uid(), so.
-- tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id),
-- null)`) -- re-read directly from both view definitions for this draft, not assumed
-- from either view's own header comment. This draft's functions reproduce that same
-- call shape against `p_actor_auth_user_id` rather than the views' own bare session-
-- bound call, for the identical service_role-safety reason given above.
--
-- ===========================================================================
-- RULE C (precedent staleness) -- every helper below checked against its MOST RECENT
-- create-or-replace, not its original creation migration
-- ===========================================================================
--   * app.can_access_record -- exactly two hits repo-wide: the original
--     20260716110430_create_field_record_access.sql:31 and ONE later rewrite,
--     20260723180000_create_commercial_sales_pipeline.sql:50-88 (COM-146's own NULL-
--     owner coalesce fix). No third hit exists. The CURRENT body (quoted in that
--     migration) is: `has_active_tenant_membership(tenant_id, actor) AND coalesce(
--     is_supreme_admin(actor) OR (owner is not null and owner = actor) OR <shared
--     org-unit membership> OR <active customer-account membership>, false)`. Called by
--     reference (never re-implemented) below, so this draft always tracks whichever
--     body is current.
--   * app.lead_record_scope_org_unit_ids -- exactly ONE hit repo-wide,
--     20260723090000_create_commercial_lead_management.sql:164-176 -- never replaced.
--     Called by reference below.
--   * app.assert_actor_is_session_identity -- exactly ONE `create or replace` hit
--     repo-wide, 20260730440000_harden_actor_identity_session_crosscheck.sql:59-89 --
--     never re-replaced. A no-op whenever the session identity is null (service_role,
--     superuser, db-tests, nested SECURITY DEFINER calls); raises
--     `actor_identity_mismatch` only when a genuine authenticated session's own
--     identity differs from the claimed `p_actor_auth_user_id`. `perform app.
--     assert_actor_is_session_identity(p_actor_auth_user_id);` is the first executable
--     statement in every function below that is reachable by `authenticated`.
--   * app.evaluate_dispatch_readiness -- exactly ONE hit repo-wide,
--     20260727160000_create_operations_basic_dispatch.sql:46-89 -- never replaced.
--     Called by reference (via the same `cross join lateral ... as r` shape both
--     views already use), never re-implemented.
--   * app.is_shipment_tracking_entitled -- TWO hits: the original disclosed-stub
--     20260729300000:70-76 (always false) and a later, real implementation via
--     `create or replace function` at
--     20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql:88-94
--     (delegates to the Configuration Engine, same signature preserved per that
--     migration's own header). Called by reference below (exactly as app.
--     dispatch_board_queue's own view body already does) -- this draft never inlines
--     either body, so it automatically tracks whichever implementation is current at
--     call time with zero staleness risk, unlike a helper this draft would otherwise
--     have to re-derive.
--
-- ===========================================================================
-- CONTRACT FIDELITY -- column shape for the two list functions
-- ===========================================================================
-- app.shipment_orders' current physical column set (verified by repo-wide grep for
-- every `alter table app.shipment_orders add column` statement, sorted by filename,
-- beyond the original 29-column 20260727100000 CREATE TABLE): exactly two additive
-- columns exist, `held_from_status` (20260727110000:62, OPS-170) and
-- `leg_network_status` (20260729290000:47, ATW-221) -- no other column was ever added
-- or dropped. `so.*` inside either view therefore expands to 31 columns today; both
-- list functions below name all 31 explicitly (RETURNS TABLE, not `returns setof app.
-- shipment_orders`, since each also appends its own view-specific projection columns)
-- in the same field order server/contracts/shipment-order/shipment-order.ts's own
-- ShipmentOrderSchema already uses (`heldFromStatus` placed right after `status`,
-- `legNetworkStatus` at the end before the view-specific columns) -- verified against
-- that contract file directly, not assumed. Every one of these 31 columns is consumed
-- by parseDispatchReadyQueueRow/parseDispatchBoardRow (server/contracts/basic-
-- dispatch/basic-dispatch.ts:42-78, server/contracts/dispatch-board/dispatch-
-- board.ts:45-90) -- no exclusion, no masking column exists on app.shipment_orders
-- itself (OPS-169's own migration header: "No masked column exists on this table").
--
-- app.dispatch_board_queue's own extra 11 projection columns (is_ready, blockers,
-- has_active_assignment, tracking_status, authoritative_source_type,
-- last_position_at, freshness_status, accuracy_meters, fallback_active,
-- tracking_entitled, tracking_exception_count -- corrected count, this verify pass:
-- the draft's original header said 10, an off-by-one; the RETURNS TABLE below (and
-- app.dispatch_board_queue's own view body) both actually carry all 11) are
-- reproduced verbatim, in the same
-- order, from 20260729300000:87-107 -- including its own coalesce()-to-honest-default
-- logic for every tracking column (never a fabricated live value).
--
-- ===========================================================================
-- ROW-NOT-FOUND / EMPTY-RESULT BEHAVIOR
-- ===========================================================================
-- Both list functions and both count functions return zero rows / a zero count
-- silently, never an exception, for a tenant the actor cannot access, a page past the
-- last row, or an actor with no standing at all -- matching the original `.from()`
-- reads' own RLS-filtered silent-empty-result behavior exactly (per this task's own
-- brief: these are broad "list what I can see" reads, not single-tenant admin
-- lookups, so no new RAISE is introduced here, matching app.list_portal_users' own
-- identical no-pre-flight-raise precedent, 20260910010000:1411-1416).
--
-- ===========================================================================
-- GRANT PARITY (ISS-2026-309) and ERR-2026-004
-- ===========================================================================
-- Every `app.*` function below is granted to `authenticated, service_role`, matching
-- this series' own uniform, ~45-function-strong convention regardless of what its own
-- underlying table/view happens to grant (20260910010000:830-833's own restatement of
-- this rule). Per ISS-2026-309 (closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): every `public.*` wrapper
-- below explicitly revokes from `anon, authenticated, service_role, public` (all four)
-- before re-granting exactly the same two roles -- a bare `revoke ... from public`
-- does NOT strip the `anon`/`authenticated` EXECUTE grants Supabase's own ALTER
-- DEFAULT PRIVILEGES rule applies to every new function in schema `public` at CREATE
-- time. Per ERR-2026-004: each `app.*` function below carries its own explicit
-- `revoke execute on function ... from public` before its grant (this migration's own
-- per-function style, matching cluster 1/2's own per-function convention rather than a
-- single trailing blanket statement).
--
-- check-rls-initplan.ts false-positive avoidance: every `comment on function ... is
-- '...'` string below avoids combining a literal mention of a rule-rewrite statement
-- with a bare, parenthesized `auth.uid()`/`auth.jwt()` mention in the same string --
-- e.g. "no later rewrite of this rule exists" instead of naming the rewrite mechanism
-- directly next to such a call. This file's own `--` line-comment prose above is
-- unaffected (the guard's own `blankLineComments` preprocessing blanks every `--` line
-- before parsing) and is written plainly. The guard itself is never suppressed, only
-- the prose reworded.

-- ===========================================================================
-- 1. app.count_dispatch_ready_shipment_orders -- the count half of
--    server/queries/basic-dispatch.ts:85-89 (listDispatchReadyQueue)
-- ===========================================================================
-- Replaces: `.from("shipment_orders").select("*", { count: "exact", head: true })
-- .eq("tenant_id", input.tenantId).eq("status", "assigned")`. No LATERAL join, no
-- readiness computation -- see this migration's own header for why the count is kept
-- entirely separate from the paginated data read below (preserves 20260907170000's
-- own already-shipped fix intent).
create function app.count_dispatch_ready_shipment_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns bigint
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return (
    select count(*)
    from app.shipment_orders so
    where so.tenant_id = p_tenant_id
      and so.status = 'assigned'
      and app.can_access_record(
        p_actor_auth_user_id,
        so.tenant_id,
        so.owner_user_id,
        app.lead_record_scope_org_unit_ids(so.org_unit_id),
        null
      )
  );
end;
$$;

comment on function app.count_dispatch_ready_shipment_orders(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3, dispatch): the exact-count half of server/queries/basic-dispatch.ts''s listDispatchReadyQueue (lines 85-89), replacing a broken .from("shipment_orders") HEAD request (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Filter reproduces tenant_id + status=''assigned'' plus app.shipment_orders'' own current shipment_orders_select_scoped predicate (app.can_access_record against an explicit actor id, never the session''s own auth context -- required for correctness under service_role''s BYPASSRLS, see this migration''s own header), matching app.dispatch_ready_queue''s own WHERE clause exactly. Deliberately has NO lateral join to app.evaluate_dispatch_readiness -- counting through that view''s own shape would force the readiness function to run once per matching row just to produce a total, the exact O(N) cost 20260907170000 (CG-AUDIT-2026-09-02 F5) already eliminated for this same screen; this function preserves that fix''s intent for the first time this read actually becomes reachable. Returns 0, never an exception, for a tenant/actor with zero visible matching rows.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.count_dispatch_ready_shipment_orders with an identical grant
-- set, never a reimplementation.
create function public.count_dispatch_ready_shipment_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.count_dispatch_ready_shipment_orders(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.count_dispatch_ready_shipment_orders(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.count_dispatch_ready_shipment_orders with an identical grant set, never a reimplementation.';

revoke execute on function app.count_dispatch_ready_shipment_orders(uuid, uuid) from public;
grant execute on function app.count_dispatch_ready_shipment_orders(uuid, uuid) to authenticated, service_role;

revoke execute on function public.count_dispatch_ready_shipment_orders(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.count_dispatch_ready_shipment_orders(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_dispatch_ready_queue -- the data half of
--    server/queries/basic-dispatch.ts:95-100 (listDispatchReadyQueue)
-- ===========================================================================
-- Replaces: `.from("dispatch_ready_queue").select("*").eq("tenant_id", input.tenantId)
-- .order("planned_pickup_at", { ascending: true, nullsFirst: false }).range(from,
-- to)`. Reproduces app.dispatch_ready_queue''s own view body (20260727160000:315-321)
-- directly against its base table, so the lateral join''s own cost profile under
-- LIMIT/OFFSET (bounded by the partial covering index 20260907170000 already added,
-- `shipment_orders_tenant_assigned_pickup_id_idx`) is unchanged from the current
-- (post-F5) `.range()` read this replaces. id is added as a secondary ORDER BY key
-- (the original call had none) purely for determinism across two page fetches when
-- planned_pickup_at ties -- matching this series'' own established
-- pagination-determinism convention (e.g. app.list_portal_users'' own id tie-break).
create function app.list_dispatch_ready_queue(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  shipment_number text,
  idempotency_key text,
  status text,
  held_from_status text,
  shipper_account_id uuid,
  consignee_snapshot jsonb,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb,
  service_type text,
  mode text,
  origin text,
  destination text,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  basis_quantity numeric,
  basis_weight_kg numeric,
  basis_volume_cbm numeric,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  split_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  leg_network_status text,
  is_ready boolean,
  blockers jsonb
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
  v_page integer;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_limit := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_page := greatest(coalesce(p_page, 1), 1);

  return query
    select
      so.id,
      so.tenant_id,
      so.job_order_id,
      so.shipment_number,
      so.idempotency_key,
      so.status,
      so.held_from_status,
      so.shipper_account_id,
      so.consignee_snapshot,
      so.notify_party_snapshot,
      so.cargo_service_snapshot,
      so.service_type,
      so.mode,
      so.origin,
      so.destination,
      so.planned_pickup_at,
      so.planned_delivery_at,
      so.basis_quantity,
      so.basis_weight_kg,
      so.basis_volume_cbm,
      so.allocated_quantity,
      so.allocated_weight_kg,
      so.allocated_volume_cbm,
      so.split_reason,
      so.owner_user_id,
      so.org_unit_id,
      so.record_version,
      so.created_by,
      so.created_at,
      so.updated_at,
      so.leg_network_status,
      r.is_ready,
      r.blockers
    from app.shipment_orders so
    cross join lateral app.evaluate_dispatch_readiness(so.id) as r
    where so.tenant_id = p_tenant_id
      and so.status = 'assigned'
      and app.can_access_record(
        p_actor_auth_user_id,
        so.tenant_id,
        so.owner_user_id,
        app.lead_record_scope_org_unit_ids(so.org_unit_id),
        null
      )
    order by so.planned_pickup_at asc nulls last, so.id asc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_dispatch_ready_queue(uuid, uuid, integer, integer) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3, dispatch): the paginated data half of server/queries/basic-dispatch.ts''s listDispatchReadyQueue (lines 95-100), replacing a broken .from("dispatch_ready_queue") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Reproduces app.dispatch_ready_queue''s own current view body verbatim against its base table -- status=''assigned'' plus app.shipment_orders'' own current shipment_orders_select_scoped predicate (app.can_access_record against an explicit actor id, never the session''s own auth context, for the service_role-BYPASSRLS reason this migration''s own header explains) -- with the same cross join lateral app.evaluate_dispatch_readiness(so.id) the view itself uses, so is_ready/blockers can never disagree with a single-shipment app.get_dispatch_readiness call. p_page/p_page_size are clamped server-side (1-100) as defense in depth for a directly-callable RPC, mirroring the TS layer''s own existing MAX_PAGE_SIZE=100 clamp. order by planned_pickup_at asc nulls last, id asc adds an id tie-break beyond the original single-column ordering for determinism across page fetches; both are covered by the existing partial index shipment_orders_tenant_assigned_pickup_id_idx (20260907170000), so this function''s own LIMIT/OFFSET cost profile is unchanged from the current (post-F5) .range() read it replaces. Deliberately returns no total_count column -- see this migration''s own header for why the exact count is a separate, lateral-free function (app.count_dispatch_ready_shipment_orders) rather than a count(*) over() column here, which would reintroduce the exact O(N) lateral-evaluation cost 20260907170000 eliminated. Returns an empty set, never an exception, for a tenant/actor with zero visible rows or a page past the last row.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_dispatch_ready_queue with an identical grant set, never a
-- reimplementation.
create function public.list_dispatch_ready_queue(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  shipment_number text,
  idempotency_key text,
  status text,
  held_from_status text,
  shipper_account_id uuid,
  consignee_snapshot jsonb,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb,
  service_type text,
  mode text,
  origin text,
  destination text,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  basis_quantity numeric,
  basis_weight_kg numeric,
  basis_volume_cbm numeric,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  split_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  leg_network_status text,
  is_ready boolean,
  blockers jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_dispatch_ready_queue(p_tenant_id, p_actor_auth_user_id, p_page, p_page_size);
$wrap$;

comment on function public.list_dispatch_ready_queue(uuid, uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_dispatch_ready_queue with an identical grant set, never a reimplementation.';

revoke execute on function app.list_dispatch_ready_queue(uuid, uuid, integer, integer) from public;
grant execute on function app.list_dispatch_ready_queue(uuid, uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_dispatch_ready_queue(uuid, uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_dispatch_ready_queue(uuid, uuid, integer, integer) to authenticated, service_role;

-- ===========================================================================
-- 3. app.count_dispatch_board_shipment_orders -- the count half of
--    server/queries/dispatch-board.ts:42-47 (listDispatchBoard)
-- ===========================================================================
-- Replaces the `{ count: "exact" }` half of `.from("dispatch_board_queue")
-- .select("*", { count: "exact" }).eq("tenant_id", input.tenantId).order(...)
-- .range(from, to)`. No lateral join, no tracking-health left join, no
-- app.is_shipment_tracking_entitled call -- none of those affect which rows match
-- (the left join is keyed on shipment_order_id, unique per row, so it can neither add
-- nor drop a row; the tracking-entitlement call is a per-row output column, never a
-- filter) -- see this migration''s own header for the full equivalence argument and
-- for why this count is not folded into a count(*) over() column on the data query.
create function app.count_dispatch_board_shipment_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns bigint
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return (
    select count(*)
    from app.shipment_orders so
    where so.tenant_id = p_tenant_id
      and so.status in ('assigned', 'dispatched', 'in_transit')
      and app.can_access_record(
        p_actor_auth_user_id,
        so.tenant_id,
        so.owner_user_id,
        app.lead_record_scope_org_unit_ids(so.org_unit_id),
        null
      )
  );
end;
$$;

comment on function app.count_dispatch_board_shipment_orders(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3, dispatch): the exact-count half of server/queries/dispatch-board.ts''s listDispatchBoard (lines 42-47), replacing a broken .from("dispatch_board_queue") count:exact request (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Filter reproduces tenant_id + status in (assigned, dispatched, in_transit) plus app.shipment_orders'' own current shipment_orders_select_scoped predicate (app.can_access_record against an explicit actor id, never the session''s own auth context, for the service_role-BYPASSRLS reason this migration''s own header explains), matching app.dispatch_board_queue''s own WHERE clause exactly -- the view''s own left join and tracking-entitlement projection are output-only and provably cannot change which rows this WHERE clause matches. Deliberately has no lateral join to app.evaluate_dispatch_readiness, for the identical O(N)-avoidance reason app.count_dispatch_ready_shipment_orders documents (this migration''s own header, "WHY FOUR NEW FUNCTIONS"). Returns 0, never an exception, for a tenant/actor with zero visible matching rows.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.count_dispatch_board_shipment_orders with an identical grant
-- set, never a reimplementation.
create function public.count_dispatch_board_shipment_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.count_dispatch_board_shipment_orders(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.count_dispatch_board_shipment_orders(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.count_dispatch_board_shipment_orders with an identical grant set, never a reimplementation.';

revoke execute on function app.count_dispatch_board_shipment_orders(uuid, uuid) from public;
grant execute on function app.count_dispatch_board_shipment_orders(uuid, uuid) to authenticated, service_role;

revoke execute on function public.count_dispatch_board_shipment_orders(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.count_dispatch_board_shipment_orders(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 4. app.list_dispatch_board -- the data half of server/queries/dispatch-board.ts:
--    42-47 (listDispatchBoard)
-- ===========================================================================
-- Replaces the data-fetch half of `.from("dispatch_board_queue").select("*", { count:
-- "exact" }).eq("tenant_id", input.tenantId).order("planned_pickup_at", { ascending:
-- true, nullsFirst: false }).range(from, to)`. Reproduces app.dispatch_board_queue''s
-- own view body verbatim (20260729300000:85-107), including its lateral readiness
-- join, its left join to app.shipment_tracking_health, and its
-- app.is_shipment_tracking_entitled(...) call (by reference -- see RULE C above for
-- why this is safe against that helper''s own later real-implementation rewrite). id
-- is added as a secondary ORDER BY key for the same pagination-determinism reason as
-- app.list_dispatch_ready_queue above.
--
-- NOTE (disclosed, out of this task''s scope): unlike app.shipment_orders'' status=
-- ''assigned''-only partial index (shipment_orders_tenant_assigned_pickup_id_idx,
-- 20260907170000), there is no covering index for this function''s own wider status
-- in (assigned, dispatched, in_transit) predicate ordered by planned_pickup_at -- a
-- natural follow-up migration (an analogous partial index with `where status in
-- (''assigned'', ''dispatched'', ''in_transit'')`) is flagged here, not built, since
-- this task''s own scope is the Option-2 wrapper swap, not new index tuning; this
-- function''s own LIMIT/OFFSET-under-lateral-join cost is therefore bounded by
-- offset+page_size lateral calls the same way the ready queue''s is, but without an
-- index to make the underlying sort itself cheap for a tenant with many matching
-- rows.
create function app.list_dispatch_board(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  shipment_number text,
  idempotency_key text,
  status text,
  held_from_status text,
  shipper_account_id uuid,
  consignee_snapshot jsonb,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb,
  service_type text,
  mode text,
  origin text,
  destination text,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  basis_quantity numeric,
  basis_weight_kg numeric,
  basis_volume_cbm numeric,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  split_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  leg_network_status text,
  is_ready boolean,
  blockers jsonb,
  has_active_assignment boolean,
  tracking_status text,
  authoritative_source_type text,
  last_position_at timestamptz,
  freshness_status text,
  accuracy_meters numeric,
  fallback_active boolean,
  tracking_entitled boolean,
  tracking_exception_count integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
  v_page integer;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_limit := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_page := greatest(coalesce(p_page, 1), 1);

  return query
    select
      so.id,
      so.tenant_id,
      so.job_order_id,
      so.shipment_number,
      so.idempotency_key,
      so.status,
      so.held_from_status,
      so.shipper_account_id,
      so.consignee_snapshot,
      so.notify_party_snapshot,
      so.cargo_service_snapshot,
      so.service_type,
      so.mode,
      so.origin,
      so.destination,
      so.planned_pickup_at,
      so.planned_delivery_at,
      so.basis_quantity,
      so.basis_weight_kg,
      so.basis_volume_cbm,
      so.allocated_quantity,
      so.allocated_weight_kg,
      so.allocated_volume_cbm,
      so.split_reason,
      so.owner_user_id,
      so.org_unit_id,
      so.record_version,
      so.created_by,
      so.created_at,
      so.updated_at,
      so.leg_network_status,
      case when so.status = 'assigned' then r.is_ready else null end,
      case when so.status = 'assigned' then r.blockers else null end,
      exists (
        select 1 from app.resource_assignments ra
        where ra.shipment_order_id = so.id and ra.is_current and ra.status = 'active'
      ),
      coalesce(th.tracking_status, 'not_tracked'),
      th.authoritative_source_type,
      th.last_position_at,
      coalesce(th.freshness_status, 'unknown'),
      th.accuracy_meters,
      coalesce(th.fallback_active, false),
      app.is_shipment_tracking_entitled(so.tenant_id),
      coalesce(th.tracking_exception_count, 0)
    from app.shipment_orders so
    cross join lateral app.evaluate_dispatch_readiness(so.id) as r
    left join app.shipment_tracking_health th on th.shipment_order_id = so.id
    where so.tenant_id = p_tenant_id
      and so.status in ('assigned', 'dispatched', 'in_transit')
      and app.can_access_record(
        p_actor_auth_user_id,
        so.tenant_id,
        so.owner_user_id,
        app.lead_record_scope_org_unit_ids(so.org_unit_id),
        null
      )
    order by so.planned_pickup_at asc nulls last, so.id asc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_dispatch_board(uuid, uuid, integer, integer) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3, dispatch): the paginated data half of server/queries/dispatch-board.ts''s listDispatchBoard (lines 42-47), replacing a broken .from("dispatch_board_queue") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Reproduces app.dispatch_board_queue''s own current view body verbatim against its base table -- status in (assigned, dispatched, in_transit) plus app.shipment_orders'' own current shipment_orders_select_scoped predicate (app.can_access_record against an explicit actor id, never the session''s own auth context, for the service_role-BYPASSRLS reason this migration''s own header explains) -- including the identical cross join lateral app.evaluate_dispatch_readiness(so.id), the identical left join to app.shipment_tracking_health, and the identical by-reference call to app.is_shipment_tracking_entitled (tracking columns stay honest and feature-gated exactly as the view''s own header describes -- never a fabricated live position). p_page/p_page_size are clamped server-side (1-100) as defense in depth for a directly-callable RPC, mirroring the TS layer''s own existing MAX_PAGE_SIZE=100 clamp. order by planned_pickup_at asc nulls last, id asc adds an id tie-break beyond the original single-column ordering for determinism across page fetches. Deliberately returns no total_count column -- the exact count is the separate, lateral-free app.count_dispatch_board_shipment_orders, matching app.list_dispatch_ready_queue''s own sibling design (see this migration''s own header for the full reasoning, including the disclosed extrapolation this choice represents). Returns an empty set, never an exception, for a tenant/actor with zero visible rows or a page past the last row.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_dispatch_board with an identical grant set, never a
-- reimplementation.
create function public.list_dispatch_board(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  shipment_number text,
  idempotency_key text,
  status text,
  held_from_status text,
  shipper_account_id uuid,
  consignee_snapshot jsonb,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb,
  service_type text,
  mode text,
  origin text,
  destination text,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  basis_quantity numeric,
  basis_weight_kg numeric,
  basis_volume_cbm numeric,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  split_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  leg_network_status text,
  is_ready boolean,
  blockers jsonb,
  has_active_assignment boolean,
  tracking_status text,
  authoritative_source_type text,
  last_position_at timestamptz,
  freshness_status text,
  accuracy_meters numeric,
  fallback_active boolean,
  tracking_entitled boolean,
  tracking_exception_count integer
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_dispatch_board(p_tenant_id, p_actor_auth_user_id, p_page, p_page_size);
$wrap$;

comment on function public.list_dispatch_board(uuid, uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_dispatch_board with an identical grant set, never a reimplementation.';

revoke execute on function app.list_dispatch_board(uuid, uuid, integer, integer) from public;
grant execute on function app.list_dispatch_board(uuid, uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_dispatch_board(uuid, uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_dispatch_board(uuid, uuid, integer, integer) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
--
-- server/queries/basic-dispatch.ts
-- ---------------------------------------------------------------------------
-- BasicDispatchQueryClient (line 18) is already `Pick<SupabaseClient, "from" |
-- "rpc">` -- "from" is no longer used anywhere in this file after this change (the
-- only other exported function, getDispatchReadiness, already used "rpc" only); it
-- MAY be narrowed to `Pick<SupabaseClient, "rpc">` as a follow-on cleanup, but this is
-- optional and not required for correctness -- leaving the wider Pick in place is
-- harmless.
--
-- Replace the entire body of listDispatchReadyQueue (currently lines 79-112) with:
--
--   export async function listDispatchReadyQueue(client: BasicDispatchQueryClient, input: ListDispatchReadyQueueInput): Promise<ListDispatchReadyQueueResult> {
--     const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
--     const page = Math.max(Math.trunc(input.page), 1);
--
--     const { data: count, error: countError } = await client.rpc("count_dispatch_ready_shipment_orders", {
--       p_tenant_id: input.tenantId,
--       p_actor_auth_user_id: input.actorAuthUserId,
--     });
--
--     if (countError) {
--       throw new BasicDispatchQueryError(countError.message);
--     }
--
--     const { data, error } = await client.rpc("list_dispatch_ready_queue", {
--       p_tenant_id: input.tenantId,
--       p_actor_auth_user_id: input.actorAuthUserId,
--       p_page: page,
--       p_page_size: pageSize,
--     });
--
--     if (error) {
--       throw new BasicDispatchQueryError(error.message);
--     }
--
--     return {
--       rows: (data ?? []).map((row: Record<string, unknown>) => parseDispatchReadyQueueRow(row)),
--       totalCount: Number(count ?? 0),
--       page,
--       pageSize,
--     };
--   }
--
-- IMPORTANT input-shape change: `ListDispatchReadyQueueInput` (currently lines 23-27)
-- does NOT carry an `actorAuthUserId` field today -- only `tenantId`, `page`,
-- `pageSize`. Both new RPCs require an explicit `p_actor_auth_user_id` (RULE A, every
-- authenticated-reachable function in this series). `ListDispatchReadyQueueInput`
-- MUST gain a new required field:
--
--   export interface ListDispatchReadyQueueInput {
--     readonly tenantId: string;
--     readonly actorAuthUserId: string;
--     readonly page: number;
--     readonly pageSize?: number;
--   }
--
-- This is a breaking change to listDispatchReadyQueue''s own call signature -- every
-- real caller must be found (repo-wide grep for "listDispatchReadyQueue(") and updated
-- to pass the calling session''s own resolved auth user id (the same
-- `access.authUserId` convention ATW-030 already established for every other
-- actorAuthUserId call site in app/), not attempted in this SQL-only draft. This
-- mirrors getDispatchReadiness''s own existing GetDispatchReadinessInput shape in the
-- same file (already carries actorAuthUserId, lines 117-121 of the contract file),
-- so the two exported functions in this module become consistent with each other for
-- the first time.
--
-- No change needed to server/contracts/basic-dispatch/basic-dispatch.ts --
-- parseDispatchReadyQueueRow already reads exactly the snake_case column names both
-- new RPC functions return (id, tenant_id, ..., held_from_status, ...,
-- leg_network_status, is_ready, blockers); the RPC row shape is identical to the
-- view''s own column names the function it replaces already consumed.
--
-- `count` in `client.rpc("count_dispatch_ready_shipment_orders", ...)` comes back as
-- a bare scalar in `data` (the function RETURNS bigint, not a table/set) -- NOT an
-- array, unlike every RETURNS TABLE/RETURNS SETOF call elsewhere in this file/series.
-- `Number(count ?? 0)` handles both a JS number and (for a very large bigint
-- PostgREST may serialize as a numeric string) a numeric string uniformly, matching
-- how every other `total_count`-style field in this series is already read (e.g.
-- portal-users.ts:80, `Number(rows[0]?.total_count)`).
--
-- Live call sites needing a change: repo-wide grep for "listDispatchReadyQueue(" for
-- the actual list to update was not re-run as part of this SQL-only draft -- do this
-- before applying, since every caller must now pass actorAuthUserId or the TS build
-- will fail (a compile-time signature change, not merely a runtime behavior change).
--
-- server/queries/dispatch-board.ts
-- ---------------------------------------------------------------------------
-- DispatchBoardQueryClient (currently line 10) is `.from()`-only today
-- (`Pick<SupabaseClient, "from">`). Replace it entirely:
--
--   Before:
--     export type DispatchBoardQueryClient = Pick<SupabaseClient, "from">;
--
--   After:
--     export type DispatchBoardQueryClient = Pick<SupabaseClient, "rpc">;
--
-- Replace the entire body of listDispatchBoard (currently lines 36-59) with:
--
--   export async function listDispatchBoard(client: DispatchBoardQueryClient, input: ListDispatchBoardInput): Promise<ListDispatchBoardResult> {
--     const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
--     const page = Math.max(Math.trunc(input.page), 1);
--
--     const { data: count, error: countError } = await client.rpc("count_dispatch_board_shipment_orders", {
--       p_tenant_id: input.tenantId,
--       p_actor_auth_user_id: input.actorAuthUserId,
--     });
--
--     if (countError) {
--       throw new DispatchBoardQueryError(countError.message);
--     }
--
--     const { data, error } = await client.rpc("list_dispatch_board", {
--       p_tenant_id: input.tenantId,
--       p_actor_auth_user_id: input.actorAuthUserId,
--       p_page: page,
--       p_page_size: pageSize,
--     });
--
--     if (error) {
--       throw new DispatchBoardQueryError(error.message);
--     }
--
--     return {
--       rows: (data ?? []).map((row: Record<string, unknown>) => parseDispatchBoardRow(row)),
--       totalCount: Number(count ?? 0),
--       page,
--       pageSize,
--     };
--   }
--
-- IMPORTANT input-shape change: `ListDispatchBoardInput` (currently lines 15-19) does
-- NOT carry an `actorAuthUserId` field today. It MUST gain one, identically to
-- ListDispatchReadyQueueInput above:
--
--   export interface ListDispatchBoardInput {
--     readonly tenantId: string;
--     readonly actorAuthUserId: string;
--     readonly page: number;
--     readonly pageSize?: number;
--   }
--
-- This is also a breaking change to listDispatchBoard''s own call signature -- every
-- real caller (repo-wide grep for "listDispatchBoard(") must be updated to pass the
-- calling session''s own resolved auth user id, not attempted in this SQL-only draft.
--
-- No change needed to server/contracts/dispatch-board/dispatch-board.ts --
-- parseDispatchBoardRow already reads exactly the snake_case column names
-- app.list_dispatch_board returns (identical to app.dispatch_board_queue''s own
-- column names).
--
-- Both files: no test-file rewrite attempted here (server/queries/basic-
-- dispatch.test.ts, server/queries/dispatch-board.test.ts if either exists) -- both
-- currently mock a `.from()`-shaped client and will need updating to mock two
-- `.rpc(...)` calls each (count, then list) instead, per this task''s own SQL-only
-- scope (matching this series'' established disclaimer for every prior batch''s own
-- *.test.ts files).
--
-- ===========================================================================
-- OPEN DESIGN QUESTIONS / RISKS FOR THE VERIFY PASS (summary of flags already raised
-- inline above, collected here for visibility)
-- ===========================================================================
-- 1. The count/list split for BOTH screens (not just the ready queue, which
--    20260907170000 already justified) is this draft''s own extrapolation. Re-check:
--    is symmetric treatment actually correct, or should app.list_dispatch_board keep
--    the single-query count(*) over() shape (matching app.list_portal_users literally)
--    and disclose the O(N) cost as a separate, later-fixed item instead? This draft
--    chose symmetry; a stricter reading of "follow the established pattern" could
--    reasonably disagree.
-- 2. listDispatchReadyQueue/listDispatchBoard''s own TS input shape gains a new
--    required `actorAuthUserId` field -- a breaking signature change this draft did
--    not chase down every call site for (explicitly out of this SQL-only draft''s
--    scope, per the TS INTEGRATION section above). The verify/apply pass MUST
--    repo-wide grep both function names before applying, or the TS build will fail
--    silently-uncaught until compile time.
-- 3. No new covering index is added for app.list_dispatch_board''s own wider status
--    in (...) predicate (see the disclosed NOTE inline above, function 4) -- flagged,
--    not fixed, as out of this task''s Option-2-wrapper scope.
-- 4. app.is_shipment_tracking_entitled is called by reference rather than inlined,
--    which is deliberate (RULE C) -- but this means app.list_dispatch_board''s own
--    behavior for the tracking_entitled column will silently change the moment
--    ATW-226A''s real implementation (already live, 20260729340000) resolves a real
--    per-tenant config value, with no further action needed here; worth the verify
--    pass double-checking this is the intended (and not merely accidental) coupling.

-- ===========================================================================
-- PART 2 of 2: JOB ORDER + JOB ORDER LINEAGE (job-order.ts, job-order-lineage.ts)
-- ===========================================================================

-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 3 batch 1 (Job Order +
-- Job Order Lineage reads, this migration's own Part 2 of 2). Continues the same
-- Design->Verify->Fix pipeline cluster 0 (batches 1-5), cluster 1 (batch 1), and
-- cluster 2 (batch 1) already
-- established: supabase/config.toml's `schemas = ["public", "graphql_public"]` never
-- exposes the "app" Postgres schema to PostgREST, so every `.from()` read against an
-- `app.*` table/view in server/queries/*.ts has never worked in production
-- (PGRST106 "Invalid schema: app" for every caller). The fix is the Option-2 wrapper:
-- a new `app.<name>` SECURITY DEFINER function reproducing the read plus its
-- RLS-equivalent authority check in SQL, a thin `public.<name>` pass-through (the only
-- PostgREST-reachable surface), then the TS caller switches `.from()` -> `.rpc()`.
--
-- SCOPE (2 files, 5 broken `.from()` reads, both against field-masked `_directory`
-- VIEWs):
--
--   1. server/queries/job-order.ts
--        getJobOrder(client, jobOrderId)                    line 65
--        getJobOrderForHandoff(client, sourceHandoffId)      line 77
--        listJobOrders(client, input)                        lines 94-99
--      all three against app.job_orders_directory.
--
--   2. server/queries/job-order-lineage.ts
--        getJobOrderHandoffForQuotation(client, quotationId) line 22
--        listJobOrderHandoffs(client, tenantId, limit=50)    lines 34-39
--      both against app.job_order_handoffs_directory.
--
-- ===========================================================================
-- RESEARCH: app.job_orders_directory (VIEW) + job_orders_select_scoped (POLICY)
-- ===========================================================================
-- View definition -- ONE, ONLY-EVER hit repo-wide for "create view app.job_orders_
-- directory" / "create or replace view app.job_orders_directory" (grepped sorted by
-- filename across every file in supabase/migrations/*.sql):
--   supabase/migrations/20260727090000_create_operations_job_order.sql:413-426.
-- Never superseded -- the body below is its current, only-ever definition.
--
--   create view app.job_orders_directory as
--   select
--     jo.id, jo.tenant_id, jo.job_number, jo.source_handoff_id, jo.quotation_id, jo.account_id,
--     jo.customer_snapshot, jo.cargo_service_snapshot,
--     case when app.has_view_selling_price(jo.tenant_id) then jo.revenue_snapshot else null end as revenue_snapshot,
--     not app.has_view_selling_price(jo.tenant_id) as revenue_masked,
--     jo.contract_snapshot,
--     case when app.has_view_cost(jo.tenant_id) then jo.credit_snapshot else null end as credit_snapshot,
--     not app.has_view_cost(jo.tenant_id) as credit_masked,
--     jo.acceptance_snapshot, jo.status, jo.owner_user_id, jo.org_unit_id, jo.record_version,
--     jo.created_by, jo.created_at, jo.updated_at
--   from app.job_orders jo
--   where app.can_access_record(auth.uid(), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null);
--
-- MASKING (confirmed against the file's own header comment, server/queries/job-order.ts:1-6,
-- and app.job_orders' own column grant at 20260727090000:454-458): `authenticated` has no
-- direct column grant on revenue_snapshot/credit_snapshot on the base table app.job_orders
-- -- the table-level grant is an explicit column list that omits exactly those two columns.
-- The view nulls them out (revenue_masked/credit_masked=true) per-caller via
-- app.has_view_selling_price/app.has_view_cost. Every other column is passed through
-- unmasked. The RETURNS TABLE column lists below reproduce this view's SELECT list
-- 1:1 (21 columns, same names/order) -- never the base table's own row type, which
-- would leak the two masked columns unconditionally to every caller regardless of
-- entitlement.
--
-- RLS predicate (RULE B) -- repo-wide grep, sorted by filename, for both
-- "create policy|alter policy" combined with the bare name "job_orders_select_scoped":
--   supabase/migrations/20260727090000_create_operations_job_order.sql:434-436 (original
--     CREATE, the only hit that is an actual policy statement)
--   supabase/migrations/20260910000000_close_o1_query_layer_cluster1_batch1_finance_reads.sql:1676
--     (a PROSE mention inside that migration's own header, citing this exact policy as
--     never-rewritten precedent for its own app.job_profitability_directory work -- not a
--     second policy statement).
-- No rewrite of this policy exists anywhere in the tree. Its current (and only-ever) body:
--
--   create policy job_orders_select_scoped on app.job_orders
--     for select to authenticated
--     using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null));
--
-- This is character-for-character the same predicate the view's own WHERE clause already
-- reproduces (modulo the `(select auth.uid())` initplan-hoisting idiom, which is an RLS-only
-- optimization with no semantic difference from the view's bare `auth.uid()`). The three new
-- functions below re-express this predicate against the base table app.job_orders with an
-- explicit p_actor_auth_user_id argument in place of both auth.uid() call sites (the view's
-- own implicit-session WHERE clause, and has_view_selling_price/has_view_cost's own
-- `default auth.uid()` trailing parameter) -- the same substitution cluster 1 batch 1's
-- app.get_shipment_actual_cost already established for this identical
-- masked-directory-view-under-RPC shape.
--
-- ===========================================================================
-- RESEARCH: app.job_order_handoffs_directory (VIEW) + its select policy
-- ===========================================================================
-- View definition -- ONE, ONLY-EVER hit repo-wide for "create view app.job_order_handoffs_
-- directory" / "create or replace view app.job_order_handoffs_directory":
--   supabase/migrations/20260724340000_create_commercial_job_order_lineage.sql:272-293.
--
--   create view app.job_order_handoffs_directory as
--   select
--     h.id, h.tenant_id, h.quotation_id, h.account_id, h.purpose, h.schema_version, h.status,
--     case when app.has_view_selling_price(h.tenant_id) then h.payload else null end as payload,
--     case when app.has_view_selling_price(h.tenant_id) then h.payload_hash else null end as payload_hash,
--     not app.has_view_selling_price(h.tenant_id) as payload_masked,
--     h.downstream_reference, h.delivered_at, h.prepared_by_auth_user_id, h.owner_user_id,
--     h.org_unit_id, h.created_by, h.created_at
--   from app.job_order_handoffs h
--   where app.can_access_record(auth.uid(), h.tenant_id, h.owner_user_id, app.lead_record_scope_org_unit_ids(h.org_unit_id), null);
--
-- MASKING (per the file's own header, server/queries/job-order-lineage.ts:1-6, and
-- app.job_order_handoffs' own column grant at 20260724340000:315-318): `authenticated` has
-- no direct column grant on payload/payload_hash on the base table -- masked wholesale
-- (payload_masked=true) for any caller lacking COM:View selling price, exactly like
-- job_orders_directory's revenue_snapshot mask (same underlying permission, reused rather
-- than a redundant OPS-level pair, per that view's own comment). The RETURNS TABLE column
-- lists below reproduce this view's SELECT list 1:1 (17 columns).
--
-- Its select policy is named job_order_handoffs_select_scoped, confirmed by reading the
-- view/table definition itself rather than assumed (the task's own caution to verify, not
-- guess, this name). Repo-wide grep, sorted by filename, for "create policy|alter policy"
-- combined with the bare name "job_order_handoffs_select_scoped" surfaces exactly ONE hit,
-- the original CREATE -- no rewrite exists anywhere in the tree:
--
--   supabase/migrations/20260724340000_create_commercial_job_order_lineage.sql:300-302
--
--   create policy job_order_handoffs_select_scoped on app.job_order_handoffs
--     for select to authenticated
--     using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null));
--
-- Identical shape to job_orders_select_scoped (same helper calls, same argument order),
-- against this sibling table's own base columns. Re-expressed below the same way, with an
-- explicit p_actor_auth_user_id argument.
--
-- ===========================================================================
-- RULE C: helper functions cited above, each checked against its OWN most recent
-- `create or replace function`, not merely the first migration that defines it
-- ===========================================================================
-- * app.can_access_record -- repo-wide grep for "create or replace function app\.
--   can_access_record|create function app\.can_access_record" (actual CREATE
--   statements, not prose mentions) finds exactly TWO hits, sorted by filename:
--     20260716110430_create_field_record_access.sql:31        (original CREATE)
--     20260723180000_create_commercial_sales_pipeline.sql:50  (CREATE OR REPLACE, COM-146)
--   No later replace exists. COM-146's patched body (the current, live definition) is
--   the one this migration's own functions call:
--     app.has_active_tenant_membership(p_tenant_id, p_auth_user_id)
--     and coalesce(
--       app.is_supreme_admin(p_auth_user_id)
--       or (p_owner_user_id is not null and p_owner_user_id = p_auth_user_id)
--       or exists (... u.org_unit_id = any(p_shared_org_unit_ids) ...)
--       or (... customer_account_ref match ...),
--       false
--     )
--   Signature: (p_auth_user_id uuid, p_tenant_id uuid, p_owner_user_id uuid,
--   p_shared_org_unit_ids uuid[] default '{}', p_customer_account_ref text default null).
--   Both job_orders_select_scoped and job_order_handoffs_select_scoped call it with a
--   literal `null` fifth argument (no customer-account-ref scope for either table) --
--   reproduced identically below.
--
-- * app.has_view_selling_price -- repo-wide grep for the same two CREATE-statement
--   patterns finds exactly ONE hit: 20260723210000_create_commercial_opportunity_
--   management.sql:134. Never replaced. Signature: (p_tenant_id uuid, p_auth_user_id
--   uuid default auth.uid()). Every call below supplies p_actor_auth_user_id explicitly
--   as the second, positional argument rather than relying on the default -- the same
--   fix cluster 1 batch 1's app.get_shipment_actual_cost applied for app.has_view_
--   actual_cost's identical default-session-argument shape (a SECURITY DEFINER RPC
--   should not depend on the calling session's own auth.uid() reading correctly inside
--   a nested call; the explicit actor argument is the one already verified via RULE A).
--
-- * app.has_view_cost -- repo-wide grep finds exactly ONE hit: 20260724090000_create_
--   commercial_costing_request.sql:144. Never replaced (two later migrations, cluster 0
--   batch 3 and batch 5, each independently re-ran and recorded the identical zero-
--   further-hits result -- cited here as corroboration, not re-derived from them).
--   Signature: (p_tenant_id uuid, p_auth_user_id uuid default auth.uid()) -- same
--   explicit-argument substitution as has_view_selling_price above.
--
-- * app.lead_record_scope_org_unit_ids -- repo-wide grep finds exactly ONE hit:
--   20260723090000_create_commercial_lead_management.sql:164. Never replaced.
--   Signature: (p_org_unit_id uuid) returns uuid[] -- the lead's own org unit plus every
--   ancestor, the exact "shared scope" set app.can_access_record's fourth argument
--   expects. Despite its "lead_" name prefix this is the repo-wide shared-org-unit-scope
--   helper every non-lead table's own select-scoped policy also calls (job_orders_
--   select_scoped and job_order_handoffs_select_scoped both do, per RULE B above) --
--   confirmed by reading its own definition/comment, not assumed from the name.
--
-- * app.assert_actor_is_session_identity -- repo-wide grep for "create or replace
--   function app\.assert_actor_is_session_identity|create function app\.assert_actor_
--   is_session_identity" finds exactly ONE hit: 20260730440000_harden_actor_identity_
--   session_crosscheck.sql:59 (itself already a CREATE OR REPLACE over an unmarked prior
--   signature -- see that migration's own header). Every later mention repo-wide (cluster
--   0 batch 2, cluster 1 batch 1, cluster 2 batch 1) is a prose citation of this same,
--   still-current body, not a further replace. Signature: (p_actor_auth_user_id uuid)
--   returns void -- raises actor_identity_mismatch (errcode insufficient_privilege) only
--   when a genuine authenticated session's auth.uid() disagrees with the claimed actor;
--   a no-op for service_role/superuser/nested-definer calls (session identity NULL).
--
-- ===========================================================================
-- RULE A -- every function below takes an actor parameter reachable by `authenticated`
-- ===========================================================================
-- None of the five original TS functions (getJobOrder, getJobOrderForHandoff,
-- listJobOrders, getJobOrderHandoffForQuotation, listJobOrderHandoffs) accepts an actor/
-- auth-user-id parameter today -- RLS alone was the authority check, running under the
-- caller's own session. Moving that check inside a SECURITY DEFINER function means it can
-- no longer rely on an implicit session; each function below therefore adds a new,
-- REQUIRED `p_actor_auth_user_id uuid` parameter, and calls
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as the first
-- executable statement (plpgsql) before any lookup -- exactly ATW-031/032, applied
-- identically to every one of the ~45 prior functions in this series. This is a REAL,
-- BREAKING SIGNATURE CHANGE to all five TS functions -- see the TS INTEGRATION block at
-- the end of this file for the exact new call shape at every one of their call sites.
--
-- ===========================================================================
-- RAISE-vs-silent-zero-rows (explicit instruction for this batch, followed here)
-- ===========================================================================
-- All five reads below are "list/lookup what I can see" reads -- three are single-record
-- lookups (by id, by source_handoff_id, by quotation_id), two are tenant-scoped lists.
-- None raises for a denied or nonexistent record/tenant; all return zero rows / null
-- silently, matching each original `.from()` read's own current behavior
-- (`.maybeSingle()` -> null; bare `.select()` -> `[]`) exactly, and requiring no TS
-- error-handling change beyond the `.from()` -> `.rpc()` call shape itself.
--
-- This is a deliberate departure from this series' OTHER "list for one named,
-- caller-supplied tenant" precedent (app.list_tenant_users / app.list_accounts / app.
-- list_portal_users' own non-member case), which DOES raise `insufficient_authority` for
-- a caller with zero standing in the named tenant -- reasoned here, not merely obeyed as
-- an instruction: those functions gate on a single, per-request, non-row-varying check
-- (`app.has_active_tenant_membership`), so collapsing "not a member" into "tenant has zero
-- rows" would erase a real distinction an admin-facing lifecycle list needs to surface.
-- listJobOrders/listJobOrderHandoffs are different in kind: app.can_access_record varies
-- PER ROW (exact owner match, shared org-unit membership, or customer-account-ref), so an
-- authenticated tenant member with no rows in their own visible scope is an entirely
-- ordinary, expected outcome -- indistinguishable in spirit from "this job order has no
-- billing-readiness handoffs yet" (app.list_billing_readiness_handoffs' own silent-empty
-- precedent), just scoped to a tenant's worth of parent rows instead of one parent row's
-- own children. No pre-flight has_active_tenant_membership raise is added for either list
-- function, matching app.list_portal_users' own identical reasoning for this identical
-- per-row-varying-predicate shape.
--
-- ===========================================================================
-- GRANT PARITY (ISS-2026-309) -- uniform convention, independently re-confirmed
-- ===========================================================================
-- Every app.* function below: `revoke execute on function app.<fn>(...) from public;`
-- then `grant execute on function app.<fn>(...) to authenticated, service_role;` -- the
-- SAME two roles this entire ~45-function series has granted every single time
-- (independently re-verified at cluster 2 batch 1, 20260910010000:681-700, against a
-- sweep of every `grant execute on function app.*` line the series has produced:
-- zero exceptions, regardless of what each function's own underlying base table/view
-- happened to grant). Applied here even though app.job_orders_directory/app.job_order_
-- handoffs_directory's own `grant select ... to authenticated, service_role;` already
-- matches this pair exactly (20260727090000:463, 20260724340000:322) -- no departure
-- to reconcile in this batch either way.
--
-- Every public.* wrapper below: `revoke execute on function public.<fn>(...) from
-- anon, authenticated, service_role, public;` (all four -- a bare `revoke ... from
-- public` does NOT strip the `anon`/`authenticated` EXECUTE grants Supabase's own ALTER
-- DEFAULT PRIVILEGES rule applies to every new function in schema public at CREATE time,
-- per ISS-2026-309/20260830200000_correct_public_wrapper_grant_parity.sql) then
-- `grant execute on function public.<fn>(...) to authenticated, service_role;` -- the
-- identical subset its app.* counterpart itself grants, never a reimplementation.
--
-- ===========================================================================
-- check-rls-initplan.ts false-positive avoidance
-- ===========================================================================
-- Per this repository's own established practice (first applied cluster 0 batches 3/5,
-- restated at every batch since): every `comment on function ... is '...'` string below
-- avoids combining the literal phrase "create policy"/"alter policy" with a bare,
-- parenthesized `auth.uid()`/`auth.jwt()` mention in the same string -- e.g. "no rewrite
-- of this policy exists" rather than naming the ALTER/CREATE POLICY mechanism directly
-- next to a parenthesized auth.uid() call. The guard itself is never suppressed, only the
-- prose reworded; this header's own `--`-comment prose above is unaffected (the scanner's
-- own blankLineComments step blanks every `--` line before parsing).
--
-- ===========================================================================
-- 1. app.get_job_order -- replaces server/queries/job-order.ts:65 (getJobOrder)
-- ===========================================================================
-- Replaces: `.from("job_orders_directory").select("*").eq("id", jobOrderId).maybeSingle()`.
-- app.job_orders is the base table; `id` is its primary key, so this filter alone already
-- bounds the result to at most one row -- no LIMIT needed.
create function app.get_job_order(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_number text,
  source_handoff_id uuid,
  quotation_id uuid,
  account_id uuid,
  customer_snapshot jsonb,
  cargo_service_snapshot jsonb,
  revenue_snapshot jsonb,
  revenue_masked boolean,
  contract_snapshot jsonb,
  credit_snapshot jsonb,
  credit_masked boolean,
  acceptance_snapshot jsonb,
  status text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select
    jo.id, jo.tenant_id, jo.job_number, jo.source_handoff_id, jo.quotation_id, jo.account_id,
    jo.customer_snapshot, jo.cargo_service_snapshot,
    case when app.has_view_selling_price(jo.tenant_id, p_actor_auth_user_id) then jo.revenue_snapshot else null end,
    not app.has_view_selling_price(jo.tenant_id, p_actor_auth_user_id),
    jo.contract_snapshot,
    case when app.has_view_cost(jo.tenant_id, p_actor_auth_user_id) then jo.credit_snapshot else null end,
    not app.has_view_cost(jo.tenant_id, p_actor_auth_user_id),
    jo.acceptance_snapshot, jo.status, jo.owner_user_id, jo.org_unit_id, jo.record_version,
    jo.created_by, jo.created_at, jo.updated_at
  from app.job_orders jo
  where jo.id = p_job_order_id
    and app.can_access_record(
      p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id,
      app.lead_record_scope_org_unit_ids(jo.org_unit_id), null
    );
end;
$$;

comment on function app.get_job_order(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3): one Job Order by id, replacing server/queries/job-order.ts:65''s broken .from("job_orders_directory") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032, RULE A -- this function''s p_actor_auth_user_id parameter is new; the original TS function took none). Row-visibility filter (app.can_access_record against tenant/owner/org-unit scope) reproduces job_orders_select_scoped''s own current predicate verbatim -- confirmed via repo-wide grep that no rewrite of this policy exists (RULE B). The revenue_snapshot/credit_snapshot CASE-WHEN masks and revenue_masked/credit_masked flags are copied verbatim from app.job_orders_directory''s own current view definition, re-expressed against the base table with an explicit p_actor_auth_user_id instead of app.has_view_selling_price/app.has_view_cost''s own default-session argument (RULE C: both helpers independently confirmed never redefined since their own original creation). id is app.job_orders'' own primary key, so the WHERE filter alone already bounds this to at most one row. Returns zero rows (never an exception) for a nonexistent job_order_id or an actor who cannot reach that job order''s tenant/owner/org-unit/customer-account scope -- matching the original RLS-filtered view''s own silent-empty-result posture and the TS layer''s existing .maybeSingle() -> null handling, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_job_order with an identical grant set, never a reimplementation.
create function public.get_job_order(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_number text,
  source_handoff_id uuid,
  quotation_id uuid,
  account_id uuid,
  customer_snapshot jsonb,
  cargo_service_snapshot jsonb,
  revenue_snapshot jsonb,
  revenue_masked boolean,
  contract_snapshot jsonb,
  credit_snapshot jsonb,
  credit_masked boolean,
  acceptance_snapshot jsonb,
  status text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_job_order(p_job_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_job_order(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_job_order with an identical grant set, never a reimplementation.';

revoke execute on function app.get_job_order(uuid, uuid) from public;
grant execute on function app.get_job_order(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_job_order(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_job_order(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.get_job_order_for_handoff -- replaces server/queries/job-order.ts:77
--    (getJobOrderForHandoff)
-- ===========================================================================
-- Replaces: `.from("job_orders_directory").select("*")
-- .eq("source_handoff_id", sourceHandoffId).maybeSingle()`. app.job_orders carries a
-- COMPOSITE unique constraint `job_orders_tenant_handoff_unique unique (tenant_id,
-- source_handoff_id)` (20260727090000:84) -- NOT a bare unique constraint on
-- source_handoff_id alone. In practice source_handoff_id is already effectively unique
-- table-wide: app.prepare_job_order (the ONE gated entrypoint that inserts into
-- app.job_orders -- independently re-verified against its own TRUE latest body,
-- 20260902201000_harden_tenant_id_disclosure_operations.sql, not merely its
-- 20260727090000 origin, plus the two intermediate redefinitions at 20260728190000 and
-- 20260819000000) always sets tenant_id := v_handoff.tenant_id (the referenced
-- handoff''s own tenant) in every one of its own historical bodies, and every direct
-- `insert into app.job_orders` in every db-test/load-test seed script repo-wide does the
-- same -- so no row any application code path has ever produced can pair a given
-- handoff id with any tenant other than that handoff''s own. This is still only an
-- application-level invariant, not a database CHECK/trigger spanning both tables --
-- app.job_orders also carries a direct `grant insert ... to service_role`
-- (20260727090000:460) that bypasses app.prepare_job_order entirely, so a genuine
-- multi-row match (two job_orders rows disagreeing about which tenant one handoff
-- belongs to) remains schema-legal, if never yet exercised anywhere in this repository.
-- ADVERSARIAL VERIFY PASS RESOLUTION (this batch''s own OPEN QUESTION #1, now closed):
-- an earlier draft of this function defensively added `order by created_at desc limit
-- 1`, silently returning "the newest" row on a hypothetical multi-row match. Rejected on
-- review: for this specific ambiguity, "silently pick one" would mean silently handing
-- the caller a DIFFERENT TENANT''s job order data -- exactly the cross-tenant leak class
-- this whole remediation series exists to close, not a merely cosmetic nondeterminism.
-- The function below instead counts matches and RAISES `ambiguous_context`
-- (`check_violation`) when more than one exists, before ever building the result row --
-- matching both the original `.maybeSingle()`''s own throw-on-conflict contract and this
-- codebase''s own established count-then-raise idiom for exactly this shape
-- (`app.resolve_access_context`, PLT-108, 20260716100825_create_principal_
-- memberships.sql:252-255/291-294: `select count(*) into v_match_count ...; elsif
-- v_match_count > 1 then raise exception ''ambiguous_context: ...'' using errcode =
-- ''check_violation''`) -- never a silent pick.
create function app.get_job_order_for_handoff(
  p_source_handoff_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_number text,
  source_handoff_id uuid,
  quotation_id uuid,
  account_id uuid,
  customer_snapshot jsonb,
  cargo_service_snapshot jsonb,
  revenue_snapshot jsonb,
  revenue_masked boolean,
  contract_snapshot jsonb,
  credit_snapshot jsonb,
  credit_masked boolean,
  acceptance_snapshot jsonb,
  status text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_match_count integer;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Adversarial verify pass resolution (see this migration''s own header, section 2):
  -- reproduces `.maybeSingle()`''s own throw-on-conflict contract explicitly, via this
  -- codebase''s established count-then-raise idiom (app.resolve_access_context,
  -- PLT-108), rather than silently returning "the newest" row on a hypothetical
  -- multi-row match.
  select count(*) into v_match_count
  from app.job_orders jo
  where jo.source_handoff_id = p_source_handoff_id
    and app.can_access_record(
      p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id,
      app.lead_record_scope_org_unit_ids(jo.org_unit_id), null
    );

  if v_match_count > 1 then
    raise exception 'ambiguous_context: source_handoff_id % matches % job orders visible to identity %, expected at most one', p_source_handoff_id, v_match_count, p_actor_auth_user_id
      using errcode = 'check_violation';
  end if;

  return query
  select
    jo.id, jo.tenant_id, jo.job_number, jo.source_handoff_id, jo.quotation_id, jo.account_id,
    jo.customer_snapshot, jo.cargo_service_snapshot,
    case when app.has_view_selling_price(jo.tenant_id, p_actor_auth_user_id) then jo.revenue_snapshot else null end,
    not app.has_view_selling_price(jo.tenant_id, p_actor_auth_user_id),
    jo.contract_snapshot,
    case when app.has_view_cost(jo.tenant_id, p_actor_auth_user_id) then jo.credit_snapshot else null end,
    not app.has_view_cost(jo.tenant_id, p_actor_auth_user_id),
    jo.acceptance_snapshot, jo.status, jo.owner_user_id, jo.org_unit_id, jo.record_version,
    jo.created_by, jo.created_at, jo.updated_at
  from app.job_orders jo
  where jo.source_handoff_id = p_source_handoff_id
    and app.can_access_record(
      p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id,
      app.lead_record_scope_org_unit_ids(jo.org_unit_id), null
    );
end;
$$;

comment on function app.get_job_order_for_handoff(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3): the Job Order converted from one Commercial handoff, if one has been prepared, replacing server/queries/job-order.ts:77''s broken .from("job_orders_directory") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032, RULE A -- p_actor_auth_user_id is new; the original TS function took none). Row-visibility filter reproduces job_orders_select_scoped''s own current predicate verbatim, identical to app.get_job_order (RULE B, same never-rewritten policy). Same masking technique and RULE C helper citations as app.get_job_order. source_handoff_id is scoped by a COMPOSITE unique constraint (tenant_id, source_handoff_id), not a bare unique constraint on this column alone, and app.job_orders carries a direct service_role insert grant that bypasses app.prepare_job_order''s own tenant-inheritance invariant -- so a multi-row match, though never yet produced by any code path in this repository, is schema-legal. Adversarial verify pass (see this migration''s own header): counts matches and RAISES `ambiguous_context` (`check_violation`) rather than silently returning "the newest" row, since a real multi-row match here would mean two job_orders rows disagree about which tenant this handoff belongs to -- silently picking one would leak a different tenant''s data, not merely return a nondeterministic pick. This reproduces `.maybeSingle()`''s own throw-on-conflict behavior more faithfully than a silent LIMIT 1 would, surfaced to the TS caller via its existing `if (error) throw` handling with no additional change needed. Returns zero rows (never an exception) for a handoff not yet converted, a nonexistent source_handoff_id, or an actor who cannot reach the resulting job order''s tenant/owner/org-unit/customer-account scope -- matching the original RLS-filtered view''s own silent-empty-result posture and the TS layer''s existing .maybeSingle() -> null handling, unchanged for the not-found case.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_job_order_for_handoff with an identical grant set, never a
-- reimplementation.
create function public.get_job_order_for_handoff(
  p_source_handoff_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_number text,
  source_handoff_id uuid,
  quotation_id uuid,
  account_id uuid,
  customer_snapshot jsonb,
  cargo_service_snapshot jsonb,
  revenue_snapshot jsonb,
  revenue_masked boolean,
  contract_snapshot jsonb,
  credit_snapshot jsonb,
  credit_masked boolean,
  acceptance_snapshot jsonb,
  status text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_job_order_for_handoff(p_source_handoff_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_job_order_for_handoff(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_job_order_for_handoff with an identical grant set, never a reimplementation.';

revoke execute on function app.get_job_order_for_handoff(uuid, uuid) from public;
grant execute on function app.get_job_order_for_handoff(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_job_order_for_handoff(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_job_order_for_handoff(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 3. app.list_job_orders -- replaces server/queries/job-order.ts:94-99 (listJobOrders)
-- ===========================================================================
-- Replaces: `.from("job_orders_directory").select("*", { count: "exact" })
-- .eq("tenant_id", input.tenantId).order("created_at", { ascending: false })
-- .range(from, to)`. Pagination shape follows app.list_portal_users' own established
-- "p_page/p_page_size + count(*) over()" convention (RULE C precedent, 20260910010000:
-- 1383-1436) rather than this schema's newer p_limit/p_after_id keyset idiom, because
-- listJobOrders'' own existing, unchanged external contract (ListJobOrdersResult.
-- totalCount, page, pageSize) needs an EXACT total count and the ability to jump to an
-- arbitrary page number. p_page/p_page_size are clamped server-side (least/greatest),
-- mirroring the TS layer''s own existing MAX_PAGE_SIZE=100/DEFAULT_PAGE_SIZE=50 clamp
-- (job-order.ts:20-21) as defense in depth for a directly-callable RPC. order by
-- created_at desc, id asc adds an id tie-break beyond the original single-column
-- `.order(...)` call, the same determinism-under-pagination discipline app.list_
-- portal_users/app.list_contacts/app.list_leads already apply for this identical
-- "arbitrary-page-jump, must not reorder rows across two page fetches" shape.
create function app.list_job_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_number text,
  source_handoff_id uuid,
  quotation_id uuid,
  account_id uuid,
  customer_snapshot jsonb,
  cargo_service_snapshot jsonb,
  revenue_snapshot jsonb,
  revenue_masked boolean,
  contract_snapshot jsonb,
  credit_snapshot jsonb,
  credit_masked boolean,
  acceptance_snapshot jsonb,
  status text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
  v_page integer;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_limit := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_page := greatest(coalesce(p_page, 1), 1);

  -- No pre-flight has_active_tenant_membership raise -- see this migration''s own
  -- RAISE-vs-silent-zero-rows header section: app.can_access_record varies per row, so a
  -- genuine tenant member with zero visible job orders and a non-member both silently
  -- yield an empty page (total_count 0), exactly as the original RLS-filtered .from()
  -- read''s own no-error-on-non-member behavior, never a thrown error.
  return query
    select
      jo.id, jo.tenant_id, jo.job_number, jo.source_handoff_id, jo.quotation_id, jo.account_id,
      jo.customer_snapshot, jo.cargo_service_snapshot,
      case when app.has_view_selling_price(jo.tenant_id, p_actor_auth_user_id) then jo.revenue_snapshot else null end,
      not app.has_view_selling_price(jo.tenant_id, p_actor_auth_user_id),
      jo.contract_snapshot,
      case when app.has_view_cost(jo.tenant_id, p_actor_auth_user_id) then jo.credit_snapshot else null end,
      not app.has_view_cost(jo.tenant_id, p_actor_auth_user_id),
      jo.acceptance_snapshot, jo.status, jo.owner_user_id, jo.org_unit_id, jo.record_version,
      jo.created_by, jo.created_at, jo.updated_at,
      count(*) over() as total_count
    from app.job_orders jo
    where jo.tenant_id = p_tenant_id
      and app.can_access_record(
        p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id,
        app.lead_record_scope_org_unit_ids(jo.org_unit_id), null
      )
    order by jo.created_at desc, jo.id asc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_job_orders(uuid, uuid, integer, integer) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3): paginated Job Orders for one tenant, most recently created first, replacing server/queries/job-order.ts:94-99''s broken .from("job_orders_directory") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032, RULE A -- p_actor_auth_user_id is new; the original TS function took none). Row filter and revenue/credit CASE-masks reproduce app.job_orders_directory''s own current view definition against its base table app.job_orders (see this migration''s own header for the full derivation) -- an explicit tenant_id filter is added since the view''s own where clause alone does not scope to a single tenant, matching app.list_portal_users'' own identical shape for this identical view-plus-explicit-tenant-filter requirement. p_page/p_page_size are clamped server-side (1-100), mirroring the TS layer''s own existing MAX_PAGE_SIZE=100/DEFAULT_PAGE_SIZE=50 clamp (job-order.ts:20-21) as defense in depth for a directly-callable RPC. total_count is an exact count(*) over() of every row matching the WHERE clause before LIMIT/OFFSET is applied -- the same per-request cost and semantics as the .from() call''s own count:"exact" option, following app.list_portal_users'' own established precedent for this exact "exact total, arbitrary page jump" requirement. order by created_at desc, id asc adds an id tie-break beyond the original single-column ordering, for determinism across page fetches. No pre-flight tenant-membership raise -- see this migration''s own RAISE-vs-silent-zero-rows section: app.can_access_record is a per-row predicate here (owner/org-unit/customer-account scope), so a non-member or a member with zero visible job orders both silently yield an empty page (rows=[], total_count 0), never a thrown error, matching the original RLS-filtered .from() read''s own current behavior exactly.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_job_orders with an identical grant set, never a
-- reimplementation.
create function public.list_job_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_number text,
  source_handoff_id uuid,
  quotation_id uuid,
  account_id uuid,
  customer_snapshot jsonb,
  cargo_service_snapshot jsonb,
  revenue_snapshot jsonb,
  revenue_masked boolean,
  contract_snapshot jsonb,
  credit_snapshot jsonb,
  credit_masked boolean,
  acceptance_snapshot jsonb,
  status text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_job_orders(p_tenant_id, p_actor_auth_user_id, p_page, p_page_size);
$wrap$;

comment on function public.list_job_orders(uuid, uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_job_orders with an identical grant set, never a reimplementation.';

revoke execute on function app.list_job_orders(uuid, uuid, integer, integer) from public;
grant execute on function app.list_job_orders(uuid, uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_job_orders(uuid, uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_job_orders(uuid, uuid, integer, integer) to authenticated, service_role;

-- ===========================================================================
-- 4. app.get_job_order_handoff_for_quotation -- replaces
--    server/queries/job-order-lineage.ts:22 (getJobOrderHandoffForQuotation)
-- ===========================================================================
-- Replaces: `.from("job_order_handoffs_directory").select("*")
-- .eq("quotation_id", quotationId).maybeSingle()`. app.job_order_handoffs carries a
-- COMPOSITE unique constraint `job_order_handoffs_tenant_quotation_purpose_unique
-- unique (tenant_id, quotation_id, purpose)` (20260724340000:88) -- NOT a bare unique
-- constraint on quotation_id alone, and this read (unlike the original insert path,
-- app.prepare_job_order_handoff) applies no `purpose` filter at all, so two rows with
-- the same quotation_id and different purpose values would be schema-legal. ADVERSARIAL
-- VERIFY PASS (independently re-derived, not merely the original draft''s own claim):
-- app.prepare_job_order_handoff -- the ONE gated entrypoint that inserts into
-- app.job_order_handoffs -- was independently re-checked against its own TRUE latest
-- body (20260902200000_harden_tenant_id_disclosure_commercial.sql, not merely its
-- 20260724340000 origin or the intermediate 20260819000000 redefinition) and, in every
-- one of its three historical bodies, hardcodes `purpose = ''job_order_draft''` in both
-- its own idempotency lookup and its INSERT (which does not even list `purpose` among
-- its target columns, relying on the column DEFAULT) -- it takes NO `p_purpose`
-- parameter at all. A repo-wide grep also confirms `''job_order_draft''` is the only
-- purpose value ever referenced anywhere in this repository (migrations, db-tests,
-- load-test seeds, and the TS contract). So no application code path can ever produce a
-- second, different-purpose row for one quotation_id -- only a direct, un-gated
-- service_role insert bypassing app.prepare_job_order_handoff entirely (the same class
-- of theoretical, never-exercised gap as app.get_job_order_for_handoff''s own
-- source_handoff_id analysis above) could. An earlier draft of this function
-- defensively added `order by created_at desc limit 1` here, silently returning "the
-- newest" row on a hypothetical multi-row match; rejected on review for the same reason
-- as app.get_job_order_for_handoff above -- the function below instead counts matches
-- and RAISES `ambiguous_context` (`check_violation`), matching both `.maybeSingle()`''s
-- own throw-on-conflict contract and app.resolve_access_context''s own established
-- count-then-raise idiom (PLT-108), never a silent pick.
create function app.get_job_order_handoff_for_quotation(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quotation_id uuid,
  account_id uuid,
  purpose text,
  schema_version integer,
  status text,
  payload jsonb,
  payload_hash text,
  payload_masked boolean,
  downstream_reference text,
  delivered_at timestamptz,
  prepared_by_auth_user_id uuid,
  owner_user_id uuid,
  org_unit_id uuid,
  created_by text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_match_count integer;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Adversarial verify pass resolution (see this migration''s own header, section 4):
  -- reproduces `.maybeSingle()`''s own throw-on-conflict contract explicitly, via this
  -- codebase''s established count-then-raise idiom (app.resolve_access_context,
  -- PLT-108), rather than silently returning "the newest" row on a hypothetical
  -- multi-row/multi-purpose match.
  select count(*) into v_match_count
  from app.job_order_handoffs h
  where h.quotation_id = p_quotation_id
    and app.can_access_record(
      p_actor_auth_user_id, h.tenant_id, h.owner_user_id,
      app.lead_record_scope_org_unit_ids(h.org_unit_id), null
    );

  if v_match_count > 1 then
    raise exception 'ambiguous_context: quotation_id % matches % job order handoffs visible to identity %, expected at most one', p_quotation_id, v_match_count, p_actor_auth_user_id
      using errcode = 'check_violation';
  end if;

  return query
  select
    h.id, h.tenant_id, h.quotation_id, h.account_id, h.purpose, h.schema_version, h.status,
    case when app.has_view_selling_price(h.tenant_id, p_actor_auth_user_id) then h.payload else null end,
    case when app.has_view_selling_price(h.tenant_id, p_actor_auth_user_id) then h.payload_hash else null end,
    not app.has_view_selling_price(h.tenant_id, p_actor_auth_user_id),
    h.downstream_reference, h.delivered_at, h.prepared_by_auth_user_id, h.owner_user_id, h.org_unit_id,
    h.created_by, h.created_at
  from app.job_order_handoffs h
  where h.quotation_id = p_quotation_id
    and app.can_access_record(
      p_actor_auth_user_id, h.tenant_id, h.owner_user_id,
      app.lead_record_scope_org_unit_ids(h.org_unit_id), null
    );
end;
$$;

comment on function app.get_job_order_handoff_for_quotation(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3): the handoff for one quotation, if one has been prepared, replacing server/queries/job-order-lineage.ts:22''s broken .from("job_order_handoffs_directory") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032, RULE A -- p_actor_auth_user_id is new; the original TS function took none). Row-visibility filter (app.can_access_record against tenant/owner/org-unit scope) reproduces job_order_handoffs_select_scoped''s own current predicate verbatim -- confirmed via repo-wide grep that no rewrite of this policy exists (RULE B). The payload/payload_hash CASE-WHEN mask and payload_masked flag are copied verbatim from app.job_order_handoffs_directory''s own current view definition, re-expressed against the base table with an explicit p_actor_auth_user_id instead of app.has_view_selling_price''s own default-session argument (RULE C: confirmed never redefined since its own original creation). quotation_id is scoped by a COMPOSITE unique constraint (tenant_id, quotation_id, purpose), not a bare unique constraint on this column alone, and this read applies no purpose filter -- but app.prepare_job_order_handoff (the only gated insert path, independently re-verified against its own true latest body) hardcodes purpose to ''job_order_draft'' and takes no p_purpose parameter at all, so no application code path can produce a second, different-purpose row; only a direct service_role bypass of that function could. Adversarial verify pass (see this migration''s own header): counts matches and RAISES `ambiguous_context` (`check_violation`) rather than silently returning "the newest" row, matching `.maybeSingle()`''s own throw-on-conflict behavior more faithfully than a silent LIMIT 1 would, surfaced to the TS caller via its existing `if (error) throw` handling with no additional change needed. Returns zero rows (never an exception) for a quotation with no handoff prepared yet, a nonexistent quotation_id, or an actor who cannot reach the handoff''s tenant/owner/org-unit/customer-account scope -- matching the original RLS-filtered view''s own silent-empty-result posture and the TS layer''s existing .maybeSingle() -> null handling, unchanged for the not-found case.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_job_order_handoff_for_quotation with an identical grant set,
-- never a reimplementation.
create function public.get_job_order_handoff_for_quotation(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  quotation_id uuid,
  account_id uuid,
  purpose text,
  schema_version integer,
  status text,
  payload jsonb,
  payload_hash text,
  payload_masked boolean,
  downstream_reference text,
  delivered_at timestamptz,
  prepared_by_auth_user_id uuid,
  owner_user_id uuid,
  org_unit_id uuid,
  created_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_job_order_handoff_for_quotation(p_quotation_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_job_order_handoff_for_quotation(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_job_order_handoff_for_quotation with an identical grant set, never a reimplementation.';

revoke execute on function app.get_job_order_handoff_for_quotation(uuid, uuid) from public;
grant execute on function app.get_job_order_handoff_for_quotation(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_job_order_handoff_for_quotation(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_job_order_handoff_for_quotation(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 5. app.list_job_order_handoffs -- replaces server/queries/job-order-lineage.ts:34-39
--    (listJobOrderHandoffs)
-- ===========================================================================
-- Replaces: `.from("job_order_handoffs_directory").select("*")
-- .eq("tenant_id", tenantId).order("created_at", { ascending: false }).limit(limit)`
-- (limit defaults to 50 in TS -- job-order-lineage.ts:33). NOT paginated with an
-- offset/count -- the TS signature returns a plain array (JobOrderHandoff[]), no
-- totalCount field (confirmed by reading the file: ListJobOrderHandoffsResult does not
-- exist, only Promise<JobOrderHandoff[]>). The original TS `limit` parameter has no
-- upper clamp of its own; a defensive `least(greatest(..., 1), 200)` server-side cap is
-- added below anyway, mirroring this schema''s own established precedent for this exact
-- "existing optional limit param, no original hard cap, now a directly-callable RPC"
-- shape (app.list_claim_evidence/app.list_claim_items, 20260903112000_harden_tenant_id_
-- disclosure_wms_outbound_ops.sql:2141-2172/2174-2210, both `p_limit integer default 50`
-- clamped to `least(greatest(coalesce(p_limit, 50), 1), 200)`) -- flagged as an OPEN
-- QUESTION at the end of this file since it is a real, if minor, behavior change for any
-- caller that ever requested more than 200 (none found in this repository today).
create function app.list_job_order_handoffs(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  quotation_id uuid,
  account_id uuid,
  purpose text,
  schema_version integer,
  status text,
  payload jsonb,
  payload_hash text,
  payload_masked boolean,
  downstream_reference text,
  delivered_at timestamptz,
  prepared_by_auth_user_id uuid,
  owner_user_id uuid,
  org_unit_id uuid,
  created_by text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  -- No pre-flight has_active_tenant_membership raise -- see this migration''s own
  -- RAISE-vs-silent-zero-rows header section: app.can_access_record varies per row, so a
  -- genuine tenant member with zero visible handoffs and a non-member both silently
  -- yield an empty array, exactly as the original RLS-filtered .from() read''s own
  -- no-error-on-non-member behavior, never a thrown error.
  return query
    select
      h.id, h.tenant_id, h.quotation_id, h.account_id, h.purpose, h.schema_version, h.status,
      case when app.has_view_selling_price(h.tenant_id, p_actor_auth_user_id) then h.payload else null end,
      case when app.has_view_selling_price(h.tenant_id, p_actor_auth_user_id) then h.payload_hash else null end,
      not app.has_view_selling_price(h.tenant_id, p_actor_auth_user_id),
      h.downstream_reference, h.delivered_at, h.prepared_by_auth_user_id, h.owner_user_id, h.org_unit_id,
      h.created_by, h.created_at
    from app.job_order_handoffs h
    where h.tenant_id = p_tenant_id
      and app.can_access_record(
        p_actor_auth_user_id, h.tenant_id, h.owner_user_id,
        app.lead_record_scope_org_unit_ids(h.org_unit_id), null
      )
    order by h.created_at desc
    limit v_limit;
end;
$$;

comment on function app.list_job_order_handoffs(uuid, uuid, integer) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3): every handoff for one tenant, most recently prepared first, replacing server/queries/job-order-lineage.ts:34-39''s broken .from("job_order_handoffs_directory") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032, RULE A -- p_actor_auth_user_id is new; the original TS function took none). Row filter and payload/payload_hash CASE-mask reproduce app.job_order_handoffs_directory''s own current view definition against its base table app.job_order_handoffs (see this migration''s own header) -- an explicit tenant_id filter is added since the view''s own where clause alone does not scope to a single tenant, and job_order_handoffs_select_scoped''s own current predicate is reproduced verbatim (RULE B: confirmed no rewrite exists). Same masking technique and RULE C helper citations as app.get_job_order_handoff_for_quotation. p_limit defaults to 50 (matching the TS layer''s own existing default, job-order-lineage.ts:33) and is defensively clamped to [1, 200] server-side -- the original TS parameter had no hard upper cap; see this migration''s own header disposition notes (item 2) for why 200 matches this codebase''s own dominant p_limit-clamp convention rather than being an isolated choice. No pre-flight tenant-membership raise -- see this migration''s own RAISE-vs-silent-zero-rows section: app.can_access_record is a per-row predicate here, so a non-member or a member with zero visible handoffs both silently yield an empty array, never a thrown error, matching the original RLS-filtered .from() read''s own current behavior exactly.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_job_order_handoffs with an identical grant set, never a
-- reimplementation.
create function public.list_job_order_handoffs(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  quotation_id uuid,
  account_id uuid,
  purpose text,
  schema_version integer,
  status text,
  payload jsonb,
  payload_hash text,
  payload_masked boolean,
  downstream_reference text,
  delivered_at timestamptz,
  prepared_by_auth_user_id uuid,
  owner_user_id uuid,
  org_unit_id uuid,
  created_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_job_order_handoffs(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_job_order_handoffs(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_job_order_handoffs with an identical grant set, never a reimplementation.';

revoke execute on function app.list_job_order_handoffs(uuid, uuid, integer) from public;
grant execute on function app.list_job_order_handoffs(uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_job_order_handoffs(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_job_order_handoffs(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- OPEN QUESTIONS / RISKS -- ADVERSARIAL VERIFY PASS DISPOSITION (CG-AUDIT-2026-09-02)
-- ===========================================================================
--
-- 1. [RESOLVED, fixed directly in this file] get_job_order_for_handoff /
--    get_job_order_handoff_for_quotation originally added an `order by created_at desc
--    limit 1` that the original `.from(...).maybeSingle()` call sites never had --
--    silently returning the newest matching row instead of `.maybeSingle()`''s own
--    throw-on-conflict (PGRST116) behavior. Independently re-derived from primary
--    sources (not the original draft''s own citations):
--      - app.prepare_job_order (the only gated app.job_orders insert path) was re-read
--        against its own TRUE latest body, 20260902201000_harden_tenant_id_disclosure_
--        operations.sql (a later redefinition than the 20260828150000 one a naive check
--        might stop at) -- it still sets tenant_id := the handoff''s own tenant_id, so no
--        row any application code path has produced can pair one source_handoff_id with
--        two different tenants. Same conclusion for app.prepare_job_order_handoff
--        against ITS true latest body, 20260902200000_harden_tenant_id_disclosure_
--        commercial.sql -- it hardcodes purpose = ''job_order_draft'' with no p_purpose
--        parameter at all, and a repo-wide grep confirms no other purpose value is ever
--        referenced anywhere (migrations, db-tests, load-test seeds, or the TS contract).
--      - In both cases a genuine multi-row match is schema-legal but application-
--        unreachable today -- reachable only via a direct service_role table insert
--        bypassing the one gated function entirely (both tables carry such a grant).
--    Given that, and that get_job_order_for_handoff''s specific multi-row scenario would
--    mean two job_orders rows disagreeing about which TENANT one handoff belongs to
--    (so "silently pick the newest" risks handing a caller a different tenant''s data,
--    not merely a nondeterministic pick), both functions now COUNT matches and RAISE
--    `ambiguous_context` (`check_violation`) when more than one exists, before building
--    any result row -- reproducing `.maybeSingle()`''s own throw-on-conflict contract
--    faithfully, via this codebase''s own established count-then-raise idiom
--    (app.resolve_access_context, PLT-108, 20260716100825:252-255/291-294), rather than
--    silently choosing a row. See each function''s own header/comment above for the full
--    derivation. The zero-row (not-found) case is unchanged -- still silent, matching
--    `.maybeSingle()` -> null.
--
-- 2. [VERIFIED, no change needed] list_job_order_handoffs: p_limit clamped to [1, 200].
--    Independently checked against this codebase''s OWN conventions rather than taken on
--    faith: `least(greatest(coalesce(p_limit, 50), 1), 200)` is not an isolated choice --
--    it is the dominant, established idiom for exactly this "p_limit default 50, simple
--    ORDER BY ... LIMIT, no offset/total_count" function shape, appearing 128 times
--    across supabase/migrations/*.sql (vs. this schema''s SEPARATE, also-established
--    page/pageSize convention -- MAX_PAGE_SIZE=100, confirmed via grep across every
--    server/queries/*.ts file that paginates -- which app.list_job_orders above
--    correctly uses instead, since it has an offset+exact-count contract this function
--    does not). The two functions in this same migration correctly use two different,
--    both-legitimate house conventions for two different shapes; 200 is not
--    inconsistent with anything. A repo-wide grep for "listJobOrderHandoffs(" call sites
--    with an explicit third argument above 200 is still worth a final check before this
--    is applied, but the cap itself needs no further justification.
--
-- 3. [VERIFIED, no change needed] Both list functions deliberately do NOT raise for a
--    non-member/zero-standing actor. Independently re-derived: the actual distinguishing
--    test this codebase applies (read directly from app.list_contacts'' own comment,
--    20260908020000:945-953, and app.list_accounts'' own comment, 20260908020000:315) is
--    not strictly "per-row-varying predicate" as this migration''s header frames it, but
--    "did the ORIGINAL `.from()`/RPC call already raise for a non-member, or did it rely
--    solely on RLS silent filtering." server/queries/job-order.ts:94-99 and job-order-
--    lineage.ts:34-39''s own original `.from("..._directory")` calls relied solely on
--    RLS with no application-level pre-flight raise -- so the silent-empty classification
--    for both list functions here is correct under either framing, and matches app.list_
--    contacts/app.list_portal_users, not app.list_accounts/app.find_duplicate_accounts.
--
-- 4. RULE A is a genuine, breaking signature change for all five TS functions (none
--    previously took an actor parameter). Confirm every real call site of all five
--    functions has a resolvable actorAuthUserId available at the call site (session
--    access context, matching the pattern every prior batch''s TS INTEGRATION notes
--    already found for their own newly-actor-parameterized functions) before this is
--    applied -- this draft does not itself locate or verify those call sites, per its
--    own SQL-only scope (see TS INTEGRATION below).

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
--
-- 1. server/queries/job-order.ts
-- ---------------------------------------------------------------------------
-- Client type: `JobOrderQueryTableClient = Pick<SupabaseClient, "from" | "rpc">`
-- (line 18) already includes "rpc" -- no type change needed (getJobOrderConversionReadiness
-- already calls .rpc()). Once all three functions below are switched, "from" is no
-- longer used anywhere in this file and MAY be dropped from the Pick<...> -- confirm
-- with a repo-wide grep for `.from(` in this file before doing so; not attempted here.
--
-- getJobOrder (currently lines 64-73): add a required second parameter
-- `actorAuthUserId: string`, replace the `.from(...)` chain with:
--     export async function getJobOrder(
--       client: JobOrderQueryTableClient,
--       jobOrderId: string,
--       actorAuthUserId: string,
--     ): Promise<JobOrder | null> {
--       const { data, error } = await client.rpc("get_job_order", {
--         p_job_order_id: jobOrderId,
--         p_actor_auth_user_id: actorAuthUserId,
--       });
--       if (error) {
--         throw new JobOrderQueryError(error.message);
--       }
--       const row = Array.isArray(data) ? data[0] : data;
--       return row ? parseJobOrder(row as Record<string, unknown>) : null;
--     }
-- (RETURNS TABLE always comes back as an array via .rpc(), unlike the old
-- .maybeSingle() single-object shape -- the `Array.isArray(data) ? data[0] : data`
-- guard, already established at cluster 1 batch 1 for this identical shape, picks the
-- single row or undefined/null; parseJobOrder''s own column-name expectations are
-- otherwise unchanged, since the RPC''s RETURNS TABLE column list matches the old
-- view''s select 1:1.)
--
-- getJobOrderForHandoff (currently lines 76-85): identical shape, add
-- `actorAuthUserId: string` as a required third parameter:
--     export async function getJobOrderForHandoff(
--       client: JobOrderQueryTableClient,
--       sourceHandoffId: string,
--       actorAuthUserId: string,
--     ): Promise<JobOrder | null> {
--       const { data, error } = await client.rpc("get_job_order_for_handoff", {
--         p_source_handoff_id: sourceHandoffId,
--         p_actor_auth_user_id: actorAuthUserId,
--       });
--       if (error) {
--         throw new JobOrderQueryError(error.message);
--       }
--       const row = Array.isArray(data) ? data[0] : data;
--       return row ? parseJobOrder(row as Record<string, unknown>) : null;
--     }
-- (Adversarial verify pass: app.get_job_order_for_handoff now RAISES `ambiguous_context`
-- instead of `.maybeSingle()`''s own PGRST116 on a genuine multi-row match -- both
-- surface identically here, via the existing `if (error) throw new JobOrderQueryError`
-- above; no TS-side change beyond the `.from()` -> `.rpc()` swap itself.)
--
-- listJobOrders (currently lines 88-111): ListJobOrdersInput gains a required
-- `actorAuthUserId: string` field; replace the `.from(...)` chain with:
--     export interface ListJobOrdersInput {
--       readonly tenantId: string;
--       readonly actorAuthUserId: string;
--       readonly page: number;
--       readonly pageSize?: number;
--     }
--     ...
--     const { data, error } = await client.rpc("list_job_orders", {
--       p_tenant_id: input.tenantId,
--       p_actor_auth_user_id: input.actorAuthUserId,
--       p_page: page,
--       p_page_size: pageSize,
--     });
--     if (error) {
--       throw new JobOrderQueryError(error.message);
--     }
--     const rows = (data ?? []) as Record<string, unknown>[];
--     const totalCount = rows.length > 0 ? Number(rows[0]?.total_count) : 0;
--     return {
--       jobOrders: rows.map((row) => parseJobOrder(row)),
--       totalCount,
--       page,
--       pageSize,
--     };
-- (The client-side `page`/`pageSize` clamp at the top of the function, lines 89-92, is
-- kept unchanged -- the RPC''s own server-side clamp is defense in depth, not a
-- replacement for it. `count: "exact"` -> the RPC''s `total_count` column, unwrapped
-- from `rows[0]`, the same idiom app.list_portal_users'' own TS caller
-- (server/queries/portal-users.ts:80) already established -- 0 when rows is empty,
-- since a paginated list with zero total rows returns literally zero rows and there is
-- no row to read total_count from.)
--
-- 2. server/queries/job-order-lineage.ts
-- ---------------------------------------------------------------------------
-- Client type: `JobOrderLineageQueryTableClient = Pick<SupabaseClient, "from">` (line
-- 11) must widen to `Pick<SupabaseClient, "from" | "rpc">` -- unlike job-order.ts,
-- "rpc" was never part of this file''s client alias before, since neither of its two
-- functions previously called .rpc() at all. Once both are switched, "from" is no
-- longer used anywhere in this file and MAY be dropped entirely (confirm with a
-- repo-wide grep for `.from(` in this file first; not attempted here).
--
-- getJobOrderHandoffForQuotation (currently lines 21-30): add a required second
-- parameter `actorAuthUserId: string`, replace the `.from(...)` chain with:
--     export async function getJobOrderHandoffForQuotation(
--       client: JobOrderLineageQueryTableClient,
--       quotationId: string,
--       actorAuthUserId: string,
--     ): Promise<JobOrderHandoff | null> {
--       const { data, error } = await client.rpc("get_job_order_handoff_for_quotation", {
--         p_quotation_id: quotationId,
--         p_actor_auth_user_id: actorAuthUserId,
--       });
--       if (error) {
--         throw new JobOrderLineageQueryError(error.message);
--       }
--       const row = Array.isArray(data) ? data[0] : data;
--       return row ? parseJobOrderHandoff(row as Record<string, unknown>) : null;
--     }
-- (Adversarial verify pass: app.get_job_order_handoff_for_quotation now RAISES
-- `ambiguous_context` instead of `.maybeSingle()`''s own PGRST116 on a genuine multi-row
-- match -- both surface identically here, via the existing `if (error) throw new
-- JobOrderLineageQueryError` above; no TS-side change beyond the `.from()` -> `.rpc()`
-- swap itself.)
--
-- listJobOrderHandoffs (currently lines 33-44): add a required third parameter
-- `actorAuthUserId: string`, keep `limit = 50` as the existing fourth (now: third
-- positional after actorAuthUserId, or reorder as this codebase''s own call-site
-- convention prefers -- see app.get_shipment_actual_cost''s own TS integration note for
-- precedent on where a newly-required actor arg is inserted; this draft places it
-- immediately after the existing required params and before any pre-existing optional
-- one, matching every other function in this same batch):
--     export async function listJobOrderHandoffs(
--       client: JobOrderLineageQueryTableClient,
--       tenantId: string,
--       actorAuthUserId: string,
--       limit = 50,
--     ): Promise<JobOrderHandoff[]> {
--       const { data, error } = await client.rpc("list_job_order_handoffs", {
--         p_tenant_id: tenantId,
--         p_actor_auth_user_id: actorAuthUserId,
--         p_limit: limit,
--       });
--       if (error) {
--         throw new JobOrderLineageQueryError(error.message);
--       }
--       return (data ?? []).map((row: Record<string, unknown>) => parseJobOrderHandoff(row));
--     }
-- Drop the now-redundant `.order(...)`/`.limit(...)` calls -- the RPC already applies
-- `order by h.created_at desc limit v_limit` server-side.
--
-- 3. Call sites (not located/fixed here, per this task''s SQL-only, two-file scope) --
--    a repo-wide grep for each of the five function names below is required before this
--    draft is applied, to thread `actorAuthUserId` (the same `access.authUserId`-shaped
--    value every prior batch''s call sites already resolve) into every real caller:
--      getJobOrder(
--      getJobOrderForHandoff(
--      listJobOrders(
--      getJobOrderHandoffForQuotation(
--      listJobOrderHandoffs(
--    Likely candidates by naming convention (not verified in this draft):
--      app/(tenant)/[tenantSlug]/operations/job-orders/[jobOrderId]/page.tsx
--      app/(tenant)/[tenantSlug]/operations/job-orders/page.tsx
--    and each function''s own *.test.ts (server/queries/job-order.test.ts,
--    server/queries/job-order-lineage.test.ts if either exists) will need its
--    `.from`-based mock updated to a `.rpc("<fn_name>", args)`-based mock, the same
--    rewrite every prior batch''s TS INTEGRATION notes deferred for the identical
--    reason (SQL-only scope).
