-- CG-AUDIT-2026-09-02 Ø1-query-layer remediation, cluster 0 batch 1 (8 of 32 CRM/commercial
-- tables in cluster 0; cluster 0 is 1 of 8 recon clusters, ~158 broken call sites total).
--
-- ===========================================================================
-- WHAT THIS CLOSES, AND WHY IT IS THE HIGHEST-PRIORITY REMAINING ITEM
-- ===========================================================================
--
-- The independent launch-readiness audit's own Ø1 finding ("the schema-exposure defect;
-- highest priority; everything else sits on top of it") was previously scoped as
-- DEFERRED_LARGE after a recon pass (CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json)
-- catalogued ~158 remaining `.from()` reads across ~65 server/queries/*.ts files. Direct
-- verification during this remediation pass confirmed the true severity is worse than
-- "architecturally imperfect": `supabase/config.toml` exposes only `public`/`graphql_public`
-- to PostgREST (`schemas = ["public", "graphql_public"]`) -- the `app` schema, where every
-- real business table lives, is completely invisible to it. None of these `.from()` calls
-- have EVER worked against the real Supabase project; every one of them 404s as a
-- nonexistent relation the instant it runs. Confirmed live and reachable, not theoretical:
-- `listAccounts`/`listContacts`/`listCustomerContracts`/etc. are wired into real page
-- routes (`/commercial/accounts`, `/commercial/contacts`, `/commercial/contracts`, and the
-- opportunity/quotation/costing detail pages that hang off them) -- this is a currently
-- broken swath of the built CRM/commercial application, not a latent risk.
--
-- The fix pattern is the one already proven for the four PostgREST-schema-exposure guard
-- fixes earlier in this same backlog (`20260906090000_fix_tenant_admin_guard_postgrest_
-- schema_exposure.sql`, `20260907150000_fix_remaining_tenant_lookup_guards_postgrest_
-- schema_exposure_iss_o1_o2.sql`, and the two customer-portal-guard/Ø2 fixes): for every
-- broken `.from()` read, author a real, SECURITY DEFINER `app.*` function that performs the
-- equivalent SELECT with correct tenant/actor authority scoping, plus a thin "Option-2"
-- `public.*` pass-through wrapper (the only surface PostgREST can reach, since `app` is
-- invisible to it) carrying an identical, ISS-2026-309-safe grant set, then switch the
-- TypeScript caller from `.from()` to `.rpc()`.
--
-- ===========================================================================
-- SCOPE OF THIS MIGRATION
-- ===========================================================================
--
-- This migration closes 8 of cluster 0's 32 tables (the CRM/commercial-core cluster,
-- itself 1 of 8 recon clusters spanning ~158 sites): app.accounts, app.account_conversions,
-- app.contacts, app.activities, app.customer_contracts,
-- app.customer_contract_price_components_directory, app.costing_requests, and
-- app.costing_request_components -- 15 new functions total, replacing 17 broken call sites
-- across server/queries/account.ts, contact.ts, contract.ts, and costing.ts. The remaining
-- 24 tables in cluster 0, and the other 7 recon clusters (finance, identity/HR,
-- dispatch/operations, tracking/telematics, documents, analytics/reporting, and a handful of
-- direct `.from()` calls in page.tsx files), are tracked as their own follow-on batches --
-- each is independently large enough to warrant its own migration and its own db-test
-- evidence, matching this backlog's own "one bounded change = one commit" discipline.
--
-- ===========================================================================
-- SECURITY DESIGN, APPLIED UNIFORMLY ACROSS EVERY FUNCTION BELOW
-- ===========================================================================
--
-- Two non-negotiable rules, each a previously-shipped-and-fixed vulnerability class in this
-- exact codebase, live-caught during this migration's own authoring by an adversarial review
-- pass before anything here was applied:
--
-- RULE A (actor-impersonation guard, ATW-031/032, ISS-2026-017/032, HDN-372/373): every new
-- `app.*` function below that takes an explicit `p_actor_auth_user_id` and is reachable by
-- `authenticated` calls `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);`
-- (or the LANGUAGE SQL equivalent, a leading `select app.assert_actor_is_session_identity(...)`
-- statement) as its first executable statement, before any lookup or authority check. Earlier
-- drafts of several of these functions omitted this call, citing pre-hardening versions of
-- sibling functions as precedent (`app.list_api_keys_for_tenant`'s original 20260719150000
-- body, `app.find_duplicate_contacts`'s original 20260723150000 body, etc.) without checking
-- whether those siblings were LATER patched -- which they were, at
-- `20260730510000_harden_actor_identity_unchecked_authority_surface.sql` and
-- `20260810400000_harden_crm_ops_actor_identity_gaps.sql` respectively, for exactly this
-- reason. Every function below was corrected (or re-drafted) to the CURRENT, patched shape
-- before being included here.
--
-- RULE B (RLS predicate currency): several tenant-membership RLS policies across this schema
-- were hardened AFTER their original creation by
-- `20260730560000_harden_customer_user_layer_default_deny.sql` to add
-- `AND NOT app.actor_holds_customer_user_layer(tenant_id)` -- closing a gap where a
-- customer-portal (`customer_user`-layer) principal, who legitimately satisfies
-- `has_active_tenant_membership`, could otherwise read tenant-wide staff data (credit
-- profiles, customer contracts, contract pricing, and others). Every function below that
-- reproduces a tenant-membership-gated policy (`app.accounts`, `app.customer_contracts`,
-- `app.customer_contract_price_components_directory`) reproduces the CURRENT, hardened
-- predicate, verified against the live `alter policy` text, not the original `create policy`
-- migration a naive precedent search would land on first.
--
-- Every `public.*` wrapper's grants follow the ISS-2026-309-corrected pattern
-- (`20260830200000_correct_public_wrapper_grant_parity.sql`): `revoke execute ... from anon,
-- authenticated, service_role, public` (all four roles, since Supabase's own `ALTER DEFAULT
-- PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role` grants
-- `anon` and `authenticated` EXECUTE directly at CREATE FUNCTION time -- a bare
-- `revoke ... from public` never touches those direct grants) before re-granting only the
-- intended subset.
--
-- No masked view's own field-masking logic is simplified or reimplemented from scratch:
-- `app.customer_contract_price_components_directory`'s five-column selling-price mask
-- (COM:View selling price, via the existing `app.has_view_selling_price` helper) is a
-- line-for-line replication of the view's own CASE-WHEN expressions, re-expressed against
-- the base table with an explicit actor argument (the same fix `app.search_vendor_rates`
-- already established for the identical "a view keyed to auth.uid() silently returns zero
-- rows when queried from a SECURITY DEFINER function with no live session GUC" problem).
--
-- Deliberate column exclusions from the original `.from()` reads are preserved exactly:
-- `app.contacts`' `normalized_email`/`normalized_phone`/`duplicate_fingerprint` correlation
-- columns are never selected by either new contacts function, matching the original
-- `.select("*")` call's own effective contract (server/contracts/contact/contact.ts's
-- `parseContact` already ignores them) and the "never select more than the contract needs"
-- discipline this codebase already applies elsewhere (e.g. `app.api_keys.key_hash`).
--
-- ===========================================================================
-- VERIFICATION
-- ===========================================================================
--
-- Every function below was independently, adversarially re-verified against the live repo
-- state (not the drafting pass's own comments) before being included in this migration:
-- target table/view existence and column shape, RLS-predicate currency (RULE B), actor-
-- identity cross-check presence (RULE A), masked-view fidelity where applicable,
-- ISS-2026-309-safe wrapper grants, deliberate column exclusions, general SQL/style
-- plausibility, and correct function-sharing where two call sites needed one. A first
-- adversarial pass over this exact batch found five of eight tables missing the RULE A
-- assert call (a systemic gap in the drafting pass's own initial instructions, corrected
-- here and for every subsequent batch) and one (the price-components directory) missing the
-- RULE B customer_user-layer exclusion -- both classes of defect are fixed in the functions
-- below, not merely disclosed as residual risk.
--
-- Per ERR-2026-004: this migration carries its own explicit
-- `revoke execute on all functions in schema app from public;` guard (see each function's own
-- section for its specific revoke, plus the blanket statement at the end of this file).
-- ===========================================================================
-- app.accounts remediation -- Option-2 RPC surface (app is not exposed to PostgREST)
-- Replaces three broken `.from("accounts")` reads in server/queries/account.ts.
-- ===========================================================================
--
-- app.accounts is a REAL BASE TABLE (not a view), created at
-- supabase/migrations/20260724290000_create_commercial_customer_account_conversion.sql
-- line 67. Grepped "alter table app.accounts" across every file in
-- supabase/migrations/*.sql (RULE B applies to column shape too, not just
-- policies): one later hit besides the table's own `enable row level security`,
-- at 20260830120000_create_customer_and_item_import_adapters.sql:92-93, which
-- adds `source_import_staging_row_id uuid references app.import_staging_rows(id)`
-- (ISS-2026-274 provenance link, no sensitivity/masking implication -- see its
-- own column comment there). No other alter/add/drop-column statement exists.
-- Full, current column list (base CREATE TABLE plus that one later column):
--   id uuid, tenant_id uuid, legal_name text, trade_name text, tax_id text,
--   normalized_legal_name text, normalized_tax_id text, duplicate_fingerprint text,
--   billing_address jsonb, customer_status text, parent_account_id uuid,
--   source_prospect_id uuid, status text, merged_into_id uuid, merged_at timestamptz,
--   merged_by text, owner_user_id uuid, org_unit_id uuid, record_version integer,
--   created_by text, created_at timestamptz, updated_at timestamptz,
--   source_import_staging_row_id uuid.
-- Every function below selects `*` (matching every original `.from()` call site,
-- which also selected `*`), so this later column is included automatically and
-- correctly -- no per-column list to keep in sync.
--
-- No column exclusion: the same migration's own header explicitly discloses "No
-- credit field of any kind exists on app.accounts" and "every column is visible to
-- any active tenant member via the base table's own RLS policy directly -- no
-- separate masked directory view" (lines 28-49, 404-410). There is no hash/secret
-- column on this table (unlike app.api_keys.key_hash) and the original `.from()`
-- call sites all used `select *`, so every function below also selects `*`.
--
-- -----------------------------------------------------------------------------
-- RULE B -- authority envelope (current RLS predicate, not the original)
-- -----------------------------------------------------------------------------
-- `create policy accounts_select_scoped on app.accounts` was ORIGINALLY declared in
-- 20260724290000_create_commercial_customer_account_conversion.sql:415-417 as:
--     using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin())
-- Grepped for every later touch across supabase/migrations/*.sql (both
-- `alter policy.*accounts` and bare `accounts_select_scoped`, sorted by filename):
-- the ONLY later statement is
-- 20260730560000_harden_customer_user_layer_default_deny.sql:76-77, which rewrites
-- it to:
--     using (((app.has_active_tenant_membership(tenant_id)
--              AND NOT app.actor_holds_customer_user_layer(tenant_id))
--             OR app.is_supreme_admin()))
-- No further alter/create-or-replace of this policy exists anywhere in
-- supabase/migrations/*.sql (confirmed by grepping "accounts_select_scoped" and
-- "alter policy.*accounts" across the whole tree; only the two hits above appear).
-- This later, narrower predicate -- membership AND NOT customer_user-layer, OR
-- supreme admin -- is therefore the envelope every function below reproduces.
--
-- -----------------------------------------------------------------------------
-- RULE C -- precedent staleness check
-- -----------------------------------------------------------------------------
-- The obvious same-table precedent, app.find_duplicate_accounts, was ORIGINALLY
-- created in 20260724290000 with only
--     if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then raise ...
-- (no actor-identity assert, no customer_user-layer exclusion). It was LATER
-- replaced in 20260810400000_harden_crm_ops_actor_identity_gaps.sql:77-109 (HDN-373)
-- to add `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as
-- the literal first statement -- confirming the RULE A shape to imitate (also
-- cross-checked against app.list_api_keys_for_tenant's own current body at
-- 20260730510000_harden_actor_identity_unchecked_authority_surface.sql:985-1007,
-- which shows the identical shape for an unrelated table). HDN-373's own header
-- (lines 27-32) explicitly discloses that has_active_tenant_membership/
-- actor_holds_customer_user_layer/is_supreme_admin were deliberately left OUT of
-- that sweep because they are legitimately called cross-actor elsewhere -- it says
-- nothing about find_duplicate_accounts's own authority *predicate* being brought
-- up to date with 20260730560000's later policy rewrite. Concretely: even the
-- CURRENT (patched) app.find_duplicate_accounts body still checks ONLY
-- has_active_tenant_membership, with no actor_holds_customer_user_layer exclusion --
-- i.e. it still reflects the ORIGINAL (pre-20260730560000) policy shape, not the
-- current one. Copying that predicate forward into new code would silently
-- reintroduce the exact customer-portal-reads-staff-data gap 20260730560000 exists
-- to close. So: app.find_duplicate_accounts is cited ONLY for the RULE A
-- assert-placement shape (language/volatility/security-mode/statement-ordering),
-- never for its authority-predicate body -- every function below instead inlines
-- the CURRENT accounts_select_scoped predicate directly, per RULE B above. (No
-- named "check_accounts_authority"/"check_commercial_account_authority" helper
-- exists anywhere in supabase/migrations for this table -- grepped
-- "create (or replace )?function app\..*authority" repository-wide -- so inlining
-- the three-helper-call predicate, exactly as find_duplicate_accounts itself and
-- the base policy both do, is the established shape for this specific table, not
-- an invented one.)
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
--
-- -----------------------------------------------------------------------------
-- Design notes shared by all three functions
-- -----------------------------------------------------------------------------
-- * app.list_accounts takes an explicit p_tenant_id (mirroring its own sibling
--   app.find_duplicate_accounts exactly, same table, same migration file) and
--   RAISES insufficient_authority on failure -- a caller asking to list a specific
--   tenant's accounts without standing to see that tenant at all is an error, not
--   a silent empty page, matching find_duplicate_accounts/list_api_keys_for_tenant/
--   list_rfqs precedent for this exact "list for one named tenant" call shape.
-- * app.list_subsidiary_accounts and app.get_account_by_id take NO explicit
--   p_tenant_id (the original `.from()` call sites never supplied one either --
--   only `.eq("parent_account_id", ...)` / `.eq("id", ...)`, relying purely on
--   RLS to filter each candidate ROW by that row's own tenant_id). Reproducing
--   that exactly means evaluating the authority predicate per-row against each
--   row's OWN tenant_id inside the WHERE clause, never against a caller-supplied
--   tenant -- a non-matching/denied row is silently absent from the result, the
--   same silent behavior `.maybeSingle()`/a plain array read under RLS already
--   had (never an error on "not found" vs. "found but not visible" -- collapsing
--   that distinction is itself a deliberate anti-enumeration property RLS already
--   gave the old code for free, so removing it here would be a regression).
-- * Bounded-list convention: BOUNDED_LIST_LIMIT (200) is a well-established
--   repository-wide RPC cap (app.list_rfqs, app.list_finance_invoices,
--   app.list_api_keys_for_tenant, app.query_audit_logs all use
--   `limit least(coalesce(p_limit, N), N)`, hard-clamped server-side regardless of
--   what the caller asks for -- see server/queries/rfq.ts's own comment: "app.list_
--   rfqs itself clamps server-side to <=200 rows regardless of what is requested").
--   app.list_accounts adopts that exact same convention (least(coalesce(p_limit,
--   200), 200)) rather than the bespoke "fetch 201, slice, flag truncated"
--   technique server/queries/bounded-list.ts currently uses for the still-`.from()`-
--   based reads -- see the TS INTEGRATION note at the bottom for the small,
--   disclosed behavior change this implies.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration must carry its
-- own explicit `revoke execute on all functions in schema app from public` before
-- its final grants, the standing per-migration convention -- included below.
-- Per ISS-2026-309 (docs/runtime/KNOWN_ISSUES.md, closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): a bare
-- `revoke execute on function public.FN(...) from public` does NOT strip the
-- `anon`/`authenticated` EXECUTE grants Supabase's own ALTER DEFAULT PRIVILEGES
-- rule applies to every new function in schema public at CREATE time. Every
-- public.* wrapper below therefore explicitly revokes from
-- `anon, authenticated, service_role, public` before re-granting exactly the
-- roles the app.* counterpart itself grants.

-- ===========================================================================
-- 1. app.list_accounts -- replaces server/queries/account.ts:42 (listAccounts)
-- ===========================================================================
-- Reads app.accounts as a tenant-wide, most-recent-first, bounded list. No
-- existing app.* function does this (find_duplicate_accounts/find_existing_
-- accounts_for_lead/find_existing_accounts_for_prospect are narrow candidate
-- searches with different filters, not a general list). Authority: current
-- accounts_select_scoped predicate (RULE B, see header above) -- membership AND
-- NOT customer_user-layer, OR supreme admin. RULE A: assert_actor_is_session_
-- identity is the first executable statement, since this function takes an
-- explicit p_actor_auth_user_id and is granted to `authenticated`.
create function app.list_accounts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.accounts
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
    raise exception 'insufficient_authority: identity % cannot list accounts for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select *
    from app.accounts
    where tenant_id = p_tenant_id
    order by created_at desc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_accounts(uuid, uuid, integer) is
  'COM-155: tenant-wide account list, most-recent first, server-side clamped to <=200 rows regardless of what is requested (mirrors app.list_rfqs/app.list_finance_invoices/app.list_api_keys_for_tenant''s own established cap convention). Authority reproduces the CURRENT accounts_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin) as rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql -- NOT app.find_duplicate_accounts'' own (still-stale) predicate, which lacks the customer_user-layer exclusion. Raises insufficient_authority (never a silent empty page) when the actor has no standing for p_tenant_id at all, matching find_duplicate_accounts/list_api_keys_for_tenant for this same "list for one named tenant" shape.';

create function public.list_accounts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.accounts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_accounts(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_accounts(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_accounts with an identical grant set, never a reimplementation.';

revoke execute on function app.list_accounts(uuid, uuid, integer) from public;
grant execute on function app.list_accounts(uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_accounts(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_accounts(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_subsidiary_accounts -- replaces server/queries/account.ts:65
--    (listSubsidiaryAccounts)
-- ===========================================================================
-- Reads app.accounts filtered by parent_account_id. No existing app.* function
-- filters accounts by parent_account_id. Authority is evaluated PER ROW against
-- each candidate row's own tenant_id (see "Design notes" in the header above) --
-- the exact same current accounts_select_scoped predicate as app.list_accounts,
-- just not gated behind a single caller-supplied p_tenant_id, because the
-- original `.from()` call site never supplied one either. RULE A: assert call is
-- the first executable statement.
create function app.list_subsidiary_accounts(
  p_parent_account_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select a.*
    from app.accounts a
    where a.parent_account_id = p_parent_account_id
      and (
        (app.has_active_tenant_membership(a.tenant_id, p_actor_auth_user_id)
           and not app.actor_holds_customer_user_layer(a.tenant_id, p_actor_auth_user_id))
        or app.is_supreme_admin(p_actor_auth_user_id)
      )
    order by a.created_at desc;
end;
$$;

comment on function app.list_subsidiary_accounts(uuid, uuid) is
  'COM-155: the subsidiaries of one parent account, resolved by the database (ISS-2026-238''s own targeted-query fix). No p_tenant_id parameter -- the original .from("accounts").eq("parent_account_id", ...) call site never supplied one either, relying purely on RLS to filter each candidate row by that row''s own tenant_id, so authority here is evaluated per-row against a.tenant_id rather than a single caller-asserted tenant. Reproduces the CURRENT accounts_select_scoped predicate (20260730560000), not app.find_duplicate_accounts'' stale one. A denied or non-existent parent silently yields zero rows, matching the RLS-filtered array the original call site already returned.';

create function public.list_subsidiary_accounts(
  p_parent_account_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.accounts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_subsidiary_accounts(p_parent_account_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_subsidiary_accounts(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_subsidiary_accounts with an identical grant set, never a reimplementation.';

revoke execute on function app.list_subsidiary_accounts(uuid, uuid) from public;
grant execute on function app.list_subsidiary_accounts(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_subsidiary_accounts(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_subsidiary_accounts(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 3. app.get_account_by_id -- replaces server/queries/account.ts:74
--    (getAccountById)
-- ===========================================================================
-- Reads one app.accounts row by id. No single-account-by-id read function
-- exists in the app schema today. Authority is evaluated against THIS row's own
-- tenant_id (same reasoning as app.list_subsidiary_accounts above -- the
-- original `.eq("id", accountId).maybeSingle()` call carried no tenant filter of
-- its own either). RULE A: assert call is the first executable statement.
-- Returns SETOF rather than a single nullable app.accounts value so that "no
-- such id" and "exists but RLS-equivalent predicate denies it" both collapse to
-- zero rows, exactly the anti-enumeration property `.maybeSingle()` under real
-- RLS already had -- never an exception, matching the original call site's
-- "returns null on not-found OR denied" contract precisely (see its own comment:
-- "Returns null when not found or RLS denies it").
create function app.get_account_by_id(
  p_account_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select a.*
    from app.accounts a
    where a.id = p_account_id
      and (
        (app.has_active_tenant_membership(a.tenant_id, p_actor_auth_user_id)
           and not app.actor_holds_customer_user_layer(a.tenant_id, p_actor_auth_user_id))
        or app.is_supreme_admin(p_actor_auth_user_id)
      );
end;
$$;

comment on function app.get_account_by_id(uuid, uuid) is
  'COM-155: single-account-by-id read, used by the account detail page. No p_tenant_id parameter -- mirrors app.list_subsidiary_accounts'' own reasoning, evaluating the CURRENT accounts_select_scoped predicate (20260730560000) against this row''s own tenant_id. Returns SETOF (zero or one row) rather than raising, so "no such id" and "exists but denied" both collapse to an empty result -- the same anti-enumeration behavior .maybeSingle() under RLS already had; the TS caller keeps returning null on an empty result exactly as before.';

create function public.get_account_by_id(
  p_account_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.accounts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_account_by_id(p_account_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_account_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_account_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_account_by_id(uuid, uuid) from public;
grant execute on function app.get_account_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_account_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_account_by_id(uuid, uuid) to authenticated, service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's PUBLIC-
-- execute default, applied before the role-specific grants above are relied upon
-- (the individual `revoke ... from public` lines per function above are kept too,
-- for the same belt-and-suspenders reason every other checkpoint in this
-- repository keeps them; this final sweep is the standing convention's closing
-- statement, not a substitute for the per-function grant hygiene above).
revoke execute on function app.list_accounts(uuid, uuid, integer) from public;
revoke execute on function app.list_subsidiary_accounts(uuid, uuid) from public;
revoke execute on function app.get_account_by_id(uuid, uuid) from public;

-- ===========================================================================
-- RULE A / RULE B SELF-CHECK (re-read before shipping)
-- ===========================================================================
-- RULE A: all three app.* functions above take an explicit p_actor_auth_user_id
-- and are granted to `authenticated` -- in every one, `perform app.assert_actor_
-- is_session_identity(p_actor_auth_user_id);` is the first statement inside
-- `begin ... end`, before any lookup, any has_active_tenant_membership/
-- actor_holds_customer_user_layer/is_supreme_admin call, and any `return query`.
-- None of the three relies on the "service_role-only" exception, so none needed
-- to invoke it.
-- RULE B: grepped "alter policy.*accounts" and the bare policy name
-- "accounts_select_scoped" across every file in supabase/migrations/*.sql (not
-- just nearby ones). Exactly two hits total: the original CREATE POLICY
-- (20260724290000) and the one later ALTER POLICY (20260730560000). No third
-- statement exists. The predicate reproduced in all three functions above is the
-- 20260730560000 (latest) version, verbatim in logical shape:
-- has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer
-- (tenant_id), OR is_supreme_admin() -- with `tenant_id` bound to a.tenant_id
-- (the row's own column) rather than a single p_tenant_id where no such
-- caller-supplied tenant existed at the original `.from()` call site.

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- server/queries/account.ts -- change AccountQueryClient's used surface from
-- `Pick<SupabaseClient, "from" | "rpc">` to `Pick<SupabaseClient, "rpc">` (no
-- caller of this file needs `.from()` on `accounts` any more once all three
-- functions below are migrated).
--
-- 1) listAccounts(client, tenantId) -- currently also implicitly needs the
--    caller's own actorAuthUserId, which it does not take today. Add a required
--    `actorAuthUserId: string` parameter (every call site -- app/(tenant)/
--    [tenantSlug]/commercial/accounts/page.tsx -- already has `access.authUserId`
--    in scope, so this is a mechanical addition, not a new lookup). New body:
--
--      const { data, error } = await client.rpc("list_accounts", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--        p_limit: 200,
--      });
--      if (error) throw new AccountQueryError(error.message);
--      const rows = (data ?? []).map((row: Record<string, unknown>) => parseAccount(row));
--      return { rows, truncated: rows.length >= 200, limit: 200 }; // toBoundedListByCapReached(rows, 200)
--
--    Keep the external return type as `Promise<BoundedList<Account>>` (page.tsx
--    reads `page.rows`/`page.truncated` and must not change) but switch the
--    truncation-DETECTION technique from `boundedRange()`/`toBoundedList()`
--    (which relies on fetching one extra row past the cap via `.range()`, a
--    `.from()`-only capability) to the already-exported
--    `toBoundedListByCapReached(rows, 200)` from server/queries/bounded-list.ts
--    (already used there for exactly this "RPC hard-caps, no extra row available"
--    situation, today for app.list_files_for_tenant for a different reason).
--    DISCLOSED BEHAVIOR CHANGE: a tenant with EXACTLY 200 accounts will now show
--    "there may be more" even though there is not -- the same accepted,
--    documented trade-off toBoundedListByCapReached's own docstring already
--    states ("over-warning costs a reader one unnecessary sentence"). This is
--    the one place this draft deviates from an exact behavior match; see
--    openQuestions.
--
-- 2) listSubsidiaryAccounts(client, parentAccountId) -- add a required
--    `actorAuthUserId: string` parameter (its one call site, the account detail
--    page, already has `access.authUserId` in scope). New body:
--
--      const { data, error } = await client.rpc("list_subsidiary_accounts", {
--        p_parent_account_id: parentAccountId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--      if (error) throw new AccountQueryError(error.message);
--      return (data ?? []).map((row: Record<string, unknown>) => parseAccount(row));
--
--    Return type is unchanged (`Promise<Account[]>`).
--
-- 3) getAccountById(client, accountId) -- add a required `actorAuthUserId: string`
--    parameter (both call sites in the account detail page already have
--    `access.authUserId` in scope). New body:
--
--      const { data, error } = await client.rpc("get_account_by_id", {
--        p_account_id: accountId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--      if (error) throw new AccountQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseAccount(row as Record<string, unknown>);
--
--    Return type is unchanged (`Promise<Account | null>`); the "not found or
--    denied -> null" contract in its own doc-comment is preserved exactly.
--
-- Call-site mechanical changes (no other logic changes needed):
--   - app/(tenant)/[tenantSlug]/commercial/accounts/page.tsx:
--       listAccounts(supabase, access.tenant.id)
--       -> listAccounts(supabase, access.tenant.id, access.authUserId)
--   - app/(tenant)/[tenantSlug]/commercial/accounts/[accountId]/page.tsx:
--       getAccountById(supabase, accountId)
--       -> getAccountById(supabase, accountId, access.authUserId)
--       getAccountById(supabase, account.parentAccountId)
--       -> getAccountById(supabase, account.parentAccountId, access.authUserId)
--       listSubsidiaryAccounts(supabase, account.id)
--       -> listSubsidiaryAccounts(supabase, account.id, access.authUserId)
--   - server/queries/account.test.ts: update the fake client fixtures from
--     `.from()`-shaped stubs to `.rpc()`-shaped stubs for these three functions,
--     mirroring how server/queries/rfq.test.ts already stubs `.rpc("list_rfqs", ...)`.
-- ============================================================================================
-- Remediation for: server/queries/account.ts:109 (getAccountConversionForQuotation)
--   `select account_id, outcome from account_conversions where quotation_id = :quotationId
--   maybeSingle()` via `.from()` -- broken in production because `app` is not exposed to
--   PostgREST (supabase/config.toml only exposes public/graphql_public).
--
-- Table read: app.account_conversions -- a BASE TABLE (create table app.account_conversions,
-- supabase/migrations/20260724290000_create_commercial_customer_account_conversion.sql:123),
-- NOT a view -- so there is no field-masking CASE/WHEN logic to replicate. Confirmed no later
-- "create or replace view"/"alter table ... add column" on this table anywhere in
-- supabase/migrations/*.sql (grepped `account_conversions` across every migration file; only
-- 20260724290000 defines its shape -- every later file that mentions it only reads/writes rows,
-- never alters the schema).
--
-- Authority rule enforced, and why:
--   The base table's own RLS SELECT policy (`account_conversions_select_scoped`, originally
--   created in 20260724290000) was LATER REWRITTEN (RULE B) by
--   supabase/migrations/20260730560000_harden_customer_user_layer_default_deny.sql:73-74 to:
--     (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id))
--       OR app.is_supreme_admin()
--   Grepped "alter policy.*account_conversions" and "account_conversions_select_scoped" across
--   every file in supabase/migrations/*.sql (sorted by filename) -- 20260730560000 is the only,
--   and therefore the LATEST, rewrite; no further alter exists after it. That policy text is the
--   outer ceiling this function must never exceed.
--
--   Rather than re-deriving that raw tenant-wide predicate, this function reuses the NARROWER,
--   already-established, per-quotation authority pattern that this exact migration file already
--   uses for reading "stuff about this quotation's conversion" --
--   app.get_account_conversion_readiness -- the closest possible sibling read (same table
--   domain, same "one accepted quotation" scope, same caller-facing use case: "what happened
--   when this quotation was converted"). Per RULE C, the precedent cited is its MOST RECENT
--   body, not its original: `create or replace function app.get_account_conversion_readiness`
--   in supabase/migrations/20260810400000_harden_crm_ops_actor_identity_gaps.sql:545-590 (the
--   original 20260724290000 body lacked the actor-identity assert and would have been a stale,
--   pre-patch precedent -- grepped "create or replace function app.get_account_conversion_
--   readiness" across all migrations; 20260810400000 is the only replacement and the latest).
--   That current body's shape is: `perform app.assert_actor_is_session_identity(...)` as the
--   FIRST statement, then look up the quotation, then gate on
--   `app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id,
--   app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null)`. This function below
--   reproduces that identical shape verbatim for its own authority check.
--
--   Confirmed this does not exceed the RLS ceiling: app.can_access_record's own body (patched by
--   COM-146, supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql:50-88 --
--   grepped "create or replace function app.can_access_record"/"create function app.can_access_
--   record"; 20260723180000 is the only replacement and the latest) requires
--   `app.has_active_tenant_membership(...)` as its own leading, non-optional conjunct, and (with
--   the `p_customer_account_ref` argument passed as `null` here, exactly as
--   get_account_conversion_readiness/convert_quotation_to_account already pass it) its
--   customer_user-layer branch can never fire -- so every caller admitted by this function is
--   already inside the table's own RLS envelope. It is narrower, not wider, than the raw
--   tenant-membership ceiling (a tenant member outside the quotation's owner/org-unit is
--   admitted by the raw table RLS but not by this function) -- an intentional, precedented
--   choice, not an oversight: this read is fundamentally "what happened to THIS quotation", the
--   exact same scope its sibling readiness function already committed to, and since the `.from()`
--   call this replaces has never worked in production (app is invisible to PostgREST), there is
--   no live "tenant-wide can already see this" behavior being narrowed -- this is the first real
--   authority decision this read has ever had.
--
-- Deliberate column exclusion: only `account_id, outcome` are selected/returned, exactly what
-- the replaced `.from(...).select("account_id, outcome")` call itself selected -- id, tenant_id,
-- prospect_id, duplicate_candidate_ids, converted_by, converted_at are never selected.
--
-- Reachable by `authenticated` (not service_role-only) -- RULE A applies: `perform app.assert_
-- actor_is_session_identity(p_actor_auth_user_id);` is the first executable statement.
-- ============================================================================================

create function app.get_account_conversion_for_quotation(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (account_id uuid, outcome text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select c.account_id, c.outcome
    from app.account_conversions c
    where c.quotation_id = p_quotation_id;
end;
$$;

comment on function app.get_account_conversion_for_quotation is
  'COM-155: narrow read of the one (or zero -- unconverted) app.account_conversions row for a given quotation, replacing the broken server/queries/account.ts:109 .from("account_conversions") call (app is not exposed to PostgREST). Authority mirrors app.get_account_conversion_readiness''s own current body (20260810400000) exactly: assert_actor_is_session_identity, then app.can_access_record keyed off the SAME quotation''s tenant/owner/org-unit -- narrower than, and therefore inside, app.account_conversions'' own current RLS ceiling (20260730560000: has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin). Returns account_id/outcome only, exactly what the replaced .from() call selected.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_account_conversion_for_quotation with an identical grant set, never a
-- reimplementation. See RGL-BLK-002-OPTION2-REMEDIATION.md.
create function public.get_account_conversion_for_quotation(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (account_id uuid, outcome text)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_account_conversion_for_quotation(p_quotation_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_account_conversion_for_quotation is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_account_conversion_for_quotation with an identical grant set, never a reimplementation.';

revoke execute on function app.get_account_conversion_for_quotation(uuid, uuid) from public;
grant execute on function app.get_account_conversion_for_quotation(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_account_conversion_for_quotation(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_account_conversion_for_quotation(uuid, uuid) to authenticated, service_role;

-- ============================================================================================
-- RULE A / RULE B self-check (re-read immediately before finishing):
--   RULE A -- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the very
--     first line inside `begin ... end` in app.get_account_conversion_for_quotation, before the
--     app.quotations lookup and before the can_access_record gate. Confirmed. The function is
--     granted to `authenticated` (not service_role-only), so the exception noted in RULE A does
--     not apply here.
--   RULE B -- grepped "alter policy" + "account_conversions_select_scoped" across every file in
--     supabase/migrations/*.sql: exactly one rewrite (20260730560000), and this function's
--     chosen authority path (can_access_record, itself gated by has_active_tenant_membership) is
--     confirmed to sit strictly inside that rewritten policy's envelope, never outside it.
-- ============================================================================================

-- TS INTEGRATION:
-- File: server/queries/account.ts (replaces the getAccountConversionForQuotation body at line 109;
-- keep the exported `AccountConversionRecord` interface exactly as-is).
--
-- 1. In server/contracts/account/account.ts, add (mirroring GetAccountConversionReadinessInputSchema
--    immediately above it):
--      export const GetAccountConversionForQuotationInputSchema = z.object({
--        quotationId: z.string().uuid(),
--        actorAuthUserId: z.string().uuid(),
--      });
--      export type GetAccountConversionForQuotationInput = z.input<typeof GetAccountConversionForQuotationInputSchema>;
--
-- 2. In server/queries/account.ts, change the signature and body of getAccountConversionForQuotation
--    from `(client, quotationId: string)` to take the new input object, and switch `.from()` to
--    `.rpc()`:
--
--      export async function getAccountConversionForQuotation(
--        client: AccountQueryClient,
--        input: GetAccountConversionForQuotationInput,
--      ): Promise<AccountConversionRecord | null> {
--        const parsedInput = GetAccountConversionForQuotationInputSchema.parse(input);
--        const { data, error } = await client.rpc("get_account_conversion_for_quotation", {
--          p_quotation_id: parsedInput.quotationId,
--          p_actor_auth_user_id: parsedInput.actorAuthUserId,
--        });
--        if (error) {
--          throw new AccountQueryError(error.message);
--        }
--        const row = Array.isArray(data) ? data[0] : data;
--        if (!row) {
--          return null;
--        }
--        const typed = row as { account_id: string; outcome: "created" | "linked_existing" };
--        return { accountId: typed.account_id, outcome: typed.outcome };
--      }
--
--    Note: a `returns table(...)` RPC comes back as an array (empty array, not null, when the
--    quotation has never been converted) -- `Array.isArray(data) ? data[0] : data` yields
--    `undefined` in that case, so `!row` still correctly maps to the "not yet converted" `null`
--    return, matching the replaced `.maybeSingle()` semantics.
--
-- 3. Import GetAccountConversionForQuotationInputSchema / GetAccountConversionForQuotationInput
--    alongside the existing GetAccountConversionReadinessInputSchema import at the top of
--    server/queries/account.ts.
--
-- 4. Every existing call site of getAccountConversionForQuotation(client, quotationId) must be
--    updated to getAccountConversionForQuotation(client, { quotationId, actorAuthUserId }) --
--    at present the only call site is server/queries/account.test.ts (lines 105-118), which will
--    need its `.from` mock replaced with a `.rpc` mock returning `[{ account_id, outcome }]` /
--    `[]`, mirroring the existing getAccountConversionReadiness test's own `.rpc` mock shape in
--    the same file.
-- CG-AUDIT-2026-09-02 O1 remediation -- app.contacts (COM-145, CG-S7-COM-004).
--
-- supabase/config.toml exposes only public/graphql_public to PostgREST; app is
-- completely invisible to it. server/queries/contact.ts:62 (listContacts) and :82
-- (getContactById) both call supabase.from("contacts")..., which can never resolve in
-- production. This migration follows the exact "Option-2" pattern already proven for
-- lib/portal/tenant-admin-guard-deps.server.ts (20260906090000_fix_tenant_admin_guard_
-- postgrest_schema_exposure.sql) and for the other three already-fixed guard-deps files
-- (20260907150000_fix_remaining_tenant_lookup_guards_postgrest_schema_exposure_iss_o1_o2.sql):
-- a real, SECURITY DEFINER app.* function that re-implements the equivalent SELECT with
-- explicit tenant/authority scoping, plus a thin public.* SECURITY DEFINER pass-through
-- wrapper (schema app is not exposed to PostgREST, so public.* is the only reachable
-- surface), with an identical grant set on both.
--
-- app.contacts is a BASE TABLE (supabase/migrations/20260723150000_create_commercial_
-- contact_activity_management.sql, line 50), not a view -- there is no field-masking
-- CASE WHEN logic to replicate; every non-excluded column is returned to any actor who
-- passes the row-level authority check below, exactly as `.select("*")` did.
--
-- ============================================================================
-- RULE B (current RLS predicate) -- app.contacts_select_scoped
-- ============================================================================
-- create policy contacts_select_scoped on app.contacts
--   for select to authenticated
--   using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id,
--          app.lead_record_scope_org_unit_ids(org_unit_id), null));
--
-- Confirmed via grep across ALL of supabase/migrations/*.sql (sorted by filename):
--   grep -n "create policy" ... | grep contacts_select_scoped   -> exactly ONE hit,
--     20260723150000_create_commercial_contact_activity_management.sql:586 (original
--     creation -- the ONLY definition that has ever existed for this policy/table).
--   grep -n "alter policy.*contacts" / grep -n "contacts_select_scoped" across every
--     migration -> no ALTER POLICY anywhere touches this policy or app.contacts'
--     select policy; the only other files matching "contacts_select_scoped" as a
--     substring are unrelated policies on OTHER tables that happen to share the
--     "..._select_scoped" suffix convention (app.contact_links on procurement/HRIS/
--     customer-portal migrations use their own distinctly-named policies, not this one).
--   grep -n "drop policy.*contact" -> one hit, on app.notification_contact_addresses
--     (an unrelated table), not app.contacts.
-- Conclusion: the predicate above, exactly as originally written, is still the CURRENT,
-- unaltered authority envelope for reading app.contacts. Both new functions below
-- reproduce it exactly (neither wider nor narrower), row by row, since SECURITY DEFINER
-- bypasses RLS and must re-implement it explicitly.
--
-- ============================================================================
-- RULE C (precedent staleness) -- app.can_access_record
-- ============================================================================
-- grep -rln "function app.can_access_record" supabase/migrations/*.sql sorted:
--   20260716110430_create_field_record_access.sql            (ORIGINAL, PLT-114)
--   20260723180000_create_commercial_sales_pipeline.sql       (CREATE OR REPLACE, COM-146)
-- The COM-146 replacement (read and used below, NOT the PLT-114 original) is the current
-- body: `has_active_tenant_membership(...) AND coalesce(is_supreme_admin(...) OR (owner
-- match) OR (shared org-unit membership) OR (customer-account membership), false)`. Its
-- own header states this fixed a real NULL-owner-defeats-the-guard defect in the
-- original body (`false OR null` is NULL, not false, previously a silent-grant bug for
-- any owner_user_id IS NULL row). Every call below uses this current 5-arg signature
-- (p_auth_user_id, p_tenant_id, p_owner_user_id, p_shared_org_unit_ids, p_customer_
-- account_ref) -- confirmed no THIRD create-or-replace exists anywhere later.
--
-- app.lead_record_scope_org_unit_ids(p_org_unit_id uuid) -- grep confirms exactly one
-- definition (20260723090000_create_commercial_lead_management.sql:164), never replaced.
--
-- app.assert_actor_is_session_identity(p_actor_auth_user_id uuid) -- grep confirms
-- exactly one definition (20260730440000_harden_actor_identity_session_crosscheck.sql:59,
-- ATW-031/ISS-2026-017), never replaced. RULE A's leading call in both functions below.
--
-- Authority-check precedent modeled on (RULE C-checked): app.get_finance_invoice_lines'
-- shape ("get by id, actor second" signature order) for get_contact_by_id, and the
-- SECURITY DEFINER + explicit-predicate-restatement style every OTHER function already
-- touching app.contacts in its own creation migration already uses (app.
-- find_duplicate_contacts, app.create_contact, app.link_contact_to_record, app.
-- unlink_contact_from_record -- none of these rely on implicit RLS pass-through, all
-- restate their authority predicate explicitly). This is deliberate, not an oversight:
-- once public.list_contacts (SECURITY DEFINER) calls app.list_contacts, the "current
-- user" for any nested call is the DEFINER (the functions' owner), not the original
-- "authenticated" session role, so a SECURITY INVOKER app.list_contacts relying on
-- app.contacts' own "to authenticated" RLS policy would silently stop being scoped by
-- it (or, if the owner is a superuser/table-owner, RLS would not apply at all) --
-- exactly the class of bug 20260826010000's own header warns about ("a security-mode
-- drift between app.<name> and its public.* wrapper"). SECURITY DEFINER + an explicit,
-- RLS-identical predicate is therefore the only correct shape here, matching every
-- sibling function on this table.
--
-- find_duplicate_contacts is NOT used as the authority precedent for these two reads --
-- per the task's own note it is "a narrow fingerprint-match RPC, not a paginated
-- directory read", and its own authority check (has_active_tenant_membership only, no
-- app.can_access_record narrowing -- confirmed current via its own most-recent
-- CREATE OR REPLACE in 20260810400000_harden_crm_ops_actor_identity_gaps.sql:111, which
-- ADDED the assert_actor_is_session_identity call but did NOT add a can_access_record
-- check) is deliberately broader than contacts_select_scoped's own RLS envelope -- a
-- disclosed, narrow exception for duplicate-detection during contact creation, not the
-- general read-authority rule for this table. Copying it forward here would OVER-GRANT
-- relative to the RLS policy these two directory/detail reads must mirror, so it is
-- rejected as precedent for list_contacts/get_contact_by_id specifically.
--
-- Deliberate column exclusion: app.contacts also carries normalized_email,
-- normalized_phone, and duplicate_fingerprint -- internal, computed correlation columns
-- app.compute_contact_duplicate_fingerprint's own comment describes as identity-matching
-- plumbing, never part of the Contact contract (server/contracts/contact/contact.ts's
-- ContactSchema/parseContact already ignore them from a raw `select *` row). Neither
-- function below selects them -- narrower than the broken `.from("contacts")
-- .select("*")` call itself, the same "never select more than the contract needs"
-- discipline this codebase already applies elsewhere (e.g. app.api_keys.key_hash via
-- app.list_api_keys_for_tenant). Both functions below return every OTHER declared
-- column, unchanged from `.select("*")`'s own effective shape once these three are set
-- aside.
--
-- Pagination shape (RULE 8, disclosed choice -- see openQuestions in the review output):
-- the most recent, most-authoritative list-pagination convention in this schema is the
-- keyset idiom 20260907160000_add_cursor_pagination_finance_lists_iss_f3.sql just
-- retrofitted onto all 13 finance list functions (`p_limit default 200, p_after_id
-- default null`, fetch limit+1 to detect "more") -- explicitly citing "101 other
-- list/search RPCs in this schema already take a p_cursor/p_after parameter". That
-- idiom is the right default for a "load more" list. It is NOT used here: listContacts'
-- own existing, unchanged contract (ListContactsInput.page/pageSize,
-- ListContactsResult.totalCount, and components/tables/pagination.tsx's numbered
-- page-N Pagination UI) requires an EXACT total count and the ability to jump to an
-- arbitrary page number, neither of which a keyset cursor can provide. To preserve the
-- call site's existing external behavior exactly (the actual mandate here -- "the
-- equivalent SELECT", not a UX redesign), app.list_contacts instead reproduces
-- `.range()` + `count: "exact"` directly: a plain OFFSET/LIMIT plus a
-- `count(*) over()` window column, computed once per query, same semantics and same
-- per-request full-match-set cost PostgREST's own `count: "exact"` already had. p_page/
-- p_page_size are still defensively clamped server-side (least/greatest), since an
-- RPC is directly callable and must not trust a caller-supplied page size.

-- ============================================================================
-- 1. app.list_contacts -- replaces server/queries/contact.ts:62 (listContacts).
-- ============================================================================

create function app.list_contacts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  full_name text,
  title text,
  email text,
  phone text,
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

  -- No pre-flight has_active_tenant_membership raise (unlike app.find_duplicate_contacts/
  -- app.create_contact): this read's own docstring contract is "RLS is the real scope
  -- gate" -- a non-member or a member with zero visible rows must both silently yield
  -- an empty page (totalCount 0), exactly as `.from("contacts")...` under RLS already
  -- does today, never a thrown error. app.can_access_record's own first AND-clause is
  -- app.has_active_tenant_membership, so a non-member is filtered out identically
  -- either way -- this is the SAME rule, applied as a row filter instead of a guard
  -- clause, to preserve the exact current no-error-on-non-member behavior.
  return query
    select
      c.id, c.tenant_id, c.full_name, c.title, c.email, c.phone, c.status,
      c.owner_user_id, c.org_unit_id, c.record_version, c.created_by,
      c.created_at, c.updated_at,
      count(*) over() as total_count
    from app.contacts c
    where c.tenant_id = p_tenant_id
      and app.can_access_record(
        p_actor_auth_user_id, c.tenant_id, c.owner_user_id,
        app.lead_record_scope_org_unit_ids(c.org_unit_id), null
      )
    order by c.full_name asc, c.id asc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_contacts(uuid, uuid, integer, integer) is
  'CG-AUDIT-2026-09-02 O1: paginated Contact directory read, replacing server/queries/contact.ts:62''s broken .from("contacts") (app is not exposed to PostgREST). Row filter reproduces app.contacts'' own contacts_select_scoped RLS predicate exactly (app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null) -- unaltered since 20260723150000, confirmed via grep for a later ALTER POLICY, none found), never a second, different authority rule. total_count is an exact count(*) over() of every row matching the WHERE clause before LIMIT/OFFSET is applied -- the same per-request cost and semantics as the .from() call''s own count:"exact" option -- so callers can still page to an arbitrary page number, unlike this schema''s newer keyset (p_limit/p_after_id) list convention, which cannot. A non-member or zero-visible-row actor gets an empty page (rows=[], effective total 0), never a thrown error, matching the RLS-filtered .from() call''s own current behavior exactly.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_contacts with an identical grant set, never a reimplementation.
create function public.list_contacts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  full_name text,
  title text,
  email text,
  phone text,
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
  select * from app.list_contacts(p_tenant_id, p_actor_auth_user_id, p_page, p_page_size);
$wrap$;

comment on function public.list_contacts(uuid, uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_contacts with an identical grant set, never a reimplementation.';

revoke execute on function app.list_contacts(uuid, uuid, integer, integer) from public;
grant execute on function app.list_contacts(uuid, uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_contacts(uuid, uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_contacts(uuid, uuid, integer, integer) to authenticated, service_role;

-- TS INTEGRATION: server/queries/contact.ts `listContacts`
-- 1. Change the client param type from `Pick<SupabaseClient, "from">` to
--    `Pick<SupabaseClient, "rpc">` (mirrors findDuplicateContacts' own
--    ContactQueryRpcClient type immediately above it in the same file -- reuse that
--    type, or widen it, rather than adding a third).
-- 2. Add `actorAuthUserId: string` to `ListContactsInput` (both call sites --
--    app/(tenant)/[tenantSlug]/commercial/contacts/page.tsx:37 and .../quotations/
--    [quotationId]/page.tsx:86 -- already resolve `access.authUserId` via
--    resolveCommercialAccessForRequest and simply need to pass it through:
--    `listContacts(supabase, { tenantId: access.tenant.id, page, actorAuthUserId: access.authUserId })`).
-- 3. Replace the `.from("contacts").select("*", {count:"exact"}).eq("tenant_id", ...)
--    .order("full_name", {ascending:true}).range(from, to)` chain with:
--      const { data, error } = await client.rpc("list_contacts", {
--        p_tenant_id: input.tenantId,
--        p_actor_auth_user_id: input.actorAuthUserId,
--        p_page: page,
--        p_page_size: pageSize,
--      });
--    (keep the existing `page`/`pageSize` clamping logic exactly as-is -- it still
--    bounds what gets sent as p_page/p_page_size).
-- 4. `count: "exact"`'s separate `count` return value goes away; total_count now rides
--    on each returned row. Map it as:
--      const rows = (data ?? []) as Record<string, unknown>[];
--      const totalCount = rows.length > 0 ? Number(rows[0].total_count) : 0;
--      return { contacts: rows.map(parseContact), totalCount, page, pageSize };
--    (parseContact already ignores the extra total_count field on each row -- no
--    contract change needed on server/contracts/contact/contact.ts; the RPC never
--    returns normalized_email/normalized_phone/duplicate_fingerprint at all).
-- 5. Error handling is unchanged: `if (error) throw new ContactQueryError(error.message);`.

-- ============================================================================
-- 2. app.get_contact_by_id -- replaces server/queries/contact.ts:82 (getContactById).
-- ============================================================================

create function app.get_contact_by_id(
  p_contact_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  full_name text,
  title text,
  email text,
  phone text,
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
  v_contact app.contacts;
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_contact from app.contacts c where c.id = p_contact_id;

  -- Anti-enumeration, matching this read's own current contract ("returns null, never
  -- an error, when RLS/no-match yields zero rows" -- server/queries/contact.ts:80's own
  -- docstring) and the same "no row, not an exception" idiom app.resolve_tenant_by_
  -- slug_for_actor already established (20260906090000) for an unauthorized vs.
  -- nonexistent single-row lookup: a nonexistent id and an id the actor cannot access
  -- both collapse to zero rows, never a thrown error, so a caller cannot distinguish
  -- "wrong id" from "exists, not yours" -- exactly RLS's own behavior today.
  if not found
     or not app.can_access_record(
       p_actor_auth_user_id, v_contact.tenant_id, v_contact.owner_user_id,
       app.lead_record_scope_org_unit_ids(v_contact.org_unit_id), null
     )
  then
    return;
  end if;

  -- Deliberate column exclusion (RULE per this migration's own header): never return
  -- normalized_email/normalized_phone/duplicate_fingerprint, matching app.list_contacts.
  id := v_contact.id; tenant_id := v_contact.tenant_id; full_name := v_contact.full_name;
  title := v_contact.title; email := v_contact.email; phone := v_contact.phone;
  status := v_contact.status; owner_user_id := v_contact.owner_user_id;
  org_unit_id := v_contact.org_unit_id; record_version := v_contact.record_version;
  created_by := v_contact.created_by; created_at := v_contact.created_at;
  updated_at := v_contact.updated_at;
  return next;
end;
$$;

comment on function app.get_contact_by_id(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1: single-contact read for the Contact Detail view, replacing server/queries/contact.ts:82''s broken .from("contacts") (app is not exposed to PostgREST). Authority predicate reproduces app.contacts'' own contacts_select_scoped RLS predicate exactly (app.can_access_record(actor, tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null) -- unaltered since 20260723150000, confirmed via grep for a later ALTER POLICY, none found). Returns zero rows (never an exception) for a nonexistent id or one the actor cannot access, matching both the current .from()+RLS behavior and app.resolve_tenant_by_slug_for_actor''s own anti-enumeration posture -- a caller cannot distinguish "does not exist" from "exists, not yours".';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_contact_by_id with an identical grant set, never a reimplementation.
create function public.get_contact_by_id(
  p_contact_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  full_name text,
  title text,
  email text,
  phone text,
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
  select * from app.get_contact_by_id(p_contact_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_contact_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_contact_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_contact_by_id(uuid, uuid) from public;
grant execute on function app.get_contact_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_contact_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_contact_by_id(uuid, uuid) to authenticated, service_role;

-- TS INTEGRATION: server/queries/contact.ts `getContactById`
-- 1. Signature changes from `(client: Pick<SupabaseClient, "from">, contactId: string)`
--    to `(client: Pick<SupabaseClient, "rpc">, contactId: string, actorAuthUserId: string)`.
-- 2. Its one call site (app/(tenant)/[tenantSlug]/commercial/contacts/[contactId]/
--    page.tsx:25) already has `access.authUserId` in scope (from
--    resolveCommercialAccessForRequest, resolved at line 16-19 before this call) --
--    change the call to `getContactById(supabase, contactId, access.authUserId)`.
-- 3. Replace `.from("contacts").select("*").eq("id", contactId).maybeSingle()` with:
--      const { data, error } = await client.rpc("get_contact_by_id", {
--        p_contact_id: contactId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    then, since a set-returning RPC always comes back as an array (never
--    single-row-shaped the way `.maybeSingle()` was):
--      if (error) throw new ContactQueryError(error.message);
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseContact(row as Record<string, unknown>);
--    (mirrors the exact `Array.isArray(data) ? data[0] : data` idiom
--    lib/portal/tenant-admin-guard-deps.server.ts already uses for its own
--    resolve_tenant_by_slug_for_actor RPC call).
-- 4. The page's own existing post-fetch tenant check
--    (`if (!contact || contact.tenantId !== access.tenant.id) notFound();`) is
--    unchanged and remains correct -- it is a defense-in-depth belt-and-suspenders
--    check on top of the RPC's own tenant-scoped authority predicate, not a
--    replacement for it.
-- ============================================================================
-- app.activities read remediation (Option-2 wrapper pattern)
-- ============================================================================
-- Replaces the broken PostgREST-schema-invisible call site:
--   server/queries/contact.ts:99 (listActivitiesForRecord) --
--     `client.from("activities").select("*").eq("related_type", relatedType)
--      .eq("related_id", relatedId).order("created_at", { ascending: false })`
--   Table read: app.activities (base table, NOT a view -- created by
--   supabase/migrations/20260723150000_create_commercial_contact_activity_management.sql,
--   lines 331-357; confirmed via grep this table has never been dropped/recreated
--   and its CREATE TABLE statement appears exactly once in supabase/migrations/*.sql).
--
--   Column list confirmed by direct read of that CREATE TABLE (18 columns): id,
--   tenant_id, type, subject, notes, status, due_at, completed_at, outcome,
--   related_type, related_id, contact_id, owner_user_id, org_unit_id,
--   record_version, created_by, created_at, updated_at. No cost/margin/sell-price
--   or other sensitive column exists on this table -- there is no masking logic to
--   replicate (unlike a "_directory" view). "select *" is therefore faithfully
--   reproduced with no column exclusion, matching the original .from() call exactly.
--
--   related_type has been extended from ('lead','prospect') to also accept
--   'opportunity' by supabase/migrations/20260723210000_create_commercial_opportunity_management.sql
--   (ALTER TABLE app.activities DROP/ADD CONSTRAINT activities_related_type_check,
--   lines 548-549 of that file) -- confirmed via grep across all migrations for
--   "app.activities" (RULE B check: this is a CHECK-constraint widening, not an
--   RLS policy rewrite, and is honored below simply by accepting whatever
--   related_type text the CHECK constraint currently allows; the function does not
--   hard-code the allowed value list). The TS RelatedType contract
--   (server/contracts/contact/contact.ts RELATED_TYPES) already reflects this.
--
-- AUTHORITY RULE ENFORCED (RULE B/C precedent chain, verified by direct grep+read,
-- not assumed):
--   1. RLS predicate: `create policy activities_select_scoped on app.activities for
--      select to authenticated using (app.can_access_record((select auth.uid()),
--      tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id),
--      null));` -- declared ONCE, in 20260723150000 (lines 601-605). RULE B check:
--      grepped "alter policy.*activities" and "activities_select_scoped" across every
--      file in supabase/migrations/*.sql -- the ONLY hit in the whole tree is that
--      original CREATE POLICY statement itself. No later ALTER POLICY, and no later
--      CREATE POLICY of the same name, exists anywhere. This is therefore the current,
--      unmodified authority envelope, and the function below reproduces it verbatim
--      (substituting the asserted p_actor_auth_user_id for auth.uid()).
--   2. app.can_access_record signature/body: RULE C check -- grepped
--      "function app.can_access_record" repo-wide. Two hits: the original
--      (20260716110430_create_field_record_access.sql) and exactly one
--      `create or replace` (20260723180000_create_commercial_sales_pipeline.sql,
--      lines 50-88, the "NULL owner_user_id must not silently grant access" fix). No
--      later replace exists (confirmed repo-wide grep). That is the version being
--      relied on here; its signature
--      (auth_user_id, tenant_id, owner_user_id, shared_org_unit_ids[], customer_account_ref)
--      is exactly what app.activities' own RLS policy already calls it with, and what
--      every activities mutation function (log_activity/complete_activity/
--      reschedule_activity/cancel_activity, same migration) already calls it with.
--   3. Direct row-level read precedent over this SAME table: RULE C check --
--      grepped "get_dashboard_activity_queue" repo-wide (3 defining hits): original
--      creation (20260724320000_create_commercial_dashboard.sql, no actor-identity
--      assert, LANGUAGE SQL) and exactly one later `create or replace`
--      (20260810200000_harden_dashboard_actor_identity_gaps.sql, lines 254-287,
--      switched to LANGUAGE PLPGSQL specifically to add
--      `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as its
--      first statement, ATW-032). That later, patched body is the one imitated below:
--      it already reads app.activities row-by-row and applies
--      `app.can_access_record(p_actor_auth_user_id, a.tenant_id, a.owner_user_id,
--      app.lead_record_scope_org_unit_ids(a.org_unit_id), null)` as an explicit WHERE
--      predicate -- i.e. the exact per-row reproduction of activities_select_scoped
--      this migration also needs, from the most recent, already-hardened sibling.
--   4. Actor-impersonation guard (RULE A): app.list_activities_for_record takes an
--      explicit p_actor_auth_user_id and is granted to `authenticated` (a tenant
--      member reading their own record's timeline, not a service_role-only surface),
--      so `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the
--      first executable statement in the function body, before any lookup --
--      identical placement to app.cancel_activity/app.complete_activity/
--      app.reschedule_activity's own ATW-032 patches
--      (20260730510000_harden_actor_identity_unchecked_authority_surface.sql) and to
--      app.get_dashboard_activity_queue's patch above. RULE C staleness check for
--      app.assert_actor_is_session_identity itself: repo-wide grep for
--      "function app.assert_actor_is_session_identity" finds exactly one definition
--      (20260730440000_harden_actor_identity_session_crosscheck.sql) -- no later
--      replace exists, so there is no stale-precedent risk on the assert helper itself.
--   5. Option-2 public.* wrapper shape/grant-parity: imitates the CURRENT, most recent
--      instance of this exact remediation effort,
--      supabase/migrations/20260907150000_fix_remaining_tenant_lookup_guards_postgrest_schema_exposure_iss_o1_o2.sql
--      (app.resolve_tenant_by_slug_for_member / public.resolve_tenant_by_slug_for_member,
--      lines 43-91) -- itself modeled on the ISS-2026-309 corrective grant-parity fix
--      (20260902075500_fix_iss2026309_class_wrapper_grant_parity_for_new_functions.sql):
--      `revoke ... from anon, authenticated, service_role, public;` before re-granting
--      only the roles the app.* counterpart actually holds, never a bare
--      "revoke ... from public" (which leaves Supabase's own default `anon` EXECUTE
--      grant on public.* functions untouched).
--
-- Deliberate design choice, disclosed (see openQuestions in the structured response):
-- the original `.from()` call carried no `.range()`/limit at all (truly unbounded).
-- This migration adds a safety-bounded `p_limit integer default 200`
-- (`limit least(coalesce(p_limit, 200), 200)`), matching this codebase's own
-- documented safe-default convention for a "returns table"/"setof" list read when no
-- sibling function on the SAME table already establishes a pagination shape to match
-- (no other read/list function exists over app.activities to mirror). Ordering
-- (`order by created_at desc`) is preserved exactly from the original call.
-- ============================================================================

create function app.list_activities_for_record(
  p_related_type text,
  p_related_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.activities
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A (ATW-032, ISS-2026-017/032): must be the first executable statement,
  -- before any lookup or authority check -- see app.cancel_activity/
  -- app.get_dashboard_activity_queue's own ATW-032 patches, imitated here.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select a.*
  from app.activities a
  where a.related_type = p_related_type
    and a.related_id = p_related_id
    -- Verbatim reproduction of activities_select_scoped (RULE B: confirmed current,
    -- never ALTER'd -- see header) applied per-row, exactly as RLS itself would.
    and app.can_access_record(
      p_actor_auth_user_id, a.tenant_id, a.owner_user_id,
      app.lead_record_scope_org_unit_ids(a.org_unit_id), null
    )
  order by a.created_at desc
  limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_activities_for_record is
  'COM-145 remediation (app schema not exposed to PostgREST): unified activity timeline for one related lead/prospect/opportunity record, most recent first. Row-filtered by the exact same app.can_access_record predicate activities_select_scoped (20260723150000, never ALTER''d) applies via RLS -- this function is a SECURITY DEFINER re-statement of that same predicate per row, not a widened or narrowed one. Actor-identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A / ATW-032). Bounded to at most 200 rows (p_limit, default+cap 200) -- the original .from() read this replaces carried no bound at all; see this file''s own header and the accompanying structured-output openQuestions for why a bound was added here.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_activities_for_record with an identical grant set, never a
-- reimplementation.
create function public.list_activities_for_record(
  p_related_type text,
  p_related_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.activities
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_activities_for_record(p_related_type, p_related_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_activities_for_record is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_activities_for_record with an identical grant set, never a reimplementation.';

-- app.list_activities_for_record grants -- mirrors this same table's own sibling
-- functions (log_activity/complete_activity/reschedule_activity/cancel_activity, all
-- granted "to authenticated, service_role" in 20260723150000) and the most recent
-- same-remediation precedent's two-line style
-- (20260907150000_fix_remaining_tenant_lookup_guards_postgrest_schema_exposure_iss_o1_o2.sql).
revoke execute on function app.list_activities_for_record(text, uuid, uuid, integer) from public;
grant execute on function app.list_activities_for_record(text, uuid, uuid, integer) to authenticated;
grant execute on function app.list_activities_for_record(text, uuid, uuid, integer) to service_role;

-- public.list_activities_for_record grants -- ISS-2026-309-corrected pattern: revoke
-- from anon, authenticated, service_role, AND public explicitly (a bare "from public"
-- never touches Supabase's own default anon EXECUTE grant on public.* functions), then
-- grant back only the roles the app.* counterpart actually holds (authenticated,
-- service_role -- never anon).
revoke execute on function public.list_activities_for_record(text, uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_activities_for_record(text, uuid, uuid, integer) to authenticated, service_role;

-- ============================================================================
-- TS INTEGRATION:
-- ============================================================================
-- File: server/queries/contact.ts
--
-- 1. Change `listActivitiesForRecord`'s client parameter type from
--    `Pick<SupabaseClient, "from">` to the already-exported `ContactQueryRpcClient`
--    (`Pick<SupabaseClient, "rpc">`, defined at the top of this same file and already
--    used by `findDuplicateContacts`).
--
-- 2. Add a new required parameter `actorAuthUserId: string` to
--    `listActivitiesForRecord` (position: after `relatedId`, matching
--    `findDuplicateContacts`'s own `tenantId, actorAuthUserId, ...` ordering
--    convention of "identifying/filter params first, actor last before options").
--    New signature:
--      listActivitiesForRecord(
--        client: ContactQueryRpcClient,
--        relatedType: RelatedType,
--        relatedId: string,
--        actorAuthUserId: string,
--      ): Promise<Activity[]>
--
-- 3. Replace the function body''s `.from(...)` chain with an `.rpc()` call to the new
--    `list_activities_for_record` RPC, passing exactly these p_* arguments (this
--    order does not matter for a named-args rpc() call, but match this order for
--    consistency with the SQL declaration):
--      const { data, error } = await client.rpc("list_activities_for_record", {
--        p_related_type: relatedType,
--        p_related_id: relatedId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (p_limit is intentionally omitted -- the RPC''s own `default 200` applies; only
--    pass p_limit explicitly if a future caller needs a different bound.)
--
-- 4. Keep the existing error/shape handling identical to `findDuplicateContacts`:
--      if (error) throw new ContactQueryError(error.message);
--      if (!Array.isArray(data)) throw new ContactQueryError("list_activities_for_record returned a non-array result");
--      return data.map((row) => parseActivity(row as Record<string, unknown>));
--    `parseActivity` (server/contracts/contact/contact.ts) already maps every
--    snake_case column this RPC returns (id, tenant_id, type, subject, notes, status,
--    due_at, completed_at, outcome, related_type, related_id, contact_id,
--    owner_user_id, org_unit_id, record_version, created_by, created_at, updated_at)
--    to the existing camelCase `Activity` contract -- no contract change needed, since
--    `returns setof app.activities` yields the identical column set the old
--    `select("*")` did.
--
-- 5. Update all three call sites to pass the actor id (each already has it in scope
--    as `access.authUserId` from `resolveCommercialAccessForRequest`/equivalent):
--      - app/(tenant)/[tenantSlug]/commercial/leads/[leadId]/page.tsx:43
--          `listActivitiesForRecord(supabase, "lead", lead.id, access.authUserId)`
--      - app/(tenant)/[tenantSlug]/commercial/prospects/[prospectId]/page.tsx:47
--          `listActivitiesForRecord(supabase, "prospect", prospect.id, access.authUserId)`
--      - app/(tenant)/[tenantSlug]/commercial/opportunities/[opportunityId]/page.tsx:51
--          `listActivitiesForRecord(supabase, "opportunity", opportunity.id, access.authUserId)`
--
-- 6. server/queries/contact.test.ts's existing `listActivitiesForRecord` describe
--    block currently builds a fake `.from()`-chain client (`fakeTableClient`) and
--    calls `listActivitiesForRecord(client, "lead", LEAD_ID)` (no actor id, 3 args).
--    Update it to the same rpc-fake-client shape `findDuplicateContacts`'s own test
--    already uses (a plain `{ async rpc(fn, args) { ... } }` object), asserting the
--    call is `list_activities_for_record` with args
--    `{ p_related_type: "lead", p_related_id: LEAD_ID, p_actor_auth_user_id: ACTOR_ID }`,
--    and pass `ACTOR_ID` (already defined in that test file) as the new 4th argument.
-- ============================================================================
-- CG-AUDIT-2026-09-02 O1 remediation -- app.customer_contracts query layer.
-- supabase/config.toml exposes only public/graphql_public to PostgREST; app is invisible
-- to it. server/queries/contract.ts's four base-table reads (listCustomerContracts,
-- listCustomerContractVersions, getCustomerContractById, getCustomerContractForQuotation)
-- all call `.from("customer_contracts")`, which is broken in production for exactly that
-- reason. This migration adds one real, SECURITY DEFINER app.* function per read plus an
-- identically-granted Option-2 public.* pass-through wrapper (app is not PostgREST-visible,
-- so public.* is the only reachable surface), following the exact pattern already proven by
-- 20260907150000 (app.resolve_tenant_by_slug_for_member) and 20260831140000
-- (app.list_files_for_tenant).
--
-- Suggested filename when this is filed as a real migration:
--   supabase/migrations/20260908010000_fix_customer_contracts_postgrest_schema_exposure.sql
--
-- ===========================================================================
-- Authority envelope (applies to all four functions below)
-- ===========================================================================
-- app.customer_contracts carries exactly one live SELECT policy, most recently rewritten by
-- 20260730560000 (`alter policy customer_contracts_select_scoped ...`):
--
--   (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id))
--   OR app.is_supreme_admin()
--
-- i.e. tenant-wide reference data, gated on active tenant membership only (no
-- app.evaluate_permission/module:permission check -- the table's own mutations use COM:Edit
-- /COM:Approve, but no COM:View gate exists anywhere for a plain read of this header table),
-- and explicitly excluding the customer_user portal layer (20260730560000's own
-- default-deny hardening: a customer_user principal satisfies has_active_tenant_membership,
-- so the exclusion has to be spelled out, it is not implied). This is also exactly the
-- posture `lib/portal/commercial-guard.ts` already enforces one layer up: its "allowed"
-- result only ever carries layer "tenant_admin" | "org_user", never "customer_user".
-- Because every function below is SECURITY DEFINER, Postgres RLS on app.customer_contracts
-- itself never runs for these calls (the function owner bypasses it) -- so each function
-- below re-states the policy's own predicate explicitly, verbatim, rather than relying on
-- RLS to filter anything, the same discipline app.list_files_for_tenant/app.list_finance_invoices
-- /app.get_effective_customer_price already established for every other SECURITY DEFINER
-- reader in this schema.
--
-- Column exclusions: none. app.customer_contracts carries no money/hash/secret column --
-- selling-price figures live one table over, in app.customer_contract_price_components, and
-- are masked there via app.customer_contract_price_components_directory (COM:View selling
-- price), which is a separate, already-reachable read path this migration does not touch.
-- Every function below is therefore a plain, unmasked `select *` / `returns setof
-- app.customer_contracts`, matching contract.ts's own header comment ("Base-table reads of
-- app.customer_contracts are unmasked -- no money columns live there").
--
-- Actor-identity cross-check: every function takes p_actor_auth_user_id as an explicit
-- argument (not the `default auth.uid()` shape app.has_active_tenant_membership/
-- app.is_supreme_admin themselves use), so each one opens with
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` -- ATW-031
-- (ISS-2026-017)'s standing rule for exactly this shape, already the pattern
-- app.list_files_for_tenant and app.resolve_tenant_by_slug_for_member both follow.

-- ===========================================================================
-- 1. app.list_customer_contracts -- replaces server/queries/contract.ts:35
--    (listCustomerContracts: select * from customer_contracts, eq tenant_id, order
--    created_at desc, bounded range(200) -- tenant contracts list page)
-- ===========================================================================
-- Authority: the table's own customer_contracts_select_scoped predicate (see envelope
-- above), applied against the CALLER'S OWN claimed p_tenant_id and raising on failure --
-- the same shape app.list_files_for_tenant/app.list_finance_invoices/app.list_rfqs already
-- use for a "list everything I as a tenant member am entitled to see" RPC (an explicit
-- p_tenant_id argument the caller is claiming to belong to is worth failing loudly on, not
-- silently returning zero rows for).
-- Pagination: `server/queries/bounded-list.ts` names this exact function (`listCustomerContracts`)
-- as one of the four ISS-2026-238 "reads every row, no cap" defects, in the same remediation
-- effort that already fixed app.list_files_for_tenant (20260831140000) by hard-clamping to
-- <=200 server-side and having the TS caller report truncation via
-- `toBoundedListByCapReached` (cap-reached is treated as "there may be more", not proven).
-- app.list_files_for_tenant is the closer sibling than app.list_finance_invoices/app.list_rfqs
-- (those predate the BoundedList convention and silently cap with no truncation signal at
-- all) -- so this function mirrors app.list_files_for_tenant's own clamp exactly. See the
-- open question in the final TS INTEGRATION note: this is a deliberate, disclosed change
-- from the *old* JS-side "fetch 201, slice to 200" truncation trick that `boundedRange()`/
-- `toBoundedList()` implement today, since a plain `limit` cannot recreate that trick without
-- either a second round trip or returning one extra row the caller must know to discard --
-- `list_files_for_tenant` already made and shipped exactly this trade-off.
create function app.list_customer_contracts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.customer_contracts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  -- Same clamp app.list_files_for_tenant uses: 200 matches BOUNDED_LIST_LIMIT, and a
  -- caller-supplied value is clamped rather than rejected -- asking for too many rows is a
  -- caller mistake, not something worth failing the whole page load over.
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 200);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
       and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    or app.is_supreme_admin(p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % has no active tenant membership (or holds the excluded customer_user layer) for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.customer_contracts
  where tenant_id = p_tenant_id
  -- id tie-break added for deterministic ordering at the cap boundary (created_at alone can
  -- tie); matches app.list_files_for_tenant's own "order by ..., id" defensive style. Purely
  -- additive -- the original `.order("created_at", { ascending: false })` had no tie-break at
  -- all, so this changes nothing observable except which of two same-instant rows sorts
  -- first, which was previously undefined.
  order by created_at desc, id
  limit v_limit;
end;
$$;

comment on function app.list_customer_contracts is
  'CG-AUDIT-2026-09-02 O1: replaces the broken .from("customer_contracts") read at server/queries/contract.ts:35 (app is not exposed to PostgREST). Tenant-wide, not record-scoped -- reproduces customer_contracts_select_scoped (20260730560000) verbatim: active tenant membership required, customer_user layer explicitly excluded, supreme_admin always allowed. Raises insufficient_privilege for a caller with no standing in p_tenant_id (matching app.list_files_for_tenant''s own posture for an explicit-tenant-argument list). Capped at <=200 rows (ISS-2026-238), clamped not rejected, same convention app.list_files_for_tenant (20260831140000) already established -- the caller should treat "returned rows = 200" as "there may be more" (see server/queries/bounded-list.ts''s toBoundedListByCapReached).';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_customer_contracts with an identical grant set, never a
-- reimplementation.
create function public.list_customer_contracts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.customer_contracts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_customer_contracts(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_customer_contracts(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_customer_contracts with an identical grant set, never a reimplementation.';

revoke execute on function app.list_customer_contracts(uuid, uuid, integer) from public;
grant execute on function app.list_customer_contracts(uuid, uuid, integer) to authenticated, service_role;

-- `from anon, ...`, not `from public` alone: Supabase's ALTER DEFAULT PRIVILEGES grants anon
-- EXECUTE explicitly at CREATE time, and an explicit grant survives a bare PUBLIC revoke
-- (ISS-2026-309).
revoke execute on function public.list_customer_contracts(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_customer_contracts(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_customer_contract_versions -- replaces server/queries/contract.ts:48
--    (listCustomerContractVersions: select * from customer_contracts, eq root_contract_id,
--    order version_number asc -- contract version history)
-- ===========================================================================
-- Authority: same customer_contracts_select_scoped predicate, but there is no independent
-- caller-claimed p_tenant_id argument here (the current .from() call has none either -- it
-- filters only by root_contract_id and relies on RLS for scoping). Every row sharing one
-- root_contract_id is guaranteed same-tenant by construction (app.create_customer_contract_draft's
-- own renewal path always copies v_source.tenant_id forward; there is no code path that
-- inserts a second tenant under one root), so the predicate is evaluated per-row against
-- that row's own tenant_id and used as a plain filter -- unauthorized rows are silently
-- omitted rather than raised, mirroring the posture contract.ts's own callers already rely
-- on (the contract detail page independently re-checks `contract.tenantId !== access.tenant.id`
-- after fetching by id, i.e. this codebase already treats "wrong tenant" as a quiet
-- not-found here, never a thrown error).
-- No pagination cap: CG-AUDIT-2026-09-02's own ISS-2026-238 finding names only
-- listCustomerContracts as unbounded; a contract's own version count is bounded by real
-- business cardinality (renewals/amendments to one commercial agreement), the same
-- "naturally bounded" exemption 20260831140000's own header already carves out for
-- config/rule/directory-shaped reads. Matches the original .ts, which never bounded this
-- read either.
create function app.list_customer_contract_versions(
  p_root_contract_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.customer_contracts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select cc.* from app.customer_contracts cc
  where cc.root_contract_id = p_root_contract_id
    and (
      (app.has_active_tenant_membership(cc.tenant_id, p_actor_auth_user_id)
         and not app.actor_holds_customer_user_layer(cc.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by cc.version_number asc;
end;
$$;

comment on function app.list_customer_contract_versions is
  'CG-AUDIT-2026-09-02 O1: replaces the broken .from("customer_contracts") read at server/queries/contract.ts:48. Every version under one root_contract_id is same-tenant by construction (app.create_customer_contract_draft''s renewal path always carries v_source.tenant_id forward), so customer_contracts_select_scoped (20260730560000) is evaluated per-row against that row''s own tenant_id: active membership required, customer_user layer excluded, supreme_admin always allowed. No raise on a mismatch -- an out-of-scope root_contract_id (or one belonging to a tenant the caller does not belong to) simply yields zero rows, matching the "quiet not-found" posture the contract detail page already relies on for a wrong-tenant contract id. Unbounded: a contract''s own version count is real business cardinality, not an ISS-2026-238 unbounded-base-table defect.';

create function public.list_customer_contract_versions(
  p_root_contract_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.customer_contracts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_customer_contract_versions(p_root_contract_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_customer_contract_versions(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_customer_contract_versions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_customer_contract_versions(uuid, uuid) from public;
grant execute on function app.list_customer_contract_versions(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_customer_contract_versions(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_customer_contract_versions(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 3. app.get_customer_contract_by_id -- replaces server/queries/contract.ts:57
--    (getCustomerContractById: select * from customer_contracts, eq id, maybeSingle --
--    contract detail page)
-- ===========================================================================
-- Authority: identical per-row predicate as (2) above, evaluated against the fetched row's
-- own tenant_id. Returns zero rows (never raises) on a non-existent id OR an id the caller's
-- tenant membership does not cover -- contract.ts's own docstring already commits to this
-- exact posture ("Returns null when not found or RLS denies it (matching every prior
-- Commercial detail-page query's posture)"), so this function reproduces that as literally
-- as SQL allows: `limit 1` on a filtered select, zero rows in either failure case, letting
-- the TS caller collapse both into null identically to a `.maybeSingle()` result that RLS
-- silently emptied.
-- No column exclusions (see envelope note above).
create function app.get_customer_contract_by_id(
  p_contract_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.customer_contracts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select * from app.customer_contracts
  where id = p_contract_id
    and (
      (app.has_active_tenant_membership(tenant_id, p_actor_auth_user_id)
         and not app.actor_holds_customer_user_layer(tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  limit 1;
end;
$$;

comment on function app.get_customer_contract_by_id is
  'CG-AUDIT-2026-09-02 O1: replaces the broken .from("customer_contracts") read at server/queries/contract.ts:57. Applies customer_contracts_select_scoped (20260730560000) against the fetched row''s own tenant_id: active membership required, customer_user layer excluded, supreme_admin always allowed. Returns zero rows -- never raises -- for a nonexistent id or one the caller''s tenant membership does not cover, matching contract.ts''s own documented "returns null when not found or RLS denies it" posture exactly (the same behavior a `.maybeSingle()` read against an RLS-filtered table already had). No column exclusions: app.customer_contracts carries no money/secret column.';

create function public.get_customer_contract_by_id(
  p_contract_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.customer_contracts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_customer_contract_by_id(p_contract_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_customer_contract_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_customer_contract_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_customer_contract_by_id(uuid, uuid) from public;
grant execute on function app.get_customer_contract_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_customer_contract_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_customer_contract_by_id(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 4. app.get_customer_contract_for_quotation -- replaces server/queries/contract.ts:69
--    (getCustomerContractForQuotation: select * from customer_contracts, eq
--    source_quotation_id, maybeSingle -- "did this quotation source a contract" lookup)
-- ===========================================================================
-- Authority: identical per-row predicate again, evaluated against the fetched row's own
-- tenant_id -- same "zero rows, never raise" posture as (3), matching contract.ts's own
-- docstring for this function ("Returns null when the quotation has never sourced a
-- contract"), now also covering "...or the caller's tenant membership does not reach it."
-- `limit 1` is a defensive belt-and-suspenders match to the real, enforced structural
-- invariant: app.create_customer_contract_draft raises quotation_already_contracted before
-- ever inserting a second row with the same source_quotation_id, so at most one row can
-- ever match -- the same "structurally at most one row" reasoning
-- app.get_effective_customer_price's own comment already documents for this table.
create function app.get_customer_contract_for_quotation(
  p_source_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.customer_contracts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select * from app.customer_contracts
  where source_quotation_id = p_source_quotation_id
    and (
      (app.has_active_tenant_membership(tenant_id, p_actor_auth_user_id)
         and not app.actor_holds_customer_user_layer(tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  limit 1;
end;
$$;

comment on function app.get_customer_contract_for_quotation is
  'CG-AUDIT-2026-09-02 O1: replaces the broken .from("customer_contracts") read at server/queries/contract.ts:69. Applies customer_contracts_select_scoped (20260730560000) against the fetched row''s own tenant_id: active membership required, customer_user layer excluded, supreme_admin always allowed. Returns zero rows -- never raises -- when the quotation never sourced a contract or the caller''s tenant membership does not cover it, matching contract.ts''s own documented posture. `limit 1` matches the real structural invariant app.create_customer_contract_draft enforces (quotation_already_contracted): at most one contract root can ever share one source_quotation_id.';

create function public.get_customer_contract_for_quotation(
  p_source_quotation_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.customer_contracts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_customer_contract_for_quotation(p_source_quotation_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_customer_contract_for_quotation(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_customer_contract_for_quotation with an identical grant set, never a reimplementation.';

revoke execute on function app.get_customer_contract_for_quotation(uuid, uuid) from public;
grant execute on function app.get_customer_contract_for_quotation(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_customer_contract_for_quotation(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_customer_contract_for_quotation(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/contract.ts. All four functions currently share
-- `ContractQueryClient = Pick<SupabaseClient, "from" | "rpc">` -- after this change "from" is
-- no longer used anywhere in the file and can be dropped from that type (keep "rpc" only,
-- matching getEffectiveCustomerPrice's own client type usage today).
--
-- Every one of the four functions below gains a new required `actorAuthUserId: string`
-- parameter (needed because the authority check now runs inside the SECURITY DEFINER RPC
-- instead of Postgres RLS). All three call sites already have this value in scope as
-- `access.authUserId` (the "allowed" branch of `CommercialGuardResult`,
-- lib/portal/commercial-guard.ts) -- no new plumbing is required, only passing it through:
--   - app/(tenant)/[tenantSlug]/commercial/contracts/page.tsx
--       listCustomerContracts(supabase, access.tenant.id)
--       -> listCustomerContracts(supabase, access.tenant.id, access.authUserId)
--   - app/(tenant)/[tenantSlug]/commercial/contracts/[contractId]/page.tsx
--       getCustomerContractById(supabase, contractId)
--       -> getCustomerContractById(supabase, contractId, access.authUserId)
--       listCustomerContractVersions(supabase, contract.rootContractId)
--       -> listCustomerContractVersions(supabase, contract.rootContractId, access.authUserId)
--   - app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/page.tsx
--       getCustomerContractForQuotation(supabase, quotation.id)
--       -> getCustomerContractForQuotation(supabase, quotation.id, access.authUserId)
--
-- 1. listCustomerContracts(client, tenantId, actorAuthUserId: string): Promise<BoundedList<CustomerContract>>
--    Replace the .from()/.eq()/.order()/.range() chain with:
--      const { data, error } = await client.rpc("list_customer_contracts", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--        p_limit: BOUNDED_LIST_LIMIT,
--      });
--    then `if (error) throw new ContractQueryError(error.message);`.
--    IMPORTANT semantic change (disclosed above): app.list_customer_contracts hard-clamps to
--    <=200 rows server-side and does not return the 201st "proof of truncation" row the old
--    `.range(0, 200)` call did. Switch the truncation signal from `toBoundedList` to
--    `toBoundedListByCapReached` (already exported by ./bounded-list.ts, already used by
--    document.ts for the identical list_files_for_tenant conversion):
--      return toBoundedListByCapReached(((data as unknown[] | null) ?? []).map((row) =>
--        parseCustomerContract(row as Record<string, unknown>)));
--    (drop the now-unused `boundedRange`/`range` import/usage for this function; `toBoundedList`
--    may still be imported if another function in this file keeps using it -- it does not,
--    after this change, so the import can be narrowed to `toBoundedListByCapReached` only).
--
-- 2. listCustomerContractVersions(client, rootContractId, actorAuthUserId: string): Promise<CustomerContract[]>
--      const { data, error } = await client.rpc("list_customer_contract_versions", {
--        p_root_contract_id: rootContractId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    then the existing `if (error) throw ...; return (data ?? []).map((row) =>
--    parseCustomerContract(row as Record<string, unknown>));` body is unchanged.
--
-- 3. getCustomerContractById(client, contractId, actorAuthUserId: string): Promise<CustomerContract | null>
--      const { data, error } = await client.rpc("get_customer_contract_by_id", {
--        p_contract_id: contractId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    then `if (error) throw new ContractQueryError(error.message);`, and since the RPC
--    returns a set (0 or 1 rows) rather than a single nullable object:
--      const row = Array.isArray(data) ? data[0] : data;
--      if (!row) return null;
--      return parseCustomerContract(row as Record<string, unknown>);
--    (same `Array.isArray(data) ? data[0] : data` unwrap already used by
--    getEffectiveCustomerPrice in this same file, minus its throw-on-missing branch -- this
--    one returns null instead, per its own existing docstring).
--
-- 4. getCustomerContractForQuotation(client, quotationId, actorAuthUserId: string): Promise<CustomerContract | null>
--    Identical shape to (3):
--      const { data, error } = await client.rpc("get_customer_contract_for_quotation", {
--        p_source_quotation_id: quotationId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    then the same `Array.isArray(data) ? data[0] : data` -> null-or-parse unwrap as (3).
--
-- server/queries/contract.test.ts's `fakeClient` already has a working `rpc` fake (used by
-- the existing getEffectiveCustomerPrice tests) -- the tests for these four functions need
-- to switch from asserting on `client.calls.table`/`eqCalls`/`range` to asserting on
-- `client.calls.rpc` (fn name + args), the same restructuring already done for
-- getEffectiveCustomerPrice's own test block in that file.
-- Replaces the broken PostgREST read at server/queries/contract.ts:81
-- (listCustomerContractPriceComponents: `.from("customer_contract_price_components_directory")
-- .select("*").eq("contract_id", contractId).order("created_at", { ascending: true })`).
-- app.customer_contract_price_components_directory is a VIEW (not a base table), created in
-- supabase/migrations/20260724300000_create_commercial_customer_contract_pricing.sql:559-579.
-- It lives in the "app" Postgres schema, which supabase/config.toml does not expose to
-- PostgREST ("public"/"graphql_public" only) -- so this .from() call has never worked in
-- production; it 404s as a nonexistent relation from PostgREST's point of view.
--
-- AUTHORITY / MASKING RULE ENFORCED, AND WHY
-- ------------------------------------------
-- Row visibility: `(app.has_active_tenant_membership(tenant_id, actor) and not
-- app.actor_holds_customer_user_layer(tenant_id, actor)) or app.is_supreme_admin(actor)` --
-- NOT the view's own original WHERE clause text (...create_commercial_customer_
-- contract_pricing.sql:579), which was superseded by
-- 20260730560000_harden_customer_user_layer_default_deny.sql's ALTER POLICY on the
-- identical `customer_contract_price_components_select_scoped` RLS policy on the base
-- table (same original migration, lines 695-697): that later migration added the
-- `AND NOT app.actor_holds_customer_user_layer(tenant_id)` exclusion specifically to stop a
-- customer-portal (customer_user-layer) principal -- who DOES satisfy
-- has_active_tenant_membership -- from reading tenant-wide staff pricing data. Tenant-wide,
-- not record/org-unit-scoped -- contracts hang off app.accounts, itself tenant-wide
-- reference data (the migration's own header, and COM-155, already establish this posture).
--
-- Column masking: currency/base_amount/minimum_amount/discount_pct/surcharge_components are
-- nulled (price_masked=true) for any actor lacking the real, seeded `COM:View selling price`
-- permission, gated through the existing `app.has_view_selling_price(tenant_id, actor)` helper
-- (created in 20260723210000_create_commercial_opportunity_management.sql:134-142, and already
-- reused by this same migration's app.get_effective_customer_price, lines 634/667-671). This is
-- an exact, line-for-line replication of the view's own five CASE WHEN expressions (lines
-- 570-575) -- not a reimplementation or simplification -- because `authenticated` has no
-- direct column-level grant on those five columns on the base table itself (lines 708-710),
-- so this is the only place the masking logic may legally live.
--
-- WHY THE MASKING IS RE-EXPRESSED AGAINST THE BASE TABLE, NOT BY QUERYING THE VIEW INTERNALLY:
-- the view's own CASE expressions call app.has_view_selling_price(c.tenant_id) relying on that
-- helper's *default* `auth.uid()` argument -- correct only when queried live under PostgREST
-- with a real JWT/session GUC set. Every function in this migration file instead threads an
-- explicit p_actor_auth_user_id through -- the exact same tension, and the exact same fix,
-- that app.search_vendor_rates (20260724150000_create_commercial_rate_cost_lookup.sql:490-558)
-- already documented in its own header comment (lines 479-489): "composing on top of a view
-- keyed to auth.uid() would silently return zero rows whenever this function is called without
-- a live session GUC set ... does not duplicate business logic: the ... cost-masking CASE
-- expressions are the same ones those views apply." app.search_vendor_rates resolved this by
-- re-expressing app.vendor_rate_versions_directory's own masking directly against the base
-- table with an explicit actor argument; this function does the identical thing for this view.
--
-- Deliberate column exclusion: none beyond what the view (and thus the original .from() call)
-- already excluded -- the five money/discount columns are nulled per-row (never omitted from
-- the shape), exactly matching the view's own `price_masked` contract. No new column is added
-- or dropped relative to the view's 16-column projection.
--
-- No p_limit/pagination: p_contract_id scopes the result to one contract version's own price
-- components, which `customer_contract_price_components_identity_unique` (same migration,
-- lines 157-159) structurally caps to one row per distinct (service_type, mode, origin_lane,
-- destination_lane, equipment_type) combination for that single contract -- not an open-ended,
-- tenant-wide list. The original .from() call itself never paginated (no `.range()`/`.limit()`
-- in server/queries/contract.ts:81), and the sibling in-migration read of the exact same
-- filter (`for v_component in select * from app.customer_contract_price_components where
-- contract_id = ...`, lines 283) is also unbounded. A `limit` would therefore change behavior
-- relative to both, not preserve it, so none is added here.

create function app.list_customer_contract_price_components(
  p_contract_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  tenant_id uuid,
  contract_id uuid,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  discount_pct numeric,
  surcharge_components jsonb,
  price_masked boolean,
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
    c.id,
    c.tenant_id,
    c.contract_id,
    c.service_type,
    c.mode,
    c.origin_lane,
    c.destination_lane,
    c.equipment_type,
    case when app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) then c.currency else null end as currency,
    case when app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) then c.base_amount else null end as base_amount,
    case when app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) then c.minimum_amount else null end as minimum_amount,
    case when app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) then c.discount_pct else null end as discount_pct,
    case when app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) then c.surcharge_components else null end as surcharge_components,
    not app.has_view_selling_price(c.tenant_id, p_actor_auth_user_id) as price_masked,
    c.created_by,
    c.created_at
  from app.customer_contract_price_components c
  where c.contract_id = p_contract_id
    and (
      (app.has_active_tenant_membership(c.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(c.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    )
  order by c.created_at asc;
end;
$$;

comment on function app.list_customer_contract_price_components(uuid, uuid) is
  'COM-156 Option-2 remediation: read path for app.customer_contract_price_components_directory (the app schema is not exposed to PostgREST, so the view itself is unreachable via .from()). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup. Row-visibility filter ((has_active_tenant_membership(tenant_id, actor) and not actor_holds_customer_user_layer(tenant_id, actor)) or is_supreme_admin(actor)) reproduces the CURRENT customer_contract_price_components_select_scoped RLS policy as hardened by 20260730560000, not the view''s own original (pre-hardening) WHERE text. The five-column selling-price CASE-WHEN mask (COM:View selling price, via app.has_view_selling_price) is copied verbatim from the view''s own definition, re-expressed against the base table with an explicit p_actor_auth_user_id instead of the view''s default-auth.uid() masking -- the same fix app.search_vendor_rates already established for the identical auth.uid()-in-a-view-under-RPC problem. Returns zero rows (never an exception) for a nonexistent contract_id or an actor with no membership in that contract''s tenant, matching the original RLS-filtered view''s own silent-empty-result posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_customer_contract_price_components with an identical grant set,
-- never a reimplementation.
create function public.list_customer_contract_price_components(
  p_contract_id uuid,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  tenant_id uuid,
  contract_id uuid,
  service_type text,
  mode text,
  origin_lane text,
  destination_lane text,
  equipment_type text,
  currency text,
  base_amount numeric,
  minimum_amount numeric,
  discount_pct numeric,
  surcharge_components jsonb,
  price_masked boolean,
  created_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_customer_contract_price_components(p_contract_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_customer_contract_price_components(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_customer_contract_price_components with an identical grant set, never a reimplementation.';

-- app.list_customer_contract_price_components: same grant set as the view it replaces
-- (`grant select on app.customer_contract_price_components_directory to authenticated,
-- service_role;`, ...create_commercial_customer_contract_pricing.sql:714) and as the other
-- read/mutation functions over this same table in that migration (lines 716-718).
revoke execute on function app.list_customer_contract_price_components(uuid, uuid) from public;
grant execute on function app.list_customer_contract_price_components(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (docs/runtime/KNOWN_ISSUES.md,
-- 20260830200000_correct_public_wrapper_grant_parity.sql): Supabase's own ALTER DEFAULT
-- PRIVILEGES rule grants EXECUTE on every new public.* function to `anon` and `authenticated`
-- at CREATE time, so `revoke ... from public` alone (the PUBLIC pseudo-role) never removes
-- those two role-specific grants. Revoke all four explicitly, then grant back only the roles
-- app.list_customer_contract_price_components itself grants to, minus anon.
revoke execute on function public.list_customer_contract_price_components(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_customer_contract_price_components(uuid, uuid) to authenticated, service_role;

-- TS INTEGRATION:
-- File: server/queries/contract.ts, function listCustomerContractPriceComponents (line 80-86).
--
-- 1. Add an `actorAuthUserId: string` parameter to listCustomerContractPriceComponents's own
--    signature (the RPC needs an explicit actor to run its authority/masking checks; the old
--    .from() call relied on the caller's own PostgREST session/JWT implicitly). Thread it in
--    from whatever server-side session context this function's own callers already hold --
--    the same value already passed as actorAuthUserId to getEffectiveCustomerPrice a few lines
--    below in this same file.
--
-- 2. Replace the body:
--      const { data, error } = await client
--        .from("customer_contract_price_components_directory")
--        .select("*")
--        .eq("contract_id", contractId)
--        .order("created_at", { ascending: true });
--    with:
--      const { data, error } = await client.rpc("list_customer_contract_price_components", {
--        p_contract_id: contractId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    (p_* argument names/order exactly as declared above: p_contract_id first, then
--    p_actor_auth_user_id -- both required from the TS side even though the SQL signature
--    defaults p_actor_auth_user_id to auth.uid(), matching how getEffectiveCustomerPrice
--    already always passes p_actor_auth_user_id explicitly despite its own SQL-level default.)
--    Drop the now-redundant `.order(...)` call -- the RPC already applies
--    `order by c.created_at asc` server-side.
--
-- 3. Row mapping is unchanged: the RPC returns the identical 16-column shape, in the identical
--    order, as the old view select (id, tenant_id, contract_id, service_type, mode,
--    origin_lane, destination_lane, equipment_type, currency, base_amount, minimum_amount,
--    discount_pct, surcharge_components, price_masked, created_by, created_at) -- so
--    `(data ?? []).map((row: Record<string, unknown>) => parseCustomerContractPriceComponent(row))`
--    on line 85 needs no change at all. Error handling (`if (error) throw new
--    ContractQueryError(error.message)`) is also unchanged -- .rpc() surfaces errors the same
--    shape as .from().
--
-- 4. The function's exported return type (`Promise<CustomerContractPriceComponent[]>`) does
--    not change.
-- CG-AUDIT-2026-09-02 O1 remediation -- app.costing_requests read path.
--
-- app.costing_requests is a real BASE TABLE (supabase/migrations/20260724090000_
-- create_commercial_costing_request.sql:45), not a view -- it carries no field-masking
-- CASE expressions of its own (masking for this feature lives entirely on
-- app.costing_responses/app.costing_responses_directory, a sibling table, and is out of
-- scope for this file). Every column returned below is exactly the column the two broken
-- `.from("costing_requests").select("*")` call sites already selected -- no exclusion,
-- since server/contracts/costing/costing.ts's own `parseCostingRequest` already consumes
-- every one of the table's 16 columns 1:1 (id, tenant_id, opportunity_id,
-- source_opportunity_version, requirements_snapshot, status, due_at, assignee_user_id,
-- cancel_reason, revised_from_id, owner_user_id, org_unit_id, record_version, created_by,
-- created_at, updated_at).
--
-- Authority envelope: the ONLY declared RLS SELECT policy on this table,
-- `costing_requests_select_scoped` (same migration, line ~579):
--   using (app.can_access_record((select auth.uid()), tenant_id, owner_user_id,
--          app.lead_record_scope_org_unit_ids(org_unit_id), null))
-- Both functions below restate that exact predicate verbatim as an explicit WHERE filter
-- -- required because a SECURITY DEFINER function runs as its owner and never evaluates
-- the invoker's own RLS policies, the identical reason app.costing_responses_directory
-- (same migration) already restates its own row filter explicitly rather than trusting
-- RLS (that view's own comment: "Adds its own explicit app.can_access_record(...) row
-- filter since security_invoker=false means the base table's RLS does not apply to this
-- view's own read."). No app.evaluate_permission(...) module:permission check applies --
-- the declared SELECT policy never calls evaluate_permission, only can_access_record, so
-- adding one here would EXCEED the already-declared read-authority envelope, not match it.
-- app.can_access_record's own body already opens with
-- app.has_active_tenant_membership(p_tenant_id, p_auth_user_id) (20260723180000
-- create_commercial_sales_pipeline.sql:50), so cross-tenant/non-member callers are folded
-- into the same "zero rows" outcome as a genuinely nonexistent id or opportunity --
-- consistent with this repo's ISS-2026-146 tenant-id-disclosure posture (20260902200000
-- harden_tenant_id_disclosure_commercial.sql), achieved here by construction (uniform
-- empty result) rather than by an explicit not-found branch, matching this exact table's
-- own two callers' documented contract ("`getCostingRequestById` returns `null` for both
-- 'does not exist' and 'exists but RLS denies it' -- deliberately not distinguished",
-- app/(tenant)/[tenantSlug]/commercial/costing-requests/[requestId]/page.tsx:21-23).
-- p_actor_auth_user_id is an explicit, non-defaulted parameter (no `default auth.uid()`)
-- to match every other function already built for this exact table
-- (app.request_costing/assign_costing_request/revise_costing_request/
-- cancel_costing_request/submit_costing_response, and the sibling read
-- app.get_opportunity_costing_readiness) -- none of them defaults it either, and every
-- real caller already resolves it server-side via lib/portal/commercial-guard.ts's
-- `authUserId` (asserted server-side against the live session identity, per that file's
-- own doc comment), never from raw client input. See "TS INTEGRATION" at the end of this
-- file for exactly where each of the two call sites already has that value in scope.
--
-- Shape/style precedent imitated: app.list_api_keys_for_tenant
-- (20260719150000_create_api_key_webhook_primitives.sql:563) for the overall SECURITY
-- DEFINER + tenant/actor-authority-first shape, and app.resolve_effective_schedule_
-- assignment (20260730910000_create_hris_shift_roster_scheduling.sql:458, `language sql
-- stable`, zero rows = no error, no exception branch at all) for the specific "plain SQL
-- select with the authority check folded into the WHERE clause" shape used here, since
-- (unlike list_api_keys_for_tenant) neither of app.costing_requests' own two reads has a
-- decision that needs surfacing as an exception -- absence of access is only ever
-- absence of rows, matching the callers' own already-documented contract quoted above.
-- Option-2 public.* wrappers follow the exact, corrected grant pattern this repo's newest
-- Option-2 migration establishes (20260907150000_fix_remaining_tenant_lookup_guards_
-- postgrest_schema_exposure_iss_o1_o2.sql:69-91): `set search_path = pg_catalog, pg_temp`
-- (not `app, public, pg_temp`, an older and now-superseded style seen in some earlier
-- Option-2 wrappers) and an explicit `revoke ... from anon, authenticated, service_role,
-- public` before re-granting, per ISS-2026-309 (a bare `revoke ... from public` does not
-- undo this project's own `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO
-- anon, authenticated, service_role` bootstrap grant on the public schema).

-- ===========================================================================
-- 1. app.get_costing_request_by_id / public.get_costing_request_by_id
--    Replaces: server/queries/costing.ts:44 (getCostingRequestById -- select * from
--    costing_requests, eq id, maybeSingle).
-- ===========================================================================

create function app.get_costing_request_by_id(p_request_id uuid, p_actor_auth_user_id uuid)
returns setof app.costing_requests
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select cr.*
  from app.costing_requests cr
  where cr.id = p_request_id
    and app.can_access_record(
      p_actor_auth_user_id, cr.tenant_id, cr.owner_user_id,
      app.lead_record_scope_org_unit_ids(cr.org_unit_id), null
    )
  limit 1;
$$;

comment on function app.get_costing_request_by_id(uuid, uuid) is
  'COM-148 read (CG-AUDIT-2026-09-02 O1): actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Restates costing_requests_select_scoped''s own RLS predicate (app.can_access_record against tenant/owner/org-unit scope) as an explicit WHERE filter, since this is SECURITY DEFINER and the base table''s RLS never applies to it. Returns zero rows -- never an exception -- for a nonexistent id, a cross-tenant id, or an in-tenant id the actor cannot otherwise reach; the caller (getCostingRequestById) already treats all three identically as `null`.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.get_costing_request_by_id with an identical grant set, never a
-- reimplementation.
create function public.get_costing_request_by_id(p_request_id uuid, p_actor_auth_user_id uuid)
returns setof app.costing_requests
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_costing_request_by_id(p_request_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_costing_request_by_id(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_costing_request_by_id with an identical grant set, never a reimplementation.';

revoke execute on function app.get_costing_request_by_id(uuid, uuid) from public;
grant execute on function app.get_costing_request_by_id(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_costing_request_by_id(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_costing_request_by_id(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_costing_requests_for_opportunity / public.list_costing_requests_for_opportunity
--    Replaces: server/queries/costing.ts:32 (listCostingRequestsForOpportunity -- select *
--    from costing_requests, eq opportunity_id, order created_at desc).
-- ===========================================================================

create function app.list_costing_requests_for_opportunity(p_opportunity_id uuid, p_actor_auth_user_id uuid)
returns setof app.costing_requests
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select cr.*
  from app.costing_requests cr
  where cr.opportunity_id = p_opportunity_id
    and app.can_access_record(
      p_actor_auth_user_id, cr.tenant_id, cr.owner_user_id,
      app.lead_record_scope_org_unit_ids(cr.org_unit_id), null
    )
  order by cr.created_at desc;
$$;

comment on function app.list_costing_requests_for_opportunity(uuid, uuid) is
  'COM-148 read (CG-AUDIT-2026-09-02 O1): actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Restates costing_requests_select_scoped''s own RLS predicate (app.can_access_record against tenant/owner/org-unit scope) as an explicit WHERE filter, since this is SECURITY DEFINER and the base table''s RLS never applies to it. No LIMIT/pagination: the original `.from("costing_requests").select("*").eq("opportunity_id", ...)` call site never applied a `.range()`/`.limit()` either, and costing_requests_opportunity_version_unique (tenant_id, opportunity_id, source_opportunity_version) already bounds the row count per opportunity to its own small revision history (app.revise_costing_request creates at most one new row per opportunity record_version) -- an artificial cap here would be a behavior change the caller never asked for, not a faithful translation of the broken read.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_costing_requests_for_opportunity with an identical grant set,
-- never a reimplementation.
create function public.list_costing_requests_for_opportunity(p_opportunity_id uuid, p_actor_auth_user_id uuid)
returns setof app.costing_requests
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_costing_requests_for_opportunity(p_opportunity_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_costing_requests_for_opportunity(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_costing_requests_for_opportunity with an identical grant set, never a reimplementation.';

revoke execute on function app.list_costing_requests_for_opportunity(uuid, uuid) from public;
grant execute on function app.list_costing_requests_for_opportunity(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_costing_requests_for_opportunity(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_costing_requests_for_opportunity(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/costing.ts
--
-- 1. Client type: both functions now need `.rpc`, not just `.from`. Either widen
--    `CostingQueryTableClient` to `Pick<SupabaseClient, "from" | "rpc">` (simplest, and
--    consistent with this file's existing single shared client-type alias) or add a
--    second `CostingQueryRpcClient = Pick<SupabaseClient, "rpc">` alias mirroring
--    server/queries/opportunity.ts's own `OpportunityQueryRpcClient` split -- either is
--    mechanical; the existing single-alias style already used throughout costing.ts is
--    the smaller diff.
--
-- 2. listCostingRequestsForOpportunity(client, opportunityId) ->
--    listCostingRequestsForOpportunity(client, opportunityId, actorAuthUserId): add a
--    required third `actorAuthUserId: string` parameter. Replace the `.from(...)` chain
--    (lines 31-35) with:
--      const { data, error } = await client.rpc("list_costing_requests_for_opportunity", {
--        p_opportunity_id: opportunityId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    `data` is already the row array (setof, not wrapped) -- keep the existing
--    `(data ?? []).map((row) => parseCostingRequest(row))` mapping unchanged; the row
--    shape (snake_case columns) is identical to the old `.from()` result, so
--    parseCostingRequest needs no change at all.
--
-- 3. getCostingRequestById(client, requestId) ->
--    getCostingRequestById(client, requestId, actorAuthUserId): add the same required
--    third `actorAuthUserId: string` parameter. Replace line 44 with:
--      const { data, error } = await client.rpc("get_costing_request_by_id", {
--        p_request_id: requestId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    `data` is an array (0 or 1 rows, the `setof` + `limit 1` shape) rather than a single
--    object/null the way `.maybeSingle()` returned it -- change the existing
--    `if (!data) { return null; }` / `parseCostingRequest(data as Record<string, unknown>)`
--    pair to:
--      const row = (data ?? [])[0];
--      if (!row) return null;
--      return parseCostingRequest(row as Record<string, unknown>);
--
-- 4. Call sites needing the new third argument -- each already has a live, session-
--    asserted actor id in scope as `access.authUserId` (lib/portal/commercial-guard.ts),
--    no new plumbing required:
--      - app/(tenant)/[tenantSlug]/commercial/opportunities/[opportunityId]/page.tsx:52
--        `listCostingRequestsForOpportunity(supabase, opportunity.id)` ->
--        `listCostingRequestsForOpportunity(supabase, opportunity.id, access.authUserId)`
--        (the same `access.authUserId` already passed one line above it, into
--        `getOpportunityCostingReadiness`).
--      - app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/page.tsx:85
--        `listCostingRequestsForOpportunity(supabase, quotation.opportunityId)` ->
--        `listCostingRequestsForOpportunity(supabase, quotation.opportunityId,
--        access.authUserId)` (confirmed in scope: the same `access.authUserId` is already
--        passed into `getQuotationSubmissionReadiness` one line above, and again into
--        `getQuotationApprovalOverview` a few lines below).
--      - app/(tenant)/[tenantSlug]/commercial/costing-requests/[requestId]/page.tsx:39
--        `getCostingRequestById(supabase, requestId)` -> `getCostingRequestById(supabase,
--        requestId, access.authUserId)` (`access` is already resolved one line above via
--        `resolveCommercialAccessForRequest`, before this call).
--
-- 5. server/queries/costing.test.ts (lines ~104-128) mocks a `.from`-based client today
--    and will need updating to mock `.rpc("list_costing_requests_for_opportunity", ...)`
--    / `.rpc("get_costing_request_by_id", ...)` instead, returning a plain row array in
--    both cases (including a single-element array for the found-by-id case, and `[]` for
--    the not-found case) -- not attempting this rewrite here per this task's scope.
-- CG-AUDIT-2026-09-02 O1 remediation -- app.costing_request_components read path.
--
-- Replaces: server/queries/costing.ts:57 (listCostingRequestComponents -- `select * from
-- costing_request_components, eq costing_request_id, order created_at asc` -- "the
-- requested line items for a costing request"). app.costing_request_components is a real
-- BASE TABLE (supabase/migrations/20260724090000_create_commercial_costing_request.sql:82),
-- not a view -- columns are exactly id, tenant_id, costing_request_id, component_code,
-- description, quantity numeric(14,3), unit, created_at (no masked/sensitive columns live
-- on this table at all; cost/margin data lives on the sibling app.costing_responses /
-- app.costing_response_components tables and is out of scope for this file). Every column
-- is returned -- server/contracts/costing/costing.ts's own `parseCostingRequestComponent`
-- consumes all 8 columns 1:1, so there is no deliberate exclusion to preserve here.
--
-- Authority envelope: the ONLY declared RLS SELECT policy on this table,
-- `costing_request_components_select_scoped` (20260724090000, line ~585):
--   using (exists (
--     select 1 from app.costing_requests cr
--     where cr.id = costing_request_components.costing_request_id
--       and app.can_access_record((select auth.uid()), cr.tenant_id, cr.owner_user_id,
--           app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)
--   ))
-- restated below as an inner join + WHERE filter (required because a SECURITY DEFINER
-- function runs as its owner and never evaluates the invoker's own RLS policies -- the
-- identical reason app.costing_responses_directory, same migration, already restates its
-- own row filter explicitly rather than trusting RLS). The join is safe (never fans out)
-- because costing_request_id is a NOT NULL FK to app.costing_requests.id, a primary key --
-- at most one cr row per component row, so `join` and the policy's `exists` are equivalent.
-- No app.evaluate_permission(...) module:permission check applies -- the declared SELECT
-- policy never calls evaluate_permission, only can_access_record (unlike, e.g.,
-- app.submit_costing_response's COM:Edit / COM:View-cost gates, which gate WRITING a
-- response, not reading a request's own line items) -- adding one here would EXCEED the
-- already-declared read-authority envelope, not match it.
--
-- app.can_access_record's own body already opens with
-- app.has_active_tenant_membership(p_tenant_id, p_auth_user_id)
-- (supabase/migrations/20260716110430_create_field_record_access.sql:45), so a
-- cross-tenant/non-member caller is folded into the same "zero rows" outcome as a
-- genuinely nonexistent costing_request_id -- consistent with this repo's ISS-2026-146
-- tenant-id-disclosure posture (20260902200000_harden_tenant_id_disclosure_commercial.sql),
-- achieved here by construction (the join produces zero rows either way) rather than by an
-- explicit not-found branch.
--
-- Zero rows, never an exception, is a deliberate match to the CURRENT caller contract, not
-- a simplification: app/(tenant)/[tenantSlug]/commercial/costing-requests/[requestId]/
-- page.tsx:53-56 calls listCostingRequestComponents(supabase, request.id) with NO
-- surrounding try/catch (unlike the getCostingRequestById call three lines above it, which
-- IS wrapped in a CostingQueryError catch) -- an RPC that raised on a denied/nonexistent
-- request here would turn what is today a silently-empty list into an unhandled 500. The
-- same page's own header comment already documents this posture for its sibling read
-- (getCostingRequestById: "returns null for both 'does not exist' and 'exists but RLS
-- denies it' -- deliberately not distinguished"); this function extends the identical
-- posture to the child list one level down. It also matches the sibling functions built for
-- app.costing_requests in this same remediation pass
-- (app.get_costing_request_by_id / app.list_costing_requests_for_opportunity,
-- o1-drafts/cluster0/app_costing_requests.sql), which restate the same
-- can_access_record-only predicate the same way and return zero rows rather than raising --
-- kept consistent here rather than introducing a second, exception-raising style for the
-- same page's own data-loading flow (the mutation functions on this table,
-- app.assign_costing_request / app.submit_costing_response, DO raise on
-- not-found/insufficient-authority, but those are single-target write actions with an
-- explicit actor-facing error contract, not a list read RLS itself only ever filters).
--
-- Shape/style precedent imitated: app.list_api_keys_for_tenant
-- (20260719150000_create_api_key_webhook_primitives.sql:563) for the general SECURITY
-- DEFINER read-function shape, and app.resolve_effective_schedule_assignment
-- (20260730910000_create_hris_shift_roster_scheduling.sql:458, `language sql stable`, zero
-- rows = "not applicable", no exception branch at all) for the specific "plain SQL select
-- with the authority check folded into the WHERE clause, absence of access is only ever
-- absence of rows" shape used here.
--
-- Option-2 public.* wrapper follows the exact, corrected grant pattern this repo's newest
-- Option-2 migration establishes (20260907150000_fix_remaining_tenant_lookup_guards_
-- postgrest_schema_exposure_iss_o1_o2.sql:69-91): `set search_path = pg_catalog, pg_temp`
-- and an explicit `revoke ... from anon, authenticated, service_role, public` before
-- re-granting, per ISS-2026-309 (a bare `revoke ... from public` does not undo this
-- project's own `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon,
-- authenticated, service_role` bootstrap grant on the public schema).

-- ===========================================================================
-- app.list_costing_request_components / public.list_costing_request_components
-- ===========================================================================

create function app.list_costing_request_components(p_request_id uuid, p_actor_auth_user_id uuid)
returns setof app.costing_request_components
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select crc.*
  from app.costing_request_components crc
  join app.costing_requests cr on cr.id = crc.costing_request_id
  where crc.costing_request_id = p_request_id
    and app.can_access_record(
      p_actor_auth_user_id, cr.tenant_id, cr.owner_user_id,
      app.lead_record_scope_org_unit_ids(cr.org_unit_id), null
    )
  order by crc.created_at asc;
$$;

comment on function app.list_costing_request_components(uuid, uuid) is
  'COM-148 read (CG-AUDIT-2026-09-02 O1): actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Restates costing_request_components_select_scoped''s own RLS predicate (app.can_access_record against the parent costing_request''s tenant/owner/org-unit scope) as an explicit join + WHERE filter, since this is SECURITY DEFINER and the base table''s RLS never applies to it. Returns zero rows -- never an exception -- for a nonexistent costing_request_id, a cross-tenant one, or an in-tenant one the actor cannot otherwise reach (app.can_access_record already folds app.has_active_tenant_membership into its own first check, so a non-member sees the same empty result as a genuinely nonexistent id, per ISS-2026-146''s tenant-id-disclosure posture). No LIMIT/pagination: the original `.from("costing_request_components").select("*").eq("costing_request_id", ...)` call site never applied a `.range()`/`.limit()` either, and a costing request''s own line items are a bounded, small, human-entered list (app.request_costing''s own p_components jsonb payload), not an unbounded feed -- an artificial cap here would be a behavior change the caller never asked for.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_costing_request_components with an identical grant set, never a
-- reimplementation.
create function public.list_costing_request_components(p_request_id uuid, p_actor_auth_user_id uuid)
returns setof app.costing_request_components
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_costing_request_components(p_request_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_costing_request_components(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_costing_request_components with an identical grant set, never a reimplementation.';

revoke execute on function app.list_costing_request_components(uuid, uuid) from public;
grant execute on function app.list_costing_request_components(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_costing_request_components(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_costing_request_components(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
-- File: server/queries/costing.ts
--
-- 1. Client type: this function now needs `.rpc`, not `.from`. `CostingQueryTableClient`
--    is currently `Pick<SupabaseClient, "from">`; widen it to
--    `Pick<SupabaseClient, "from" | "rpc">` (smallest diff, and the same client value is
--    already threaded through every other function in this file, several of which are
--    being migrated to `.rpc` too in this same remediation pass -- see
--    o1-drafts/cluster0/app_costing_requests.sql''s own TS INTEGRATION note, which makes
--    the identical widening choice for this same file/type).
--
-- 2. listCostingRequestComponents(client, requestId) ->
--    listCostingRequestComponents(client, requestId, actorAuthUserId): add a required
--    third `actorAuthUserId: string` parameter. Replace the `.from(...)` chain
--    (lines 56-60) with:
--      const { data, error } = await client.rpc("list_costing_request_components", {
--        p_request_id: requestId,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--    `data` is already the row array (setof, not wrapped) and already ordered
--    `created_at asc` server-side, so the existing
--    `(data ?? []).map((row) => parseCostingRequestComponent(row))` mapping (line 64) needs
--    NO change at all -- the row shape (snake_case: id, tenant_id, costing_request_id,
--    component_code, description, quantity, unit, created_at) is byte-for-byte identical
--    to the old `.from()` result, since the RPC selects `crc.*` from the same table.
--
-- 3. Call site needing the new third argument:
--    app/(tenant)/[tenantSlug]/commercial/costing-requests/[requestId]/page.tsx:54
--      `listCostingRequestComponents(supabase, request.id)` ->
--      `listCostingRequestComponents(supabase, request.id, access.authUserId)`
--    (`access.authUserId` is already resolved at the top of the page via
--    `resolveCommercialAccessForRequest`, in scope at this call site already -- the same
--    value the sibling `getCostingRequestById`/`listCostingRequestsForOpportunity` calls in
--    this same remediation pass are wired to).
--
-- 4. server/queries/costing.test.ts (lines 137-145, `describe("listCostingRequestComponents"...`)
--    mocks a `.from`-based client today (`fakeTableClient`) and will need updating to mock
--    `.rpc("list_costing_request_components", ...)` instead, returning a plain row array
--    (e.g. `[VALID_COMPONENT_ROW]`) -- not attempting this rewrite here, per this task's
--    scope (SQL only).
-- Final blanket revoke (ERR-2026-004 standing convention).
revoke execute on all functions in schema app from public;
