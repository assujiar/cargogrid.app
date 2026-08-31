-- Closes the remaining six of `ISS-2026-186` (and with it the live half of `ISS-2026-179` /
-- `HDN-BLK-014`), by fixing the layer those entries never looked at.
--
-- THE FINDING, RESTATED CORRECTLY
--
--   Six `SECURITY DEFINER` primitives answer a question *about a claimed identity* and are
--   granted to `authenticated`:
--
--     app.has_active_tenant_membership(p_tenant_id, p_auth_user_id)
--     app.actor_holds_customer_user_layer(p_tenant_id, p_auth_user_id)
--     app.has_active_support_grant(p_tenant_id, p_auth_user_id)
--     app.is_supreme_admin(p_auth_user_id)
--     app.can_access_record(p_auth_user_id, p_tenant_id, p_owner_user_id, ...)
--     app.resolve_locale_context(p_tenant_id, p_user_auth_user_id)
--
--   Any authenticated user could ask them about ANY other identity and get a truthful answer:
--   is this person a Supreme Admin, is that person a member of that tenant, does this person
--   hold a support grant. A boolean oracle over the platform's own authority graph.
--
-- WHY THREE PRIOR ATTEMPTS COULD NOT FIX IT, AND WHY THEY WERE RIGHT NOT TO
--
--   `ISS-2026-186` records that the blind `assert_actor_is_session_identity` pattern -- the one
--   that closed the other 19 functions in this family -- cannot be used here, because these are
--   called with genuinely THIRD-PARTY actor arguments elsewhere in the schema. That is true, and
--   re-confirmed here rather than taken on trust:
--
--     app.has_active_tenant_membership(p_tenant_id, p_owner_user_id)
--     app.has_active_tenant_membership(p_tenant_id, p_recipient_auth_user_id)
--     app.is_supreme_admin(p_assignee_auth_user_id)
--
--   `auth.uid()` reads the session's JWT claim, and SECURITY DEFINER changes the *role*, not the
--   session. So it does NOT go null inside a nested definer call, and an unconditional assert
--   really would break every one of those legitimate third-party uses mid-transaction.
--
--   Two further facts, established live, rule out the other obvious fixes:
--
--   1. **Revoking `authenticated` is catastrophic, not conservative.** These functions are RLS
--      PREDICATES: 304 policies reference `app.is_supreme_admin`, 276
--      `app.actor_holds_customer_user_layer`, 266 `app.has_active_tenant_membership`, 72
--      `app.can_access_record`. A policy expression is evaluated as the *querying* role, so
--      removing the grant would break ~918 policy evaluations — every protected read in the
--      product.
--
--   2. **A raising guard inside a policy is worse than no guard.** A `raise` in an RLS predicate
--      aborts the whole statement instead of filtering rows, so it converts a row-level denial
--      into a query error.
--
--   And `app.has_active_tenant_membership` has a third constraint of its own:
--   `app.evaluate_permission` calls it to DECIDE membership and must return a clean
--   `not_active_tenant_member` denial. A guard there would turn the RBAC evaluator's most common
--   denial into an exception.
--
-- THE LAYER ALL THREE PASSES MISSED
--
--   Every one of those ~918 RLS call sites, and every internal third-party-actor call site,
--   invokes the **`app.*`** function directly — verified: 266 of 266 and 304 of 304 policy
--   expressions are `app.`-prefixed, zero bare references. And `app` is not exposed to PostgREST.
--
--   So none of them is the attack surface. The oracle is reachable from a browser only through
--   the thin **`public.*` wrapper**, at `/rest/v1/rpc/<name>`.
--
--   Guarding the wrapper closes the oracle and touches nothing else: RLS keeps calling `app.*`,
--   internal functions keep passing third-party actors to `app.*`, and `app.evaluate_permission`
--   keeps returning its clean denial. That is why this fix is possible at all, and why the
--   earlier "it cannot be done with the assert pattern" conclusion was correct about `app.*` and
--   simply never asked about `public.*`.
--
-- WHY THIS DOES NOT BREAK THE REAL CLIENT CALLERS -- each one checked, not assumed
--
--   Every call site in the repository that reaches these through the `public.*` wrapper passes
--   the requesting session's OWN identity:
--
--     lib/portal/customer-portal-guard-deps.server.ts  actor_holds_customer_user_layer(own id)
--     lib/portal/customer-ticket-guard-deps.server.ts  actor_holds_customer_user_layer(own id)
--     server/policies/api-request-context.ts           can_access_record(p_auth_user_id = the
--                                                      requesting actor; p_owner_user_id is the
--                                                      RECORD's owner, a different parameter --
--                                                      conflating those two is what made the
--                                                      original triage read this as third-party)
--     server/queries/support-access.ts                 has_active_support_grant -- test callers only
--     server/queries/localization.ts                   resolve_locale_context -- test callers only,
--                                                      and always with a null actor
--
--   `app.assert_actor_is_session_identity` raises only when a non-null session identity differs
--   from a non-null claimed actor. So:
--     - `anon` pre-login (locale resolution): `auth.uid()` is null -> no-op, still works;
--     - `service_role`: `auth.uid()` is null -> no-op;
--     - a null actor argument: no-op;
--     - an authenticated session asking about itself: passes;
--     - an authenticated session asking about someone else: refused. That is the whole fix.

