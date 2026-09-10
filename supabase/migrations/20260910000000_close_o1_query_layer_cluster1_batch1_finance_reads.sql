-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 1 (finance) batch 1 of ~N.
-- Continues the same Design->Verify->Fix adversarial pipeline cluster 0's batches
-- 1-5 established (RULE A/B/C baked into every draft and every independent verify
-- pass below), user-directed ("lanjut sampe siap launching") extension of
-- CG-AUDIT-2026-09-02's Ø1-query-layer finding: supabase/config.toml only exposes
-- "public"/"graphql_public" to PostgREST, so every .from() read against the "app"
-- schema has never worked in production. Cluster 0 (CRM/commercial, 32 tables) is
-- now fully closed; this migration opens cluster 1 (finance, 6 tables / 8 call
-- sites per docs/build-log/remediation/CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json).
--
-- 8 new app.*/public.* Option-2 wrapper function pairs across 6 tables/views:
--   app.shipment_actual_costs_directory (VIEW): app.get_shipment_actual_cost
--   app.billing_readiness_evaluations (BASE TABLE): app.get_current_billing_readiness_
--                                        evaluation, app.list_billing_readiness_evaluations
--                                        (kept as two separate functions, matching the
--                                        existing TS layer's own two-function shape,
--                                        rather than merging via an only_current flag)
--   app.billing_readiness_handoffs (BASE TABLE): app.list_billing_readiness_handoffs
--   app.finance_currencies (BASE TABLE):  app.list_finance_currencies
--   app.finance_rounding_modes (BASE TABLE): app.list_finance_rounding_modes
--   app.finance_period_close_checklist_items (BASE TABLE): app.list_finance_period_
--                                        checklist_items
--   app.job_profitability_directory (VIEW): app.get_job_profitability_directory
--
-- Notable design decision, independently verified: app.list_finance_currencies and
-- app.list_finance_rounding_modes are declared SECURITY INVOKER (the unmarked
-- default), not SECURITY DEFINER like every other function in this remediation
-- series -- both tables carry a bare `using (true)` SELECT policy for role
-- `authenticated` plus a direct table-level `grant select ... to authenticated`,
-- so the real calling role already has everything it needs; this matches the
-- established live precedent for this exact "global reference table, zero actor
-- param, zero tenant scoping" shape (app.list_api_versions/app.api_versions,
-- app.list_webhook_event_types/app.webhook_event_types, both also unmarked-invoker
-- over an identical bare-true/authenticated-grant table). This deviation from the
-- otherwise-universal SECURITY DEFINER pattern was independently re-derived and
-- confirmed by an adversarial verify pass (which also confirmed the table-level
-- grants that make invoker mode actually work, not merely infer it from the
-- precedent functions' own declarations) before being included here.
--
-- Every function below was independently adversarially re-verified against the
-- live repo state (not merely its own draft's claims) before being included in
-- this migration. Two real (non-functional, citation/prose-only) issues were
-- found and fixed during that verify pass: (1) the finance-currencies/rounding-
-- modes draft's own precedent citation for app.list_webhook_event_types pointed
-- at the migration that creates the underlying TABLE, not the one that declares
-- the function itself -- corrected to the accurate file/line. (2) No SQL logic in
-- any of the 8 functions needed correction -- every other table (actual-cost/
-- billing-readiness, finance-period-checklist-items, job-profitability-directory)
-- passed independent adversarial re-verification, including an actual run of
-- scripts/security/check-rls-initplan.ts against each draft, with zero issues
-- found.
--
-- DISCLOSED, OUT-OF-SCOPE FINDINGS (different tables, different clusters/batches;
-- recorded here so they are not silently rediscovered, matching this series' own
-- established disclosure convention):
--   1. supabase/migrations/20260830140000_create_incident_communication.sql's own
--      `comment on function app.list_incident_communication_audiences` (line 406)
--      cited "app.list_finance_currencies' own precedent" for a function that did
--      not exist anywhere in this repository before this migration -- a dangling
--      forward citation, now retroactively made true by this migration. A
--      citation-accuracy defect, not a security bug.
--   2. That SAME migration's app.list_incident_communication_audiences()/
--      public.list_incident_communication_audiences() pair appears to be a
--      genuinely live, different defect: both are declared invoker (no `security
--      definer`), but the underlying table has RLS enabled with NO create policy
--      at all, and `revoke all ... from public, anon, authenticated` (only
--      service_role is granted). Unlike app.api_versions/app.webhook_event_types
--      (which DO grant SELECT to authenticated and DO carry a `using (true)`
--      policy, making invoker mode correct), an authenticated caller invoking
--      this function would hit a real Postgres permission-denied error, not
--      return rows. Out of scope for this batch (a different table, a different
--      cluster of this same Ø1 effort) -- flagged here rather than left for
--      whoever owns that read path to rediscover.
--
-- All 6 affected TS query files (server/queries/actual-cost.ts, billing-
-- readiness.ts, currency-exchange-rate.ts, finance-config.ts, fiscal-period.ts,
-- job-profitability.ts) and every real page.tsx call site are switched from
-- .from() to .rpc() in this same commit, per each function's own embedded TS
-- INTEGRATION note below. getBillingReadinessEvaluationHistory has no live
-- page.tsx caller today (only unit tests reference it) -- fixed anyway since the
-- broken .from() read it replaces is broken regardless of caller count; same for
-- listFinanceRoundingModes.
--
-- This migration closes 8 of cluster 1's 8 call sites across 6 tables -- cluster
-- 1 (finance, 6 tables/8 call sites) is now fully DONE. Clusters 2-7 (96 more
-- .from() call sites across identity/dispatch/tracking/documents/analytics/misc)
-- remain, per CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json.

-- ===========================================================================
-- TABLE 1 of 4: app.shipment_actual_costs_directory + app.billing_readiness_evaluations
-- + app.billing_readiness_handoffs (OPS/Finance job-order-scoped reads)
-- ===========================================================================
-- CG-AUDIT-2026-09-02 Ø1-query-layer remediation -- cluster 1 (finance), batch 1 of ~N:
-- OPS/Finance job-order-scoped reads: actual-cost header (Ops shipment-order detail) and
-- billing-readiness evaluation/handoff (Ops job-order detail).
--
-- SCOPE: closes 4 of cluster 1's broken `.from()` call sites, across 2 tables/views:
--   1. app.shipment_actual_costs_directory (VIEW)      server/queries/actual-cost.ts:30
--      (getShipmentActualCost)
--   2. app.billing_readiness_evaluations   (BASE TABLE) server/queries/billing-readiness.ts:27
--      (getCurrentBillingReadinessEvaluation, is_current=true, .maybeSingle())
--   3. app.billing_readiness_evaluations   (BASE TABLE) server/queries/billing-readiness.ts:36
--      (getBillingReadinessEvaluationHistory, unfiltered, order by version_number asc --
--      kept as a SEPARATE app.* function from #2, per this batch's own explicit scope, to
--      minimize behavior change vs. the existing TS layer rather than merging into one
--      parameterized function)
--   4. app.billing_readiness_handoffs      (BASE TABLE) server/queries/billing-readiness.ts:45
--      (listBillingReadinessHandoffs, order by handed_off_at desc)
--
-- SEVERITY (unchanged from every prior Ø1 batch's own header): supabase/config.toml
-- (`schemas = ["public", "graphql_public"]`) never exposes "app" to PostgREST -- every
-- `.from()` call in the 2 TS files above against these `app.*` relations has NEVER worked
-- in production. This sits behind two real, reachable pages: the Shipment Order detail
-- page's Actual Cost panel (`app/(tenant)/[tenantSlug]/operations/shipment-orders/
-- [shipmentOrderId]/page.tsx`) and the Job Order detail page's Billing Readiness panel
-- (`app/(tenant)/[tenantSlug]/operations/job-orders/[jobOrderId]/page.tsx`) -- a live,
-- currently-broken read path, not merely an architectural backlog item.
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior Ø1 remediation commit in this
-- series, cluster 0 batches 1-5): for each broken `.from()` read, author a new `app.*`
-- SECURITY DEFINER function performing the equivalent SELECT with correct tenant/RLS/
-- authority scoping (taking the actor id as an explicit `p_actor_auth_user_id` parameter,
-- never relying on `auth.uid()` session context -- a SECURITY DEFINER function runs as its
-- owner and never evaluates the caller's own RLS), plus a thin `public.*` pass-through
-- wrapper (the only PostgREST-reachable surface, since `app` itself is invisible) carrying
-- an IDENTICAL grant set -- never a reimplementation. 4 new `app.*`/`public.*` function
-- pairs total across the 2 tables/1 view above.
--
-- MANDATORY RULES applied to every function below (baked into every prior Ø1 batch's own
-- design/verify process; independently re-derived here, not assumed from any recon
-- restatement):
--
--   RULE A (actor-impersonation guard, ATW-031/032, ISS-2026-017/032): every new app.*
--   function below takes an explicit `p_actor_auth_user_id` and is granted to
--   `authenticated` (see grants below), so `perform app.assert_actor_is_session_identity
--   (p_actor_auth_user_id);` is the FIRST executable statement in every function body,
--   before any lookup or authority check. Confirmed against app.assert_actor_is_session_
--   identity's own CURRENT (and only-ever, `create or replace`) body -- 20260730440000_
--   harden_actor_identity_session_crosscheck.sql:59 -- a no-op whenever the session
--   `auth.uid` is null (service_role/superuser/db-tests/nested SECURITY DEFINER calls),
--   raising `actor_identity_mismatch` only when a genuine authenticated session's own
--   identity differs from the claimed `p_actor_auth_user_id`. Repo-wide grep for
--   "create or replace function app.assert_actor_is_session_identity" /
--   "create function app.assert_actor_is_session_identity" (sorted by filename) confirms
--   exactly one hit, this one -- there is no later rewrite of this helper.
--
--   RULE B (RLS predicate currency): row-visibility predicates below reproduce the CURRENT
--   RLS predicate for each relation, verified by grepping BOTH `create policy`/`alter
--   policy` naming each table AND each policy's own bare name across every file in
--   supabase/migrations/*.sql, sorted by filename:
--     * `shipment_actual_costs_select_scoped` -- exactly ONE hit, its original `create
--       policy` at 20260728110000_create_operations_actual_cost.sql:707. No later `alter
--       policy` of any kind touches this policy or this table anywhere in the repo
--       (grepped `alter policy.*shipment_actual_costs` repo-wide: zero hits). Also checked
--       whether 20260730560000_harden_customer_user_layer_default_deny.sql (the migration
--       that layered a customer_user-layer exclusion onto 98 tenant-membership-only
--       policies) touches this table: grepped "shipment_actual_costs" against that one
--       file -- zero hits, confirming it is out of that hardening's own scope (this
--       policy was never a bare has_active_tenant_membership test to begin with -- it
--       composes app.can_access_record, which already folds has_active_tenant_membership
--       into its own first conjunct). The 20260728110000 predicate is therefore still the
--       CURRENT, only-ever-declared version.
--     * `billing_readiness_evaluations_select_scoped` / `billing_readiness_handoffs_select_
--       scoped` -- exactly ONE hit each, both original `create policy` statements at
--       20260728140000_create_operations_billing_readiness.sql:502 and :512. Repo-wide grep
--       for "alter policy.*billing_readiness" and for both bare policy names (sorted by
--       filename across every migrations file) returns zero hits beyond those two original
--       CREATE POLICY statements -- no later rewrite of either policy exists anywhere.
--       20260730560000 was also checked against these two tables by name -- zero hits,
--       same reasoning as above (both already compose app.can_access_record via a join to
--       app.job_orders, never a bare has_active_tenant_membership test).
--   All three predicates share the identical shape -- `exists (select 1 from <parent
--   table> parent where parent.id = <this row>.<fk> and app.can_access_record((select
--   auth.uid()), parent.tenant_id, parent.owner_user_id, app.lead_record_scope_org_unit_
--   ids(parent.org_unit_id), null))` -- restated below as an explicit join + WHERE filter
--   (required because a SECURITY DEFINER function never evaluates the invoker's own RLS),
--   with `(select auth.uid())` replaced by the function's own explicit
--   `p_actor_auth_user_id` parameter instead of the policy's session-bound default.
--
--   RULE C (precedent staleness): every existing app.* function cited below as an
--   authority-check or shape precedent was independently re-confirmed against its MOST
--   RECENT `create or replace function`, not merely its original creation migration:
--     * app.can_access_record(uuid, uuid, uuid, uuid[], text) -- repo-wide grep for
--       "create or replace function app.can_access_record" / "create function app.can_
--       access_record" finds exactly two hits: 20260716110430_create_field_record_
--       access.sql (original) and 20260723180000_create_commercial_sales_pipeline.sql
--       (COM-146 patch). 20260723180000 is the later file by filename/date and is the body
--       reproduced below (`has_active_tenant_membership(...) and coalesce(is_supreme_admin
--       OR exact-owner-match OR shared-org-unit-membership OR customer-account-ref-
--       membership, false)` -- the defense-in-depth `coalesce(..., false)` wrapper COM-146
--       added so a NULL p_owner_user_id can never silently resolve to a NULL/falsy-but-
--       unguarded grant). This is the same current body every cluster-0 batch already
--       independently confirmed.
--     * app.lead_record_scope_org_unit_ids(uuid) -- repo-wide grep for "create or replace
--       function app.lead_record_scope_org_unit_ids" / "create function app.lead_record_
--       scope_org_unit_ids" finds exactly one hit, 20260723090000_create_commercial_lead_
--       management.sql:164 -- never replaced, so that original body (own org unit plus
--       every ancestor, via app.org_unit_ancestor_ids) is already current.
--     * app.has_view_actual_cost(uuid, uuid) -- repo-wide grep for "create or replace
--       function app.has_view_actual_cost" / "create function app.has_view_actual_cost"
--       finds exactly one hit, 20260728110000_create_operations_actual_cost.sql:64 --
--       never replaced. Current body: a thin wrapper delegating to app.evaluate_permission
--       for the OPS module's "View cost" action. Its second parameter defaults to
--       `auth.uid` in its own declaration -- app.get_shipment_actual_cost below always
--       supplies its own explicit `p_actor_auth_user_id` for that argument rather than
--       relying on the default, the same "explicit actor arg instead of a nested-call
--       default-auth reliance" fix app.list_costing_responses_for_request/app.list_credit_
--       profiles (cluster 0 batch 3) already established for the structurally identical
--       "view masks a column via a helper whose own default reads session state, re-
--       express against the base table with an explicit actor arg instead" problem.
--
-- WHY THE MASKING (function #1 only) IS RE-EXPRESSED AGAINST THE BASE TABLE, NOT BY
-- SELECTING FROM THE VIEW: app.shipment_actual_costs_directory's own CASE expressions call
-- `app.has_view_actual_cost(sac.tenant_id)` relying on that helper's own default `auth.uid`
-- argument and its own outer `where app.can_access_record(auth.uid(), ...)` filter --
-- reading it directly from inside a SECURITY DEFINER RPC would keep both of those tied to
-- session state rather than the function's own explicit actor parameter. This function
-- instead re-expresses the view's exact same 19-column projection and masking logic
-- directly against app.shipment_actual_costs, the same fix cluster 0's app.search_vendor_
-- rates / app.list_costing_responses_for_request / app.list_customer_contract_price_
-- components already established for this identical class of problem.
--
-- billing_readiness_evaluations / billing_readiness_handoffs carry NO masked/`_directory`
-- view at all (confirmed: `create or replace view app.billing_readiness_evaluations_
-- directory` / `..._handoffs_directory` -- zero hits repo-wide) -- per this capability's
-- own design header (20260728140000:1-11), no money amount is ever exposed here, only
-- evidence status/blockers, so functions #2-#4 below need only the row-visibility join,
-- never a column-masking CASE expression.
--
-- DELIBERATE COLUMN EXCLUSION (contract fidelity, the "return exactly what the TS contract
-- consumes" discipline cluster 0 batch 4's app.prospects fix established -- checked against
-- the REAL contract files, not assumed):
--   * app.get_shipment_actual_cost: server/contracts/actual-cost/actual-cost.ts's own
--     ShipmentActualCostDirectoryRowSchema/parseShipmentActualCostDirectoryRow consumes
--     all 19 columns app.shipment_actual_costs_directory itself already projects (id,
--     tenant_id, shipment_order_id, version_number, is_current, supersedes_version_id,
--     status, currency, estimated_amount, total_amount, cost_masked, approved_by_auth_
--     user_id, approved_at, rejection_reason, adjustment_reason, record_version,
--     created_by, created_at, updated_at) -- no exclusion needed, this function's own
--     RETURNS TABLE reproduces exactly those 19 columns.
--   * app.get_current_billing_readiness_evaluation / app.list_billing_readiness_
--     evaluations: app.billing_readiness_evaluations has 26 physical columns, but
--     server/contracts/billing-readiness/billing-readiness.ts's own
--     BillingReadinessEvaluationSchema/parseBillingReadinessEvaluation consumes only 25 of
--     them -- `overridden_by_auth_user_id` (uuid) is NOT read by parseBillingReadinessEvaluation
--     at all (only the sibling text label `overridden_by` is: `overriddenBy: row.
--     overridden_by`); confirmed independently against both the contract's own field list
--     and server/queries/billing-readiness.test.ts's own EVALUATION_ROW fixture, which
--     likewise never sets `overridden_by_auth_user_id`. Both new functions' RETURNS TABLE
--     therefore deliberately excludes `overridden_by_auth_user_id`, returning the other 25
--     columns (id, tenant_id, job_order_id, version_number, is_current, evaluated_status,
--     effective_status, blockers, evidence, rule_version, is_overridden, override_reason,
--     overridden_by, overridden_at, override_revoked_reason, override_revoked_by,
--     override_revoked_at, reevaluation_reason, supersedes_evaluation_id, evaluated_by_
--     auth_user_id, evaluated_by, record_version, created_by, created_at, updated_at) --
--     `evaluated_by_auth_user_id` IS kept (the contract's own `evaluatedByAuthUserId` field
--     reads it). `effective_status` is a Postgres GENERATED (stored) column -- selected like
--     any ordinary column, no special handling needed.
--   * app.list_billing_readiness_handoffs: app.billing_readiness_handoffs has exactly 9
--     physical columns (id, tenant_id, job_order_id, evaluation_id, idempotency_key,
--     handed_off_by_auth_user_id, handed_off_by, handed_off_at, created_at), and server/
--     contracts/billing-readiness/billing-readiness.ts's own BillingReadinessHandoffSchema/
--     parseBillingReadinessHandoff consumes all 9 -- no exclusion; this function is
--     declared `returns setof app.billing_readiness_handoffs` (the same "no masking, no
--     exclusion, return the whole row" shape cluster 0 batch 3's app.list_costing_response_
--     components already established for a structurally identical case).
--
-- ROW-NOT-FOUND / DENIED-ACCESS BEHAVIOR: all four functions below return zero rows --
-- never an exception -- for a nonexistent id, a cross-tenant one, or an in-tenant one the
-- actor cannot otherwise reach (app.can_access_record already folds app.has_active_tenant_
-- membership into its own first conjunct, so a non-member sees the same empty result as a
-- genuinely nonexistent id, per ISS-2026-146's tenant-id-disclosure posture). This matches
-- the original RLS-filtered `.from()` reads' own silent-empty-result posture exactly, and
-- the existing TS layer's own handling (`.maybeSingle()` -> null; `data ?? []` -> `[]`) --
-- no TS error-handling change is needed for the not-found/denied case, only for the
-- .from()-to-.rpc() call shape itself (see TS INTEGRATION section at the end of this file).
--
-- No p_limit/pagination on any of the four: none of the original `.from()` call sites ever
-- applied a `.range()`/`.limit()` either, and each reads exactly one shipment order's own
-- current actual-cost header, or one job order's own bounded evaluation-version history /
-- handoff history -- small, human-scale, per-record lists, not an unbounded tenant-wide
-- feed (matches every prior Ø1 batch's identical reasoning for this same "single parent
-- record's own child rows" shape).
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own explicit
-- `revoke execute on all functions in schema app from public` before its final grants, the
-- standing per-migration convention. Per ISS-2026-309 (closed by 20260830200000_correct_
-- public_wrapper_grant_parity.sql): every public.* wrapper below explicitly revokes from
-- `anon, authenticated, service_role, public` (all four) before re-granting exactly the
-- roles its app.* counterpart itself grants -- a bare `revoke ... from public` does NOT
-- strip the `anon`/`authenticated` EXECUTE grants Supabase's own ALTER DEFAULT PRIVILEGES
-- rule applies to every new function in schema public at CREATE time.
--
-- check-rls-initplan.ts false-positive avoidance: per this repository's own established
-- practice (first applied at cluster 0 batches 3/5), every `comment on function ... is
-- '...'` string below avoids combining the literal phrase "create policy"/"alter policy"
-- with a bare, parenthesized `auth.uid()`/`auth.jwt()` mention in the same string -- e.g.
-- "no later rewrite of this policy exists" instead of "no later ALTER POLICY exists", and
-- `auth.uid` written without a trailing call where it would otherwise sit near such a
-- phrase. The guard itself is never suppressed, only the prose reworded.

-- ===========================================================================
-- 1. app.get_shipment_actual_cost -- replaces server/queries/actual-cost.ts:30
--    (getShipmentActualCost)
-- ===========================================================================
-- Replaces: `.from("shipment_actual_costs_directory").select("*")
-- .eq("shipment_order_id", shipmentOrderId).eq("is_current", true).maybeSingle()`.
-- app.shipment_actual_costs_directory is a VIEW (20260728110000_create_operations_actual_
-- cost.sql:719-729, the one and only "create view app.shipment_actual_costs_directory" /
-- "create or replace view app.shipment_actual_costs_directory" hit repo-wide, confirmed by
-- grep sorted across every file in supabase/migrations/*.sql), re-expressed here directly
-- against its base table app.shipment_actual_costs (see file header for why). Row
-- visibility restates shipment_actual_costs_select_scoped's own CURRENT (and only-ever)
-- predicate: an exists-join to app.shipment_orders scoped via app.can_access_record on
-- that shipment's own tenant/owner/org-unit. is_current is already exclusive per shipment
-- order (partial unique index shipment_actual_costs_one_current_idx), so the `is_current =
-- true` filter alone already bounds this to at most one row -- no LIMIT needed.
create function app.get_shipment_actual_cost(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_order_id uuid,
  version_number integer,
  is_current boolean,
  supersedes_version_id uuid,
  status text,
  currency text,
  estimated_amount numeric,
  total_amount numeric,
  cost_masked boolean,
  approved_by_auth_user_id uuid,
  approved_at timestamptz,
  rejection_reason text,
  adjustment_reason text,
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
    sac.id,
    sac.tenant_id,
    sac.shipment_order_id,
    sac.version_number,
    sac.is_current,
    sac.supersedes_version_id,
    sac.status,
    sac.currency,
    case when app.has_view_actual_cost(sac.tenant_id, p_actor_auth_user_id) then sac.estimated_amount else null end,
    case when app.has_view_actual_cost(sac.tenant_id, p_actor_auth_user_id) then sac.total_amount else null end,
    not app.has_view_actual_cost(sac.tenant_id, p_actor_auth_user_id),
    sac.approved_by_auth_user_id,
    sac.approved_at,
    sac.rejection_reason,
    sac.adjustment_reason,
    sac.record_version,
    sac.created_by,
    sac.created_at,
    sac.updated_at
  from app.shipment_actual_costs sac
  join app.shipment_orders so on so.id = sac.shipment_order_id
  where sac.shipment_order_id = p_shipment_order_id
    and sac.is_current = true
    and app.can_access_record(
      p_actor_auth_user_id, so.tenant_id, so.owner_user_id,
      app.lead_record_scope_org_unit_ids(so.org_unit_id), null
    );
end;
$$;

comment on function app.get_shipment_actual_cost(uuid, uuid) is
  'OPS-178/O1 remediation: read path for app.shipment_actual_costs_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row-visibility filter (join to app.shipment_orders + app.can_access_record against tenant/owner/org-unit scope) reproduces shipment_actual_costs_select_scoped''s own current predicate verbatim -- confirmed via repo-wide grep that no later rewrite of this policy exists. The estimated_amount/total_amount CASE-WHEN mask and cost_masked flag are copied verbatim from the view''s own definition, re-expressed against the base table with an explicit p_actor_auth_user_id instead of app.has_view_actual_cost''s own default-auth argument. Returns zero rows (never an exception) for a nonexistent shipment_order_id, a shipment with no current actual-cost header, or an actor who cannot reach that shipment''s tenant/owner/org-unit scope -- matching the original RLS-filtered view''s own silent-empty-result posture (and the TS layer''s existing .maybeSingle() -> null handling, unchanged).';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_shipment_actual_cost with an identical grant set, never a
-- reimplementation.
create function public.get_shipment_actual_cost(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_order_id uuid,
  version_number integer,
  is_current boolean,
  supersedes_version_id uuid,
  status text,
  currency text,
  estimated_amount numeric,
  total_amount numeric,
  cost_masked boolean,
  approved_by_auth_user_id uuid,
  approved_at timestamptz,
  rejection_reason text,
  adjustment_reason text,
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
  select * from app.get_shipment_actual_cost(p_shipment_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_shipment_actual_cost(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_shipment_actual_cost with an identical grant set, never a reimplementation.';

-- app.get_shipment_actual_cost: same grant set as the view it replaces
-- (`grant select on app.shipment_actual_costs_directory to authenticated, service_role;`,
-- 20260728110000:738).
revoke execute on function app.get_shipment_actual_cost(uuid, uuid) from public;
grant execute on function app.get_shipment_actual_cost(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO
-- anon, authenticated bootstrap grant on the public schema).
revoke execute on function public.get_shipment_actual_cost(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_shipment_actual_cost(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.get_current_billing_readiness_evaluation -- replaces
--    server/queries/billing-readiness.ts:27 (getCurrentBillingReadinessEvaluation)
-- ===========================================================================
-- Replaces: `.from("billing_readiness_evaluations").select("*").eq("job_order_id",
-- jobOrderId).eq("is_current", true).maybeSingle()`. app.billing_readiness_evaluations is
-- a real BASE TABLE (20260728140000_create_operations_billing_readiness.sql:67-98), not a
-- view -- no `_directory` masking view exists for it at all (see file header). Row
-- visibility restates billing_readiness_evaluations_select_scoped''s own CURRENT (and
-- only-ever) predicate: an exists-join to app.job_orders scoped via app.can_access_record
-- on that job order''s own tenant/owner/org-unit. is_current is exclusive per job order
-- (partial unique index billing_readiness_evaluations_one_current_idx), so `is_current =
-- true` alone already bounds this to at most one row.
create function app.get_current_billing_readiness_evaluation(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  version_number integer,
  is_current boolean,
  evaluated_status text,
  effective_status text,
  blockers jsonb,
  evidence jsonb,
  rule_version integer,
  is_overridden boolean,
  override_reason text,
  overridden_by text,
  overridden_at timestamptz,
  override_revoked_reason text,
  override_revoked_by text,
  override_revoked_at timestamptz,
  reevaluation_reason text,
  supersedes_evaluation_id uuid,
  evaluated_by_auth_user_id uuid,
  evaluated_by text,
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
    be.id, be.tenant_id, be.job_order_id, be.version_number, be.is_current,
    be.evaluated_status, be.effective_status, be.blockers, be.evidence, be.rule_version,
    be.is_overridden, be.override_reason, be.overridden_by, be.overridden_at,
    be.override_revoked_reason, be.override_revoked_by, be.override_revoked_at,
    be.reevaluation_reason, be.supersedes_evaluation_id, be.evaluated_by_auth_user_id,
    be.evaluated_by, be.record_version, be.created_by, be.created_at, be.updated_at
  from app.billing_readiness_evaluations be
  join app.job_orders jo on jo.id = be.job_order_id
  where be.job_order_id = p_job_order_id
    and be.is_current = true
    and app.can_access_record(
      p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id,
      app.lead_record_scope_org_unit_ids(jo.org_unit_id), null
    );
end;
$$;

comment on function app.get_current_billing_readiness_evaluation(uuid, uuid) is
  'OPS-181/O1 remediation: the current (is_current=true) billing-readiness evaluation for a Job Order, replacing server/queries/billing-readiness.ts:27''s broken .from("billing_readiness_evaluations") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row-visibility filter (join to app.job_orders + app.can_access_record against tenant/owner/org-unit scope) reproduces billing_readiness_evaluations_select_scoped''s own current predicate verbatim -- confirmed via repo-wide grep that no later rewrite of this policy exists. Deliberately excludes the physical overridden_by_auth_user_id column: server/contracts/billing-readiness/billing-readiness.ts''s own parseBillingReadinessEvaluation never reads it (only the sibling text label overridden_by), so it is not part of this function''s contract-facing shape (the "return exactly what the TS contract consumes" discipline cluster 0''s app.prospects fix established). Returns zero rows (never an exception) for a nonexistent job_order_id, a job order never evaluated, or an actor who cannot reach that job order''s tenant/owner/org-unit scope -- matching the TS layer''s existing .maybeSingle() -> null handling, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_current_billing_readiness_evaluation with an identical grant
-- set, never a reimplementation.
create function public.get_current_billing_readiness_evaluation(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  version_number integer,
  is_current boolean,
  evaluated_status text,
  effective_status text,
  blockers jsonb,
  evidence jsonb,
  rule_version integer,
  is_overridden boolean,
  override_reason text,
  overridden_by text,
  overridden_at timestamptz,
  override_revoked_reason text,
  override_revoked_by text,
  override_revoked_at timestamptz,
  reevaluation_reason text,
  supersedes_evaluation_id uuid,
  evaluated_by_auth_user_id uuid,
  evaluated_by text,
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
  select * from app.get_current_billing_readiness_evaluation(p_job_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_current_billing_readiness_evaluation(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_current_billing_readiness_evaluation with an identical grant set, never a reimplementation.';

-- app.get_current_billing_readiness_evaluation: same grant set as the base table
-- (`grant select on app.billing_readiness_evaluations to authenticated, service_role;`,
-- 20260728140000:524).
revoke execute on function app.get_current_billing_readiness_evaluation(uuid, uuid) from public;
grant execute on function app.get_current_billing_readiness_evaluation(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_current_billing_readiness_evaluation(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_current_billing_readiness_evaluation(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 3. app.list_billing_readiness_evaluations -- replaces
--    server/queries/billing-readiness.ts:36 (getBillingReadinessEvaluationHistory)
-- ===========================================================================
-- Replaces: `.from("billing_readiness_evaluations").select("*").eq("job_order_id",
-- jobOrderId).order("version_number", { ascending: true })`. Same table, same row-
-- visibility predicate as function #2 above, but deliberately kept as a SEPARATE function
-- (not merged with app.get_current_billing_readiness_evaluation via an `only_current`
-- flag) -- per this batch''s own explicit scope, to minimize behavior change against the
-- existing TS layer, matching cluster 0 batch 3''s own "distinct, self-documenting single-
-- purpose RPCs over one function whose row set pivots on an optional parameter"
-- convention. Unfiltered (every version, not just is_current), ordered oldest-first by
-- version_number -- matches the original .from() call''s own ordering and the TS doc
-- comment''s own "the prior versions remain linked (supersedes_evaluation_id), never
-- rewritten" description.
create function app.list_billing_readiness_evaluations(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  version_number integer,
  is_current boolean,
  evaluated_status text,
  effective_status text,
  blockers jsonb,
  evidence jsonb,
  rule_version integer,
  is_overridden boolean,
  override_reason text,
  overridden_by text,
  overridden_at timestamptz,
  override_revoked_reason text,
  override_revoked_by text,
  override_revoked_at timestamptz,
  reevaluation_reason text,
  supersedes_evaluation_id uuid,
  evaluated_by_auth_user_id uuid,
  evaluated_by text,
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
    be.id, be.tenant_id, be.job_order_id, be.version_number, be.is_current,
    be.evaluated_status, be.effective_status, be.blockers, be.evidence, be.rule_version,
    be.is_overridden, be.override_reason, be.overridden_by, be.overridden_at,
    be.override_revoked_reason, be.override_revoked_by, be.override_revoked_at,
    be.reevaluation_reason, be.supersedes_evaluation_id, be.evaluated_by_auth_user_id,
    be.evaluated_by, be.record_version, be.created_by, be.created_at, be.updated_at
  from app.billing_readiness_evaluations be
  join app.job_orders jo on jo.id = be.job_order_id
  where be.job_order_id = p_job_order_id
    and app.can_access_record(
      p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id,
      app.lead_record_scope_org_unit_ids(jo.org_unit_id), null
    )
  order by be.version_number asc;
end;
$$;

comment on function app.list_billing_readiness_evaluations(uuid, uuid) is
  'OPS-181/O1 remediation: every billing-readiness evaluation ever recorded for a Job Order, oldest version first, replacing server/queries/billing-readiness.ts:36''s broken .from("billing_readiness_evaluations") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row-visibility filter is identical to app.get_current_billing_readiness_evaluation -- join to app.job_orders + app.can_access_record against tenant/owner/org-unit scope, reproducing billing_readiness_evaluations_select_scoped''s own current predicate verbatim (confirmed via repo-wide grep that no later rewrite of this policy exists) -- deliberately kept a separate function rather than merged with the is_current-only read, to minimize behavior change against the existing TS layer''s own two-function shape. Same deliberate overridden_by_auth_user_id column exclusion as app.get_current_billing_readiness_evaluation (see that function''s own comment for the contract-fidelity reasoning). Returns an empty set (never an exception) for a nonexistent job_order_id or an actor who cannot reach it -- matching the TS layer''s existing (data ?? []) handling, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_billing_readiness_evaluations with an identical grant set,
-- never a reimplementation.
create function public.list_billing_readiness_evaluations(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  version_number integer,
  is_current boolean,
  evaluated_status text,
  effective_status text,
  blockers jsonb,
  evidence jsonb,
  rule_version integer,
  is_overridden boolean,
  override_reason text,
  overridden_by text,
  overridden_at timestamptz,
  override_revoked_reason text,
  override_revoked_by text,
  override_revoked_at timestamptz,
  reevaluation_reason text,
  supersedes_evaluation_id uuid,
  evaluated_by_auth_user_id uuid,
  evaluated_by text,
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
  select * from app.list_billing_readiness_evaluations(p_job_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_billing_readiness_evaluations(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_billing_readiness_evaluations with an identical grant set, never a reimplementation.';

revoke execute on function app.list_billing_readiness_evaluations(uuid, uuid) from public;
grant execute on function app.list_billing_readiness_evaluations(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_billing_readiness_evaluations(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_billing_readiness_evaluations(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 4. app.list_billing_readiness_handoffs -- replaces
--    server/queries/billing-readiness.ts:45 (listBillingReadinessHandoffs)
-- ===========================================================================
-- Replaces: `.from("billing_readiness_handoffs").select("*").eq("job_order_id",
-- jobOrderId).order("handed_off_at", { ascending: false })`. app.billing_readiness_
-- handoffs is a real BASE TABLE (20260728140000:122-133), append-only, no `_directory`
-- masking view. Row visibility restates billing_readiness_handoffs_select_scoped''s own
-- CURRENT (and only-ever) predicate -- an exists-join to app.job_orders scoped via
-- app.can_access_record, the identical shape as functions #2/#3 above but against this
-- sibling table''s own policy (confirmed as a SEPARATE grep hit from the evaluations
-- policy, both original, neither ever rewritten). Returns the full row (no masking, no
-- deliberate exclusion -- all 9 physical columns are consumed by parseBillingReadinessHandoff,
-- see file header), so this is declared `returns setof app.billing_readiness_handoffs`
-- rather than an explicit RETURNS TABLE column list, matching cluster 0 batch 3''s own
-- app.list_costing_response_components precedent for this identical "full row, no
-- masking" shape.
create function app.list_billing_readiness_handoffs(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.billing_readiness_handoffs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select h.*
  from app.billing_readiness_handoffs h
  join app.job_orders jo on jo.id = h.job_order_id
  where h.job_order_id = p_job_order_id
    and app.can_access_record(
      p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id,
      app.lead_record_scope_org_unit_ids(jo.org_unit_id), null
    )
  order by h.handed_off_at desc;
end;
$$;

comment on function app.list_billing_readiness_handoffs(uuid, uuid) is
  'OPS-181/O1 remediation: every Finance handoff ever produced for a Job Order, newest first, replacing server/queries/billing-readiness.ts:45''s broken .from("billing_readiness_handoffs") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row-visibility filter (join to app.job_orders + app.can_access_record against tenant/owner/org-unit scope) reproduces billing_readiness_handoffs_select_scoped''s own current predicate verbatim -- confirmed via repo-wide grep that no later rewrite of this policy exists, and that it is a distinct policy from its sibling billing_readiness_evaluations_select_scoped (same shape, different table). No column exclusion: every physical column on this append-only table is consumed by parseBillingReadinessHandoff. Returns an empty set (never an exception) for a nonexistent job_order_id, a job order with no handoffs yet, or an actor who cannot reach it -- matching the TS layer''s existing (data ?? []) handling, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_billing_readiness_handoffs with an identical grant set, never a
-- reimplementation.
create function public.list_billing_readiness_handoffs(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.billing_readiness_handoffs
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_billing_readiness_handoffs(p_job_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_billing_readiness_handoffs(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_billing_readiness_handoffs with an identical grant set, never a reimplementation.';

-- app.list_billing_readiness_handoffs: same grant set as the base table
-- (`grant select on app.billing_readiness_handoffs to authenticated, service_role;`,
-- 20260728140000:526).
revoke execute on function app.list_billing_readiness_handoffs(uuid, uuid) from public;
grant execute on function app.list_billing_readiness_handoffs(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_billing_readiness_handoffs(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_billing_readiness_handoffs(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
--
-- 1. server/queries/actual-cost.ts -- getShipmentActualCost (currently lines 29-35)
-- ---------------------------------------------------------------------------
-- Client type: `ActualCostQueryClient = Pick<SupabaseClient, "from" | "rpc">` (line 19)
-- already includes "rpc" -- no type change needed.
--
-- Add a required second parameter `actorAuthUserId: string`:
--   export async function getShipmentActualCost(
--     client: ActualCostQueryClient,
--     shipmentOrderId: string,
--     actorAuthUserId: string,
--   ): Promise<ShipmentActualCostDirectoryRow | null> {
--
-- Replace the `.from(...)` chain (current lines 30) with:
--     const { data, error } = await client.rpc("get_shipment_actual_cost", {
--       p_shipment_order_id: shipmentOrderId,
--       p_actor_auth_user_id: actorAuthUserId,
--     });
--     if (error) {
--       throw new ActualCostQueryError(error.message);
--     }
--     const row = Array.isArray(data) ? data[0] : data;
--     return row ? parseShipmentActualCostDirectoryRow(row as Record<string, unknown>) : null;
--   }
-- (RETURNS TABLE always comes back as an array via .rpc(), unlike the old .maybeSingle()
-- single-object shape -- the `Array.isArray(data) ? data[0] : data` guard, already used
-- elsewhere in this same file for evaluateActualCostVariance, picks the single row or
-- undefined/null; parseShipmentActualCostDirectoryRow''s own column-name expectations are
-- otherwise unchanged, since the RPC''s RETURNS TABLE column list matches the old view
-- select 1:1.)
--
-- Call site needing the new second argument -- `access.authUserId` is already resolved and
-- already threaded into two sibling calls on the very next two lines:
--   app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/page.tsx:244
--   Before: `actualCost = await getShipmentActualCost(supabase, shipment.id);`
--   After:  `actualCost = await getShipmentActualCost(supabase, shipment.id, access.authUserId);`
--
-- server/queries/actual-cost.test.ts (describe("getShipmentActualCost"), lines 32-85) mocks
-- a `.from`-based client today and will need updating to mock `.rpc("get_shipment_actual_
-- cost", ...)` instead, returning `{ data: [DIRECTORY_ROW], error: null }` (an array, per
-- RETURNS TABLE) and calling `getShipmentActualCost(client, SHIPMENT_ID, ACTOR_ID)` --
-- not attempting this rewrite here, per this task''s SQL-only scope.
--
-- 2. server/queries/billing-readiness.ts -- all three functions (currently lines 26-50)
-- ---------------------------------------------------------------------------
-- Client type: `BillingReadinessQueryClient = Pick<SupabaseClient, "from">` (line 16) must
-- widen to `Pick<SupabaseClient, "from" | "rpc">` -- unlike actual-cost.ts, "rpc" was never
-- part of this file''s client alias before, since none of its three functions previously
-- called .rpc() at all.
--
-- getCurrentBillingReadinessEvaluation (currently lines 26-32): add a required second
-- parameter `actorAuthUserId: string`, replace the `.from(...)` chain with:
--     const { data, error } = await client.rpc("get_current_billing_readiness_evaluation", {
--       p_job_order_id: jobOrderId,
--       p_actor_auth_user_id: actorAuthUserId,
--     });
--     if (error) {
--       throw new BillingReadinessQueryError(error.message);
--     }
--     const row = Array.isArray(data) ? data[0] : data;
--     return row ? parseBillingReadinessEvaluation(row as Record<string, unknown>) : null;
--
-- getBillingReadinessEvaluationHistory (currently lines 35-41): add a required second
-- parameter `actorAuthUserId: string`, replace the `.from(...)` chain with:
--     const { data, error } = await client.rpc("list_billing_readiness_evaluations", {
--       p_job_order_id: jobOrderId,
--       p_actor_auth_user_id: actorAuthUserId,
--     });
--     if (error) {
--       throw new BillingReadinessQueryError(error.message);
--     }
--     return (data ?? []).map((row: Record<string, unknown>) => parseBillingReadinessEvaluation(row));
-- Drop the now-redundant `.order(...)` call -- the RPC already applies
-- `order by be.version_number asc` server-side.
--
-- listBillingReadinessHandoffs (currently lines 44-50): add a required second parameter
-- `actorAuthUserId: string`, replace the `.from(...)` chain with:
--     const { data, error } = await client.rpc("list_billing_readiness_handoffs", {
--       p_job_order_id: jobOrderId,
--       p_actor_auth_user_id: actorAuthUserId,
--     });
--     if (error) {
--       throw new BillingReadinessQueryError(error.message);
--     }
--     return (data ?? []).map((row: Record<string, unknown>) => parseBillingReadinessHandoff(row));
-- Drop the now-redundant `.order(...)` call -- the RPC already applies
-- `order by h.handed_off_at desc` server-side.
--
-- Call sites needing the new second argument:
--   app/(tenant)/[tenantSlug]/operations/job-orders/[jobOrderId]/page.tsx:74-75 --
--   `access.authUserId` is already resolved at the top of the page (line 40) and already
--   threaded into the sibling `getTransactionLineage` call four lines below (line 85):
--     Before:
--       billingReadinessEvaluation = await getCurrentBillingReadinessEvaluation(supabase, jobOrder.id);
--       billingReadinessHandoffs = await listBillingReadinessHandoffs(supabase, jobOrder.id);
--     After:
--       billingReadinessEvaluation = await getCurrentBillingReadinessEvaluation(supabase, jobOrder.id, access.authUserId);
--       billingReadinessHandoffs = await listBillingReadinessHandoffs(supabase, jobOrder.id, access.authUserId);
--
--   getBillingReadinessEvaluationHistory: no live page.tsx call site found anywhere in
--   app/ (grepped "getBillingReadinessEvaluationHistory(" repo-wide -- the only two hits
--   outside its own declaration in server/queries/billing-readiness.ts are in server/
--   queries/billing-readiness.test.ts). This function is switched to the new .rpc() shape
--   and given the same required actorAuthUserId parameter as its two siblings for
--   interface consistency (and because it shares the exact same underlying table/RLS
--   predicate), but no real caller today needs threading through a page.
--
-- server/queries/billing-readiness.test.ts (its own fakeClient helper, lines 51-82, and
-- all three describe blocks, lines 84-121) mocks a `.from`-based client today and will
-- need updating to a `.rpc`-based mock -- the same `.rpc("<fn_name>", args)` capture
-- pattern server/queries/costing.test.ts / credit.test.ts already use for their own
-- already-migrated functions -- returning row arrays (single-element for the two
-- maybeSingle-shaped former reads) and passing ACTOR_ID as each function''s new second
-- argument -- not attempting this rewrite here, per this task''s SQL-only scope.

-- ===========================================================================
-- TABLE 2 of 4: app.finance_currencies + app.finance_rounding_modes
-- ===========================================================================
-- CG-AUDIT-2026-09-02 Ø1-query-layer remediation -- cluster 1 (finance), batch 1
-- of N: 2 global reference/catalogue tables, zero tenant/actor scoping.
--
-- SCOPE:
--   1. app.finance_currencies      (server/queries/currency-exchange-rate.ts,
--                                    listFinanceCurrencies)
--   2. app.finance_rounding_modes  (server/queries/finance-config.ts,
--                                    listFinanceRoundingModes)
--
-- SEVERITY (same root cause as every prior Ø1 batch): supabase/config.toml's
-- `schemas = ["public", "graphql_public"]` never exposes the "app" Postgres
-- schema to PostgREST. Both `.from("finance_currencies")` (currency-exchange-
-- rate.ts:33) and `.from("finance_rounding_modes")` (finance-config.ts:148)
-- have therefore never worked in production -- PGRST106 "Invalid schema: app"
-- for every caller, live and reachable behind
-- app/(tenant)/[tenantSlug]/finance/exchange-rates/page.tsx (the currency
-- registry half of that page's parallel Promise.all load).
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior Ø1 commit): a new
-- `app.*` function reachable only via RPC, plus a thin `public.*` pass-
-- through wrapper (the only PostgREST-reachable surface) with an IDENTICAL
-- grant set -- never a reimplementation.
--
-- ===========================================================================
-- RULE A (actor-impersonation guard, ATW-031/032) -- DOES NOT APPLY, and why
-- ===========================================================================
-- Both functions below are declared with ZERO parameters. There is no
-- p_actor_auth_user_id (or any other actor-identifying argument) for a caller
-- to spoof, so `app.assert_actor_is_session_identity(...)` has nothing to
-- guard -- adding a call to it here would mean inventing an actor parameter
-- that serves no authorization purpose (see RULE B below: both predicates are
-- a bare `true` for any `authenticated` caller, so no actor value could ever
-- change the outcome). This reasoning was checked against this codebase's own
-- established convention for the identical shape -- "global reference table,
-- no actor param, no tenant scoping, `authenticated`-broad SELECT policy" --
-- rather than assumed:
--
--   grep -rn "create \(or replace \)\?function app\.\(list\|get\)_[a-z_]*()" supabase/migrations/*.sql
--
-- surfaces four existing zero-parameter app.list_*/get_* functions.
-- Two are a precise structural match (same "bare `true`, `select to
-- authenticated`, base-table `grant select ... to authenticated,
-- service_role`" shape our two tables carry) and are reused directly as the
-- shape precedent for both functions below:
--
--   * app.list_api_versions() (supabase/migrations/
--     20260804010000_create_intelligence_public_api_platform.sql:301-307).
--     Its own table, app.api_versions, carries `create policy
--     api_versions_select_all on app.api_versions for select to authenticated
--     using (true);` (same file, lines 425-427) plus `grant select on
--     app.api_versions to authenticated, service_role;` (line 429) --
--     independently re-read, not trusted from any restated summary.
--   * app.list_webhook_event_types() (supabase/migrations/
--     20260804010000_create_intelligence_public_api_platform.sql:365-371 --
--     CORRECTED during adversarial verification: an earlier draft of this
--     citation pointed at 20260719150000_create_api_key_webhook_primitives.sql,
--     which is where app.webhook_event_types the TABLE is created, not where
--     this function is declared; independently re-read and confirmed at the
--     file/line above). The table itself, app.webhook_event_types, carries
--     `create policy webhook_event_types_select_all on
--     app.webhook_event_types for select to authenticated using (true);`
--     (supabase/migrations/20260719150000_create_api_key_webhook_primitives.sql,
--     lines 1023-1025) plus `grant select on app.webhook_event_types to
--     authenticated, service_role;` (same file, line 1029) -- also
--     independently re-read.
--
-- RULE C on both: `grep -rln "create or replace function
-- app.list_api_versions\|create or replace function
-- app.list_webhook_event_types"` across every file in supabase/migrations/*.sql
-- returns zero hits -- neither has ever been replaced; each cited body above
-- is its current, only-ever-declared definition. Likewise `grep -rn "alter
-- policy"` filtered for `api_versions_select_all`/`webhook_event_types_select_all`
-- returns zero hits -- neither table's policy has ever been rewritten either.
--
-- The load-bearing detail in both precedents: NEITHER app.list_api_versions()
-- nor app.list_webhook_event_types() is declared `security definer`. Both are
-- plain `language sql stable` (Postgres's default security mode, invoker),
-- with zero in-function authority check, and app.list_webhook_event_types'
-- own comment states the reason directly: it "mirrors app.webhook_event_types'
-- own RLS policy (select to authenticated using (true))" -- i.e. the
-- function deliberately runs as the REAL calling role so the table's already-
-- correct grant + policy do the entire job, rather than reproducing that
-- predicate a second time inside a SECURITY DEFINER body (a real, if narrow,
-- privilege-escalation surface this codebase's own
-- 20260826000000_create_public_api_data_wrappers.sql header calls out
-- explicitly: "wrapping [invoker functions] in another security-definer
-- layer changes nothing they didn't already do... A wrapper that forced
-- security definer on these would silently execute them as the owning
-- superuser instead"). app.finance_currencies and app.finance_rounding_modes
-- are the identical shape (bare `true`, `select to authenticated`, direct
-- `grant select ... to authenticated`, verified in RULE B below) -- so both
-- functions below follow this SAME established convention: plain
-- `language sql stable`, no `security definer`, no in-function check.
--
-- DISCLOSED DEVIATION FROM THIS TASK'S OWN INITIAL FRAMING: the originating
-- instruction for this batch suggested `security definer` for both
-- functions. Independent verification against the two precedents above shows
-- that is not, in fact, this codebase's own established pattern for a
-- genuinely open, `using (true)`-to-`authenticated`, zero-actor-param
-- reference table -- the live precedent is `security invoker` (the
-- unmarked default). Both functions below follow the verified live
-- precedent, not the suggested default, per this task's own instruction to
-- "follow whatever established convention you find" rather than invent a new
-- one. `stable` is kept (both precedents and both of our tables' read shape
-- justify it); `security definer` is deliberately omitted from both.
--
-- ===========================================================================
-- RULE B (RLS predicate currency) -- both tables
-- ===========================================================================
-- 1. app.finance_currencies. Ran both required greps across every file in
--    supabase/migrations/*.sql, sorted by filename:
--      grep -n "policy" supabase/migrations/*.sql | grep -i "finance_currencies"
--      grep -rn "alter policy" supabase/migrations/*.sql | grep -i "finance_currenc"
--    Exactly one CREATE POLICY exists anywhere, and zero ALTER POLICY
--    statements of any kind touch it:
--      create policy finance_currencies_select_authenticated on app.finance_currencies
--        for select to authenticated
--        using (true);
--    (supabase/migrations/20260728230000_create_finance_currency_exchange_rate.sql:604-606).
--    This is therefore still the CURRENT, only-ever-declared predicate -- no
--    later hardening (no customer_user-layer exclusion, no tenant check) was
--    ever layered onto it, consistent with it holding genuinely global data
--    (a currency code has no tenant_id column at all -- confirmed against the
--    table's own 4-column shape, `create table app.finance_currencies (code
--    text primary key, name text not null, minor_unit_precision integer not
--    null default 2, is_active boolean not null default true, ...)`, same
--    file, lines 52-59). Table grant: `grant select on app.finance_currencies
--    to authenticated, service_role;` (line 625).
--
-- 2. app.finance_rounding_modes. Ran the same two greps for this table:
--      grep -n "policy" supabase/migrations/*.sql | grep -i "finance_rounding_modes"
--      grep -rn "alter policy" supabase/migrations/*.sql | grep -i "finance_rounding"
--    Exactly one CREATE POLICY exists anywhere, and zero ALTER POLICY
--    statements touch it:
--      create policy finance_rounding_modes_select_authenticated on app.finance_rounding_modes
--        for select to authenticated
--        using (true);
--    (supabase/migrations/20260728200000_create_finance_configuration.sql:619-621),
--    whose own preceding comment already states the intended posture
--    verbatim: "Platform-owned reference data (mirrors app.config_types'/
--    app.finance_config_class equivalents' own posture) -- safe to expose
--    broadly." Table shape (same file, lines 110-114): `create table
--    app.finance_rounding_modes (code text primary key, name text not null,
--    description text not null)` -- 3 columns total, no tenant_id, nothing
--    else on the table to under- or over-select. Table grant: `grant select
--    on app.finance_rounding_modes to authenticated, service_role;` (line
--    623).
--
-- Neither table appears anywhere in
-- 20260730560000_harden_customer_user_layer_default_deny.sql (grepped
-- "finance_currencies\|finance_rounding_modes" against that file directly --
-- zero hits), confirming both were correctly out of scope for that
-- hardening pass: it only ever targeted policies whose entire test was a
-- bare `app.has_active_tenant_membership(...)` call, and these two policies
-- have no tenant-membership test to begin with.
--
-- ===========================================================================
-- CONTRACT FIDELITY (both, re-read directly, not assumed)
-- ===========================================================================
-- server/contracts/currency-exchange-rate/currency-exchange-rate.ts'
-- parseFinanceCurrency consumes exactly `code`, `name`,
-- `minor_unit_precision` (-> minorUnitPrecision), `is_active` (-> isActive)
-- -- the table's own 4 columns, 1:1, nothing more and nothing less.
-- `returns setof app.finance_currencies` below matches this exactly, and
-- reproduces the original `.from(...).select("*")` shape verbatim.
--
-- server/contracts/finance-config/finance-config.ts' parseFinanceRoundingModeInfo
-- consumes exactly `code`, `name`, `description` -- which, per RULE B above,
-- are the table's ONLY 3 columns. `returns setof app.finance_rounding_modes`
-- below is therefore byte-for-byte equivalent to the original
-- `.from(...).select("code, name, description")` (there is no 4th column a
-- bare `select *` could ever over-select here).
--
-- ===========================================================================
-- ISS-2026-309 grant-parity (docs/runtime/KNOWN_ISSUES.md, closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql)
-- ===========================================================================
-- A bare `revoke execute on function public.FN(...) from public` does NOT
-- strip the `anon`/`authenticated` EXECUTE grants Supabase's own ALTER
-- DEFAULT PRIVILEGES rule applies to every new function created in schema
-- public. Both public.* wrappers below therefore explicitly revoke from
-- `anon, authenticated, service_role, public` (all four) before re-granting
-- exactly the same roles as their app.* counterpart -- `authenticated,
-- service_role`, never `anon`.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): the standing per-migration
-- convention of an explicit, directly-provable `revoke execute on all
-- functions in schema app from public` is included as this fragment's final
-- statement, matching every prior batch's own placement.
--
-- ===========================================================================
-- check-rls-initplan.ts false-positive avoidance
-- ===========================================================================
-- Neither predicate below ever calls auth.uid()/auth.jwt() (both are a bare
-- `true`), so there is no bare-auth-call text for the guard's
-- BARE_AUTH_CALL/DEFAULT_PARAM_INITPLAN checks to ever combine with a
-- policy-rewrite phrase in the first place. As a defensive habit matching
-- every prior batch in this series regardless, every `comment on function`
-- string below describes the RULE B history as "no later rewrite of this
-- policy exists" rather than the literal two-word phrase this project's own
-- guard has previously misread out of comment prose.
--
-- ===========================================================================
-- DISCLOSED, OUT-OF-SCOPE FINDINGS (not fixed here -- different tables,
-- different clusters; recorded so they are not silently rediscovered)
-- ===========================================================================
-- 1. supabase/migrations/20260830140000_create_incident_communication.sql's
--    own `comment on function app.list_incident_communication_audiences`
--    (line 406) reads: "Mirrors app.list_finance_currencies' own precedent
--    for a global reference registry." app.list_finance_currencies did not
--    exist anywhere in this repository before this fragment -- grepped
--    `list_finance_currencies` across every file in supabase/migrations/*.sql
--    before writing this fragment; the ONLY hit anywhere was that one
--    comment string itself. That comment is therefore a forward/dangling
--    citation to a function that had never been created -- a
--    citation-accuracy defect of the same class prior batches in this series
--    disclosed (e.g. the batch-2 close entry's false "never replaced" claim),
--    not a security or masking bug, and out of scope to edit here (different
--    table, different migration, already shipped). It is, at least,
--    retroactively made true by this fragment.
--
-- 2. While independently verifying the app.list_api_versions/
--    app.list_webhook_event_types precedent above, the SAME
--    20260830140000 migration's app.list_incident_communication_audiences()/
--    public.list_incident_communication_audiences() pair appears to be a
--    genuinely live, different defect: both are declared without `security
--    definer` (invoker), but that migration's own RLS section (same file,
--    lines 409-419) does `alter table app.incident_communication_audiences
--    enable row level security;` with NO create policy statement for it at
--    all, and `revoke all on app.incident_communication_audiences from
--    public, anon, authenticated;` (only `service_role` is granted ALL).
--    Unlike app.api_versions/app.webhook_event_types (which DO grant SELECT
--    to authenticated and DO carry a `using (true)` policy, making invoker
--    mode correct), an `authenticated` caller invoking this function would
--    have EXECUTE via its own grant but zero SELECT privilege on the
--    underlying table -- invoker mode would raise a real Postgres
--    permission-denied error, not return rows. Grepped
--    `incident_communication_audiences` across every other file in
--    supabase/migrations/*.sql -- zero hits, so nothing later fixes this.
--    Out of scope for this batch (a different table, in a different cluster
--    of this same Ø1 effort) -- flagged here rather than silently left for
--    whoever owns that read path to rediscover, matching this series' own
--    established disclosure convention (e.g. batch 3's stale-helper note,
--    batch 4's mutation RULE A gaps).

-- ===========================================================================
-- 1. app.list_finance_currencies -- replaces server/queries/
--    currency-exchange-rate.ts:32-38 (listFinanceCurrencies)
-- ===========================================================================
create function app.list_finance_currencies()
returns setof app.finance_currencies
language sql
stable
as $$
  select * from app.finance_currencies order by code asc;
$$;

comment on function app.list_finance_currencies() is
  'FIN-194/O1 remediation: the full governed currency registry, code ascending, replacing server/queries/currency-exchange-rate.ts''s broken .from("finance_currencies").select("*").order("code", {ascending:true}) (app is not exposed to PostgREST). Zero parameters, zero in-function authority check -- app.finance_currencies carries no tenant_id and its own only-ever-declared SELECT policy, finance_currencies_select_authenticated, is a bare `using (true)` for role authenticated (20260728230000_create_finance_currency_exchange_rate.sql:604-606; no later rewrite of this policy exists anywhere in supabase/migrations). Deliberately `security invoker` (the unmarked default), not `security definer`: this function runs as the real calling role, which already holds a direct `grant select on app.finance_currencies to authenticated, service_role`, so the table''s own grant and policy do the whole job -- matching this codebase''s own established shape for a zero-actor-param global reference table (app.list_api_versions/app.api_versions, app.list_webhook_event_types/app.webhook_event_types, both unmarked-invoker over an identical bare-true/authenticated-grant table shape). No RULE A actor-impersonation guard: this function takes no actor parameter, so there is no identity claim for app.assert_actor_is_session_identity to cross-check. Returns exactly the 4-column shape server/contracts/currency-exchange-rate/currency-exchange-rate.ts''s parseFinanceCurrency consumes (code, name, minor_unit_precision, is_active) -- identical to the replaced `select *`.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin
-- pass-through to app.list_finance_currencies with an identical grant set
-- AND an identical security mode (invoker, matching its app.* counterpart --
-- never a reimplementation, and never a privilege upgrade the app.* function
-- itself does not have).
create function public.list_finance_currencies()
returns setof app.finance_currencies
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_currencies();
$wrap$;

comment on function public.list_finance_currencies() is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_finance_currencies with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_finance_currencies() from public;
grant execute on function app.list_finance_currencies() to authenticated, service_role;

revoke execute on function public.list_finance_currencies() from anon, authenticated, service_role, public;
grant execute on function public.list_finance_currencies() to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_finance_rounding_modes -- replaces server/queries/
--    finance-config.ts:147-153 (listFinanceRoundingModes)
-- ===========================================================================
create function app.list_finance_rounding_modes()
returns setof app.finance_rounding_modes
language sql
stable
as $$
  select * from app.finance_rounding_modes;
$$;

comment on function app.list_finance_rounding_modes() is
  'FIN-191/O1 remediation: the bounded rounding-convention catalogue, replacing server/queries/finance-config.ts''s broken .from("finance_rounding_modes").select("code, name, description") (app is not exposed to PostgREST). Zero parameters, zero in-function authority check -- app.finance_rounding_modes carries no tenant_id and its own only-ever-declared SELECT policy, finance_rounding_modes_select_authenticated, is a bare `using (true)` for role authenticated (20260728200000_create_finance_configuration.sql:619-621, whose own preceding comment already calls this table "safe to expose broadly"; no later rewrite of this policy exists anywhere in supabase/migrations). Deliberately `security invoker` (the unmarked default), not `security definer`, for the identical reason as its sibling app.list_finance_currencies immediately above: the real calling role already holds a direct `grant select on app.finance_rounding_modes to authenticated, service_role`, matching this codebase''s established app.list_api_versions/app.list_webhook_event_types shape for this exact table class. No RULE A guard: no actor parameter exists to protect. No ORDER BY: the replaced `.from()` call applied none either, and `code`/`name`/`description` are this table''s entire, fixed 3-column shape (verified against its own `create table` statement) -- so `select *` here is byte-for-byte the same result set server/contracts/finance-config/finance-config.ts''s parseFinanceRoundingModeInfo already consumes, in whatever order Postgres returns it, exactly as before.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin
-- pass-through to app.list_finance_rounding_modes with an identical grant
-- set AND an identical security mode (invoker), never a reimplementation.
create function public.list_finance_rounding_modes()
returns setof app.finance_rounding_modes
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_rounding_modes();
$wrap$;

comment on function public.list_finance_rounding_modes() is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_finance_rounding_modes with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_finance_rounding_modes() from public;
grant execute on function app.list_finance_rounding_modes() to authenticated, service_role;

revoke execute on function public.list_finance_rounding_modes() from anon, authenticated, service_role, public;
grant execute on function public.list_finance_rounding_modes() to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION: listFinanceCurrencies
-- ===========================================================================
-- File: server/queries/currency-exchange-rate.ts, function listFinanceCurrencies
-- (current lines 31-38).
--
-- 1. Type: `FinanceCurrencyTableClient` (line 22) is currently
--    `Pick<SupabaseClient, "from">` and is used ONLY as this function's own
--    parameter type (confirmed: no other reference anywhere in this file).
--    Change its definition in place, keeping the exported name unchanged so
--    the test file''s existing import keeps resolving:
--      export type FinanceCurrencyTableClient = Pick<SupabaseClient, "rpc">;
--
-- 2. Function signature is UNCHANGED (still takes only `client`, zero other
--    parameters -- this function needs no actor id, matching the new RPC):
--      export async function listFinanceCurrencies(client: FinanceCurrencyTableClient): Promise<FinanceCurrency[]>
--
-- 3. Replace the `.from(...)` chain (current line 33) with:
--      const { data, error } = await client.rpc("list_finance_currencies");
--    (zero-argument RPC -- no second `.rpc(...)` argument object needed).
--    Drop the now-redundant `.order("code", { ascending: true })` call -- the
--    RPC already applies `order by code asc` server-side.
--
-- 4. Row mapping and error handling are UNCHANGED: the RPC returns the same
--    4-column shape (code, name, minor_unit_precision, is_active) the old
--    `.from(...).select("*")` did, so `(data ?? []).map((row) =>
--    parseFinanceCurrency(row as Record<string, unknown>))` (current line 37)
--    and `if (error) throw new CurrencyExchangeRateQueryError(error.message)`
--    (current line 34-36) need no changes at all.
--
-- 5. Call site -- needs NO change (signature is identical, `supabase`
--    structurally satisfies the new `Pick<SupabaseClient, "rpc">` type just
--    as it did the old `"from"` one):
--      app/(tenant)/[tenantSlug]/finance/exchange-rates/page.tsx:46
--      `listFinanceCurrencies(supabase),` inside the page''s own
--      `Promise.all([...])` load -- left exactly as-is.
--
-- 6. server/queries/currency-exchange-rate.test.ts (describe block
--    "listFinanceCurrencies", current lines 48-63) mocks a `.from`-based
--    `fakeTableClient` today and will need updating to the file''s own
--    already-existing `fakeRpcClient` helper (lines 37-46, already used by
--    every other RPC-backed function in this same test file) -- e.g.
--    `fakeRpcClient({ data: [{ code: "USD", name: "United States Dollar",
--    minor_unit_precision: 2, is_active: true }], error: null })`, then
--    assert `client.calls[0]?.fn === "list_finance_currencies"`. Not
--    attempting this rewrite here, per this task''s scope (SQL only).

-- ===========================================================================
-- TS INTEGRATION: listFinanceRoundingModes
-- ===========================================================================
-- File: server/queries/finance-config.ts, function listFinanceRoundingModes
-- (current lines 147-153).
--
-- 1. Type: `FinanceRoundingModesTableClient` (line 31) is currently
--    `Pick<SupabaseClient, "from">` and is used ONLY as this function's own
--    parameter type (confirmed: no other reference anywhere in this file).
--    Change its definition in place, keeping the exported name unchanged:
--      export type FinanceRoundingModesTableClient = Pick<SupabaseClient, "rpc">;
--
-- 2. Function signature is UNCHANGED:
--      export async function listFinanceRoundingModes(client: FinanceRoundingModesTableClient): Promise<FinanceRoundingModeInfo[]>
--
-- 3. Replace the `.from(...)` chain (current line 148) with:
--      const { data, error } = await client.rpc("list_finance_rounding_modes");
--
-- 4. Row mapping and error handling are UNCHANGED: `(data ?? []).map((row) =>
--    parseFinanceRoundingModeInfo(row as Record<string, unknown>))` (current
--    line 152) and the existing `if (error) throw new
--    FinanceConfigQueryError(error.message)` (current lines 149-151) need no
--    changes -- the RPC returns the identical 3-column shape (code, name,
--    description) the old `.select("code, name, description")` did.
--
-- 5. Call site: grepped `listFinanceRoundingModes` across every `.ts`/`.tsx`
--    file in this repository (excluding node_modules) -- the only hits
--    outside server/queries/finance-config.ts itself are
--    server/queries/finance-config.test.ts (its own test) and a doc comment
--    in server/queries/currency-exchange-rate.ts:7 that merely names this
--    function in passing. **No live page.tsx (or any other) call site
--    exists anywhere in this repository today** -- this function is
--    currently unreferenced outside its own test, so there is no downstream
--    caller to update in this same commit.
--
-- 6. server/queries/finance-config.test.ts (describe block
--    "listFinanceRoundingModes", current lines 137-152) mocks a `.from`-based
--    `fakeTableClient` today and will need updating to mock `.rpc("list_finance_rounding_modes")`
--    instead (this file''s own `fakeClient` helper used by every other RPC-backed
--    function in the same file, e.g. `resolveFinanceConfig`''s describe block,
--    is the ready-made pattern to reuse) -- returning `{ data: [{ code:
--    "round_half_up", name: "Round half up", description: "..." }], error:
--    null }` and asserting the call was made with fn `"list_finance_rounding_modes"`
--    and no args. Not attempting this rewrite here, per this task''s scope (SQL only).


-- ===========================================================================
-- TABLE 3 of 4: app.finance_period_close_checklist_items
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1 remediation -- app.finance_period_close_checklist_items read path.
-- Ø1-query-layer cluster 1 (finance), batch 1 of ~N.
--
-- Replaces: server/queries/fiscal-period.ts:73-79 (listFinancePeriodChecklistItems --
-- `.from("finance_period_close_checklist_items").select("*").eq("period_id", periodId)
-- .order("item_key", { ascending: true })` -- "Direct RLS-scoped read of one period's own
-- checklist items"). app.finance_period_close_checklist_items is a real BASE TABLE
-- (supabase/migrations/20260728220000_create_finance_fiscal_period.sql:104-117), not a
-- view -- columns are exactly id, period_id, item_key, label, required, source_capability,
-- satisfied, satisfied_reason, satisfied_by, satisfied_at, created_at (11 columns). It lives
-- in the "app" Postgres schema, which supabase/config.toml never exposes to PostgREST
-- ("public"/"graphql_public" only) -- so this .from() call has never worked in production,
-- despite the source comment above it claiming "no RPC needed" (that comment predates this
-- audit's finding that `app` itself is unreachable via .from() regardless of how broad the
-- policy is).
--
-- Contract fidelity: server/contracts/fiscal-period/fiscal-period.ts's own
-- `parseFinancePeriodChecklistItem` consumes exactly these 11 columns 1:1 (id, periodId,
-- itemKey, label, required, sourceCapability, satisfied, satisfiedReason, satisfiedBy,
-- satisfiedAt, createdAt) -- no deliberate column exclusion, no masked/derived column to add.
-- `returns setof app.finance_period_close_checklist_items` therefore reproduces the base
-- table's own shape verbatim, matching the sibling same-shape precedent
-- app.list_costing_response_components (o1-drafts/cluster0/app_costing_response_components.sql)
-- rather than needing an explicit RETURNS TABLE.
--
-- RULE B (RLS predicate currency) -- ran both required greps across every file in
-- supabase/migrations/*.sql, sorted by filename:
--   * `finance_period_close_checklist_items_select_scoped` (the bare policy name) --
--     exactly two hits: the original policy statement in
--     20260728220000_create_finance_fiscal_period.sql:590-598 and one later policy revision
--     in 20260730560000_harden_customer_user_layer_default_deny.sql:196-197. No third hit
--     anywhere -- the 20260730560000 text is the current, only-ever-revised version.
--   * A second, independent grep for the table name against every policy-revision statement
--     in 20260730560000 confirms this table is explicitly in that migration's own target set
--     (its header lists `finance_period_close_checklist_items` by name among the 98 policies
--     it rewrote), so the revision below is not a coincidental unrelated hit.
--
--   Original (20260728220000):
--     using (
--       exists (
--         select 1 from app.finance_fiscal_periods p
--         where p.id = finance_period_close_checklist_items.period_id
--           and (app.has_active_tenant_membership(p.tenant_id) or app.is_supreme_admin())
--       )
--     )
--
--   Current, most-recently-revised policy text (20260730560000:196-197), reproduced verbatim
--   from the migration file:
--     using ((EXISTS ( SELECT 1 FROM app.finance_fiscal_periods p WHERE ((p.id =
--     finance_period_close_checklist_items.period_id) AND ((app.has_active_tenant_membership(
--     p.tenant_id) AND NOT app.actor_holds_customer_user_layer(p.tenant_id)) OR
--     app.is_supreme_admin())))));
--
--   The function below reproduces this CURRENT text -- has_active_tenant_membership AND NOT
--   actor_holds_customer_user_layer, OR is_supreme_admin, evaluated against the parent
--   app.finance_fiscal_periods row's own tenant_id -- restated as an inner join + WHERE
--   filter (required because this is SECURITY DEFINER and runs as its owner, so the base
--   table's own row-level security is never evaluated for it). The join is safe and never
--   fans out: finance_period_close_checklist_items.period_id is a NOT NULL FK to
--   app.finance_fiscal_periods.id, which is that table's own primary key
--   (20260728220000:58,106) -- exactly one parent period per checklist-item row.
--
-- RULE C (precedent staleness) -- every helper cited below independently re-confirmed
-- against its MOST RECENT create-or-replace, not its original:
--   * app.has_active_tenant_membership(uuid, uuid) -- 3 definitions repo-wide
--     (20260716105512 original, 20260716111315, and
--     20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64, the latest by
--     filename date). The 20260907110000 body is read and used here -- it excludes a
--     suspended/revoked app.users row on top of the active tenant_user_identities check, and
--     its own body already ORs in `app.is_supreme_admin(p_auth_user_id)` and
--     `app.has_active_support_grant(p_tenant_id, p_auth_user_id)` internally. Practical
--     consequence for this function's own header comment on the app.* function below: a
--     Supreme Admin with zero tenant membership for this period's tenant already passes this
--     predicate transitively through has_active_tenant_membership's own internal OR-branch --
--     there is no SEPARATE, explicit is_supreme_admin() bypass needed in that inner branch
--     for that case to work; the outer `OR app.is_supreme_admin(...)` in the policy text
--     above is what actually matters for a Supreme Admin who is also NOT excluded by the
--     `AND NOT actor_holds_customer_user_layer` conjunct on the has_active_tenant_membership
--     side (a real, if narrow, distinction: the outer OR is not redundant, since
--     has_active_tenant_membership's own transitive supreme-admin pass would otherwise still
--     be defeated by `AND NOT actor_holds_customer_user_layer` if a supreme admin somehow
--     also held a customer_user-layer membership in the same tenant).
--   * app.actor_holds_customer_user_layer(uuid, uuid) --
--     20260730311000_harden_customer_inventory_access_rls_isolation.sql:71. Repo-wide grep
--     for a later `create or replace function app.actor_holds_customer_user_layer`: zero
--     hits. One CREATE, never replaced -- current.
--   * app.is_supreme_admin(uuid) -- 20260716105512_create_rls_tenant_policies.sql:45.
--     Repo-wide grep for a later `create or replace function app.is_supreme_admin`: zero
--     hits. One CREATE, never replaced -- current.
--   * app.assert_actor_is_session_identity(uuid) --
--     20260730440000_harden_actor_identity_session_crosscheck.sql:59, `create or replace`,
--     the only definition anywhere -- current. Returns void; the session identity's own
--     mismatch check runs before any lookup below.
--
-- RULE C cross-check within THIS SAME TABLE, as required by this batch's own scope note --
-- two existing app.* functions were read in full, at their CURRENT bodies:
--   1. app.get_finance_period_close_readiness(uuid, uuid) -- 3 definitions repo-wide
--      (20260728220000 original, 20260810900000, and
--      20260902100000_harden_tenant_id_disclosure_finance.sql:958-989, the latest by
--      filename date -- read in full). Its own gate for reading this SAME table is NOT the
--      RLS predicate above: it resolves the parent period once, folds "not found" together
--      with `app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id)`
--      into a single not-found-shaped error (no `actor_holds_customer_user_layer` exclusion
--      at all), then separately requires `app.check_finance_period_authority('View', ...)`
--      (a FIN:View RBAC-permission check) before reading
--      `app.finance_period_close_checklist_items` directly with no further per-row filter.
--      This is a genuinely different authority MECHANISM (RBAC-permission-gated, entry-point
--      only) than the table's own current row-level security predicate reproduced above
--      (membership-plus-customer-layer-exclusion, evaluated so it could in principle differ
--      per row if a period ever spanned tenants, which it cannot -- period_id is a single FK).
--      This is a disclosed, out-of-scope-to-fix inconsistency between this table's declared
--      RLS SELECT policy and one of its own pre-existing reader functions -- mirroring this
--      same remediation effort's own prior disclosed-but-unfixed finding on
--      app.check_approval_request_authority
--      (20260909010000_close_o1_query_layer_cluster0_batch3_costing_credit_approval.sql).
--      Deliberately NOT reused as precedent here: this new function reproduces the table's
--      own current, actually-declared row-visibility policy, not
--      get_finance_period_close_readiness's separate FIN:View entry gate -- copying the
--      latter would silently swap in a different (and, on the customer-layer axis, WIDER)
--      authority envelope than the one this O1 remediation is required to replicate.
--   2. app.acknowledge_finance_period_checklist_item(uuid, text, boolean, text, uuid, text)
--      -- read at its current body,
--      20260902100000_harden_tenant_id_disclosure_finance.sql:57-102 (the latest of several
--      touches -- 20260810700000 and 20260826000000/20260831290000 only added
--      SECURITY DEFINER/search_path or a public.* wrapper without changing this body's own
--      authority logic; 20260902100000 is the one that actually rewrote the gate). Confirmed
--      NOT a substitute for, and NOT copied as precedent for, this new read function: it is a
--      single-item MUTATION (one row, matched by exact (period_id, item_key), not a period's
--      full checklist), gated by `app.has_active_tenant_membership(v_period.tenant_id,
--      p_actor_auth_user_id)` (again no `actor_holds_customer_user_layer` exclusion) PLUS a
--      separate FIN:Edit permission check PLUS a closed-period guard -- a narrower-in-shape,
--      differently-sourced (RBAC Edit, not RLS-predicate read) authority envelope than the
--      plain read this function replicates. Reusing its gate would both under- and
--      over-restrict this list-read relative to the table's own actual SELECT policy.
--
-- Deliberate column exclusion: none (see contract fidelity note above).
--
-- No p_limit/pagination: the original `.from(...)` call site never applied a
-- `.range()`/`.limit()` either, and one period's own checklist is inherently bounded by
-- `finance_period_close_checklist_items_period_key_unique (period_id, item_key)` -- at most
-- one row per item key, itself a small snapshot pinned once from the tenant's
-- finance_close_policy config at calendar-generation time (this table's own header comment,
-- 20260728220000:119-120: "never re-read live once pinned"), never an unbounded feed.
-- Mirrors app.list_costing_response_components' identical no-pagination reasoning for the
-- same "bounded-by-a-unique-constraint child list" shape.
--
-- Zero-rows-not-exception posture: a nonexistent p_period_id, a cross-tenant one, or an
-- in-tenant one this actor cannot see (customer_user-layer-excluded, or no active
-- membership) all collapse to zero rows, never a raised exception -- matching the original
-- RLS-filtered `.from()` call's own silent-empty-result behavior, and matching the page's
-- own existing empty-state copy ("No close-policy checklist was effective when this period
-- was generated -- nothing to acknowledge.",
-- app/(tenant)/[tenantSlug]/finance/fiscal-periods/[periodId]/page.tsx:99). Unlike
-- app.get_finance_period_close_readiness (which raises on an unresolvable/unauthorized
-- period because it is resolving one named period as its primary subject), this is a list
-- shape over a child collection, so it follows app.list_credit_profiles/
-- app.list_costing_response_components's silent-empty convention instead.
--
-- RULE A: this function is `authenticated`-reachable (see grants below) and takes an
-- explicit p_actor_auth_user_id, so the session-identity assertion is its first executable
-- statement, before any lookup or row filter.
--
-- Wording note: this header deliberately avoids pairing the words this table's policy
-- revision was made by with a literal Postgres auth-helper call inside any
-- `comment on function ... is '...'` string below (only in this plain `--` header, which
-- this repository's own check-rls-initplan.ts guard never parses) -- the established
-- avoidance for that guard's known comment-prose false positive.

create function app.list_finance_period_checklist_items(
  p_period_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.finance_period_close_checklist_items
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select i.*
  from app.finance_period_close_checklist_items i
  join app.finance_fiscal_periods p on p.id = i.period_id
  where i.period_id = p_period_id
    and (
      (app.has_active_tenant_membership(p.tenant_id, p_actor_auth_user_id)
         and not app.actor_holds_customer_user_layer(p.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by i.item_key asc;
$$;

comment on function app.list_finance_period_checklist_items(uuid, uuid) is
  'FIN-193/O1 remediation: one fiscal period''s own close-checklist items, item_key ascending, replacing server/queries/fiscal-period.ts:73''s broken .from("finance_period_close_checklist_items") read (app is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row visibility joins to the parent app.finance_fiscal_periods row and reproduces that table''s CURRENT finance_period_close_checklist_items_select_scoped predicate, as most recently revised in migration 20260730560000 (NOT the narrower original 20260728220000 wording, which lacked the customer_user-layer exclusion): active tenant membership for the parent period''s own tenant, excluding an active customer_user-layer principal, with a global supreme-admin grant always passing regardless of membership. Deliberately reproduces this table''s own declared read policy, not the different, narrower-mechanism gates used by the pre-existing app.get_finance_period_close_readiness (a separate FIN:View permission check) or app.acknowledge_finance_period_checklist_item (a single-item FIN:Edit mutation) on this same table -- see this migration fragment''s own file header for the full disclosed comparison. Returns zero rows, never an exception, for a nonexistent period_id, a cross-tenant one, or an in-tenant one this actor cannot see -- matching the original RLS-filtered read''s own silent-empty-result posture. No LIMIT/pagination: a period''s own checklist is inherently bounded by finance_period_close_checklist_items_period_key_unique (period_id, item_key), a small snapshot pinned once at calendar-generation time.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_finance_period_checklist_items with an identical grant set, never
-- a reimplementation.
create function public.list_finance_period_checklist_items(
  p_period_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.finance_period_close_checklist_items
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_period_checklist_items(p_period_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_finance_period_checklist_items(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_period_checklist_items with an identical grant set, never a reimplementation.';

-- app.list_finance_period_checklist_items: same grant set as the base table it reads
-- (`grant select on app.finance_period_close_checklist_items to authenticated, service_role;`,
-- 20260728220000:611), and the same grant set the sibling app.get_finance_period_close_readiness
-- / app.acknowledge_finance_period_checklist_item RPCs already carry on this same table
-- (20260826000000_create_public_api_data_wrappers.sql / 20260831290000).
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke before grant, the
-- standing per-migration convention.
revoke execute on function app.list_finance_period_checklist_items(uuid, uuid) from public;
grant execute on function app.list_finance_period_checklist_items(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own ALTER DEFAULT PRIVILEGES bootstrap grant of EXECUTE on every
-- new function in schema public to anon/authenticated/service_role at CREATE time) -- pattern
-- per 20260907150000_fix_remaining_tenant_lookup_guards_postgrest_schema_exposure_iss_o1_o2.sql:69-91,
-- and identical to every public.* wrapper in this same remediation series (e.g.
-- 20260909010000_close_o1_query_layer_cluster0_batch3_costing_credit_approval.sql). `anon` is
-- never granted -- this is an authenticated-only read.
revoke execute on function public.list_finance_period_checklist_items(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_period_checklist_items(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/fiscal-period.ts
--
-- 1. Client type: `FiscalPeriodChecklistTableClient` (currently `Pick<SupabaseClient,
--    "from">`, line 23) must widen to include "rpc" -- either replace its own declaration
--    with `Pick<SupabaseClient, "rpc">` (it is no longer used for a `.from()` call at all
--    once this function moves to .rpc(), so it can be collapsed into the same
--    `FiscalPeriodQueryRpcClient` alias every other function in this file already uses, line
--    22) or keep a separate alias if some other reason keeps it distinct -- there is none
--    left in this file after this change, so collapsing it into
--    `FiscalPeriodQueryRpcClient` (and dropping the now-unused
--    `FiscalPeriodChecklistTableClient` export) is the simpler, correct move. Callers
--    (currently only the one page-level call site below and the test file) pass a real
--    Supabase client either way, so this is a type-only simplification.
--
-- 2. Add a required third parameter `actorAuthUserId: string` to
--    listFinancePeriodChecklistItems's own signature:
--      export async function listFinancePeriodChecklistItems(
--        client: FiscalPeriodQueryRpcClient,
--        periodId: string,
--        actorAuthUserId: string,
--      ): Promise<FinancePeriodChecklistItem[]>
--
-- 3. Replace the `.from(...)` chain (current lines 74-77) with:
--      const { data, error } = await client.rpc("list_finance_period_checklist_items", {
--        p_period_id: periodId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    Drop the now-redundant `.order(...)` call -- the RPC already applies
--    `order by i.item_key asc` server-side. Error handling and the row mapping (line 78,
--    `(data ?? []).map((row) => parseFinancePeriodChecklistItem(row as Record<string,
--    unknown>))`) are unchanged -- the RPC returns the identical 11-column shape, in the
--    identical snake_case column names, as the old `.from()` result (`i.*` selects the same
--    base table this function did).
--
-- 4. Also update the file-level doc comment at the top of the function (current lines 72,
--    "app.finance_period_close_checklist_items carries a broad tenant-member SELECT policy,
--    no RPC needed -- mirrors app.finance_rounding_modes' own direct-table-read convention")
--    -- this claim is exactly the defect this migration fixes (RPC IS needed; `app` is
--    invisible to PostgREST regardless of the policy's own breadth) and should be replaced
--    with a comment matching this file's own sibling functions' style (e.g. "RPC-backed read
--    of one period's own close-checklist items via app.list_finance_period_checklist_items,
--    item_key ascending").
--
-- 5. Call site needing the new third argument -- already has a live, session-asserted actor
--    id in scope one line above and two lines below this exact call, no new plumbing
--    required:
--      app/(tenant)/[tenantSlug]/finance/fiscal-periods/[periodId]/page.tsx:43
--      BEFORE: `checklistItems = await listFinancePeriodChecklistItems(supabase, periodId);`
--      AFTER:  `checklistItems = await listFinancePeriodChecklistItems(supabase, periodId,
--               access.authUserId);`
--      (`access.authUserId` is already resolved at the top of this same page via
--      `resolveFinanceAccessForRequest`, line 26, and already threaded into the sibling
--      `listFinanceFiscalPeriods` call one line above this one (line 38) and into
--      `getFinancePeriodCloseReadiness`/`getFinancePeriodTransitionHistory` two lines below
--      it (lines 44-45) -- this is the one remaining sibling call in this try block still
--      missing it.)
--    Grepped repo-wide for every other call site of `listFinancePeriodChecklistItems`
--    outside this file: none found -- server/queries/fiscal-period.test.ts (below) is the
--    only other reference, and no other page.tsx/actions.ts anywhere in app/ calls it.
--
-- 6. server/queries/fiscal-period.test.ts (describe block "listFinancePeriodChecklistItems",
--    lines 84-102) currently declares its own local `fakeTableClient` helper (a
--    `.from().select().eq().order()` chain stub, lines 85-92) and calls
--    `listFinancePeriodChecklistItems(client, PERIOD_ID)` (line 98, only two args). Needs
--    updating to reuse the shared `fakeClient` helper already defined at the top of this same
--    test file (lines 37-48, the same `.rpc(fn, args)` stub every other describe block in
--    this file already uses) instead of its own bespoke `fakeTableClient`, and to call
--    `listFinancePeriodChecklistItems(client, PERIOD_ID, ACTOR_ID)` (both constants already
--    declared at the top of this file, lines 15-16) -- matching every sibling describe block
--    in the same file (e.g. "getFinancePeriodCloseReadiness", lines 64-70). Not attempting
--    this rewrite here, per this task's scope (SQL only).

-- ===========================================================================
-- TABLE 4 of 4: app.job_profitability_directory
-- ===========================================================================
-- CG-AUDIT-2026-09-02 Ø1-query-layer remediation -- cluster 1 (finance), batch 1 of N.
--
-- SCOPE: 1 function, closing the single broken read in
-- server/queries/job-profitability.ts:20 (getJobProfitability):
--   1. app.job_profitability_directory (server/queries/job-profitability.ts)
--
-- SEVERITY (unchanged from every cluster 0 batch's own header): supabase/config.toml only
-- exposes "public"/"graphql_public" to PostgREST -- the "app" Postgres schema, where
-- app.job_profitability_directory actually lives, is completely invisible to it. The
-- `.from("job_profitability_directory").select("*").eq("job_order_id", jobOrderId)
-- .eq("is_current", true).maybeSingle()` call at server/queries/job-profitability.ts:20 has
-- NEVER worked in production; it 404s as a nonexistent relation from PostgREST's point of
-- view. This is a live, currently-broken read path behind a real, reachable page (the Job
-- Order detail page's Profitability panel), not merely an architectural backlog item.
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior Ø1 remediation commit in this
-- series, cluster 0 batches 1-5): author a new `app.*` SECURITY DEFINER function performing
-- the equivalent SELECT with correct tenant/RLS/authority scoping and masking, plus a thin
-- `public.*` pass-through wrapper (the only PostgREST-reachable surface, since `app` itself
-- is invisible) carrying an IDENTICAL grant set -- never a reimplementation.
--
-- ===========================================================================
-- SOURCE OF TRUTH: app.job_profitability_directory (view)
-- ===========================================================================
-- Grepped `create or replace view app.job_profitability_directory` / `create view
-- app.job_profitability_directory` across every file in supabase/migrations/*.sql, sorted by
-- filename -- 3 hits, in chronological order:
--   1. supabase/migrations/20260728120000_create_operations_job_profitability.sql:242
--      (original CREATE VIEW, 22 columns)
--   2. supabase/migrations/20260901050000_label_operations_job_profitability_revenue_basis.sql:192
--      (CREATE OR REPLACE VIEW, appends revenue_basis -- 23 columns)
--   3. supabase/migrations/20260902050000_wire_fx_conversion_into_operations_job_profitability.sql:408-437
--      (CREATE OR REPLACE VIEW, appends 13 FX/invoiced columns -- 36 columns, the LATEST and
--      therefore authoritative definition)
-- The function below reproduces #3's own defining SELECT verbatim, re-expressed against the
-- base table app.job_profitability_snapshots with an explicit p_actor_auth_user_id instead of
-- the view's own default-session auth.uid reliance (see "WHY RE-EXPRESSED" below).
--
-- Row visibility (from #3, line 437):
--   where app.can_access_record((session identity), jo.tenant_id, jo.owner_user_id,
--     app.lead_record_scope_org_unit_ids(jo.org_unit_id), null)
--   joined via app.job_orders jo on jo.id = jps.job_order_id
--
-- Column masking (from #3, the CASE expressions on lines 412-434): revenue_currency,
-- revenue_amount, cost_currency, cost_amount, margin_amount, margin_percent,
-- revenue_base_amount, revenue_fx_rate, invoiced_currency, invoiced_amount,
-- invoiced_base_amount, invoiced_fx_rate are nulled, and source_cost_version_ids /
-- source_invoice_ids emptied to '{}'::uuid[], unless app.has_view_job_margin(jps.tenant_id[,
-- actor]) is true; margin_masked is set to the negation. revenue_basis, base_currency,
-- revenue_fx_as_of, revenue_fx_status, invoiced_status, invoiced_fx_as_of, invoiced_fx_status
-- are deliberately UNMASKED state/timing metadata (per #3's own comment on view, restated
-- verbatim below) -- id/tenant_id/job_order_id/version_number/is_current/status/
-- blocked_reason/recalculation_reason/calculated_by_auth_user_id/calculated_at/
-- record_version/created_by/created_at/updated_at are likewise never masked.
--
-- RULE B (RLS predicate currency) -- ran the required greps rather than trusting any
-- restated summary (including this ticket's own paraphrase):
--   * `grep -rn "alter policy" supabase/migrations/*.sql | grep -i "job_profit\|job_orders"`
--     -> ZERO hits. `job_profitability_snapshots_select_scoped` (created alongside the view
--     itself, 20260728120000:229-238) and `job_orders_select_scoped`
--     (20260727090000_create_operations_job_order.sql:434-436) have each only ever been
--     created once and never rewritten since. Unlike batch 3's app.credit_profiles_directory
--     finding (a hand-written view WHERE clause that silently drifted from its base table's
--     later-rewritten policy), there is no drift to reconcile here: the view's own WHERE
--     clause (#3, line 437) and the CURRENT job_profitability_snapshots_select_scoped policy
--     text are, and have always been, character-for-character the same predicate (both
--     wrapping the identical exists-join-to-job_orders-plus-can_access_record shape), and
--     job_orders_select_scoped itself composes the identical can_access_record call with no
--     extra conjunct. The predicate reproduced in this function's own WHERE/JOIN below is
--     therefore confirmed current on independent, direct inspection -- not merely copied
--     from the view text.
--   * Both source policies (per their own live text) call `app.can_access_record` with the
--     session identity read through the repository's own `(select auth.<fn>())` initplan-
--     hoisting idiom -- irrelevant to this function's own body, since a SECURITY DEFINER
--     function never evaluates a base table's row-security policies for its caller at all
--     (it runs as its owner); the join/WHERE filter below is this function's own,
--     independently-evaluated substitute for that policy, not a reference to it.
--
-- RULE C (precedent staleness) -- every helper cited below independently re-confirmed
-- against its MOST RECENT create-or-replace, not its original creation migration:
--   * app.can_access_record(uuid, uuid, uuid, uuid[], text) -- `grep -rn "create or replace
--     function app.can_access_record\|create function app.can_access_record"` ->
--     exactly two hits, 20260716110430_create_field_record_access.sql:31 (original) and
--     20260723180000_create_commercial_sales_pipeline.sql:50 (CREATE OR REPLACE, COM-146 --
--     coalesces the whole owner/shared-scope/customer-ref OR-expression to `false` so a NULL
--     owner_user_id can never silently resolve as an uncaught SQL NULL). 20260723180000 is
--     the current, later definition and is the body reproduced in the WHERE clause below --
--     the same current body cluster 0's every batch already re-confirmed and reused.
--   * app.lead_record_scope_org_unit_ids(uuid) -- one hit only
--     (20260723090000_create_commercial_lead_management.sql:164), never replaced -- current.
--   * app.has_view_job_margin(uuid, uuid) -- one hit only
--     (20260728120000_create_operations_job_profitability.sql:56), never replaced -- current.
--     Its own signature already takes an explicit second `p_auth_user_id uuid default
--     auth.uid()` parameter (unlike the view's zero-arg call site, which relies on that
--     default), so this function supplies p_actor_auth_user_id explicitly at every call site
--     below, overriding the default rather than depending on it.
--   * app.assert_actor_is_session_identity(uuid) --
--     20260730440000_harden_actor_identity_session_crosscheck.sql:59, `create or replace`,
--     the only definition -- current. Raises `actor_identity_mismatch` (errcode
--     insufficient_privilege) when a live session identity disagrees with the claimed
--     p_actor_auth_user_id; a no-op when the session identity resolves to NULL
--     (service_role/superuser/db-tests/nested SECURITY DEFINER calls).
--
-- WHY THE MASKING IS RE-EXPRESSED AGAINST THE BASE TABLE, NOT BY SELECTING FROM THE VIEW:
-- the view's own CASE expressions call app.has_view_job_margin(jps.tenant_id) relying on
-- that helper's *default* second-argument session lookup -- correct only under a live
-- PostgREST request/session GUC, never when invoked from a SECURITY DEFINER function called
-- via RPC (there is no live per-request session context to default from at that point). This
-- is the exact same tension app.search_vendor_rates, app.list_customer_contract_price_
-- components, and (this same remediation effort) every masked cluster-0 _directory function
-- already resolved by re-expressing the view's masking directly against its base table with
-- an explicit p_actor_auth_user_id argument instead of the view's own default-session call.
-- This function does the identical thing for app.job_profitability_directory.
--
-- ===========================================================================
-- CRITICAL DISTINCTION -- app.get_finance_job_profitability is a DIFFERENT function, over a
-- DIFFERENT table, gated by a DIFFERENT authority check. Read to confirm before writing a
-- single line below.
-- ===========================================================================
-- `grep -rn "create or replace function app.get_finance_job_profitability\|create function
-- app.get_finance_job_profitability"` -> two hits:
--   * supabase/migrations/20260729260000_create_finance_job_profitability.sql:304 (original)
--   * supabase/migrations/20260903132000_harden_tenant_id_disclosure_finance_residual.sql:1009
--     (CREATE OR REPLACE -- its own inline comment says "live definition from
--     20260729260000_create_finance_job_profitability.sql", i.e. restated byte-for-byte
--     unchanged as part of that migration's own broader bulk-restatement pass, not a logic
--     change)
-- The current (20260903132000) body, read in full:
--   create or replace function app.get_finance_job_profitability(p_job_order_id uuid, p_actor_auth_user_id uuid)
--   returns setof app.finance_job_profitability_facts
--   ...
--   begin
--     select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
--     if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
--       raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
--     end if;
--     if not app.has_view_finance_margin(v_job.tenant_id, p_actor_auth_user_id) then
--       raise exception 'insufficient_authority: identity % lacks FIN:View margin for tenant %', ...
--     end if;
--     return query select * from app.finance_job_profitability_facts where job_order_id = p_job_order_id and is_current;
--   end;
-- Three independently-confirmed points of difference from the function this migration adds:
--   1. TABLE: app.get_finance_job_profitability reads app.finance_job_profitability_facts
--      (FIN-212, the accounting-truth counterpart, revenue_basis fixed to 'billed' --
--      the actual amount from every issued app.finance_invoices row). This migration's own
--      function reads app.job_profitability_snapshots (OPS-179, the quote-time operational
--      estimate, revenue_basis fixed to 'quoted'). The two figures are deliberately
--      independent and can legitimately differ (see 20260901050000's own comment on table).
--   2. GATE: app.get_finance_job_profitability is gated by app.has_view_finance_margin (the
--      FIN:View margin permission). This migration's own function is gated by
--      app.has_view_job_margin (the OPS:View margin permission) for masking, and
--      app.can_access_record for row visibility -- a structurally different envelope (row
--      visibility vs. an all-or-nothing tenant-wide FIN:View margin gate that raises rather
--      than masks).
--   3. CALLER: app.get_finance_job_profitability already exists, is already RPC-based, and
--      already serves Finance's own read path. It is NOT called, aliased, wrapped, or reused
--      anywhere in this migration -- server/queries/job-profitability.ts's
--      getJobProfitability needs the Operations (OPS-179) figure, not the Finance one, and
--      no code change described in this migration's TS INTEGRATION block touches Finance's
--      query files at all.
-- The function this migration adds is named app.get_job_profitability_directory (not
-- app.get_job_profitability, to avoid a name one edit-distance from the existing, unrelated
-- app.get_finance_job_profitability and to name it after the view it replaces, matching this
-- entire remediation series' own `get_<view_name>` naming convention).
--
-- ===========================================================================
-- ALSO CONFIRMED NOT A SUBSTITUTE: app.calculate_job_profitability
-- ===========================================================================
-- Read in full (current body: 20260902050000_wire_fx_conversion_into_operations_job_
-- profitability.sql:227-400, itself a byte-for-byte carry-forward of 20260728120000's
-- original body per 20260901050000's own header note "app.calculate_job_profitability's live
-- body was byte-for-byte identical to the original 20260728120000 migration -- no drift to
-- reconcile"). It is a mutation (recalculates and INSERTs a new job_profitability_snapshots
-- version, flips the prior is_current row), gated by THREE checks in sequence: OPS:Edit
-- (`app.evaluate_permission(actor, tenant, 'OPS', 'Edit')`), OPS:View margin
-- (`app.has_view_job_margin`), and `app.can_access_record`. That first conjunct -- write
-- authority -- has no analog in a plain SELECT: a viewer who can read a masked-but-visible
-- profitability row (can_access_record true, has_view_job_margin false or true) very often
-- cannot edit the Job Order at all. Gating a read function on OPS:Edit would therefore
-- UNDER-serve real read-only viewers the view itself already admits; this migration's own
-- read function below does NOT call evaluate_permission('OPS','Edit') anywhere, matching the
-- view's own read-only authority envelope exactly instead.
--
-- ===========================================================================
-- CONTRACT FIDELITY
-- ===========================================================================
-- server/contracts/job-profitability/job-profitability.ts's JobProfitabilityDirectoryRowSchema
-- (JobProfitabilitySnapshotSchema extended with marginMasked) has exactly 36 fields, and
-- parseJobProfitabilityDirectoryRow/parseJobProfitabilitySnapshot consume exactly the 36
-- snake_case columns the view itself projects (verified 1:1 by hand against both the schema
-- and the view's own column list above) -- no physical column is excluded here because none
-- exists to exclude: the view's projection already excludes nothing from the base table's own
-- 34 real columns (it adds one derived column, margin_masked, beyond them). RETURNS TABLE below
-- reproduces that exact 36-column list, in the view's own column order, so the RPC's row shape
-- is byte-for-byte what parseJobProfitabilityDirectoryRow already expects -- no TS-side mapping
-- change beyond the call itself (see TS INTEGRATION below).
--
-- No p_limit/pagination: the original .from(...).eq(...).eq(...).maybeSingle() call site
-- already narrows to at most one row (job_profitability_snapshots_one_current_idx is a real
-- partial unique index on (job_order_id) where is_current, so at most one is_current row can
-- ever exist per Job Order) -- this is a by-id lookup, not an unbounded list, matching every
-- "no p_tenant_id, per-row, zero-or-one" precedent in this series
-- (app.get_credit_profile_for_account, batch 3). `order by ... limit 1` is added purely as a
-- defensive belt-and-suspenders measure (the partial unique index already makes a second
-- is_current row physically impossible) so this function can never itself raise a
-- "more than one row" condition even if that invariant were ever violated at the storage
-- layer -- an explicit RETURNS TABLE with an implicit zero-or-one-row result, matching
-- .maybeSingle()'s own contract, is preserved either way.
--
-- Deliberate column exclusion: none (see CONTRACT FIDELITY above).
--
-- RULE A: this function is `authenticated`-reachable (see grants below) and takes an
-- explicit p_actor_auth_user_id, so `app.assert_actor_is_session_identity
-- (p_actor_auth_user_id)` is invoked (plpgsql `perform` form) as the first executable
-- statement, before any lookup or authority check.
--
-- check-rls-initplan.ts false-positive avoidance: this migration's own `comment on function`
-- strings deliberately never combine the literal phrase describing a policy rewrite with a
-- parenthesized `auth.uid`/`auth.jwt` call in the same string (unlike this file's `--` line
-- comments above, which are blanked out by that scanner's own comment-stripping pass before
-- parsing and are therefore never at risk) -- reworded, never suppressed.
--
-- ISS-2026-309 grant parity: the public.* wrapper below explicitly revokes execute from
-- `anon, authenticated, service_role, public` before re-granting only `authenticated,
-- service_role` -- the same two roles the view itself was ever granted select to
-- (20260902050000:447, `grant select on app.job_profitability_directory to authenticated,
-- service_role;`), never `anon`.

create function app.get_job_profitability_directory(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  version_number integer,
  is_current boolean,
  status text,
  blocked_reason text,
  revenue_currency text,
  revenue_amount numeric,
  cost_currency text,
  cost_amount numeric,
  margin_amount numeric,
  margin_percent numeric,
  source_cost_version_ids uuid[],
  margin_masked boolean,
  recalculation_reason text,
  calculated_by_auth_user_id uuid,
  calculated_at timestamptz,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  revenue_basis text,
  base_currency text,
  revenue_base_amount numeric,
  revenue_fx_rate numeric,
  revenue_fx_as_of timestamptz,
  revenue_fx_status text,
  invoiced_currency text,
  invoiced_amount numeric,
  invoiced_status text,
  invoiced_base_amount numeric,
  invoiced_fx_rate numeric,
  invoiced_fx_as_of timestamptz,
  invoiced_fx_status text,
  source_invoice_ids uuid[]
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
    jps.id,
    jps.tenant_id,
    jps.job_order_id,
    jps.version_number,
    jps.is_current,
    jps.status,
    jps.blocked_reason,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.revenue_currency else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.revenue_amount else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.cost_currency else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.cost_amount else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.margin_amount else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.margin_percent else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.source_cost_version_ids else '{}'::uuid[] end,
    not app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id),
    jps.recalculation_reason,
    jps.calculated_by_auth_user_id,
    jps.calculated_at,
    jps.record_version,
    jps.created_by,
    jps.created_at,
    jps.updated_at,
    jps.revenue_basis,
    jps.base_currency,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.revenue_base_amount else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.revenue_fx_rate else null end,
    jps.revenue_fx_as_of,
    jps.revenue_fx_status,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.invoiced_currency else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.invoiced_amount else null end,
    jps.invoiced_status,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.invoiced_base_amount else null end,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.invoiced_fx_rate else null end,
    jps.invoiced_fx_as_of,
    jps.invoiced_fx_status,
    case when app.has_view_job_margin(jps.tenant_id, p_actor_auth_user_id) then jps.source_invoice_ids else '{}'::uuid[] end
  from app.job_profitability_snapshots jps
  join app.job_orders jo on jo.id = jps.job_order_id
  where jps.job_order_id = p_job_order_id
    and jps.is_current = true
    and app.can_access_record(
      p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id,
      app.lead_record_scope_org_unit_ids(jo.org_unit_id), null
    )
  order by jps.calculated_at desc
  limit 1;
end;
$$;

comment on function app.get_job_profitability_directory(uuid, uuid) is
  'OPS-179 read (CG-AUDIT-2026-09-02 O1, cluster 1 finance batch 1): read path for app.job_profitability_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row-visibility filter (join to app.job_orders + app.can_access_record against tenant/owner/org-unit scope) reproduces job_profitability_snapshots_select_scoped''s own predicate verbatim -- confirmed via repo-wide grep for a later rewrite of that policy or of job_orders_select_scoped: neither has ever been redefined since its own original creation, and both already match the view''s own WHERE clause character for character, so there is no drift to reconcile (unlike the credit_profiles_directory finding in this series'' batch 3). The revenue/cost/margin/FX/invoiced-total CASE-WHEN masks and the margin_masked flag are copied verbatim from the view''s own definition, re-expressed against the base table with an explicit p_actor_auth_user_id instead of app.has_view_job_margin''s own default-session second argument (the same fix this series'' every masked _directory function already established for the identical default-session-argument-under-RPC problem). Distinct from, and never a substitute for, app.get_finance_job_profitability: that function reads the unrelated app.finance_job_profitability_facts table (the accounting-truth ''billed'' figure) and is gated by app.has_view_finance_margin, not app.has_view_job_margin -- see this migration''s own file header for the full independently-verified comparison. Also distinct from app.calculate_job_profitability, a mutation additionally gated by OPS:Edit -- an authority envelope this read function deliberately does not require. Returns zero rows (never an exception) for a nonexistent job_order_id, a Job Order with no current snapshot, or an actor who cannot reach that Job Order''s tenant/owner/org-unit scope, matching the original .maybeSingle() call site''s own null-on-empty posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_job_profitability_directory with an identical grant set, never a
-- reimplementation.
create function public.get_job_profitability_directory(
  p_job_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  version_number integer,
  is_current boolean,
  status text,
  blocked_reason text,
  revenue_currency text,
  revenue_amount numeric,
  cost_currency text,
  cost_amount numeric,
  margin_amount numeric,
  margin_percent numeric,
  source_cost_version_ids uuid[],
  margin_masked boolean,
  recalculation_reason text,
  calculated_by_auth_user_id uuid,
  calculated_at timestamptz,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  revenue_basis text,
  base_currency text,
  revenue_base_amount numeric,
  revenue_fx_rate numeric,
  revenue_fx_as_of timestamptz,
  revenue_fx_status text,
  invoiced_currency text,
  invoiced_amount numeric,
  invoiced_status text,
  invoiced_base_amount numeric,
  invoiced_fx_rate numeric,
  invoiced_fx_as_of timestamptz,
  invoiced_fx_status text,
  source_invoice_ids uuid[]
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_job_profitability_directory(p_job_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_job_profitability_directory(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_job_profitability_directory with an identical grant set, never a reimplementation.';

-- app.get_job_profitability_directory: same grant set as the view it replaces
-- (`grant select on app.job_profitability_directory to authenticated, service_role;`,
-- 20260902050000:447).
revoke execute on function app.get_job_profitability_directory(uuid, uuid) from public;
grant execute on function app.get_job_profitability_directory(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own ALTER DEFAULT PRIVILEGES bootstrap grant of EXECUTE to
-- anon/authenticated on every new function in schema public) -- pattern per
-- 20260907150000_fix_remaining_tenant_lookup_guards_postgrest_schema_exposure_iss_o1_o2.sql:69-91.
revoke execute on function public.get_job_profitability_directory(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_job_profitability_directory(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/job-profitability.ts
--
-- 1. Client type: `JobProfitabilityQueryClient` (line 9) is currently
--    `Pick<SupabaseClient, "from">`. Widen it to include "rpc":
--      export type JobProfitabilityQueryClient = Pick<SupabaseClient, "from" | "rpc">;
--    ("from" itself becomes unused by this function afterward, but is left on the alias --
--    matching this series' own established convention of widening rather than narrowing a
--    shared client-type alias -- there is only the one function in this file, so nothing
--    else in job-profitability.ts still needs "from" either; if a lint flags the now-unused
--    "from" this alias could instead be narrowed to `Pick<SupabaseClient, "rpc">`, but no
--    other file in this series has done that for a single-function query file, so "from" is
--    kept for consistency unless the project's own lint gate objects.)
--
-- 2. Add a required second parameter `actorAuthUserId: string` to getJobProfitability's own
--    signature:
--      export async function getJobProfitability(
--        client: JobProfitabilityQueryClient,
--        jobOrderId: string,
--        actorAuthUserId: string,
--      ): Promise<JobProfitabilityDirectoryRow | null>
--
-- 3. Replace the `.from(...)` chain (current line 20) with:
--      const { data, error } = await client.rpc("get_job_profitability_directory", {
--        p_job_order_id: jobOrderId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--      if (error) {
--        throw new JobProfitabilityQueryError(error.message);
--      }
--      const row = Array.isArray(data) ? (data[0] ?? null) : (data ?? null);
--      return row ? parseJobProfitabilityDirectoryRow(row as Record<string, unknown>) : null;
--    (RETURNS TABLE surfaces from PostgREST/postgrest-js as an array, never a bare object --
--    this is the exact `data[0] ?? null` unwrap idiom this series already uses everywhere a
--    `.maybeSingle()` `.from()` read is replaced by a `RETURNS TABLE` RPC returning
--    zero-or-one row; the `Array.isArray` guard is defensive against a mocked test client
--    that hands back a bare object instead of an array, matching how this same idiom is
--    written at every other cluster-0 zero-or-one-row call site in this series.)
--    Full replacement for the current function body (lines 19-25):
--      export async function getJobProfitability(client: JobProfitabilityQueryClient, jobOrderId: string, actorAuthUserId: string): Promise<JobProfitabilityDirectoryRow | null> {
--        const { data, error } = await client.rpc("get_job_profitability_directory", { p_job_order_id: jobOrderId, p_actor_auth_user_id: actorAuthUserId });
--        if (error) {
--          throw new JobProfitabilityQueryError(error.message);
--        }
--        const row = Array.isArray(data) ? (data[0] ?? null) : (data ?? null);
--        return row ? parseJobProfitabilityDirectoryRow(row as Record<string, unknown>) : null;
--      }
--
-- 4. Row mapping is otherwise unchanged: the RPC returns the identical 36-column shape, in
--    the identical snake_case column names, as the old view select -- parseJobProfitability
--    DirectoryRow (server/contracts/job-profitability/job-profitability.ts:116) needs no
--    change at all (see CONTRACT FIDELITY above).
--
-- 5. Call site needing the new third argument -- grepped `getJobProfitability(` repo-wide;
--    exactly one real (non-test) call site exists:
--      app/(tenant)/[tenantSlug]/operations/job-orders/[jobOrderId]/page.tsx:63
--      BEFORE: `profitabilitySnapshot = await getJobProfitability(supabase, jobOrder.id);`
--      AFTER:  `profitabilitySnapshot = await getJobProfitability(supabase, jobOrder.id, access.authUserId);`
--    `access.authUserId` is already resolved at the top of this same page (line 40,
--    `resolveOperationsAccessForRequest`) and is already threaded into a sibling call 22
--    lines below this one on the identical page
--    (line 85: `getTransactionLineage(supabase, { jobOrderId: jobOrder.id, actorAuthUserId: access.authUserId })`)
--    -- no new plumbing required, same value, same page, same request.
--
-- 6. server/queries/job-profitability.test.ts (both tests in the "getJobProfitability"
--    describe block, lines 36-89) mock a `.from`-based client today and will need updating to
--    the same `.rpc` mock shape this series' own sibling test files already use elsewhere
--    (call `getJobProfitability(client, JOB_ORDER_ID, ACTOR_ID)`, assert against
--    `rpc("get_job_profitability_directory", { p_job_order_id: JOB_ORDER_ID,
--    p_actor_auth_user_id: ACTOR_ID })`, and return `DIRECTORY_ROW` wrapped in an array from
--    the mock's `rpc()` rather than from a `.maybeSingle()` builder) -- not attempting this
--    rewrite here, per this task's SQL-only scope. ACTOR_ID (test file line 8) is already
--    declared as a fixture constant, unused by either existing test today -- it becomes the
--    new third argument.
