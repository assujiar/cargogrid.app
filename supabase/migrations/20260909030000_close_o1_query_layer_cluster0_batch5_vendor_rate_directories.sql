-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 0 batch 5 of 5 (FINAL
-- batch of cluster 0). Closes the last 4 tables in cluster 0 (CRM/commercial, 32
-- tables total) -- app.vendor_rate_versions_directory, app.v_active_vendor_rates,
-- app.rate_selections_directory, app.vendor_rate_tiers_directory. Continues the
-- same Design->Verify->Fix adversarial pipeline batches 1-4 established (RULE
-- A/B/C baked into every draft and every independent verify pass below),
-- user-directed ("lanjut sampe siap launching") extension of CG-AUDIT-2026-09-02's
-- Ø1-query-layer finding: supabase/config.toml only exposes "public"/
-- "graphql_public" to PostgREST, so every .from() read against the "app" schema
-- has never worked in production.
--
-- The Workflow tool's own subagent-spawning path failed twice in a row during
-- batch 4's design stage with a permission-handler schema-validation bug (a
-- session/harness-level defect, not a code issue -- confirmed by testing that the
-- plain Agent tool worked fine in the same session). This batch, like batch 4,
-- was completed via parallel design agents plus independent verify agents
-- launched directly through the Agent tool instead, applying the identical RULE
-- A/B/C discipline the Workflow pipeline itself encodes.
--
-- 8 new app.*/public.* Option-2 wrapper function pairs across 4 tables:
--   app.vendor_rate_versions_directory: app.list_rate_versions_for_master_record,
--                                        app.get_rate_version_by_id,
--                                        app.list_pending_rate_versions,
--                                        app.list_procurement_linked_vendor_rate_versions,
--                                        app.list_vendor_rate_versions_for_vendor
--                                        (5 functions -- one per distinct call shape;
--                                        explicitly considered and declined to merge
--                                        two of them into one parameterized function,
--                                        matching this effort's own established
--                                        "distinct, self-documenting RPC names" convention)
--   app.v_active_vendor_rates:          app.list_active_vendor_rates
--   app.rate_selections_directory:      app.list_rate_selections_for_request
--   app.vendor_rate_tiers_directory:    app.list_vendor_rate_tiers
--
-- Notable design decision, independently verified: app.v_active_vendor_rates'
-- own read (listActiveVendorRates) is NOT routed through the existing
-- app.search_vendor_rates function, despite superficial similarity (both return
-- SETOF app.vendor_rate_versions_directory-shaped rows for approved+effective
-- rates). search_vendor_rates hard-requires the actor to hold the specific,
-- dynamically tenant-configured COM:View permission via app.evaluate_permission
-- -- a real, provable authority gap relative to the view chain's own current
-- test (plain active tenant membership, no COM:View requirement): a tenant can
-- configure a staff role with active membership and zero COM permissions,
-- satisfying the view's own test while being rejected by search_vendor_rates.
-- Reusing it would have been a silent authority regression. A new, purpose-built
-- function (app.list_active_vendor_rates) was authored instead, reproducing the
-- view chain's own actual current authority test and the call site's own actual
-- (vendor_code-ordered, unfiltered) behavior. This conclusion was independently
-- re-derived and confirmed by an adversarial verify pass before being included
-- here, not merely accepted from the design draft.
--
-- Every function below was independently adversarially re-verified against the
-- live repo state (not merely its own draft's claims) before being included in
-- this migration. One real (non-functional, prose-only) issue was found and
-- fixed during that verify pass: app.vendor_rate_versions_directory's own header
-- comment originally claimed two of its five call shapes (the
-- vendor_master_id-IS-NOT-NULL browse and the vendor_master_id-EQUALS-a-value
-- lookup) were "not nested/subset forms of each other" as justification for
-- keeping them as separate functions -- that claim was factually wrong (the
-- second predicate genuinely does imply the first under SQL's three-valued
-- logic). The comment was corrected to state the TRUE reasoning (this
-- codebase's own established preference for distinct, self-documenting
-- single-purpose RPC names over one function whose row set silently pivots on
-- an optional parameter) while keeping the actual decision (5 separate
-- functions) unchanged -- no SQL logic in any of the 8 functions needed
-- correction. All other 3 tables (app.v_active_vendor_rates, app.rate_selections_
-- directory, app.vendor_rate_tiers_directory) passed independent adversarial
-- re-verification with zero issues found.
--
-- Both affected TS query files (server/queries/rate.ts, procurement-rate.ts) and
-- every real page.tsx call site are switched from .from() to .rpc() in this same
-- commit, per each function's own embedded TS INTEGRATION note below. Two
-- functions in this batch (app.list_rate_versions_for_master_record,
-- app.list_vendor_rate_versions_for_vendor) have no live page.tsx caller today
-- (only unit tests reference them) -- fixed anyway since the broken .from() read
-- these functions replace is broken regardless of caller count.
--
-- This batch closes the LAST 4 of cluster 0's 32 tables -- cluster 0
-- (CRM/commercial, all 32 tables) is now fully DONE. Clusters 1-7 (104 more
-- .from() call sites across finance/identity/dispatch/tracking/documents/
-- analytics/misc) remain, per CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json.

-- ===========================================================================
-- TABLE 1 of 4: app.vendor_rate_versions_directory
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- app.vendor_rate_versions_directory
-- read path (cluster 0, 5th and final table of this pass over server/queries/rate.ts +
-- server/queries/procurement-rate.ts).
--
-- app.vendor_rate_versions_directory is a VIEW (not a base table). It lives in the "app"
-- Postgres schema, which supabase/config.toml only ever exposes "public"/"graphql_public"
-- to PostgREST -- every `.from("vendor_rate_versions_directory")` read against it has
-- therefore never worked in production (404s as a nonexistent relation from PostgREST's
-- point of view). Five broken call sites across two files are replaced here with five
-- app.*/public.* Option-2 wrapper function pairs -- one per distinct filter shape:
--   server/queries/rate.ts:29             listRateVersionsForMasterRecord
--     -> app.list_rate_versions_for_master_record / public.list_rate_versions_for_master_record
--   server/queries/rate.ts:41             getRateVersionById
--     -> app.get_rate_version_by_id / public.get_rate_version_by_id
--   server/queries/rate.ts:53             listPendingRateVersions
--     -> app.list_pending_rate_versions / public.list_pending_rate_versions
--   server/queries/procurement-rate.ts:51 listProcurementLinkedVendorRateVersions
--     -> app.list_procurement_linked_vendor_rate_versions / public.list_procurement_linked_vendor_rate_versions
--   server/queries/procurement-rate.ts:70 listVendorRateVersionsForVendor
--     -> app.list_vendor_rate_versions_for_vendor / public.list_vendor_rate_versions_for_vendor
--
-- SHARED-FUNCTION REASONING (task's own "may share one parameterized function" option,
-- explicitly considered and rejected): all five call shapes were compared pairwise.
--   * listRateVersionsForMasterRecord (eq master_record_id) vs. getRateVersionById
--     (eq rate_version_id, maybeSingle): different key column, different cardinality
--     contract (list vs. zero-or-one) -- not the same shape.
--   * listPendingRateVersions (eq tenant_id + eq approval_status='pending_approval') is the
--     only call filtering on approval_status at all -- unique among the five.
--   * listProcurementLinkedVendorRateVersions (eq tenant_id + vendor_master_id IS NOT NULL)
--     vs. listVendorRateVersionsForVendor (eq tenant_id + vendor_master_id = :value): CORRECTION
--     (adversarial review, 2026-09-09) -- an earlier draft of this note claimed these two
--     predicates are "not nested/subset forms of each other" and therefore cannot share one
--     parameterized function without a second boolean flag. That claim is WRONG and has been
--     struck: `v.vendor_master_id = p_vendor_master_id` already implies
--     `v.vendor_master_id is not null` for any non-null p_vendor_master_id, because SQL's
--     three-valued equality can never evaluate true against a null column value -- so
--     `v.vendor_master_id is not null and (p_vendor_master_id is null or v.vendor_master_id =
--     p_vendor_master_id)` correctly reproduces BOTH behaviors from one nullable parameter
--     (NULL -> "any vendor-linked row", a real uuid -> "that one vendor's rows"), with no
--     second flag needed. They genuinely are a nested/subset pair. Kept as two separate
--     functions anyway -- not because merging is technically impossible, but because this
--     remediation effort's own established convention (app.list_accounts /
--     app.list_subsidiary_accounts / app.get_account_by_id, batch1: three separate
--     single-purpose functions over the same app.accounts table with overlapping predicates,
--     never collapsed into one with an optional-filter parameter) already prefers distinct,
--     self-documenting RPC names with fixed parameter lists over one function whose returned
--     row set silently pivots on whether an optional argument was supplied -- and the two TS
--     call sites already have distinct names, distinct signatures, and no shared caller. Five
--     distinct, single-purpose functions is therefore a defensible, convention-matching
--     choice, not a forced one -- restated accurately rather than on a false premise.
--
-- ===========================================================================
-- TARGET VIEW: FULL COLUMN SHAPE AND MASKING (RULE B applied -- latest view, not original)
-- ===========================================================================
-- `grep -n "create view app.vendor_rate_versions_directory\|create or replace view
-- app.vendor_rate_versions_directory" supabase/migrations/*.sql` -> exactly two hits:
--   1. 20260724150000_create_commercial_rate_cost_lookup.sql:135 (original CREATE VIEW,
--      COM-149) -- 25 columns, no vendor_master_id/lead_time_days/capacity_terms.
--   2. 20260730620000_extend_commercial_vendor_rate_for_procurement.sql:1572 (CREATE OR
--      REPLACE VIEW, PRC-255 design note 14) -- widens to 34 columns (adds
--      vendor_master_id, lead_time_days, capacity_terms -- the latter two cost-masked
--      identically to base_amount) AND hardens the row filter to exclude a
--      customer_user-layer principal entirely.
-- No later `create or replace view` exists (that grep's only two hits are the two above) --
-- #2 is therefore the CURRENT, authoritative definition, reproduced verbatim below (not #1).
--
-- The view's live SELECT list (20260730620000:1572-1611), 34 columns:
--   v.id as rate_version_id, v.tenant_id, v.master_record_id, m.code as vendor_code,
--   m.name as vendor_name, v.service_type, v.mode, v.origin_lane, v.destination_lane,
--   v.equipment_type, v.cargo_weight_min, v.cargo_weight_max, v.cargo_volume_min,
--   v.cargo_volume_max,
--   case when app.has_view_cost(v.tenant_id) then v.currency else null end as currency,
--   case when app.has_view_cost(v.tenant_id) then v.base_amount else null end as base_amount,
--   case when app.has_view_cost(v.tenant_id) then v.minimum_amount else null end as minimum_amount,
--   case when app.has_view_cost(v.tenant_id) then v.surcharge_components else null end as surcharge_components,
--   not app.has_view_cost(v.tenant_id) as cost_masked,
--   v.approval_status, v.effective_from, v.effective_to, v.supersedes_version_id,
--   v.approved_by, v.approved_at, v.rejected_reason, v.withdrawn_reason, v.record_version,
--   v.created_by, v.created_at, v.updated_at, v.vendor_master_id,
--   case when app.has_view_cost(v.tenant_id) then v.lead_time_days else null end as lead_time_days,
--   case when app.has_view_cost(v.tenant_id) then v.capacity_terms else null end as capacity_terms
--   from app.vendor_rate_versions v join app.master_records m on m.id = v.master_record_id
--   where (app.has_active_tenant_membership(v.tenant_id) and not
--          app.actor_holds_customer_user_layer(v.tenant_id)) or app.is_supreme_admin();
-- All five functions below reproduce this exact 34-column projection and exact masking --
-- never more, never fewer columns -- and re-express the has_view_cost/has_active_tenant_
-- membership/actor_holds_customer_user_layer/is_supreme_admin calls with an explicit
-- p_actor_auth_user_id argument instead of each helper's default auth.uid() argument (see
-- "WHY THE MASKING IS RE-EXPRESSED AGAINST THE BASE TABLE" below). The base table
-- (app.vendor_rate_versions) has since gained three MORE columns not in this view's own
-- projection (governance_approval_status, governance_approval_request_id,
-- source_import_staging_row_id -- added by 20260730660000/20260730620000 respectively) --
-- these are deliberately NOT surfaced by any function below, matching the view's own
-- current (never re-widened) 34-column shape exactly.
--
-- Deliberate column note: server/contracts/rate/rate.ts's RateVersionSchema/parseRateVersion
-- (the contract listRateVersionsForMasterRecord/getRateVersionById/listPendingRateVersions
-- already parse every row through) only reads 27 of these 34 columns -- it does not declare
-- vendor_master_id/lead_time_days/capacity_terms (server/queries/procurement-rate.ts's own
-- header explains parseRateVersion was never extended for these PRC-255 columns, and that
-- file's own two functions return raw Record<string,unknown>[] instead, precisely so they
-- can carry them). All five functions below still return the FULL 34-column shape
-- unconditionally (matching the original `select("*")` on the view, not a narrower,
-- per-caller-contract projection) -- zod simply ignores object keys it does not declare, so
-- this is a faithful, lossless reproduction of the original `.select("*")` behavior for
-- every call site, both the parseRateVersion ones and the raw-row ones.
--
-- ===========================================================================
-- RULE B -- authority envelope for the row filter (current RLS predicate, not the original)
-- ===========================================================================
-- The view's own row filter super-set of the base table's RLS predicate is what actually
-- governs a `.from()` read (SECURITY INVOKER views apply RLS via the querying role; this
-- view is security_invoker=false per its own migration's stated house style, so its filter
-- clause IS the enforcement, not a redundant belt-and-suspenders). Cross-checked against the
-- base table's own current RLS anyway, since both must agree (and do):
--   `grep -n "vendor_rate_versions_select_scoped\|create policy.*vendor_rate_versions\|alter
--   policy.*vendor_rate_versions" supabase/migrations/*.sql` -> exactly two hits:
--     1. 20260724150000_create_commercial_rate_cost_lookup.sql:676 (original CREATE POLICY):
--        `using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())`
--     2. 20260730560000_harden_customer_user_layer_default_deny.sql:355 (ALTER POLICY):
--        `using (((app.has_active_tenant_membership(tenant_id) AND NOT
--        app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()))`
--   #2 postdates #1 and is therefore the CURRENT base-table RLS predicate. It is IDENTICAL
--   in shape to the view's own row filter as re-widened by 20260730620000 (which was itself
--   written chronologically after 20260730560000, so the view's own filter already reflects
--   this hardening -- both are in agreement, and neither is stale relative to the other).
--   No later ALTER POLICY on this table exists (those two greps are the complete history).
--   Row visibility below reproduces this exact, current, hardened predicate: a
--   customer_user-layer principal gets ZERO rows from every function below, not merely
--   cost-masked ones -- stronger than masking alone, matching the view's own comment
--   ("Row filter hardened to exclude a customer_user-layer principal entirely").
--
-- ===========================================================================
-- RULE C -- precedent staleness: every helper below confirmed against its MOST RECENT
-- definition, not merely its original
-- ===========================================================================
--   * app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default
--     auth.uid()) -- `grep -n "create or replace function
--     app.has_active_tenant_membership\|create function app.has_active_tenant_membership"
--     supabase/migrations/*.sql` -> THREE hits: 20260716105512 (original), 20260716111315
--     (CREATE OR REPLACE, adds the support-grant branch), 20260907110000 (CREATE OR REPLACE,
--     D3b -- additionally excludes a suspended/revoked app.users row). The 20260907110000
--     body is the current one and is what every call below relies on; signature is
--     unchanged across all three (2-arg, actor still passed explicitly as the 2nd
--     positional argument).
--   * app.actor_holds_customer_user_layer(p_tenant_id uuid, p_auth_user_id uuid default
--     auth.uid()) -- grepped repo-wide for both "create or replace function" and "create
--     function" spellings -> exactly ONE hit, ever (20260730311000_harden_customer_
--     inventory_access_rls_isolation.sql:71) -- never replaced. Current = original.
--   * app.is_supreme_admin(p_auth_user_id uuid default auth.uid()) -- grepped repo-wide ->
--     exactly ONE `create function`, ever (20260716105512_create_rls_tenant_policies.sql:45)
--     -- never replaced. Current = original.
--   * app.has_view_cost(p_tenant_id uuid, p_auth_user_id uuid default auth.uid()) -- grepped
--     repo-wide -> exactly ONE `create function`, ever (20260724090000_create_commercial_
--     costing_request.sql:144) -- never replaced. Body: `select
--     (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'COM', 'View cost')).allowed;`
--     -- the same all-or-nothing, "no masked-but-visible state" gate the view itself already
--     used and search_vendor_rates already re-expresses with an explicit actor arg.
--   * app.assert_actor_is_session_identity(p_actor_auth_user_id uuid) -- grepped repo-wide ->
--     exactly ONE `create or replace function`, ever (20260730440000_harden_actor_identity_
--     session_crosscheck.sql:59) -- never replaced. Current = original (there is nothing to
--     reconcile -- it has had exactly one body its entire existence).
--
-- WHY THE MASKING/ROW-FILTER IS RE-EXPRESSED AGAINST THE BASE TABLE, NOT BY SELECTING FROM
-- THE VIEW: the view's own CASE expressions and WHERE clause call app.has_view_cost(v.
-- tenant_id) / app.has_active_tenant_membership(v.tenant_id) / app.actor_holds_customer_
-- user_layer(v.tenant_id) / app.is_supreme_admin() relying on each helper's *default*
-- `auth.uid()` argument -- correct only under a live PostgREST request/session GUC, not when
-- invoked from a SECURITY DEFINER function called via RPC (a nested SECURITY DEFINER call's
-- own session GUC is not guaranteed to be the calling session's). This is the exact tension
-- app.search_vendor_rates (20260724150000_create_commercial_rate_cost_lookup.sql:490-558,
-- widened 20260730620000:1623-1696) already documented and resolved for THIS SAME view, and
-- the same fix this remediation effort's own app.list_customer_contract_price_components
-- (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:1896-1952) and app.
-- list_costing_responses_for_request (20260909010000_close_o1_query_layer_cluster0_batch3_
-- costing_credit_approval.sql:221-272) already established for their own sibling masked
-- directory views: re-express the view's masking/row-filter directly against the base
-- table, with an explicit p_actor_auth_user_id argument passed into every helper call.
--
-- Precedent modeled on (RULE C -- checked, not assumed):
--  * app.search_vendor_rates (widened body at 20260730620000_extend_commercial_vendor_
--    rate_for_procurement.sql:1623-1696) -- the closest possible precedent: it is a
--    SECURITY DEFINER function reading this EXACT view/table, re-expressing this EXACT
--    34-column masking with this EXACT app.has_view_cost(v.tenant_id, p_actor_auth_user_id)
--    call shape. NOT followed for its row-visibility predicate, however: search_vendor_rates
--    gates row visibility on `app.evaluate_permission(actor, tenant, 'COM', 'View').allowed`
--    (a MODULE PERMISSION check) plus `approval_status = 'approved' AND
--    effective_from <= now() AND (effective_to is null or effective_to > now())` plus four
--    caller-supplied optional filters -- that is search_vendor_rates' OWN narrower, curated
--    comparison-lookup contract (Prompt 149 §4's disclosed scope boundary: "a bounded,
--    single-lane comparison lookup... not a paginated full master-data browse"), not the
--    directory view's own tenant-membership-based row filter. Copying search_vendor_rates'
--    row predicate forward here would both UNDER-grant (COM:View is a real, seeded,
--    narrower permission than mere tenant membership -- excluding a tenant member who lacks
--    it, which the directory view never excluded) and OVER-narrow (approved+effective-only,
--    silently dropping every pending_approval/rejected/withdrawn/superseded row every one of
--    these five call sites explicitly needs "any approval_status" for). Only its MASKING
--    expressions are reused verbatim; its row-visibility predicate is not.
--  * app.list_customer_contract_price_components / app.list_costing_responses_for_request
--    (cited above) -- for overall shape: `language plpgsql`, `perform app.assert_actor_is_
--    session_identity(p_actor_auth_user_id);` as the unconditional first statement,
--    `returns table (...)` mirroring the view's own column list, masking CASE expressions
--    threading the explicit actor arg, `stable security definer set search_path = app,
--    pg_temp`.
--  * `p_actor_auth_user_id` as an explicit, non-defaulted parameter (no `default auth.uid()`)
--    for the three functions with a real, live TS caller today (get_rate_version_by_id,
--    list_pending_rate_versions, list_procurement_linked_vendor_rate_versions) -- every real
--    call site already resolves it server-side via `access.authUserId`
--    (lib/portal/commercial-guard.ts / lib/portal/procurement-guard.ts), never raw client
--    input, matching this same remediation effort's own established convention (batch1/
--    batch3 headers, same reasoning). list_rate_versions_for_master_record and list_vendor_
--    rate_versions_for_vendor currently have NO live page.tsx caller (grepped repo-wide for
--    both names outside server/queries/*.ts and server/queries/*.test.ts -- zero hits) --
--    they are still given the same non-defaulted, explicit-actor shape for consistency with
--    their three siblings and because a future caller (or a currently-untested code path)
--    must not silently default to auth.uid() and skip RULE A's actor-identity cross-check
--    reasoning; both are still `authenticated`-reachable via the RPC grant below regardless
--    of whether a UI caller currently exists, so the guard is required either way.
--  * `limit least(coalesce(p_limit, 200), 200)` bounded-list convention, `p_limit integer
--    default 200` -- for the two procurement-scoped reads only (list_procurement_linked_
--    vendor_rate_versions, list_vendor_rate_versions_for_vendor), matching their own current
--    TS-side `PROCUREMENT_RATE_LIST_LIMIT = 200` constant (server/queries/procurement-
--    rate.ts:47) and `.limit(PROCUREMENT_RATE_LIST_LIMIT)` calls -- and matching this
--    remediation effort's own established bounded-list idiom (e.g. app.list_contacts /
--    app.list_accounts, 20260908020000, `limit least(coalesce(p_limit, 200), 200)`). The
--    other three functions below apply NO limit, matching their own original `.from(...)`
--    calls, which never called `.range()`/`.limit()` either (rate.ts:27-37, rate.ts:40-49,
--    rate.ts:52-63) -- adding one where none existed would be a behavior change, not a
--    faithful remediation.
--
-- RULE A (checked against EVERY function below, self-check per the task's own final step):
-- all five functions take an explicit p_actor_auth_user_id and are granted to
-- `authenticated` (see grants below), so `perform app.assert_actor_is_session_identity
-- (p_actor_auth_user_id);` is the unconditional FIRST executable statement in every one of
-- the five function bodies, before any lookup, join, or authority check -- required "even
-- when the only gate is app.can_access_record(...)/app.has_active_tenant_membership(...)"
-- per this task's own RULE A text, which is exactly the gate shape every one of these five
-- functions uses (has_active_tenant_membership/actor_holds_customer_user_layer/
-- is_supreme_admin/has_view_cost -- no app.evaluate_permission module-permission check
-- appears in any of them, since none is part of the view's own row/column-masking
-- predicate).

-- ===========================================================================
-- 1. app.list_rate_versions_for_master_record / public.list_rate_versions_for_master_record
--    Replaces: server/queries/rate.ts:27-37 (listRateVersionsForMasterRecord) --
--    `.from("vendor_rate_versions_directory").select("*").eq("master_record_id",
--    masterRecordId).order("created_at", { ascending: false })`. Any approval_status.
-- ===========================================================================

create function app.list_rate_versions_for_master_record(
  p_master_record_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
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
    v.id as rate_version_id,
    v.tenant_id,
    v.master_record_id,
    m.code as vendor_code,
    m.name as vendor_name,
    v.service_type,
    v.mode,
    v.origin_lane,
    v.destination_lane,
    v.equipment_type,
    v.cargo_weight_min,
    v.cargo_weight_max,
    v.cargo_volume_min,
    v.cargo_volume_max,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.currency else null end as currency,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.base_amount else null end as base_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.minimum_amount else null end as minimum_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.surcharge_components else null end as surcharge_components,
    not app.has_view_cost(v.tenant_id, p_actor_auth_user_id) as cost_masked,
    v.approval_status,
    v.effective_from,
    v.effective_to,
    v.supersedes_version_id,
    v.approved_by,
    v.approved_at,
    v.rejected_reason,
    v.withdrawn_reason,
    v.record_version,
    v.created_by,
    v.created_at,
    v.updated_at,
    v.vendor_master_id,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.lead_time_days else null end as lead_time_days,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.capacity_terms else null end as capacity_terms
  from app.vendor_rate_versions v
  join app.master_records m on m.id = v.master_record_id
  where v.master_record_id = p_master_record_id
    and (
      (app.has_active_tenant_membership(v.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(v.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by v.created_at desc;
end;
$$;

comment on function app.list_rate_versions_for_master_record(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: read path for app.vendor_rate_versions_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()), replacing server/queries/rate.ts:27''s broken .from("vendor_rate_versions_directory"). Every rate version under one master record, any approval_status, most recently created first. Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A). Row filter reproduces the view''s CURRENT (20260730620000, post-20260730560000-hardening) predicate verbatim: (has_active_tenant_membership AND NOT actor_holds_customer_user_layer) OR is_supreme_admin -- a customer_user-layer principal gets zero rows, not merely masked ones. The currency/base_amount/minimum_amount/surcharge_components/lead_time_days/capacity_terms CASE-WHEN cost mask and cost_masked flag are copied verbatim from the view''s own definition, re-expressed against the base table with an explicit p_actor_auth_user_id instead of the view''s default-auth.uid() masking -- the same fix app.search_vendor_rates already established for this exact view under RPC invocation. Returns zero rows (never an exception) for a nonexistent master_record_id or an actor with no membership in that record''s tenant, matching the original RLS/view-filtered .from() call''s own silent-empty-result posture. No limit/pagination, matching the original .from() call, which never applied .range()/.limit() either.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_rate_versions_for_master_record with an identical grant set,
-- never a reimplementation.
create function public.list_rate_versions_for_master_record(
  p_master_record_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_rate_versions_for_master_record(p_master_record_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_rate_versions_for_master_record(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_rate_versions_for_master_record with an identical grant set, never a reimplementation.';

-- Same grant set as the view it replaces (`grant select on app.vendor_rate_versions_directory
-- to authenticated, service_role;`, 20260730620000:1722).
revoke execute on function app.list_rate_versions_for_master_record(uuid, uuid) from public;
grant execute on function app.list_rate_versions_for_master_record(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO
-- anon, authenticated, service_role` bootstrap grant on the public schema).
revoke execute on function public.list_rate_versions_for_master_record(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_rate_versions_for_master_record(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION: server/queries/rate.ts `listRateVersionsForMasterRecord`
-- ===========================================================================
-- 1. Change `RateQueryTableClient` usage for this function (or widen the shared alias, the
--    same way this remediation effort's other files did) to require `"rpc"`, not `"from"`.
--    rate.ts already imports nothing from "@supabase/supabase-js" beyond the `SupabaseClient`
--    type -- `export type RateQueryTableClient = Pick<SupabaseClient, "from" | "rpc">;` covers
--    every function in this file (all five need rpc after this migration; see functions 2/3
--    below), so widen the ONE shared alias rather than adding a second type.
-- 2. Add a required `actorAuthUserId: string` parameter:
--      export async function listRateVersionsForMasterRecord(
--        client: RateQueryTableClient,
--        masterRecordId: string,
--        actorAuthUserId: string,
--      ): Promise<RateVersion[]>
-- 3. Replace the `.from("vendor_rate_versions_directory").select("*")
--    .eq("master_record_id", masterRecordId).order("created_at", { ascending: false })` chain
--    with:
--      const { data, error } = await client.rpc("list_rate_versions_for_master_record", {
--        p_master_record_id: masterRecordId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    Drop the now-redundant `.order(...)` call -- the RPC already applies
--    `order by v.created_at desc` server-side.
-- 4. Row mapping is unchanged: `(data ?? []).map((row: Record<string, unknown>) =>
--    parseRateVersion(row))` -- the RPC returns the identical 34-column shape (in the
--    identical column names) as the old view select; parseRateVersion already ignores the
--    three trailing PRC-255 columns it does not declare.
-- 5. Error handling is unchanged: `if (error) throw new RateQueryError(error.message);`.
-- 6. No current page.tsx call site exists for this function (grepped repo-wide outside
--    server/queries/*.ts and *.test.ts -- zero hits) -- only server/queries/rate.test.ts
--    (describe block "listRateVersionsForMasterRecord", line 98) calls it today, and that
--    test''s fake client will need a `rpc` fake returning `[VALID_RATE_VERSION_ROW]` in place
--    of its current `.from`-chain mock -- not attempting that rewrite here, per this task''s
--    scope (SQL design only).

-- ===========================================================================
-- 2. app.get_rate_version_by_id / public.get_rate_version_by_id
--    Replaces: server/queries/rate.ts:40-49 (getRateVersionById) --
--    `.from("vendor_rate_versions_directory").select("*").eq("rate_version_id",
--    rateVersionId).maybeSingle()`. Any approval_status.
-- ===========================================================================

create function app.get_rate_version_by_id(
  p_rate_version_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
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
    v.id as rate_version_id,
    v.tenant_id,
    v.master_record_id,
    m.code as vendor_code,
    m.name as vendor_name,
    v.service_type,
    v.mode,
    v.origin_lane,
    v.destination_lane,
    v.equipment_type,
    v.cargo_weight_min,
    v.cargo_weight_max,
    v.cargo_volume_min,
    v.cargo_volume_max,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.currency else null end as currency,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.base_amount else null end as base_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.minimum_amount else null end as minimum_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.surcharge_components else null end as surcharge_components,
    not app.has_view_cost(v.tenant_id, p_actor_auth_user_id) as cost_masked,
    v.approval_status,
    v.effective_from,
    v.effective_to,
    v.supersedes_version_id,
    v.approved_by,
    v.approved_at,
    v.rejected_reason,
    v.withdrawn_reason,
    v.record_version,
    v.created_by,
    v.created_at,
    v.updated_at,
    v.vendor_master_id,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.lead_time_days else null end as lead_time_days,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.capacity_terms else null end as capacity_terms
  from app.vendor_rate_versions v
  join app.master_records m on m.id = v.master_record_id
  where v.id = p_rate_version_id
    and (
      (app.has_active_tenant_membership(v.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(v.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  limit 1;
end;
$$;

comment on function app.get_rate_version_by_id(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: single-rate-version read for the Rate Version Detail pages (both Commercial and Procurement), replacing server/queries/rate.ts:40''s broken .from("vendor_rate_versions_directory"). Any approval_status. Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A). Row filter reproduces the view''s CURRENT (post-20260730560000-hardening) predicate verbatim: (has_active_tenant_membership AND NOT actor_holds_customer_user_layer) OR is_supreme_admin. The four cost-masked / two PRC-255-masked columns (currency/base_amount/minimum_amount/surcharge_components/lead_time_days/capacity_terms) are copied verbatim from the view''s own CASE-WHEN expressions, re-expressed with an explicit p_actor_auth_user_id -- the same fix app.search_vendor_rates already established for this exact view. Returns zero rows (never an exception) for a nonexistent id or one the actor cannot access, matching both the original RLS/view-filtered .maybeSingle() behavior and this repository''s own anti-enumeration posture (app.get_contact_by_id, app.get_costing_request_by_id) -- a caller cannot distinguish "does not exist" from "exists, not yours".';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_rate_version_by_id with an identical grant set, never a
-- reimplementation.
create function public.get_rate_version_by_id(
  p_rate_version_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_rate_version_by_id(p_rate_version_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_rate_version_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_rate_version_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_rate_version_by_id(uuid, uuid) from public;
grant execute on function app.get_rate_version_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_rate_version_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_rate_version_by_id(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION: server/queries/rate.ts `getRateVersionById`
-- ===========================================================================
-- 1. Signature changes from `(client: RateQueryTableClient, rateVersionId: string)` to
--    `(client: RateQueryTableClient, rateVersionId: string, actorAuthUserId: string)`
--    (RateQueryTableClient widened to `Pick<SupabaseClient, "from" | "rpc">`, see function 1
--    above -- one shared type change covers this file''s three affected functions).
-- 2. Replace `.from("vendor_rate_versions_directory").select("*")
--    .eq("rate_version_id", rateVersionId).maybeSingle()` with:
--      const { data, error } = await client.rpc("get_rate_version_by_id", {
--        p_rate_version_id: rateVersionId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--      if (error) throw new RateQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseRateVersion(row as Record<string, unknown>);
--    (a set-returning RPC always comes back as an array, never single-row-shaped the way
--    `.maybeSingle()` was -- same `Array.isArray(data) ? data[0] : data` unwrap idiom this
--    remediation effort''s other get-by-id functions already use.)
-- 3. Both call sites already have a live, session-asserted actor id in scope:
--      app/(tenant)/[tenantSlug]/commercial/rates/[rateVersionId]/page.tsx:25
--      `getRateVersionById(supabase, rateVersionId)` ->
--      `getRateVersionById(supabase, rateVersionId, access.authUserId)` (access resolved via
--      resolveCommercialAccessForRequest one line above, line 16).
--      app/(tenant)/[tenantSlug]/procurement/rates/[rateVersionId]/page.tsx:31
--      `getRateVersionById(supabase, rateVersionId)` ->
--      `getRateVersionById(supabase, rateVersionId, access.authUserId)` (access resolved via
--      resolveProcurementAccessForRequest one line above, line 20).
-- 4. Both pages'' own existing post-fetch tenant check
--    (`if (!rate || rate.tenantId !== access.tenant.id) notFound();` on the Commercial page)
--    is unchanged and remains correct -- defense in depth, not a substitute for the RPC''s own
--    tenant-membership row filter.
-- 5. server/queries/rate.test.ts (describe block "getRateVersionById") needs its fake client
--    switched from mocking `.from().select().eq().maybeSingle()` to mocking
--    `.rpc("get_rate_version_by_id", ...)` returning `[VALID_RATE_VERSION_ROW]` -- not
--    attempting that rewrite here, per this task''s scope.

-- ===========================================================================
-- 3. app.list_pending_rate_versions / public.list_pending_rate_versions
--    Replaces: server/queries/rate.ts:52-63 (listPendingRateVersions) --
--    `.from("vendor_rate_versions_directory").select("*").eq("tenant_id", tenantId)
--    .eq("approval_status", "pending_approval").order("created_at", { ascending: false })`.
--    tenant_admin approval review queue.
-- ===========================================================================

create function app.list_pending_rate_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
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
    v.id as rate_version_id,
    v.tenant_id,
    v.master_record_id,
    m.code as vendor_code,
    m.name as vendor_name,
    v.service_type,
    v.mode,
    v.origin_lane,
    v.destination_lane,
    v.equipment_type,
    v.cargo_weight_min,
    v.cargo_weight_max,
    v.cargo_volume_min,
    v.cargo_volume_max,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.currency else null end as currency,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.base_amount else null end as base_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.minimum_amount else null end as minimum_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.surcharge_components else null end as surcharge_components,
    not app.has_view_cost(v.tenant_id, p_actor_auth_user_id) as cost_masked,
    v.approval_status,
    v.effective_from,
    v.effective_to,
    v.supersedes_version_id,
    v.approved_by,
    v.approved_at,
    v.rejected_reason,
    v.withdrawn_reason,
    v.record_version,
    v.created_by,
    v.created_at,
    v.updated_at,
    v.vendor_master_id,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.lead_time_days else null end as lead_time_days,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.capacity_terms else null end as capacity_terms
  from app.vendor_rate_versions v
  join app.master_records m on m.id = v.master_record_id
  where v.tenant_id = p_tenant_id
    and v.approval_status = 'pending_approval'
    and (
      (app.has_active_tenant_membership(v.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(v.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by v.created_at desc;
end;
$$;

comment on function app.list_pending_rate_versions(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: read path for the tenant_admin approval review queue, replacing server/queries/rate.ts:52''s broken .from("vendor_rate_versions_directory"). Every rate version awaiting approval (approval_status = pending_approval) for one tenant, most recently created first. Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A). Row filter reproduces the view''s CURRENT (post-20260730560000-hardening) predicate verbatim: (has_active_tenant_membership AND NOT actor_holds_customer_user_layer) OR is_supreme_admin -- note this is NOT app.is_support_grant_authority (the narrower tenant_admin/Supreme-Admin-only gate app.approve_rate_version/app.reject_rate_version themselves enforce before actually deciding a rate) -- this function only reproduces the view''s own READ authority envelope, which is ordinary tenant membership; the mutation-time authority check is unchanged and still lives in app.approve_rate_version/app.reject_rate_version, not duplicated here. The currency/base_amount/minimum_amount/surcharge_components/lead_time_days/capacity_terms CASE-WHEN cost mask and cost_masked flag are copied verbatim from the view''s own definition, re-expressed with an explicit p_actor_auth_user_id -- the same fix app.search_vendor_rates already established for this exact view. Returns zero rows (never an exception) for a non-member actor, matching the original view-filtered .from() call''s own silent-empty-result posture. No limit/pagination, matching the original .from() call, which never applied .range()/.limit() either.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_pending_rate_versions with an identical grant set, never a
-- reimplementation.
create function public.list_pending_rate_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_pending_rate_versions(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_pending_rate_versions(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_pending_rate_versions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_pending_rate_versions(uuid, uuid) from public;
grant execute on function app.list_pending_rate_versions(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_pending_rate_versions(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_pending_rate_versions(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION: server/queries/rate.ts `listPendingRateVersions`
-- ===========================================================================
-- 1. Add a required `actorAuthUserId: string` parameter (RateQueryTableClient widened to
--    `Pick<SupabaseClient, "from" | "rpc">`, see function 1 above):
--      export async function listPendingRateVersions(
--        client: RateQueryTableClient,
--        tenantId: string,
--        actorAuthUserId: string,
--      ): Promise<RateVersion[]>
-- 2. Replace the `.from("vendor_rate_versions_directory").select("*")
--    .eq("tenant_id", tenantId).eq("approval_status", "pending_approval")
--    .order("created_at", { ascending: false })` chain with:
--      const { data, error } = await client.rpc("list_pending_rate_versions", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    Drop the now-redundant `.order(...)` call -- the RPC already applies
--    `order by v.created_at desc` server-side, and the `approval_status = pending_approval`
--    filter is already applied server-side too.
-- 3. Row mapping/error handling unchanged: `if (error) throw new RateQueryError(
--    error.message); return (data ?? []).map((row: Record<string, unknown>) =>
--    parseRateVersion(row));`.
-- 4. Call site already has a live, session-asserted actor id in scope:
--      app/(tenant)/[tenantSlug]/commercial/rates/page.tsx:39
--      `listPendingRateVersions(supabase, access.tenant.id)` ->
--      `listPendingRateVersions(supabase, access.tenant.id, access.authUserId)` (the same
--      `access.authUserId` already resolved via resolveCommercialAccessForRequest, line 26,
--      and already passed one line above into `listActiveVendorRates` -- note
--      listActiveVendorRates itself reads app.v_active_vendor_rates, not app.vendor_rate_
--      versions_directory directly, and is OUT OF SCOPE for this remediation pass; it is not
--      touched here).
-- 5. server/queries/rate.test.ts (describe block "listPendingRateVersions") needs its fake
--    client switched from mocking the `.from` chain to mocking
--    `.rpc("list_pending_rate_versions", ...)` -- not attempting that rewrite here, per this
--    task''s scope.

-- ===========================================================================
-- 4. app.list_procurement_linked_vendor_rate_versions /
--    public.list_procurement_linked_vendor_rate_versions
--    Replaces: server/queries/procurement-rate.ts:50-62
--    (listProcurementLinkedVendorRateVersions) --
--    `.from("vendor_rate_versions_directory").select("*").eq("tenant_id", tenantId)
--    .not("vendor_master_id", "is", null).order("created_at", { ascending: false })
--    .limit(PROCUREMENT_RATE_LIST_LIMIT)`. Procurement-scoped, all-statuses rate directory.
-- ===========================================================================

create function app.list_procurement_linked_vendor_rate_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
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
    v.id as rate_version_id,
    v.tenant_id,
    v.master_record_id,
    m.code as vendor_code,
    m.name as vendor_name,
    v.service_type,
    v.mode,
    v.origin_lane,
    v.destination_lane,
    v.equipment_type,
    v.cargo_weight_min,
    v.cargo_weight_max,
    v.cargo_volume_min,
    v.cargo_volume_max,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.currency else null end as currency,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.base_amount else null end as base_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.minimum_amount else null end as minimum_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.surcharge_components else null end as surcharge_components,
    not app.has_view_cost(v.tenant_id, p_actor_auth_user_id) as cost_masked,
    v.approval_status,
    v.effective_from,
    v.effective_to,
    v.supersedes_version_id,
    v.approved_by,
    v.approved_at,
    v.rejected_reason,
    v.withdrawn_reason,
    v.record_version,
    v.created_by,
    v.created_at,
    v.updated_at,
    v.vendor_master_id,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.lead_time_days else null end as lead_time_days,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.capacity_terms else null end as capacity_terms
  from app.vendor_rate_versions v
  join app.master_records m on m.id = v.master_record_id
  where v.tenant_id = p_tenant_id
    and v.vendor_master_id is not null
    and (
      (app.has_active_tenant_membership(v.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(v.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by v.created_at desc, v.id desc
  limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_procurement_linked_vendor_rate_versions(uuid, uuid, integer) is
  'CG-AUDIT-2026-09-02 O1: read path for the Procurement-scoped vendor rate directory (PRC-255), replacing server/queries/procurement-rate.ts:51''s broken .from("vendor_rate_versions_directory"). Every rate version linked to a real, registered Procurement vendor identity (vendor_master_id IS NOT NULL, ADR-0020), any approval_status, most recently created first, bounded to the most recent p_limit (default/hard-cap 200, matching the TS-side PROCUREMENT_RATE_LIST_LIMIT constant this replaces). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A). Row filter reproduces the view''s CURRENT (post-20260730560000-hardening) predicate verbatim: (has_active_tenant_membership AND NOT actor_holds_customer_user_layer) OR is_supreme_admin. The cost-masked columns are copied verbatim from the view''s own CASE-WHEN expressions, re-expressed with an explicit p_actor_auth_user_id -- the same fix app.search_vendor_rates already established for this exact view. `limit least(coalesce(p_limit, 200), 200)` is this remediation effort''s own established bounded-list convention (app.list_contacts/app.list_accounts) -- hard-clamped server-side regardless of what an RPC caller supplies, since an RPC is directly callable and must not trust a caller-supplied limit. `order by v.created_at desc, v.id desc` adds a tie-break for deterministic top-N truncation under LIMIT (the original .order()-only call had no such tie-break, but none is needed for correctness there since it never truncated with a LIMIT -- this function does, so one is added here, matching this remediation effort''s own bounded-list convention).';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_procurement_linked_vendor_rate_versions with an identical grant
-- set, never a reimplementation.
create function public.list_procurement_linked_vendor_rate_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_procurement_linked_vendor_rate_versions(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_procurement_linked_vendor_rate_versions(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_procurement_linked_vendor_rate_versions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_procurement_linked_vendor_rate_versions(uuid, uuid, integer) from public;
grant execute on function app.list_procurement_linked_vendor_rate_versions(uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_procurement_linked_vendor_rate_versions(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_procurement_linked_vendor_rate_versions(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION: server/queries/procurement-rate.ts `listProcurementLinkedVendorRateVersions`
-- ===========================================================================
-- 1. Change `ProcurementRateQueryTableClient` from `Pick<SupabaseClient, "from">` to
--    `Pick<SupabaseClient, "from" | "rpc">` (widen the one shared alias -- both affected
--    functions in this file need it; `listVendorRateTiers`, unaffected by this migration,
--    keeps using only `.from` but the widened type is still assignable).
-- 2. Add a required `actorAuthUserId: string` parameter:
--      export async function listProcurementLinkedVendorRateVersions(
--        client: ProcurementRateQueryTableClient,
--        tenantId: string,
--        actorAuthUserId: string,
--      ): Promise<Record<string, unknown>[]>
-- 3. Replace the `.from("vendor_rate_versions_directory").select("*")
--    .eq("tenant_id", tenantId).not("vendor_master_id", "is", null)
--    .order("created_at", { ascending: false }).limit(PROCUREMENT_RATE_LIST_LIMIT)` chain
--    with:
--      const { data, error } = await client.rpc("list_procurement_linked_vendor_rate_versions", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--        p_limit: PROCUREMENT_RATE_LIST_LIMIT,
--      });
--    Drop the `.not(...)`/`.order(...)`/`.limit(...)` calls -- all three are now applied
--    server-side (vendor_master_id IS NOT NULL, order by created_at desc/id desc, limit
--    least(p_limit, 200)). The pre-existing `PROCUREMENT_RATE_LIST_LIMIT = 200` constant
--    (line 47) can stay and simply be threaded through as `p_limit`, or be dropped entirely
--    in favor of the RPC''s own default (200) -- either is correct since they are the same
--    value; keeping the constant preserves the existing "the TS layer states its own bound"
--    documentation value the surrounding comment (lines 38-46) already argues for.
-- 4. Row shape/error handling unchanged: `if (error) throw new ProcurementRateQueryError(
--    error.message); return data ?? [];` -- this function already returns raw
--    Record<string, unknown>[], never parsed through parseRateVersion, so the RPC''s identical
--    column-name output requires no further mapping change.
-- 5. Call site already has a live, session-asserted actor id in scope:
--      app/(tenant)/[tenantSlug]/procurement/rates/page.tsx:29
--      `listProcurementLinkedVendorRateVersions(supabase, access.tenant.id)` ->
--      `listProcurementLinkedVendorRateVersions(supabase, access.tenant.id,
--      access.authUserId)` (access resolved via resolveProcurementAccessForRequest, line 19).
-- 6. server/queries/procurement-rate.test.ts (describe block for this function) needs its
--    fake client switched from mocking `.from().eq().not().order().limit()` to mocking
--    `.rpc("list_procurement_linked_vendor_rate_versions", ...)` -- not attempting that
--    rewrite here, per this task''s scope.

-- ===========================================================================
-- 5. app.list_vendor_rate_versions_for_vendor / public.list_vendor_rate_versions_for_vendor
--    Replaces: server/queries/procurement-rate.ts:64-81 (listVendorRateVersionsForVendor) --
--    `.from("vendor_rate_versions_directory").select("*").eq("tenant_id", tenantId)
--    .eq("vendor_master_id", vendorMasterId).order("created_at", { ascending: false })
--    .limit(PROCUREMENT_RATE_LIST_LIMIT)`.
-- ===========================================================================

create function app.list_vendor_rate_versions_for_vendor(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
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
    v.id as rate_version_id,
    v.tenant_id,
    v.master_record_id,
    m.code as vendor_code,
    m.name as vendor_name,
    v.service_type,
    v.mode,
    v.origin_lane,
    v.destination_lane,
    v.equipment_type,
    v.cargo_weight_min,
    v.cargo_weight_max,
    v.cargo_volume_min,
    v.cargo_volume_max,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.currency else null end as currency,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.base_amount else null end as base_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.minimum_amount else null end as minimum_amount,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.surcharge_components else null end as surcharge_components,
    not app.has_view_cost(v.tenant_id, p_actor_auth_user_id) as cost_masked,
    v.approval_status,
    v.effective_from,
    v.effective_to,
    v.supersedes_version_id,
    v.approved_by,
    v.approved_at,
    v.rejected_reason,
    v.withdrawn_reason,
    v.record_version,
    v.created_by,
    v.created_at,
    v.updated_at,
    v.vendor_master_id,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.lead_time_days else null end as lead_time_days,
    case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.capacity_terms else null end as capacity_terms
  from app.vendor_rate_versions v
  join app.master_records m on m.id = v.master_record_id
  where v.tenant_id = p_tenant_id
    and v.vendor_master_id = p_vendor_master_id
    and (
      (app.has_active_tenant_membership(v.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(v.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by v.created_at desc, v.id desc
  limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_vendor_rate_versions_for_vendor(uuid, uuid, uuid, integer) is
  'CG-AUDIT-2026-09-02 O1: read path for one Procurement vendor''s own rate directory (PRC-255), replacing server/queries/procurement-rate.ts:70''s broken .from("vendor_rate_versions_directory"). Every rate version linked to one specific real, registered vendor identity (vendor_master_id = p_vendor_master_id, ADR-0020), any approval_status, most recently created first, bounded to the most recent p_limit (default/hard-cap 200, matching the TS-side PROCUREMENT_RATE_LIST_LIMIT constant this replaces). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A). Row filter reproduces the view''s CURRENT (post-20260730560000-hardening) predicate verbatim: (has_active_tenant_membership AND NOT actor_holds_customer_user_layer) OR is_supreme_admin -- deliberately NOT narrower merely because a vendor_master_id is supplied (the view itself applies no per-vendor authority narrowing; vendor rates remain tenant-wide reference data, per the original view''s own comment). The cost-masked columns are copied verbatim from the view''s own CASE-WHEN expressions, re-expressed with an explicit p_actor_auth_user_id -- the same fix app.search_vendor_rates already established for this exact view. `limit least(coalesce(p_limit, 200), 200)` and the `order by v.created_at desc, v.id desc` tie-break match app.list_procurement_linked_vendor_rate_versions (function 4 above, same migration, same PROCUREMENT_RATE_LIST_LIMIT-derived bound).';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_vendor_rate_versions_for_vendor with an identical grant set,
-- never a reimplementation.
create function public.list_vendor_rate_versions_for_vendor(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_vendor_rate_versions_for_vendor(p_tenant_id, p_vendor_master_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_vendor_rate_versions_for_vendor(uuid, uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_vendor_rate_versions_for_vendor with an identical grant set, never a reimplementation.';

revoke execute on function app.list_vendor_rate_versions_for_vendor(uuid, uuid, uuid, integer) from public;
grant execute on function app.list_vendor_rate_versions_for_vendor(uuid, uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_vendor_rate_versions_for_vendor(uuid, uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_vendor_rate_versions_for_vendor(uuid, uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION: server/queries/procurement-rate.ts `listVendorRateVersionsForVendor`
-- ===========================================================================
-- 1. Uses the same widened `ProcurementRateQueryTableClient` as function 4 above (`Pick<
--    SupabaseClient, "from" | "rpc">`) -- no separate type change needed.
-- 2. Add a required `actorAuthUserId: string` parameter:
--      export async function listVendorRateVersionsForVendor(
--        client: ProcurementRateQueryTableClient,
--        tenantId: string,
--        vendorMasterId: string,
--        actorAuthUserId: string,
--      ): Promise<Record<string, unknown>[]>
-- 3. Replace the `.from("vendor_rate_versions_directory").select("*")
--    .eq("tenant_id", tenantId).eq("vendor_master_id", vendorMasterId)
--    .order("created_at", { ascending: false }).limit(PROCUREMENT_RATE_LIST_LIMIT)` chain
--    with:
--      const { data, error } = await client.rpc("list_vendor_rate_versions_for_vendor", {
--        p_tenant_id: tenantId,
--        p_vendor_master_id: vendorMasterId,
--        p_actor_auth_user_id: actorAuthUserId,
--        p_limit: PROCUREMENT_RATE_LIST_LIMIT,
--      });
--    Drop the `.order(...)`/`.limit(...)` calls -- both are now applied server-side.
-- 4. Row shape/error handling unchanged: `if (error) throw new ProcurementRateQueryError(
--    error.message); return data ?? [];` -- raw Record<string, unknown>[], same as function 4.
-- 5. No current page.tsx call site exists for this function (grepped repo-wide outside
--    server/queries/*.ts and *.test.ts -- zero hits; server/queries/procurement-rate.ts''s own
--    header comment already flags this file as extending rate.ts''s shape ahead of a UI that
--    has not yet been wired to this particular function) -- only
--    server/queries/procurement-rate.test.ts (describe block "listVendorRateVersionsForVendor",
--    line 124) calls it today, and that test''s fake client will need updating the same way
--    as function 4''s test -- not attempting that rewrite here, per this task''s scope.

-- ===========================================================================
-- FINAL SELF-CHECK (task step 7 -- re-read the draft above and confirm RULE A/RULE B
-- against EVERY function)
-- ===========================================================================
-- RULE A: all five `create function app.*` bodies above open with `perform app.assert_
-- actor_is_session_identity(p_actor_auth_user_id);` as their first executable statement
-- (verified by re-reading each of the five `begin` blocks above in sequence) -- before any
-- table lookup, join, or authority-helper call. All five are granted to `authenticated`
-- (see the five `grant execute on function app.* to authenticated, service_role;`
-- statements above), so all five are RULE-A-reachable and all five carry the check.
-- RULE B: all five row filters use the IDENTICAL, current (post-20260730560000-hardening,
-- post-20260730620000-view-rewrite) predicate --
--   (app.has_active_tenant_membership(v.tenant_id, p_actor_auth_user_id) and not
--    app.actor_holds_customer_user_layer(v.tenant_id, p_actor_auth_user_id))
--   or app.is_supreme_admin(p_actor_auth_user_id)
-- -- verified by re-reading each of the five WHERE clauses above in sequence, cross-checked
-- against both the view's own current CREATE OR REPLACE text (20260730620000:1611) and the
-- base table's own current ALTER POLICY text (20260730560000:355-356), which agree with each
-- other and with what is reproduced above. No function above uses the ORIGINAL (pre-hardening)
-- predicate (`has_active_tenant_membership(tenant_id) or is_supreme_admin()`, without the
-- actor_holds_customer_user_layer exclusion) -- that would under-restrict relative to the
-- current view/policy and was deliberately not used.

-- ===========================================================================
-- TABLE 2 of 4: app.v_active_vendor_rates
-- ===========================================================================
-- O1 query-layer remediation, cluster0 -- app.v_active_vendor_rates
-- ===========================================================================
-- Replaces: server/queries/rate.ts:66-76 (listActiveVendorRates), which does
--   .from("v_active_vendor_rates").select("*").eq("tenant_id", tenantId)
--   .order("vendor_code", { ascending: true })
-- against app.v_active_vendor_rates -- app is not exposed to PostgREST
-- (supabase/config.toml only exposes public/graphql_public), so this call is
-- currently broken in production.
--
-- PRECEDENT / DEFINITIONS READ (most recent create-or-replace of each, per RULE C):
--   * app.v_active_vendor_rates itself: created (drop+create, replacing the
--     PLT-120 seed at 20260717120000_create_master_data.sql:589) in
--     20260724150000_create_commercial_rate_cost_lookup.sql:185-191:
--       create view app.v_active_vendor_rates as
--       select * from app.vendor_rate_versions_directory
--       where approval_status = 'approved'
--         and effective_from <= now()
--         and (effective_to is null or effective_to > now());
--     Never itself redefined since (`grep -rn "create (or replace )?view app\.
--     v_active_vendor_rates"` across supabase/migrations/*.sql: exactly this one
--     hit). It carries no authority predicate of its own -- it is a pure
--     `select *` composition over app.vendor_rate_versions_directory, and
--     therefore inherits that view's row filter (and column shape) automatically,
--     including every later change to that view -- confirmed explicitly by
--     20260730620000's own comment (line 1569: "app.v_active_vendor_rates
--     (select * ...) inherits both automatically").
--   * app.vendor_rate_versions_directory: created 20260724150000:135-171 (30
--     columns, WHERE `app.has_active_tenant_membership(v.tenant_id) or
--     app.is_supreme_admin()` -- no customer_user-layer exclusion at that
--     point), then CREATE OR REPLACE'd in
--     20260730620000_extend_commercial_vendor_rate_for_procurement.sql:1572-1611
--     (PRC-255) -- the CURRENT, and only later, definition
--     (`grep -rn "create (or replace )?view app\.vendor_rate_versions_directory"`:
--     exactly these two hits, 20260730620000 is the later filename). That
--     rewrite (a) appends three trailing columns (vendor_master_id,
--     lead_time_days, capacity_terms -- the latter two cost-masked identically
--     to base_amount, per its own column list lines 1606-1608) for a 34-column
--     shape total, and (b) HARDENS the row filter to
--       where (app.has_active_tenant_membership(v.tenant_id)
--              and not app.actor_holds_customer_user_layer(v.tenant_id))
--             or app.is_supreme_admin();
--     -- its own comment (line 1613) says so explicitly: "Row filter hardened to
--     exclude a customer_user-layer principal entirely ... the same pattern-5
--     predicate every Phase 6 table uses." So, unlike the credit_profiles_
--     directory / accounts precedent from the immediately-preceding batches
--     (20260908020000, 20260909010000) where the *_directory view's own WHERE
--     text was left stale by a later ALTER POLICY on the base table, THIS view
--     was itself explicitly re-issued in lockstep with the hardening and is
--     current, not stale.
--   * app.vendor_rate_versions_select_scoped (base-table RLS policy): created
--     20260724150000:676-678 (`has_active_tenant_membership(tenant_id) or
--     is_supreme_admin()`), then ALTER POLICY'd in
--     20260730560000_harden_customer_user_layer_default_deny.sql:355-356 to
--       using (((app.has_active_tenant_membership(tenant_id)
--                and not app.actor_holds_customer_user_layer(tenant_id))
--               or app.is_supreme_admin()));
--     `grep -rln "vendor_rate_versions_select_scoped"` across
--     supabase/migrations: exactly these two files, no later ALTER -- this is
--     the CURRENT table policy. It is now IDENTICAL in shape to the view's own
--     current WHERE clause above (both post-date and match
--     20260730560000's hardening -- the view catch-up landed 20260730620000,
--     chronologically after the policy ALTER on the same day). RULE B
--     satisfied: the view's own current authority predicate is, and is proven
--     to be, the one actually in force today.
--   * app.search_vendor_rates: created 20260724150000:490-560, then CREATE OR
--     REPLACE'd (signature unchanged) in 20260730620000:1623-1696 to widen its
--     column list to the new 34-column shape (`grep -rn "create (or replace )?
--     function app\.search_vendor_rates"`: exactly these two hits, 20260730620000
--     is the current body, read and used for the analysis below). A
--     `public.search_vendor_rates` Option-2 wrapper already exists
--     (20260826000000_create_public_api_data_wrappers.sql:36740-36756, RGL-394
--     bulk wrapper generation), already granted to authenticated/service_role.
--
-- SEARCH_VENDOR_RATES EQUIVALENCE ANALYSIS (why it is NOT reused directly):
--   1. Authority. app.search_vendor_rates' CURRENT body (20260730620000:1641-1645)
--      gates on
--        v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'View');
--        if not v_decision.allowed then raise ...
--      i.e. it hard-requires the actor to hold the specific, granular, seeded
--      'COM' / 'View' permission via app.evaluate_permission. The view chain's
--      own CURRENT authority test (vendor_rate_versions_directory's WHERE
--      clause / the base table's CURRENT RLS policy, both above) is instead
--      `(has_active_tenant_membership(tenant_id) AND NOT
--      actor_holds_customer_user_layer(tenant_id)) OR is_supreme_admin()` --
--      no COM:View requirement at all. These are NOT the same test, and
--      evaluate_permission's test is NOT provably broader-or-equal:
--        - app.permissions seeds 'COM'/'View' as an ordinary, non-protected,
--          'standard'-category permission (20260716103445_create_roles_
--          permissions.sql:43: `('View', 'COM', 'standard', false)`).
--        - Roles and their permission bindings are fully dynamic, tenant-
--          admin-configured data (app.roles / app.role_versions /
--          app.role_version_permissions, 20260716103445_create_roles_
--          permissions.sql:209-317 -- app.create_role / app.create_role_version
--          / app.set_role_version_permissions) -- there is no static seed that
--          grants every tenant role, or every actor with active tenant
--          membership, the COM:View permission. A tenant is free to configure
--          e.g. a Warehouse/HR/Finance-only staff role with active tenant
--          membership (and no customer_user-layer flag) that was simply never
--          assigned any 'COM' module permission at all.
--        - Such an actor squarely satisfies the view chain's own current
--          test (plain active staff membership, not a customer-portal
--          principal) but would be REJECTED by
--          app.evaluate_permission(...,'COM','View') and therefore by
--          app.search_vendor_rates.
--      So routing this call site through app.search_vendor_rates would be a
--      silent authority regression -- denying access to actors this call
--      site's own current read path (the view) grants today. Per the
--      instructions, this is not something to guess past: no equivalence-or-
--      broader proof exists, so search_vendor_rates is rejected as unsafe to
--      reuse for this call site.
--   2. Ordering / limiting. The call site does an unfiltered browse ordered by
--      `vendor_code asc` with no limit (server/queries/rate.ts:66-76).
--      app.search_vendor_rates orders `by base_amount nulls last, vendor_code,
--      rate_version_id` (cost-first) with `limit least(coalesce(p_limit, 20),
--      200)` -- default 20, i.e. a bounded shortlist/comparison tool (its own
--      header comment, 20260724150000:471-489/562-563, is explicit that this
--      is deliberately "a bounded, single-lane comparison lookup ... not a
--      paginated full master-data browse"). Reusing it here would silently
--      change both the sort order and the effective page size for every
--      existing caller of this "simple unfiltered browse" shape -- a second,
--      independent reason not to reuse it even setting authority aside.
--   Conclusion: write a new, purpose-built app.* function that reproduces the
--   view chain's own actual (current) authority test and the call site's own
--   actual (vendor_code-ordered, unfiltered) behavior -- exactly the same
--   choice app.list_accounts/app.list_credit_profiles made for the
--   structurally identical "tenant-wide masked directory browse" shape in the
--   immediately-preceding batches of this same remediation effort
--   (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:279-336,
--   20260909010000_close_o1_query_layer_cluster0_batch3_costing_credit_approval.sql:680-806).
--
-- Deliberately queries app.vendor_rate_versions/app.master_records directly,
-- never app.vendor_rate_versions_directory/app.v_active_vendor_rates
-- themselves: those views' CASE/WHERE expressions call
-- app.has_view_cost(v.tenant_id)/app.has_active_tenant_membership(v.tenant_id)
-- relying on those helpers' *default* auth.uid() argument, which is only
-- correct when queried live under PostgREST with a real JWT/session GUC set --
-- composing a SECURITY DEFINER function on top of such a view would silently
-- return zero rows whenever called without a live session GUC. This is the
-- exact tension app.search_vendor_rates' own header already documented
-- (20260724150000:478-489) and the exact fix this function reapplies with an
-- explicit p_actor_auth_user_id threaded through every masking/authority call.
--
-- RULE A: takes p_actor_auth_user_id and is reachable by `authenticated` --
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the
-- first executable statement (plpgsql body).
--
-- Column shape: all 34 columns of the CURRENT app.vendor_rate_versions_directory
-- projection (20260730620000), field for field, in the same order -- matches
-- server/contracts/rate/rate.ts's RateVersionSchema/parseRateVersion for the
-- first 30 (it ignores unknown keys by default, zod's own `z.object()`
-- behavior, so the 3 trailing PRC-255 columns are harmless extras on the wire
-- today); no deliberate column exclusion.
--
-- Bounded-list convention: BOUNDED_LIST_LIMIT (200), the same repository-wide
-- cap app.list_accounts/app.list_credit_profiles/app.list_rfqs/
-- app.list_finance_invoices/app.list_api_keys_for_tenant/app.query_audit_logs
-- already use (`limit least(coalesce(p_limit, 200), 200)`), server-side
-- clamped regardless of what is requested. The original `.from()` call site
-- had no `.limit()` at all (genuinely open-ended tenant-wide browse, same
-- shape as app.list_accounts/app.list_credit_profiles) -- see the disclosed,
-- small behavior change in the TS INTEGRATION note at the bottom.
--
-- Ordering: `order by vendor_code asc` is the call site's own exact behavior
-- (server/queries/rate.ts:71); `, rate_version_id asc` is appended purely as a
-- deterministic tie-break for rows sharing the same vendor_code (a vendor can
-- have many lanes/services), since Postgres does not guarantee stable order
-- across ties otherwise -- it never changes the primary sort key the caller
-- asked for.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit
-- `revoke execute ... from public` below. Per ISS-2026-309 (closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): the public.*
-- wrapper below revokes from `anon, authenticated, service_role, public`
-- (all four) before re-granting only the roles the app.* counterpart itself
-- grants (authenticated, service_role -- same set
-- `grant select on app.v_active_vendor_rates to authenticated, service_role;`,
-- 20260724150000:711, already used).
-- ===========================================================================

create function app.list_active_vendor_rates(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- RULE B: reproduces the CURRENT vendor_rate_versions_select_scoped RLS
  -- predicate (20260730560000_harden_customer_user_layer_default_deny.sql:355-356),
  -- which is also the CURRENT app.vendor_rate_versions_directory view WHERE
  -- clause (20260730620000_extend_commercial_vendor_rate_for_procurement.sql:1611)
  -- -- the two are identical today, see header analysis above.
  if not (
    (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
       and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    or app.is_supreme_admin(p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list active vendor rates for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      v.id as rate_version_id,
      v.tenant_id,
      v.master_record_id,
      m.code as vendor_code,
      m.name as vendor_name,
      v.service_type,
      v.mode,
      v.origin_lane,
      v.destination_lane,
      v.equipment_type,
      v.cargo_weight_min,
      v.cargo_weight_max,
      v.cargo_volume_min,
      v.cargo_volume_max,
      case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.currency else null end,
      case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.base_amount else null end,
      case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.minimum_amount else null end,
      case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.surcharge_components else null end,
      not app.has_view_cost(v.tenant_id, p_actor_auth_user_id),
      v.approval_status,
      v.effective_from,
      v.effective_to,
      v.supersedes_version_id,
      v.approved_by,
      v.approved_at,
      v.rejected_reason,
      v.withdrawn_reason,
      v.record_version,
      v.created_by,
      v.created_at,
      v.updated_at,
      v.vendor_master_id,
      case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.lead_time_days else null end,
      case when app.has_view_cost(v.tenant_id, p_actor_auth_user_id) then v.capacity_terms else null end
    from app.vendor_rate_versions v
    join app.master_records m on m.id = v.master_record_id
    where v.tenant_id = p_tenant_id
      and v.approval_status = 'approved'
      and v.effective_from <= now()
      and (v.effective_to is null or v.effective_to > now())
    order by m.code asc, v.id asc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_active_vendor_rates(uuid, uuid, integer) is
  'O1 remediation: replaces server/queries/rate.ts:66 listActiveVendorRates''s broken .from("v_active_vendor_rates") (app is not exposed to PostgREST). Reproduces app.v_active_vendor_rates'' own current defining SELECT (approved + currently-effective rows of the CURRENT, 34-column app.vendor_rate_versions_directory, 20260730620000) directly against the base tables app.vendor_rate_versions/app.master_records -- never the views themselves, to avoid a nested-SECURITY-DEFINER auth.uid() reliance (the fix app.search_vendor_rates/app.list_accounts/app.list_credit_profiles already established). currency/base_amount/minimum_amount/surcharge_components/lead_time_days/capacity_terms are nulled (cost_masked=true) unless the actor holds COM:View cost (app.has_view_cost). Row scope reproduces the CURRENT vendor_rate_versions_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin, 20260730560000) -- deliberately NOT app.search_vendor_rates, whose evaluate_permission(COM,View) gate is a distinct, dynamically tenant-configured, strictly narrower permission that could deny an actor this view chain''s own current test grants (see this migration''s file header for the full equivalence analysis), and whose base_amount-first ordering with a default limit of 20 does not match this call site''s own vendor_code-ascending, originally-unbounded browse. Ordered by vendor_code (m.code) ascending with a rate_version_id tie-break, matching the original .order("vendor_code", {ascending: true}) call; server-side clamped to <=200 rows regardless of what is requested (BOUNDED_LIST_LIMIT convention, mirrors app.list_accounts/app.list_credit_profiles). Raises insufficient_authority (never a silent empty page) when the actor has no standing for p_tenant_id at all, matching app.list_accounts/app.list_credit_profiles for this same "list for one named tenant" shape.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin
-- security-definer pass-through to app.list_active_vendor_rates with an
-- identical grant set, never a reimplementation.
create function public.list_active_vendor_rates(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  rate_version_id uuid,
  tenant_id uuid,
  master_record_id uuid,
  vendor_code text,
  vendor_name text,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  cargo_weight_min numeric,
  cargo_weight_max numeric,
  cargo_volume_min numeric,
  cargo_volume_max numeric,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  surcharge_components jsonb,
  cost_masked boolean,
  approval_status text,
  effective_from timestamptz,
  effective_to timestamptz,
  supersedes_version_id uuid,
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  withdrawn_reason text,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  vendor_master_id uuid,
  lead_time_days integer,
  capacity_terms text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_active_vendor_rates(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_active_vendor_rates(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_active_vendor_rates with an identical grant set, never a reimplementation.';

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default before any role-specific grant.
revoke execute on function app.list_active_vendor_rates(uuid, uuid, integer) from public;
grant execute on function app.list_active_vendor_rates(uuid, uuid, integer) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309: a bare
-- `revoke ... from public` does not strip the anon/authenticated EXECUTE
-- grants Supabase's ALTER DEFAULT PRIVILEGES rule applies to every new
-- function in schema public at CREATE time, so all four roles are revoked
-- explicitly before re-granting exactly the app.* function's own grant set
-- (authenticated, service_role -- no anon).
revoke execute on function public.list_active_vendor_rates(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_active_vendor_rates(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION: server/queries/rate.ts's listActiveVendorRates (lines 66-76)
-- ===========================================================================
-- Replace:
--   const { data, error } = await client
--     .from("v_active_vendor_rates")
--     .select("*")
--     .eq("tenant_id", tenantId)
--     .order("vendor_code", { ascending: true });
--   if (error) { throw new RateQueryError(error.message); }
--   return (data ?? []).map((row) => parseRateVersion(row));
--
-- with:
--   const { data, error } = await client.rpc("list_active_vendor_rates", {
--     p_tenant_id: tenantId,
--     p_actor_auth_user_id: actorAuthUserId,
--   });
--   if (error) { throw new RateQueryError(error.message); }
--   return (data ?? []).map((row: Record<string, unknown>) => parseRateVersion(row));
--
-- `actorAuthUserId` must be threaded into `listActiveVendorRates`'s own
-- signature (it currently takes only `client`/`tenantId`) -- the caller's own
-- session identity, exactly as every other RPC'd query in this remediation
-- effort requires (app.assert_actor_is_session_identity rejects any mismatch
-- against auth.uid() for a real `authenticated` session). `RateQueryTableClient`
-- (currently `Pick<SupabaseClient, "from">`) must widen to
-- `Pick<SupabaseClient, "from" | "rpc">`, matching the pattern already used by
-- every other query module this remediation effort has touched.
-- `parseRateVersion` needs no change: it already ignores unrecognized keys, so
-- the RPC's 3 additional PRC-255 columns (vendor_master_id, lead_time_days,
-- capacity_terms) pass through harmlessly.
-- No caller of listActiveVendorRates currently asks for more than the default
-- 200-row cap; if one later does, thread an optional `limit` parameter through
-- to `p_limit`.
-- ===========================================================================

-- ===========================================================================
-- TABLE 3 of 4: app.rate_selections_directory
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1 remediation -- app.rate_selections_directory read path.
--
-- Replaces the broken PostgREST read at server/queries/rate.ts:81
-- (listRateSelectionsForRequest: `.from("rate_selections_directory").select("*")
-- .eq("costing_request_id", costingRequestId).order("created_at", { ascending: false })` --
-- "Field-masked rate selections for one costing request, most recently created first --
-- reads through app.rate_selections_directory, never the base table directly.").
-- select_vendor_rate (a mutation) writes app.rate_selections; no read over
-- rate_selections_directory exists anywhere else in the codebase (confirmed by grepping
-- "rate_selections_directory" across every *.ts/*.tsx file: only server/queries/rate.ts's
-- own broken .from() call, server/queries/rate.test.ts's mock of it, and two doc-comment
-- mentions in server/contracts/rate/rate.ts show up).
--
-- app.rate_selections_directory is a VIEW (not a base table), created in
-- supabase/migrations/20260724150000_create_commercial_rate_cost_lookup.sql:200-220. It
-- lives in the "app" Postgres schema, which supabase/config.toml never exposes to
-- PostgREST ("public"/"graphql_public" only) -- so this .from() call has never worked in
-- production; it 404s as a nonexistent relation from PostgREST's point of view.
--
-- RULE B check: grepped `create policy`/`alter policy` against "rate_selections" across
-- every file in supabase/migrations/*.sql (sorted by filename/date) -- exactly one hit,
-- `rate_selections_select_scoped`, CREATEd once in 20260724150000 (lines 680-687) and never
-- touched by any later ALTER POLICY anywhere in the repo. In particular,
-- 20260730560000_harden_customer_user_layer_default_deny.sql (the migration that added
-- `AND NOT app.actor_holds_customer_user_layer(tenant_id)` to 98 policies whose entire test
-- was a bare `app.has_active_tenant_membership` call) DOES touch its sibling
-- `vendor_rate_versions_select_scoped` (that file, line 355) but never names
-- `rate_selections_select_scoped` or any `rate_selections` table at all -- confirmed by
-- grepping "rate" against that file. `create or replace view app.rate_selections_directory`
-- also does not appear anywhere outside its one 20260724150000 CREATE VIEW (confirmed by
-- grepping "rate_selections_directory" repo-wide: the only other hits are a doc-style
-- reference-in-a-comment in 20260724180000 and two build-review comments in
-- 20260730670000, neither of which redefines the view). The predicate reproduced below is
-- therefore the CURRENT, only-ever-declared authority envelope -- no later hardening was
-- ever layered onto this table.
--
-- AUTHORITY / MASKING RULE ENFORCED, AND WHY
-- -------------------------------------------
-- Row visibility: restates `rate_selections_select_scoped` verbatim (20260724150000,
-- lines 680-687) --
--   exists (select 1 from app.costing_requests cr where cr.id = rate_selections.costing_request_id
--     and app.can_access_record((select auth.uid()), cr.tenant_id, cr.owner_user_id,
--         app.lead_record_scope_org_unit_ids(cr.org_unit_id), null))
-- -- expressed below as an inner join + WHERE filter (required because this function is
-- SECURITY DEFINER and runs as its owner, so the base table's/view's own RLS-derived row
-- filter is never evaluated for it -- the identical reason the view's own comment gives for
-- adding its own explicit app.can_access_record(...) filter rather than trusting RLS, and
-- the identical reason app.list_costing_responses_for_request (this same remediation
-- effort's batch 3, 20260909010000_close_o1_query_layer_cluster0_batch3_costing_credit_
-- approval.sql:221-272) restates costing_responses_select_scoped). No
-- app.evaluate_permission(...) module:permission check gates row visibility itself -- only
-- the three masked columns are gated that way (see below) -- so adding one to the row
-- filter would EXCEED the declared read-authority envelope, not match it.
-- RULE C check on app.can_access_record: grepped
-- "create or replace function app.can_access_record|create function app.can_access_record"
-- repo-wide -> exactly two hits: 20260716110430_create_field_record_access.sql (original)
-- and 20260723180000_create_commercial_sales_pipeline.sql (CREATE OR REPLACE, COM-146 --
-- coalesces the whole OR expression to `false` so a NULL owner_user_id can never silently
-- read as SQL NULL/falsy-but-unguarded). The 5-arg signature and body reproduced in the
-- WHERE clause below (actor, tenant_id, owner_user_id, shared_org_unit_ids, customer_ref)
-- is that CURRENT, patched version -- not the original.
--
-- Column masking: currency/amount/snapshot are nulled, and cost_masked computed, via
-- `app.has_view_cost(tenant_id, actor)` -- the same seeded, protected COM:View cost
-- permission (app.evaluate_permission(actor, tenant, 'COM', 'View cost')) COM-148's sibling
-- directory uses -- copied verbatim from the view's own three expressions (20260724150000,
-- lines 208-211). override_reason and selected_by are NOT masked (also copied verbatim
-- from the view: lines 212-213 sit outside the has_view_cost CASE-WHEN entirely) --
-- reproduced below unconditionally, matching the view exactly. RULE C check on
-- app.has_view_cost: grepped "create or replace function app.has_view_cost|create function
-- app.has_view_cost" repo-wide -> exactly one hit (its original 20260724090000 definition,
-- never redefined), so that is already its current, correct body -- nothing to reconcile.
-- `authenticated` has no direct column-level grant on currency/amount/snapshot on the base
-- table (20260724150000, lines 705-707 grant only
-- id, tenant_id, costing_request_id, rate_version_id, is_adhoc, override_reason,
-- selected_by, created_at) -- this function, like the view, is the only legal place this
-- masking logic may live.
--
-- WHY THE MASKING IS RE-EXPRESSED AGAINST THE BASE TABLE, NOT BY SELECTING FROM THE VIEW:
-- the view's own CASE expressions call app.has_view_cost(s.tenant_id) relying on that
-- helper's *default* `auth.uid()` argument -- correct only under a live PostgREST
-- request/session GUC, not when invoked from a SECURITY DEFINER function called via RPC.
-- This is the exact same tension app.search_vendor_rates
-- (20260724150000_create_commercial_rate_cost_lookup.sql:490-558) and, in this same
-- remediation effort, app.list_costing_responses_for_request (batch 3, cited above) already
-- resolved by re-expressing the view's masking directly against its base table with an
-- explicit p_actor_auth_user_id argument instead of the view's default-auth.uid() call.
-- This function does the identical thing for app.rate_selections_directory.
--
-- Precedent modeled on:
--  * Primary shape/style precedent: app.list_costing_responses_for_request /
--    app.list_costing_response_components (batch 3 of this same remediation effort,
--    20260909010000_close_o1_query_layer_cluster0_batch3_costing_credit_approval.sql:
--    221-322) -- the closest same-shape precedent named in this task: a masked directory
--    view, joined through the SAME owning app.costing_requests row via the SAME
--    app.can_access_record call, re-expressed as `language plpgsql`,
--    `perform assert_actor_is_session_identity` first, `returns table (...)`, non-defaulted
--    `p_actor_auth_user_id`, and an identical Option-2 wrapper/grant convention. Followed
--    line-for-line here; the only structural difference is which base table/directory view
--    is being restated (app.rate_selections / app.rate_selections_directory instead of
--    app.costing_responses / app.costing_responses_directory) and that three columns are
--    masked here (currency/amount/snapshot) instead of two (currency/total_amount).
--  * `p_actor_auth_user_id` as an explicit, non-defaulted parameter (no `default
--    auth.uid()`) -- matches every sibling read function over this same costing-request
--    detail page built across batches 1 and 3 (app.get_costing_request_by_id,
--    app.list_costing_requests_for_opportunity, app.list_costing_request_components,
--    app.list_costing_responses_for_request, app.list_costing_response_components). Every
--    real caller resolves it server-side via lib/portal/commercial-guard.ts's
--    `authUserId`/`resolveCommercialAccessForRequest`'s `access.authUserId`, never raw
--    client input. This function's only caller (the SAME costing-request detail page,
--    app/(tenant)/[tenantSlug]/commercial/costing-requests/[requestId]/page.tsx) already
--    has that exact `access.authUserId` in scope four lines above its own call site.
--
-- select_vendor_rate (app.select_vendor_rate, most recent body at
-- 20260827130000_harden_tenant_disclosure_representative_extension_batch2.sql:94-...) was
-- checked per RULE C/step 3 as a candidate authority precedent and NOT reused: it is a
-- mutation gated on COM:Edit AND COM:View cost (an actor may not commit a cost figure to a
-- costing request they cannot see the cost of back) -- that dual gate is strictly
-- NARROWER than the actual SELECT authority (`rate_selections_select_scoped`/the view),
-- which admits any caller who can reach the owning costing_request's record-scope
-- regardless of COM:Edit or COM:View cost (COM:View cost only gates which COLUMNS come
-- back, per-row, not row visibility itself). Reusing select_vendor_rate's authority check
-- for a plain read would silently narrow the read below its declared RLS/view envelope --
-- exactly the failure mode RULE C exists to prevent. app.can_access_record (the same
-- primitive the view and the RLS policy both already use) is the correct, non-narrowing
-- choice, not select_vendor_rate's write-side gate.
--
-- Deliberate column exclusion: none beyond what the view already masks -- this function
-- returns exactly the view's 12-column projection (id, tenant_id, costing_request_id,
-- rate_version_id, is_adhoc, currency, amount, snapshot, cost_masked, override_reason,
-- selected_by, created_at), never any other raw app.rate_selections column. currency/
-- amount/snapshot are nulled per-row (never omitted from the shape), exactly matching the
-- view's own cost_masked contract; server/contracts/rate/rate.ts's parseRateSelection
-- consumes exactly these 12 keys 1:1 (snake_case -> camelCase), so the shape is preserved
-- exactly.
--
-- No p_limit/pagination: the original `.from(...)` call site never applied a
-- `.range()`/`.limit()` either, and this reads a single costing request's own rate
-- selection history (one row per app.select_vendor_rate call against that request) -- a
-- bounded, small, human-driven list, not an unbounded feed. Matches every sibling function
-- on this same costing-request detail page, which reasoned identically and added no limit.
--
-- RULE A: this function is `authenticated`-reachable (see grant below) and takes an
-- explicit p_actor_auth_user_id -- app.assert_actor_is_session_identity(p_actor_auth_user_id)
-- is therefore its first executable statement, before any lookup or authority check.

create function app.list_rate_selections_for_request(
  p_costing_request_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  costing_request_id uuid,
  rate_version_id uuid,
  is_adhoc boolean,
  currency text,
  amount numeric,
  snapshot jsonb,
  cost_masked boolean,
  override_reason text,
  selected_by text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select
    s.id,
    s.tenant_id,
    s.costing_request_id,
    s.rate_version_id,
    s.is_adhoc,
    case when app.has_view_cost(s.tenant_id, p_actor_auth_user_id) then s.currency else null end as currency,
    case when app.has_view_cost(s.tenant_id, p_actor_auth_user_id) then s.amount else null end as amount,
    case when app.has_view_cost(s.tenant_id, p_actor_auth_user_id) then s.snapshot else null end as snapshot,
    not app.has_view_cost(s.tenant_id, p_actor_auth_user_id) as cost_masked,
    s.override_reason,
    s.selected_by,
    s.created_at
  from app.rate_selections s
  join app.costing_requests cr on cr.id = s.costing_request_id
  where s.costing_request_id = p_costing_request_id
    and app.can_access_record(
      p_actor_auth_user_id, cr.tenant_id, cr.owner_user_id,
      app.lead_record_scope_org_unit_ids(cr.org_unit_id), null
    )
  order by s.created_at desc;
end;
$$;

comment on function app.list_rate_selections_for_request(uuid, uuid) is
  'COM-149 read (CG-AUDIT-2026-09-02 O1): read path for app.rate_selections_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/RULE A). Row-visibility filter (join to app.costing_requests + app.can_access_record against tenant/owner/org-unit scope) reproduces rate_selections_select_scoped''s own CURRENT RLS predicate verbatim (confirmed via repo-wide grep: no later rewrite of this policy exists, and 20260730560000''s customer_user-layer hardening pass never named it). The currency/amount/snapshot CASE-WHEN mask and cost_masked flag are copied verbatim from the view''s own definition (20260724150000, lines 208-211), re-expressed against the base table with an explicit p_actor_auth_user_id instead of the view''s own default-auth.uid masking -- the same fix app.search_vendor_rates and app.list_costing_responses_for_request already established for the identical default-auth.uid-in-a-view-under-RPC problem. override_reason/selected_by are reproduced unmasked, exactly as the view leaves them. Returns zero rows (never an exception) for a nonexistent costing_request_id or an actor who cannot reach that request''s tenant/owner/org-unit scope, matching the original RLS-filtered view''s own silent-empty-result posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_rate_selections_for_request with an identical grant set, never
-- a reimplementation.
create function public.list_rate_selections_for_request(
  p_costing_request_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  costing_request_id uuid,
  rate_version_id uuid,
  is_adhoc boolean,
  currency text,
  amount numeric,
  snapshot jsonb,
  cost_masked boolean,
  override_reason text,
  selected_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_rate_selections_for_request(p_costing_request_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_rate_selections_for_request(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_rate_selections_for_request with an identical grant set, never a reimplementation.';

-- app.list_rate_selections_for_request: same grant set as the view it replaces
-- (`grant select on app.rate_selections_directory to authenticated, service_role;`,
-- 20260724150000, line 712).
revoke execute on function app.list_rate_selections_for_request(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function app.list_rate_selections_for_request(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO
-- anon, authenticated, service_role` bootstrap grant on the public schema) -- pattern per
-- 20260907150000_fix_remaining_tenant_lookup_guards_postgrest_schema_exposure_iss_o1_o2.sql:69-91,
-- and identically applied in this remediation effort's own batch 3
-- (app.list_costing_responses_for_request, cited above).
revoke execute on function public.list_rate_selections_for_request(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_rate_selections_for_request(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/rate.ts, function listRateSelectionsForRequest (lines 78-89).
--
-- Current real signature (checked, not assumed): `listRateSelectionsForRequest(client:
-- RateQueryTableClient, costingRequestId: string): Promise<RateSelection[]>` -- it does
-- NOT currently take an actorAuthUserId at all, unlike this file's own
-- listPendingRateVersions/listActiveVendorRates (which take a plain tenantId, not an
-- actor). A new required parameter must be added.
--
-- 1. Client type: `RateQueryTableClient` is currently `Pick<SupabaseClient, "from">`
--    (server/queries/rate.ts:17) -- unlike costing.ts's CostingQueryTableClient, "rpc" is
--    NOT already part of this file's shared alias (no other function in rate.ts calls
--    .rpc() today). Widen it to `Pick<SupabaseClient, "from" | "rpc">` -- the other four
--    functions in this file (listRateVersionsForMasterRecord, getRateVersionById,
--    listPendingRateVersions, listActiveVendorRates) keep using `.from()` against
--    app.vendor_rate_versions_directory/app.v_active_vendor_rates unchanged; those two
--    views are a separate, out-of-scope O1 gap (also currently-broken PostgREST reads, not
--    part of this task) and are not touched here.
--
-- 2. Add a required third parameter `actorAuthUserId: string`:
--      export async function listRateSelectionsForRequest(
--        client: RateQueryTableClient,
--        costingRequestId: string,
--        actorAuthUserId: string,
--      ): Promise<RateSelection[]>
--
-- 3. Replace the `.from(...)` chain (lines 80-84) with:
--      const { data, error } = await client.rpc("list_rate_selections_for_request", {
--        p_costing_request_id: costingRequestId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    Drop the now-redundant `.order(...)` call -- the RPC already applies
--    `order by s.created_at desc` server-side.
--
-- 4. Row mapping is unchanged: the RPC returns the identical 12-column shape, in the
--    identical column names, as the old view select (id, tenant_id, costing_request_id,
--    rate_version_id, is_adhoc, currency, amount, snapshot, cost_masked, override_reason,
--    selected_by, created_at) -- so the existing
--    `(data ?? []).map((row: Record<string, unknown>) => parseRateSelection(row))` on
--    line 88 needs no change at all. Error handling (`if (error) throw new
--    RateQueryError(error.message)`) is also unchanged -- .rpc() surfaces errors in the
--    same shape as .from().
--
-- 5. The function's exported return type (`Promise<RateSelection[]>`) does not change.
--
-- 6. Call site needing the new third argument -- already has a live, session-asserted
--    actor id in scope, no new plumbing required:
--      app/(tenant)/[tenantSlug]/commercial/costing-requests/[requestId]/page.tsx:69
--      `listRateSelectionsForRequest(supabase, request.id)` ->
--      `listRateSelectionsForRequest(supabase, request.id, access.authUserId)` (the same
--      `access.authUserId` already in scope and already passed into
--      `getCostingRequestById`/`listCostingRequestComponents`/
--      `listCostingResponsesForRequest`/`listMarginCalculationsForRequest` on lines 39, 54,
--      55, and 82 of the same page). This call currently sits inside a
--      `Promise.all([listRateSelectionsForRequest(...), listActiveVendorRates(...)])`
--      wrapped in its own try/catch (lines 67-78) -- only the first element of that array
--      needs the new argument; listActiveVendorRates is untouched (out of scope, see (1)).
--
-- 7. server/queries/rate.test.ts (describe block "listRateSelectionsForRequest", starting
--    line 155) mocks a `.from`-based client today (`fakeTableClient`) and will need
--    updating to mock `.rpc("list_rate_selections_for_request", ...)` instead, returning a
--    plain row array (snake_case columns, same shape as today's fake `.from()` response
--    rows, e.g. VALID_SELECTION_ROW) -- not attempting this rewrite here per this task's
--    scope.

-- ===========================================================================
-- TABLE 4 of 4: app.vendor_rate_tiers_directory
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 0 continuation,
-- app.vendor_rate_tiers_directory read path.
--
-- Replaces the broken PostgREST read at server/queries/procurement-rate.ts:26-36
-- (listVendorRateTiers: `.from("vendor_rate_tiers_directory").select("*")
-- .eq("rate_version_id", rateVersionId).order("tier_order", { ascending: true })`).
-- supabase/config.toml only exposes "public"/"graphql_public" to PostgREST -- the
-- "app" Postgres schema, where app.vendor_rate_tiers_directory actually lives, is
-- completely invisible to it. This .from() call has never worked in production; it
-- 404s as a nonexistent relation from PostgREST's point of view.
--
-- SOURCE OF TRUTH (RULE C -- precedent staleness, independently re-confirmed)
-- ------------------------------------------------------------------------
-- app.vendor_rate_tiers_directory is a VIEW (not a base table), created at
-- supabase/migrations/20260730620000_extend_commercial_vendor_rate_for_procurement.sql:
-- 405-426:
--   create view app.vendor_rate_tiers_directory
--   as
--   select
--     t.id,
--     t.tenant_id,
--     t.rate_version_id,
--     t.tier_order,
--     t.weight_min,
--     t.weight_max,
--     t.volume_min,
--     t.volume_max,
--     case when app.has_prc_view_cost(t.tenant_id) then t.amount else null end as amount,
--     case when app.has_prc_view_cost(t.tenant_id) then t.minimum_charge else null end as minimum_charge,
--     not app.has_prc_view_cost(t.tenant_id) as cost_masked,
--     t.record_version,
--     t.created_by,
--     t.created_at,
--     t.updated_at
--   from app.vendor_rate_tiers t
--   where (app.has_active_tenant_membership(t.tenant_id) and not app.actor_holds_customer_user_layer(t.tenant_id)) or app.is_supreme_admin();
-- Grepped `create view app.vendor_rate_tiers_directory` and `create or replace
-- view.*vendor_rate_tiers_directory` across every file in supabase/migrations/*.sql
-- (sorted by filename): three files mention the string
-- (20260730620000 itself, 20260730670000_harden_procurement_batch_257_259_review_
-- fixes.sql, 20260902030000_add_vendor_rate_zone_distance_pricing_iss2026060.sql),
-- but the latter two only REFERENCE the view name in a comment ( 20260730670000's
-- single hit is prose inside a `comment on function app.select_vendor_rate` string;
-- 20260902030000 explicitly documents its own new, PARALLEL,
-- never-merged-with-app.vendor_rate_tiers sibling table/view --
-- app.vendor_rate_zone_distance_tiers / app.vendor_rate_zone_distance_tiers_
-- directory -- and says so in its own header: "PARALLEL to (never touching) app.
-- vendor_rate_tiers"). Neither file contains a `create or replace view` for
-- app.vendor_rate_tiers_directory itself. This is therefore both the original AND
-- the current definition -- no later rewrite to reconcile.
--
-- RULE B -- authority envelope (current RLS predicate, not merely the original)
-- ------------------------------------------------------------------------
-- Grepped `create policy`/`alter policy` naming `app.vendor_rate_tiers` and the bare
-- policy name `vendor_rate_tiers_select_scoped` across every file in
-- supabase/migrations/*.sql, sorted by filename: the ONLY hit anywhere is the
-- original declaration at 20260730620000:1706-1708:
--   create policy vendor_rate_tiers_select_scoped on app.vendor_rate_tiers
--     for select to authenticated
--     using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());
-- No later ALTER POLICY exists (repo-wide `alter policy.*vendor_rate` only matches
-- the UNRELATED `vendor_rate_versions_select_scoped` policy, hardened separately at
-- 20260730560000_harden_customer_user_layer_default_deny.sql:355 -- a different
-- table/policy this checkpoint does not touch). This table's own policy was
-- authored with the hardened pattern-5 predicate from the start (the migration's
-- own design note 14 says so explicitly: "app.vendor_rate_tiers_directory (new)
-- uses the identical hardened predicate from the start"), so it needed no
-- retrofit and has none. The read authority below reproduces this exact predicate,
-- with an explicit p_actor_auth_user_id in place of each helper's own default
-- auth.uid().
--
-- Also grepped `alter table app.vendor_rate_tiers\b` repo-wide: zero hits --
-- app.vendor_rate_tiers has never had a column added/dropped/renamed since its
-- original 20260730620000:374-398 definition (20260902030000's own new zone/
-- distance tier table is a wholly separate, parallel table, explicitly disclosed as
-- never touching this one). The 15-column shape reproduced below is still
-- exhaustive and current.
--
-- Helper functions re-confirmed current (RULE C, each grepped for
-- `create function app.<name>|create or replace function app.<name>` across every
-- file in supabase/migrations/*.sql, sorted by filename, most recent body used):
--   * app.has_prc_view_cost(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- exactly one hit, 20260730590000_create_procurement_vendor_assessment.sql:457,
--     never replaced. `select (app.evaluate_permission(p_auth_user_id, p_tenant_id,
--     'PRC', 'View cost')).allowed;` -- the exact PRC:View cost gate ADR-0020
--     directs this checkpoint's own sensitive-field class to reuse.
--   * app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default
--     auth.uid()) -- three hits (20260716105512 original, 20260716111315 support-
--     access widening, 20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64
--     the CURRENT `create or replace`, CG-AUDIT-2026-09-02 D3b). The D3b body
--     additionally excludes an identity whose app.users row is suspended/revoked,
--     ORs in app.is_supreme_admin(p_auth_user_id) and
--     app.has_active_support_grant(p_tenant_id, p_auth_user_id). Because the view's
--     WHERE clause calls this helper BY NAME (not a pinned body), it already
--     transparently absorbed the D3b hardening the moment that migration ran with
--     zero changes of its own -- this function reproduces that same current
--     behavior by calling the identical current helper, explicit actor argument
--     supplied instead of the default.
--   * app.actor_holds_customer_user_layer(p_tenant_id uuid, p_auth_user_id uuid
--     default auth.uid()) -- exactly one hit, 20260730311000_harden_customer_
--     inventory_access_rls_isolation.sql:71, never replaced.
--   * app.is_supreme_admin(p_auth_user_id uuid default auth.uid()) -- exactly one
--     REAL `create function` hit, 20260716105512_create_rls_tenant_policies.sql:45,
--     never replaced (a later batch-3 migration's own header comment merely QUOTES
--     this same grep result as its own RULE C confirmation -- verified by reading
--     it directly; it is prose, not a second definition).
--   * app.assert_actor_is_session_identity(p_actor_auth_user_id uuid) -- exactly one
--     REAL `create or replace function` hit, 20260730440000_harden_actor_identity_
--     session_crosscheck.sql:59, never replaced (this same remediation effort's own
--     batch 2 file quotes it in prose only, not a second definition -- verified by
--     reading it directly). Degrades to "no session identity known" (skips the
--     mismatch check) rather than raising when auth.uid() itself throws or returns
--     null -- safe under a service_role/nested-SECURITY-DEFINER call.
--
-- MASKING REPLICATION -- exact, line-for-line reproduction of the view's own 2
-- CASE-WHEN pairs (amount/minimum_charge gated on app.has_prc_view_cost) plus its
-- cost_masked boolean -- not a reimplementation or simplification. The only change
-- from the view's own text is passing p_actor_auth_user_id explicitly as the second
-- argument to app.has_prc_view_cost/app.has_active_tenant_membership/app.actor_
-- holds_customer_user_layer/app.is_supreme_admin instead of relying on their own
-- `default auth.uid()` -- the identical compose-on-a-view-keyed-to-auth.uid()-
-- under-a-SECURITY-DEFINER-RPC fix this same remediation effort's batch 2
-- (app.list_margin_calculations_for_request) and batch 4
-- (app.list_quotation_lines) already applied, tracing back to app.search_vendor_
-- rates and app.list_customer_contract_price_components. `authenticated` has no
-- direct column grant on amount/minimum_charge on the base table itself (only the
-- narrower column-list grant at 20260730620000:1715-1718, which explicitly omits
-- exactly those two columns), so this function is the only place the masking logic
-- may legally live.
--
-- RULE A: this function takes an explicit p_actor_auth_user_id and is granted to
-- `authenticated` (mirrors the view's own
-- `grant select on app.vendor_rate_tiers_directory to authenticated, service_role;`,
-- 20260730620000:1721), so
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the
-- first executable statement, before any lookup or authority check -- confirmed by
-- self-check below (RULE A self-check: PASS -- it is the sole statement preceding
-- `return query`).
--
-- Precedent modeled on: app.list_quotation_lines (this exact remediation effort's
-- own batch 4, supabase/migrations/20260909020000_close_o1_query_layer_cluster0_
-- batch4_leads_prospects_quotation_directory.sql:2708-2774) -- the most recent
-- already-shipped fix in this repository for an identical "PRC/COM-cost-masked
-- `_directory` view over a table joined through its owning parent row, unreachable
-- via .from(), needs re-expression against the base table with an explicit actor
-- argument" shape. That function's own header traces the auth.uid()-default fix
-- back to app.search_vendor_rates and app.list_customer_contract_price_components;
-- the same reasoning applies here verbatim. Unlike app.list_quotation_lines,
-- app.vendor_rate_tiers has no owning-parent JOIN to reproduce for row visibility
-- (the tenant_id column lives directly on app.vendor_rate_tiers itself, not only on
-- a parent row) -- the WHERE clause below is a direct, single-table reproduction of
-- vendor_rate_tiers_select_scoped, which is itself simpler than
-- quotation_lines_select_scoped's own EXISTS-through-app.quotations shape.
--
-- Deliberate column exclusion: none -- all 15 columns of the view's own projection
-- are returned, in the view's own column order (amount/minimum_charge nulled
-- per-row via cost_masked, exactly matching the view's own contract, never omitted
-- from the shape). This is also the exact 15-field shape server/contracts/
-- procurement-rate/procurement-rate.ts's VendorRateTierSchema (parseVendorRateTier)
-- already expects.
--
-- No p_limit/pagination: the original .from() call itself never paginated (no
-- `.range()`/`.limit()` in server/queries/procurement-rate.ts:26-36), and one rate
-- version has at most a small, bounded number of tiers (a single rate's own pricing
-- ladder, not an open-ended tenant-wide list) -- the identical rationale this same
-- remediation effort's app.list_quotation_lines already documented for the sibling
-- "one parent row's own child rows" shape. Adding a limit would change behavior
-- relative to the call this replaces, so none is added here.
--
-- Ordering: reproduces the original call's own `.order("tier_order", { ascending:
-- true })` server-side (`order by t.tier_order asc`).
--
-- Row-visibility posture: returns zero rows (never an exception) for a nonexistent
-- rate_version_id or an actor with no tenant-membership/support-grant/supreme-admin
-- access to that row's tenant (including a customer_user-layer principal, which the
-- view's own hardened pattern-5 predicate excludes entirely, not merely masks),
-- matching the original RLS-filtered view's own silent-empty-result posture.

create function app.list_vendor_rate_tiers(
  p_rate_version_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  tenant_id uuid,
  rate_version_id uuid,
  tier_order integer,
  weight_min numeric,
  weight_max numeric,
  volume_min numeric,
  volume_max numeric,
  amount numeric,
  minimum_charge numeric,
  cost_masked boolean,
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
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select
    t.id,
    t.tenant_id,
    t.rate_version_id,
    t.tier_order,
    t.weight_min,
    t.weight_max,
    t.volume_min,
    t.volume_max,
    case when app.has_prc_view_cost(t.tenant_id, p_actor_auth_user_id) then t.amount else null end as amount,
    case when app.has_prc_view_cost(t.tenant_id, p_actor_auth_user_id) then t.minimum_charge else null end as minimum_charge,
    not app.has_prc_view_cost(t.tenant_id, p_actor_auth_user_id) as cost_masked,
    t.record_version,
    t.created_by,
    t.created_at,
    t.updated_at
  from app.vendor_rate_tiers t
  where t.rate_version_id = p_rate_version_id
    and (
      (app.has_active_tenant_membership(t.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(t.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by t.tier_order asc;
end;
$$;

comment on function app.list_vendor_rate_tiers(uuid, uuid) is
  'O1 remediation: read path for app.vendor_rate_tiers_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup. Row-visibility filter reproduces the CURRENT vendor_rate_tiers_select_scoped RLS policy / view WHERE clause verbatim (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin -- the hardened pattern-5 shape this table''s policy was authored with from the start, per 20260730620000''s own design note 14) -- confirmed via grep that no later ALTER POLICY exists for this table. The amount/minimum_charge CASE-WHEN mask (PRC:View cost, app.has_prc_view_cost) is copied verbatim from the view''s own definition (20260730620000_extend_commercial_vendor_rate_for_procurement.sql:405-426, never since replaced), re-expressed against the base table with an explicit p_actor_auth_user_id instead of the view''s default-auth.uid masking -- the same fix app.list_quotation_lines (this same remediation effort''s batch 4) already established for the identical auth.uid-in-a-view-under-RPC problem, tracing back to app.search_vendor_rates and app.list_customer_contract_price_components. Returns zero rows (never an exception) for a nonexistent rate_version_id or an actor with no tenant access to it, matching the original RLS-filtered view''s own silent-empty-result posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin
-- security-definer pass-through to app.list_vendor_rate_tiers with an identical
-- grant set, never a reimplementation.
create function public.list_vendor_rate_tiers(
  p_rate_version_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  tenant_id uuid,
  rate_version_id uuid,
  tier_order integer,
  weight_min numeric,
  weight_max numeric,
  volume_min numeric,
  volume_max numeric,
  amount numeric,
  minimum_charge numeric,
  cost_masked boolean,
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
  select * from app.list_vendor_rate_tiers(p_rate_version_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_vendor_rate_tiers(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_vendor_rate_tiers with an identical grant set, never a reimplementation.';

-- app.list_vendor_rate_tiers: same grant set as the view it replaces
-- (`grant select on app.vendor_rate_tiers_directory to authenticated,
-- service_role;`, 20260730620000_extend_commercial_vendor_rate_for_procurement.sql:1721).
revoke execute on function app.list_vendor_rate_tiers(uuid, uuid) from public;
grant execute on function app.list_vendor_rate_tiers(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309: Supabase's own ALTER DEFAULT
-- PRIVILEGES rule grants EXECUTE on every new public.* function to `anon` and
-- `authenticated` at CREATE FUNCTION time, so `revoke ... from public` alone (the
-- PUBLIC pseudo-role) never removes those two role-specific grants. Revoke all four
-- explicitly, then grant back only the roles app.list_vendor_rate_tiers itself
-- grants to, minus anon.
revoke execute on function public.list_vendor_rate_tiers(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_vendor_rate_tiers(uuid, uuid) to authenticated, service_role;

-- FINAL SELF-CHECK (performed before finishing, per task instructions)
-- ------------------------------------------------------------------------
-- RULE A: app.list_vendor_rate_tiers takes an explicit p_actor_auth_user_id, is
-- granted to `authenticated`, and its FIRST executable statement is
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` -- before
-- the `return query` lookup, before any authority/masking check. PASS.
-- RULE B: the `where` clause's `(app.has_active_tenant_membership(t.tenant_id,
-- p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(t.tenant_id,
-- p_actor_auth_user_id)) or app.is_supreme_admin(p_actor_auth_user_id)` predicate is
-- structurally identical (modulo the explicit actor argument replacing each
-- helper's own default auth.uid()) to the CURRENT (and only-ever)
-- vendor_rate_tiers_select_scoped policy body and the view's own WHERE clause, both
-- re-grepped immediately above with no later ALTER POLICY / CREATE OR REPLACE VIEW
-- found. PASS.

-- TS INTEGRATION:
-- File: server/queries/procurement-rate.ts, function listVendorRateTiers
-- (line 26-36). Current real signature (confirmed by reading the file, not
-- assumed): `listVendorRateTiers(client: ProcurementRateQueryTableClient,
-- rateVersionId: string): Promise<VendorRateTier[]>` -- it takes NO actor/auth
-- parameter today at all (the old .from() call relied entirely on the caller's own
-- PostgREST session/JWT via RLS); one must be added.
--
-- 1. Add an `actorAuthUserId: string` parameter to listVendorRateTiers's own
--    signature:
--      export async function listVendorRateTiers(
--        client: ProcurementRateQueryTableClient,
--        rateVersionId: string,
--        actorAuthUserId: string,
--      ): Promise<VendorRateTier[]> {
--
-- 2. Widen `ProcurementRateQueryTableClient` (line 16, currently
--    `Pick<SupabaseClient, "from">`) to `Pick<SupabaseClient, "from" | "rpc">` --
--    listProcurementLinkedVendorRateVersions/listVendorRateVersionsForVendor keep
--    using "from" against app.vendor_rate_versions_directory unchanged for now
--    (that view has the identical PostgREST-unreachable problem, but its own
--    read-function remediation is a separate, independently-tracked work item, out
--    of scope here); only listVendorRateTiers switches to "rpc". This is the
--    identical widening this same remediation effort's app.list_quotation_lines fix
--    already applied to its own sibling QuotationQueryTableClient.
--
-- 3. Replace the body:
--      const { data, error } = await client
--        .from("vendor_rate_tiers_directory")
--        .select("*")
--        .eq("rate_version_id", rateVersionId)
--        .order("tier_order", { ascending: true });
--    with:
--      const { data, error } = await client.rpc("list_vendor_rate_tiers", {
--        p_rate_version_id: rateVersionId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (p_* argument names exactly as declared above: p_rate_version_id first, then
--    p_actor_auth_user_id -- both required from the TS side even though the SQL
--    signature defaults p_actor_auth_user_id to auth.uid().) Drop the
--    now-redundant `.order(...)` call -- the RPC already applies
--    `order by t.tier_order asc` server-side.
--
-- 4. Row mapping is unchanged: the RPC returns the identical 15-column shape, in
--    the identical order, as the old view select (and exactly the shape
--    server/contracts/procurement-rate/procurement-rate.ts's VendorRateTierSchema/
--    parseVendorRateTier already expects), so
--    `(data ?? []).map((row: Record<string, unknown>) => parseVendorRateTier(row))`
--    needs no change at all. Error handling (`if (error) throw new
--    ProcurementRateQueryError(error.message)`) is also unchanged -- .rpc() surfaces
--    errors the same shape as .from().
--
-- 5. The function's exported return type (`Promise<VendorRateTier[]>`) does not
--    change.
--
-- 6. Caller update: app/(tenant)/[tenantSlug]/procurement/rates/[rateVersionId]/
--    page.tsx:32 (`tiers = await listVendorRateTiers(supabase, rateVersionId);`)
--    must pass a third argument. The page already resolves
--    `const access = await resolveProcurementAccessForRequest(tenantSlug);` at
--    line 20, whose "allowed" variant (lib/portal/procurement-guard.ts:38) carries
--    `readonly authUserId: string` -- pass `access.authUserId` through as the new
--    third argument, exactly the "actor auth_user_id it already has on hand from a
--    sibling call on the same page" pattern this same remediation effort's
--    app.list_quotation_lines TS-integration note already applied.
--
-- 7. server/queries/procurement-rate.test.ts's "queries the field-masked
--    vendor_rate_tiers_directory view, filtered by rate_version_id, ordered by
--    tier_order" test (describe("listVendorRateTiers"), line 76-90) currently
--    asserts on `capture.calls.table`/`capture.calls.eqCalls`/
--    `capture.calls.orderColumn`/`capture.calls.ascending` via the shared
--    `fakeTableClient` helper (which only implements `.from()`); it (and the two
--    sibling tests in the same describe block, lines 92-103, "returns an empty
--    array" and "throws ProcurementRateQueryError on a real error") must switch to
--    a fake implementing `.rpc()` and assert on the function name
--    ("list_vendor_rate_tiers") and its args object
--    (p_rate_version_id/p_actor_auth_user_id) instead, and pass a third
--    `actorAuthUserId` argument to every `listVendorRateTiers(client, ...)` call --
--    the same restructuring this same remediation effort's
--    server/queries/quotation.test.ts equivalent (listQuotationLines) already
--    applied. The two sibling describe blocks in this file
--    (listProcurementLinkedVendorRateVersions, listVendorRateVersionsForVendor) are
--    unaffected -- those two functions keep using `.from()` unchanged (item 2
--    above).
