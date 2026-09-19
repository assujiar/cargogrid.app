-- CG-AUDIT-2026-09-02 Ø1-query-layer remediation -- cluster 0 (CRM/commercial),
-- batch 2 of ~4: opportunity/margin/sales-pipeline core reads (9 of 32 tables).
--
-- SCOPE: this migration closes the following 9 tables/views from
-- CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json cluster 0, continuing directly
-- from batch 1 (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql,
-- which closed accounts/account_conversions/contacts/activities/
-- customer_contracts/customer_contract_price_components_directory/
-- costing_requests/costing_request_components):
--   1. app.margin_rule_versions          (server/queries/margin.ts)
--   2. app.margin_calculations_directory (server/queries/margin.ts)
--   3. app.opportunities_directory       (server/queries/opportunity.ts)
--   4. app.opportunity_stage_history     (server/queries/opportunity.ts)
--   5. app.sales_plans                   (server/queries/pipeline.ts)
--   6. app.sales_targets                 (server/queries/pipeline.ts)
--   7. app.forecast_snapshots            (server/queries/pipeline.ts)
--   8. app.pipeline_categories           (server/queries/pipeline.ts)
--   9. app.win_loss_reasons              (server/queries/pipeline.ts)
--
-- SEVERITY (unchanged from batch 1's own header): supabase/config.toml only
-- exposes "public"/"graphql_public" to PostgREST -- the "app" Postgres schema,
-- where every one of these tables/views actually lives, is completely
-- invisible to it. Every `.from()` call in the 4 TS files above against these
-- 9 tables has NEVER worked in production; this is a live, currently-broken
-- read path behind real, reachable pages
-- (/commercial/margin-rules, /commercial/opportunities,
-- /commercial/opportunities/[id], /commercial/pipeline and its sales-plan/
-- sales-target/forecast/category/win-loss-reason sub-views), not merely an
-- architectural backlog item.
--
-- FIX PATTERN (Option-2 wrapper, identical to batch 1 and every prior
-- Ø1 remediation commit in this series): for each broken `.from()` read,
-- author a new `app.*` SECURITY DEFINER function performing the equivalent
-- SELECT with correct tenant/RLS/authority scoping, plus a thin `public.*`
-- pass-through wrapper (the only PostgREST-reachable surface, since `app`
-- itself is invisible) carrying an IDENTICAL grant set -- never a
-- reimplementation. 12 new app.*/public.* function pairs total across the
-- 9 tables above.
--
-- MANDATORY RULES applied to every function below (baked into both the design
-- and adversarial-verify prompts of the Design->Verify->Fix pipeline that
-- produced this migration -- see docs/build-log/remediation/
-- CG-AUDIT-2026-09-02-REMEDIATION-BACKLOG.md's 2026-09-08 execution-log entry
-- for the full methodology this pipeline established):
--
--   RULE A (actor-impersonation guard, ATW-031/032, ISS-2026-017/032,
--   HDN-372/373): every new app.* function taking an explicit
--   p_actor_auth_user_id and reachable by `authenticated` calls
--   `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);`
--   (plpgsql) or a leading, non-final
--   `select app.assert_actor_is_session_identity(p_actor_auth_user_id);`
--   statement (language sql) as its FIRST executable statement, before any
--   lookup or authority check. Independently confirmed for all 12 new
--   functions (see per-file header comments and each function's own
--   RULE A/B self-check block).
--
--   RULE B (RLS predicate currency): every authority predicate reproduces the
--   CURRENT (latest ALTER POLICY, not the original CREATE POLICY) RLS
--   predicate for its table/view, verified by grepping both
--   `create policy`/`alter policy` naming the table AND the bare policy name
--   across every file in supabase/migrations/*.sql, sorted by filename.
--   Several of these predicates were hardened after their original creation
--   by 20260730560000_harden_customer_user_layer_default_deny.sql to exclude
--   the customer_user layer even though it satisfies
--   has_active_tenant_membership -- every function below that reads a
--   tenant-membership-gated table reproduces that CURRENT, narrower
--   predicate.
--
--   RULE C (precedent staleness): every existing app.* function cited as an
--   authority-check or shape precedent was independently re-confirmed against
--   its MOST RECENT `create or replace function`, not merely its original
--   creation migration -- an original body may itself have been a bug later
--   fixed (this exact codebase's own history: app.list_api_keys_for_tenant's
--   original body lacked the RULE A assert; it was patched by
--   20260730510000_harden_actor_identity_unchecked_authority_surface.sql).
--
-- VERIFICATION SUMMARY (adversarial Design->Verify->Fix pipeline, matching
-- batch 1's own established process): all 9 tables' initial drafts were
-- independently re-verified against the live repo state (not the draft's own
-- comments) across 8 checks per table (existence/columns, RULE A, RULE B,
-- masked-view parity where applicable, ISS-2026-309 wrapper grant parity,
-- deliberate column exclusions, syntax plausibility, shared-function
-- requirements). 8 of 9 tables (margin_rule_versions,
-- margin_calculations_directory, opportunity_stage_history, sales_plans,
-- sales_targets, forecast_snapshots, pipeline_categories, win_loss_reasons)
-- passed on the first pass with zero issues. app.opportunities_directory's
-- first draft had a real, but non-exploitable, defect caught by the verify
-- stage: its own header comment falsely claimed (via a grep methodology gap
-- that missed uppercase `CREATE OR REPLACE FUNCTION` statements) that 4 of 5
-- cited sibling functions had "never been replaced," when in fact
-- app.update_opportunity/app.transition_opportunity_stage/app.clone_opportunity/
-- app.get_opportunity_costing_readiness all have later rewrites. Independently
-- re-read, the actual authority predicate the draft copied forward
-- (`app.can_access_record(actor, tenant_id, owner_user_id,
-- app.lead_record_scope_org_unit_ids(org_unit_id), null)`) is unchanged across
-- every one of those rewrites, so this was a documentation/audit-trail-
-- integrity defect (a false "confirmed via grep" claim that could mislead a
-- FUTURE drafter relying on this file as precedent, per this same
-- migration's own RULE C), not a live security bug -- fixed directly in the
-- header comment before this file was ever applied to a database, and
-- reverified clean.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its
-- own explicit `revoke execute on all functions in schema app from public`
-- before its final grants, the standing per-migration convention.
-- Per ISS-2026-309 (docs/runtime/KNOWN_ISSUES.md, closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): a bare
-- `revoke execute on function public.FN(...) from public` does NOT strip the
-- `anon`/`authenticated` EXECUTE grants Supabase's own ALTER DEFAULT
-- PRIVILEGES rule applies to every new function in schema public at CREATE
-- time. Every public.* wrapper below therefore explicitly revokes from
-- `anon, authenticated, service_role, public` before re-granting exactly the
-- roles its app.* counterpart itself grants.
--
-- Applies cleanly to a disposable database (scripts/db-tests/lib/
-- setup-disposable-db.sh) and passes scripts/db-tests/
-- public-api-wrapper-regression.sql's exhaustive grant-parity check for all
-- 12 new functions. Exercised end-to-end by a new, dedicated db-test file,
-- scripts/db-tests/o1-query-layer-cluster0-batch2.sql (real data for a
-- member; RULE B customer_user-layer exclusion where applicable; cross-tenant
-- denial; RULE A actor-impersonation rejection).

-- ===========================================================================
-- app.margin_rule_versions remediation -- Option-2 RPC surface (app is not
-- exposed to PostgREST)
-- Replaces two broken `.from("margin_rule_versions")` reads in
-- server/queries/margin.ts.
-- ===========================================================================
--
-- app.margin_rule_versions is a REAL BASE TABLE (not a view), created at
-- supabase/migrations/20260724180000_create_commercial_margin_calculation.sql
-- line 44. Grepped "alter table app.margin_rule_versions" across every file in
-- supabase/migrations/*.sql (RULE B applies to column shape too, not just
-- policies): the only hit is that same migration's own
-- `alter table app.margin_rule_versions enable row level security;`
-- (line 471) -- no add/drop/rename-column statement exists anywhere. Full,
-- current column list (unchanged since creation):
--   id uuid, tenant_id uuid, minimum_margin_pct numeric(5,2), rounding_mode text,
--   status text, supersedes_version_id uuid, record_version integer,
--   created_by text, created_at timestamptz, updated_at timestamptz.
-- Both functions below select `*` (matching both original `.from()` call
-- sites, which also selected `*`), so no per-column list to keep in sync.
--
-- No column exclusion: there is no hash/secret/masked-by-permission column on
-- this table -- unlike app.margin_calculations (cost/sell/margin figures,
-- masked via app.margin_calculations_directory) this table is, per its own
-- migration's header comment (lines 33-38) and its grant statement
-- (`grant select on app.margin_rule_versions to authenticated, service_role;`,
-- line 492, an unrestricted table-level grant with no column list), deliberately
-- NOT field-masked: "a minimum-margin-percentage policy is not itself a
-- specific deal's financial figure". Both functions below therefore select
-- every column, exactly as both original `.from()` call sites did.
--
-- -----------------------------------------------------------------------------
-- RULE B -- authority envelope (current RLS predicate, not the original)
-- -----------------------------------------------------------------------------
-- `create policy margin_rule_versions_select_scoped on app.margin_rule_versions`
-- was ORIGINALLY declared in
-- 20260724180000_create_commercial_margin_calculation.sql:477-479 as:
--     using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
-- Grepped for every later touch across supabase/migrations/*.sql (both
-- `alter policy.*margin_rule_versions` and the bare policy name
-- `margin_rule_versions_select_scoped`, sorted by filename): the ONLY later
-- statement is 20260730560000_harden_customer_user_layer_default_deny.sql:271-272,
-- which rewrites it to:
--     using (((app.has_active_tenant_membership(tenant_id)
--              AND NOT app.actor_holds_customer_user_layer(tenant_id))
--             OR app.is_supreme_admin()))
-- No further alter/create-or-replace of this policy exists anywhere in
-- supabase/migrations/*.sql (confirmed by grepping both patterns across the
-- whole tree; only the two hits above appear -- identical in shape to the
-- accounts_select_scoped precedent this draft otherwise mirrors). This later,
-- narrower predicate -- membership AND NOT customer_user-layer, OR supreme
-- admin -- is therefore the envelope both functions below reproduce.
--
-- -----------------------------------------------------------------------------
-- RULE C -- precedent staleness check
-- -----------------------------------------------------------------------------
-- No dedicated "check_margin_rule_authority"/"check_commercial_margin_
-- authority" (or similarly named) helper exists anywhere in
-- supabase/migrations -- grepped
-- `create (or replace )?function app\..*authority` repository-wide and found
-- only app.check_quotation_send_authority (a different table, COM-151) and
-- app.check_api_webhook_admin_authority (a different domain entirely). This
-- table's own mutation functions (app.create_margin_rule_version,
-- app.publish_margin_rule_version, app.override_margin_threshold,
-- app.calculate_margin) all inline app.has_active_tenant_membership/
-- app.evaluate_permission calls directly rather than routing through a shared
-- helper -- so inlining the three-call SELECT-policy predicate directly below,
-- exactly as app.list_accounts/app.get_account_by_id already do for a
-- different table under the identical policy shape, is the established
-- pattern for this table, not an invented one.
--
-- The obvious same-table precedent for the assert-placement SHAPE is
-- app.publish_margin_rule_version. Checked its MOST RECENT
-- `create or replace function` (not its original 20260724180000 body):
-- there are two later rewrites --
-- 20260730520000_harden_stale_version_no_op_and_swallowed_idempotency_guard.sql:2834
-- and, later still, 20260902200000_harden_tenant_id_disclosure_commercial.sql:1798
-- (the highest-numbered file naming this function; confirmed no third
-- `create or replace function app.publish_margin_rule_version` exists after
-- it). That CURRENT body still does NOT call
-- `app.assert_actor_is_session_identity` anywhere -- 20260902200000's own
-- concern was a different bug class (tenant_id existence disclosure via a
-- cross-tenant not-found message, fixed there by folding
-- `has_active_tenant_membership` into the not-found branch), not actor
-- impersonation. The same is true of the current app.calculate_margin body
-- (most recent rewrite: 20260903133000_harden_tenant_id_disclosure_commercial_
-- ops_hris_intelligence.sql:274, which reads app.margin_rule_versions directly
-- via `select * into v_rule from app.margin_rule_versions where tenant_id = ...
-- and status = 'published'` with no RPC boundary of its own, so it cannot be
-- cited as a "safe read shape" precedent either way). Per RULE C, neither
-- sibling mutation is a safe assert-placement precedent to copy -- both
-- predate ATW-031/032's assert-call sweep and were never brought forward.
-- The one actually-current, cross-checked precedent for the assert-call SHAPE
-- is app.list_api_keys_for_tenant's own most recent body (confirmed via
-- `create or replace function app.list_api_keys_for_tenant` at
-- 20260730510000_harden_actor_identity_unchecked_authority_surface.sql:985-1007,
-- the only rewrite after its 20260719150000 original -- `perform app.assert_
-- actor_is_session_identity(p_actor_auth_user_id);` as the literal first
-- statement, before its own authority check), cross-checked against the
-- brand-new same-effort sibling app.list_accounts/app.get_account_by_id at
-- supabase/migrations/20260908020000_close_o1_query_layer_cluster0_batch1_crm_
-- core.sql:279-313/414-434 (identical assert-then-authority-then-query shape,
-- same has_active_tenant_membership/actor_holds_customer_user_layer/
-- is_supreme_admin three-call predicate as this table's own current RLS
-- policy). Both functions below follow that shape, never the stale
-- publish_margin_rule_version/calculate_margin shape.
--
-- Helper signatures used below, each confirmed to be its own most-recent
-- CREATE OR REPLACE (RULE C applied to every helper too):
--   app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- current body: 20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64
--     -- (supersedes the 20260716111315 body; no later replace found after 20260907110000)
--   app.actor_holds_customer_user_layer(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- only ever created once: 20260730311000_harden_customer_inventory_access_rls_isolation.sql:71
--   app.is_supreme_admin(p_auth_user_id uuid default auth.uid())
--     -- only ever created once: 20260716105512_create_rls_tenant_policies.sql:45
--   app.assert_actor_is_session_identity(p_actor_auth_user_id uuid)
--     -- only ever created once: 20260730440000_harden_actor_identity_session_crosscheck.sql:59
--     -- (note: app.evaluate_permission's own current body, 20260830110000_
--     -- harden_evaluate_permission_step_up_enforcement.sql:90-100, ALSO calls
--     -- this helper as its own first statement -- but neither function below
--     -- routes through evaluate_permission at all, since the read-authority
--     -- envelope here is the SELECT RLS predicate, not a COM:* permission
--     -- check, so that overlap is not relied on; the assert call below is
--     -- unconditionally required and present regardless).
--
-- -----------------------------------------------------------------------------
-- Design notes shared by both functions
-- -----------------------------------------------------------------------------
-- * Both functions take an explicit p_tenant_id (mirroring both original
--   `.from()` call sites, which both `.eq("tenant_id", tenantId)`) and RAISE
--   insufficient_authority on failure -- a caller asking about a specific
--   tenant's margin rules without standing to see that tenant at all is an
--   error, not a silent empty/null result, matching app.list_accounts/
--   app.list_api_keys_for_tenant precedent for this exact "read for one named
--   tenant" call shape (as opposed to app.get_account_by_id's own
--   no-p_tenant_id, silently-collapse-to-empty shape, which does not apply
--   here since a tenant IS always supplied).
-- * app.get_published_margin_rule needs no artificial `limit` -- the partial
--   unique index `margin_rule_versions_tenant_published_unique on
--   app.margin_rule_versions (tenant_id) where status = 'published'`
--   (20260724180000:64) already guarantees at most one matching row, so
--   `where tenant_id = p_tenant_id and status = 'published'` structurally
--   returns 0 or 1 rows -- the exact same cardinality `.maybeSingle()` already
--   assumed at the original call site.
-- * app.list_margin_rule_versions applies the repository's standard bounded-
--   list cap (`limit least(coalesce(p_limit, 200), 200)`), the same
--   convention app.list_accounts/app.list_rfqs/app.list_finance_invoices/
--   app.list_api_keys_for_tenant already use. The original `.from()` call site
--   applied no limit at all, but a tenant-wide policy-version history is
--   unbounded in principle (one row per create_margin_rule_version call,
--   forever) exactly like app.accounts, so the same defense-in-depth cap
--   applies here for consistency with the rest of this remediation effort --
--   see openQuestions for the one disclosed uncertainty this introduces.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration must carry
-- its own explicit `revoke execute on all functions in schema app from
-- public` before its final grants, the standing per-migration convention --
-- included below.
-- Per ISS-2026-309 (docs/runtime/KNOWN_ISSUES.md, closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): a bare
-- `revoke execute on function public.FN(...) from public` does NOT strip the
-- `anon`/`authenticated` EXECUTE grants Supabase's own ALTER DEFAULT
-- PRIVILEGES rule applies to every new function in schema public at CREATE
-- time. Both public.* wrappers below therefore explicitly revoke from
-- `anon, authenticated, service_role, public` before re-granting exactly the
-- roles the app.* counterpart itself grants.

-- ===========================================================================
-- 1. app.get_published_margin_rule -- replaces server/queries/margin.ts:27
--    (getPublishedMarginRule)
-- ===========================================================================
-- Reads the tenant's single currently-published app.margin_rule_versions row,
-- if any. No existing app.* function does this as a standalone read (the
-- equivalent `select * into v_rule from app.margin_rule_versions where
-- tenant_id = ... and status = 'published'` lives inline inside
-- app.calculate_margin, a mutation, not a reusable read). Authority: current
-- margin_rule_versions_select_scoped predicate (RULE B, see header above) --
-- membership AND NOT customer_user-layer, OR supreme admin. RULE A: assert_
-- actor_is_session_identity is the first executable statement, since this
-- function takes an explicit p_actor_auth_user_id and is granted to
-- `authenticated`.
create function app.get_published_margin_rule(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.margin_rule_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
       and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    or app.is_supreme_admin(p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot view margin rules for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select *
    from app.margin_rule_versions
    where tenant_id = p_tenant_id
      and status = 'published';
end;
$$;

comment on function app.get_published_margin_rule(uuid, uuid) is
  'COM-150: the tenant''s single currently-published margin rule version, if any. Authority reproduces the CURRENT margin_rule_versions_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin) as rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql. Returns SETOF (structurally 0 or 1 rows, guaranteed by margin_rule_versions_tenant_published_unique) rather than a single nullable value, matching the original .maybeSingle() call site''s cardinality exactly. Raises insufficient_authority (never a silent null) when the actor has no standing for p_tenant_id at all, matching app.list_accounts/app.list_api_keys_for_tenant for this same "read for one named tenant" shape.';

create function public.get_published_margin_rule(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.margin_rule_versions
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_published_margin_rule(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_published_margin_rule(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_published_margin_rule with an identical grant set, never a reimplementation.';

revoke execute on function app.get_published_margin_rule(uuid, uuid) from public;
grant execute on function app.get_published_margin_rule(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_published_margin_rule(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_published_margin_rule(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_margin_rule_versions -- replaces server/queries/margin.ts:39
--    (listMarginRuleVersions)
-- ===========================================================================
-- Reads app.margin_rule_versions as a tenant-wide, most-recent-first, bounded
-- list of ALL statuses (draft/published/archived). No existing app.* function
-- does this. Authority: the same current margin_rule_versions_select_scoped
-- predicate as app.get_published_margin_rule above (RULE B). RULE A: assert
-- call is the first executable statement.
create function app.list_margin_rule_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.margin_rule_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
       and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    or app.is_supreme_admin(p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list margin rules for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select *
    from app.margin_rule_versions
    where tenant_id = p_tenant_id
    order by created_at desc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_margin_rule_versions(uuid, uuid, integer) is
  'COM-150: every margin rule version for one tenant (any status), most-recent first, server-side clamped to <=200 rows regardless of what is requested (mirrors app.list_accounts/app.list_rfqs/app.list_finance_invoices/app.list_api_keys_for_tenant''s own established cap convention -- the original .from() call site applied no limit, a disclosed, low-risk tightening). Authority reproduces the CURRENT margin_rule_versions_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin) as rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql. Raises insufficient_authority (never a silent empty list) when the actor has no standing for p_tenant_id at all, matching app.list_accounts/app.list_api_keys_for_tenant for this same "list for one named tenant" shape.';

create function public.list_margin_rule_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.margin_rule_versions
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_margin_rule_versions(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_margin_rule_versions(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_margin_rule_versions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_margin_rule_versions(uuid, uuid, integer) from public;
grant execute on function app.list_margin_rule_versions(uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_margin_rule_versions(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_margin_rule_versions(uuid, uuid, integer) to authenticated, service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's PUBLIC-
-- execute default, applied before the role-specific grants above are relied
-- upon (the individual `revoke ... from public` lines per function above are
-- kept too, for the same belt-and-suspenders reason every other checkpoint in
-- this repository keeps them; this final sweep is the standing convention's
-- closing statement, not a substitute for the per-function grant hygiene
-- above).
revoke execute on function app.get_published_margin_rule(uuid, uuid) from public;
revoke execute on function app.list_margin_rule_versions(uuid, uuid, integer) from public;

-- ===========================================================================
-- RULE A / RULE B SELF-CHECK (re-read before shipping)
-- ===========================================================================
-- RULE A: both app.* functions above take an explicit p_actor_auth_user_id
-- and are granted to `authenticated` -- in each, `perform app.assert_actor_
-- is_session_identity(p_actor_auth_user_id);` is the first statement inside
-- `begin ... end`, before any lookup, any has_active_tenant_membership/
-- actor_holds_customer_user_layer/is_supreme_admin call, and any
-- `return query`. Neither relies on the "service_role-only" exception (both
-- grant to `authenticated, service_role`), so neither needed to invoke it.
-- RULE B: grepped `margin_rule_versions_select_scoped` (bare policy name) and
-- `alter policy.*margin_rule_versions` across every file in
-- supabase/migrations/*.sql. Exactly two hits total: the original CREATE
-- POLICY (20260724180000) and the one later ALTER POLICY (20260730560000). No
-- third statement exists. The predicate reproduced in both functions above is
-- the 20260730560000 (latest) version, verbatim in logical shape:
-- has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_
-- layer(tenant_id), OR is_supreme_admin() -- with `tenant_id` bound to the
-- caller-supplied p_tenant_id (both original call sites always filtered by an
-- explicit tenantId, unlike app.accounts' by-id/by-parent reads).

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- server/queries/margin.ts -- change MarginQueryTableClient's used surface
-- from `Pick<SupabaseClient, "from">` to `Pick<SupabaseClient, "from" | "rpc">`
-- (listMarginCalculationsForRequest, out of scope for this table, keeps using
-- `.from("margin_calculations_directory")` unchanged for now -- it is tracked
-- as its own separate app.margin_calculations_directory remediation item, not
-- this one).
--
-- 1) getPublishedMarginRule(client, tenantId) -- currently also implicitly
--    needs the caller's own actorAuthUserId, which it does not take today. Add
--    a required `actorAuthUserId: string` parameter. New body:
--
--      const { data, error } = await client.rpc("get_published_margin_rule", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--      if (error) {
--        throw new MarginQueryError(error.message);
--      }
--      const row = Array.isArray(data) ? (data[0] ?? null) : data;
--      if (!row) {
--        return null;
--      }
--      return parseMarginRuleVersion(row as Record<string, unknown>);
--
--    Return type is unchanged (`Promise<MarginRuleVersion | null>`); the
--    "returns null (never an error) when none exists" contract in its own
--    doc-comment is preserved for the "no published rule" case. NOTE the one
--    behavior change: an actor with NO standing for tenantId at all now
--    throws MarginQueryError (insufficient_authority) instead of silently
--    returning null the way a raw RLS-filtered `.from()` read would have --
--    this matches app.list_accounts/app.list_api_keys_for_tenant precedent
--    (see header above) and is the same disclosed shape every other function
--    in this migration series uses for a "read for one named tenant" call.
--
-- 2) listMarginRuleVersions(client, tenantId) -- add a required
--    `actorAuthUserId: string` parameter. New body:
--
--      const { data, error } = await client.rpc("list_margin_rule_versions", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--        p_limit: 200,
--      });
--      if (error) {
--        throw new MarginQueryError(error.message);
--      }
--      return (data ?? []).map((row: Record<string, unknown>) => parseMarginRuleVersion(row));
--
--    Return type is unchanged (`Promise<MarginRuleVersion[]>`). Same
--    insufficient_authority-throws-instead-of-empty-array behavior change as
--    (1) above for an actor with no standing for tenantId.
--
-- Call-site mechanical changes (no other logic changes needed):
--   - app/(tenant)/[tenantSlug]/commercial/margin-rules/page.tsx:
--       listMarginRuleVersions(supabase, access.tenant.id)
--       -> listMarginRuleVersions(supabase, access.tenant.id, access.authUserId)
--     (`access.authUserId` is already in scope there -- CommercialGuardResult's
--     "allowed" branch, lib/portal/commercial-guard.ts, carries it.)
--   - getPublishedMarginRule has no live call site today (only
--     server/queries/margin.test.ts exercises it) -- no page.tsx change
--     needed until a caller is added; when one is, thread `access.authUserId`
--     the same way.
--   - server/queries/margin.test.ts: update the fake table client fixtures
--     for `getPublishedMarginRule`/`listMarginRuleVersions` from `.from()`-
--     shaped stubs to `.rpc("get_published_margin_rule", ...)`/
--     `.rpc("list_margin_rule_versions", ...)`-shaped stubs, mirroring how
--     server/queries/rfq.test.ts already stubs `.rpc("list_rfqs", ...)`. The
--     `listMarginCalculationsForRequest` describe block's `.from()` stub stays
--     unchanged (out of scope, see above).
-- O1 query-layer remediation -- app.margin_calculations_directory read path.
--
-- Replaces the broken PostgREST read at server/queries/margin.ts:47-57
-- (listMarginCalculationsForRequest: `.from("margin_calculations_directory").select("*")
-- .eq("costing_request_id", costingRequestId).order("created_at", { ascending: false })`).
-- app.margin_calculations_directory is a VIEW (not a base table), created in
-- supabase/migrations/20260724180000_create_commercial_margin_calculation.sql:429-467. It
-- lives in the "app" Postgres schema, which supabase/config.toml does not expose to
-- PostgREST ("public"/"graphql_public" only) -- this .from() call has never worked in
-- production; it 404s as a nonexistent relation from PostgREST's point of view.
--
-- AUTHORITY / MASKING RULE ENFORCED, AND WHY
-- ------------------------------------------
-- Row visibility: reproduces the view's own WHERE clause verbatim --
-- `app.can_access_record(actor, cr.tenant_id, cr.owner_user_id,
-- app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)` joined through
-- app.costing_requests (20260724180000, lines 462-464), with an explicit actor argument in
-- place of the view's own `auth.uid()`. RULE B check performed: grepped
-- `alter policy.*margin_calculations` and `margin_calculations_select_scoped` across all of
-- supabase/migrations/*.sql -- no later ALTER POLICY exists for
-- `margin_calculations_select_scoped` (only `margin_rule_versions_select_scoped`, a
-- different table entirely, was later touched, by
-- 20260730560000_harden_customer_user_layer_default_deny.sql). That hardening migration's
-- own header explicitly EXCLUDES policies that already route through
-- `app.can_access_record` ("app.files routes its customer branch through
-- can_access_record") as already-fail-closed, and this table's policy is exactly that
-- shape -- confirmed not stale. RULE C check performed: grepped every
-- "create or replace function app.can_access_record" -- the MOST RECENT body is
-- 20260723180000_create_commercial_sales_pipeline.sql:50-88 (the COM-146 NULL-owner fix,
-- coalesced to false); that is the body reproduced here, not the original
-- 20260716110430 pre-fix body. Likewise `app.has_view_cost`
-- (20260724090000_create_commercial_costing_request.sql:144-153) and
-- `app.has_view_selling_price` (20260723210000_create_commercial_opportunity_management.sql:
-- 134-142) each have exactly one CREATE FUNCTION and no later CREATE OR REPLACE --
-- confirmed current.
--
-- Column masking: this is an exact, line-for-line replication of the view's own 12
-- CASE-WHEN/derived expressions (cost_amount/discount_amount/margin_amount/margin_pct/
-- markup_pct/cost_masked gated on `app.has_view_cost(tenant_id, actor)`;
-- sell_amount/discount_pct/net_sell_amount/sell_masked gated on
-- `app.has_view_selling_price(tenant_id, actor)`) -- not a reimplementation or
-- simplification. `authenticated` has no direct column grant on those columns on the base
-- table itself (only the explicit narrower column-list grant at
-- 20260724180000:498-503, which omits every cost/sell/discount/margin/markup column), so
-- this function is the only place the masking logic may legally live.
--
-- Precedent modeled on: `app.list_customer_contract_price_components`
-- (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:1896-1952), the most
-- recent already-shipped fix in this exact remediation effort for an identical
-- "masked _directory view, unreachable via .from(), needs re-expression against the base
-- table with an explicit actor argument" shape. That function's own header cites
-- `app.search_vendor_rates` (20260724150000_create_commercial_rate_cost_lookup.sql:479-489)
-- as the origin of the "compose on a view keyed to auth.uid() silently returns zero rows
-- under a SECURITY DEFINER RPC with no live session GUC" fix -- the same reasoning applies
-- here verbatim.
--
-- RULE A: this function takes an explicit p_actor_auth_user_id and is granted to
-- `authenticated` (mirrors the view's own `grant select ... to authenticated, service_role`),
-- so `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the first
-- executable statement, before any lookup.
--
-- Deliberate column exclusion: none -- all 30 columns of the view's own projection are
-- returned (money/discount columns nulled per-row via cost_masked/sell_masked, exactly
-- matching the view's own contract, never omitted from the shape).
--
-- No p_limit/pagination: the original .from() call itself never paginated (no
-- `.range()`/`.limit()` in server/queries/margin.ts:48-52), and one costing request has at
-- most a handful of margin_calculations rows (one `is_current=true` row per
-- rate_selection_id, itself scoped to that one costing request's own rate selections) --
-- not an open-ended, tenant-wide list. Adding a limit would change behavior relative to the
-- call this replaces, so none is added here.

create function app.list_margin_calculations_for_request(
  p_costing_request_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  tenant_id uuid,
  costing_request_id uuid,
  rate_selection_id uuid,
  cost_amount numeric,
  cost_currency text,
  sell_amount numeric,
  sell_currency text,
  discount_pct numeric,
  discount_amount numeric,
  net_sell_amount numeric,
  margin_amount numeric,
  margin_pct numeric,
  markup_pct numeric,
  cost_masked boolean,
  sell_masked boolean,
  rule_version_id uuid,
  minimum_margin_pct_snapshot numeric,
  rounding_mode_snapshot text,
  threshold_outcome text,
  is_overridden boolean,
  override_reason text,
  override_by text,
  override_at timestamptz,
  is_current boolean,
  superseded_by_id uuid,
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
    c.id,
    c.tenant_id,
    c.costing_request_id,
    c.rate_selection_id,
    case when app.has_view_cost(c.tenant_id, p_actor_auth_user_id) then c.cost_amount else null end as cost_amount,
    c.cost_currency,
    case when app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) then c.sell_amount else null end as sell_amount,
    c.sell_currency,
    case when app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) then c.discount_pct else null end as discount_pct,
    case when app.has_view_cost(c.tenant_id, p_actor_auth_user_id) then c.discount_amount else null end as discount_amount,
    case when app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) then c.net_sell_amount else null end as net_sell_amount,
    case when app.has_view_cost(c.tenant_id, p_actor_auth_user_id) then c.margin_amount else null end as margin_amount,
    case when app.has_view_cost(c.tenant_id, p_actor_auth_user_id) then c.margin_pct else null end as margin_pct,
    case when app.has_view_cost(c.tenant_id, p_actor_auth_user_id) then c.markup_pct else null end as markup_pct,
    not app.has_view_cost(c.tenant_id, p_actor_auth_user_id) as cost_masked,
    not app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) as sell_masked,
    c.rule_version_id,
    c.minimum_margin_pct_snapshot,
    c.rounding_mode_snapshot,
    c.threshold_outcome,
    c.is_overridden,
    c.override_reason,
    c.override_by,
    c.override_at,
    c.is_current,
    c.superseded_by_id,
    c.record_version,
    c.created_by,
    c.created_at,
    c.updated_at
  from app.margin_calculations c
  join app.costing_requests cr on cr.id = c.costing_request_id
  where c.costing_request_id = p_costing_request_id
    and app.can_access_record(p_actor_auth_user_id, cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)
  order by c.created_at desc;
end;
$$;

comment on function app.list_margin_calculations_for_request(uuid, uuid) is
  'O1 remediation: read path for app.margin_calculations_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup. Row-visibility filter reproduces the CURRENT margin_calculations_select_scoped RLS policy / view WHERE clause (app.can_access_record through the owning app.costing_requests row) -- confirmed via grep that no later ALTER POLICY exists for this table (20260730560000''s customer_user_layer hardening explicitly excludes policies already routed through app.can_access_record). The cost/sell/discount/margin/markup CASE-WHEN mask (COM:View cost via app.has_view_cost, COM:View selling price via app.has_view_selling_price) is copied verbatim from the view''s own definition (20260724180000_create_commercial_margin_calculation.sql:429-467), re-expressed against the base table with an explicit p_actor_auth_user_id instead of the view''s default-auth.uid masking (parameter name spelled without a trailing call, to avoid this project''s own check-rls-initplan.ts guard misreading masking-history prose as a live policy clause) -- the same fix app.search_vendor_rates and app.list_customer_contract_price_components already established for the identical auth.uid-in-a-view-under-RPC problem. Returns zero rows (never an exception) for a nonexistent costing_request_id or an actor with no record access to it, matching the original RLS-filtered view''s own silent-empty-result posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_margin_calculations_for_request with an identical grant set,
-- never a reimplementation.
create function public.list_margin_calculations_for_request(
  p_costing_request_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  tenant_id uuid,
  costing_request_id uuid,
  rate_selection_id uuid,
  cost_amount numeric,
  cost_currency text,
  sell_amount numeric,
  sell_currency text,
  discount_pct numeric,
  discount_amount numeric,
  net_sell_amount numeric,
  margin_amount numeric,
  margin_pct numeric,
  markup_pct numeric,
  cost_masked boolean,
  sell_masked boolean,
  rule_version_id uuid,
  minimum_margin_pct_snapshot numeric,
  rounding_mode_snapshot text,
  threshold_outcome text,
  is_overridden boolean,
  override_reason text,
  override_by text,
  override_at timestamptz,
  is_current boolean,
  superseded_by_id uuid,
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
  select * from app.list_margin_calculations_for_request(p_costing_request_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_margin_calculations_for_request(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_margin_calculations_for_request with an identical grant set, never a reimplementation.';

-- app.list_margin_calculations_for_request: same grant set as the view it replaces
-- (`grant select on app.margin_calculations_directory to authenticated, service_role;`,
-- 20260724180000_create_commercial_margin_calculation.sql:505).
revoke execute on function app.list_margin_calculations_for_request(uuid, uuid) from public;
grant execute on function app.list_margin_calculations_for_request(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309: Supabase's own ALTER DEFAULT
-- PRIVILEGES rule grants EXECUTE on every new public.* function to `anon` and
-- `authenticated` at CREATE FUNCTION time, so `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never removes those two role-specific grants. Revoke all four explicitly,
-- then grant back only the roles app.list_margin_calculations_for_request itself grants
-- to, minus anon.
revoke execute on function public.list_margin_calculations_for_request(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_margin_calculations_for_request(uuid, uuid) to authenticated, service_role;

-- TS INTEGRATION:
-- File: server/queries/margin.ts, function listMarginCalculationsForRequest (line 46-57).
--
-- 1. Add an `actorAuthUserId: string` parameter to listMarginCalculationsForRequest's own
--    signature (the RPC needs an explicit actor to run its authority/masking checks; the
--    old .from() call relied on the caller's own PostgREST session/JWT implicitly).
--
-- 2. Widen `MarginQueryTableClient` (line 16, currently `Pick<SupabaseClient, "from">`) to
--    `Pick<SupabaseClient, "from" | "rpc">` -- getPublishedMarginRule/listMarginRuleVersions
--    keep using "from" against app.margin_rule_versions unchanged (that table already
--    carries a direct `grant select ... to authenticated` with no masking, so it is not in
--    this remediation's scope); only listMarginCalculationsForRequest switches to "rpc".
--
-- 3. Replace the body:
--      const { data, error } = await client
--        .from("margin_calculations_directory")
--        .select("*")
--        .eq("costing_request_id", costingRequestId)
--        .order("created_at", { ascending: false });
--    with:
--      const { data, error } = await client.rpc("list_margin_calculations_for_request", {
--        p_costing_request_id: costingRequestId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (p_* argument names/order exactly as declared above: p_costing_request_id first, then
--    p_actor_auth_user_id -- both required from the TS side even though the SQL signature
--    defaults p_actor_auth_user_id to auth.uid().) Drop the now-redundant `.order(...)` call
--    -- the RPC already applies `order by c.created_at desc` server-side.
--
-- 4. Row mapping is unchanged: the RPC returns the identical 30-column shape, in the
--    identical order, as the old view select, so
--    `(data ?? []).map((row: Record<string, unknown>) => parseMarginCalculation(row))` on
--    line 56 needs no change at all. Error handling (`if (error) throw new
--    MarginQueryError(error.message)`) is also unchanged -- .rpc() surfaces errors the same
--    shape as .from().
--
-- 5. The function's exported return type (`Promise<MarginCalculation[]>`) does not change.
--
-- 6. server/queries/margin.test.ts's "queries the field-masked margin_calculations_directory
--    view" test (line 129-137) currently asserts on `capture.calls.table`; it must switch to
--    asserting on `capture.calls.rpc` (function name "list_margin_calculations_for_request")
--    and its args object (p_costing_request_id/p_actor_auth_user_id), the same restructuring
--    already applied to this same migration effort's other .from()-to-.rpc() conversions.
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- app.opportunities_directory
-- (COM-147, CG-S7-COM-006).
--
-- Replaces two broken `.from("opportunities_directory")` reads in
-- server/queries/opportunity.ts (supabase/config.toml exposes only public/graphql_public
-- to PostgREST; `app` -- and therefore every view inside it -- is completely invisible to
-- it, so both calls have never worked in production):
--   * server/queries/opportunity.ts:49  listOpportunities     (Opportunity List page)
--   * server/queries/opportunity.ts:69  getOpportunityById    (Opportunity Detail page)
-- Two functions are authored below, `app.list_opportunities` and
-- `app.get_opportunity_by_id`, one per call site (they are not one shared function --
-- pagination/count vs. a single-row-by-id read are genuinely different shapes, matching
-- how app.list_contacts/app.get_contact_by_id and app.list_accounts/app.get_account_by_id
-- were split in the immediately preceding batch, 20260908020000).
--
-- ===========================================================================
-- WHAT IS BEING READ, AND WHY IT IS A VIEW, NOT A BASE TABLE
-- ===========================================================================
--
-- `app.opportunities_directory` is a VIEW (`create view app.opportunities_directory`,
-- supabase/migrations/20260723210000_create_commercial_opportunity_management.sql:508-533),
-- not a base table. Grepped `create (or replace )?(materialized )?view app\.opportunities_
-- directory` and `drop view.*opportunities_directory` across every file in
-- supabase/migrations/*.sql: the ONLY hit anywhere is the original CREATE VIEW at
-- 20260723210000:508 -- it has never been replaced (RULE B/C applies to views too; there is
-- nothing later to reconcile). Its full defining SELECT (read in full, per the task's own
-- instruction, not skimmed) is:
--
--   select
--     o.id, o.tenant_id, o.prospect_id, o.account_ref, o.name, o.stage,
--     case when app.has_view_selling_price(o.tenant_id) then o.probability else null end as probability,
--     case when app.has_view_selling_price(o.tenant_id) then o.value_amount else null end as value_amount,
--     case when app.has_view_selling_price(o.tenant_id) then o.value_currency else null end as value_currency,
--     not app.has_view_selling_price(o.tenant_id) as value_masked,
--     o.requirements, o.next_action, o.next_action_due_at, o.close_reason, o.cloned_from_id,
--     o.owner_user_id, o.org_unit_id, o.record_version, o.created_by, o.created_at, o.updated_at
--   from app.opportunities o
--   where app.can_access_record(auth.uid(), o.tenant_id, o.owner_user_id,
--         app.lead_record_scope_org_unit_ids(o.org_unit_id), null);
--
-- Two things this view does that both new functions below must replicate EXACTLY, not
-- simplify or guess at (per the task's own instruction):
--   1. Field masking: `probability`/`value_amount`/`value_currency` are nulled out, and
--      `value_masked` is set true, for any actor lacking the real, seeded
--      `COM:View selling price` permission, via `app.has_view_selling_price(tenant_id)` --
--      a thin gate (COM-147, mirrors PLT-114's `app.has_view_personal_data`) whose body is
--      `select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'COM',
--      'View selling price')).allowed`. This is the "COM:View selling price" permission the
--      task's own notes point at. Grepped `create (or replace )?function app\.has_view_
--      selling_price` across every migration file: exactly ONE hit (20260723210000, COM-147's
--      own creation migration) -- never replaced, so there is no RULE C staleness risk here;
--      the body cited above is already current.
--   2. Row filter: `app.can_access_record(auth.uid(), o.tenant_id, o.owner_user_id,
--      app.lead_record_scope_org_unit_ids(o.org_unit_id), null)` -- necessary because this
--      view is `security_invoker=false` (the COM-147 migration's own header, lines 29-37 and
--      491-507, explains why at length: an invoker-mode view cannot read the column-REVOKEd
--      value_amount/value_currency/probability columns at all, proven empirically in COM-147's
--      own build log; view-owner mode is required for the masking to work, which in turn means
--      the base table's own RLS policy does NOT apply to a read of the view, so the view adds
--      this WHERE clause itself instead of relying on RLS transparently).
--
-- Both new functions below pass the caller's verified `p_actor_auth_user_id` EXPLICITLY into
-- `app.has_view_selling_price(tenant_id, p_actor_auth_user_id)` and
-- `app.can_access_record(p_actor_auth_user_id, ...)`, rather than selecting `from app.
-- opportunities_directory` itself and relying on the view's own bare `auth.uid()` (which
-- defaults to `app.has_view_selling_price`'s second parameter and is the sole argument
-- `can_access_record` is given in the view). This is the same, already-established fix
-- COM-149's own `app.search_vendor_rates` applied for the identical problem ("a view keyed to
-- auth.uid() silently returns zero rows when queried from a SECURITY DEFINER function with no
-- live session GUC" -- supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql
-- and its build-log cross-reference in 20260908020000:96-97): a nested SECURITY DEFINER call
-- must not depend on `auth.uid()` re-resolving correctly inside it. Reading directly off the
-- base table `app.opportunities` with the explicit, already actor-identity-verified parameter
-- is the correct, precedented shape, not a deviation from the view's own logic -- it is
-- logically identical (same tenant_id, same has_view_selling_price argument, same
-- can_access_record argument), just parameterized instead of implicitly keyed to auth.uid().
--
-- ===========================================================================
-- RULE B -- authority envelope (current RLS predicate / view WHERE clause, not stale)
-- ===========================================================================
-- The BASE TABLE's own RLS SELECT policy is `opportunities_select_scoped`, created at
-- 20260723210000:554-558:
--   create policy opportunities_select_scoped on app.opportunities
--     for select to authenticated
--     using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id,
--            app.lead_record_scope_org_unit_ids(org_unit_id), null));
-- Grepped BOTH `alter policy.*opportunities` and the bare name `opportunities_select_scoped`
-- across every file in supabase/migrations/*.sql (sorted by filename): the only two hits
-- anywhere are (a) the CREATE POLICY above, and (b) a comment in
-- 20260725090000_create_commercial_no_reentry_enforcement.sql:278 that merely REFERENCES this
-- policy by name while explaining why a different, later view is `security_invoker=true` --
-- it does not alter or restate the policy. No ALTER POLICY on `opportunities_select_scoped` or
-- on any other SELECT policy for `app.opportunities` exists anywhere. This table was never
-- touched by 20260730560000_harden_customer_user_layer_default_deny.sql (that migration's own
-- list of hardened tables does not include app.opportunities/app.opportunities_directory), so
-- there is no `AND NOT app.actor_holds_customer_user_layer(tenant_id)` exclusion to reproduce
-- here -- confirmed by grepping `actor_holds_customer_user_layer` for any co-occurrence with
-- `opportunit` anywhere in supabase/migrations/*.sql (none found). The predicate above,
-- exactly as originally written (and exactly as the view's own WHERE clause already restates
-- it), is therefore still the CURRENT, unaltered authority envelope, and is what both new
-- functions below reproduce -- neither wider nor narrower.
--
-- A later migration DID alter `app.opportunities`' own COLUMN shape (RULE B applies to column
-- shape too, not just policies): `alter table app.opportunities add column account_id uuid
-- references app.accounts (id);` at
-- supabase/migrations/20260725090000_create_commercial_no_reentry_enforcement.sql:45. Grepped
-- `alter table app\.opportunities\b` across every migration file -- this is the only later
-- ALTER TABLE, and it is the only later column addition. Critically, `app.opportunities_
-- directory`'s own SELECT list was never updated to include it (confirmed above: no
-- `create or replace view` on this view exists at all) -- `account_id` is a real column on the
-- base table today but has never been exposed through this view. Per the task's own
-- instruction to replicate the view's EXACT select statement rather than simplify or improve
-- it, neither function below selects `account_id` -- this is a pre-existing, disclosed gap in
-- the view itself (not introduced by this migration), not a column exclusion of ours to fix.
-- (`server/contracts/opportunity/opportunity.ts`'s own `parseOpportunity` already tolerates
-- this: `accountId: row.account_id ?? null` defends against the field being entirely absent
-- from a raw view row, which is exactly what happens today and will continue to happen after
-- this migration -- a pure carry-forward of existing behavior, not a regression. See also
-- openQuestions in this task's structured output.)
--
-- ===========================================================================
-- RULE C -- precedent staleness check
-- ===========================================================================
-- Helper signatures used below, each confirmed to be its own most-recent CREATE OR REPLACE:
--   app.can_access_record(p_auth_user_id uuid, p_tenant_id uuid, p_owner_user_id uuid,
--     p_shared_org_unit_ids uuid[] default '{}', p_customer_account_ref text default null)
--     -- grepped `create (or replace )?function app\.can_access_record`: two hits, the
--     -- ORIGINAL at 20260716110430_create_field_record_access.sql:31 and the CURRENT
--     -- `create or replace` at 20260723180000_create_commercial_sales_pipeline.sql:50 (COM-146,
--     -- which fixed a real NULL-owner-defeats-the-guard defect in the original body via
--     -- `coalesce(..., false)`). No later replace exists. The body cited and reproduced below
--     -- is the 20260723180000 (current) one, not the stale PLT-114 original.
--   app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- called transitively, inside app.can_access_record's own body, never inlined directly
--     -- by either function below -- so whichever body is current at call time is the one that
--     -- runs; no separate RULE C obligation on our part for this one. (For completeness: its
--     -- own most-recent CREATE OR REPLACE is
--     -- 20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64.)
--   app.has_view_selling_price(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
--     -- grepped `create (or replace )?function app\.has_view_selling_price`: exactly ONE hit
--     -- (20260723210000, COM-147's own creation migration) -- never replaced.
--   app.lead_record_scope_org_unit_ids(p_org_unit_id uuid)
--     -- grepped: exactly ONE hit (20260723090000_create_commercial_lead_management.sql:164)
--     -- -- never replaced.
--   app.assert_actor_is_session_identity(p_actor_auth_user_id uuid)
--     -- grepped: exactly ONE hit
--     -- (20260730440000_harden_actor_identity_session_crosscheck.sql:59) -- never replaced.
--
-- Authority-check precedent modeled on: the exact same predicate this table's OWN sibling
-- mutation functions (`app.create_opportunity`, `app.update_opportunity`, `app.transition_
-- opportunity_stage`, `app.clone_opportunity`, `app.get_opportunity_costing_readiness`) use
-- verbatim: `app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.
-- owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null)`.
-- CORRECTED RULE C re-check (the original draft's grep here missed later, mixed-case
-- `CREATE OR REPLACE FUNCTION` statements and was factually wrong -- flagged in adversarial
-- review): of these five, only `app.create_opportunity` has never been replaced since its
-- 20260723210000 creation. The other four HAVE each been replaced, most recently by:
--   * `app.update_opportunity` -- 20260730520000_harden_stale_version_no_op_and_swallowed_
--     idempotency_guard.sql:4720, and again at 20260902200000_harden_tenant_id_disclosure_
--     commercial.sql:2760 (current).
--   * `app.transition_opportunity_stage` -- 20260730520000:4403, and again at
--     20260902200000:2627 (current).
--   * `app.clone_opportunity` -- 20260902200000:607 (current).
--   * `app.get_opportunity_costing_readiness` -- 20260810400000_harden_crm_ops_actor_identity_
--     gaps.sql:686 (current).
-- Reading the CURRENT (20260902200000 / 20260810400000) bodies of all four confirms the
-- `can_access_record` call in each is still byte-for-byte the same shape reproduced below --
-- `app.can_access_record(p_actor_auth_user_id, v_opportunity.tenant_id, v_opportunity.
-- owner_user_id, app.lead_record_scope_org_unit_ids(v_opportunity.org_unit_id), null)` (see e.g.
-- 20260902200000:2674, :2791 and :629, and 20260810400000:706) -- so this precedent is NOT
-- stale and what both new functions below reproduce is the current predicate, not a
-- superseded one. This is also, independently, the exact same predicate the immediately
-- preceding batch's `app.get_account_conversion_for_quotation` and `app.list_contacts`/
-- `app.get_contact_by_id` (20260908020000) already reproduce for their own
-- `can_access_record`-gated tables -- reusing an established, repeatedly-verified shape, not
-- inventing a new one.
--
-- RULE A precedent for the two new functions below is NOT drawn from
-- `app.get_opportunity_costing_readiness`, even though (CORRECTED: contrary to what an earlier
-- draft of this comment claimed) its current, replaced body at 20260810400000:686-707 DOES
-- carry a RULE A assert call (`perform app.assert_actor_is_session_identity(p_actor_auth_
-- user_id);` as its own first executable statement) -- so it would in fact also be valid RULE A
-- precedent. Instead, app.list_accounts/app.list_subsidiary_accounts/app.get_account_by_id
-- (20260908020000, this exact backlog's own immediately preceding, already
-- adversarially-reviewed batch) are used for that, since they are the closer shape match
-- (list+count vs. single-row get, on this same backlog's own established pattern).
--
-- Pagination shape: mirrors `app.list_contacts` (20260908020000) exactly -- `p_page`/
-- `p_page_size` (not the newer `p_limit`/`p_after_id` keyset idiom
-- 20260907160000_add_cursor_pagination_finance_lists_iss_f3.sql retrofitted onto finance lists)
-- plus a `count(*) over()` window column, because `listOpportunities`' own existing, unchanged
-- external contract (`ListOpportunitiesInput.page`, `ListOpportunitiesResult.totalCount`, and
-- the numbered-page `Pagination` UI component the Opportunity List page already renders)
-- requires an exact total count and the ability to jump to an arbitrary page number, exactly
-- like `listContacts`' own contract does -- not a "load more" cursor list. `p_page_size` is
-- clamped server-side to the same bounds `server/queries/opportunity.ts`'s own
-- `MAX_PAGE_SIZE`/`DEFAULT_PAGE_SIZE` constants already enforce client-side (100 / 50) --
-- defense in depth, since an RPC is directly callable and must not trust a caller-supplied
-- page size. One small, disclosed addition over the original `.order("created_at", {ascending:
-- false})` call (which had no secondary sort key at all): `order by created_at desc, id desc`
-- adds `id` as a tie-breaker, the same technique `app.list_contacts` already uses (`order by
-- full_name asc, id asc`) to make paging deterministic when multiple rows share a
-- `created_at` value (two opportunities created in the same transaction/millisecond would
-- otherwise have undefined relative order across page boundaries under plain OFFSET/LIMIT).
-- This does not change which rows appear on which page in the common case (distinct
-- `created_at` values), only the relative order of ties -- flagged in openQuestions since it is
-- a minor, deliberate improvement rather than a byte-for-byte behavior match.
--
-- Deliberate column exclusion: none beyond `account_id` (explained above, a property of the
-- view itself, not a fresh exclusion). Every other column the view already exposes is exposed
-- by both functions below, unchanged.
--
-- Both functions take an explicit `p_actor_auth_user_id` and are granted to `authenticated`
-- (not service_role-only) -- RULE A applies to both: `perform app.assert_actor_is_session_
-- identity(p_actor_auth_user_id);` is the first executable statement in each, before any
-- lookup or authority check.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit `revoke execute ... from public`
-- per function below, plus the standing blanket statement. Per ISS-2026-309 (closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): every `public.*` wrapper below
-- revokes from `anon, authenticated, service_role, public` (all four) before re-granting only
-- the intended subset, since Supabase's own ALTER DEFAULT PRIVILEGES rule grants `anon`/
-- `authenticated` EXECUTE directly at CREATE FUNCTION time in schema `public`.
-- ===========================================================================

-- ===========================================================================
-- 1. app.list_opportunities -- replaces server/queries/opportunity.ts:49 (listOpportunities)
-- ===========================================================================
create function app.list_opportunities(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  prospect_id uuid,
  account_ref text,
  name text,
  stage text,
  probability integer,
  value_amount numeric,
  value_currency text,
  value_masked boolean,
  requirements jsonb,
  next_action text,
  next_action_due_at timestamptz,
  close_reason text,
  cloned_from_id uuid,
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

  -- No pre-flight has_active_tenant_membership raise: this read's own existing contract
  -- (server/queries/opportunity.ts's own doc-comment, "RLS plus the view's own can_access_
  -- record filter is the real scope gate") is that a non-member or a member with zero
  -- visible rows both silently yield an empty page (totalCount 0), exactly as the
  -- `.from("opportunities_directory")` read under RLS-equivalent filtering already does
  -- today, never a thrown error -- mirrors app.list_contacts' own identical choice
  -- (20260908020000) for the same reason.
  return query
    select
      o.id,
      o.tenant_id,
      o.prospect_id,
      o.account_ref,
      o.name,
      o.stage,
      case when app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id) then o.probability else null end,
      case when app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id) then o.value_amount else null end,
      case when app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id) then o.value_currency else null end,
      not app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id),
      o.requirements,
      o.next_action,
      o.next_action_due_at,
      o.close_reason,
      o.cloned_from_id,
      o.owner_user_id,
      o.org_unit_id,
      o.record_version,
      o.created_by,
      o.created_at,
      o.updated_at,
      count(*) over() as total_count
    from app.opportunities o
    where o.tenant_id = p_tenant_id
      and app.can_access_record(
        p_actor_auth_user_id, o.tenant_id, o.owner_user_id,
        app.lead_record_scope_org_unit_ids(o.org_unit_id), null
      )
    order by o.created_at desc, o.id desc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_opportunities(uuid, uuid, integer, integer) is
  'CG-AUDIT-2026-09-02 O1: paginated, field-masked Opportunity list, replacing server/queries/opportunity.ts:49''s broken .from("opportunities_directory") (app is not exposed to PostgREST). Reproduces app.opportunities_directory''s exact defining SELECT against the base table app.opportunities directly (never the view itself, to avoid a nested-SECURITY-DEFINER auth.uid() reliance -- the same fix COM-149''s app.search_vendor_rates already established): probability/value_amount/value_currency are nulled out and value_masked=true unless the actor holds COM:View selling price (app.has_view_selling_price, unaltered since 20260723210000), and every row is additionally filtered by app.opportunities'' own current opportunities_select_scoped RLS predicate (app.can_access_record, unaltered since 20260723210000 -- confirmed via grep for a later ALTER POLICY, none found). account_id (added later by 20260725090000, never backfilled into this view) is deliberately not selected, matching the view''s own never-updated column list exactly. total_count is an exact count(*) over() of every row matching the WHERE clause before LIMIT/OFFSET, mirroring app.list_contacts'' identical technique for the same "exact count, arbitrary page number" external contract. A non-member or zero-visible-row actor gets an empty page, never a thrown error.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_opportunities with an identical grant set, never a
-- reimplementation.
create function public.list_opportunities(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  prospect_id uuid,
  account_ref text,
  name text,
  stage text,
  probability integer,
  value_amount numeric,
  value_currency text,
  value_masked boolean,
  requirements jsonb,
  next_action text,
  next_action_due_at timestamptz,
  close_reason text,
  cloned_from_id uuid,
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
  select * from app.list_opportunities(p_tenant_id, p_actor_auth_user_id, p_page, p_page_size);
$wrap$;

comment on function public.list_opportunities(uuid, uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_opportunities with an identical grant set, never a reimplementation.';

revoke execute on function app.list_opportunities(uuid, uuid, integer, integer) from public;
grant execute on function app.list_opportunities(uuid, uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_opportunities(uuid, uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_opportunities(uuid, uuid, integer, integer) to authenticated, service_role;

-- ===========================================================================
-- 2. app.get_opportunity_by_id -- replaces server/queries/opportunity.ts:69
--    (getOpportunityById)
-- ===========================================================================
create function app.get_opportunity_by_id(
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  prospect_id uuid,
  account_ref text,
  name text,
  stage text,
  probability integer,
  value_amount numeric,
  value_currency text,
  value_masked boolean,
  requirements jsonb,
  next_action text,
  next_action_due_at timestamptz,
  close_reason text,
  cloned_from_id uuid,
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

  -- Anti-enumeration, matching this read's own current contract (server/queries/
  -- opportunity.ts:67's own doc-comment: "returns null (never an error) when RLS/no-match
  -- yields zero rows") and app.get_account_by_id/app.get_contact_by_id's identical posture
  -- (20260908020000): a nonexistent id and an id the actor cannot access both collapse to
  -- zero rows below, never a thrown exception -- a caller cannot distinguish "wrong id"
  -- from "exists, not yours", the same behavior RLS-filtered `.maybeSingle()` already had.
  return query
    select
      o.id,
      o.tenant_id,
      o.prospect_id,
      o.account_ref,
      o.name,
      o.stage,
      case when app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id) then o.probability else null end,
      case when app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id) then o.value_amount else null end,
      case when app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id) then o.value_currency else null end,
      not app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id),
      o.requirements,
      o.next_action,
      o.next_action_due_at,
      o.close_reason,
      o.cloned_from_id,
      o.owner_user_id,
      o.org_unit_id,
      o.record_version,
      o.created_by,
      o.created_at,
      o.updated_at
    from app.opportunities o
    where o.id = p_opportunity_id
      and app.can_access_record(
        p_actor_auth_user_id, o.tenant_id, o.owner_user_id,
        app.lead_record_scope_org_unit_ids(o.org_unit_id), null
      );
end;
$$;

comment on function app.get_opportunity_by_id(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: single-opportunity, field-masked read for the Opportunity Detail view, replacing server/queries/opportunity.ts:69''s broken .from("opportunities_directory") (app is not exposed to PostgREST). Reproduces app.opportunities_directory''s exact defining SELECT against the base table directly (same auth.uid()-avoidance reasoning as app.list_opportunities), with the identical has_view_selling_price masking and can_access_record row filter, both unaltered since 20260723210000. account_id is deliberately not selected, matching the view''s own never-updated column list. Returns zero rows (never an exception) for a nonexistent id or one the actor cannot access, matching both the original .maybeSingle() contract and app.get_account_by_id/app.get_contact_by_id''s own anti-enumeration posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_opportunity_by_id with an identical grant set, never a
-- reimplementation.
create function public.get_opportunity_by_id(
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  prospect_id uuid,
  account_ref text,
  name text,
  stage text,
  probability integer,
  value_amount numeric,
  value_currency text,
  value_masked boolean,
  requirements jsonb,
  next_action text,
  next_action_due_at timestamptz,
  close_reason text,
  cloned_from_id uuid,
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
  select * from app.get_opportunity_by_id(p_opportunity_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_opportunity_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_opportunity_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_opportunity_by_id(uuid, uuid) from public;
grant execute on function app.get_opportunity_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_opportunity_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_opportunity_by_id(uuid, uuid) to authenticated, service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's PUBLIC-execute
-- default, applied before the role-specific grants above are relied upon (the individual
-- `revoke ... from public` lines per function above are kept too, for the same
-- belt-and-suspenders reason every other checkpoint in this repository keeps them).
revoke execute on function app.list_opportunities(uuid, uuid, integer, integer) from public;
revoke execute on function app.get_opportunity_by_id(uuid, uuid) from public;

-- ===========================================================================
-- RULE A / RULE B SELF-CHECK (re-read immediately before shipping)
-- ===========================================================================
-- RULE A: both app.* functions above take an explicit p_actor_auth_user_id and are granted
-- to `authenticated` (not service_role-only). In both, `perform app.assert_actor_is_session_
-- identity(p_actor_auth_user_id);` is the very first statement inside `begin ... end`,
-- before v_limit/v_page assignment (list function) and before the `return query` (both
-- functions) -- no lookup, no has_view_selling_price call, and no can_access_record call
-- precedes it in either function. Neither relies on the "service_role-only" exception.
--
-- RULE B: grepped `alter policy.*opportunities` and the bare name `opportunities_select_
-- scoped`, PLUS `create (or replace )?(materialized )?view app\.opportunities_directory` and
-- `drop view.*opportunities_directory`, across every file in supabase/migrations/*.sql (not
-- just nearby ones). Total hits: one CREATE POLICY (20260723210000), one unrelated comment
-- that merely names the policy (20260725090000:278, does not alter it), and one CREATE VIEW
-- (20260723210000) -- no ALTER POLICY, no second CREATE POLICY, and no CREATE OR REPLACE VIEW
-- exist anywhere. Also grepped `actor_holds_customer_user_layer` for any co-occurrence with
-- `opportunit` -- none found, confirming this table was never brought under
-- 20260730560000_harden_customer_user_layer_default_deny.sql's later hardening (unlike
-- app.accounts/app.customer_contracts/etc. in the immediately preceding batch). The predicate
-- reproduced in both functions above -- app.can_access_record(actor, tenant_id, owner_user_id,
-- app.lead_record_scope_org_unit_ids(org_unit_id), null) -- and the masking gate --
-- app.has_view_selling_price(tenant_id, actor) -- are therefore both confirmed current, not
-- stale.

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- File: server/queries/opportunity.ts
--
-- 1) Change `OpportunityQueryTableClient` (`Pick<SupabaseClient, "from">`) to be unused by
--    listOpportunities/getOpportunityById -- both now only need `OpportunityQueryRpcClient`
--    (`Pick<SupabaseClient, "rpc">`, already defined in this file and already used by
--    getOpportunityCostingReadiness). If listOpportunityStageHistory (a separate, still-`.from()`
--    read over app.opportunity_stage_history, out of this task's scope) is left unchanged for
--    now, keep `OpportunityQueryTableClient` exported for that one function only; otherwise
--    both listOpportunities and getOpportunityById should take `OpportunityQueryRpcClient`.
--
-- 2) `ListOpportunitiesInput` needs a new required field: `actorAuthUserId: string` (its one
--    call site, app/(tenant)/[tenantSlug]/commercial/opportunities/page.tsx:43, already has
--    `access.authUserId` in scope via resolveCommercialAccessForRequest -- confirmed by the
--    same field already being used at the sibling detail page,
--    app/(tenant)/[tenantSlug]/commercial/opportunities/[opportunityId]/page.tsx:50/51/52 --
--    so this is a mechanical addition, not a new lookup).
--
-- 3) listOpportunities new body:
--      export async function listOpportunities(client: OpportunityQueryRpcClient, input: ListOpportunitiesInput): Promise<ListOpportunitiesResult> {
--        const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
--        const page = Math.max(Math.trunc(input.page), 1);
--        const { data, error } = await client.rpc("list_opportunities", {
--          p_tenant_id: input.tenantId,
--          p_actor_auth_user_id: input.actorAuthUserId,
--          p_page: page,
--          p_page_size: pageSize,
--        });
--        if (error) {
--          throw new OpportunityQueryError(error.message);
--        }
--        const rows = (data ?? []) as Record<string, unknown>[];
--        const totalCount = rows.length > 0 ? Number(rows[0]?.total_count) : 0;
--        return {
--          opportunities: rows.map((row) => parseOpportunity(row)),
--          totalCount,
--          page,
--          pageSize,
--        };
--      }
--    (parseOpportunity already ignores the extra total_count field on each row -- no contract
--    change needed on server/contracts/opportunity/opportunity.ts. Keep the existing
--    page/pageSize clamping logic exactly as-is -- it still bounds what gets sent as
--    p_page/p_page_size, on top of the RPC's own defensive server-side clamp.)
--
-- 4) getOpportunityById new signature/body (add the same required `actorAuthUserId: string`
--    parameter -- both call sites in the detail page already have `access.authUserId` in
--    scope):
--      export async function getOpportunityById(client: OpportunityQueryRpcClient, opportunityId: string, actorAuthUserId: string): Promise<Opportunity | null> {
--        const { data, error } = await client.rpc("get_opportunity_by_id", {
--          p_opportunity_id: opportunityId,
--          p_actor_auth_user_id: actorAuthUserId,
--        });
--        if (error) {
--          throw new OpportunityQueryError(error.message);
--        }
--        const row = Array.isArray(data) ? data[0] : data;
--        if (!row) {
--          return null;
--        }
--        return parseOpportunity(row as Record<string, unknown>);
--      }
--    Return type is unchanged (`Promise<Opportunity | null>`); the "not found or denied ->
--    null" contract in its own doc-comment is preserved exactly.
--
-- Call-site mechanical changes (no other logic changes needed):
--   - app/(tenant)/[tenantSlug]/commercial/opportunities/page.tsx:43:
--       listOpportunities(supabase, { tenantId: access.tenant.id, page })
--       -> listOpportunities(supabase, { tenantId: access.tenant.id, page, actorAuthUserId: access.authUserId })
--   - app/(tenant)/[tenantSlug]/commercial/opportunities/[opportunityId]/page.tsx:34:
--       getOpportunityById(supabase, opportunityId)
--       -> getOpportunityById(supabase, opportunityId, access.authUserId)
--   - server/queries/opportunity.test.ts: `fakeTableClient` (its `.from()`-shaped stub) is no
--     longer sufficient for these two functions -- replace with a `.rpc()`-shaped fake client
--     mirroring server/queries/rfq.test.ts's/server/queries/contact.test.ts's own `.rpc(...)`
--     stub shape, one branch keyed on the RPC name ("list_opportunities" vs.
--     "get_opportunity_by_id") returning an array of row objects (each opportunity row plus
--     `total_count` for the list case) / `[]` (not-found/denied) / an error object, matching
--     how VALID_OPPORTUNITY_ROW is already shaped in that file.
-- ============================================================================================
-- CG-AUDIT-2026-09-02 O1 remediation -- app.opportunity_stage_history (COM-147).
--
-- Replaces: server/queries/opportunity.ts:82 (listOpportunityStageHistory) --
--   `.from("opportunity_stage_history").select("*").eq("opportunity_id", opportunityId)
--   .order("changed_at", { ascending: true })`, currently 404-broken in production because
--   supabase/config.toml exposes only public/graphql_public to PostgREST and `app` is
--   completely invisible to it. transition_opportunity_stage/create_opportunity/
--   clone_opportunity all WRITE this table already (20260723210000); no read function on it
--   existed before this migration.
--
-- Table shape: app.opportunity_stage_history is a BASE TABLE, not a view -- created at
-- supabase/migrations/20260723210000_create_commercial_opportunity_management.sql:115-125
-- (id uuid, tenant_id uuid, opportunity_id uuid, from_stage text, to_stage text,
-- probability integer, reason text, changed_by text, changed_at timestamptz). Grepped
-- "alter table app.opportunity_stage_history" across every file in supabase/migrations/*.sql:
-- the only hit is that same migration's own `enable row level security` -- no later
-- add/drop-column statement exists anywhere, so this is still the complete, current column
-- list. There is no hash/secret/correlation column on this table (unlike e.g.
-- app.contacts.normalized_email or app.api_keys.key_hash) and the original `.from()` call
-- selected `*`, so the function below also selects every column -- no exclusion.
--
-- ------------------------------------------------------------------------------------------
-- RULE B -- current RLS predicate (opportunity_stage_history_select_scoped)
-- ------------------------------------------------------------------------------------------
-- create policy opportunity_stage_history_select_scoped on app.opportunity_stage_history
--   (20260723210000_create_commercial_opportunity_management.sql:560-568):
--     for select to authenticated
--     using (
--       exists (
--         select 1 from app.opportunities o
--         where o.id = opportunity_stage_history.opportunity_id
--           and app.can_access_record((select auth.uid()), o.tenant_id, o.owner_user_id,
--               app.lead_record_scope_org_unit_ids(o.org_unit_id), null)
--       )
--     );
-- Grepped, sorted by filename, across ALL of supabase/migrations/*.sql:
--   `grep -n "alter policy" **/*.sql | grep -i opportunit`            -> zero hits
--   `grep -rln "opportunity_stage_history_select_scoped" **/*.sql`    -> ONE hit, the
--       original create-policy file above (no later rewrite, no drop-and-recreate)
--   `grep -rln "opportunities_select_scoped" **/*.sql`                -> two hits, the
--       original create-policy file plus one unrelated COMMENT (20260725090000, discussing
--       an unrelated security_invoker=true view) that never touches this policy's text
-- Conclusion: the predicate quoted above, unaltered since 20260723210000, is still the
-- CURRENT authority envelope. The function below reproduces it exactly, restated as an
-- explicit WHERE/EXISTS filter (SECURITY DEFINER bypasses RLS entirely, so it must be
-- re-implemented, never assumed) rather than a caller-supplied tenant/owner argument, since
-- the child table itself carries no owner_user_id/org_unit_id of its own -- only the parent
-- app.opportunities row does, exactly as the policy's own EXISTS join expresses.
--
-- ------------------------------------------------------------------------------------------
-- RULE C -- precedent staleness check
-- ------------------------------------------------------------------------------------------
-- app.can_access_record: `grep -n "function app.can_access_record" **/*.sql` finds two
-- definitions -- the PLT-114 original (20260716110430) and ONE later
-- `create or replace` at 20260723180000_create_commercial_sales_pipeline.sql:50-88 (COM-146,
-- fixes a NULL-owner-defeats-the-guard defect in the original). No third replace exists
-- anywhere later. The 5-arg COM-146 signature/body
-- (p_auth_user_id, p_tenant_id, p_owner_user_id, p_shared_org_unit_ids, p_customer_account_ref)
-- is what is called below -- the current, patched body, not the stale original.
-- app.assert_actor_is_session_identity: `grep -n "function app.assert_actor_is_session_
-- identity" **/*.sql` finds exactly ONE definition, 20260730440000_harden_actor_identity_
-- session_crosscheck.sql:59 (ATW-031/ISS-2026-017) -- never replaced, so no staleness risk.
-- app.lead_record_scope_org_unit_ids: exactly one definition
-- (20260723090000_create_commercial_lead_management.sql:164), never replaced.
--
-- Direct, same-domain, same-shape precedent for THIS function's authority pattern and
-- language/statement-ordering: app.list_costing_requests_for_opportunity, authored earlier
-- in this SAME migration file (see the app.costing_requests remediation section above,
-- "2. app.list_costing_requests_for_opportunity") -- an identically-shaped "list a child
-- table filtered by opportunity_id, actor argument second, LANGUAGE SQL, leading
-- `select app.assert_actor_is_session_identity(p_actor_auth_user_id);` statement, no
-- LIMIT/pagination" read. That function's own authority check restates its *own* table's
-- (costing_requests_select_scoped) predicate directly against columns costing_requests
-- carries itself (owner_user_id/org_unit_id live on that table). app.opportunity_stage_
-- history carries neither column itself, so this function's predicate instead reproduces
-- opportunity_stage_history_select_scoped's own EXISTS-against-app.opportunities join
-- verbatim (RULE B above) -- the same general shape (an explicit WHERE restating the
-- table's current RLS policy, LANGUAGE SQL, assert-then-select), adapted to this table's
-- own (parent-joined, not self-owned) authority columns. This is the correct precedent to
-- imitate for shape; it is NOT stale (authored fresh in this same batch, already
-- post-hardening) so RULE C's staleness concern does not apply to it the way it would to an
-- older, possibly-since-patched sibling.
--
-- Bounded-list convention (item 8): no LIMIT/pagination, matching this exact precedent's own
-- stated reasoning -- the original `.from("opportunity_stage_history").select("*")
-- .eq("opportunity_id", opportunityId).order("changed_at", {ascending: true})` call site
-- never applied a `.range()`/`.limit()` either, and the row count per opportunity is
-- naturally small: app.create_opportunity/app.clone_opportunity each insert exactly one
-- initial row, and app.transition_opportunity_stage inserts exactly one row per actual
-- stage change a human performs on that one opportunity -- there is no unbounded/tenant-wide
-- fan-out here the way app.list_accounts (a genuine tenant-wide list) has. Adding an
-- artificial cap would be a behavior change nobody asked for, not a faithful translation.
-- ============================================================================================

create function app.list_opportunity_stage_history(
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.opportunity_stage_history
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select h.*
  from app.opportunity_stage_history h
  where h.opportunity_id = p_opportunity_id
    and exists (
      select 1
      from app.opportunities o
      where o.id = h.opportunity_id
        and app.can_access_record(
          p_actor_auth_user_id, o.tenant_id, o.owner_user_id,
          app.lead_record_scope_org_unit_ids(o.org_unit_id), null
        )
    )
  order by h.changed_at asc;
$$;

comment on function app.list_opportunity_stage_history(uuid, uuid) is
  'COM-147 read (CG-AUDIT-2026-09-02 O1): actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032, RULE A). Restates opportunity_stage_history_select_scoped''s own current RLS predicate (20260723210000, never later altered -- confirmed via grep) as an explicit EXISTS-against-app.opportunities filter, since this is SECURITY DEFINER and the base table''s RLS never applies to it, and the child table carries no owner_user_id/org_unit_id of its own -- authority is necessarily evaluated against the PARENT opportunity row''s tenant/owner/org-unit via app.can_access_record (current COM-146 body). A nonexistent opportunity id, a cross-tenant id, or an in-tenant id the actor cannot otherwise reach all collapse to zero rows -- never an exception -- exactly matching the anti-enumeration behavior the original RLS-filtered `.from()` read already had. No LIMIT: the original call site applied none, and this table''s own row count per opportunity is naturally bounded to the handful of real stage-change actions a human can perform on one record (see migration header for the full reasoning).';

create function public.list_opportunity_stage_history(
  p_opportunity_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.opportunity_stage_history
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_opportunity_stage_history(p_opportunity_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_opportunity_stage_history(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_opportunity_stage_history with an identical grant set, never a reimplementation.';

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's PUBLIC-execute
-- default, applied before the role-specific grant below is relied upon.
revoke execute on function app.list_opportunity_stage_history(uuid, uuid) from public;
grant execute on function app.list_opportunity_stage_history(uuid, uuid) to authenticated, service_role;

-- Per ISS-2026-309 (20260830200000_correct_public_wrapper_grant_parity.sql): a bare
-- `revoke ... from public` does NOT strip the `anon`/`authenticated` EXECUTE grants
-- Supabase's own ALTER DEFAULT PRIVILEGES rule applies to every new function in schema
-- public at CREATE time -- revoke from all four roles explicitly before re-granting.
revoke execute on function public.list_opportunity_stage_history(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_opportunity_stage_history(uuid, uuid) to authenticated, service_role;

-- ============================================================================================
-- RULE A / RULE B self-check (re-read immediately before finishing):
--   RULE A -- `select app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the
--     literal first statement in app.list_opportunity_stage_history's LANGUAGE SQL body,
--     before the SELECT that reads the table. The function takes an explicit
--     p_actor_auth_user_id and is granted to `authenticated` (not service_role-only), so
--     RULE A's exception does not apply and the assert call is required -- present, confirmed.
--   RULE B -- grepped "alter policy" (repo-wide, filtered for "opportunit") and the bare
--     policy name "opportunity_stage_history_select_scoped" across every file in
--     supabase/migrations/*.sql: zero ALTER POLICY hits, and exactly one CREATE POLICY hit
--     (the original, 20260723210000). The predicate reproduced above is therefore still the
--     current, unaltered envelope -- no later rewrite was missed.
-- ============================================================================================

-- TS INTEGRATION:
-- File: server/queries/opportunity.ts
--
-- 1. Change listOpportunityStageHistory's client parameter type from
--    `OpportunityQueryTableClient` (Pick<SupabaseClient, "from">) to the file's existing
--    `OpportunityQueryRpcClient` (Pick<SupabaseClient, "rpc">, already defined at the top of
--    this file and already used by getOpportunityCostingReadiness) -- no new type needed.
--
-- 2. Add a required third parameter `actorAuthUserId: string`, and replace the `.from()`
--    chain (lines 81-85) with an `.rpc()` call:
--
--      export async function listOpportunityStageHistory(
--        client: OpportunityQueryRpcClient,
--        opportunityId: string,
--        actorAuthUserId: string,
--      ): Promise<OpportunityStageHistoryEntry[]> {
--        const { data, error } = await client.rpc("list_opportunity_stage_history", {
--          p_opportunity_id: opportunityId,
--          p_actor_auth_user_id: actorAuthUserId,
--        });
--        if (error) {
--          throw new OpportunityQueryError(error.message);
--        }
--        return (data ?? []).map((row: Record<string, unknown>) => parseOpportunityStageHistoryEntry(row));
--      }
--
--    `data` from a `returns setof app.opportunity_stage_history` RPC is already a plain row
--    array (not wrapped, not a single object) -- the existing
--    `(data ?? []).map((row) => parseOpportunityStageHistoryEntry(row))` line is kept
--    completely unchanged; parseOpportunityStageHistoryEntry needs no change at all since the
--    returned row shape (id, tenant_id, opportunity_id, from_stage, to_stage, probability,
--    reason, changed_by, changed_at) is identical to the old `.from()` row shape. Ordering
--    (changed_at ascending) is now enforced inside the function's own `order by`, not by a
--    client-side `.order()` call, so the returned array order is unchanged.
--
-- 3. Call site update -- app/(tenant)/[tenantSlug]/commercial/opportunities/[opportunityId]/
--    page.tsx:49:
--      listOpportunityStageHistory(supabase, opportunity.id)
--      -> listOpportunityStageHistory(supabase, opportunity.id, access.authUserId)
--    `access.authUserId` is already resolved and already in scope one line below (passed into
--    `getOpportunityCostingReadiness` on line 50) and two lines below (into
--    `listActivitiesForRecord`/`listCostingRequestsForOpportunity`) -- purely mechanical, no
--    new lookup required.
--
-- 4. server/queries/opportunity.test.ts:128-132 (`describe("listOpportunityStageHistory", ...)`)
--    -- update the fake client fixture from a `.from()`-shaped stub to an `.rpc("list_
--    opportunity_stage_history", ...)`-shaped stub returning a plain row array, mirroring how
--    this same file's own getOpportunityCostingReadiness test already stubs `.rpc(...)`, and
--    add the new required `actorAuthUserId` argument to the `listOpportunityStageHistory(client,
--    OPPORTUNITY_ID)` call at line 132.
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 0, table app.sales_plans.
--
-- Replaces two broken `.from("sales_plans")` reads in server/queries/pipeline.ts (the `app`
-- schema is invisible to PostgREST -- see supabase/config.toml `schemas = ["public",
-- "graphql_public"]` -- so both calls 404 as a nonexistent relation on every real request):
--   * server/queries/pipeline.ts:76  listSalesPlans  -- select * from sales_plans, eq
--     tenant_id, order created_at desc. Feeds app/(tenant)/[tenantSlug]/commercial/
--     pipeline/page.tsx's plan table.
--   * server/queries/pipeline.ts:88  getSalesPlanById -- select * from sales_plans, eq id,
--     maybeSingle. Feeds the Plan Detail page,
--     app/(tenant)/[tenantSlug]/commercial/pipeline/[planId]/page.tsx.
-- These are two distinct, differently-filtered reads (tenant-wide bounded list vs.
-- single-row-by-id) with no shared extra parameter that would let one function serve both --
-- per the task's own item 7, they get two separate functions (mirroring how this exact
-- codebase already pairs app.list_accounts / app.get_account_by_id, rather than one
-- function with an optional id argument).
--
-- TABLE (not a view): app.sales_plans, created at
-- supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql:324-341. Exact
-- column list (verified by reading the CREATE TABLE statement directly, not inferred):
--   id uuid, tenant_id uuid, org_unit_id uuid (nullable), name text, period_start date,
--   period_end date, status text, supersedes_plan_id uuid (nullable),
--   owner_user_id uuid (nullable, references auth.users), record_version integer,
--   created_by text (nullable), created_at timestamptz, updated_at timestamptz.
-- Confirmed via `grep -n "create table app.sales_plans\|create or replace view app.sales_
-- plans\|create materialized view app.sales_plans"` across supabase/migrations/*.sql: only
-- one hit, the CREATE TABLE above -- this is a genuine base table, never a view, so there is
-- no field-masking CASE-WHEN logic to replicate (item 6 of the task is a no-op here). No
-- later "create or replace" of this table exists (tables cannot be CREATE OR REPLACE'd
-- anyway; confirmed no subsequent `alter table app.sales_plans` changed its shape).
--
-- Column exclusion: NONE. server/contracts/pipeline/pipeline.ts's `parseSalesPlan` (the
-- function server/queries/pipeline.ts already feeds every row through) maps every single
-- column above 1:1 into SalesPlanSchema -- there is no hash/secret/internal column on this
-- table to begin with. Both new functions below therefore `select *`, exactly matching the
-- original `.select("*")` calls' own effective contract.
--
-- AUTHORITY RULE ENFORCED, AND WHY (RULE B, with the required ALTER-POLICY currency check):
-- `grep -n "create policy" supabase/migrations/*.sql | grep sales_plans` finds exactly one
-- policy: `sales_plans_select_scoped`, created at
-- supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql:1229-1233:
--   create policy sales_plans_select_scoped on app.sales_plans for select to authenticated
--   using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id,
--          app.lead_record_scope_org_unit_ids(org_unit_id), null));
-- Per RULE B, also grepped for any later rewrite before trusting this text as current:
--   * `grep -rn "alter policy" supabase/migrations/*.sql | grep -i sales_plans` -> no hits.
--   * `grep -rln "sales_plans_select_scoped" supabase/migrations/*.sql` -> only the one file
--     above -- the policy is never named again, so it was never ALTER'd.
--   * Specifically checked whether 20260730560000_harden_customer_user_layer_default_deny.sql
--     (the migration that retrofitted "AND NOT app.actor_holds_customer_user_layer(tenant_id)"
--     onto several tenant-membership-flat policies) touches this table:
--     `grep -n "sales_plan" 20260730560000_harden_customer_user_layer_default_deny.sql` ->
--     no hits. This is expected, not an oversight on that migration's part: that hardening
--     pass only applied to policies whose predicate was the FLAT
--     `app.has_active_tenant_membership(tenant_id)` (any tenant member sees every row --
--     the shape a customer_user-layer principal could otherwise exploit for tenant-wide
--     staff data). `sales_plans_select_scoped` was never flat -- it was already
--     owner/org-unit/customer-ref scoped via app.can_access_record from the moment COM-146
--     created it, so the customer_user-layer gap that migration closed elsewhere never
--     existed here in the first place.
-- So the CURRENT (and only-ever) predicate is reproduced verbatim below, with the caller's
-- session identity threaded through as an explicit `p_actor_auth_user_id` argument (SECURITY
-- DEFINER functions cannot rely on the RLS-clause's own `(select auth.uid())` the way the
-- policy itself does, since RLS is bypassed for a definer function -- restating the identical
-- predicate against the explicit actor argument is what keeps this a reproduction, not a
-- narrowing or widening, of the RLS envelope).
--
-- PRECEDENT FOR THE AUTHORITY-CHECK SHAPE (RULE C: most-recent body, not the original):
-- `app.can_access_record` itself: `grep -n "create or replace function app.can_access_record\|
-- create function app.can_access_record" supabase/migrations/*.sql` finds exactly two hits --
-- the original at 20260716110430_create_field_record_access.sql:31 and COM-146's
-- CREATE OR REPLACE at 20260723180000_create_commercial_sales_pipeline.sql:50-88 (which fixed
-- a real NULL-owner-comparison defect, per that migration's own header). No later
-- CREATE OR REPLACE exists, so 20260723180000's body -- the one already read in full above --
-- is confirmed current.
-- Function SHAPE modeled on `app.get_sales_target_actual`, the closest possible sibling: same
-- table domain (app.sales_plans/app.sales_targets, COM-146), same "single row, actor-scoped"
-- read shape, and it already threads p_actor_auth_user_id through this exact
-- app.can_access_record(..., app.lead_record_scope_org_unit_ids(...), null) call. Per RULE C,
-- confirmed its MOST RECENT body, not its original: `grep -n "create or replace function app.
-- get_sales_target_actual\|create function app.get_sales_target_actual"
-- supabase/migrations/*.sql` finds the original at 20260723180000:511-542 (no RULE-A assert)
-- and a later CREATE OR REPLACE at 20260810400000_harden_crm_ops_actor_identity_gaps.sql:
-- 382-414 that inserts `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);`
-- as the first statement, ahead of the app.sales_targets lookup -- that HDN-373 migration's own
-- header explains why: this class of function is self-referential (the actor parameter names
-- the caller, passed straight through), so binding it to the session identity is a pure
-- security repair, not a behavior change for any legitimate caller. 20260810400000 is the
-- current, correct shape and is what is reproduced below (never the pre-patch original).
-- The list variant (app.list_sales_plans) additionally mirrors app.list_accounts /
-- app.get_account_by_id (supabase/migrations/20260908020000_close_o1_query_layer_cluster0_
-- batch1_crm_core.sql:279-462, this exact remediation effort's own immediately-preceding
-- batch) for two structural choices: (a) the bounded-list cap
-- `limit least(coalesce(p_limit, 200), 200)`, the same convention app.list_rfqs/app.list_
-- finance_invoices/app.list_api_keys_for_tenant/app.list_accounts all already use; and
-- (b) applying the authority predicate as a per-ROW WHERE-clause filter rather than a single
-- up-front all-or-nothing raise -- because, unlike app.accounts' flat tenant-membership
-- policy, `sales_plans_select_scoped` is itself a per-row predicate (owner_user_id /
-- org_unit_id vary row to row), so a per-row filter is what actually reproduces it (this
-- mirrors app.list_subsidiary_accounts / app.get_account_by_id's reasoning in that same
-- migration for the identical "no single flat tenant gate" situation, not app.list_accounts'
-- own single up-front raise, which only fits a flat, tenant-wide predicate). This also
-- preserves the original `.from("sales_plans").select("*").eq("tenant_id", tenantId)`
-- call's own behavior under RLS exactly: rows the policy would have hidden are silently
-- absent from the result, never an exception -- "not found" and "found but not visible"
-- were never distinguished by the old code path either.
--
-- RULE A (actor-impersonation guard, ISS-2026-017/032, HDN-372/373): both functions below
-- take an explicit p_actor_auth_user_id and are granted to `authenticated` (not
-- service_role-only), so both open with
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as their first
-- executable statement, before any lookup or authority check -- reproducing app.get_sales_
-- target_actual's current (patched) shape, not its stale original.
--
-- Bounded-list choice (task item 8): plain `order by created_at desc limit
-- least(coalesce(p_limit, 200), 200)`, matching app.list_accounts/app.list_rfqs/app.list_
-- finance_invoices/app.list_api_keys_for_tenant's own established convention -- no cursor
-- pagination exists anywhere in this table's own domain (app.sales_plans has no sibling list
-- function today), so this is the closest-matching established sibling shape, not a guess.

create function app.list_sales_plans(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.sales_plans
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select *
    from app.sales_plans sp
    where sp.tenant_id = p_tenant_id
      and app.can_access_record(
        p_actor_auth_user_id,
        sp.tenant_id,
        sp.owner_user_id,
        app.lead_record_scope_org_unit_ids(sp.org_unit_id),
        null
      )
    order by sp.created_at desc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_sales_plans(uuid, uuid, integer) is
  'COM-146 (O1-query-layer remediation): tenant-scoped sales plan list, most-recent first, server-side clamped to <=200 rows (mirrors app.list_accounts/app.list_rfqs/app.list_finance_invoices/app.list_api_keys_for_tenant''s own established cap convention). Authority reproduces the CURRENT (and only-ever, confirmed no later ALTER POLICY) sales_plans_select_scoped predicate -- app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null), verbatim, from supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql -- applied per-row in the WHERE clause (not a single flat gate) because that predicate itself varies per row. A tenant member with no visible plans silently gets an empty list, exactly as the original RLS-backed .from() call already behaved; this function never raises for "no accessible rows".';

create function public.list_sales_plans(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.sales_plans
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_sales_plans(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_sales_plans(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_sales_plans with an identical grant set, never a reimplementation.';

revoke execute on function app.list_sales_plans(uuid, uuid, integer) from public;
grant execute on function app.list_sales_plans(uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_sales_plans(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_sales_plans(uuid, uuid, integer) to authenticated, service_role;

-- app.get_sales_plan_by_id -- replaces server/queries/pipeline.ts:88 (getSalesPlanById).
-- Same table, same authority predicate, same RULE A/B/C findings as app.list_sales_plans
-- above (see that function's header block for the full citations -- not repeated here to
-- avoid drifting out of sync with it). Returns SETOF (zero or one row) rather than a single
-- nullable value or a raised exception on denial, so "no such id" and "exists but the
-- current sales_plans_select_scoped predicate denies it" both collapse to an empty result --
-- exactly the anti-enumeration behavior the original `.eq("id", planId).maybeSingle()` call
-- already had under RLS (a denied row simply never came back; there was never a distinct
-- "denied" error). This mirrors app.get_account_by_id's identical reasoning in
-- supabase/migrations/20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:
-- 414-440 for the exact same "single row by id, no separate tenant argument, per-row
-- predicate" shape (the original `.eq("id", planId)` call carried no tenant filter of its
-- own either, so authority here is evaluated against THIS row's own tenant_id/owner_user_id/
-- org_unit_id, not a caller-asserted tenant).
create function app.get_sales_plan_by_id(
  p_plan_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.sales_plans
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select *
    from app.sales_plans sp
    where sp.id = p_plan_id
      and app.can_access_record(
        p_actor_auth_user_id,
        sp.tenant_id,
        sp.owner_user_id,
        app.lead_record_scope_org_unit_ids(sp.org_unit_id),
        null
      );
end;
$$;

comment on function app.get_sales_plan_by_id(uuid, uuid) is
  'COM-146 (O1-query-layer remediation): single-sales-plan-by-id read, used by the Plan Detail page. No p_tenant_id parameter -- mirrors app.get_account_by_id''s own reasoning, evaluating the CURRENT sales_plans_select_scoped predicate (app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null), unchanged since 20260723180000_create_commercial_sales_pipeline.sql, confirmed via grep for a later ALTER POLICY -- none found) against this row''s own tenant_id/owner_user_id/org_unit_id. Returns SETOF (zero or one row) rather than raising, so "no such id" and "exists but denied" both collapse to an empty result -- the TS caller keeps returning null on an empty result exactly as .maybeSingle() under RLS already did.';

create function public.get_sales_plan_by_id(
  p_plan_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.sales_plans
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_sales_plan_by_id(p_plan_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_sales_plan_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_sales_plan_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_sales_plan_by_id(uuid, uuid) from public;
grant execute on function app.get_sales_plan_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_sales_plan_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_sales_plan_by_id(uuid, uuid) to authenticated, service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since PLT-118,
-- swept once more here before relying on the role-specific grants above (belt-and-suspenders,
-- matching every other checkpoint in this repository, e.g. 20260908020000:464-472).
revoke execute on function app.list_sales_plans(uuid, uuid, integer) from public;
revoke execute on function app.get_sales_plan_by_id(uuid, uuid) from public;

-- ===========================================================================
-- RULE A / RULE B SELF-CHECK (re-read before shipping, per task step 10)
-- ===========================================================================
-- RULE A: app.list_sales_plans and app.get_sales_plan_by_id both take an explicit
-- p_actor_auth_user_id and are granted to `authenticated`. In both, re-reading the bodies
-- above: `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the very
-- first line of the `begin` block, before the `return query` / lookup / app.can_access_record
-- call in either function. Neither function is service_role-only, so the exception in RULE A
-- does not apply and is not being relied on.
-- RULE B: grepped `alter policy.*sales_plans` and `sales_plans_select_scoped` across every
-- file in supabase/migrations/*.sql (sorted by filename, which is date-ordered in this repo)
-- -- zero ALTER POLICY hits, and the policy name appears only in its own 20260723180000
-- creation migration. The predicate reproduced in both functions above is therefore
-- confirmed current, not stale. RULE C: app.can_access_record's only two definitions
-- (20260716110430 original, 20260723180000 COM-146 replacement) were both read in full; the
-- COM-146 body is what both functions above call. app.get_sales_target_actual's two
-- definitions (20260723180000 original, 20260810400000 HDN-373 replacement) were both read in
-- full; the HDN-373 body (with the RULE A assert) is the shape both functions above imitate.
--
-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/pipeline.ts
--
-- 1. listSalesPlans (currently line 74-84):
--    - Change the parameter list to add the actor identity: from
--      `listSalesPlans(client: PipelineQueryTableClient, tenantId: string)` to
--      `listSalesPlans(client: PipelineQueryRpcClient, tenantId: string, actorAuthUserId: string)`
--      (swap the client type from the `.from`-only `PipelineQueryTableClient` to the
--      already-declared `.rpc`-only `PipelineQueryRpcClient` used a few lines above by
--      getPipelineSummary/getSalesTargetActual -- the real `supabase` client passed at every
--      call site already satisfies both shapes structurally, so this is purely a narrowing of
--      the declared parameter type, not a runtime change to what object is passed in).
--    - Replace the body's `.from("sales_plans").select("*").eq("tenant_id", tenantId).order("created_at",
--      { ascending: false })` chain with:
--        const { data, error } = await client.rpc("list_sales_plans", {
--          p_tenant_id: tenantId,
--          p_actor_auth_user_id: actorAuthUserId,
--        });
--      (omit p_limit to take the function''s own default of 200, matching the original
--      call''s lack of any limit/pagination).
--    - Keep the existing `if (error) throw new PipelineQueryError(error.message);` and the
--      existing `return (data ?? []).map((row: Record<string, unknown>) => parseSalesPlan(row));`
--      unchanged -- `list_sales_plans` returns `setof app.sales_plans`, which the JS client
--      surfaces as a plain array of row objects with the identical snake_case column names
--      `parseSalesPlan` already expects, so no change to the mapping logic itself.
--
-- 2. getSalesPlanById (currently line 87-96):
--    - Change the parameter list the same way: from
--      `getSalesPlanById(client: PipelineQueryTableClient, planId: string)` to
--      `getSalesPlanById(client: PipelineQueryRpcClient, planId: string, actorAuthUserId: string)`.
--    - Replace `.from("sales_plans").select("*").eq("id", planId).maybeSingle()` with:
--        const { data, error } = await client.rpc("get_sales_plan_by_id", {
--          p_plan_id: planId,
--          p_actor_auth_user_id: actorAuthUserId,
--        });
--      Note the shape change: `get_sales_plan_by_id` returns `setof app.sales_plans` (zero or
--      one row as an ARRAY), not a single nullable object the way `.maybeSingle()` did -- so
--      the "no row" check must become an array check:
--        if (error) { throw new PipelineQueryError(error.message); }
--        if (!Array.isArray(data) || data.length === 0) { return null; }
--        return parseSalesPlan(data[0] as Record<string, unknown>);
--      (replacing the current `if (!data) return null; return parseSalesPlan(data as
--      Record<string, unknown>);` body).
--
-- 3. Call-site updates (both already have an authenticated actor id in scope, so no new
--    upstream plumbing is needed):
--    - app/(tenant)/[tenantSlug]/commercial/pipeline/page.tsx:36 --
--      `listSalesPlans(supabase, access.tenant.id)` becomes
--      `listSalesPlans(supabase, access.tenant.id, access.authUserId)` (`access.authUserId`
--      is the same field this page''s sibling detail page already reads off the same
--      `resolveCommercialAccessForRequest(...)` result, e.g. its own
--      `getSalesTargetActual(supabase, target.id, access.authUserId)` call).
--    - app/(tenant)/[tenantSlug]/commercial/pipeline/[planId]/page.tsx:31 --
--      `getSalesPlanById(supabase, planId)` becomes
--      `getSalesPlanById(supabase, planId, access.authUserId)` (`access` is already resolved
--      earlier in this same function body, at its own line 22, before this call).
--
-- 4. server/queries/pipeline.test.ts:162-176's two describe blocks (`listSalesPlans`,
--    `getSalesPlanById`) will need their mock client to stub `.rpc("list_sales_plans", ...)`
--    / `.rpc("get_sales_plan_by_id", ...)` instead of `.from("sales_plans")...`, and their
--    call sites (lines 165, 174) need a third `actorAuthUserId` argument -- mechanical
--    updates only, not described further here since this task is schema-only.
-- ===========================================================================
-- Ø1 query-layer remediation -- app.sales_targets (cluster 0, follow-on batch)
-- ===========================================================================
-- Replaces: server/queries/pipeline.ts:101 (listSalesTargetsForPlan) --
--   `.from("sales_targets").select("*").eq("sales_plan_id", salesPlanId)
--   .order("metric_type", { ascending: true })` -- broken because `app` is not
--   in supabase/config.toml's exposed `schemas` list, so PostgREST 404s the
--   relation. app.sales_targets is a real BASE TABLE (not a view) -- confirmed
--   by `create table app.sales_targets (...)` at
--   supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql:349.
--   No later `create or replace view`/materialized-view exists for this name
--   (grep for "app.sales_targets" as a view found none), and no masking is
--   required: every column in app.sales_targets (id, tenant_id, sales_plan_id,
--   pipeline_category_id, metric_type, org_unit_id, owner_user_id,
--   target_value, record_version, created_by, created_at, updated_at) maps
--   1:1 onto server/contracts/pipeline/pipeline.ts's SalesTargetSchema, and
--   the table has no cost/margin/sell-price-style sensitive column at all
--   (target_value is a plain count against one of four canonical-record
--   metrics -- COM-146 explicitly notes no currency/selling-value field
--   exists on any canonical record yet). No column is excluded relative to
--   the original `select("*")`.
--
-- Authority rule enforced, and why:
--   Row-level predicate `app.can_access_record(p_actor_auth_user_id,
--   t.tenant_id, t.owner_user_id, app.lead_record_scope_org_unit_ids(t.org_unit_id), null)`,
--   evaluated PER ROW (not a single up-front tenant gate), reproducing
--   `sales_targets_select_scoped` exactly as created at
--   20260723180000_create_commercial_sales_pipeline.sql:1235-1239 --
--   `for select to authenticated using (app.can_access_record((select
--   auth.uid()), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids
--   (org_unit_id), null))`.
--   RULE B check: grepped `alter policy` and the literal policy name
--   `sales_targets_select_scoped` across every file in supabase/migrations/*.sql
--   (sorted by filename) -- the ONLY hit is this original `create policy`
--   statement itself; no later ALTER rewrites it, and
--   20260730560000_harden_customer_user_layer_default_deny.sql (the
--   customer_user-layer hardening migration that DOES rewrite several
--   tenant-membership `has_active_tenant_membership`-only policies, e.g.
--   accounts/customer_contracts) does not mention sales_targets/sales_plans at
--   all -- expected, since this table was never has_active_tenant_membership-
--   gated in the first place; its can_access_record predicate already
--   excludes bare tenant-membership as sufficient.
--   RULE C check: app.can_access_record has exactly two bodies in the
--   migrations tree -- the original at
--   20260716110430_create_field_record_access.sql:31 and a `create or
--   replace` in THIS SAME migration (20260723180000, ~line 50) that fixes a
--   real NULL-owner boolean-coercion bug (see that migration's own header
--   note) -- no later redefinition exists (confirmed by grep for `create or
--   replace function app.can_access_record` across all migrations), so the
--   20260723180000 body is the current, correct one and is what the RLS
--   policy above (created in that same file) already reflects. Likewise
--   app.lead_record_scope_org_unit_ids has exactly one definition
--   (20260723090000_create_commercial_lead_management.sql:164), never
--   replaced. Direct precedent for this exact predicate shape being reused
--   verbatim inside a SECURITY DEFINER function (rather than only inside RLS)
--   is app.get_sales_target_actual's own CURRENT body -- the `create or
--   replace function app.get_sales_target_actual` at
--   20260810400000_harden_crm_ops_actor_identity_gaps.sql:382 (patched there
--   for the exact RULE A gap this task warns about; its ORIGINAL body at
--   20260723180000:511 is stale and must not be copied) -- which calls
--   `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as
--   its first statement, then gates on
--   `app.can_access_record(p_actor_auth_user_id, v_target.tenant_id,
--   v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null)`.
--   This migration's style/grant conventions (comment shape, Option-2 wrapper
--   body, ISS-2026-309 four-role revoke-then-regrant) are imitated directly
--   from the already-shipped sibling batch
--   20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql (e.g.
--   app.list_subsidiary_accounts / app.list_customer_contract_price_components),
--   which is this exact same remediation effort's own established, reviewed
--   house style for a "list rows scoped to one parent id, per-row authority
--   predicate, silently RLS-shaped empty/partial result" read function.
--
-- Pagination: the original `.from()` call carried no `.range()`/`.limit()`
-- and is scoped to a single sales_plan_id, whose targets are structurally
-- capped by `sales_targets_plan_metric_scope_unique` (one row per distinct
-- (metric_type, org_unit_id, owner_user_id) combination for that plan) --
-- not an open-ended tenant-wide list. Matching that same original behavior
-- and app.list_customer_contract_price_components' identical "list children
-- of one named parent id" precedent (which also carries no p_limit), no
-- p_limit/pagination parameter is added here.
-- ===========================================================================

create function app.list_sales_targets_for_plan(
  p_sales_plan_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.sales_targets
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select t.*
    from app.sales_targets t
    where t.sales_plan_id = p_sales_plan_id
      and app.can_access_record(
        p_actor_auth_user_id,
        t.tenant_id,
        t.owner_user_id,
        app.lead_record_scope_org_unit_ids(t.org_unit_id),
        null
      )
    order by t.metric_type asc;
end;
$$;

comment on function app.list_sales_targets_for_plan(uuid, uuid) is
  'COM-146 Ø1 remediation: read path for app.sales_targets, replacing the broken server/queries/pipeline.ts:101 .from("sales_targets") call (app is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup. Row-visibility predicate (app.can_access_record(actor, tenant_id, owner_user_id, lead_record_scope_org_unit_ids(org_unit_id), null)), evaluated per row, reproduces the CURRENT and only version of sales_targets_select_scoped (20260723180000_create_commercial_sales_pipeline.sql, never later ALTERed) and mirrors app.get_sales_target_actual''s CURRENT (20260810400000-patched) authority check verbatim. No p_tenant_id parameter and no raise-on-denial: the original .from().eq("sales_plan_id", ...) call carried no tenant filter and relied purely on RLS to silently filter/empty the result per row, which this reproduces exactly (targets within one plan can have different owner_user_id/org_unit_id, hence different per-row authority, rather than one plan-wide gate). Ordered by metric_type ascending, matching the original .order("metric_type", { ascending: true }). No column excluded or added relative to the original select("*") -- table has no sensitive/masked column.';

create function public.list_sales_targets_for_plan(
  p_sales_plan_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.sales_targets
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_sales_targets_for_plan(p_sales_plan_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_sales_targets_for_plan(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_sales_targets_for_plan with an identical grant set, never a reimplementation.';

-- Grant set mirrors the other app.* functions over this same table in the
-- same migration/domain (app.get_sales_target_actual / app.create_sales_target
-- / app.update_sales_target, all granted to authenticated + service_role via
-- their public.* wrappers in 20260826000000_create_public_api_data_wrappers.sql)
-- and the RLS policy's own `to authenticated` grantee -- a tenant-membership
-- (can_access_record-scoped), not support/supreme-only, read.
revoke execute on function app.list_sales_targets_for_plan(uuid, uuid) from public;
grant execute on function app.list_sales_targets_for_plan(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309
-- (20260830200000_correct_public_wrapper_grant_parity.sql): Supabase's own
-- ALTER DEFAULT PRIVILEGES rule grants EXECUTE on every new public.* function
-- to `anon` and `authenticated` at CREATE time, so a bare `revoke ... from
-- public` never strips those role-specific grants. Revoke all four roles
-- explicitly, then grant back only what app.list_sales_targets_for_plan
-- itself grants to.
revoke execute on function public.list_sales_targets_for_plan(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_sales_targets_for_plan(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/pipeline.ts
--
-- 1. Change `listSalesTargetsForPlan`'s client parameter type from
--    `PipelineQueryTableClient` (`Pick<SupabaseClient, "from">`) to
--    `PipelineQueryRpcClient` (`Pick<SupabaseClient, "rpc">`) -- the same type
--    already used by `getSalesTargetActual` a few lines above it in this file.
--
-- 2. Add an explicit `actorAuthUserId: string` parameter (same name/shape
--    `getSalesTargetActual` already takes), since app.list_sales_targets_for_plan
--    requires p_actor_auth_user_id and no default is provided:
--
--      export async function listSalesTargetsForPlan(
--        client: PipelineQueryRpcClient,
--        salesPlanId: string,
--        actorAuthUserId: string,
--      ): Promise<SalesTarget[]> {
--        const { data, error } = await client.rpc("list_sales_targets_for_plan", {
--          p_sales_plan_id: salesPlanId,
--          p_actor_auth_user_id: actorAuthUserId,
--        });
--        if (error) {
--          throw new PipelineQueryError(error.message);
--        }
--        if (!Array.isArray(data)) {
--          throw new PipelineQueryError("list_sales_targets_for_plan returned a non-array result");
--        }
--        return data.map((row) => parseSalesTarget(row as Record<string, unknown>));
--      }
--
--    (Argument order in the rpc payload object does not matter -- named params
--    -- but p_sales_plan_id then p_actor_auth_user_id mirrors the function's
--    declared parameter order.)
--
-- 3. Rows returned by list_sales_targets_for_plan(...) are shaped identically
--    to a `select * from app.sales_targets` row (same column set as the
--    table), so the existing `parseSalesTarget` parser (already used for the
--    old `.from()` path) needs no changes.
--
-- 4. Update every call site of `listSalesTargetsForPlan(client, salesPlanId)`
--    to pass the caller's actorAuthUserId as the new third argument (the same
--    identity already threaded through to `getSalesTargetActual` in the same
--    request/page).
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1 query-layer remediation -- app.forecast_snapshots read path.
--
-- Replaces: server/queries/pipeline.ts:112-122 (listForecastSnapshotsForTarget --
-- `select * from forecast_snapshots, eq sales_target_id, order snapshot_at desc` --
-- snapshot history for one sales target's Plan Detail page row, and also feeds
-- `snapshots[0] ?? null` as "latestSnapshot" one call site up,
-- app/(tenant)/[tenantSlug]/commercial/pipeline/[planId]/page.tsx:50-52). This
-- `.from("forecast_snapshots")` call is broken in production for the same reason as
-- every other `.from()` read in this backlog: `supabase/config.toml` exposes only
-- `public`/`graphql_public` to PostgREST; `app` (where this table actually lives) is
-- completely invisible to it.
--
-- Suggested filename when this is filed as a real migration:
--   supabase/migrations/20260908030000_fix_forecast_snapshots_postgrest_schema_exposure.sql
--
-- ===========================================================================
-- TARGET SHAPE: real base table, not a view
-- ===========================================================================
-- app.forecast_snapshots is a real BASE TABLE
-- (supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql:380-396),
-- not a view/directory -- no field-masking logic applies (grepped "create view
-- app.forecast_snapshots" / "create or replace view app.forecast_snapshots" /
-- "create materialized view app.forecast_snapshots" repo-wide: zero hits). Exact column
-- list/types (line 380-396): id uuid pk, tenant_id uuid not null references app.tenants,
-- sales_target_id uuid not null references app.sales_targets, computed_value integer not
-- null (>=0), override_value integer (nullable, >=0), override_reason text (nullable,
-- required non-empty iff override_value is set), snapshot_at timestamptz not null default
-- now(), created_by text, created_at timestamptz not null default now(). No hash/secret/
-- cost/margin column exists on this table at all -- it is a plain, unmasked count
-- snapshot (COM-146's own table comment: "an append-only, point-in-time capture of a
-- sales target's reconciled actual ... plus an optional, reasoned manual override").
--
-- Column exclusions: none. All 9 columns above are selected below (`returns setof
-- app.forecast_snapshots`), an exact match for the original `.select("*")` and for
-- `parseForecastSnapshot`'s 1:1 field mapping
-- (server/contracts/pipeline/pipeline.ts:312-324: id, tenant_id, sales_target_id,
-- computed_value, override_value, override_reason, snapshot_at, created_by, created_at --
-- note created_at is mapped but NOT updated_at, because this table has no updated_at
-- column at all; nothing is being dropped that the original call ever returned).
--
-- ===========================================================================
-- AUTHORITY RULE ENFORCED, AND WHY (RULE B + RULE C precedent chain, verified by
-- direct grep+read, not assumed)
-- ===========================================================================
--
-- 1. RLS predicate (RULE B): `create policy forecast_snapshots_select_scoped on
--    app.forecast_snapshots for select to authenticated using (exists (select 1 from
--    app.sales_targets t where t.id = forecast_snapshots.sales_target_id and
--    app.can_access_record((select auth.uid()), t.tenant_id, t.owner_user_id,
--    app.lead_record_scope_org_unit_ids(t.org_unit_id), null)));` -- declared ONCE, in
--    20260723180000_create_commercial_sales_pipeline.sql, lines 1241-1249. RULE B check:
--    grepped `alter policy.*forecast_snapshots`, `alter policy.*sales_targets`,
--    `forecast_snapshots_select_scoped`, and `sales_targets_select_scoped` across every
--    file in supabase/migrations/*.sql (sorted by filename) -- the ONLY hits anywhere in
--    the tree are the two original CREATE POLICY statements themselves (lines 1235 and
--    1241 of that same migration). No later ALTER POLICY, and no later CREATE POLICY of
--    either name, exists. This is therefore the current, unmodified authority envelope --
--    NOT one of the tables 20260730560000_harden_customer_user_layer_default_deny.sql
--    later hardened (confirmed by grepping that file directly for
--    "sales_targets|forecast_snapshots|sales_plans": zero hits) -- app.forecast_snapshots
--    is record-scoped via app.can_access_record (owner/org-unit/shared scope), not
--    tenant-membership-scoped via app.has_active_tenant_membership, so the
--    actor_holds_customer_user_layer exclusion that hardening added does not apply to it
--    at all. The function below reproduces the policy's `exists (...)` join against
--    app.sales_targets verbatim (substituting the asserted p_actor_auth_user_id for
--    auth.uid()), since a SECURITY DEFINER function never evaluates the invoker's own RLS.
--
-- 2. app.can_access_record signature/body (RULE C): grepped "create or replace function
--    app.can_access_record" / "create function app.can_access_record" repo-wide. Two
--    hits: the original (20260716110430_create_field_record_access.sql:31) and exactly
--    one `create or replace` (20260723180000_create_commercial_sales_pipeline.sql,
--    lines 50-88 -- the "NULL owner_user_id must not silently grant access" fix,
--    documented in that same migration's own header). No later replace exists anywhere
--    (confirmed repo-wide). That is the current version relied on here, and it is
--    exactly the same one forecast_snapshots_select_scoped/sales_targets_select_scoped
--    themselves already call, and the same one app.get_sales_target_actual and
--    app.capture_forecast_snapshot (below) already call.
--
-- 3. app.lead_record_scope_org_unit_ids (RULE C): grepped "create or replace function
--    app.lead_record_scope_org_unit_ids" / "create function ..." repo-wide -- exactly one
--    hit (20260723090000_create_commercial_lead_management.sql:164), no later replace.
--    Current, no staleness risk.
--
-- 4. app.assert_actor_is_session_identity (RULE C): grepped
--    "create or replace function app.assert_actor_is_session_identity" repo-wide --
--    exactly one hit (20260730440000_harden_actor_identity_session_crosscheck.sql:59),
--    no later replace. Current, no staleness risk on the assert helper itself.
--
-- 5. Direct row-lookup/raise-shape precedent over THIS SAME table family (RULE C,
--    the specific check this backlog's own reviewers flag as most commonly skipped):
--    grepped "capture_forecast_snapshot" and "get_sales_target_actual" repo-wide and read
--    the MOST RECENT hit for each, not the original creation migration -- and found that
--    NEITHER sibling alone is a fully current-and-correct precedent to copy wholesale:
--      a. app.get_sales_target_actual -- most recent body is the `create or replace` at
--         20260810400000_harden_crm_ops_actor_identity_gaps.sql:382-414 (an ATW-032/
--         RULE-A patch). It opens with
--         `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as its
--         first executable statement, before the `select into v_target from
--         app.sales_targets` lookup -- this is the RULE A placement imitated below.
--         BUT: grepping "capture_forecast_snapshot|get_sales_target_actual" also shows
--         get_sales_target_actual was NEVER touched by the later ISS-2026-146
--         tenant-id-disclosure pass (20260902200000, see (b)) -- it still raises the OLD,
--         two-separate-branches shape (`sales_target_not_found` on a bare not-found,
--         then a DIFFERENT `insufficient_authority ... for tenant %` message if
--         can_access_record fails) with no has_active_tenant_membership pre-check folded
--         in. That is a residual, disclosed gap in get_sales_target_actual today, out of
--         this task's scope to fix -- NOT copied forward here.
--      b. app.capture_forecast_snapshot -- most recent body is the `CREATE OR REPLACE` at
--         20260902200000_harden_tenant_id_disclosure_commercial.sql:553-604 (ISS-2026-146:
--         "fold app.has_active_tenant_membership(<row>.tenant_id, p_actor_auth_user_id)
--         into the SAME not-found branch the row-miss case already raises, using the
--         identical generic message/errcode ... only a caller with NO relationship to the
--         tenant sees a different (and less disclosing) outcome"). Its lookup is now:
--         `if not found or not app.has_active_tenant_membership(v_target.tenant_id,
--         p_actor_auth_user_id) then raise exception 'sales_target_not_found: %', ...
--         using errcode = 'no_data_found'; end if;` followed by a SEPARATE
--         `can_access_record` check/raise afterward -- this folded not-found shape is
--         imitated below. BUT: this same current body does NOT open with
--         `perform app.assert_actor_is_session_identity(...)` at all -- neither its
--         original (20260723180000) nor its ISS-2026-146 replacement
--         (20260902200000) ever added the RULE A assert call (confirmed: grepped
--         "assert_actor_is_session_identity" is absent from every hit of
--         "capture_forecast_snapshot" in the repo). That is a residual, disclosed RULE A
--         gap in capture_forecast_snapshot today (it is out of this task's scope, which is
--         a new READ function over app.forecast_snapshots, not a fix to the existing
--         WRITE function) -- NOT copied forward here either.
--    Conclusion: this is exactly the "citing a stale pre-patch precedent" trap RULE C
--    warns about, except split across two siblings instead of one -- each sibling is
--    current on a DIFFERENT axis and stale on the other. The function below is built by
--    combining the fix each sibling actually has, not by wholesale-copying either one:
--    app.assert_actor_is_session_identity(p_actor_auth_user_id) is unconditionally the
--    first executable statement (RULE A, non-negotiable per this task's own instructions,
--    independent of what capture_forecast_snapshot currently does), and the not-found
--    branch folds in app.has_active_tenant_membership exactly as capture_forecast_snapshot's
--    current (20260902200000) body does, so this brand-new function does not reintroduce
--    the already-fixed ISS-2026-146 cross-tenant-disclosure gap that get_sales_target_actual
--    itself still has today.
--
-- Pagination (REQUIRED STEP 8): the original `.from()` read carried no `.range()`/limit at
-- all. No other read/list function exists directly over app.forecast_snapshots to mirror.
-- The closest same-remediation-effort sibling with an identical "list children of one
-- parent, actor-scoped, no pre-existing pagination shape to match" shape is
-- app.list_activities_for_record
-- (supabase/migrations/20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:
-- 1266-1298), which adds a safety-bounded `p_limit integer default 200` clamped via
-- `limit least(coalesce(p_limit, 200), 200)`. The same shape is used below. Disclosed as
-- an open question: app.forecast_snapshots is naturally low-cardinality in practice (one
-- row per explicit `capture_forecast_snapshot` call, not a high-frequency event log like
-- activities), so a 200 cap is very unlikely to ever bind, but this mirrors the
-- established convention rather than leaving the read fully unbounded.
--
-- Shape/style precedent imitated for the general SECURITY DEFINER function shape and the
-- Option-2 wrapper: app.list_api_keys_for_tenant's CURRENT (patched) shape --
-- 20260719150000_create_api_key_webhook_primitives.sql:563 for the original, and
-- 20260730510000_harden_actor_identity_unchecked_authority_surface.sql for the
-- assert-call patch that made it current -- and, more directly, app.list_activities_for_record
-- above (same migration, same remediation effort, same "list children of one
-- can_access_record-scoped parent" shape).
--
-- Option-2 public.* wrapper grants follow the ISS-2026-309-corrected pattern
-- (20260902075500_fix_iss2026309_class_wrapper_grant_parity_for_new_functions.sql /
-- 20260830200000_correct_public_wrapper_grant_parity.sql): `revoke execute ... from anon,
-- authenticated, service_role, public` (all four, since this project's own
-- `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon, authenticated,
-- service_role` grants `anon`/`authenticated` EXECUTE directly at CREATE FUNCTION time --
-- a bare `revoke ... from public` never touches those) before re-granting only the roles
-- the app.* counterpart itself grants to.
-- ===========================================================================

-- ===========================================================================
-- app.list_forecast_snapshots_for_target / public.list_forecast_snapshots_for_target
-- ===========================================================================

create function app.list_forecast_snapshots_for_target(
  p_sales_target_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.forecast_snapshots
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_target app.sales_targets;
begin
  -- RULE A (ISS-2026-017/032, HDN-372/373): must be the first executable statement,
  -- before any lookup or authority check -- imitates app.get_sales_target_actual's own
  -- current (20260810400000) placement. Unconditional here regardless of
  -- app.capture_forecast_snapshot's own current gap (see header, point 5b).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_target from app.sales_targets where id = p_sales_target_id;
  -- ISS-2026-146 tenant-id-disclosure-safe shape, imitating app.capture_forecast_snapshot's
  -- current (20260902200000) not-found branch: fold the tenant-membership pre-check into
  -- the SAME generic "not found" message/errcode a genuinely nonexistent id would already
  -- produce, so a caller with no relationship at all to the target's tenant cannot
  -- distinguish "no such target" from "target exists in a tenant I don't belong to".
  if not found or not app.has_active_tenant_membership(v_target.tenant_id, p_actor_auth_user_id) then
    raise exception 'sales_target_not_found: %', p_sales_target_id using errcode = 'no_data_found';
  end if;

  -- Verbatim reproduction of forecast_snapshots_select_scoped's own EXISTS/can_access_record
  -- predicate (RULE B: confirmed current, never ALTER'd -- see header), evaluated once
  -- against the single parent sales_target row (every forecast_snapshots row for this
  -- p_sales_target_id shares the exact same tenant_id/owner_user_id/org_unit_id by
  -- construction -- sales_target_id is a NOT NULL FK to app.sales_targets.id, a primary
  -- key -- so checking it once here is equivalent to the policy's own per-row EXISTS).
  -- A same-tenant caller who simply lacks record-level access (wrong owner/org-unit scope)
  -- gets this distinct, more specific message -- this does not disclose cross-tenant
  -- existence, only that the caller's own tenant has a target they cannot reach.
  if not app.can_access_record(p_actor_auth_user_id, v_target.tenant_id, v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales target %', p_actor_auth_user_id, p_sales_target_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select *
  from app.forecast_snapshots
  where sales_target_id = p_sales_target_id
  order by snapshot_at desc, id
  limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_forecast_snapshots_for_target is
  'CG-AUDIT-2026-09-02 O1 remediation: replaces the broken .from("forecast_snapshots") read at server/queries/pipeline.ts:112 (app schema not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A). Authority: looks up the single parent app.sales_targets row and raises the generic sales_target_not_found (no_data_found) message both when the row genuinely does not exist AND when the actor has no active tenant membership in its tenant (ISS-2026-146 cross-tenant-disclosure-safe fold, matching app.capture_forecast_snapshot''s current 20260902200000 body) -- only then applies app.can_access_record (forecast_snapshots_select_scoped''s own predicate, 20260723180000, never ALTER''d) to gate record-level access, raising insufficient_authority on failure. Returns every column of app.forecast_snapshots (no exclusions -- this table carries no masked/sensitive column), most recent snapshot_at first, bounded to at most 200 rows (p_limit, default+cap 200; the original .from() read this replaces carried no bound at all -- see this file''s own header and the accompanying structured-output openQuestions).';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_forecast_snapshots_for_target with an identical grant set,
-- never a reimplementation.
create function public.list_forecast_snapshots_for_target(
  p_sales_target_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.forecast_snapshots
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_forecast_snapshots_for_target(p_sales_target_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_forecast_snapshots_for_target is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_forecast_snapshots_for_target with an identical grant set, never a reimplementation.';

-- app.list_forecast_snapshots_for_target grants -- mirrors this exact table's own
-- sibling functions (app.capture_forecast_snapshot, app.get_sales_target_actual, both
-- "to authenticated, service_role") and the table's own direct grant
-- (`grant select on app.forecast_snapshots to authenticated, service_role;`,
-- 20260723180000, line 1264).
revoke execute on function app.list_forecast_snapshots_for_target(uuid, uuid, integer) from public;
grant execute on function app.list_forecast_snapshots_for_target(uuid, uuid, integer) to authenticated, service_role;

-- public.list_forecast_snapshots_for_target grants -- ISS-2026-309-corrected pattern:
-- revoke from anon, authenticated, service_role, AND public explicitly (a bare "from
-- public" never touches this project's own default anon/authenticated EXECUTE grant on
-- newly created public.* functions), then grant back only the roles the app.*
-- counterpart itself holds (authenticated, service_role -- never anon).
revoke execute on function public.list_forecast_snapshots_for_target(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_forecast_snapshots_for_target(uuid, uuid, integer) to authenticated, service_role;

-- ============================================================================
-- TS INTEGRATION:
-- ============================================================================
-- File: server/queries/pipeline.ts, function listForecastSnapshotsForTarget (currently
-- lines 111-122).
--
-- 1. Change the function's `client` parameter type from `PipelineQueryTableClient`
--    (`Pick<SupabaseClient, "from">`) to the already-exported `PipelineQueryRpcClient`
--    (`Pick<SupabaseClient, "rpc">`, defined at the top of this same file and already
--    used by `getPipelineSummary`/`getSalesTargetActual`).
--
-- 2. Add a new required parameter `actorAuthUserId: string`, positioned after
--    `salesTargetId` -- matching `getSalesTargetActual`''s own existing ordering
--    (`client, salesTargetId, actorAuthUserId`) immediately above it in this same file.
--    New signature:
--      export async function listForecastSnapshotsForTarget(
--        client: PipelineQueryRpcClient,
--        salesTargetId: string,
--        actorAuthUserId: string,
--      ): Promise<ForecastSnapshot[]>
--
-- 3. Replace the function body''s `.from(...)` chain with an `.rpc()` call to the new
--    `list_forecast_snapshots_for_target` RPC, passing exactly these p_* arguments
--    (named-args rpc() call, so order is not semantically load-bearing, but match this
--    order for readability/consistency with the SQL declaration):
--      const { data, error } = await client.rpc("list_forecast_snapshots_for_target", {
--        p_sales_target_id: salesTargetId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--      if (error) {
--        throw new PipelineQueryError(error.message);
--      }
--      if (!Array.isArray(data)) {
--        throw new PipelineQueryError("list_forecast_snapshots_for_target returned a non-array result");
--      }
--      return data.map((row) => parseForecastSnapshot(row as Record<string, unknown>));
--    (`p_limit` is intentionally omitted -- the RPC''s own `default 200` applies; only pass
--    it explicitly if a future caller needs a different bound.)
--    `parseForecastSnapshot` (server/contracts/pipeline/pipeline.ts:312-324) already maps
--    every snake_case column this RPC returns (id, tenant_id, sales_target_id,
--    computed_value, override_value, override_reason, snapshot_at, created_by,
--    created_at) to the existing camelCase `ForecastSnapshot` contract 1:1 -- no contract
--    change needed, since `returns setof app.forecast_snapshots` yields the identical
--    column set the old `.select("*")` did.
--
-- 4. Update the one call site:
--    app/(tenant)/[tenantSlug]/commercial/pipeline/[planId]/page.tsx:50, inside the
--    `targets.map(async (target) => { const [actual, snapshots] = await Promise.all([...]) })`
--    block --
--      `listForecastSnapshotsForTarget(supabase, target.id)`
--      -> `listForecastSnapshotsForTarget(supabase, target.id, access.authUserId)`
--    `access.authUserId` is already in scope and already passed one line above into the
--    sibling `getSalesTargetActual(supabase, target.id, access.authUserId)` call in the
--    SAME `Promise.all` -- no new value needs to be threaded in. Note this RPC can now
--    throw `PipelineQueryError` (sales_target_not_found / insufficient_authority)
--    exactly as `getSalesTargetActual` already can at this exact call site today (neither
--    call in this `Promise.all` is individually wrapped in a local try/catch) -- this
--    introduces no new failure-mode class beyond what the page already accepts from its
--    sibling call.
--
-- 5. server/queries/pipeline.test.ts''s existing `listForecastSnapshotsForTarget` describe
--    block (currently lines 188-195) builds a fake `.from()`-chain client via
--    `fakeTableClient({ data: [VALID_SNAPSHOT_ROW], error: null })` and calls
--    `listForecastSnapshotsForTarget(client, TARGET_ID)` (2 args). Update it to the same
--    `{ async rpc() { return { data, error }; } }` fake shape the adjacent
--    `describe("getSalesTargetActual", ...)` block (lines 125-135) already uses, e.g.:
--      const client = {
--        async rpc() {
--          return { data: [VALID_SNAPSHOT_ROW], error: null };
--        },
--      } as unknown as PipelineQueryRpcClient;
--      const snapshots = await listForecastSnapshotsForTarget(client, TARGET_ID, ACTOR_ID);
--    passing the already-defined `ACTOR_ID` constant (line 21 of that file, already used
--    by the `getSalesTargetActual` test) as the new third argument.
-- ============================================================================
-- ===========================================================================
-- app.pipeline_categories remediation -- Option-2 RPC surface
-- (app is not exposed to PostgREST; supabase/config.toml only exposes
-- "public"/"graphql_public")
-- ===========================================================================
--
-- Replaces the one broken `.from("pipeline_categories")` read in
-- server/queries/pipeline.ts:127 (listPipelineCategories). create_pipeline_category/
-- update_pipeline_category are mutations (already exist, unaffected); no list read
-- for this table existed before this migration.
--
-- TARGET: app.pipeline_categories is a REAL BASE TABLE (confirmed via
-- `grep -n "create table app.pipeline_categories"` -- one hit only, no
-- "create view"/"create materialized view" hit for this name anywhere in
-- supabase/migrations/*.sql), created at
-- supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql:307-319:
--   id uuid, tenant_id uuid, code text, label text, sort_order integer,
--   is_active boolean, record_version integer, created_by text,
--   created_at timestamptz, updated_at timestamptz
-- No later `alter table app.pipeline_categories add/drop/alter column` statement
-- exists anywhere in supabase/migrations/*.sql (grepped "alter table
-- app.pipeline_categories" repo-wide) -- the column list above is still current.
-- All 10 columns map 1:1 to PipelineCategorySchema / parsePipelineCategory
-- (server/contracts/pipeline/pipeline.ts:44-55,259-272); the table carries no
-- hash/secret/masked column, so `select *` is preserved verbatim -- no column
-- exclusion is needed or applied.
--
-- RULE B (RLS predicate currency): `grep -n "create policy.*pipeline_categories"`
-- finds the original policy at 20260723180000_create_commercial_sales_pipeline.sql
-- :1221-1223 (`app.has_active_tenant_membership(tenant_id)` alone). A repo-wide
-- `grep -n "alter policy.*pipeline_categories"` AND `grep -n
-- "pipeline_categories_select_scoped"` across every file in
-- supabase/migrations/*.sql, sorted by filename, finds exactly ONE later rewrite --
-- 20260730560000_harden_customer_user_layer_default_deny.sql:286-287:
--   using ((app.has_active_tenant_membership(tenant_id)
--           AND NOT app.actor_holds_customer_user_layer(tenant_id)))
-- No hit in any migration dated after 20260730560000 (in particular,
-- 20260902200000_harden_tenant_id_disclosure_commercial.sql only touches
-- app.update_pipeline_category's function body, never this policy). This IS the
-- current predicate and is what this migration's new function reproduces.
-- Note this table's altered policy, unlike app.accounts/app.org_units-with-supreme-
-- bypass-siblings, carries NO `OR app.is_supreme_admin()` clause -- reproduced
-- exactly, without inventing a broader bypass the live policy does not itself grant.
--
-- AUTHORITY-CHECK PRECEDENT (RULE C applied): modeled on app.list_accounts
-- (supabase/migrations/20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql
-- :279-309) -- the most recent, already-adversarially-reviewed function in this exact
-- repo doing "reproduce a has_active_tenant_membership-AND-NOT-actor_holds_customer_
-- user_layer RLS predicate inside a SECURITY DEFINER list function, with
-- assert_actor_is_session_identity as the first statement". That function's own RULE A
-- shape was itself checked against app.list_api_keys_for_tenant's CURRENT, patched body
-- at supabase/migrations/20260730510000_harden_actor_identity_unchecked_authority_
-- surface.sql:985-1007 (which added the assert call) -- NOT its stale pre-patch
-- original at 20260719150000_create_api_key_webhook_primitives.sql:563-585.
-- Explicitly checked and NOT followed as precedent: this table's own sibling mutation
-- functions app.create_pipeline_category (20260723180000:547-590, unchanged since) and
-- app.update_pipeline_category -- whose MOST RECENT `CREATE OR REPLACE` is
-- 20260902200000_harden_tenant_id_disclosure_commercial.sql:2834-2885, confirmed via
-- `grep -n "CREATE OR REPLACE FUNCTION app.update_pipeline_category"` across all
-- migrations -- STILL do not call app.assert_actor_is_session_identity even in that
-- latest body, despite taking an explicit p_actor_auth_user_id and being granted to
-- `authenticated` (see the public.create_pipeline_category/public.update_pipeline_category
-- wrappers in 20260826000000_create_public_api_data_wrappers.sql:8216-8231,40156-40171,
-- both granted to `authenticated`). That is an apparent still-open RULE A gap in those
-- two existing mutation functions, out of scope for this read-only remediation and NOT
-- copied forward here.
--
-- PAGINATION (rule 8): the original `.from()` call has no `.limit()` and no `is_active`
-- filter -- just `.eq("tenant_id", tenantId).order("sort_order", ascending: true)`. The
-- closest same-table sibling (list_finance_tax_codes, a small tenant reference-data list)
-- carries no limit/cap at all; the closest same-*remediation-batch* sibling
-- (app.list_accounts, above) clamps to `limit least(coalesce(p_limit, 200), 200)`. Since
-- pipeline_categories is admin-managed, per-tenant reference data with a uniqueness
-- constraint on (tenant_id, code) and is realistically always small, either convention is
-- defensible; this migration follows the newer, stricter list_accounts convention (a
-- defensive server-side cap, never a behavior change for any real tenant) -- flagged in
-- openQuestions as a judgment call, not a settled precedent match.
--
-- Grants: table grants `select` to `authenticated, service_role` (20260723180000:1261) --
-- this migration's app.* grant mirrors that exactly. Wrapper grants follow the
-- ISS-2026-309-corrected pattern (`revoke ... from anon, authenticated, service_role,
-- public` before re-granting only the intended subset), per
-- 20260902075500_fix_iss2026309_class_wrapper_grant_parity_for_new_functions.sql.
-- ===========================================================================

create function app.list_pipeline_categories(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.pipeline_categories
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A (ISS-2026-017/032, HDN-372/373): first executable statement, before any
  -- lookup or authority check -- the claimed actor must genuinely be the calling
  -- session, never merely an actor the caller asserts is allowed.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
    and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list pipeline categories for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select *
    from app.pipeline_categories
    where tenant_id = p_tenant_id
    order by sort_order asc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_pipeline_categories(uuid, uuid, integer) is
  'COM-146: tenant-scoped pipeline-category reference list, in display (sort_order) order, server-side clamped to <=200 rows regardless of what is requested (mirrors app.list_accounts'' own established cap convention -- COM-146''s own reference-data cardinality is realistically far smaller). Authority reproduces the CURRENT pipeline_categories_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer) as rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql -- confirmed via repo-wide grep that no later rewrite of this policy exists. NOTE: unlike app.margin_rule_versions, this predicate carries no SEPARATE "OR is_supreme_admin()" clause of its own -- but app.has_active_tenant_membership''s own CURRENT body (20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64-80) already ORs in a call to app.is_supreme_admin using that same actor id internally, so a global Supreme Admin with zero tenant_user_identities/app.users row for this tenant still passes has_active_tenant_membership transitively (and does not hold the customer_user layer either) -- i.e. a Supreme Admin IS granted access here too, just via that helper''s own bypass rather than a second, explicit one in this function''s own predicate. Live-verified against a real disposable database (scripts/db-tests/o1-query-layer-cluster0-batch2.sql): a first draft of that test wrongly assumed the opposite and was corrected after this exact behavior was observed live, not guessed. Raises insufficient_authority (never a silent empty page) when the actor has no standing for p_tenant_id at all (a non-member, non-supreme-admin actor), matching app.list_accounts/app.list_api_keys_for_tenant for this same "list for one named tenant" shape.';

create function public.list_pipeline_categories(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.pipeline_categories
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_pipeline_categories(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_pipeline_categories(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_pipeline_categories with an identical grant set, never a reimplementation.';

revoke execute on function app.list_pipeline_categories(uuid, uuid, integer) from public;
grant execute on function app.list_pipeline_categories(uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_pipeline_categories(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_pipeline_categories(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/pipeline.ts, function listPipelineCategories (currently line
-- ~127), currently typed to take `PipelineQueryTableClient` (a `Pick<SupabaseClient,
-- "from">`).
--
-- 1. Change its parameter's client type to `PipelineQueryRpcClient` (the
--    `Pick<SupabaseClient, "rpc">` alias already defined and already used by
--    getPipelineSummary/getSalesTargetActual above in this same file) -- OR add
--    `actorAuthUserId: string` as a new required parameter alongside the existing
--    `tenantId: string` if the function is kept on the `from`-client type union; either
--    way the caller must now also supply the acting user's auth_user_id, which this new
--    RPC requires and the old `.from()` call never did.
--
-- 2. Replace the body:
--      const { data, error } = await client
--        .from("pipeline_categories")
--        .select("*")
--        .eq("tenant_id", tenantId)
--        .order("sort_order", { ascending: true });
--    with:
--      const { data, error } = await client.rpc("list_pipeline_categories", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (p_limit is optional/defaulted server-side to 200 -- omit it unless a caller
--    genuinely needs a smaller page.)
--
-- 3. Keep the existing error handling (`if (error) throw new PipelineQueryError(...)`)
--    and the existing row mapping unchanged:
--      return (data ?? []).map((row: Record<string, unknown>) => parsePipelineCategory(row));
--    -- `list_pipeline_categories` returns `setof app.pipeline_categories`, whose columns
--    (id, tenant_id, code, label, sort_order, is_active, record_version, created_by,
--    created_at, updated_at) are exactly the columns parsePipelineCategory already reads,
--    so no contract/schema change is needed.
--
-- 4. Update every call site of `listPipelineCategories(client, tenantId)` to also pass
--    the acting user's auth_user_id (the same identity already threaded through this
--    file's other actor-scoped calls, e.g. getSalesTargetActual's `actorAuthUserId`
--    parameter) -- `listPipelineCategories(client, tenantId, actorAuthUserId)`.
-- ===========================================================================
-- ===========================================================================
-- app.win_loss_reasons -- Ø1 query-layer remediation (schema-exposure fix)
-- ===========================================================================
-- Replaces: server/queries/pipeline.ts:140 (listWinLossReasons) --
--   `select * from win_loss_reasons where tenant_id = :tenantId order by label asc`
--   via `.from()`, which 404s in production because supabase/config.toml only
--   exposes the "public"/"graphql_public" schemas to PostgREST -- "app" is
--   completely invisible to it.
-- Table: app.win_loss_reasons is a real BASE TABLE (created
--   20260723180000_create_commercial_sales_pipeline.sql:403), NOT a view --
--   confirmed no later "create or replace view"/"create materialized view" of
--   this name exists anywhere in supabase/migrations (grepped repo-wide). No
--   field-masking helper applies (no cost/margin/sell-price columns on this
--   table), so this is a plain, unmasked passthrough of every column the
--   original `.from()` `select("*")` already returned -- no column exclusions.
--
-- Authority rule enforced, and why:
--   RLS predicate (RULE B): `win_loss_reasons_select_scoped` was ORIGINALLY
--   created at 20260723180000:1225-1227 as
--     `for select to authenticated using (app.has_active_tenant_membership(tenant_id))`
--   Grepped repo-wide for "alter policy.*win_loss_reasons" and
--   "win_loss_reasons_select_scoped" across every supabase/migrations/*.sql
--   (sorted by filename): exactly ONE later rewrite exists,
--   20260730560000_harden_customer_user_layer_default_deny.sql:361-362:
--     `alter policy win_loss_reasons_select_scoped on app.win_loss_reasons
--        using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));`
--   That is the CURRENT, live predicate this function reproduces exactly --
--   membership AND NOT customer_user-layer. Unlike many sibling tables hardened
--   in that same migration (accounts, vehicle_*, sim_cards, etc.), the rewritten
--   win_loss_reasons predicate carries NO `OR app.is_supreme_admin()` branch --
--   confirmed by reading the literal text at line 362, which ends after the
--   `NOT app.actor_holds_customer_user_layer(tenant_id))` close-paren with no
--   trailing `OR`. So this function must NOT add a supreme-admin override either
--   (adding one would exceed the RLS envelope this fix must not exceed).
--
--   No named "check_pipeline_authority"/"check_win_loss_authority" helper
--   exists for this table (grepped "create (or replace )?function app\..*authority"
--   repo-wide) -- this table's own sibling mutations
--   (app.create_win_loss_reason at 20260723180000:1030 and
--   app.update_win_loss_reason, most recently replaced at
--   20260902200000_harden_tenant_id_disclosure_commercial.sql:3049) both inline
--   `app.has_active_tenant_membership(tenant_id, actor)` directly rather than
--   call a helper, so inlining the two-helper-call RLS predicate directly here
--   (has_active_tenant_membership AND NOT actor_holds_customer_user_layer) is
--   the established shape for this table, not an invented one.
--
--   RULE A / RULE C staleness check performed and NOT blindly trusted:
--   app.create_win_loss_reason (20260723180000, never replaced since) and the
--   CURRENT app.update_win_loss_reason body (confirmed via
--   `grep -n "CREATE OR REPLACE FUNCTION app.update_win_loss_reason"` -- most
--   recent hit is 20260902200000:3049, read in full) BOTH still lack any
--   `perform app.assert_actor_is_session_identity(...)` call, even in their most
--   current form -- these same-table sibling mutations are themselves stale
--   w.r.t. RULE A and are NOT used as precedent for the assert-call placement.
--   Likewise app.list_finance_tax_codes (a same-shape "small tenant reference
--   list, ordered by a natural key, no limit" precedent for the LIST SHAPE only
--   -- 20260729090000_create_finance_tax_baseline.sql:538, most recently
--   replaced at 20260810900000_harden_finance_authority_chain_tierc_completeness.sql:1492)
--   is likewise still missing the assert call even in its current, hardened
--   (added-SECURITY-DEFINER) form -- also not used as RULE-A precedent. The
--   actual RULE-A shape imitated here is app.list_accounts, itself authored in
--   this exact remediation effort's own prior batch
--   (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:279-309),
--   which puts `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);`
--   as the literal first executable statement, cross-checked against
--   app.list_api_keys_for_tenant's own CURRENT body
--   (20260730510000_harden_actor_identity_unchecked_authority_surface.sql:985-1007,
--   itself the most-recent CREATE OR REPLACE of that function -- confirmed via
--   `grep -n "CREATE OR REPLACE FUNCTION app.list_api_keys_for_tenant"`, no later
--   replace exists after that migration).
--
--   List-shape/pagination convention (research step 8): this is small,
--   tenant-admin-managed reference/master data (a handful of won/lost reason
--   codes per tenant, unique on (tenant_id, code)) -- the same shape as
--   app.list_finance_tax_codes and the sibling app.pipeline_categories table in
--   this same migration/domain, neither of which caps with `limit`; both simply
--   `order by <natural key>`. This function follows that same-domain,
--   same-shape convention (`order by label asc`, no limit) rather than the
--   `limit least(coalesce(p_limit, 200), 200)` convention used for
--   unbounded-growth operational tables (accounts, rfqs, invoices, api keys).
--   This also exactly reproduces the original `.from()` call's own
--   `.order("label", { ascending: true })` with no `.range()`/`.limit()` call.
--
-- Per ERR-2026-004: `revoke execute on all functions in schema app from public`
-- is this repo's own standing per-migration convention (already applied by the
-- migration that created this table, 20260723180000:1209) and is not repeated
-- here in isolation since it is schema-wide, not per-function -- an explicit
-- per-function `revoke ... from public` is nonetheless included below for this
-- function alone, matching this remediation effort's own established per-function
-- belt-and-suspenders style (20260908020000:331).
-- ===========================================================================

create function app.list_win_loss_reasons(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.win_loss_reasons
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
    and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list win/loss reasons for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select *
    from app.win_loss_reasons
    where tenant_id = p_tenant_id
    order by label asc;
end;
$$;

comment on function app.list_win_loss_reasons(uuid, uuid) is
  'Ø1 query-layer fix: replaces the broken server/queries/pipeline.ts:140 (listWinLossReasons) `.from("win_loss_reasons")` PostgREST read (app schema is not exposed to PostgREST). Tenant-wide win/loss reason list, label ascending -- no limit, matching this table''s own small tenant-admin-managed reference-data shape (mirrors app.list_finance_tax_codes''s no-limit, order-by-natural-key convention) and the original .from() call''s own .order("label") with no .range()/.limit(). Authority reproduces the CURRENT win_loss_reasons_select_scoped RLS predicate exactly (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, per 20260730560000_harden_customer_user_layer_default_deny.sql:361-362) -- this function''s own predicate carries no SEPARATE is_supreme_admin() clause, matching the live policy text verbatim, but app.has_active_tenant_membership''s own CURRENT body (20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64-80) already ORs in a call to app.is_supreme_admin using that same actor id internally -- so a global Supreme Admin with zero standing in this tenant still passes transitively (see app.list_pipeline_categories''s own comment, same table family, for the live-verified detail). Raises insufficient_authority (never a silent empty page) when the actor has no standing for p_tenant_id (a non-member, non-supreme-admin actor), matching app.list_accounts/app.list_api_keys_for_tenant precedent for this "list for one named tenant" call shape.';

create function public.list_win_loss_reasons(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.win_loss_reasons
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_win_loss_reasons(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_win_loss_reasons(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_win_loss_reasons with an identical grant set, never a reimplementation.';

revoke execute on function app.list_win_loss_reasons(uuid, uuid) from public;
grant execute on function app.list_win_loss_reasons(uuid, uuid) to authenticated, service_role;

-- ISS-2026-309: a bare `revoke ... from public` does NOT strip the `anon`/
-- `authenticated` EXECUTE grants Supabase's ALTER DEFAULT PRIVILEGES rule applies
-- to every new function in schema public at CREATE time -- revoke from all four
-- roles first, then re-grant only the same subset app.list_win_loss_reasons
-- itself grants (authenticated, service_role -- never anon, which the app.*
-- grant above never included either).
revoke execute on function public.list_win_loss_reasons(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_win_loss_reasons(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- RULE A / RULE B self-check (research step 10)
-- ===========================================================================
-- RULE A: `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);`
--   is the first statement inside `begin ... end` of app.list_win_loss_reasons
--   -- nothing (no lookup, no authority check) precedes it. The function takes
--   an explicit p_actor_auth_user_id and is granted to `authenticated`, so the
--   exception this rule guards against (service-role-only reachability) does
--   not apply here.
-- RULE B: grepped `alter policy.*win_loss_reasons` and the literal string
--   `win_loss_reasons_select_scoped` across every file in supabase/migrations/
--   (sorted by filename/date) -- exactly two hits total: the original CREATE
--   POLICY (20260723180000) and the one ALTER POLICY (20260730560000). No
--   later ALTER exists. The predicate this function enforces
--   (`has_active_tenant_membership(tenant_id, actor) AND NOT
--   actor_holds_customer_user_layer(tenant_id, actor)`, no is_supreme_admin
--   branch) is a line-for-line reproduction of that latest (and only later)
--   ALTER POLICY's `using` clause, with auth.uid() made an explicit
--   p_actor_auth_user_id argument (as every other SECURITY DEFINER function in
--   this codebase does, since a SECURITY DEFINER function has no live
--   auth.uid() session GUC of its own to fall back on).
-- ===========================================================================

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/pipeline.ts
--
-- 1. Change the client type parameter of `listWinLossReasons` from
--    `PipelineQueryTableClient` to `PipelineQueryRpcClient` (the same
--    `Pick<SupabaseClient, "rpc">` type already used by `getPipelineSummary`/
--    `getSalesTargetActual` above it in this file).
--
-- 2. The function signature must gain an explicit `actorAuthUserId: string`
--    parameter -- the new RPC requires it (both for the
--    assert_actor_is_session_identity actor-impersonation guard and for the
--    has_active_tenant_membership/actor_holds_customer_user_layer authority
--    check), whereas the old `.from()` call relied purely on the caller's own
--    RLS session and took no actor argument. New signature:
--      export async function listWinLossReasons(
--        client: PipelineQueryRpcClient,
--        tenantId: string,
--        actorAuthUserId: string,
--      ): Promise<WinLossReason[]>
--    (mirrors `getSalesTargetActual`'s own `(client, salesTargetId,
--    actorAuthUserId)` parameter-ordering convention in this same file.)
--    NOTE for whoever applies this mechanically: every existing call site of
--    `listWinLossReasons(...)` elsewhere in the codebase must be updated to
--    additionally pass the calling actor's auth user id -- grep
--    `listWinLossReasons(` repo-wide to find and update them.
--
-- 3. Replace the function body:
--      const { data, error } = await client
--        .from("win_loss_reasons")
--        .select("*")
--        .eq("tenant_id", tenantId)
--        .order("label", { ascending: true });
--    with:
--      const { data, error } = await client.rpc("list_win_loss_reasons", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (argument object keys must be exactly `p_tenant_id`, `p_actor_auth_user_id`
--    -- the new RPC's own parameter names, in the order they appear in the
--    `create function app.list_win_loss_reasons(p_tenant_id uuid,
--    p_actor_auth_user_id uuid)` signature above; supabase-js RPC calls take a
--    named-parameter object so declaration order does not itself matter, but
--    matching the names exactly does.)
--
-- 4. Everything after the client call is UNCHANGED: `if (error) { throw new
--    PipelineQueryError(error.message); }` stays as-is (the RPC's own
--    `insufficient_authority`/`insufficient_privilege` errors surface through
--    the same `error` object a `.from()` call would have used), and
--    `(data ?? []).map((row) => parseWinLossReason(row as
--    Record<string, unknown>))` is unchanged -- `returns setof
--    app.win_loss_reasons` yields the exact same snake_case row shape
--    (id, tenant_id, code, label, outcome, is_active, record_version,
--    created_by, created_at, updated_at) that `parseWinLossReason` already
--    expects, since this function selects every column of the base table with
--    no renaming, casting, or exclusion.
-- ===========================================================================
-- Final blanket revoke (ERR-2026-004 standing convention).
revoke execute on all functions in schema app from public;