-- ===========================================================================
-- Six wrappers, each rebuilt byte-identically apart from the added assert.
-- Signature, return type, language, volatility, security mode and search_path are
-- reproduced exactly from pg_get_functiondef; `CREATE OR REPLACE` preserves the ACL,
-- so no grant is widened or narrowed by this migration.
-- The assert is fully qualified: these wrappers run with search_path = pg_catalog, pg_temp.
-- ===========================================================================

create or replace function public.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select app.has_active_tenant_membership(p_tenant_id, p_auth_user_id);
$wrap$;

create or replace function public.actor_holds_customer_user_layer(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select app.actor_holds_customer_user_layer(p_tenant_id, p_auth_user_id);
$wrap$;

create or replace function public.has_active_support_grant(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select app.has_active_support_grant(p_tenant_id, p_auth_user_id);
$wrap$;

create or replace function public.is_supreme_admin(p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select app.is_supreme_admin(p_auth_user_id);
$wrap$;

create or replace function public.can_access_record(p_auth_user_id uuid, p_tenant_id uuid, p_owner_user_id uuid, p_shared_org_unit_ids uuid[] default '{}'::uuid[], p_customer_account_ref text default null::text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select app.can_access_record(p_auth_user_id, p_tenant_id, p_owner_user_id, p_shared_org_unit_ids, p_customer_account_ref);
$wrap$;

-- p_user_auth_user_id, not p_auth_user_id: this one names its actor parameter differently, and
-- it is the ONLY one of the six granted to `anon` -- a tenant's login page must resolve its
-- language, timezone and currency before any session exists. Anonymous callers have a null
-- `auth.uid()`, so the assert is a no-op for exactly that case and pre-login rendering is
-- unaffected.
create or replace function public.resolve_locale_context(p_tenant_id uuid, p_user_auth_user_id uuid default null::uuid)
returns table(tenant_id uuid, source text, locale text, timezone text, currency text, terminology_overrides jsonb)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.assert_actor_is_session_identity(p_user_auth_user_id);
  select * from app.resolve_locale_context(p_tenant_id, p_user_auth_user_id);
$wrap$;

comment on function public.is_supreme_admin(uuid) is
  'RGL-394 Option-2 wrapper, hardened by ISS-2026-186 (20260831010000): a thin security-definer pass-through to app.is_supreme_admin that FIRST asserts the claimed actor is the calling session''s own identity. The app.* function is deliberately left unguarded -- it is an RLS predicate in 304 policies and is called with genuinely third-party actor arguments inside other definer functions, both of which a raising guard would break. Only this wrapper is reachable over PostgREST, so only this wrapper needs the guard.';

comment on function public.has_active_tenant_membership(uuid, uuid) is
  'RGL-394 Option-2 wrapper, hardened by ISS-2026-186 (20260831010000): asserts the claimed actor is the calling session before delegating. app.has_active_tenant_membership stays unguarded on purpose -- it backs 266 RLS policies and is what app.evaluate_permission calls to produce its clean not_active_tenant_member denial, which an exception would replace with a query error.';
