-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 2 (HRIS/identity-access)
-- batch 1 of ~N. Continues the same Design->Verify->Fix adversarial pipeline cluster 0's
-- 5 batches (32/32 tables closed) and cluster 1's 1 batch (6/6 tables closed) established
-- (RULE A/B/C baked into every draft and every independent verify pass below),
-- user-directed ("lanjut sampe siap launching") extension of CG-AUDIT-2026-09-02's
-- Ø1-query-layer finding: supabase/config.toml only exposes "public"/"graphql_public" to
-- PostgREST, so every .from() read against the "app" schema has never worked in
-- production.
--
-- Per CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json, cluster 2 (hris-identity-access) has
-- 10 recorded call-site entries: one placeholder ("(none)", server/queries/employee.ts --
-- already fully migrated off .from(), confirmed by its own file header), one already-fine
-- SWAP_ONLY entry (server/queries/field-access.ts:28, app.can_access_record, already a
-- working .rpc() call), one SWAP_ONLY closed in a prior commit this same session
-- (server/queries/leave.ts:132, reusing cluster 0 batch 3's app.get_approval_requests_
-- entity_refs -- no new SQL needed), and 7 real NEEDS_NEW_FUNCTION call sites across 5
-- tables/views closed by THIS migration:
--   app.tenant_user_identities  server/queries/auth-identity.ts:28 (listIdentityTenantLinks)
--   app.users                   server/queries/user-lifecycle.ts:63 (listTenantUsers, half 1)
--   app.users_directory         server/queries/user-lifecycle.ts:64 (listTenantUsers, half 2)
--   app.users_directory         server/queries/portal-users.ts:69 (listPortalUsers)
--   app.users_directory         server/queries/field-access.ts:62 (listUserDirectory)
--   app.permissions             server/queries/role-permission.ts:27 (listPermissionsForModule)
--   app.roles                   server/queries/role-permission.ts:37 (listTenantRoles)
--
-- 7 new app.*/public.* Option-2 wrapper function pairs across 5 tables/views:
--   app.tenant_user_identities: app.list_identity_tenant_links -- resolved a genuine
--                                design ambiguity (self-lookup vs. admin-lookup-of-
--                                another) as SELF-ONLY, backed by real evidence (zero
--                                production callers, the table's own current RLS
--                                predicate having no auth_user_id axis at all, and
--                                direct precedent from the app.get_my_employee_profile
--                                self-service family) -- independently re-confirmed by
--                                the verify pass, which found even stronger
--                                corroborating evidence (app.resolve_access_context's
--                                own identical row-filter shape for the real login-time
--                                "which tenant can I access" resolver).
--   app.users:                  app.list_tenant_users -- RULE B finding: app.users' own
--                                current SELECT policy carries no admin-authority/role
--                                conjunct at all (plain active-tenant-membership, customer_
--                                user layer excluded) -- independently confirmed by the
--                                verify pass as expected layering, not a gap: the real
--                                Tenant Admin page (admin/users/page.tsx) gates entry via
--                                a separate, documented portal-guard layer
--                                (tenant-admin-guard.ts), not via a stricter RLS predicate.
--   app.users_directory:        app.list_user_directory_email_projections (user-lifecycle.ts
--                                half 2), app.list_portal_users (paginated, exact-count),
--                                app.list_user_directory (unbounded, all columns) -- a
--                                real, live authority drift was found and CORRECTED, not
--                                merely disclosed: the view's own WHERE clause was never
--                                given the customer_user-layer exclusion its sibling base
--                                table app.users received in 20260730560000 (a structural
--                                impossibility for that migration to have done, since RLS
--                                policies attach to tables, never views) -- all three
--                                functions add the exclusion, matching app.users' own
--                                current, hardened predicate, since this is a brand-new
--                                capability with no live behavior to preserve either way.
--   app.permissions:             app.list_permissions_for_module -- app.permissions has
--                                NEVER had any RLS policy or any grant beyond service_role
--                                (a still-open PLT-113/114-era deferral, never revisited);
--                                this is therefore the FIRST-EVER grant of read access to
--                                this table for any role but service_role, a genuine
--                                widening decision, not a reproduction of existing
--                                behavior. The verify pass narrowed the design's own
--                                initial "zero actor param, wide open" draft to add a
--                                minimal "does this identity hold any real standing on the
--                                platform at all" gate (an active app.principal_memberships
--                                row), reusing this repository's own existing primitive
--                                for that exact question rather than inventing a new one --
--                                closing a concretely-identified gap (a revoked/never-
--                                onboarded identity's still-live JWT) at zero cost to the
--                                real, still-unbuilt future consumer.
--   app.roles:                   app.list_tenant_roles -- reproduces roles_select_own_
--                                tenant's own current (post-hardening) predicate verbatim;
--                                independently checked and confirmed there is no dedicated
--                                RBAC-admin gate beyond plain tenant membership to defer to
--                                (role administration itself is service_role-only today).
--
-- Every function below was independently adversarially re-verified against the live repo
-- state (not merely its own draft's claims) before being included in this migration. One
-- real grant-parity defect was found and fixed during that verify pass: app.list_tenant_
-- users' first-pass draft granted EXECUTE to `authenticated` only (mirroring app.users'
-- own narrower, differently-motivated table-level grant), which the verify pass corrected
-- to `authenticated, service_role` after finding the cited precedent had been misread and
-- confirming every one of the ~45 prior O1-remediated app.* functions across cluster 0/1
-- grants both roles with zero exceptions.
--
-- All 5 affected TS query files (server/queries/user-lifecycle.ts, portal-users.ts,
-- field-access.ts, auth-identity.ts, role-permission.ts) and every real page.tsx call
-- site are switched from .from() to .rpc() in this same commit, per each function's own
-- embedded TS INTEGRATION note below. Five of the seven functions have no live page.tsx
-- caller today (listIdentityTenantLinks, listTenantUsers, listUserDirectory,
-- listPermissionsForModule, listTenantRoles) -- fixed anyway, since the broken .from()
-- read each replaces is broken regardless of caller count, matching this series' own
-- established precedent (cluster 1 batch 1's getBillingReadinessEvaluationHistory/
-- listFinanceRoundingModes).
--
-- This migration closes 7 of cluster 2's 10 recorded call-site entries -- combined with
-- the leave.ts SWAP_ONLY fix already closed in this same session (a separate commit, no
-- new SQL) and the two already-fine entries (employee.ts, field-access.ts's own
-- can_access_record call), cluster 2 (HRIS/identity-access) is now fully DONE. Clusters
-- 3-7 (dispatch/tracking/documents/analytics/misc) remain, per
-- CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json.

-- ===========================================================================
-- TABLE 1 of 4: app.tenant_user_identities
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 2 (HRIS/identity-access),
-- batch 1 of ~N. Continues the same Design->Verify->Fix pipeline cluster 0 (32 tables,
-- batches 1-5, all closed), cluster 1 (finance, 6 tables/8 call sites, batch 1, all
-- closed) already established: supabase/config.toml's `schemas = ["public",
-- "graphql_public"]` never exposes "app" to PostgREST, so every `.from()` read against an
-- `app.*` relation in server/queries/*.ts has NEVER worked in production.
--
-- Per CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json, cluster 2 (hris-identity-access) has
-- 10 recorded call-site entries: one placeholder ("(none)"), one already-fine SWAP_ONLY
-- entry (app.can_access_record, already a working .rpc() call), and 8 real
-- NEEDS_NEW_FUNCTION defects across 6 tables/views (app.approval_requests, app.users,
-- app.users_directory x3, app.tenant_user_identities, app.permissions, app.roles). This
-- batch closes exactly 1 of those 8 call sites:
--   app.tenant_user_identities   server/queries/auth-identity.ts:28 (listIdentityTenantLinks)
-- The remaining 7 call sites across 5 tables/views in this cluster, plus clusters 3-7
-- (dispatch/tracking/documents/analytics/misc), remain open.
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior O1 batch): a new `app.*`
-- SECURITY DEFINER function reimplementing the read with explicit, correct authority
-- scoping (an explicit `p_actor_auth_user_id` parameter, never a bare reliance on session
-- state), plus a thin `public.*` pass-through wrapper (the only PostgREST-reachable
-- surface) carrying an IDENTICAL grant set -- never a reimplementation.
--
-- ===========================================================================
-- THE DESIGN QUESTION, AND HOW IT WAS RESOLVED (self-lookup vs. admin-lookup-of-another)
-- ===========================================================================
--
-- The broken read is `client.from("tenant_user_identities").select("*").eq("auth_user_id",
-- authUserId)` -- every column, every row (any status), for ONE auth_user_id, spanning
-- EVERY tenant that identity is linked to. Unlike almost every other O1 fix in this
-- series, this read carries no `tenant_id` filter at all -- it is fundamentally a
-- cross-tenant, single-identity query ("every tenant this identity can reach"), not a
-- single-tenant, multi-identity query ("every identity linked to this tenant").
--
-- Two candidate authority models were considered, per this batch's own task framing:
--   (a) SELF-ONLY: the function may only ever return the CALLING identity's own rows --
--       p_actor_auth_user_id (the caller) and the identity being looked up are the same
--       value, structurally.
--   (b) ADMIN-LOOKUP-OF-ANOTHER: a sufficiently privileged actor (e.g. Supreme Admin) may
--       look up a DIFFERENT identity's tenant links, e.g. a support tool.
--
-- Real evidence gathered, not assumed:
--
-- 1. CALL SITES (repo-wide grep for "listIdentityTenantLinks("): exactly one production
--    definition (server/queries/auth-identity.ts:27) and three test invocations
--    (server/queries/auth-identity.test.ts:37,48,56), each passing one literal UUID
--    directly -- no `page.tsx`, route handler, server action, or any other production
--    caller exists anywhere in this repository. There is no live evidence of an
--    admin-looks-up-another-identity caller today -- confirmed, not inferred.
--
-- 2. THE FUNCTION'S OWN STATED PURPOSE (auth-identity.ts:26 doc comment, and the recon's
--    own readDescription, CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json line 613): "Serves
--    auth-identity linkage lookup (PLT-107) -- e.g. resolving which tenants a GIVEN
--    LOGGED-IN IDENTITY can access." This is self-lookup framing -- a signed-in identity
--    discovering its own reachable tenant set (e.g. at login, before a tenant is chosen),
--    not a support tool inspecting someone else's account. The recon entry's own notes
--    (same file, line 616) independently reached the identical conclusion during initial
--    triage: "this table has no tenant_id filter in the current read ... the authority
--    model for a new function here needs care: it must only let a caller read THEIR OWN
--    identity's tenant links ... since there is no per-tenant boundary to lean on for this
--    particular query shape." That triage note is corroborating evidence, independently
--    re-derived below from the real RLS predicate rather than taken on faith.
--
-- 3. THE CURRENT RLS PREDICATE ON app.tenant_user_identities (RULE B; full derivation in
--    the RULE B section below): the table's own, only-ever-declared SELECT policy
--    (`tenant_user_identities_select_own_tenant`) is a TENANT-MEMBERSHIP predicate --
--    `app.has_active_tenant_membership(tenant_id) and not
--    app.actor_holds_customer_user_layer(tenant_id)` -- with NO reference to auth_user_id
--    at all. Read literally, it lets ANY actively-linked staff member of tenant T see
--    EVERY tenant_user_identities row belonging to tenant T, regardless of whose row it
--    is -- a "see my tenant's own roster" shape. That is a genuinely different axis from
--    this read's own shape (one identity, all its tenants, no tenant_id supplied at all).
--    Applying that predicate verbatim, per row, to this cross-tenant read would produce an
--    accidental, never-designed capability: actor X (a staff member of tenant Acme) could
--    pass an arbitrary p_auth_user_id belonging to some OTHER identity Y and see every row
--    of Y's that happens to sit in a tenant where X ALSO has active membership -- not a
--    deliberate admin/support capability, just an artifact of a table-wide policy that was
--    written for a different query shape (tenant roster browsing) being force-fit onto
--    this one (cross-tenant self lookup). There is no dedicated authority helper anywhere
--    in this schema wired specifically to "may actor X read identity Y's tenant_user_
--    identities rows" -- the only privileged bypass that exists at all is Supreme Admin,
--    which is already folded into app.has_active_tenant_membership generically, not a
--    purpose-built gate for this read.
--
-- 4. DIRECT, ON-POINT PRECEDENT already in this schema for exactly this shape: `app.get_my
--    _employee_profile` and its four siblings (app.get_my_assigned_interviews, app.get_my_
--    attendance_status, app.get_my_employee_position_assignment_history, app.get_my_
--    schedule -- 20260730830000_create_hris_employee_master.sql and siblings, most
--    recently re-declared at 20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:
--    241 onward) are this codebase's own established "narrow self-service read, own row(s)
--    only" family: single `p_actor_auth_user_id` parameter (no separate "whose record"
--    parameter at all), `perform app.assert_actor_is_session_identity(p_actor_auth_user_id)`
--    as the first statement, and a row filter keyed to that same actor id -- no additional
--    admin/support branch. 20260907110000's own header names this family explicitly:
--    "narrow self-service reads ... that read only the calling identity's OWN row(s),
--    never another identity's or the wider tenant's data."
--
-- RESOLUTION: self-only (option a). app.list_identity_tenant_links takes a SINGLE
-- parameter, `p_actor_auth_user_id` -- there is no separate "subject" parameter to keep in
-- sync with it, because the identity being looked up IS the actor, structurally (matching
-- app.get_my_employee_profile's own precedent shape exactly: no p_target_auth_user_id ever
-- existed for that family either). RULE A's actor-impersonation guard is therefore not
-- merely "the first defensive statement" here -- it IS the entire authority model: a
-- caller cannot even express "look up someone else's links" in this function's own
-- signature, let alone have that request silently accepted.
--
-- One deliberate consequence, disclosed rather than silently absorbed: because this is a
-- self-only design, the row filter below is `auth_user_id = p_actor_auth_user_id` alone --
-- it deliberately does NOT also layer on app.has_active_tenant_membership/app.actor_holds_
-- customer_user_layer per row (the general policy's own predicate, see RULE B). Reproducing
-- that predicate here would silently break this function's own documented contract ("any
-- status -- caller filters by status if only active/invited linkages are wanted",
-- auth-identity.ts:26): an 'invited' row has, by definition, no corresponding active
-- app.tenant_user_identities row yet for that (tenant, identity) pair, so app.has_active_
-- tenant_membership(tenant_id, p_actor_auth_user_id) would read false for that very row --
-- hiding a newly-invited identity's own pending invitation from itself, and hiding its own
-- 'revoked' history rows the same way. A self-scoped identity-linkage lookup is not the
-- resource app.has_active_tenant_membership was written to gate (it gates "can this
-- identity see the wider tenant's OTHER data", not "can this identity see its own linkage
-- records") -- the row-ownership filter alone (auth_user_id = the actor, enforced equal to
-- the session identity by RULE A) is the correct, sufficient, and narrower-than-the-
-- general-policy authority envelope for this specific self-service read, matching the
-- app.get_my_employee_profile family's own established reasoning for why a self-scoped
-- read does not need the broad membership gate its OWN resource would otherwise require.
--
-- ===========================================================================
-- RULE A (actor-impersonation guard, ATW-031/032, ISS-2026-017/032)
-- ===========================================================================
-- Repo-wide grep, sorted by filename: "create or replace function app.assert_actor_is_
-- session_identity" / "create function app.assert_actor_is_session_identity" -- exactly
-- ONE hit, 20260730440000_harden_actor_identity_session_crosscheck.sql:59 (the only
-- `create or replace`, never re-replaced since). Current body: a no-op whenever the
-- session identity is null (service_role, superuser, db-tests, nested SECURITY DEFINER
-- calls); for a genuine authenticated session, raises `actor_identity_mismatch` iff the
-- claimed p_actor_auth_user_id differs from the real session identity. `perform app.
-- assert_actor_is_session_identity(p_actor_auth_user_id);` is the first executable
-- statement in the function body below, before any lookup.
--
-- ===========================================================================
-- RULE B (RLS predicate currency)
-- ===========================================================================
-- Repo-wide grep for BOTH `create policy`/`alter policy` naming app.tenant_user_identities
-- AND the bare policy name `tenant_user_identities_select_own_tenant`, across every file in
-- supabase/migrations/*.sql sorted by filename:
--   * Original: 20260716105512_create_rls_tenant_policies.sql:102-105 --
--       create policy tenant_user_identities_select_own_tenant
--         on app.tenant_user_identities for select to authenticated
--         using (app.has_active_tenant_membership(tenant_id));
--   * Later rewrite (the CURRENT, ground-truth version): 20260730560000_harden_customer_
--     user_layer_default_deny.sql:322 --
--       alter policy tenant_user_identities_select_own_tenant on app.tenant_user_identities
--         using ((app.has_active_tenant_membership(tenant_id)
--                 AND NOT app.actor_holds_customer_user_layer(tenant_id)));
--     No THIRD hit exists anywhere in the repo -- this is the current, only-ever-rewritten
--     predicate. (Also checked: no supplemental own-row SELECT policy exists on this table
--     under any name -- 20260810500000_harden_own_row_rls_membership_gap.sql, despite its
--     name, touches other tables, not this one -- grepped "tenant_user_identities" against
--     that file specifically: zero hits.)
-- As explained in the DESIGN QUESTION section above, this predicate is genuinely a
-- tenant-membership ("see my tenant's own roster") rule, not a self-row rule, and is
-- deliberately NOT reproduced verbatim inside the function below -- its role here is
-- evidentiary (it rules OUT "there is a built-in admin/support envelope for this exact
-- read" and confirms the self-only resolution), not prescriptive of the row filter itself.
--
-- ===========================================================================
-- RULE C (precedent staleness)
-- ===========================================================================
-- Every helper cited above was checked against its MOST RECENT create-or-replace, not its
-- original creation migration:
--   * app.has_active_tenant_membership -- three hits repo-wide (20260716105512 original,
--     20260716111315 support-access extension, 20260907110000 D3b fix). The CURRENT body
--     (20260907110000:64-80) additionally excludes an identity with a corresponding
--     suspended/revoked app.users row, ORs in Supreme Admin and an active support grant --
--     cited here only to establish why it is NOT layered onto this function's own row
--     filter (see DESIGN QUESTION section); not used in the function body below.
--   * app.actor_holds_customer_user_layer -- exactly ONE hit, 20260730311000_harden_
--     customer_inventory_access_rls_isolation.sql:71 -- never replaced. Not used in the
--     function body below, same reasoning.
--   * app.is_supreme_admin -- exactly ONE hit, 20260716105512_create_rls_tenant_policies.
--     sql:45 -- never replaced (confirmed by grep, zero later `create or replace function
--     app.is_supreme_admin` hits). Not used directly here -- this function has no
--     privileged-bypass branch, per the self-only resolution above; Supreme Admin gets no
--     special treatment reading identity-linkage rows that are not its own.
--   * app.get_my_employee_profile (self-only shape precedent) -- two hits, the original
--     20260730830000_create_hris_employee_master.sql:2243 and the current
--     20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:241 (retargeted onto
--     app.has_active_identity_link, not app.has_active_tenant_membership, for the reason
--     that migration's own header explains). The current body is what is cited above.
--
-- ===========================================================================
-- CONTRACT FIDELITY (the "return exactly what the TS contract consumes" discipline,
-- cluster 0 batch 4's app.prospects fix)
-- ===========================================================================
-- server/contracts/auth/identity.ts's own TenantUserIdentitySchema/parseTenantUserIdentity
-- consumes exactly 13 fields (id, authUserId, tenantId, status, invitedBy, invitedAt,
-- activatedAt, revokedAt, revokedReason, mfaEnrolled, recordVersion, createdAt, updatedAt),
-- mapped 1:1 from app.tenant_user_identities' own 13 physical columns (20260716095343_
-- link_auth_identities.sql:17-34: id, auth_user_id, tenant_id, status, invited_by,
-- invited_at, activated_at, revoked_at, revoked_reason, mfa_enrolled, record_version,
-- created_at, updated_at) -- no exclusion needed, no masking column, every physical column
-- is consumed. This function is therefore declared `returns setof app.tenant_user_
-- identities` (full row, no explicit column list), matching cluster 1 batch 1's own
-- app.list_billing_readiness_handoffs precedent for this identical "full row, no masking,
-- no exclusion" shape. No ORDER BY: the original `.from()` call applied none.
--
-- ===========================================================================
-- ROW-NOT-FOUND BEHAVIOR
-- ===========================================================================
-- Returns an empty set (never an exception) for an identity with zero linkages -- matching
-- the original `.from()` read's own silent-empty-result posture and the TS layer's
-- existing `(data ?? []) -> []` handling exactly (no TS error-handling change needed for
-- this case, only the .from()-to-.rpc() call shape -- see TS INTEGRATION below).
--
-- Per ERR-2026-004: this migration's own final grants are additive to whatever base state
-- already exists (no `revoke ... from public` on the whole schema is repeated here, only
-- the two functions this migration itself creates). Per ISS-2026-309 (closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): the public.* wrapper explicitly
-- revokes from `anon, authenticated, service_role, public` (all four) before re-granting
-- exactly the roles its app.* counterpart itself grants -- a bare `revoke ... from public`
-- does NOT strip the `anon`/`authenticated` EXECUTE grants this project's own ALTER DEFAULT
-- PRIVILEGES rule applies to every new function in schema public at CREATE time. Never
-- granted to anon.
--
-- check-rls-initplan.ts false-positive avoidance: per this repository's own established
-- practice, every `comment on function ... is '...'` string below avoids combining the
-- literal phrase "create policy"/"alter policy" with a bare, parenthesized auth.uid()/
-- auth.jwt() mention in the same string (those phrases and that literal call shape appear
-- only in this file's own `--` line-comment header above, which the guard's own
-- blankLineComments preprocessing already excludes from its scan). The guard itself is
-- never suppressed, only the prose reworded.

-- ===========================================================================
-- app.list_identity_tenant_links -- replaces server/queries/auth-identity.ts:28
--   (listIdentityTenantLinks)
-- ===========================================================================
create function app.list_identity_tenant_links(
  p_actor_auth_user_id uuid
)
returns setof app.tenant_user_identities
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup. This function has no separate
  -- "subject" parameter to guard against divergence from -- the identity being looked up
  -- IS the actor, structurally (see this migration's own header, DESIGN QUESTION
  -- section) -- so this assertion is the entire authority model, not merely a guard in
  -- front of a further check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select tui.*
  from app.tenant_user_identities tui
  where tui.auth_user_id = p_actor_auth_user_id;
end;
$$;

comment on function app.list_identity_tenant_links(uuid) is
  'PLT-107/O1 remediation: every app.tenant_user_identities row (any status -- invited, active, or revoked) belonging to one auth identity, across every tenant it has ever been linked to, replacing server/queries/auth-identity.ts''s broken .from("tenant_user_identities") read (the app schema is not exposed to PostgREST). Self-only by construction: the single p_actor_auth_user_id parameter names both the caller and the identity being looked up, cross-checked against the real session identity by app.assert_actor_is_session_identity before any lookup (ATW-031/032) -- there is no way to request a different identity''s rows through this function''s own signature. Deliberately does NOT layer the table''s own general tenant-membership SELECT policy on top of the row filter (that policy governs a different query shape -- browsing a tenant''s own roster -- and would incorrectly hide this identity''s own not-yet-active or revoked rows from itself, contradicting this function''s documented any-status contract); auth_user_id = the actor is itself the complete and correct authority envelope for a purely self-scoped linkage lookup. Returns an empty set, never an exception, for an identity with zero linkages, matching the original read''s own silent-empty-result behavior.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_identity_tenant_links with an identical grant set, never a
-- reimplementation.
create function public.list_identity_tenant_links(
  p_actor_auth_user_id uuid
)
returns setof app.tenant_user_identities
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_identity_tenant_links(p_actor_auth_user_id);
$wrap$;

comment on function public.list_identity_tenant_links(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_identity_tenant_links with an identical grant set, never a reimplementation.';

-- app.list_identity_tenant_links: EXECUTE granted to the same roles the base table''s own
-- SELECT grant covers for ordinary reads (authenticated), plus service_role per this
-- series'' own standing convention (every prior O1 app.* function grants service_role
-- regardless of the underlying table''s own grant list -- e.g. cluster 1 batch 1''s
-- app.get_shipment_actual_cost, cluster 0 batch 1''s app.list_activities_for_record).
-- Never anon: this table carries identity-linkage data (auth_user_id, invited_by,
-- revoked_reason), never meant for an unauthenticated caller.
revoke execute on function app.list_identity_tenant_links(uuid) from public;
grant execute on function app.list_identity_tenant_links(uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO
-- anon, authenticated bootstrap grant on the public schema).
revoke execute on function public.list_identity_tenant_links(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_identity_tenant_links(uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
--
-- server/queries/auth-identity.ts (currently lines 1-35)
-- ---------------------------------------------------------------------------
-- The `IdentityLookupClient` interface (currently lines 11-17) is `.from()`-shaped only --
-- unlike actual-cost.ts/billing-readiness.ts in cluster 1 batch 1, "rpc" was never part of
-- this file''s client alias at all. Replace it entirely (nothing else in this file, or
-- anywhere else in the repo -- confirmed by repo-wide grep for "IdentityLookupClient",
-- whose only hits are this file''s own declaration and its own test file''s three usages --
-- depends on the `.from()` shape):
--
--   Before:
--     export interface IdentityLookupClient {
--       from(table: "tenant_user_identities"): {
--         select(columns: string): {
--           eq(column: string, value: string): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
--         };
--       };
--     }
--
--   After:
--     export interface IdentityLookupClient {
--       rpc(
--         fn: "list_identity_tenant_links",
--         args: { p_actor_auth_user_id: string },
--       ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
--     }
--
-- listIdentityTenantLinks itself (currently lines 26-34) -- signature is UNCHANGED (still
-- one client + one `authUserId: string` argument -- no call site needs a new argument
-- threaded through, since this is now a self-lookup and authUserId already IS the actor''s
-- own id), only the body and its own doc comment change:
--
--   Before (doc comment, line 26):
--     /** Every tenant an auth identity is currently linked to (any status -- caller
--      * filters by status if only active/invited linkages are wanted). */
--
--   After:
--     /** Every tenant the CALLING identity is currently linked to (any status -- caller
--      * filters by status if only active/invited linkages are wanted). Self-lookup only --
--      * authUserId must be the caller''s own session identity; the database rejects any
--      * other value with actor_identity_mismatch (ATW-031/032). */
--
--   Before (body, lines 27-34):
--     export async function listIdentityTenantLinks(client: IdentityLookupClient, authUserId: string): Promise<TenantUserIdentity[]> {
--       const { data, error } = await client.from("tenant_user_identities").select("*").eq("auth_user_id", authUserId);
--
--       if (error) {
--         throw new IdentityLookupError(error.message);
--       }
--       return (data ?? []).map((row) => parseTenantUserIdentity(row as Record<string, unknown>));
--     }
--
--   After:
--     export async function listIdentityTenantLinks(client: IdentityLookupClient, authUserId: string): Promise<TenantUserIdentity[]> {
--       const { data, error } = await client.rpc("list_identity_tenant_links", {
--         p_actor_auth_user_id: authUserId,
--       });
--
--       if (error) {
--         throw new IdentityLookupError(error.message);
--       }
--       return (data ?? []).map((row) => parseTenantUserIdentity(row as Record<string, unknown>));
--     }
-- (RETURNS SETOF already comes back as an array via .rpc(), exactly like the old
-- `data ?? []` array shape -- unlike the cluster 1 batch 1 RETURNS TABLE-plus-.maybeSingle()
-- cases, no Array.isArray(data) ? data[0] : data unwrap is needed here at all.)
--
-- Live call sites needing a change: NONE FOUND. Repo-wide grep for "listIdentityTenantLinks("
-- outside this file and its own test returns zero hits -- no page.tsx, route handler,
-- server action, or any other production module calls this function today. The only other
-- reference is server/queries/auth-identity.test.ts:37,48,56 (describe("listIdentityTenant
-- Links")), which mocks a `.from`-based IdentityLookupClient today and will need updating to
-- mock `.rpc("list_identity_tenant_links", ...)` instead, returning `{ data: [ROW], error:
-- null }` per test case -- not attempting that rewrite here, per this task''s SQL-only
-- scope (matching cluster 1 batch 1''s identical disclaimer for actual-cost.test.ts).
--
-- Should a future caller need this (e.g. a login-time "which tenants can I access" flow),
-- it must pass its own resolved session auth user id (the same `access.authUserId`
-- convention ATW-030 already established for every other actorAuthUserId call site in
-- app/), never a different identity''s id -- the database now enforces that itself and
-- raises actor_identity_mismatch on any mismatch, so no additional TS-side guard is needed
-- beyond passing the right value in the first place.

-- ===========================================================================
-- TABLE 2 of 4: app.users (tenant lifecycle list)
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 2 (HRIS/identity-access),
-- batch 1 of ~N. Continues the same Design->Verify->Fix adversarial pipeline cluster 0's
-- 5 batches (32/32 tables closed) and cluster 1's 1 batch (6/6 tables closed) established
-- (RULE A/B/C baked into this draft below), user-directed ("lanjut sampe siap launching")
-- extension of CG-AUDIT-2026-09-02's Ø1-query-layer finding: supabase/config.toml only
-- exposes "public"/"graphql_public" to PostgREST, so every `.from()` read against the
-- "app" schema has never worked in production.
--
-- SCOPE OF THIS FRAGMENT (1 of 2 halves of one TS function -- see note below): closes the
-- app.users half of server/queries/user-lifecycle.ts:63 (listTenantUsers), 1 of cluster 2's
-- broken `.from()` call sites:
--   1. app.users (BASE TABLE)  server/queries/user-lifecycle.ts:63 (listTenantUsers, the
--      `client.from("users").select(USERS_GRANTED_COLUMNS).eq("tenant_id", tenantId)` half)
--
-- NOT in scope, deliberately: server/queries/user-lifecycle.ts:64's sibling
-- `client.from("users_directory").select("id, email, email_masked").eq("tenant_id",
-- tenantId)` read (the SAME TS function, listTenantUsers, merges both halves by id). A
-- DIFFERENT agent is fixing that half in parallel over app.users_directory -- see the
-- "TS INTEGRATION" section at the end of this file for how the two fixes are meant to be
-- merged into one final function body. This fragment does not create, alter, or grant
-- anything on app.users_directory, and does not touch server/queries/user-lifecycle.ts:64.
--
-- SEVERITY (unchanged from every prior Ø1 batch's own header): this is a live, currently-
-- broken read path behind the Tenant Admin's user lifecycle list (every user of a tenant,
-- any status -- draft/invited/active/suspended/revoked -- an admin-only UI capability per
-- this function's own module header at server/queries/user-lifecycle.ts:1-30), not merely
-- an architectural backlog item. No page.tsx call site currently exists for listTenantUsers
-- (confirmed: repo-wide grep for "listTenantUsers" outside server/queries/user-lifecycle.ts
-- itself finds only server/queries/user-lifecycle.test.ts) -- fixed anyway, per this series'
-- own established "the broken .from() read is broken regardless of caller count" precedent
-- (cluster 1 batch 1's getBillingReadinessEvaluationHistory/listFinanceRoundingModes).
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior Ø1 remediation commit in this
-- series): a new `app.*` SECURITY DEFINER function performing the equivalent SELECT with
-- correct tenant/RLS scoping (taking the actor id as an explicit `p_actor_auth_user_id`
-- parameter, never relying on `auth.uid()` session context -- a SECURITY DEFINER function
-- runs as its owner and never evaluates the caller's own RLS), plus a thin `public.*`
-- pass-through wrapper (the only PostgREST-reachable surface, since `app` itself is
-- invisible) carrying an IDENTICAL grant set -- never a reimplementation.
--
-- MANDATORY RULES applied below (baked into every prior Ø1 batch's own design/verify
-- process; independently re-derived here against this repo's live migration state, not
-- assumed from any recon restatement or from this checkpoint's own task framing):
--
--   RULE A (actor-impersonation guard, ATW-031/032, ISS-2026-017/032): the new function
--   below takes an explicit `p_actor_auth_user_id` and is granted to `authenticated`, so
--   `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the FIRST
--   executable statement, before any lookup or authority check. Confirmed against
--   app.assert_actor_is_session_identity's own CURRENT (and only-ever, one `create or
--   replace`, never re-replaced) body -- 20260730440000_harden_actor_identity_session_
--   crosscheck.sql:59-89 -- repo-wide grep for "create or replace function app.assert_
--   actor_is_session_identity" / "create function app.assert_actor_is_session_identity"
--   (sorted by filename) confirms exactly one hit, this one. A no-op whenever the session
--   `auth.uid` is null (service_role/superuser/db-tests/nested SECURITY DEFINER calls),
--   raising `actor_identity_mismatch` only when a genuine authenticated session's own
--   identity differs from the claimed `p_actor_auth_user_id`.
--
--   RULE B (RLS predicate currency -- IMPORTANT FINDING, do not assume): app.users' own
--   SELECT policy is named `users_select_own_tenant`. Repo-wide grep for the bare policy
--   name across every file in supabase/migrations/*.sql, sorted by filename, finds exactly
--   TWO hits:
--     * 20260716105512_create_rls_tenant_policies.sql:126-129 -- the ORIGINAL `create
--       policy users_select_own_tenant on app.users for select to authenticated using
--       (app.has_active_tenant_membership(tenant_id));` -- plain tenant membership, no
--       admin-authority conjunct, no `is_supreme_admin()` branch.
--     * 20260730560000_harden_customer_user_layer_default_deny.sql:334-335 -- a later
--       rewrite of that SAME policy: `using ((app.has_active_tenant_membership(tenant_id)
--       AND NOT app.actor_holds_customer_user_layer(tenant_id)));` -- this is the CURRENT,
--       only-ever-rewritten text (confirmed no third hit exists for this policy name
--       anywhere in the migration set).
--   This is the ONLY predicate app.users' own SELECT policy carries -- no admin-authority/
--   role check of any kind is layered onto it at the RLS level (unlike, e.g.,
--   `accounts_select_scoped`, which separately ORs in `app.is_supreme_admin()` at the top
--   level of ITS OWN policy text). The task framing that this is an "admin-only capability"
--   describes the TENANT ADMIN UI FEATURE consuming this read (every status, not just
--   active, is a lifecycle-management view), not a stricter row-visibility rule the real
--   database policy itself enforces -- there is no live page.tsx caller today to confirm
--   an application-layer admin gate either (see SEVERITY note above), so the only concrete,
--   verifiable authority requirement for THIS read, right now, is app.users' own real
--   policy text quoted above: active tenant membership, with the customer_user layer
--   explicitly excluded. This function reproduces exactly that, not a stronger predicate
--   invented for this task -- "reproduce the RLS this table already has," never "redesign
--   it," is this series' own established discipline (see RULE B in every prior batch's own
--   header, e.g. 20260910000000:147-178). Note for whoever wires the real Tenant Admin
--   page: if that page needs an admin-only gate beyond plain tenant membership, that is a
--   NEW authority decision belonging to whoever builds that page, not something this
--   remediation fragment should silently invent by tightening the predicate below.
--   `app.has_active_tenant_membership` itself already folds an `app.is_supreme_admin(...)`
--   OR-branch and an `app.has_active_support_grant(...)` OR-branch into its own body (see
--   RULE C below), so a Supreme Admin or an active support grant already satisfies this
--   predicate without any separate top-level OR needed here, matching app.users' own real
--   policy text verbatim (which also has no separate top-level OR).
--
--   RULE C (precedent staleness): every existing app.* function relied on below was
--   independently re-confirmed against its MOST RECENT `create or replace function`, not
--   merely its original creation migration:
--     * app.has_active_tenant_membership(uuid, uuid) -- repo-wide grep for "create or
--       replace function app.has_active_tenant_membership" / "create function app.has_
--       active_tenant_membership" finds THREE hits: 20260716105512_create_rls_tenant_
--       policies.sql (original), 20260716111315_create_support_access.sql (adds the
--       support-grant OR-branch), and 20260907110000_fix_suspended_user_retains_access_
--       iss_d3b.sql (D3b -- the latest, by filename). The current body (20260907110000:
--       64-79) is: a genuinely active app.tenant_user_identities linkage for this tenant
--       WHERE THE CORRESPONDING app.users ROW IS NOT suspended/revoked, OR
--       app.is_supreme_admin(p_auth_user_id), OR app.has_active_support_grant(p_tenant_id,
--       p_auth_user_id). This is the current body reproduced by composition below (the
--       function is called directly with an explicit p_actor_auth_user_id argument, never
--       re-implemented inline, so it always tracks whatever this helper's own latest
--       version does).
--     * app.actor_holds_customer_user_layer(uuid, uuid) -- repo-wide grep for "create or
--       replace function app.actor_holds_customer_user_layer" / "create function app.
--       actor_holds_customer_user_layer" finds exactly ONE hit, 20260730311000_harden_
--       customer_inventory_access_rls_isolation.sql:71-84 -- never replaced, so that
--       original body (an ACTIVE app.principal_memberships row with layer='customer_user'
--       for this tenant/identity) is already current. Called directly by composition,
--       same discipline as above.
--     * app.assert_actor_is_session_identity(uuid) -- see RULE A above, one hit, current.
--
-- DELIBERATE COLUMN EXCLUSION (contract fidelity, the "return exactly what the TS contract
-- consumes" discipline cluster 0 batch 4's app.prospects fix / cluster 1 batch 1's
-- app.billing_readiness_evaluations fix established -- checked against the REAL contract
-- file and the REAL column grant, not assumed):
--   app.users has 18 physical columns (20260716102620_create_users.sql:16-40): id,
--   tenant_id, auth_user_id, EMAIL, display_name, status, org_unit_id, invited_by,
--   invited_at, invite_expires_at, activated_at, suspended_at, suspended_reason, revoked_at,
--   revoked_reason, record_version, created_at, updated_at. `email` is deliberately excluded
--   from this function's RETURNS TABLE -- this is not merely a contract-fidelity nicety here,
--   it is load-bearing for PLT-114's own field-masking design: 20260716110430_create_field_
--   record_access.sql:134-139 does `revoke select on app.users from authenticated` and
--   re-grants SELECT on an explicit 17-column list that OMITS email, "precisely so a column-
--   level revoke cannot be undone by [the] broader table-level grant" (server/queries/user-
--   lifecycle.ts:9-11's own module header, quoting the same design). A SECURITY DEFINER
--   function runs as its OWNER, not as `authenticated` -- it is NOT subject to that column-
--   level grant at all, so a careless `returns setof app.users` / `select *` here would
--   silently reintroduce a raw, unmasked email read for every authenticated caller,
--   regressing PLT-114 through the exact same class of hole this whole Ø1 remediation
--   series exists to close, not merely fail contract fidelity. This function's RETURNS
--   TABLE therefore explicitly lists exactly the 17 columns 20260716110430:135-139 itself
--   grants (id, tenant_id, auth_user_id, display_name, status, org_unit_id, invited_by,
--   invited_at, invite_expires_at, activated_at, suspended_at, suspended_reason, revoked_at,
--   revoked_reason, record_version, created_at, updated_at) -- verified against server/
--   queries/user-lifecycle.ts:38-39's own USERS_GRANTED_COLUMNS constant (identical list,
--   identical order) and against server/contracts/user-lifecycle/user-lifecycle.ts's own
--   parseTenantUser (lines 61-83), which reads every one of these 17 fields (mapped to its
--   own camelCase TenantUser shape) and reads `email`/`emailMasked` from the SEPARATE
--   app.users_directory projection argument instead, never from this half's row. No column
--   this function returns is unused by the contract, and no contract field this function is
--   responsible for is missing from its return shape.
--
-- ROW-NOT-FOUND / DENIED-ACCESS BEHAVIOR: this is a "list for one named, caller-supplied
-- tenant" call shape (`p_tenant_id` is an explicit parameter, exactly like the original
-- `.eq("tenant_id", tenantId)` filter) -- the same shape as app.list_accounts (cluster 0
-- batch 1, 20260908020000:279-309). Following that precedent exactly: a caller with no
-- standing for `p_tenant_id` at all (fails app.users' own reproduced predicate for every
-- row, since the predicate does not vary per-row) raises `insufficient_authority`, never a
-- silent empty page -- collapsing "not a member of this tenant" into "tenant has zero
-- users" would be a worse, more confusing failure mode for an admin-facing lifecycle list
-- than a real error. A genuine member sees every one of the tenant's own users regardless
-- of status (the original `.eq("tenant_id", tenantId)` read applied no status filter and no
-- ordering -- neither is added here, preserving exact existing behavior).
--
-- No p_limit/pagination: the original `.from()` call site never applied a `.range()`/
-- `.limit()` either, and a tenant's own user roster is a bounded, human-scale list (staff
-- headcount), not an unbounded tenant-wide feed -- matches cluster 1 batch 1's identical
-- reasoning for billing-readiness evaluation/handoff history (20260910000000:278-283).
-- Introducing a cap the original code never had would itself be a silent behavior change on
-- an admin lifecycle view that needs to show every user, not the same "minimize behavior
-- change vs. the existing TS layer" discipline this series has followed throughout.
--
-- GRANT PARITY -- CORRECTED after independent re-verification (do not trust the first-pass
-- reasoning below at face value): app.users' own SELECT grant (20260716110430_create_
-- field_record_access.sql:135-139) genuinely is `to authenticated` ONLY -- repo-wide grep
-- for "app.users" combined with "service_role" finds zero hits anywhere; unlike every other
-- Ø1-remediated table/view sampled (app.accounts, app.win_loss_reasons, app.pipeline_
-- categories -- all `to authenticated, service_role` from their own original CREATE TABLE
-- migration), `service_role` was never separately granted direct SELECT on this specific
-- table (PLT-113/PLT-114's own original scope decision, not an oversight introduced here).
--
-- A first-pass draft of this migration mirrored that table-level omission onto this
-- function's own EXECUTE grant (`authenticated` only) and cited 20260910000000:426-428
-- (app.get_shipment_actual_cost) as precedent for doing so. That citation was WRONG on
-- inspection -- 20260910000000:426-428 actually reads `grant execute on function app.
-- get_shipment_actual_cost(uuid, uuid) to authenticated, service_role;`, because the view
-- it replaces (app.shipment_actual_costs_directory) was itself granted to `authenticated,
-- service_role`. It is an example of the mirroring RULE correctly producing a BOTH-roles
-- grant, not an example of an authenticated-only grant -- it does not support the
-- authenticated-only conclusion it was cited for.
--
-- More importantly, a repo-wide sweep of every `grant execute on function app.*` line
-- this remediation series has produced so far (cluster 0 batches 1-5, cluster 1 batch 1 --
-- 20260908020000/20260909000000/20260909010000/20260909020000/20260909030000/
-- 20260910000000) finds EVERY SINGLE ONE of ~45 O1-remediated app.* functions granted to
-- `authenticated, service_role` -- zero exceptions, regardless of what each one's own
-- underlying base table/view happened to grant. This is because every backend/admin
-- tooling surface in this codebase (cron jobs, support tooling, internal dashboards,
-- migration/backfill scripts) authenticates as `service_role` and needs uniform EXECUTE
-- access across every one of these RPCs -- the SAME reason app.users_directory (the
-- sibling read for the SAME listTenantUsers call, see TS INTEGRATION below) is itself
-- granted `to service_role` (20260716110430:166) despite app.users' own narrower,
-- column-scoped `authenticated` grant being about forcing `email` through the masking
-- view for THAT ROLE specifically, not about excluding service_role from tenant user
-- lifecycle data generally. The RETURNS TABLE below structurally omits `email` for every
-- caller regardless of role, so granting service_role here carries none of the raw-email-
-- leak risk the column-level revoke on the base table exists to prevent -- there is no
-- security reason to make this the one function in the whole series service_role cannot
-- call. Corrected below to `authenticated, service_role`, matching this series' own
-- established, universal convention instead of the table's own narrower, differently-
-- motivated grant.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration fragment carries its own
-- explicit per-function `revoke ... from public` before its final grants, the standing
-- per-migration convention. Per ISS-2026-309 (closed by 20260830200000_correct_public_
-- wrapper_grant_parity.sql): the public.* wrapper below explicitly revokes from
-- `anon, authenticated, service_role, public` (all four) before re-granting exactly the
-- role its app.* counterpart itself grants -- a bare `revoke ... from public` does NOT
-- strip the `anon`/`authenticated` EXECUTE grants Supabase's own ALTER DEFAULT PRIVILEGES
-- rule applies to every new function in schema public at CREATE time.
--
-- check-rls-initplan.ts false-positive avoidance: per this repository's own established
-- practice, every `comment on function ... is '...'` string below avoids combining the
-- literal phrase "create policy"/"alter policy" with a bare, parenthesized `auth.uid()`/
-- `auth.jwt()` mention in the same string -- e.g. "no later rewrite of this policy exists"
-- instead of naming the rewrite mechanism directly, and `auth.uid`/`auth.role` written
-- without a trailing call where it would otherwise sit near such a phrase. The guard itself
-- is never suppressed, only the prose reworded (this header's own `--`-comment prose above
-- IS allowed to use the real SQL keywords freely -- the scanner's own `blankLineComments`
-- step blanks every `--` line before parsing, so only literal `comment on function ... is
-- '...'` string bodies carry this restriction).

-- ===========================================================================
-- app.list_tenant_users -- replaces (half of) server/queries/user-lifecycle.ts:63
-- (the app.users half of listTenantUsers)
-- ===========================================================================
create function app.list_tenant_users(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  auth_user_id uuid,
  display_name text,
  status text,
  org_unit_id uuid,
  invited_by text,
  invited_at timestamptz,
  invite_expires_at timestamptz,
  activated_at timestamptz,
  suspended_at timestamptz,
  suspended_reason text,
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer,
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
    app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
    and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list users for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    u.id,
    u.tenant_id,
    u.auth_user_id,
    u.display_name,
    u.status,
    u.org_unit_id,
    u.invited_by,
    u.invited_at,
    u.invite_expires_at,
    u.activated_at,
    u.suspended_at,
    u.suspended_reason,
    u.revoked_at,
    u.revoked_reason,
    u.record_version,
    u.created_at,
    u.updated_at
  from app.users u
  where u.tenant_id = p_tenant_id;
end;
$$;

comment on function app.list_tenant_users(uuid, uuid) is
  'PLT-110/O1 remediation: every app.users row for one tenant, any lifecycle status (invited/active/suspended/revoked), replacing the app.users half of server/queries/user-lifecycle.ts''s broken .from("users") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Authority reproduces users_select_own_tenant''s own current predicate verbatim -- active tenant membership (which already folds in a Supreme Admin exception and an active support grant, see app.has_active_tenant_membership''s own current body) with the customer_user layer explicitly excluded -- confirmed via repo-wide grep that no later rewrite of this policy exists beyond the one already reproduced here. Raises insufficient_authority (never a silent empty page) when the actor has no standing for p_tenant_id at all, matching app.list_accounts for this same "list for one named tenant" call shape. Deliberately excludes the physical email column -- returning it here would bypass PLT-114''s own column-level grant restriction on app.users, which exists specifically so email can only be read through app.users_directory''s masking projection; this function''s caller (listTenantUsers) merges that projection back in from a separate read. No ordering, no row limit -- the original .from() read applied neither, and a tenant''s own user roster is a bounded, human-scale list.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_tenant_users with an identical grant set, never a
-- reimplementation.
create function public.list_tenant_users(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  auth_user_id uuid,
  display_name text,
  status text,
  org_unit_id uuid,
  invited_by text,
  invited_at timestamptz,
  invite_expires_at timestamptz,
  activated_at timestamptz,
  suspended_at timestamptz,
  suspended_reason text,
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_tenant_users(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_tenant_users(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_tenant_users with an identical grant set, never a reimplementation.';

-- app.list_tenant_users: `authenticated, service_role`, matching this remediation series'
-- own established, universal convention (every one of ~45 prior O1-remediated app.*
-- functions across cluster 0/cluster 1 grants both roles) -- NOT a bare mirror of app.
-- users' own narrower, differently-motivated table-level grant (see GRANT PARITY note
-- above for why that mirroring reasoning does not actually apply here).
revoke execute on function app.list_tenant_users(uuid, uuid) from public;
grant execute on function app.list_tenant_users(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO
-- anon, authenticated bootstrap grant on the public schema).
revoke execute on function public.list_tenant_users(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_tenant_users(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
--
-- IMPORTANT -- this fixes only ONE of the two reads inside listTenantUsers.
-- server/queries/user-lifecycle.ts:64 (`client.from("users_directory").select("id, email,
-- email_masked").eq("tenant_id", tenantId)`) is being fixed SEPARATELY by a parallel agent
-- working on app.users_directory (its own app.*/public.* wrapper, e.g. something shaped
-- like app.list_tenant_users_directory / public.list_tenant_users_directory -- exact name
-- to be confirmed against whatever that agent lands). Both changes touch the SAME function
-- body (listTenantUsers merges the two reads by id today, at server/queries/user-
-- lifecycle.ts:74-90) and the SAME file, so they must be merged together, not applied as
-- two independent edits that each rewrite the whole function -- whoever integrates both
-- patches should take ONE final version of listTenantUsers that:
--   1. Calls BOTH rpcs (this one for the app.users half, the parallel agent's for the
--      app.users_directory half) instead of BOTH .from() calls, preserving the existing
--      Promise.all([...]) parallel-fetch shape (lines 62-65) -- neither read depends on the
--      other's result.
--   2. Takes ONE new `actorAuthUserId: string` parameter (not two) and passes it as
--      `p_actor_auth_user_id` to both rpc calls.
--   3. Keeps the existing merge-by-id / emailById Map logic (lines 74-90) unchanged -- it
--      does not care whether its two inputs came from `.from()` or `.rpc()`, only that both
--      resolved to arrays of the same row shapes as before.
--
-- Below is the exact TS change needed for JUST the app.users half (this fragment's own
-- scope), written so it composes cleanly with the users_directory half:
--
-- 1. Client type -- currently `UserLookupClient` (server/queries/user-lifecycle.ts:41-47)
--    only declares `from`. It must widen to also declare `rpc`, e.g.:
--      export interface UserLookupClient {
--        from(table: "users" | "users_directory"): { ... unchanged, or removed entirely
--          once BOTH halves are migrated ... };
--        rpc(
--          fn: "list_tenant_users" | "list_tenant_users_directory", // or whatever name the
--                                                                    // parallel agent lands
--          args: { p_tenant_id: string; p_actor_auth_user_id: string },
--        ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
--      }
--    (Do not remove `from` here unilaterally -- coordinate with the parallel agent's own
--    edit so the interface change lands once, not twice.)
--
-- 2. listTenantUsers itself (currently lines 61-91) -- add the new parameter and replace
--    ONLY the app.users half of the Promise.all (line 63):
--      export async function listTenantUsers(
--        client: UserLookupClient,
--        tenantId: string,
--        actorAuthUserId: string,
--      ): Promise<TenantUser[]> {
--        const [users, directory] = await Promise.all([
--          client.rpc("list_tenant_users", {
--            p_tenant_id: tenantId,
--            p_actor_auth_user_id: actorAuthUserId,
--          }),
--          /* users_directory half -- parallel agent's own .rpc() call replaces the
--             existing client.from("users_directory")... line here */
--        ]);
--
--        if (users.error) {
--          throw new UserLookupError(users.error.message);
--        }
--        if (directory.error) {
--          throw new UserLookupError(directory.error.message);
--        }
--        // `users.data` is now an array from RETURNS TABLE (same array shape the code
--        // already expects from `.from()` -- no `Array.isArray` guard needed here, unlike
--        // the single-row .maybeSingle() cases elsewhere in this series, because this was
--        // always a multi-row list read).
--        ... rest of the function (emailById map, final .map()) is unchanged ...
--
-- 3. Real call site needing `actorAuthUserId` threaded through: NONE FOUND. Repo-wide grep
--    for "listTenantUsers" outside server/queries/user-lifecycle.ts and server/queries/
--    user-lifecycle.test.ts returns zero hits -- no page.tsx, route handler, or other
--    server/queries|mutations file calls it today. This is a genuinely unwired admin-
--    lifecycle read (the Tenant Admin "all users, all statuses" list has no live UI/route
--    yet), not a call site this fragment failed to find.
--
-- 4. server/queries/user-lifecycle.test.ts (describe("listTenantUsers"), the whole file)
--    mocks a `.from()`-based fakeClient for BOTH tables today (lines 34-52) and asserts the
--    exact 17-column string requested from "users" (lines 77-88, "never asks app.users for
--    `*`"). Once BOTH halves move to `.rpc()`, that test needs rewriting to mock `.rpc(fn,
--    args)` for both "list_tenant_users" and whatever the directory-half function is named,
--    returning `{ data: [ROW], error: null }` / `{ data: [DIRECTORY_ROW], error: null }`
--    and calling `listTenantUsers(client, TENANT_ID, ACTOR_ID)`. The "never asks app.users
--    for `*`" assertion (lines 77-88) becomes moot once the read is an RPC with a fixed
--    RETURNS TABLE shape (the 17-column discipline is now enforced by this migration's own
--    RETURNS TABLE list, not by a runtime column-string argument) -- it should be replaced
--    with an assertion that the RPC was called with the right `p_tenant_id`/
--    `p_actor_auth_user_id`, or simply dropped as no-longer-applicable, at the discretion of
--    whoever lands the merged edit. Not rewritten here -- both halves need to land together
--    for this file to compile/pass, and only one half is this fragment's own scope.

-- ===========================================================================
-- TABLE 3 of 4: app.users_directory (3 call sites)
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 2 (HRIS/identity-access),
-- batch 1 of ~N. Continues the same Design->Verify->Fix adversarial pipeline cluster 0
-- (5 batches, 32 tables, DONE) and cluster 1 (1 batch, 6 tables, DONE) already
-- established (RULE A/B/C baked into every draft, user-directed "lanjut sampe siap
-- launching" extension of CG-AUDIT-2026-09-02's O1-query-layer finding):
-- supabase/config.toml's `schemas = ["public", "graphql_public"]` never exposes the
-- "app" Postgres schema to PostgREST, so every `.from()` read in server/queries/*.ts
-- against an `app.*` table/view has never worked in production.
--
-- SCOPE: this batch closes exactly ONE table's worth of call sites -- app.users_directory
-- (a VIEW), read at three different call sites, each with a different column/ordering/
-- pagination shape, across three different TS query files:
--   1. server/queries/user-lifecycle.ts:64 (part of listTenantUsers) --
--      `.from("users_directory").select("id, email, email_masked").eq("tenant_id", tenantId)`
--   2. server/queries/portal-users.ts:69-74 (listPortalUsers) --
--      `.from("users_directory").select("id, display_name, status, email, email_masked",
--      { count: "exact" }).eq("tenant_id", input.tenantId).order("display_name",
--      { ascending: true }).range(from, to)`
--   3. server/queries/field-access.ts:62 (listUserDirectory) --
--      `.from("users_directory").select("*").eq("tenant_id", tenantId)`
--
-- Per this codebase's own established "distinct, self-documenting single-purpose RPCs"
-- convention (every prior cluster-0/1 batch; explicitly NOT merged into one flexible
-- function with optional column/order/pagination flags), this migration authors THREE
-- separate app.*/public.* Option-2 wrapper pairs, one per call site:
--   app.list_user_directory_email_projections -- call site 1 (3 columns, unordered,
--                                                 unpaginated)
--   app.list_portal_users                     -- call site 2 (5 columns + total_count,
--                                                 ordered, paginated)
--   app.list_user_directory                   -- call site 3 (all 10 columns, unordered,
--                                                 unpaginated)
--
-- COORDINATION NOTE (parallel work on the SAME TS file): server/queries/user-lifecycle.ts's
-- listTenantUsers does TWO reads today (`Promise.all`, merged by `id`) --
-- `client.from("users").select(USERS_GRANTED_COLUMNS).eq("tenant_id", tenantId)` (line 63,
-- the app.users half) and the `users_directory` read this migration's function #1 replaces
-- (line 64). A different agent is handling the app.users half in parallel -- this migration
-- is ONLY function #1 (the users_directory/email-masking half) below. See the TS
-- INTEGRATION section at the end of this file for exactly how the two halves are meant to
-- merge back into one `listTenantUsers` signature change.
--
-- ===========================================================================
-- app.users_directory: the live view definition, derived, not assumed
-- ===========================================================================
-- Repo-wide grep, sorted by filename, for both spellings:
--   `create view app.users_directory` / `create or replace view app.users_directory`
-- across every file in supabase/migrations/*.sql returns exactly two hits:
--   1. supabase/migrations/20260716110430_create_field_record_access.sql:145 -- the
--      ORIGINAL `create view` (PLT-114). No tenant-scoping WHERE clause at all --
--      security_invoker defaults to false (owner-mode), so the view runs with its
--      OWNER's rights (BYPASSRLS), and this original version relied on RLS
--      "propagating" through the view -- which, per Postgres's own documented
--      semantics, it never does for a non-invoker view.
--   2. supabase/migrations/20260716113048_create_audit_trail.sql:469 -- a LATER
--      `create or replace view` (PLT-116), the CURRENT and only-ever-replaced-once
--      definition. That migration's own header comment (lines 440-468) documents
--      the live, reproduced bug the original version had: querying app.users_directory
--      returned literally every tenant's users to any authenticated caller, because
--      the view's owner has BYPASSRLS and a non-invoker view's RLS posture is its
--      OWNER's, never the caller's. Fix: an explicit
--      `where app.has_active_tenant_membership(u.tenant_id)` predicate added directly
--      to the view's own query -- NOT reliance on the underlying table's RLS. No
--      migration after 20260716113048 touches this view again (confirmed by the same
--      grep above returning only these two hits, and by grepping `alter view
--      app.users_directory` / `drop view app.users_directory` repo-wide -- zero hits
--      for both). The CURRENT view, reproduced verbatim below:
--
--        create or replace view app.users_directory as
--        select
--          u.id, u.tenant_id, u.auth_user_id, u.display_name, u.status, u.org_unit_id,
--          case
--            when app.has_view_personal_data(u.tenant_id) then u.email
--            else app.mask_email(u.email)
--          end as email,
--          not app.has_view_personal_data(u.tenant_id) as email_masked,
--          u.created_at, u.updated_at
--        from app.users u
--        where app.has_active_tenant_membership(u.tenant_id);
--
--      Ten columns, exactly. `grant select on app.users_directory to authenticated,
--      service_role;` (20260716110430:165-166, never touched again since PLT-116 adds
--      no grant statements of its own) is the grant set every function below mirrors.
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior O1 remediation commit): for
-- each broken `.from()` read, a new `app.*` SECURITY DEFINER function reimplements the
-- view's exact row-visibility predicate AND masking logic explicitly, taking the actor
-- id as an explicit `p_actor_auth_user_id` parameter instead of relying on
-- `auth.uid()` session context (a SECURITY DEFINER function never evaluates the
-- invoker's own RLS, and the view's own predicate/masking helpers both default their
-- own actor argument to `auth.uid()` -- every call below supplies the explicit
-- parameter instead of relying on that default, the same fix cluster 0/1 already
-- established for this identical class of problem). Plus a thin `public.*`
-- pass-through wrapper (the only PostgREST-reachable surface, since `app` itself is
-- invisible) carrying an IDENTICAL grant set -- never a reimplementation.
--
-- ===========================================================================
-- RULE A (actor-impersonation guard, ATW-031/032, ISS-2026-017/032)
-- ===========================================================================
-- All three new app.* functions below take an explicit `p_actor_auth_user_id` and are
-- granted to `authenticated` (see grants below), so `app.assert_actor_is_session_
-- identity(p_actor_auth_user_id)` is the FIRST executable statement in every function
-- body, before any lookup or authority check -- as a leading `perform` (plpgsql,
-- function #2) or a leading bare `select` (sql, functions #1/#3, matching app.list_
-- costing_response_components' own established "language sql, leading select app.
-- assert_actor_is_session_identity(...), then a plain select" shape,
-- 20260909010000:472-479). Confirmed against app.assert_actor_is_session_identity's own
-- CURRENT (and only-ever, single `create or replace`) body -- repo-wide grep for
-- "create or replace function app.assert_actor_is_session_identity" / "create function
-- app.assert_actor_is_session_identity" (sorted by filename) confirms exactly one hit,
-- 20260730440000_harden_actor_identity_session_crosscheck.sql:59 -- a no-op whenever the
-- session `auth.uid` is null (service_role/superuser/db-tests/nested SECURITY DEFINER
-- calls, read defensively via begin/exception so a missing auth schema degrades rather
-- than raises), raising `actor_identity_mismatch` only when a genuine authenticated
-- session's own identity differs from the claimed `p_actor_auth_user_id`.
--
-- ===========================================================================
-- RULE B (RLS predicate currency)
-- ===========================================================================
-- app.users_directory is a VIEW, so this needed checking three ways, not assumed from
-- any restated summary:
--
-- 1. Does row visibility come from the view's OWN WHERE clause? Yes -- see the view
--    definition above: `where app.has_active_tenant_membership(u.tenant_id)`, added by
--    PLT-116 specifically BECAUSE a non-security-invoker view's RLS posture is its
--    OWNER's, never the caller's (that migration's own header proves this live, by
--    reproducing the cross-tenant leak the ORIGINAL view had before that WHERE clause
--    existed). This is the real, load-bearing, and ONLY row-visibility mechanism this
--    view has.
-- 2. Does the underlying table's RLS ALSO apply (the view running as invoker against
--    it)? No -- `security_invoker` was never set to true for this view (confirmed:
--    grepped "alter view app.users_directory" and the view's own two `create`/`create or
--    replace` statements above, neither sets `security_invoker`, so it stays at
--    Postgres's own default of false). A non-invoker view runs its defining query with
--    the VIEW OWNER's privileges and RLS posture, not the caller's or the underlying
--    table's policies -- app.users' own RLS policies are therefore structurally
--    irrelevant to what this view itself returns, which is exactly PLT-116's own
--    documented reason for adding the explicit WHERE clause in the first place rather
--    than trusting policy propagation.
-- 3. Repo-wide grep for a policy literally named against `users_directory` (both `create
--    policy`/`alter policy` naming it, and the bare string `users_directory` inside any
--    policy-related statement) across every file in supabase/migrations/*.sql: zero
--    hits. Views do not carry RLS policies of their own in Postgres at all (RLS
--    attaches to tables) -- there never was one to become stale.
--
-- Each function restates the view's own current WHERE clause --
-- `app.has_active_tenant_membership(u.tenant_id)` -- with the function's own explicit
-- `p_actor_auth_user_id` in place of the default `auth.uid()` argument, plus each call
-- site's own explicit `tenant_id = p_tenant_id` filter (the same filter every one of the
-- three original `.from()` calls already applies via `.eq("tenant_id", ...)` -- the
-- view's own WHERE clause alone does not scope to one tenant, since a caller who is an
-- active member of MULTIPLE tenants would otherwise see every one of them merged
-- together) -- BUT NOT verbatim: adversarial review (CG-AUDIT-2026-09-02 verify pass)
-- found a real drift here and corrected it rather than merely disclosing it, for the
-- reasons below.
--
-- FOUND AND CORRECTED, NOT REPRODUCED VERBATIM: app.users' OWN base-table RLS policy
-- (`users_select_own_tenant`) was hardened by 20260730560000_harden_customer_user_
-- layer_default_deny.sql, which rewrote it (and 97 sibling tenant-membership-only
-- policies) to additionally exclude a customer_user-layer principal --
-- `app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_
-- layer(tenant_id)` (that file, line 334-335; app.actor_holds_customer_user_layer's own
-- single, never-replaced definition is 20260730311000_harden_customer_inventory_
-- access_rls_isolation.sql:71). app.users_directory's own WHERE clause was never given
-- the equivalent exclusion -- and, per point 2 above, structurally COULD NOT have
-- inherited it from that base-table policy rewrite even if someone had intended it to,
-- because this view never evaluates app.users' RLS at all.
--
-- Read 20260730560000's own header directly (its full text, not a restated summary)
-- before treating this as a deliberate, scoped exclusion: it says nothing about views
-- anywhere in it, and its own mechanism -- `alter policy ... using (...)` against 98
-- explicitly named table policies -- has no equivalent it could even apply to a view;
-- RLS policies attach to tables, not views (the same fact RULE B point 3 above already
-- establishes), so app.users_directory was never a candidate that migration could have
-- "decided to leave alone." Its own "Why it is needed" section instead names the exact
-- risk this migration exists to close: a customer_user-layer principal "could read
-- finance_journals, credit_profiles, customer_contracts, role_assignments, users,
-- vehicle telemetry and the rest of this list -- through a raw Supabase client, with no
-- portal code involved at all" -- `users` is named explicitly as one of the tables this
-- hardening pass exists to keep a customer_user-layer principal out of. That same
-- migration's own live-verified premise applies unchanged here too: "app.invite_user
-- writes an app.tenant_user_identities row, has_active_tenant_membership reads exactly
-- that table, and a freshly granted customer_user principal returns
-- has_active_tenant_membership = true alongside actor_holds_customer_user_layer = true"
-- -- i.e. a customer_user-layer principal genuinely satisfies this view's own WHERE
-- clause today; this is not a theoretical gap. This is a genuine oversight (a view
-- structurally could not be swept by an ALTER-POLICY-only migration), not a disclosed,
-- deliberate scope boundary -- there is no evidence anywhere in that migration's text of
-- an intentional decision to leave app.users_directory open.
--
-- Why fix it here rather than disclose-and-defer (this series' usual posture for an
-- out-of-scope finding): this file's own header establishes that the `app` schema has
-- NEVER been exposed to PostgREST, so none of these three read paths -- including
-- app.users_directory's row set -- has ever been reachable in production before this
-- migration. There is no live behavior to preserve either way. What this migration DOES
-- do is activate a brand-new capability: three SECURITY DEFINER functions granted
-- EXECUTE to `authenticated` broadly, each directly callable by any authenticated
-- session via a raw Supabase client -- not gated by any page-level guard, exactly the
-- threat model 20260730560000's own header describes for its other 98 policies.
-- Shipping that brand-new capability with the view's stale predicate would open a side
-- door, on day one, to the identical row set (this view is a masked projection of
-- app.users, not a different table) that 20260730560000 deliberately closed off for
-- app.users itself -- via all three call sites, including the full, effectively-
-- unmasked-except-email field set in listUserDirectory (display_name, status,
-- org_unit_id, auth_user_id, created_at/updated_at, none of which are redacted by
-- anything in this view).
--
-- Independently confirmed there is no live customer-facing need being served by leaving
-- this open: server/queries/portal-users.ts's own header calls its read a "Tenant Admin
-- portal users-list query," and its one live caller,
-- app/(tenant)/[tenantSlug]/admin/users/page.tsx:49, is gated by
-- lib/portal/tenant-admin-guard.ts, whose own REQUIRED_LAYER constant is exactly
-- "tenant_admin" -- its own header states the layering is deliberate: "Tenant Admin
-- only; Supreme/customer/organizational roles route to appropriate surfaces."
-- server/queries/user-lifecycle.ts's listTenantUsers and server/queries/field-access.ts's
-- listUserDirectory have NO live page.tsx caller at all (grepped repo-wide -- only their
-- own *.test.ts files call either). So no legitimate customer-facing feature anywhere in
-- this repository today needs a customer_user-layer principal to read this directory --
-- the exclusion costs zero real functionality, staff-facing or otherwise.
--
-- Per this series' own RULE B discipline (take the underlying table's/policy's CURRENT,
-- most-hardened predicate when it and a derived object's own predicate diverge, rather
-- than reproduce a stale one) and because there is no live behavior for this brand-new
-- capability to preserve either way, all three functions below add
-- `and not app.actor_holds_customer_user_layer(u.tenant_id, p_actor_auth_user_id)`
-- alongside the view's own `app.has_active_tenant_membership` predicate -- matching
-- app.users' own CURRENT, hardened `users_select_own_tenant` policy exactly, instead of
-- the view's stale, never-patched one. This is a correction confined to, and disclosed
-- in, the three new functions this migration is already authoring -- the view itself
-- (app.users_directory) is left untouched and still carries its own stale predicate,
-- since altering a pre-existing view is outside this migration's mandate and the view
-- itself is unreachable via PostgREST regardless.
--
-- ===========================================================================
-- RULE C (precedent staleness) -- every function/helper cited above and below
-- ===========================================================================
--   * app.has_active_tenant_membership(uuid, uuid) -- repo-wide grep for "create or
--     replace function app.has_active_tenant_membership" / "create function app.has_
--     active_tenant_membership" finds three hits: the original
--     20260716105512_create_rls_tenant_policies.sql:61, an intermediate rewrite in
--     20260716111315_create_support_access.sql:285 (adds the has_active_support_grant
--     branch), and the MOST RECENT, 20260907110000_fix_suspended_user_retains_access_
--     iss_d3b.sql:64 (CG-AUDIT-2026-09-02 D3b) -- the body reproduced by every function
--     below via a direct call (never re-derived inline): a genuinely active app.tenant_
--     user_identities linkage AND no corresponding app.users row that is suspended/
--     revoked, OR app.is_supreme_admin, OR app.has_active_support_grant. Calling this
--     function directly (rather than re-deriving its predicate inline, which every
--     function below does NOT do) means this migration automatically stays correct if
--     it is ever rewritten again -- the same "call the helper, don't inline its body"
--     discipline the view itself already uses.
--   * app.is_supreme_admin(uuid) -- repo-wide grep for "create or replace function
--     app.is_supreme_admin" finds zero hits; "create function app.is_supreme_admin"
--     finds exactly one, the original 20260716105512_create_rls_tenant_policies.sql:45
--     -- never replaced, called only transitively via has_active_tenant_membership
--     above, not directly by any function below.
--   * app.has_view_personal_data(uuid, uuid) -- repo-wide grep for "create or replace
--     function app.has_view_personal_data" finds zero hits; "create function app.has_
--     view_personal_data" finds exactly one, 20260716110430_create_field_record_
--     access.sql:88 -- never replaced. Current (and only-ever) body: a thin SECURITY
--     DEFINER wrapper delegating to app.evaluate_permission for the HRS module's "View
--     personal data" action, its own second parameter defaulting to `auth.uid` --
--     every call below always supplies its own explicit `p_actor_auth_user_id` for that
--     argument instead of relying on the default, the same "explicit actor arg instead
--     of a nested-call default-auth reliance" fix cluster 1 batch 1's own app.has_view_
--     actual_cost citation already established for this identical shape.
--   * app.mask_email(text) -- repo-wide grep for "create or replace function app.mask_
--     email" finds zero hits; "create function app.mask_email" finds exactly one,
--     20260716110430_create_field_record_access.sql:108 -- never replaced. Deterministic,
--     non-reversible redaction (first character + domain); immutable, no actor
--     parameter to go stale.
--   * app.assert_actor_is_session_identity(uuid) -- see RULE A above; current body
--     confirmed at 20260730440000:59, the only `create or replace`.
--   * app.actor_holds_customer_user_layer(uuid, uuid) -- added to all three functions
--     below by this migration's own adversarial verify pass, not part of the view's own
--     predicate (see RULE B above for the full derivation of why). Repo-wide grep for
--     "create or replace function app.actor_holds_customer_user_layer" finds zero hits;
--     "create function app.actor_holds_customer_user_layer" finds exactly one,
--     20260730311000_harden_customer_inventory_access_rls_isolation.sql:71 -- never
--     replaced. Current (and only-ever) body: true iff an active
--     app.principal_memberships row exists for this (tenant_id, auth_user_id) pair with
--     layer = 'customer_user'; every call below always supplies its own explicit
--     `p_actor_auth_user_id` for the second argument instead of relying on the
--     function's own `default auth.uid()`.
--   * Paginated-list-with-exact-count precedent (function #2 below): repo-wide grep for
--     `total_count bigint` / `count(*) over()` inside supabase/migrations/*.sql surfaces
--     app.list_contacts (20260908020000_close_o1_query_layer_cluster0_batch1_crm_
--     core.sql:898-959) and its own siblings app.list_leads / app.list_opportunities /
--     app.list_prospects (same series, cluster 0 batches 2/4) -- all four share the
--     identical shape: `p_page`/`p_page_size` (defensively clamped server-side via
--     `least(greatest(coalesce(...), 1), 100)`), a plain OFFSET/LIMIT, and a `count(*)
--     over()` window column aliased `total_count`, chosen specifically (over this
--     schema's newer `p_limit`/`p_after_id` keyset idiom, 20260907160000) because the
--     TS-layer contract needs an EXACT total count and the ability to jump to an
--     arbitrary page number -- exactly server/queries/portal-users.ts's own existing
--     `ListPortalUsersResult.totalCount` / numbered-page `Pagination` UI
--     (app/(tenant)/[tenantSlug]/admin/users/page.tsx:102-107) requirement. Repo-wide
--     grep for a later `create or replace function app.list_contacts`: zero hits --
--     the body cited (and imitated below) is current. app.list_portal_users below
--     follows this established convention exactly, rather than inventing a different
--     pagination shape for the identical UI requirement.
--
-- ===========================================================================
-- CONTRACT FIDELITY ("return exactly what the TS contract consumes",
-- cluster 0 batch 4's app.prospects fix)
-- ===========================================================================
--   * app.list_user_directory_email_projections: server/queries/user-lifecycle.ts's own
--     inline read (`.select("id, email, email_masked")`) consumes exactly these 3
--     columns, merged into TenantUserSchema's `id`/`email`/`emailMasked` fields
--     (server/contracts/user-lifecycle/user-lifecycle.ts:61-83, parseTenantUser) -- no
--     exclusion needed, this function returns exactly 3 columns, matching the original
--     `.select(...)` list verbatim.
--   * app.list_portal_users: PortalUserSchema (server/queries/portal-users.ts:20-26)
--     consumes id/displayName/status/email/emailMasked -- exactly the 5 columns the
--     original `.select("id, display_name, status, email, email_masked", ...)` already
--     requested, plus `total_count`, a pagination-plumbing column parsePortalUser
--     (portal-users.ts:50-58) already ignores from a raw row (it destructures only the
--     5 named fields) -- no exclusion needed beyond matching the original select list.
--   * app.list_user_directory: server/contracts/field-access/field-access.ts's own
--     UserDirectoryEntrySchema (lines 19-31) consumes id/tenantId/authUserId/
--     displayName/status/orgUnitId/email/emailMasked/createdAt/updatedAt -- all 10
--     fields, 1:1 with all 10 columns app.users_directory itself projects. Unlike
--     cluster 0 batch 4's app.prospects fix (which found columns the base table
--     exposed that the contract did NOT consume), there is no exclusion to make here --
--     the view itself never had a wider column set than the contract needs, so `select
--     *`'s effective shape and this function's RETURNS TABLE are identical.
--
-- No p_limit/pagination on functions #1/#3: neither original `.from()` call ever
-- applied a `.range()`/`.limit()`, and both read every row for exactly one named
-- tenant -- matching every prior O1 batch's identical reasoning for this same
-- "unbounded-by-original-design, single tenant, human-scale" shape (e.g. cluster 0
-- batch 3's app.list_costing_response_components, which also reproduces an unordered,
-- unpaginated original `.from()` read verbatim rather than inventing an ORDER BY or a
-- cap the original never had).
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): each app.* function below carries
-- its own explicit `revoke execute on function ... from public` before its grant, the
-- standing per-migration convention (matching cluster 1 batch 1's own per-function
-- style, not a single trailing blanket statement). Per ISS-2026-309 (closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql): every public.* wrapper below
-- explicitly revokes from `anon, authenticated, service_role, public` (all four) before
-- re-granting exactly the roles its app.* counterpart itself grants -- a bare `revoke
-- ... from public` does NOT strip the `anon`/`authenticated` EXECUTE grants Supabase's
-- own ALTER DEFAULT PRIVILEGES rule applies to every new function in schema public at
-- CREATE time.
--
-- check-rls-initplan.ts false-positive avoidance: per this repository's own established
-- practice, every `comment on function ... is '...'` string below avoids combining the
-- literal phrase "create policy"/"alter policy" with a bare, parenthesized
-- `auth.uid()`/`auth.jwt()` mention in the same string -- e.g. "no policy of its own
-- exists" instead of naming ALTER POLICY directly near such a call, and `auth.uid`
-- written without a trailing call where it would otherwise sit near such a phrase. The
-- guard itself is never suppressed, only the prose reworded.

-- ===========================================================================
-- 1. app.list_user_directory_email_projections -- replaces
--    server/queries/user-lifecycle.ts:64 (part of listTenantUsers)
-- ===========================================================================
-- Replaces: `.from("users_directory").select("id, email, email_masked")
-- .eq("tenant_id", tenantId)`. Every row for one tenant, no ordering, no pagination --
-- matching the original call verbatim (see file header for why no ORDER BY/LIMIT is
-- added). This is ONLY the users_directory half of listTenantUsers -- the sibling
-- app.users half (line 63 of the same TS function) is a different agent's own scope;
-- see the TS INTEGRATION section at the end of this file for how the two merge.
create function app.list_user_directory_email_projections(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  email text,
  email_masked boolean
)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select
    u.id,
    case
      when app.has_view_personal_data(u.tenant_id, p_actor_auth_user_id) then u.email
      else app.mask_email(u.email)
    end as email,
    not app.has_view_personal_data(u.tenant_id, p_actor_auth_user_id) as email_masked
  from app.users u
  where u.tenant_id = p_tenant_id
    and app.has_active_tenant_membership(u.tenant_id, p_actor_auth_user_id)
    and not app.actor_holds_customer_user_layer(u.tenant_id, p_actor_auth_user_id);
$$;

comment on function app.list_user_directory_email_projections(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 2, HRIS/identity-access): the users_directory half of server/queries/user-lifecycle.ts''s listTenantUsers (line 64) -- the app schema is not exposed to PostgREST, so app.users_directory itself is unreachable via .from(). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Reproduces app.users_directory''s own current view definition directly against its base table app.users: row visibility restates the view''s own where clause (app.has_active_tenant_membership, current per the D3b suspended/revoked-user fix) with an explicit tenant_id filter added (the view''s own predicate alone does not scope to one tenant); the email CASE-mask and email_masked flag are copied verbatim from the view, re-expressed with an explicit p_actor_auth_user_id instead of app.has_view_personal_data''s own default-auth argument. CORRECTED beyond the view''s own predicate (adversarial verify pass, CG-AUDIT-2026-09-02): also excludes an active customer_user-layer principal (not app.actor_holds_customer_user_layer), matching app.users'' own CURRENT, hardened users_select_own_tenant policy (20260730560000) instead of the view''s stale, never-patched where clause -- this migration''s own header explains the full derivation of why the current, hardened predicate is used here rather than the view''s. Unordered, unpaginated -- matches the original .from() read exactly, which never applied either. Returns an empty set (never an exception) for a nonexistent tenant_id, an actor with no active membership there, or a customer_user-layer actor, matching the RLS-filtered .from() read''s own silent-empty-result posture. This is ONLY the users_directory half of listTenantUsers -- the sibling app.users half (line 63 of the same function) is a separate function, authored elsewhere; see this migration''s own TS INTEGRATION note for how the two merge back into one call.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_user_directory_email_projections with an identical grant
-- set, never a reimplementation.
create function public.list_user_directory_email_projections(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  email text,
  email_masked boolean
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_user_directory_email_projections(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_user_directory_email_projections(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_user_directory_email_projections with an identical grant set, never a reimplementation.';

-- Same grant set as the view it replaces (`grant select on app.users_directory to
-- authenticated, service_role;`, 20260716110430:165-166, never touched again).
revoke execute on function app.list_user_directory_email_projections(uuid, uuid) from public;
grant execute on function app.list_user_directory_email_projections(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_user_directory_email_projections(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_user_directory_email_projections(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_portal_users -- replaces server/queries/portal-users.ts:69-74
--    (listPortalUsers)
-- ===========================================================================
-- Replaces: `.from("users_directory").select("id, display_name, status, email,
-- email_masked", { count: "exact" }).eq("tenant_id", input.tenantId)
-- .order("display_name", { ascending: true }).range(from, to)`. Pagination shape
-- follows app.list_contacts' own established "p_page/p_page_size + count(*) over()"
-- convention (see RULE C above) rather than this schema's newer p_limit/p_after_id
-- keyset idiom, because listPortalUsers' own existing, unchanged external contract
-- (ListPortalUsersResult.totalCount, and the numbered-page Pagination UI
-- app/(tenant)/[tenantSlug]/admin/users/page.tsx already renders) needs an EXACT total
-- count and the ability to jump to an arbitrary page number, neither of which a keyset
-- cursor can provide. p_page/p_page_size are defensively clamped server-side
-- (least/greatest) exactly like server/queries/portal-users.ts's own existing
-- MAX_PAGE_SIZE=100 client-side clamp -- defense in depth, since an RPC is directly
-- callable and must not trust a caller-supplied page size. order by display_name asc,
-- id asc adds an id tie-break beyond the original single-column `.order(...)` call, the
-- same determinism-under-pagination discipline app.list_contacts/app.list_leads/
-- app.list_opportunities/app.list_prospects already apply for this identical
-- "arbitrary-page-jump, must not reorder rows across two page fetches" shape.
create function app.list_portal_users(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  display_name text,
  status text,
  email text,
  email_masked boolean,
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

  -- No pre-flight has_active_tenant_membership raise, matching app.list_contacts' own
  -- established reasoning for this identical shape: a non-member or a member with zero
  -- visible rows both silently yield an empty page (total_count 0), exactly as the
  -- original RLS-filtered .from() read's own no-error-on-non-member behavior, never a
  -- thrown error.
  return query
    select
      u.id,
      u.display_name,
      u.status,
      case
        when app.has_view_personal_data(u.tenant_id, p_actor_auth_user_id) then u.email
        else app.mask_email(u.email)
      end as email,
      not app.has_view_personal_data(u.tenant_id, p_actor_auth_user_id) as email_masked,
      count(*) over() as total_count
    from app.users u
    where u.tenant_id = p_tenant_id
      and app.has_active_tenant_membership(u.tenant_id, p_actor_auth_user_id)
      and not app.actor_holds_customer_user_layer(u.tenant_id, p_actor_auth_user_id)
    order by u.display_name asc, u.id asc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_portal_users(uuid, uuid, integer, integer) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 2, HRIS/identity-access): paginated Tenant Admin portal users-list read, replacing server/queries/portal-users.ts:69-74''s broken .from("users_directory") (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row filter and email CASE-mask reproduce app.users_directory''s own current view definition against its base table app.users (see this migration''s own header for the full derivation) -- an explicit tenant_id filter is added since the view''s own where clause alone does not scope to a single tenant. CORRECTED beyond the view''s own predicate (adversarial verify pass, CG-AUDIT-2026-09-02): also excludes an active customer_user-layer principal (not app.actor_holds_customer_user_layer), matching app.users'' own CURRENT, hardened users_select_own_tenant policy (20260730560000) instead of the view''s stale, never-patched where clause -- this Tenant Admin-only read has no legitimate customer-portal caller (server/queries/portal-users.ts''s own header, and its one live caller''s tenant_admin-only guard, confirm this), so the exclusion costs no real functionality. p_page/p_page_size are clamped server-side (1-100), mirroring the TS layer''s own existing MAX_PAGE_SIZE=100 clamp as defense in depth for a directly-callable RPC. total_count is an exact count(*) over() of every row matching the WHERE clause before LIMIT/OFFSET is applied -- the same per-request cost and semantics as the .from() call''s own count:"exact" option, following app.list_contacts'' own established precedent for this exact "exact total, arbitrary page jump" requirement (chosen over this schema''s newer keyset p_limit/p_after_id convention, which cannot support either). order by display_name asc, id asc adds an id tie-break beyond the original single-column ordering, for determinism across page fetches. A non-member, zero-visible-row, or customer_user-layer actor gets an empty page (rows=[], total_count 0), never a thrown error, matching the original RLS-filtered .from() read''s own current behavior exactly.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_portal_users with an identical grant set, never a
-- reimplementation.
create function public.list_portal_users(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  display_name text,
  status text,
  email text,
  email_masked boolean,
  total_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_portal_users(p_tenant_id, p_actor_auth_user_id, p_page, p_page_size);
$wrap$;

comment on function public.list_portal_users(uuid, uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_portal_users with an identical grant set, never a reimplementation.';

revoke execute on function app.list_portal_users(uuid, uuid, integer, integer) from public;
grant execute on function app.list_portal_users(uuid, uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_portal_users(uuid, uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_portal_users(uuid, uuid, integer, integer) to authenticated, service_role;

-- ===========================================================================
-- 3. app.list_user_directory -- replaces server/queries/field-access.ts:62
--    (listUserDirectory)
-- ===========================================================================
-- Replaces: `.from("users_directory").select("*").eq("tenant_id", tenantId)`. Every
-- column of the view (all 10 -- see CONTRACT FIDELITY above, no exclusion needed),
-- every row for one tenant, no ordering, no pagination -- matches the original call
-- verbatim.
create function app.list_user_directory(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  auth_user_id uuid,
  display_name text,
  status text,
  org_unit_id uuid,
  email text,
  email_masked boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select
    u.id,
    u.tenant_id,
    u.auth_user_id,
    u.display_name,
    u.status,
    u.org_unit_id,
    case
      when app.has_view_personal_data(u.tenant_id, p_actor_auth_user_id) then u.email
      else app.mask_email(u.email)
    end as email,
    not app.has_view_personal_data(u.tenant_id, p_actor_auth_user_id) as email_masked,
    u.created_at,
    u.updated_at
  from app.users u
  where u.tenant_id = p_tenant_id
    and app.has_active_tenant_membership(u.tenant_id, p_actor_auth_user_id)
    and not app.actor_holds_customer_user_layer(u.tenant_id, p_actor_auth_user_id);
$$;

comment on function app.list_user_directory(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 2, HRIS/identity-access): the full field-masked directory for one tenant, replacing server/queries/field-access.ts:62''s broken .from("users_directory") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Reproduces app.users_directory''s own current view definition, directly against its base table app.users -- all 10 view columns, none excluded (server/contracts/field-access/field-access.ts''s own UserDirectoryEntrySchema consumes all 10, see this migration''s own CONTRACT FIDELITY section). Row visibility restates the view''s own where clause (app.has_active_tenant_membership, current per the D3b suspended/revoked-user fix) with an explicit tenant_id filter added (the view''s own predicate alone does not scope to one tenant). CORRECTED beyond the view''s own predicate (adversarial verify pass, CG-AUDIT-2026-09-02): also excludes an active customer_user-layer principal (not app.actor_holds_customer_user_layer), matching app.users'' own CURRENT, hardened users_select_own_tenant policy (20260730560000) instead of the view''s stale, never-patched where clause -- this is the full, effectively-unmasked-except-email directory (display_name/status/org_unit_id/auth_user_id/timestamps all pass through verbatim), so leaving the view''s stale predicate in place would have handed a customer_user-layer principal exactly the staff-directory exposure 20260730560000 closed off for app.users itself; this migration''s own header explains the full derivation. Unordered, unpaginated -- matches the original .from() read exactly, which never applied either. Returns an empty set (never an exception) for a nonexistent tenant_id, an actor with no active membership there, or a customer_user-layer actor, matching the RLS-filtered .from() read''s own silent-empty-result posture.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_user_directory with an identical grant set, never a
-- reimplementation.
create function public.list_user_directory(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  auth_user_id uuid,
  display_name text,
  status text,
  org_unit_id uuid,
  email text,
  email_masked boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_user_directory(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_user_directory(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_user_directory with an identical grant set, never a reimplementation.';

revoke execute on function app.list_user_directory(uuid, uuid) from public;
grant execute on function app.list_user_directory(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_user_directory(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_user_directory(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
--
-- 1. server/queries/user-lifecycle.ts -- listTenantUsers (currently lines 61-91)
-- ---------------------------------------------------------------------------
-- SQL-only scope, per this task's own mandate -- not attempting the TS rewrite here.
-- This function does TWO reads today, merged by id: `client.from("users")
-- .select(USERS_GRANTED_COLUMNS).eq("tenant_id", tenantId)` (line 63, a DIFFERENT
-- agent's own scope) and `client.from("users_directory").select("id, email,
-- email_masked").eq("tenant_id", tenantId)` (line 64, THIS migration's function #1).
--
-- COORDINATION: both halves need the identical new required third parameter,
-- `actorAuthUserId: string` (app.assert_actor_is_session_identity needs a real,
-- explicit actor for both new RPCs) -- so `listTenantUsers`''s own signature changes
-- exactly ONCE, to:
--   export async function listTenantUsers(
--     client: UserLookupClient,
--     tenantId: string,
--     actorAuthUserId: string,
--   ): Promise<TenantUser[]> {
--
-- `UserLookupClient` (currently a bespoke `.from(table)` interface, lines 41-47) must
-- widen to expose `.rpc()` instead, once BOTH halves move off `.from()` -- e.g.:
--   export interface UserLookupClient {
--     rpc(
--       fn: "list_user_directory_email_projections", // this migration's function
--       args: { p_tenant_id: string; p_actor_auth_user_id: string },
--     ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
--     // + whatever call signature the sibling app.users-half RPC needs, added by that
--     // other agent's own fix -- both entries live on the SAME widened interface,
--     // there being only one `client` object threaded through this function.
--   }
--
-- This migration's OWN half of the body (replacing line 64 only):
--   client.rpc("list_user_directory_email_projections", {
--     p_tenant_id: tenantId,
--     p_actor_auth_user_id: actorAuthUserId,
--   }),
-- -- in place of `client.from("users_directory").select("id, email, email_masked")
-- .eq("tenant_id", tenantId)` inside the existing `Promise.all([...])` (line 62-65).
-- The result shape from `.rpc()` is an array of `{ id, email, email_masked }` rows
-- (RETURNS TABLE), which is exactly what the existing merge logic (lines 74-89,
-- building `emailById` from `directory.data ?? []`) already expects -- no change
-- needed to the merge logic itself once both `.from()` calls become `.rpc()` calls and
-- their `{ data, error }` shapes are read the same way (`directory.error` /
-- `directory.data` continue to work unchanged, since `.rpc()` also returns `{ data,
-- error }`).
--
-- No live page.tsx call site found: grepped `listTenantUsers(` repo-wide -- the only
-- hits outside its own declaration in server/queries/user-lifecycle.ts are in
-- server/queries/user-lifecycle.test.ts (7 call sites, all needing the new third
-- argument and a `.rpc`-based fakeClient once both halves land) -- not attempting that
-- rewrite here, per this task's SQL-only scope.
--
-- 2. server/queries/portal-users.ts -- listPortalUsers (currently lines 60-86)
-- ---------------------------------------------------------------------------
-- `ListPortalUsersInput` (lines 29-33) gains a required `actorAuthUserId: string`
-- field. The client parameter type (`Pick<SupabaseClient, "from">`, line 61) becomes
-- `Pick<SupabaseClient, "rpc">` -- no other method of `SupabaseClient` is used by this
-- function once `.from()` is gone.
--
-- Full replacement for the current body (lines 60-86):
--   export async function listPortalUsers(
--     client: Pick<SupabaseClient, "rpc">,
--     input: ListPortalUsersInput,
--   ): Promise<ListPortalUsersResult> {
--     const pageSize = Math.min(Math.max(Math.trunc(input.pageSize), 1), MAX_PAGE_SIZE);
--     const page = Math.max(Math.trunc(input.page), 1);
--
--     const { data, error } = await client.rpc("list_portal_users", {
--       p_tenant_id: input.tenantId,
--       p_actor_auth_user_id: input.actorAuthUserId,
--       p_page: page,
--       p_page_size: pageSize,
--     });
--
--     if (error) {
--       throw new PortalUsersQueryError(error.message);
--     }
--
--     const rows = (data ?? []) as Record<string, unknown>[];
--     const totalCount = rows.length > 0 ? Number(rows[0]?.total_count) : 0;
--
--     return {
--       users: rows.map((row) => parsePortalUser(row)),
--       totalCount,
--       page,
--       pageSize,
--     };
--   }
-- (`from`/`to`/`.range()` go away entirely -- the RPC applies LIMIT/OFFSET itself from
-- `p_page`/`p_page_size`, and `count: "exact"`'s separate `count` return value is
-- replaced by unwrapping `rows[0].total_count`, the same idiom app.list_contacts'' own
-- TS INTEGRATION note already establishes for this identical `count(*) over()` shape.
-- `parsePortalUser` needs no change -- it already destructures only the 5 named fields
-- from each row, ignoring the extra `total_count` column.)
--
-- Call site needing the new field -- the one real (non-test) caller repo-wide, grepped
-- `listPortalUsers(` across app/**/*.tsx:
--   app/(tenant)/[tenantSlug]/admin/users/page.tsx:49
--   Before: `result = await listPortalUsers(supabase, { tenantId: access.tenant.id, page, pageSize: PAGE_SIZE });`
--   After:  `result = await listPortalUsers(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, page, pageSize: PAGE_SIZE });`
--   `access.authUserId` is already resolved and in scope at that point (line 36,
--   `resolveTenantAdminAccessForRequest`; `TenantAdminGuardResult`''s own `{ status:
--   "allowed" }` branch carries `authUserId` -- lib/portal/tenant-admin-guard.ts:47) --
--   a mechanical addition, no new lookup needed.
--
-- server/queries/portal-users.test.ts (its own `fakeClient` helper, lines 16-38, and
-- every test in the "listPortalUsers" describe block, lines 40-98) mocks a
-- `.from`-based client today and needs updating to mock `.rpc("list_portal_users",
-- args)` instead, returning `{ data: ROWS.map(r => ({ ...r, total_count: N })), error:
-- null }` (each row now carries its own total_count, per count(*) over()''s per-row
-- window semantics) and passing an `actorAuthUserId` in every `listPortalUsers(client,
-- { ... })` call -- not attempting this rewrite here, per this task''s SQL-only scope.
--
-- 3. server/queries/field-access.ts -- listUserDirectory (currently lines 61-68)
-- ---------------------------------------------------------------------------
-- `UserDirectoryLookupClient` (currently a bespoke `.from(table)` interface, lines
-- 45-51) becomes an `.rpc()`-shaped interface instead:
--   export interface UserDirectoryLookupClient {
--     rpc(
--       fn: "list_user_directory",
--       args: { p_tenant_id: string; p_actor_auth_user_id: string },
--     ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
--   }
--
-- Add a required second parameter `actorAuthUserId: string`, full replacement for the
-- current body (lines 61-68):
--   export async function listUserDirectory(
--     client: UserDirectoryLookupClient,
--     tenantId: string,
--     actorAuthUserId: string,
--   ): Promise<UserDirectoryEntry[]> {
--     const { data, error } = await client.rpc("list_user_directory", {
--       p_tenant_id: tenantId,
--       p_actor_auth_user_id: actorAuthUserId,
--     });
--
--     if (error) {
--       throw new UserDirectoryLookupError(error.message);
--     }
--     return (data ?? []).map((row) => parseUserDirectoryEntry(row as Record<string, unknown>));
--   }
--
-- No live page.tsx call site found: grepped `listUserDirectory(` repo-wide -- the only
-- hits outside its own declaration in server/queries/field-access.ts are in
-- server/queries/field-access.test.ts (2 call sites, both needing the new second
-- argument and a `.rpc`-based fakeDirectoryClient) -- not attempting that rewrite
-- here, per this task's SQL-only scope.

-- ===========================================================================
-- TABLE 4 of 4: app.permissions + app.roles
-- ===========================================================================
-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 2 (HRIS/identity-access)
-- batch 1 of ~N. Continues the same Design->Verify->Fix adversarial pipeline clusters
-- 0 (5 batches, 32 tables) and 1 (1 batch, 6 tables) established (RULE A/B/C baked
-- into every draft below), user-directed ("lanjut sampe siap launching") extension of
-- CG-AUDIT-2026-09-02's Ø1-query-layer finding: supabase/config.toml only exposes
-- "public"/"graphql_public" to PostgREST (`schemas = ["public", "graphql_public"]`),
-- so every .from() read against the "app" schema has never worked in production.
-- Cluster 0 (CRM/commercial) and cluster 1 (finance) are fully closed; this fragment
-- opens cluster 2 (HRIS/identity-access) with the 2 call sites named by
-- docs/build-log/remediation/CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json for
-- server/queries/role-permission.ts (lines 27 and 37, both `NEEDS_NEW_FUNCTION`).
--
-- 2 new app.*/public.* Option-2 wrapper function pairs across 2 tables:
--   app.permissions (BASE TABLE): app.list_permissions_for_module
--   app.roles       (BASE TABLE): app.list_tenant_roles
--
-- SCOPE: closes both of server/queries/role-permission.ts's broken `.from()` call
-- sites:
--   1. app.permissions (line 27, listPermissionsForModule) --
--      `client.from("permissions").select("*").eq("resource_module_code", moduleCode)`
--      -- the full canonical permission catalogue (all columns) for one business-
--      domain module code. Serves role/permission admin UI (e.g. populating the list
--      of assignable permissions when building/editing a role).
--   2. app.roles (line 37, listTenantRoles) --
--      `client.from("roles").select("*").eq("tenant_id", tenantId)` -- every column,
--      every role (any status, including drafts) belonging to one tenant. Serves the
--      tenant's role administration list.
-- Neither function has a live page.tsx caller today (grepped `listPermissionsForModule`/
-- `listTenantRoles` across app/**/*.tsx repo-wide: zero hits) -- only
-- server/queries/role-permission.test.ts references either. Fixed anyway, matching
-- cluster 1 batch 1's own "getBillingReadinessEvaluationHistory has no live page.tsx
-- caller today... fixed anyway since the broken .from() read it replaces is broken
-- regardless of caller count" precedent -- a broken read is broken whether or not a
-- page currently reaches it, and a future tenant role/permission admin UI is the named
-- eventual consumer of exactly these two reads (PLT-111's own build log,
-- docs/build-log/phase-01/PLT-111.md, defers that UI to PLT-135; PLT-135's own build
-- log, docs/build-log/phase-01/PLT-135.md, in turn shipped only the Tenant Admin
-- portal shell + Users list and explicitly deferred Roles/permissions-catalogue admin
-- UI to a still-later, not-yet-built slice -- corrected here from an earlier
-- misattribution of this UI directly to PLT-111).
--
-- SEVERITY: same as every prior Ø1 batch -- the "app" schema is invisible to
-- PostgREST, so both `.from()` calls above have never worked in production. Distinct
-- from every table cluster 0/1 closed so far, this cluster's finding is COMPOUND: even
-- setting the schema-visibility defect aside, app.permissions carries no working
-- read path for the `authenticated` role at all, at any layer -- see the RULE B
-- finding for app.permissions below. app.roles does have a real, working RLS SELECT
-- policy and a real `grant select ... to authenticated` (20260716105512), so for that
-- table the schema-visibility defect is the ONLY defect.
--
-- FIX PATTERN (Option-2 wrapper, identical to every prior Ø1 remediation commit in
-- this series): for each broken `.from()` read, author a new `app.*` function
-- performing the equivalent SELECT with correct authority scoping, plus a thin
-- `public.*` pass-through wrapper (the only PostgREST-reachable surface, since `app`
-- itself is invisible) carrying an IDENTICAL grant set -- never a reimplementation.
--
-- ===========================================================================
-- FINDING: does app.permissions need an actor param at all? (independently derived,
-- not assumed from the cluster 1 batch 1 finance_currencies/finance_rounding_modes
-- precedent just because both are "reference tables")
-- ===========================================================================
-- app.permissions IS a genuinely GLOBAL, non-tenant-scoped catalogue -- its own
-- `create table app.permissions` (20260716103445_create_roles_permissions.sql:20-35)
-- has no tenant_id column at all (id, action, resource_module_code, category,
-- protected, code, created_at -- 7 columns, confirmed against the live `create table`
-- statement). In THAT specific respect it matches the finance_currencies/finance_
-- rounding_modes shape. But the AUTHORITY GATE does not match that precedent, and this
-- was independently re-derived by reading the table's own current RLS state, not
-- assumed from the shared "reference table" label:
--
--   * app.permissions has RLS enabled (`alter table app.permissions enable row level
--     security;`, 20260716103445:550) but repo-wide grep for `on app.permissions`,
--     `permissions_select`, and `policy.*permissions` across every file in
--     supabase/migrations/*.sql (sorted by filename) finds ZERO `create policy`/`alter
--     policy` statements naming this table, ever. RLS-enabled-with-zero-policies is
--     Postgres default-deny for every role except one with BYPASSRLS (service_role,
--     in Supabase).
--   * The ONLY grant this table has ever received is `grant select, insert, update,
--     delete on app.permissions, app.roles, ... to service_role;`
--     (20260716103445:557-559) -- service_role only, never `authenticated`.
--   * 20260716105512_create_rls_tenant_policies.sql (the migration that DID wire up
--     `authenticated`'s grant + SELECT policy for app.roles, see the RULE B finding
--     below) explicitly disclosed app.permissions as OUT of its own scope: "Global,
--     non-tenant-scoped catalogues (app.entitlement_modules/features/packages, app.
--     permissions) are out of this checkpoint's scope entirely -- no live UI consumes
--     them yet" (lines 34-36). Repo-wide grep for any later grant/policy on app.
--     entitlement_modules (the sibling catalogue named in that same disclosure) also
--     finds zero hits -- that deferred decision was never revisited for either
--     catalogue anywhere in this repository, confirming this is a genuinely still-open
--     gap, not one already resolved elsewhere that this fragment could just copy.
--
-- Net effect: unlike app.finance_currencies/app.finance_rounding_modes (which DO carry
-- a direct `grant select ... to authenticated` plus a bare `using (true)` policy,
-- confirmed by cluster 1 batch 1's own independent verify pass, making SECURITY
-- INVOKER mode actually work), `authenticated` today has NO path to read app.
-- permissions at all -- not through PostgREST (blocked by the schema-visibility
-- defect this whole Ø1 effort addresses), and not even through a hypothetical direct
-- table grant (there isn't one). A SECURITY INVOKER wrapper here would not "just work"
-- like the finance pair -- it would hit a real Postgres permission-denied error for
-- every authenticated caller, the exact same "invoker-mode-but-no-underlying-grant"
-- trap cluster 1 batch 1's own file header already disclosed as a live, different
-- defect on app.list_incident_communication_audiences (a different table, out of that
-- batch's scope; the same shape recurs here, in scope this time).
--
-- app.list_permissions_for_module below is therefore declared SECURITY DEFINER, not
-- SECURITY INVOKER -- a deliberate, independently-derived DEPARTURE from the finance-
-- reference-table precedent, for the concrete reason above, not a default reversion.
--
-- ADVERSARIAL-VERIFY REVISION (independent re-derivation, not a rubber stamp of the
-- first draft's own "zero actor parameter" call): app.permissions' lack of per-row,
-- identity-dependent VISIBILITY is real and confirmed -- no tenant_id/owner_user_id/
-- org-unit column exists, so once an actor is allowed to call this function at all,
-- every row is identical for every caller. But "no row-level variance" is a different
-- question from "who may call this function at all," and re-examined independently
-- against this specific fact: this is the FIRST time in this table's history that any
-- role other than service_role gains a read path to it, and a bare Supabase
-- `authenticated` JWT is not proof of any live standing in this platform. Direct read
-- of `app.revoke_auth_identity` (20260716095343_link_auth_identities.sql:142-174)
-- confirms it only flips `app.tenant_user_identities.status` to `'revoked'` -- it never
-- calls a Supabase auth-admin API to ban the underlying `auth.users` row or invalidate
-- an already-issued session token. A fully offboarded identity (revoked from every
-- tenant, or never onboarded into one at all) can therefore still hold a live,
-- `authenticated`-role session for the remainder of its natural token lifetime with
-- literally nothing else authorizing it. Since there is no existing production
-- behavior on this table to preserve (unlike app.roles below), the right question for
-- a first-ever exposure is not "what is the loosest grant that technically works" but
-- "what is the narrowest gate that costs the real use case nothing" -- and a trivial
-- one exists: `app.principal_memberships` (status = 'active') is this repository's own
-- existing, load-bearing definition of "does this identity currently hold ANY real
-- standing on this platform" -- it is exactly what `app.resolve_access_context`'s own
-- unscoped/global-request branch already keys off of
-- (20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:99-119, `count(*) from
-- app.principal_memberships where auth_user_id = ... and status = 'active'`), and it is
-- the same table `app.actor_holds_customer_user_layer`/`app.has_active_tenant_
-- membership`/`app.is_supreme_admin`/`app.has_active_support_grant` already query from
-- inside SECURITY DEFINER despite it, too, being granted to service_role only
-- (20260716100825_create_principal_memberships.sql) -- reusing this exact shape is not
-- a new authority primitive, it is the established one. The one disclosed real future
-- consumer of this function -- a tenant role/permission admin UI -- can only ever be
-- reached through a portal guard that already requires exactly this same "holds an
-- active membership somewhere" standing to render anything at all (the live
-- `lib/portal/tenant-admin-guard.ts` shipped by PLT-135, `docs/build-log/phase-01/
-- PLT-135.md` -- itself the checkpoint that deferred Roles/permissions-catalogue admin
-- UI to a still-later, not-yet-built slice; PLT-111's own build log names PLT-135, not
-- itself, as the deferred consumer, corrected here from the first draft's own
-- misattribution), so this gate costs that real use case nothing while closing a
-- concretely-identified gap for the population -- a valid-but-stale token with no
-- current standing anywhere -- that would otherwise be the very first principal type
-- ever allowed to read this catalogue.
--
-- app.list_permissions_for_module below therefore takes an explicit
-- `p_actor_auth_user_id` parameter, opens with the RULE A
-- `app.assert_actor_is_session_identity` guard (now load-bearing, since the parameter
-- itself now matters), and adds one constant-across-all-rows filter -- an active
-- `app.principal_memberships` row for that actor, in any tenant or as a global Supreme
-- Admin -- alongside the module-code filter. This still does not reintroduce per-row,
-- per-tenant filtering (the catalogue itself still has none), and it still returns zero
-- rows rather than raising for an actor with no current standing, matching every other
-- denied-access case this fragment documents. The narrow, filtered EXECUTE grant on
-- this specific function (to `authenticated` only, never a blanket table-level grant)
-- IS the deliberate authority boundary this fragment draws for the first time this
-- catalogue has ever been readable outside service_role -- a considered widening
-- (previously: unreachable by any session; now: readable, filtered by module code, to
-- any authenticated session that currently holds real standing somewhere on the
-- platform), not an accidental or maximally-open one. Content-wise, app.permissions
-- still carries no monetary, PII, or per-tenant data of any kind (19 fixed permission-
-- action names crossed with 9 fixed module codes, per 20260716103445's own header,
-- "reproduced from real, already-VERIFIED architecture evidence"; the specific 64-row
-- per-module seed and generated `code` strings are this migration's own data, not
-- independently re-published elsewhere, but carry no tenant-differentiating content --
-- every tenant sees the identical catalogue), so the module-code-filtered, standing-
-- gated read below carries no disclosure risk beyond what docs/architecture/
-- 06_RLS_RBAC_WORKSTREAM.md §5.1/§5.2 already establish as this catalogue's own public
-- design in this repository's own committed documentation.
--
-- ===========================================================================
-- RULE B (RLS predicate currency): app.roles' own CURRENT SELECT policy
-- ===========================================================================
-- Repo-wide grep for `create policy`/`alter policy` naming `app.roles`, AND for the
-- bare policy name `roles_select_own_tenant`, across every file in
-- supabase/migrations/*.sql, sorted by filename, finds exactly TWO hits:
--   * `create policy roles_select_own_tenant on app.roles for select to authenticated
--     using (app.has_active_tenant_membership(tenant_id));`
--     (20260716105512_create_rls_tenant_policies.sql:132-135, the original) -- this
--     same migration also issues `grant select on app.roles to authenticated;`
--     (line 131), the real table-level grant this precedent (unlike app.permissions
--     above) actually has.
--   * `alter policy roles_select_own_tenant on app.roles using
--     ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_
--     customer_user_layer(tenant_id)));`
--     (20260730560000_harden_customer_user_layer_default_deny.sql:307-308) -- the
--     customer_user-layer default-deny hardening pass layered onto 98 tenant-
--     membership-only policies repo-wide.
-- No later ALTER POLICY of `roles_select_own_tenant` exists anywhere in this
-- repository (that second hit is the newest by filename) -- 20260730560000's rewrite
-- is therefore the CURRENT predicate, reproduced verbatim below, NOT the narrower
-- original 20260716105512 wording (which lacked the customer_user-layer exclusion).
--
-- This finding deliberately does NOT assume the "beyond plain tenant membership"
-- possibility this task raised (a dedicated RBAC-admin permission action, or a
-- tenant_admin-layer check gating who may list a tenant's roles) -- that possibility
-- was checked, not found: the live predicate above is exactly `has_active_tenant_
-- membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)`, nothing
-- more. Role ADMINISTRATION (create/publish/assign, PLT-111's own app.create_role /
-- app.publish_role_version / app.assign_role functions) is service_role-only today --
-- there is no `authenticated`-reachable mutation path for roles at all yet, so there
-- is no narrower "who may configure roles" RBAC-admin gate this SELECT policy could
-- have deferred to even if the feature wanted one; the READ side (list a tenant's own
-- roles) is deliberately as broad as any other tenant-primary-table read this same
-- migration wired up in the same pass (app.org_units, app.tenant_entitlements, etc. --
-- see 20260716105512's own file header, "Tenant-scoped *primary* tables").
--
-- RULE C (precedent staleness) -- every helper cited above independently re-confirmed
-- against its MOST RECENT `create or replace function`, not its original creation:
--   * app.has_active_tenant_membership(uuid, uuid) -- repo-wide grep for `create or
--     replace function app.has_active_tenant_membership` / `create function app.
--     has_active_tenant_membership` finds THREE hits: 20260716105512 (original),
--     20260716111315_create_support_access.sql (adds the support-grant OR branch),
--     and 20260907110000_fix_suspended_user_retains_access_iss_d3b.sql:64 (CG-AUDIT-
--     2026-09-02 D3b, the newest by filename -- reproduced below). Its CURRENT body:
--     `exists(active app.tenant_user_identities row for (tenant_id, auth_user_id) with
--     NO corresponding suspended/revoked app.users row) OR app.is_supreme_admin(actor)
--     OR app.has_active_support_grant(tenant_id, actor)`. This means app.list_tenant_
--     roles below needs no SEPARATE is_supreme_admin() branch of its own -- a global
--     Supreme Admin already passes through has_active_tenant_membership's own third
--     disjunct, exactly the same "already ORed in" finding cluster 0 batch 2's own
--     close entry made for app.pipeline_categories/app.win_loss_reasons.
--   * app.actor_holds_customer_user_layer(uuid, uuid) -- repo-wide grep for `create or
--     replace function app.actor_holds_customer_user_layer` / `create function app.
--     actor_holds_customer_user_layer` finds exactly ONE hit, 20260730311000_harden_
--     customer_inventory_access_rls_isolation.sql:71 -- never replaced. Current (and
--     only-ever) body: `exists (active app.principal_memberships row for (tenant_id,
--     auth_user_id) with layer = 'customer_user')`.
--   * app.assert_actor_is_session_identity(uuid) -- repo-wide grep for `create or
--     replace function app.assert_actor_is_session_identity` / `create function app.
--     assert_actor_is_session_identity` finds exactly ONE hit,
--     20260730440000_harden_actor_identity_session_crosscheck.sql:59 -- never
--     replaced. A no-op whenever the session `auth.uid()` is null (service_role,
--     superuser, db-tests, or an already-nested SECURITY DEFINER call -- all trusted),
--     raising `actor_identity_mismatch` only when a genuine authenticated session's own
--     identity differs from the claimed `p_actor_auth_user_id`.
--
-- ===========================================================================
-- CONTRACT FIDELITY (the "return exactly what the TS contract consumes" discipline
-- cluster 0 batch 4's app.prospects fix established -- checked against the REAL
-- contract file, not assumed)
-- ===========================================================================
-- server/contracts/role-permission/role-permission.ts:
--   * parsePermission (lines 151-161) reads id, action, resource_module_code,
--     category, protected, code, created_at -- exactly app.permissions' own 7
--     physical columns (20260716103445:20-35), 1:1, nothing more and nothing less.
--     `returns setof app.permissions` below is therefore byte-for-byte equivalent to
--     the replaced `.from("permissions").select("*")`.
--   * parseRole (lines 164-176) reads id, tenant_id, name, description, status,
--     created_by, record_version, created_at, updated_at -- exactly app.roles' own 9
--     physical columns (20260716103445:79-91), 1:1. `returns setof app.roles` below
--     is likewise byte-for-byte equivalent to the replaced `.from("roles").select("*")`.
-- Neither function needs a RETURNS TABLE column exclusion -- both tables' entire
-- physical column sets are already exactly what their contract consumes.
--
-- ROW-NOT-FOUND / DENIED-ACCESS BEHAVIOR: both functions return zero rows -- never an
-- exception -- for a module code with no seeded permissions, an actor holding no
-- active app.principal_memberships row anywhere (app.list_permissions_for_module), a
-- nonexistent tenant_id, a cross-tenant one, or (for app.list_tenant_roles) an
-- in-tenant actor excluded by the customer_user-layer clause. This matches the
-- original RLS-filtered `.from()` reads' own silent-empty-result posture, and the
-- existing TS layer's own `data ?? []` handling (see TS INTEGRATION at the end of this
-- file).
--
-- No p_limit/pagination on either: the original `.from()` call sites applied none
-- either, and both are small, human-scale, per-request lists (one module's own
-- fixed permission subset; one tenant's own role count), not an unbounded feed --
-- matches every prior Ø1 batch's identical reasoning for this shape.
--
-- ===========================================================================
-- ISS-2026-309 grant-parity (docs/runtime/KNOWN_ISSUES.md, closed by
-- 20260830200000_correct_public_wrapper_grant_parity.sql)
-- ===========================================================================
-- A bare `revoke execute on function public.FN(...) from public` does NOT strip the
-- `anon`/`authenticated` EXECUTE grants Supabase's own ALTER DEFAULT PRIVILEGES rule
-- applies to every new function created in schema public. Both public.* wrappers
-- below therefore explicitly revoke from `anon, authenticated, service_role, public`
-- (all four) before re-granting exactly the same roles as their app.* counterpart --
-- `authenticated, service_role`, never `anon`.
--
-- ===========================================================================
-- check-rls-initplan.ts false-positive avoidance
-- ===========================================================================
-- Per this repository's own established practice (cluster 0 batches 3/5, cluster 1
-- batch 1): every `comment on function ... is '...'` string below avoids combining the
-- literal phrase "create policy"/"alter policy" with a bare, parenthesized
-- `auth.uid()`/`auth.jwt()` mention in the same string -- e.g. "no later rewrite of
-- this policy exists" instead of a literal "ALTER POLICY" callout, and `auth.uid`
-- written without a trailing call where it would otherwise sit near such a phrase.
-- The guard itself is never suppressed, only the prose reworded.

-- ===========================================================================
-- 1. app.list_permissions_for_module -- replaces server/queries/role-permission.ts:27
--    (listPermissionsForModule)
-- ===========================================================================
-- Replaces: `.from("permissions").select("*").eq("resource_module_code", moduleCode)`.
-- RULE A guard present and load-bearing -- see the file-header finding above (revised
-- during adversarial verification) for the full reasoning: app.permissions itself has
-- no per-row, per-actor visibility variance, but this is the first-ever grant of read
-- access to this table for any role but service_role, so a minimal "does this actor
-- hold any real standing on the platform at all" gate (an active app.principal_
-- memberships row, in any tenant or as a global Supreme Admin) is added -- a constant
-- filter across every row, not a per-row scope. SECURITY DEFINER because, unlike app.
-- finance_currencies/app.finance_rounding_modes, `authenticated` has no direct
-- table-level grant on app.permissions to fall back on in invoker mode.
create function app.list_permissions_for_module(
  p_resource_module_code text,
  p_actor_auth_user_id uuid
)
returns setof app.permissions
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select *
  from app.permissions
  where resource_module_code = p_resource_module_code
    and exists (
      select 1 from app.principal_memberships
      where auth_user_id = p_actor_auth_user_id and status = 'active'
    );
$$;

comment on function app.list_permissions_for_module(text, uuid) is
  'PLT-111/O1 remediation: the full canonical permission catalogue for one business-domain module code, replacing server/queries/role-permission.ts:27''s broken .from("permissions") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032) -- load-bearing here, not a formality: this is the first-ever grant of read access to app.permissions for any role but service_role (repo-wide grep confirms zero create-policy/later-rewrite ever named this table, and its only-ever grant before this fragment was service_role, 20260716103445:557-559; 20260716105512_create_rls_tenant_policies.sql explicitly deferred it, "no live UI consumes them yet," never revisited since). app.permissions itself carries no tenant_id/owner/org-unit column, so every row is identical for every caller once admitted -- but a bare authenticated session proves nothing about current standing (app.revoke_auth_identity only updates app.tenant_user_identities.status, it never bans the underlying auth.users row), so this function additionally requires an active app.principal_memberships row for the caller, the same "does this identity hold any real standing" primitive app.resolve_access_context''s own unscoped-request branch already relies on. Deliberately SECURITY DEFINER rather than SECURITY INVOKER: invoker mode would hit a genuine permission-denied error for every authenticated caller, since there is no direct table-level grant to fall back on. Deliberately not a disclosure risk beyond that standing gate: app.permissions holds only the 19 fixed permission-action names crossed with 9 fixed module codes docs/architecture/06_RLS_RBAC_WORKSTREAM.md section 5.1/5.2 already publish, no tenant or monetary data. Returns zero rows, never an exception, for a module code with no seeded permissions or for an actor holding no active principal membership anywhere -- matching the original read''s own silent-empty-result posture. Returns exactly the 7-column shape server/contracts/role-permission/role-permission.ts''s own parsePermission consumes (id, action, resource_module_code, category, protected, code, created_at) -- identical to the replaced select *.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_permissions_for_module with an identical grant set, never a
-- reimplementation.
create function public.list_permissions_for_module(
  p_resource_module_code text,
  p_actor_auth_user_id uuid
)
returns setof app.permissions
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_permissions_for_module(p_resource_module_code, p_actor_auth_user_id);
$wrap$;

comment on function public.list_permissions_for_module(text, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_permissions_for_module with an identical grant set, never a reimplementation.';

-- app.list_permissions_for_module: the first EXECUTE grant this catalogue has ever
-- had for a non-service_role principal -- narrow (this function's own filtered
-- projection, further gated by the caller's own active-standing check), never a
-- blanket table-level grant on app.permissions itself.
revoke execute on function app.list_permissions_for_module(text, uuid) from public;
grant execute on function app.list_permissions_for_module(text, uuid) to authenticated, service_role;

revoke execute on function public.list_permissions_for_module(text, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_permissions_for_module(text, uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_tenant_roles -- replaces server/queries/role-permission.ts:37
--    (listTenantRoles)
-- ===========================================================================
-- Replaces: `.from("roles").select("*").eq("tenant_id", tenantId)`. Row visibility
-- restates roles_select_own_tenant's own CURRENT (post-20260730560000) predicate --
-- see the RULE B finding above -- as an explicit WHERE filter (required because a
-- SECURITY DEFINER function never evaluates the invoker's own RLS): active tenant
-- membership for the requested tenant (which already folds in a global Supreme Admin
-- and an active support grant, per app.has_active_tenant_membership's own current
-- body -- see RULE C above), excluding an active customer_user-layer principal.
-- Unfiltered by status -- every role (active or archived) is returned, matching the
-- original `.from()` call's own lack of a status filter and this function's own
-- doc comment ("every role, any status").
create function app.list_tenant_roles(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.roles
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select *
  from app.roles
  where tenant_id = p_tenant_id
    and app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
    and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id);
$$;

comment on function app.list_tenant_roles(uuid, uuid) is
  'PLT-111/O1 remediation: every role (any status, including archived) a tenant has created, replacing server/queries/role-permission.ts:37''s broken .from("roles") read (the app schema is not exposed to PostgREST). Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (ATW-031/032). Row-visibility filter reproduces roles_select_own_tenant''s own current predicate verbatim, as most recently revised in migration 20260730560000 (not the narrower original 20260716105512 wording, which lacked the customer_user-layer exclusion): active tenant membership for the requested tenant, excluding an active customer_user-layer principal. No separate global-Supreme-Admin branch is needed here -- app.has_active_tenant_membership''s own current body already ORs a Supreme Admin identity in, the same "already folded in" finding cluster 0 batch 2 made for app.pipeline_categories/app.win_loss_reasons. Independently checked and NOT found: a dedicated RBAC-admin permission action or tenant_admin-layer gate beyond plain tenant membership -- role administration (create/publish/assign) has no authenticated-reachable mutation path at all today (service_role only), so this SELECT policy has no narrower "who may configure roles" authority to defer to. Returns zero rows, never an exception, for a nonexistent tenant_id, or an in-tenant actor excluded by the customer_user-layer clause -- matching the original RLS-filtered read''s own silent-empty-result posture (and the TS layer''s existing (data ?? []) handling, unchanged). Returns exactly the 9-column shape server/contracts/role-permission/role-permission.ts''s own parseRole consumes (id, tenant_id, name, description, status, created_by, record_version, created_at, updated_at) -- identical to the replaced select *.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.list_tenant_roles with an identical grant set, never a
-- reimplementation.
create function public.list_tenant_roles(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.roles
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_tenant_roles(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_tenant_roles(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_tenant_roles with an identical grant set, never a reimplementation.';

-- app.list_tenant_roles: same grant set as the base table it reads
-- (`grant select on app.roles to authenticated;`, 20260716105512:131 -- service_role
-- added here to match this series' own established convention of also granting the
-- backend/internal caller, since app.roles' own base-table grant predates that
-- convention and named only authenticated).
revoke execute on function app.list_tenant_roles(uuid, uuid) from public;
grant execute on function app.list_tenant_roles(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_tenant_roles(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_tenant_roles(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
--
-- File: server/queries/role-permission.ts (both functions live here).
--
-- 1. Type: `RolePermissionLookupClient` (currently lines 10-16) is a bespoke
--    `.from().select().eq()` shape, not `Pick<SupabaseClient, ...>` -- matching this
--    file's own existing convention (rather than switching styles), replace it with
--    an `.rpc()`-shaped interface covering both new RPCs:
--
--      export interface RolePermissionLookupClient {
--        rpc(
--          fn: "list_permissions_for_module",
--          args: { p_resource_module_code: string; p_actor_auth_user_id: string },
--        ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
--        rpc(
--          fn: "list_tenant_roles",
--          args: { p_tenant_id: string; p_actor_auth_user_id: string },
--        ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
--      }
--
-- 2. listPermissionsForModule (currently lines 26-33). Add a REQUIRED second parameter
--    `actorAuthUserId: string` (RULE A, added during adversarial verification --
--    app.list_permissions_for_module now takes and checks an explicit actor id, per
--    the revised file-header finding above). Replace the `.from(...)` chain (current
--    line 27) with:
--
--      export async function listPermissionsForModule(
--        client: RolePermissionLookupClient,
--        moduleCode: string,
--        actorAuthUserId: string,
--      ): Promise<Permission[]> {
--        const { data, error } = await client.rpc("list_permissions_for_module", {
--          p_resource_module_code: moduleCode,
--          p_actor_auth_user_id: actorAuthUserId,
--        });
--        if (error) {
--          throw new RolePermissionLookupError(error.message);
--        }
--        return (data ?? []).map((row) => parsePermission(row as Record<string, unknown>));
--      }
--
--    Row mapping and error handling are otherwise unchanged -- the RPC's RETURNS
--    TABLE column list matches the old `select *` 1:1.
--
-- 3. listTenantRoles (currently lines 36-43). Add a REQUIRED third parameter
--    `actorAuthUserId: string` (RULE A -- app.list_tenant_roles takes an explicit
--    actor id and this is the only way to supply it):
--
--      export async function listTenantRoles(
--        client: RolePermissionLookupClient,
--        tenantId: string,
--        actorAuthUserId: string,
--      ): Promise<Role[]> {
--        const { data, error } = await client.rpc("list_tenant_roles", {
--          p_tenant_id: tenantId,
--          p_actor_auth_user_id: actorAuthUserId,
--        });
--        if (error) {
--          throw new RolePermissionLookupError(error.message);
--        }
--        return (data ?? []).map((row) => parseRole(row as Record<string, unknown>));
--      }
--
-- 4. Call sites needing the new argument: NONE found. Repo-wide grep for
--    `listPermissionsForModule` / `listTenantRoles` across app/**/*.tsx and server/**/
--    *.ts (excluding this file and its own test) finds zero hits -- no live page.tsx
--    caller exists for either function today (see file header; independently
--    confirmed against docs/build-log/phase-01/PLT-111.md, "no live route exists yet,"
--    and PLT-135.md, which built the Tenant Admin portal shell but explicitly deferred
--    Roles/permissions-catalogue admin UI to a still-later slice). No production call
--    site to update -- but note both TS function signatures below are still a real,
--    disclosed breaking API change (a new required parameter each), not merely
--    additive, since server/queries/role-permission.test.ts (the only existing caller)
--    will fail to compile against the new signatures until updated per item 5.
--
-- 5. server/queries/role-permission.test.ts mocks a `.from()`-based `fakeClient`
--    today (lines 29-43) and will need updating to an `.rpc()`-based fake returning
--    `{ data: [PERMISSION_ROW] | [ROLE_ROW], error: null }` (an array, per RETURNS
--    TABLE/setof), asserting the call was made with fn `"list_permissions_for_module"`
--    / `"list_tenant_roles"` and the right `p_*` args, and passing a second
--    `actorAuthUserId` argument to every `listPermissionsForModule(...)` call
--    (currently lines 48 and 55) and a third `actorAuthUserId` argument to every
--    `listTenantRoles(...)` call (currently lines 62 and 69) in that file -- not
--    attempting this rewrite here, per this task's SQL-only scope.
