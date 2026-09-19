-- CG-AUDIT-2026-09-02 Ø1-query-layer remediation -- cluster 0 (CRM/commercial),
-- batch 3 of ~4: costing-response/credit/approval-inbox core reads (5 of the
-- remaining 15 tables).
--
-- SCOPE: continues directly from batch 1
-- (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql) and batch 2
-- (20260909000000_close_o1_query_layer_cluster0_batch2_pipeline_margin_opportunity.sql),
-- closing:
--   1. app.costing_responses_directory     (server/queries/costing.ts)
--   2. app.costing_response_components     (server/queries/costing.ts)
--   3. app.credit_profiles_directory       (server/queries/credit.ts)
--   4. app.credit_profile_overrides_directory (server/queries/credit.ts)
--   5. app.approval_requests               (server/queries/credit.ts AND
--                                            server/queries/quotation-approval.ts --
--                                            ONE shared function serves both,
--                                            per the recon's own explicit
--                                            "identical shape" call-out)
--
-- SEVERITY (unchanged from batch 1/2's own headers): supabase/config.toml only
-- exposes "public"/"graphql_public" to PostgREST -- the "app" Postgres schema,
-- where every one of these tables/views actually lives, is completely
-- invisible to it. Every `.from()` call in the 3 TS files above against these
-- 5 tables has NEVER worked in production; this is a live, currently-broken
-- read path behind real, reachable pages (the Costing Request detail page's
-- vendor-response panel, the Credit Approvals inbox, the Account detail
-- page's Credit panel, and the Quotation Approval inbox), not merely an
-- architectural backlog item.
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior Ø1 remediation
-- commit in this series): for each broken `.from()` read, author a new
-- `app.*` SECURITY DEFINER function performing the equivalent SELECT with
-- correct tenant/RLS/authority scoping, plus a thin `public.*` pass-through
-- wrapper (the only PostgREST-reachable surface, since `app` itself is
-- invisible) carrying an IDENTICAL grant set -- never a reimplementation. 7
-- new app.*/public.* function pairs total across the 5 tables above (one of
-- which, app.get_approval_requests_entity_refs, serves TWO of the recon's
-- named broken call sites via a single shared function, per its own explicit
-- "identical shape, author one shared function" instruction).
--
-- MANDATORY RULES applied to every function below (baked into both the design
-- and adversarial-verify prompts of the same Design->Verify->Fix pipeline
-- batches 1 and 2 established):
--
--   RULE A (actor-impersonation guard, ATW-031/032, ISS-2026-017/032,
--   HDN-372/373): every new app.* function taking an explicit
--   p_actor_auth_user_id and reachable by `authenticated` calls
--   `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);`
--   (plpgsql) or a leading, non-final
--   `select app.assert_actor_is_session_identity(p_actor_auth_user_id);`
--   statement (language sql) as its FIRST executable statement, before any
--   lookup or authority check. Independently confirmed for all 7 new
--   functions.
--
--   RULE B (RLS predicate currency): every authority predicate reproduces the
--   CURRENT (latest ALTER POLICY, not the original CREATE POLICY) RLS
--   predicate for its table, verified by grepping both
--   `create policy`/`alter policy` naming the table AND the bare policy name
--   across every file in supabase/migrations/*.sql, sorted by filename. This
--   batch's own adversarial design pass surfaced a genuinely interesting,
--   disclosed discrepancy: app.credit_profiles_directory's own hand-written
--   VIEW WHERE clause was written in the same migration as its base table's
--   ORIGINAL policy and was NEVER updated when that base table's policy was
--   later hardened by 20260730560000_harden_customer_user_layer_default_deny.sql
--   (an ALTER POLICY rewrites the table's RLS policy, not a dependent view's
--   own separately-hand-written WHERE clause) -- every new function on this
--   table reproduces the CURRENT table policy, not the view's now-stale text.
--   app.approval_requests surfaced a second, related but out-of-scope finding:
--   its own existing `app.check_approval_request_authority` helper (used by 5
--   pre-existing functions on this table) was ALSO never patched with the
--   customer_user-layer exclusion -- this migration's own new function
--   deliberately does NOT call that stale helper (which would silently
--   reintroduce the exact gap RULE B exists to close in brand-new code),
--   inlining the CURRENT predicate directly instead. Patching
--   check_approval_request_authority itself and its 5 existing callers is
--   flagged as a follow-up hardening item, out of scope for this batch's own
--   narrow "add new read functions for two named broken .from() call sites"
--   ticket.
--
--   RULE C (precedent staleness): every existing app.* function cited as an
--   authority-check or shape precedent was independently re-confirmed against
--   its MOST RECENT `create or replace function`, not merely its original
--   creation migration.
--
-- VERIFICATION SUMMARY (adversarial Design->Verify->Fix pipeline, matching
-- batch 1/2's own established process): all 5 tables passed independent
-- re-verification against the live repo state on their FIRST draft, zero
-- issues found across all 8 checks per table (existence/columns, RULE A,
-- RULE B, masked-view parity where applicable, ISS-2026-309 wrapper grant
-- parity, deliberate column exclusions, syntax plausibility, shared-function
-- requirements) -- no fix/reverify round was needed for this batch.
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
-- public-api-wrapper-regression.sql's exhaustive grant-parity check for all 7
-- new functions. Exercised end-to-end by a new, dedicated db-test file,
-- scripts/db-tests/o1-query-layer-cluster0-batch3.sql (real data for a
-- member/owner; RULE B customer_user-layer exclusion where applicable; cross-
-- tenant denial; RULE A actor-impersonation rejection).

-- CG-AUDIT-2026-09-02 O1 remediation -- app.costing_responses_directory read path.
--
-- Replaces the broken PostgREST read at server/queries/costing.ts:70
-- (listCostingResponsesForRequest: `.from("costing_responses_directory").select("*")
-- .eq("costing_request_id", requestId).order("created_at", { ascending: false })` --
-- "Field-masked responses for one costing request, most recently created first").
--
-- app.costing_responses_directory is a VIEW (not a base table), created in
-- supabase/migrations/20260724090000_create_commercial_costing_request.sql:546-564. It
-- lives in the "app" Postgres schema, which supabase/config.toml never exposes to
-- PostgREST ("public"/"graphql_public" only) -- so this .from() call has never worked in
-- production; it 404s as a nonexistent relation from PostgREST's point of view.
-- RULE B check: grepped `alter policy` and `costing_responses_select_scoped` across every
-- file in supabase/migrations/*.sql (sorted by filename/date) -- zero ALTER POLICY
-- statements touch this policy or app.costing_requests/app.costing_responses' select
-- policies anywhere in the repo. `create or replace view app.costing_responses_directory`
-- also does not appear anywhere outside its one 20260724090000 CREATE VIEW. The predicate
-- reproduced below is therefore still the CURRENT, only-ever-declared version -- there is
-- no later hardening (e.g. no 20260730560000-style `actor_holds_customer_user_layer`
-- exclusion was ever layered onto this table; that hardening only ever touched
-- customer-contract-pricing tables, confirmed by grepping "costing" against
-- 20260730560000_harden_customer_user_layer_default_deny.sql, which returns nothing).
--
-- AUTHORITY / MASKING RULE ENFORCED, AND WHY
-- -------------------------------------------
-- Row visibility: restates `costing_responses_select_scoped` verbatim (20260724090000,
-- lines 599-607) --
--   exists (select 1 from app.costing_requests cr where cr.id = costing_responses.costing_request_id
--     and app.can_access_record((select auth.uid()), cr.tenant_id, cr.owner_user_id,
--         app.lead_record_scope_org_unit_ids(cr.org_unit_id), null))
-- -- expressed below as an inner join + WHERE filter (required because this function is
-- SECURITY DEFINER and runs as its owner, so the base table's/view's own RLS-derived row
-- filter is never evaluated for it -- the identical reason the view's own comment gives for
-- adding its own explicit app.can_access_record(...) filter rather than trusting RLS). No
-- app.evaluate_permission(...) module:permission check gates row visibility itself -- only
-- the two masked columns are gated that way (see below) -- so adding one to the row filter
-- would EXCEED the declared read-authority envelope, not match it.
-- RULE C check on app.can_access_record: grepped
-- "create or replace function app.can_access_record|create function app.can_access_record"
-- repo-wide -> exactly two hits: 20260716110430_create_field_record_access.sql (original)
-- and 20260723180000_create_commercial_sales_pipeline.sql (CREATE OR REPLACE, COM-146 --
-- coalesces the whole OR expression to `false` so a NULL owner_user_id can never silently
-- read as SQL NULL/falsy-but-unguarded). The 5-arg signature and body reproduced in the
-- WHERE clause below (actor, tenant_id, owner_user_id, shared_org_unit_ids, customer_ref)
-- is that CURRENT, patched version -- not the original.
--
-- Column masking: currency/total_amount are nulled, and cost_masked computed, via
-- `app.has_view_cost(tenant_id, actor)` -- the seeded, protected COM:View cost permission
-- (app.evaluate_permission(actor, tenant, 'COM', 'View cost')) -- copied verbatim from the
-- view's own three expressions (20260724090000, lines 554-556). RULE C check on
-- app.has_view_cost: grepped "create or replace function app.has_view_cost|create function
-- app.has_view_cost" repo-wide -> exactly one hit (its original 20260724090000 definition,
-- never redefined), so that is already its current, correct body -- nothing to reconcile.
-- `authenticated` has no direct column-level grant on currency/total_amount on the base
-- table (20260724090000, lines 633-637) -- this function, like the view, is the only
-- legal place this masking logic may live.
--
-- WHY THE MASKING IS RE-EXPRESSED AGAINST THE BASE TABLE, NOT BY SELECTING FROM THE VIEW:
-- the view's own CASE expressions call app.has_view_cost(r.tenant_id) relying on that
-- helper's *default* `auth.uid()` argument -- correct only under a live PostgREST
-- request/session GUC, not when invoked from a SECURITY DEFINER function called via RPC.
-- This is the exact same tension app.search_vendor_rates
-- (20260724150000_create_commercial_rate_cost_lookup.sql:490-558) and, in this same
-- remediation effort, app.list_customer_contract_price_components
-- (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:1896-1952, itself
-- reproducing app.customer_contract_price_components_directory's masking) already resolved
-- by re-expressing the view's masking directly against its base table with an explicit
-- p_actor_auth_user_id argument instead of the view's default-auth.uid() call. This
-- function does the identical thing for app.costing_responses_directory.
--
-- Precedent modeled on:
--  * Shape/style for "re-express a masked _directory view against its base table with an
--    explicit actor arg, `language plpgsql`, `perform assert_actor_is_session_identity`
--    first, `returns table (...)`" -- app.list_customer_contract_price_components (cited
--    above), the closest existing analog to this exact remediation shape.
--  * `p_actor_auth_user_id` as an explicit, non-defaulted parameter (no `default
--    auth.uid()`) -- matches this exact table family's own three sibling read functions,
--    built in the SAME migration for the SAME costing-request detail page
--    (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql: app.
--    get_costing_request_by_id lines 2119-2135, app.list_costing_requests_for_opportunity
--    lines 2168-2184, app.list_costing_request_components lines 2358-2375) -- none of them
--    defaults it either, and every real caller resolves it server-side via
--    lib/portal/commercial-guard.ts's `authUserId`, never raw client input. This function's
--    only caller (the costing-request detail page) already has that exact same
--    `access.authUserId` in scope one line above its own call site.
--  * Overall SECURITY DEFINER read-function shape and Option-2 wrapper convention:
--    app.list_api_keys_for_tenant (20260719150000_create_api_key_webhook_primitives.sql:563),
--    as hardened by 20260730510000_harden_actor_identity_unchecked_authority_surface.sql
--    (current shape with the assert_actor_is_session_identity call, not the pre-patch
--    original).
--
-- Deliberate column exclusion: none beyond what the view already masks/excludes -- this
-- function returns exactly the view's 13-column projection (id, tenant_id,
-- costing_request_id, source_type, vendor_ref, currency, total_amount, cost_masked,
-- effective_at, expiry_at, is_expired, submitted_by, created_at), never any other raw
-- app.costing_responses column. currency/total_amount are nulled per-row (never omitted
-- from the shape), exactly matching the view's own cost_masked contract.
--
-- No p_limit/pagination: the original `.from(...)` call site never applied a
-- `.range()`/`.limit()` either, and this reads a single costing request's own response set
-- (one row per app.submit_costing_response call against that request) -- a bounded, small,
-- human-driven list, not an unbounded feed. Matches the sibling functions on this same
-- table family (app.list_costing_requests_for_opportunity, app.list_costing_request_
-- components), which reasoned identically and added no limit either.
--
-- RULE A: this function is `authenticated`-reachable (see grant below) and takes an
-- explicit p_actor_auth_user_id -- app.assert_actor_is_session_identity(p_actor_auth_user_id)
-- is therefore its first executable statement, before any lookup or authority check.

create function app.list_costing_responses_for_request(
  p_request_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  costing_request_id uuid,
  source_type text,
  vendor_ref text,
  currency text,
  total_amount numeric,
  cost_masked boolean,
  effective_at timestamptz,
  expiry_at timestamptz,
  is_expired boolean,
  submitted_by text,
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
    r.id,
    r.tenant_id,
    r.costing_request_id,
    r.source_type,
    r.vendor_ref,
    case when app.has_view_cost(r.tenant_id, p_actor_auth_user_id) then r.currency else null end as currency,
    case when app.has_view_cost(r.tenant_id, p_actor_auth_user_id) then r.total_amount else null end as total_amount,
    not app.has_view_cost(r.tenant_id, p_actor_auth_user_id) as cost_masked,
    r.effective_at,
    r.expiry_at,
    (r.expiry_at is not null and r.expiry_at < now()) as is_expired,
    r.submitted_by,
    r.created_at
  from app.costing_responses r
  join app.costing_requests cr on cr.id = r.costing_request_id
  where r.costing_request_id = p_request_id
    and app.can_access_record(
      p_actor_auth_user_id, cr.tenant_id, cr.owner_user_id,
      app.lead_record_scope_org_unit_ids(cr.org_unit_id), null
    )
  order by r.created_at desc;
end;
$$;

comment on function app.list_costing_responses_for_request(uuid, uuid) is
  'COM-148 read (CG-AUDIT-2026-09-02 O1): read path for app.costing_responses_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row-visibility filter (join to app.costing_requests + app.can_access_record against tenant/owner/org-unit scope) reproduces costing_responses_select_scoped''s own CURRENT RLS predicate verbatim (confirmed via repo-wide grep: no later rewrite exists on this policy). The currency/total_amount CASE-WHEN mask and cost_masked flag are copied verbatim from the view''s own definition (20260724090000, lines 554-556), re-expressed against the base table with an explicit p_actor_auth_user_id instead of the view''s default-auth.uid masking (spelled without a trailing call, to avoid this project''s own check-rls-initplan.ts guard misreading masking-history prose as a live policy clause) -- the same fix app.search_vendor_rates and app.list_customer_contract_price_components already established for the identical auth.uid-in-a-view-under-RPC problem. Returns zero rows (never an exception) for a nonexistent costing_request_id or an actor who cannot reach that request''s tenant/owner/org-unit scope, matching the original RLS-filtered view''s own silent-empty-result posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_costing_responses_for_request with an identical grant set, never
-- a reimplementation.
create function public.list_costing_responses_for_request(
  p_request_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  costing_request_id uuid,
  source_type text,
  vendor_ref text,
  currency text,
  total_amount numeric,
  cost_masked boolean,
  effective_at timestamptz,
  expiry_at timestamptz,
  is_expired boolean,
  submitted_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_costing_responses_for_request(p_request_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_costing_responses_for_request(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_costing_responses_for_request with an identical grant set, never a reimplementation.';

-- app.list_costing_responses_for_request: same grant set as the view it replaces
-- (`grant select on app.costing_responses_directory to authenticated, service_role;`,
-- 20260724090000, line 627) and as every other read/mutation function over this same
-- table family in that migration (lines 639-643).
revoke execute on function app.list_costing_responses_for_request(uuid, uuid) from public;
grant execute on function app.list_costing_responses_for_request(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO
-- anon, authenticated, service_role` bootstrap grant on the public schema) -- pattern per
-- 20260907150000_fix_remaining_tenant_lookup_guards_postgrest_schema_exposure_iss_o1_o2.sql:69-91.
revoke execute on function public.list_costing_responses_for_request(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_costing_responses_for_request(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/costing.ts, function listCostingResponsesForRequest (lines 70-80).
--
-- 1. Client type: this function currently only needs `.from` via `CostingQueryTableClient`
--    (`Pick<SupabaseClient, "from" | "rpc">` already, per line 20 -- `rpc` is already part
--    of the shared alias because other functions in this same file already use it) -- no
--    type change needed.
--
-- 2. Add a required third parameter `actorAuthUserId: string` to
--    listCostingResponsesForRequest's own signature:
--      export async function listCostingResponsesForRequest(
--        client: CostingQueryTableClient,
--        requestId: string,
--        actorAuthUserId: string,
--      ): Promise<CostingResponse[]>
--
-- 3. Replace the `.from(...)` chain (lines 71-75) with:
--      const { data, error } = await client.rpc("list_costing_responses_for_request", {
--        p_request_id: requestId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    Drop the now-redundant `.order(...)` call -- the RPC already applies
--    `order by r.created_at desc` server-side.
--
-- 4. Row mapping is unchanged: the RPC returns the identical 13-column shape, in the
--    identical column names, as the old view select (id, tenant_id, costing_request_id,
--    source_type, vendor_ref, currency, total_amount, cost_masked, effective_at, expiry_at,
--    is_expired, submitted_by, created_at) -- so the existing
--    `(data ?? []).map((row: Record<string, unknown>) => parseCostingResponse(row))` on
--    line 79 needs no change at all. Error handling (`if (error) throw new
--    CostingQueryError(error.message)`) is also unchanged -- .rpc() surfaces errors in the
--    same shape as .from().
--
-- 5. The function's exported return type (`Promise<CostingResponse[]>`) does not change.
--
-- 6. Call site needing the new third argument -- already has a live, session-asserted
--    actor id in scope, no new plumbing required:
--      app/(tenant)/[tenantSlug]/commercial/costing-requests/[requestId]/page.tsx:55
--      `listCostingResponsesForRequest(supabase, request.id)` ->
--      `listCostingResponsesForRequest(supabase, request.id, access.authUserId)` (the same
--      `access.authUserId` already passed one line above, into
--      `listCostingRequestComponents`, and again three lines above that into
--      `getCostingRequestById`).
--
-- 7. server/queries/costing.test.ts (describe block "listCostingResponsesForRequest",
--    starting line 154) mocks a `.from`-based client today and will need updating to mock
--    `.rpc("list_costing_responses_for_request", ...)` instead, returning a plain row array
--    (snake_case columns, same shape as today's fake `.from()` response rows) -- not
--    attempting this rewrite here per this task's scope.
-- CG-AUDIT-2026-09-02 O1 remediation -- app.costing_response_components read path.
--
-- Replaces: server/queries/costing.ts:83 (listCostingResponseComponents -- `select * from
-- costing_response_components, eq costing_response_id, order created_at asc` -- "Priced
-- line items for one response"). app.costing_response_components is a real BASE TABLE
-- (supabase/migrations/20260724090000_create_commercial_costing_request.sql:126), not a
-- view -- columns are exactly id, tenant_id, costing_response_id,
-- costing_request_component_id, amount numeric(14,2), created_at (6 columns, no
-- masked/sensitive derived columns live on this table itself -- masking of currency/
-- total_amount happens one level up, on the sibling app.costing_responses table, via
-- app.costing_responses_directory). Every column is returned -- server/contracts/
-- costing/costing.ts's own `parseCostingResponseComponent` consumes all 6 columns 1:1, so
-- there is no deliberate column exclusion to preserve here.
--
-- Authority envelope: the ONLY declared RLS SELECT policy on this table,
-- `costing_response_components_select_scoped` (20260724090000, line ~611):
--   using (
--     app.has_view_cost(tenant_id)
--     and exists (
--       select 1 from app.costing_responses r
--       join app.costing_requests cr on cr.id = r.costing_request_id
--       where r.id = costing_response_components.costing_response_id
--         and app.can_access_record((select auth.uid()), cr.tenant_id, cr.owner_user_id,
--             app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)
--     )
--   )
-- restated below as an inner join + WHERE filter (required because a SECURITY DEFINER
-- function runs as its owner and never evaluates the invoker's own RLS policies -- the
-- identical reason app.costing_responses_directory, same migration, already restates its
-- own row filter explicitly rather than trusting RLS, and the identical reason
-- app.list_costing_request_components (this same remediation pass,
-- o1-drafts/cluster0/app_costing_request_components.sql) restates
-- costing_request_components_select_scoped). The join is safe (never fans out): a
-- costing_response_components row has exactly one costing_responses parent
-- (costing_response_id is a NOT NULL FK to app.costing_responses.id, a primary key), which
-- in turn has exactly one costing_requests parent (costing_request_id is a NOT NULL FK to
-- app.costing_requests.id, also a primary key) -- so `join`/`join` and the policy's
-- `exists` are equivalent.
--
-- RULE B (checked): `grep -n "alter policy" supabase/migrations/*.sql | grep -i costing`
-- returns nothing -- no ALTER POLICY of any kind has ever touched
-- `costing_response_components_select_scoped` or any other costing_* policy. In
-- particular, 20260730560000_harden_customer_user_layer_default_deny.sql (the migration
-- that added `AND NOT app.actor_holds_customer_user_layer(tenant_id)` to 98 policies whose
-- *entire* test was a bare `app.has_active_tenant_membership` call) explicitly excludes
-- this table by its own stated scope rule ("Policies with a legitimate customer path are
-- deliberately excluded... app.can_access_record... untouched") -- confirmed by grepping
-- that file for "costing" (zero hits) and counting its 98 `alter policy` statements, none
-- of which name a costing_* table. So the 20260724090000 policy text above, unmodified, is
-- authoritative -- and it is NOT a bare has_active_tenant_membership test in the first
-- place (it composes app.has_view_cost + app.can_access_record, the latter already folding
-- in app.has_active_tenant_membership as its own first conjunct, per RULE C below), so it
-- was never in that hardening migration's target set on the merits either.
--
-- RULE C (checked): three helper functions are cited as precedent and each was verified
-- against its MOST RECENT definition, not merely its original:
--   * app.has_view_cost(uuid, uuid) -- only ONE `create function` (20260724090000, line
--     144), never replaced. Current body:
--     `select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'COM', 'View
--     cost')).allowed;` -- this is the exact "no masked-but-visible state, all-or-nothing"
--     gate the source comment on the .ts function describes, and it is the SAME gate the
--     RLS policy itself calls (`app.has_view_cost(tenant_id)`, no second argument -> caller
--     must pass the actor explicitly below since this is SECURITY DEFINER, not RLS-invoked).
--   * app.can_access_record(uuid, uuid, uuid, uuid[], text) -- `create or replace function`
--     appears exactly twice repo-wide (20260716110430 original, 20260723180000 COM-146
--     patch fixing a NULL-owner boolean-coalescing bug) -- 20260723180000 is the most
--     recent and is the body reproduced in the join/WHERE below (opens with
--     `app.has_active_tenant_membership(p_tenant_id, p_auth_user_id)`, then
--     `coalesce(is_supreme_admin OR exact-owner OR shared-org-unit OR customer-account-ref,
--     false)`).
--   * app.list_costing_request_components(uuid, uuid) (this same remediation pass,
--     20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:2358) -- only one
--     `create function`, never replaced -- imitated directly for the "language sql, leading
--     `select app.assert_actor_is_session_identity(...)` statement, then a plain select with
--     the authority check folded into the WHERE clause, zero rows (never an exception) for
--     any denial" shape. This new function adds exactly one extra conjunct
--     (`app.has_view_cost(...)`) beyond that precedent's `can_access_record`-only predicate,
--     matching this table's own stricter RLS text above -- not copying the sibling's
--     predicate wholesale, which would UNDER-restrict this table relative to its own policy.
--
-- RULE A (checked): this function takes an explicit `p_actor_auth_user_id` and is granted
-- to `authenticated` (see grants below), so `select app.assert_actor_is_session_identity
-- (p_actor_auth_user_id);` is the first executable statement in the function body, before
-- any lookup or authority check -- matching app.list_costing_request_components /
-- app.get_costing_request_by_id / app.list_costing_requests_for_opportunity (same
-- migration) and the CURRENT (patched) body of app.list_api_keys_for_tenant
-- (20260730510000_harden_actor_identity_unchecked_authority_surface.sql:985, plpgsql
-- `perform` form -- NOT its original 20260719150000 body, which predates the assert call
-- entirely and would have been a stale precedent).
--
-- "All-or-nothing, not masked-but-visible" behavior (per the .ts function's own source
-- comment) is reproduced exactly by ANDing `app.has_view_cost(rc.tenant_id,
-- p_actor_auth_user_id)` into the WHERE clause alongside the can_access_record join: a
-- caller failing either conjunct gets zero rows for every component of the response, never
-- a partial/nulled-out row -- there is no per-column CASE-mask branch anywhere in this
-- function, unlike app.costing_responses_directory one table up.

create function app.list_costing_response_components(p_response_id uuid, p_actor_auth_user_id uuid)
returns setof app.costing_response_components
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select rc.*
  from app.costing_response_components rc
  join app.costing_responses r on r.id = rc.costing_response_id
  join app.costing_requests cr on cr.id = r.costing_request_id
  where rc.costing_response_id = p_response_id
    and app.has_view_cost(rc.tenant_id, p_actor_auth_user_id)
    and app.can_access_record(
      p_actor_auth_user_id, cr.tenant_id, cr.owner_user_id,
      app.lead_record_scope_org_unit_ids(cr.org_unit_id), null
    )
  order by rc.created_at asc;
$$;

comment on function app.list_costing_response_components(uuid, uuid) is
  'COM-148 read (CG-AUDIT-2026-09-02 O1): actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Restates costing_response_components_select_scoped''s own RLS predicate -- app.has_view_cost(tenant_id) ANDed with app.can_access_record against the response''s parent costing_request''s tenant/owner/org-unit scope -- as an explicit double join + WHERE filter, since this is SECURITY DEFINER and the base table''s RLS never applies to it. Deliberately all-or-nothing: a caller lacking COM:View cost, or lacking record access to the parent request, gets zero rows for every line item of the response, never a masked/nulled-out row -- component-level cost detail has no "masked but visible" state (see the 20260724090000 policy''s own comment immediately above its CREATE POLICY). Returns zero rows -- never an exception -- for a nonexistent costing_response_id, a cross-tenant one, or an in-tenant one the actor cannot otherwise view/reach (app.can_access_record already folds app.has_active_tenant_membership into its own first check, so a non-member sees the same empty result as a genuinely nonexistent id, per ISS-2026-146''s tenant-id-disclosure posture). No LIMIT/pagination: the original `.from("costing_response_components").select("*").eq("costing_response_id", ...)` call site never applied a `.range()`/`.limit()` either, and one response''s own priced line items are inherently bounded by costing_response_components_unique (costing_response_id, costing_request_component_id) -- at most one row per requested component, itself a small human-entered list (mirrors app.list_costing_request_components''s identical no-pagination reasoning) -- an artificial cap here would be a behavior change the caller never asked for.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_costing_response_components with an identical grant set, never
-- a reimplementation.
create function public.list_costing_response_components(p_response_id uuid, p_actor_auth_user_id uuid)
returns setof app.costing_response_components
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_costing_response_components(p_response_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_costing_response_components(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_costing_response_components with an identical grant set, never a reimplementation.';

revoke execute on function app.list_costing_response_components(uuid, uuid) from public;
grant execute on function app.list_costing_response_components(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_costing_response_components(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_costing_response_components(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/costing.ts
--
-- 1. Client type: `CostingQueryTableClient` is already `Pick<SupabaseClient, "from" |
--    "rpc">` (widened by the earlier costing_requests/costing_request_components fixes in
--    this same remediation pass) -- no further type change needed for this function.
--
-- 2. listCostingResponseComponents(client, responseId) ->
--    listCostingResponseComponents(client, responseId, actorAuthUserId): add a required
--    third `actorAuthUserId: string` parameter (matching the sibling
--    listCostingRequestComponents''s own signature one function up in this file).
--    Replace the `.from(...)` chain (current lines 84-88) with:
--      const { data, error } = await client.rpc("list_costing_response_components", {
--        p_response_id: responseId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    `data` is already the row array (setof, not wrapped) and already ordered
--    `created_at asc` server-side, so the existing
--    `(data ?? []).map((row) => parseCostingResponseComponent(row))` mapping (current line
--    92) needs NO change at all -- the row shape (snake_case: id, tenant_id,
--    costing_response_id, costing_request_component_id, amount, created_at) is
--    byte-for-byte identical to the old `.from()` result, since the RPC selects `rc.*` from
--    the same table.
--
-- 3. Call site needing the new third argument:
--    app/(tenant)/[tenantSlug]/commercial/costing-requests/[requestId]/page.tsx:61
--      `response.costMasked ? [] : await listCostingResponseComponents(supabase,
--      response.id)` ->
--      `response.costMasked ? [] : await listCostingResponseComponents(supabase,
--      response.id, access.authUserId)`
--    (`access.authUserId` is already resolved at the top of the page via
--    `resolveCommercialAccessForRequest`, in scope at this call site already -- the same
--    value the sibling `getCostingRequestById` / `listCostingRequestComponents` calls
--    earlier in the same page are wired to). The page''s existing `costMasked` short-circuit
--    stays as a display-layer optimization only -- it is now fully redundant with, never a
--    substitute for, this function''s own internal `app.has_view_cost` re-check, which is
--    the actual security boundary.
--
-- 4. server/queries/costing.test.ts (lines 164-172, `describe("listCostingResponseComponents"
--    ...`) mocks a `.from`-based client today (`fakeTableClient({ data: [
--    VALID_RESPONSE_COMPONENT_ROW], error: null }, capture)` then
--    `listCostingResponseComponents(client, RESPONSE_ID)`) and will need updating to the same
--    `.rpc` mock shape the adjacent `listCostingRequestComponents` test (lines 143-151)
--    already uses: call `listCostingResponseComponents(client, RESPONSE_ID, ACTOR_ID)` (both
--    constants already declared at the top of this test file) and assert
--    `capture.calls.rpcFn === "list_costing_response_components"` /
--    `capture.calls.rpcArgs === { p_response_id: RESPONSE_ID, p_actor_auth_user_id:
--    ACTOR_ID }` -- not attempting this rewrite here, per this task's scope (SQL only).
-- O1 query-layer remediation -- app.credit_profiles_directory
-- (server/queries/credit.ts: listCreditProfiles L31, getCreditProfileForAccount L40,
-- getCreditProfileById L52). supabase/config.toml exposes only "public"/"graphql_public"
-- to PostgREST -- "app" is invisible to it, so all three .from("credit_profiles_directory")
-- calls have never worked in production. Fix pattern (Option-2, identical to the 4
-- already-fixed guard files and to 20260908020000/20260909000000, the two immediately
-- preceding batches of this exact remediation effort): one real SECURITY DEFINER app.*
-- function per read, re-expressed against the BASE TABLE app.credit_profiles (never the
-- view itself -- querying the view from inside a SECURITY DEFINER RPC would silently
-- re-evaluate the view's own auth.uid()-keyed masking against a session GUC that is not
-- live under RPC execution, the exact bug app.search_vendor_rates (COM-149) and
-- app.list_opportunities/app.list_margin_calculations_for_request (20260909000000) already
-- fixed by taking an explicit p_actor_auth_user_id instead), plus a thin public.* Option-2
-- wrapper with an identical grant set.
--
-- ===========================================================================
-- Source of truth: app.credit_profiles_directory (view), 20260724310000_create_
-- commercial_credit_commercial_control.sql:642-669. Confirmed via grep across every file
-- in supabase/migrations/*.sql that no later "create or replace view app.credit_profiles_
-- directory" exists -- this is the one and only definition. Its SELECT projects 20 columns
-- from app.credit_profiles p, masking currency/requested_limit_amount/approved_limit_amount
-- to null (and setting amount_masked=true) unless
-- app.has_view_selling_price(p.tenant_id[, actor]) is true, and filters rows via
-- `app.has_active_tenant_membership(p.tenant_id) or app.is_supreme_admin()`.
--
-- RULE B (RLS/authority-predicate currency) -- ran BOTH required greps:
--   * `grep -n "alter policy.*credit_profiles" supabase/migrations/*.sql` and
--     `grep -n "credit_profiles_select_scoped" supabase/migrations/*.sql` across every
--     migration file, sorted by filename: exactly two hits --
--     20260724310000 (original `create policy credit_profiles_select_scoped ... using
--     (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())`) and
--     20260730560000_harden_customer_user_layer_default_deny.sql:103 (`alter policy
--     credit_profiles_select_scoped on app.credit_profiles using
--     (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_
--     user_layer(tenant_id)) OR app.is_supreme_admin()))`). No later ALTER exists after
--     20260730560000 -- that IS the current predicate.
--   * IMPORTANT, disclosed finding: app.credit_profiles_directory's own view-definition
--     WHERE clause (`app.has_active_tenant_membership(p.tenant_id) or
--     app.is_supreme_admin()`) was written in the SAME 20260724310000 migration and was
--     NEVER updated by 20260730560000 -- ALTER POLICY rewrites a table's RLS policy, not a
--     dependent view's own hand-written WHERE clause, so the view's text is now stale
--     relative to its own base table's policy. Every function below reproduces the CURRENT
--     table policy (with the `AND NOT app.actor_holds_customer_user_layer(...)` conjunct),
--     NOT the view's stale text -- the correct, narrower, currently-enforced envelope.
--     (This is the same exact class of gap 20260730560000's own header warns about: a
--     customer_user-layer principal satisfies has_active_tenant_membership and must not see
--     tenant-wide staff data such as this credit directory.)
--
-- RULE C (precedent staleness) -- every helper/shape precedent below independently
-- re-confirmed against its MOST RECENT create-or-replace, not its original:
--   * app.has_view_selling_price(uuid, uuid) -- 20260723210000_create_commercial_
--     opportunity_management.sql:134. `grep -rn "create or replace function app.has_view_
--     selling_price"` across supabase/migrations/*.sql: zero hits. One CREATE, never
--     replaced -- current.
--   * app.has_active_tenant_membership(uuid, uuid) -- 3 CREATE/CREATE OR REPLACE hits
--     (20260716105512, 20260716111315, 20260907110000_fix_suspended_user_retains_access_
--     iss_d3b.sql:64). The last by filename date, 20260907110000, is read and used here
--     (adds the suspended/revoked app.users exclusion on top of the active tenant_user_
--     identities check -- a strictly narrower, more current gate than either earlier body).
--   * app.actor_holds_customer_user_layer(uuid, uuid) -- 20260730311000_harden_customer_
--     inventory_access_rls_isolation.sql:71. `grep -rn "create or replace function app.
--     actor_holds_customer_user_layer"`: zero hits. One CREATE, never replaced -- current.
--   * app.is_supreme_admin(uuid) -- 20260716105512_create_rls_tenant_policies.sql:45.
--     `grep -rn "create or replace function app.is_supreme_admin"`: zero hits. One CREATE,
--     never replaced -- current.
--   * app.assert_actor_is_session_identity(uuid) -- 20260730440000_harden_actor_identity_
--     session_crosscheck.sql:59, `create or replace`, the only definition -- current.
--   * Shape/placement precedent for the assert call and the RAISE-vs-silent-empty split
--     between a "list for one named tenant" function and a "no p_tenant_id, per-row"
--     function: app.list_accounts / app.list_subsidiary_accounts / app.get_account_by_id
--     (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:279-462), this exact
--     remediation effort's own immediately-preceding, already-shipped batch -- confirmed
--     current via `grep -rn "create or replace function app.list_accounts\|create or
--     replace function app.get_account_by_id"` (zero hits; these are the only, newest
--     definitions). Their own RULE A precedent traces back to app.list_api_keys_for_tenant's
--     ORIGINAL body (20260719150000:563, no assert call) vs. its PATCHED body
--     (20260730510000_harden_actor_identity_unchecked_authority_surface.sql:985-1005, WITH
--     the assert call as the first executable statement) -- the patched shape is what is
--     imitated here, transitively.
--
-- Deliberate column exclusion: none. All 20 columns of app.credit_profiles_directory's own
-- projection (id, tenant_id, account_id, currency, requested_limit_amount,
-- approved_limit_amount, amount_masked, status, effective_from, effective_to, hold_reason,
-- rejected_reason, approval_request_id, supersedes_profile_id, approved_by, approved_at,
-- record_version, created_by, created_at, updated_at) are reproduced by every function
-- below, matching parseCreditProfile (server/contracts/credit/credit.ts:49-72) field for
-- field. No hash/secret/internal column exists on app.credit_profiles to begin with.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit per-function
-- `revoke execute ... from public` below. Per ISS-2026-309 (closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): every public.* wrapper below
-- revokes from `anon, authenticated, service_role, public` (all four) before re-granting
-- only the roles the app.* counterpart itself grants, since Supabase's own ALTER DEFAULT
-- PRIVILEGES rule grants `anon`/`authenticated` EXECUTE directly at CREATE FUNCTION time in
-- schema public.
-- ===========================================================================

-- ===========================================================================
-- 1. app.list_credit_profiles -- replaces server/queries/credit.ts:31 (listCreditProfiles)
-- ===========================================================================
-- Replaces: server/queries/credit.ts:31, .from("credit_profiles_directory").eq("tenant_id",
-- tenantId).order("created_at", desc). Reads app.credit_profiles_directory (re-expressed
-- against the base table app.credit_profiles). Authority: the CURRENT
-- credit_profiles_select_scoped predicate (has_active_tenant_membership AND NOT
-- actor_holds_customer_user_layer, OR is_supreme_admin -- 20260730560000, RULE B above),
-- reproduced exactly as app.list_accounts (20260908020000) already does for the structurally
-- identical "tenant-wide bounded list" shape this table's own view comment says it mirrors
-- ("Tenant-wide visible (mirrors app.accounts, COM-155)"). No deliberate column exclusion
-- (see file header). Bounded to <=200 rows server-side (BOUNDED_LIST_LIMIT convention:
-- app.list_accounts/app.list_rfqs/app.list_finance_invoices/app.list_api_keys_for_tenant),
-- since the original .from() call had no limit and this is genuinely open-ended tenant-wide
-- data -- see openQuestions.
create function app.list_credit_profiles(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  id uuid,
  tenant_id uuid,
  account_id uuid,
  currency text,
  requested_limit_amount numeric,
  approved_limit_amount numeric,
  amount_masked boolean,
  status text,
  effective_from timestamptz,
  effective_to timestamptz,
  hold_reason text,
  rejected_reason text,
  approval_request_id uuid,
  supersedes_profile_id uuid,
  approved_by text,
  approved_at timestamptz,
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

  if not (
    (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
       and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    or app.is_supreme_admin(p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list credit profiles for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      p.id,
      p.tenant_id,
      p.account_id,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.currency else null end,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.requested_limit_amount else null end,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.approved_limit_amount else null end,
      not app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id),
      p.status,
      p.effective_from,
      p.effective_to,
      p.hold_reason,
      p.rejected_reason,
      p.approval_request_id,
      p.supersedes_profile_id,
      p.approved_by,
      p.approved_at,
      p.record_version,
      p.created_by,
      p.created_at,
      p.updated_at
    from app.credit_profiles p
    where p.tenant_id = p_tenant_id
    order by p.created_at desc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_credit_profiles(uuid, uuid, integer) is
  'COM-157/O1 remediation: tenant-wide, most-recent-first, field-masked credit profile list, replacing server/queries/credit.ts:31''s broken .from("credit_profiles_directory") (app is not exposed to PostgREST). Reproduces app.credit_profiles_directory''s own defining SELECT directly against the base table app.credit_profiles (never the view itself, to avoid a nested-SECURITY-DEFINER auth.uid() reliance -- the fix app.search_vendor_rates/app.list_opportunities already established): currency/requested_limit_amount/approved_limit_amount are nulled and amount_masked=true unless the actor holds COM:View selling price (app.has_view_selling_price, unaltered since 20260723210000). Row scope reproduces the CURRENT credit_profiles_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin) as rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql -- NOT the view''s own now-stale WHERE clause, which lacks the customer_user-layer exclusion (see this migration''s file header). Server-side clamped to <=200 rows regardless of what is requested (mirrors app.list_accounts). Raises insufficient_authority (never a silent empty page) when the actor has no standing for p_tenant_id at all, matching app.list_accounts for this same "list for one named tenant" shape.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_credit_profiles with an identical grant set, never a
-- reimplementation.
create function public.list_credit_profiles(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns table (
  id uuid,
  tenant_id uuid,
  account_id uuid,
  currency text,
  requested_limit_amount numeric,
  approved_limit_amount numeric,
  amount_masked boolean,
  status text,
  effective_from timestamptz,
  effective_to timestamptz,
  hold_reason text,
  rejected_reason text,
  approval_request_id uuid,
  supersedes_profile_id uuid,
  approved_by text,
  approved_at timestamptz,
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
  select * from app.list_credit_profiles(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_credit_profiles(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_credit_profiles with an identical grant set, never a reimplementation.';

-- app.list_credit_profiles: same grant set as the view it replaces
-- (`grant select on app.credit_profiles_directory to authenticated, service_role;`,
-- 20260724310000:764).
revoke execute on function app.list_credit_profiles(uuid, uuid, integer) from public;
grant execute on function app.list_credit_profiles(uuid, uuid, integer) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309.
revoke execute on function public.list_credit_profiles(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_credit_profiles(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- 2. app.get_credit_profile_for_account -- replaces server/queries/credit.ts:40
--    (getCreditProfileForAccount)
-- ===========================================================================
-- Replaces: server/queries/credit.ts:40, .from("credit_profiles_directory")
-- .eq("account_id", accountId).order("created_at", desc).limit(1). Reads
-- app.credit_profiles_directory (re-expressed against the base table). No p_tenant_id
-- parameter -- the original .from() call never supplied one either (only
-- .eq("account_id", ...)), relying purely on RLS to filter each candidate row by that row's
-- own tenant_id, so authority is evaluated per-row against p.tenant_id, exactly like
-- app.get_account_by_id/app.list_subsidiary_accounts (20260908020000) already do for the
-- identical "no explicit tenant, per-row" shape. Authority predicate: CURRENT
-- credit_profiles_select_scoped (RULE B above). No deliberate column exclusion (file
-- header). Anti-enumeration: RETURNS TABLE with an implicit zero-or-one-row result (never an
-- exception) so "no profile for this account" and "a profile exists but this actor cannot
-- see it" both collapse to zero rows -- the same behavior the original RLS-filtered
-- .limit(1) array read already had before the caller took data?.[0] ?? null.
create function app.get_credit_profile_for_account(
  p_account_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  account_id uuid,
  currency text,
  requested_limit_amount numeric,
  approved_limit_amount numeric,
  amount_masked boolean,
  status text,
  effective_from timestamptz,
  effective_to timestamptz,
  hold_reason text,
  rejected_reason text,
  approval_request_id uuid,
  supersedes_profile_id uuid,
  approved_by text,
  approved_at timestamptz,
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
      p.id,
      p.tenant_id,
      p.account_id,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.currency else null end,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.requested_limit_amount else null end,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.approved_limit_amount else null end,
      not app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id),
      p.status,
      p.effective_from,
      p.effective_to,
      p.hold_reason,
      p.rejected_reason,
      p.approval_request_id,
      p.supersedes_profile_id,
      p.approved_by,
      p.approved_at,
      p.record_version,
      p.created_by,
      p.created_at,
      p.updated_at
    from app.credit_profiles p
    where p.account_id = p_account_id
      and (
        (app.has_active_tenant_membership(p.tenant_id, p_actor_auth_user_id)
           and not app.actor_holds_customer_user_layer(p.tenant_id, p_actor_auth_user_id))
        or app.is_supreme_admin(p_actor_auth_user_id)
      )
    order by p.created_at desc
    limit 1;
end;
$$;

comment on function app.get_credit_profile_for_account(uuid, uuid) is
  'COM-157/O1 remediation: the current (most recently created) field-masked credit profile for one account, replacing server/queries/credit.ts:40''s broken .from("credit_profiles_directory")...limit(1) (app is not exposed to PostgREST). Reproduces app.credit_profiles_directory''s own defining SELECT against the base table app.credit_profiles directly (never the view itself, same nested-auth.uid() avoidance as app.list_credit_profiles above). No p_tenant_id parameter, mirroring app.get_account_by_id/app.list_subsidiary_accounts (20260908020000): the original call never supplied one, so the CURRENT credit_profiles_select_scoped predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin -- 20260730560000, NOT the view''s own stale WHERE clause, see file header) is evaluated per-row against this row''s own tenant_id. currency/requested_limit_amount/approved_limit_amount masking is identical to app.list_credit_profiles. A nonexistent account, an account with no credit profile, and an account whose sole profile this actor cannot see all collapse to zero rows, never an exception -- the TS caller keeps returning null on an empty result exactly as before.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_credit_profile_for_account with an identical grant set, never a
-- reimplementation.
create function public.get_credit_profile_for_account(
  p_account_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  account_id uuid,
  currency text,
  requested_limit_amount numeric,
  approved_limit_amount numeric,
  amount_masked boolean,
  status text,
  effective_from timestamptz,
  effective_to timestamptz,
  hold_reason text,
  rejected_reason text,
  approval_request_id uuid,
  supersedes_profile_id uuid,
  approved_by text,
  approved_at timestamptz,
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
  select * from app.get_credit_profile_for_account(p_account_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_credit_profile_for_account(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_credit_profile_for_account with an identical grant set, never a reimplementation.';

revoke execute on function app.get_credit_profile_for_account(uuid, uuid) from public;
grant execute on function app.get_credit_profile_for_account(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_credit_profile_for_account(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_credit_profile_for_account(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 3. app.get_credit_profile_by_id -- replaces server/queries/credit.ts:52
--    (getCreditProfileById)
-- ===========================================================================
-- Replaces: server/queries/credit.ts:52, .from("credit_profiles_directory")
-- .eq("id", profileId).maybeSingle(). Reads app.credit_profiles_directory (re-expressed
-- against the base table). No p_tenant_id parameter -- same reasoning as
-- app.get_credit_profile_for_account/app.get_account_by_id above: the original call never
-- supplied one, so the CURRENT credit_profiles_select_scoped predicate (RULE B above) is
-- evaluated per-row against this row's own tenant_id. No deliberate column exclusion (file
-- header). Anti-enumeration: RETURNS TABLE (zero or one row, since id is the primary key)
-- rather than raising, so "no such id" and "exists but denied" both collapse to an empty
-- result, exactly the behavior .maybeSingle() under real RLS already had.
create function app.get_credit_profile_by_id(
  p_profile_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  account_id uuid,
  currency text,
  requested_limit_amount numeric,
  approved_limit_amount numeric,
  amount_masked boolean,
  status text,
  effective_from timestamptz,
  effective_to timestamptz,
  hold_reason text,
  rejected_reason text,
  approval_request_id uuid,
  supersedes_profile_id uuid,
  approved_by text,
  approved_at timestamptz,
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
      p.id,
      p.tenant_id,
      p.account_id,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.currency else null end,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.requested_limit_amount else null end,
      case when app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id) then p.approved_limit_amount else null end,
      not app.has_view_selling_price(p.tenant_id, p_actor_auth_user_id),
      p.status,
      p.effective_from,
      p.effective_to,
      p.hold_reason,
      p.rejected_reason,
      p.approval_request_id,
      p.supersedes_profile_id,
      p.approved_by,
      p.approved_at,
      p.record_version,
      p.created_by,
      p.created_at,
      p.updated_at
    from app.credit_profiles p
    where p.id = p_profile_id
      and (
        (app.has_active_tenant_membership(p.tenant_id, p_actor_auth_user_id)
           and not app.actor_holds_customer_user_layer(p.tenant_id, p_actor_auth_user_id))
        or app.is_supreme_admin(p_actor_auth_user_id)
      );
end;
$$;

comment on function app.get_credit_profile_by_id(uuid, uuid) is
  'COM-157/O1 remediation: single-credit-profile-by-id, field-masked read, replacing server/queries/credit.ts:52''s broken .from("credit_profiles_directory").eq("id", ...).maybeSingle() (app is not exposed to PostgREST). Reproduces app.credit_profiles_directory''s own defining SELECT against the base table app.credit_profiles directly (never the view itself, same nested-auth.uid() avoidance as the two functions above). No p_tenant_id parameter, mirroring app.get_account_by_id (20260908020000): the CURRENT credit_profiles_select_scoped predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin -- 20260730560000, NOT the view''s own stale WHERE clause, see file header) is evaluated against this row''s own tenant_id. currency/requested_limit_amount/approved_limit_amount masking is identical to app.list_credit_profiles. Returns zero or one row (id is the primary key) rather than raising, so "no such id" and "exists but denied" both collapse to an empty result -- the same anti-enumeration behavior .maybeSingle() under RLS already had; the TS caller keeps returning null on an empty result exactly as before.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_credit_profile_by_id with an identical grant set, never a
-- reimplementation.
create function public.get_credit_profile_by_id(
  p_profile_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  account_id uuid,
  currency text,
  requested_limit_amount numeric,
  approved_limit_amount numeric,
  amount_masked boolean,
  status text,
  effective_from timestamptz,
  effective_to timestamptz,
  hold_reason text,
  rejected_reason text,
  approval_request_id uuid,
  supersedes_profile_id uuid,
  approved_by text,
  approved_at timestamptz,
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
  select * from app.get_credit_profile_by_id(p_profile_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_credit_profile_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_credit_profile_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_credit_profile_by_id(uuid, uuid) from public;
grant execute on function app.get_credit_profile_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_credit_profile_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_credit_profile_by_id(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- RULE A / RULE B self-check (re-read before finishing)
-- ===========================================================================
-- RULE A: all three functions (app.list_credit_profiles, app.get_credit_profile_for_account,
-- app.get_credit_profile_by_id) take an explicit p_actor_auth_user_id and are granted to
-- `authenticated` below -- each function body's literal FIRST statement (before any
-- declare-block work, lookup, or authority check) is
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);`. Confirmed by
-- re-reading each `as $$ begin ... end; $$;` block above in order.
-- RULE B: re-confirmed via a fresh grep pass (`grep -n "alter policy.*credit_profiles"` and
-- `grep -n "credit_profiles_select_scoped"` across supabase/migrations/*.sql) that
-- 20260730560000_harden_customer_user_layer_default_deny.sql:103 is the ONLY, and therefore
-- CURRENT, alter of credit_profiles_select_scoped -- no migration after it touches this
-- policy. All three functions above reproduce that exact predicate
-- (`(has_active_tenant_membership(tenant_id, actor) AND NOT actor_holds_customer_user_
-- layer(tenant_id, actor)) OR is_supreme_admin(actor)`), not the view's own older text.
-- ===========================================================================

-- TS INTEGRATION:
-- File: server/queries/credit.ts.
--
-- 1. Widen CreditQueryClient (line 15, currently `Pick<SupabaseClient, "from" | "rpc">`) --
--    already includes "rpc", no change needed there. All three functions below switch from
--    "from" to "rpc"; listCreditProfileOverrides (line 61, a DIFFERENT table,
--    credit_profile_overrides_directory) is out of scope for this file and keeps using
--    "from" unless a companion remediation covers it separately.
--
-- 2. listCreditProfiles(client, tenantId) [line 28-35]: add an `actorAuthUserId: string`
--    parameter to its own signature (the RPC needs an explicit actor; the old .from() call
--    relied on the caller's own PostgREST session/JWT implicitly, which never worked here
--    anyway). Replace the body:
--      const { data, error } = await client.rpc("list_credit_profiles", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (omit p_limit to keep the RPC's own default of 200; add it only if a future caller
--    needs to override the cap.) Keep the existing
--    `(data ?? []).map((row) => parseCreditProfile(row))` mapping unchanged -- the returned
--    rows carry the exact same 20 column names (snake_case) parseCreditProfile already
--    expects.
--
-- 3. getCreditProfileForAccount(client, accountId) [line 38-46]: add an
--    `actorAuthUserId: string` parameter. Replace the body:
--      const { data, error } = await client.rpc("get_credit_profile_for_account", {
--        p_account_id: accountId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    `data` is now an array (RETURNS TABLE), zero or one row -- keep the existing
--    `const row = (data ?? [])[0]; if (!row) return null; return parseCreditProfile(row)`
--    logic unchanged (it already treats data as an array and takes element 0, exactly
--    matching the old .limit(1) array shape).
--
-- 4. getCreditProfileById(client, profileId) [line 48-56]: add an `actorAuthUserId: string`
--    parameter. Replace the body:
--      const { data, error } = await client.rpc("get_credit_profile_by_id", {
--        p_profile_id: profileId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    `data` is now an array (RETURNS TABLE) instead of a single nullable object
--    (.maybeSingle()) -- change the null-check/return to
--    `const row = (data ?? [])[0]; if (!row) return null; return parseCreditProfile(row)`
--    (same pattern as step 3), replacing the old `if (!data) return null; return
--    parseCreditProfile(data)`.
--
-- 5. Every call site of these three exported functions elsewhere in the server layer must be
--    updated to pass the caller's own actorAuthUserId through (the same threading pattern
--    already used for every other actor-scoped RPC call in this codebase).
-- Replaces the broken PostgREST read at server/queries/credit.ts:64
-- (listCreditProfileOverrides: `.from("credit_profile_overrides_directory")
-- .select("*").eq("credit_profile_id", profileId).order("created_at", { ascending: false })`).
-- app.credit_profile_overrides_directory is a VIEW (not a base table), created at
-- supabase/migrations/20260724310000_create_commercial_credit_commercial_control.sql:700-717.
-- Grepped "create or replace view app.credit_profile_overrides_directory" across every file in
-- supabase/migrations/*.sql (RULE B/C) -- no hit besides the original creation, so the view's
-- defining SELECT (lines 702-714) is still current. It lives in the "app" Postgres schema, which
-- supabase/config.toml does not expose to PostgREST ("public"/"graphql_public" only) -- this
-- .from() call has never worked in production.
--
-- AUTHORITY / MASKING RULE ENFORCED, AND WHY
-- ------------------------------------------
-- Row visibility: `(app.has_active_tenant_membership(tenant_id, actor) and not
-- app.actor_holds_customer_user_layer(tenant_id, actor)) or app.is_supreme_admin(actor)` --
-- NOT the view's own original WHERE clause text (...create_commercial_credit_commercial_
-- control.sql:714, `app.has_active_tenant_membership(o.tenant_id) or app.is_supreme_admin()`),
-- which was superseded by 20260730560000_harden_customer_user_layer_default_deny.sql's ALTER
-- POLICY on the identical `credit_profile_overrides_select_scoped` RLS policy on the base table
-- (same original migration, lines 732-734; alter at 20260730560000_harden_customer_user_layer_
-- default_deny.sql:100-101). Grepped both "create policy" and "alter policy" naming
-- `credit_profile_overrides` / `credit_profile_overrides_select_scoped` across every file in
-- supabase/migrations/*.sql (RULE B): the only alter is that one, which adds
-- `AND NOT app.actor_holds_customer_user_layer(tenant_id)` specifically to stop a customer-portal
-- (customer_user-layer) principal -- who DOES satisfy has_active_tenant_membership -- from
-- reading tenant-wide staff credit-override data. Tenant-wide, not record/org-unit-scoped
-- (credit_profile_overrides carries no owner_user_id/org_unit_id column at all -- COM-157's own
-- migration header already establishes credit_profiles/its overrides as tenant-wide reference
-- data, mirroring app.accounts/COM-155).
--
-- Column masking: `amount` is nulled (amount_masked=true) for any actor lacking the real, seeded
-- `COM:View selling price` permission, gated through the existing
-- `app.has_view_selling_price(tenant_id, actor)` helper (created at 20260723210000_create_
-- commercial_opportunity_management.sql:134-142; grepped for a later "create or replace function
-- app.has_view_selling_price" -- RULE C -- none found, still current). This is an exact
-- replication of the view's own single CASE WHEN expression (line 706) -- not a reimplementation
-- -- because `authenticated` has no direct column-level grant on `amount` on the base table
-- itself (line 753: the column grant list omits it), so this is the only place the masking logic
-- may legally live. Precedent for this exact authority-check pattern (has_active_tenant_
-- membership + actor_holds_customer_user_layer exclusion + is_supreme_admin, combined with
-- has_view_selling_price masking) is app.list_customer_contract_price_components (this same
-- cluster0 remediation effort, COM-156 table) and app.check_customer_credit itself (this same
-- migration, line 520-634, which already reuses has_view_selling_price for the identical
-- mask-the-function's-own-output technique on this same feature).
--
-- WHY THE MASKING IS RE-EXPRESSED AGAINST THE BASE TABLE, NOT BY QUERYING THE VIEW INTERNALLY:
-- the view's own CASE expression calls app.has_view_selling_price(o.tenant_id) relying on that
-- helper's *default* `auth.uid()` argument -- correct only under a live PostgREST session GUC,
-- not when composed inside another SECURITY DEFINER RPC. Every function in this migration
-- threads an explicit p_actor_auth_user_id instead, the same fix app.search_vendor_rates
-- (COM-149) and app.list_customer_contract_price_components (COM-156, this cluster) already
-- established for the identical problem.
--
-- Deliberate column exclusion: none beyond what the view (and thus the original .from() call)
-- already excluded -- `amount` is nulled per-row (never omitted from the shape), exactly matching
-- the view's own `amount_masked` contract. No new column added or dropped relative to the view's
-- 10-column projection (id, tenant_id, credit_profile_id, amount, amount_masked, reason,
-- expires_at, approved_by, created_by, created_at).
--
-- No p_limit/pagination: p_credit_profile_id scopes the result to one credit profile's own
-- overrides -- the original .from() call itself never paginated (no `.range()`/`.limit()` in
-- server/queries/credit.ts:64), and app.check_customer_credit's own sibling read of the same
-- table (line 608-612) is likewise a bare, unbounded filter. A `limit` would change behavior
-- relative to both, not preserve it, so none is added here (mirrors app.list_customer_contract_
-- price_components' identical reasoning for its own single-parent-scoped read).

create function app.list_credit_profile_overrides(
  p_credit_profile_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  credit_profile_id uuid,
  amount numeric,
  amount_masked boolean,
  reason text,
  expires_at timestamptz,
  approved_by text,
  created_by text,
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
    o.id,
    o.tenant_id,
    o.credit_profile_id,
    case when app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id) then o.amount else null end as amount,
    not app.has_view_selling_price(o.tenant_id, p_actor_auth_user_id) as amount_masked,
    o.reason,
    o.expires_at,
    o.approved_by,
    o.created_by,
    o.created_at
  from app.credit_profile_overrides o
  where o.credit_profile_id = p_credit_profile_id
    and (
      (app.has_active_tenant_membership(o.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(o.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by o.created_at desc;
end;
$$;

comment on function app.list_credit_profile_overrides(uuid, uuid) is
  'COM-157 Option-2 remediation: read path for app.credit_profile_overrides_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup. Row-visibility filter ((has_active_tenant_membership(tenant_id, actor) and not actor_holds_customer_user_layer(tenant_id, actor)) or is_supreme_admin(actor)) reproduces the CURRENT credit_profile_overrides_select_scoped RLS policy as hardened by 20260730560000_harden_customer_user_layer_default_deny.sql, not the view''s own original (pre-hardening) WHERE text. The single-column amount mask (COM:View selling price, via app.has_view_selling_price) is copied verbatim from the view''s own definition, re-expressed against the base table with an explicit p_actor_auth_user_id instead of the view''s default-auth.uid() masking. Returns zero rows (never an exception) for a nonexistent credit_profile_id or an actor with no qualifying membership in that profile''s tenant, matching the original RLS-filtered view''s own silent-empty-result posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_credit_profile_overrides with an identical grant set, never a
-- reimplementation.
create function public.list_credit_profile_overrides(
  p_credit_profile_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  credit_profile_id uuid,
  amount numeric,
  amount_masked boolean,
  reason text,
  expires_at timestamptz,
  approved_by text,
  created_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_credit_profile_overrides(p_credit_profile_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_credit_profile_overrides(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_credit_profile_overrides with an identical grant set, never a reimplementation.';

-- app.list_credit_profile_overrides: same grant set as the view it replaces
-- (`grant select on app.credit_profile_overrides_directory to authenticated, service_role;`,
-- 20260724310000_create_commercial_credit_commercial_control.sql:766) and as every mutation
-- function over this same table/feature in that migration (lines 768-773).
revoke execute on function app.list_credit_profile_overrides(uuid, uuid) from public;
grant execute on function app.list_credit_profile_overrides(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (docs/runtime/KNOWN_ISSUES.md,
-- 20260830200000_correct_public_wrapper_grant_parity.sql): Supabase's own ALTER DEFAULT
-- PRIVILEGES rule grants EXECUTE on every new public.* function to `anon` and `authenticated`
-- at CREATE time, so `revoke ... from public` alone (the PUBLIC pseudo-role) never removes those
-- two role-specific grants. Revoke all four explicitly, then grant back only the roles
-- app.list_credit_profile_overrides itself grants to, minus anon.
revoke execute on function public.list_credit_profile_overrides(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_credit_profile_overrides(uuid, uuid) to authenticated, service_role;

-- TS INTEGRATION:
-- File: server/queries/credit.ts, function listCreditProfileOverrides (lines 62-69).
--
-- 1. Add an `actorAuthUserId: string` parameter to listCreditProfileOverrides's own signature
--    (the RPC needs an explicit actor to run its authority/masking checks; the old .from() call
--    relied on the caller's own PostgREST session/JWT implicitly). Thread it in from whatever
--    server-side session context this file's other functions already receive it from (e.g.
--    getCreditProfileApprovalOverview's own actorAuthUserId parameter a few lines below).
--
-- 2. Replace the body:
--      const { data, error } = await client
--        .from("credit_profile_overrides_directory")
--        .select("*")
--        .eq("credit_profile_id", profileId)
--        .order("created_at", { ascending: false });
--    with:
--      const { data, error } = await client.rpc("list_credit_profile_overrides", {
--        p_credit_profile_id: profileId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (p_* argument names/order exactly as declared above: p_credit_profile_id first, then
--    p_actor_auth_user_id.) Drop the now-redundant `.order(...)` call -- the RPC already applies
--    `order by o.created_at desc` server-side.
--
-- 3. Row mapping is unchanged: the RPC returns the identical 10-column shape, in the identical
--    order, as the old view select (id, tenant_id, credit_profile_id, amount, amount_masked,
--    reason, expires_at, approved_by, created_by, created_at) -- so
--    `(data ?? []).map((row: Record<string, unknown>) => parseCreditProfileOverride(row))` on
--    line 68 needs no change at all. Error handling (`if (error) throw new CreditQueryError(
--    error.message)`) is also unchanged -- .rpc() surfaces errors the same shape as .from().
--
-- 4. The function's exported return type (`Promise<CreditProfileOverride[]>`) does not change.
--
-- 5. server/queries/credit.test.ts:110-113 currently calls
--    `listCreditProfileOverrides(client, PROFILE_ID)` with a two-arg CreditQueryClient mock
--    stubbing `.from()` -- update it to pass a third actorAuthUserId argument and stub `.rpc()`
--    (returning `{ data: [...], error: null }`) instead of `.from()`, mirroring how this same
--    test file already stubs .rpc() for check_customer_credit-shaped calls elsewhere in the repo.
-- CG-AUDIT-2026-09-02 Ø1-query-layer remediation -- cluster 0, table
-- app.approval_requests.
--
-- Replaces TWO broken `.from("approval_requests")` reads (identical shape,
-- confirmed byte-for-byte identical in the live TS source):
--   1. server/queries/credit.ts:113 (listCreditProfileApprovalInboxForActor)
--        .select("id, entity_type, entity_id").in("id", requestIds)
--        then filters client-side to entity_type === "credit_profile".
--   2. server/queries/quotation-approval.ts:81 (listQuotationApprovalInboxForActor)
--        .select("id, entity_type, entity_id").in("id", requestIds)
--        then filters client-side to entity_type === "quotation".
-- Both resolve `requestIds` from app.list_pending_approval_steps_for_actor
-- (PLT-123, already an RPC, entity-agnostic, unaffected by this migration) and
-- then need this one bulk id -> {entity_type, entity_id} lookup. Per the task
-- notes, ONE shared function serves both call sites (no p_entity_type filter
-- parameter is needed in SQL at all: exactly like the original `.from()` call,
-- both callers fetch id/entity_type/entity_id together and filter by
-- entity_type client-side afterward -- see "TS INTEGRATION" at the bottom).
--
-- Table (base table, NOT a view -- confirmed via
-- `grep -n "create table app.approval_requests"`,
-- supabase/migrations/20260719090000_create_approval_engine.sql:176). No
-- field-masking logic applies (masking is a `_directory`-view-only concern in
-- this codebase; approval_requests carries no cost/margin/sell-price-style
-- columns). Deliberate column exclusion: only id/entity_type/entity_id are
-- selected, exactly matching the original `.from()` call's own
-- `.select("id, entity_type, entity_id")` -- tenant_id, config_version_id,
-- pattern, status, idempotency_key, requested_by(_auth_user_id), started_at/
-- ended_at/ended_reason, record_version, created_at/updated_at are all
-- deliberately NOT returned, matching the original read exactly.
--
-- RULE B (RLS predicate currency) -- IMPORTANT, live discrepancy found:
--   `create policy approval_requests_select_scoped on app.approval_requests`
--   (20260719090000_create_approval_engine.sql:879) originally read:
--     using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
--   It was LATER rewritten by
--   `alter policy approval_requests_select_scoped on app.approval_requests`
--   in 20260730560000_harden_customer_user_layer_default_deny.sql:85 to:
--     using (((app.has_active_tenant_membership(tenant_id)
--              AND NOT app.actor_holds_customer_user_layer(tenant_id))
--             OR app.is_supreme_admin()));
--   Confirmed via `grep -rn "approval_requests_select_scoped"
--   supabase/migrations/*.sql` (sorted by filename) that ONLY these two files
--   reference the policy name -- 20260730560000 is the current, final version.
--   THIS function reproduces that CURRENT (narrower) predicate.
--
--   RULE C (precedent staleness) -- also an IMPORTANT live discrepancy found:
--   the obvious existing authority-check precedent for this table,
--   `app.check_approval_request_authority(p_tenant_id, p_actor_auth_user_id)`
--   (created once, at 20260719090000_create_approval_engine.sql:309; confirmed
--   via `grep -n "create or replace function app.check_approval_request_
--   authority\|create function app.check_approval_request_authority"
--   supabase/migrations/*.sql` that it has NEVER been replaced), still reads:
--     select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
--            or app.is_supreme_admin(p_actor_auth_user_id);
--   i.e. it was NEVER patched to add the `AND NOT
--   app.actor_holds_customer_user_layer(...)` conjunct that the RLS policy
--   itself received in 20260730560000. Every existing app.* function on this
--   table (app.get_approval_request_history, app.list_pending_approval_steps_
--   for_actor, app.request_approval, app.decide_approval_step,
--   app.cancel_approval_request -- all call check_approval_request_authority)
--   is therefore ALSO stale relative to the current RLS policy -- but widening
--   the scope of THIS migration to re-patch those pre-existing functions is
--   out of scope for this table's own Ø1 remediation ticket (this migration
--   only adds NEW functions for the two named broken `.from()` call sites; it
--   does not touch check_approval_request_authority or its five existing
--   callers). This new function therefore does NOT call
--   check_approval_request_authority -- doing so would silently reintroduce
--   the customer_user-layer leak into brand-new code. Instead it inlines the
--   CURRENT accounts_select_scoped-style predicate directly, per-row against
--   each candidate row's own tenant_id, the exact same shape and rationale
--   already established for this identical "original `.from()` call carried
--   no single caller-asserted tenant_id" situation by
--   app.list_subsidiary_accounts / app.get_account_by_id
--   (20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql:348,414;
--   both re-confirmed as each table's MOST RECENT body, i.e. their own
--   original and only body -- no later `create or replace` exists for
--   either). Flagging the check_approval_request_authority /
--   five-caller staleness for a follow-up hardening migration
--   (same shape as 20260730510000_harden_actor_identity_unchecked_authority_
--   surface.sql) is noted in openQuestions.
--
-- RULE A: p_actor_auth_user_id is an explicit parameter and this function is
-- granted to `authenticated` -> `perform
-- app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the first
-- executable statement, before any lookup or authority check.
--
-- Bounding: p_ids is caller-supplied and already bounded upstream by
-- app.list_pending_approval_steps_for_actor's own result set (one tenant's
-- currently-active pending steps) -- this is a bulk id-list resolution, not an
-- open-ended list/paginated read, so no LIMIT/cursor is applied, matching the
-- original `.in("id", requestIds)` call's own unbounded-by-count-but-bounded-
-- by-input-set semantics exactly.

create function app.get_approval_requests_entity_refs(
  p_ids uuid[],
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  entity_type text,
  entity_id uuid
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select r.id, r.entity_type, r.entity_id
    from app.approval_requests r
    where r.id = any (p_ids)
      and (
        (app.has_active_tenant_membership(r.tenant_id, p_actor_auth_user_id)
           and not app.actor_holds_customer_user_layer(r.tenant_id, p_actor_auth_user_id))
        or app.is_supreme_admin(p_actor_auth_user_id)
      );
end;
$$;

comment on function app.get_approval_requests_entity_refs(uuid[], uuid) is
  'CG-AUDIT-2026-09-02 O1 cluster 0: bulk id -> {entity_type, entity_id} resolution for approval_requests, shared by listCreditProfileApprovalInboxForActor (server/queries/credit.ts) and listQuotationApprovalInboxForActor (server/queries/quotation-approval.ts) -- both filter the result to their own entity_type client-side afterward, exactly as the original .from("approval_requests").select("id, entity_type, entity_id").in("id", requestIds) call did. No p_tenant_id parameter: the original call site never supplied one either, so authority is evaluated per-row against each candidate row''s own tenant_id (same shape as app.list_subsidiary_accounts/app.get_account_by_id). Authority reproduces the CURRENT approval_requests_select_scoped predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin) as rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql -- deliberately NOT app.check_approval_request_authority, whose body (unchanged since 20260719090000_create_approval_engine.sql) was never patched to add the customer_user-layer exclusion and is therefore stale relative to this table''s own current RLS policy. Ids the actor has no standing for, and unknown ids, are silently omitted from the result set (never raised), matching the original RLS-filtered `.in()` read''s own "denied/missing rows just don''t come back" contract exactly.';

create function public.get_approval_requests_entity_refs(
  p_ids uuid[],
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  entity_type text,
  entity_id uuid
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_approval_requests_entity_refs(p_ids, p_actor_auth_user_id);
$wrap$;

comment on function public.get_approval_requests_entity_refs(uuid[], uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_approval_requests_entity_refs with an identical grant set, never a reimplementation.';

-- Per ERR-2026-004: explicit revoke of the app-schema PUBLIC-execute default
-- before any role-specific grant (standing per-migration convention).
revoke execute on function app.get_approval_requests_entity_refs(uuid[], uuid) from public;
grant execute on function app.get_approval_requests_entity_refs(uuid[], uuid) to authenticated, service_role;

-- Per ISS-2026-309 (closed by 20260830200000_correct_public_wrapper_grant_
-- parity.sql): a bare `revoke ... from public` does NOT strip the
-- anon/authenticated EXECUTE grants Supabase's ALTER DEFAULT PRIVILEGES rule
-- applies to every new function in schema public at CREATE time -- revoke from
-- every role explicitly, then re-grant only the app.* function's own roles.
revoke execute on function public.get_approval_requests_entity_refs(uuid[], uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_approval_requests_entity_refs(uuid[], uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- server/queries/credit.ts (listCreditProfileApprovalInboxForActor, currently
-- around line 113) and server/queries/quotation-approval.ts
-- (listQuotationApprovalInboxForActor, currently around line 81): replace
--
--   const { data, error } = await client.from("approval_requests")
--     .select("id, entity_type, entity_id").in("id", requestIds);
--
-- with
--
--   const { data, error } = await client.rpc("get_approval_requests_entity_refs", {
--     p_ids: requestIds,
--     p_actor_auth_user_id: actorAuthUserId,
--   });
--
-- (`actorAuthUserId` is already in scope in both call sites -- it is a
-- parameter of listCreditProfileApprovalInboxForActor/
-- listQuotationApprovalInboxForActor themselves.) Keep the existing
-- `if (error) { throw new CreditQueryError(error.message); }` /
-- `QuotationApprovalQueryError` handling unchanged.
--
-- Row shape returned by the RPC is IDENTICAL to the old `.from()` select
-- (`{ id: string; entity_type: string; entity_id: string | null }[]`), so the
-- existing downstream code is untouched verbatim in both files:
--
--   const profileIdByRequestId = new Map<string, string>();       // credit.ts
--   for (const row of (data ?? []) as Array<{ id: string; entity_type: string; entity_id: string | null }>) {
--     if (row.entity_type === "credit_profile" && row.entity_id) {
--       profileIdByRequestId.set(row.id, row.entity_id);
--     }
--   }
--
--   const quotationIdByRequestId = new Map<string, string>();     // quotation-approval.ts
--   for (const row of (data ?? []) as Array<{ id: string; entity_type: string; entity_id: string | null }>) {
--     if (row.entity_type === "quotation" && row.entity_id) {
--       quotationIdByRequestId.set(row.id, row.entity_id);
--     }
--   }
--
-- No other lines in either function need to change -- `client` in both files
-- is already typed as `Pick<SupabaseClient, "from" | "rpc">`
-- (CreditQueryClient / QuotationApprovalQueryClient), so `.rpc(...)` is
-- already available with no type-signature change needed.
-- Final blanket revoke (ERR-2026-004 standing convention).
revoke execute on all functions in schema app from public;
