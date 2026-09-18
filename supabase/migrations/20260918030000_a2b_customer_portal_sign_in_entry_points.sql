-- CG-AUDIT-2026-09-02 A2b (bounded core): "Customer portal has no sign-in
-- route; no vendor principal layer exists at all" -- carried as one
-- undivided DEFERRED_LARGE item ("vendor layer is a schema-level product
-- decision") and never itself independently re-verified since.
--
-- A dedicated research pass, the same "verify before trusting a deferred
-- label" discipline that found B7's/B2a's/E6's/B4's own real bounded cores,
-- found this finding bundles two genuinely different situations:
--
--   * The vendor principal layer half is a real, still-open, DELIBERATELY
--     ratified PRODUCT decision, not an oversight -- docs/build-log/
--     phase-06/PRC-267.md ("Optional Vendor Portal") is explicitly BLOCKED
--     pending a Platform-level external-identity ADR that was never
--     ratified (docs/adr/ADR-0022), and docs/adr/ADR-0025 Part A instead
--     ratifies vendor/customer API keys (app.api_keys, data-scoped, never
--     actor-scoped, staff-issued only) as the deliberate substitute --
--     confirmed by 20260804030000_create_intelligence_vendor_api.sql's own
--     header ("No fifth principal layer... no login/session concept at
--     all"). This migration does not touch that boundary. DEFERRED_LARGE
--     stays accurate for the vendor half.
--
--   * The customer-portal-sign-in half is stale, not accurate. The
--     `customer_user` principal layer (ADR-0024) is real, extensive, and
--     already load-bearing -- ~90 migrations, dozens of server/contracts|
--     mutations|queries/customer-portal-* files, real sign-in via app/
--     (public)/login/actions.ts (supabase.auth.signInWithPassword, the same
--     shared entry point every layer uses). What is genuinely still missing
--     is narrow and mechanical, not a product/schema decision: CPL-300
--     (20260801010000_create_customer_portal_account_scope.sql) shipped
--     app.grant_initial_customer_portal_account_admin (the tenant-admin-only
--     bootstrap seeding the first account_admin on a brand-new account) and
--     app.accept_customer_portal_invite (an invited identity accepting a
--     subsequent app.invite_customer_portal_user invite) with real, tested
--     RPCs and typed server/mutations/customer-portal-scope.ts wrappers --
--     but that migration's own §9 deliberately chartered "the full Customer
--     User Management UI" to a later prompt, and CPL-315
--     (customer-portal-users/) built the self-service invite/role/status/
--     access-review UI for an ALREADY-active account_admin, never a caller
--     for either of these two RPCs. Confirmed by a repo-wide grep: zero
--     non-test/non-contract call sites for either function anywhere in
--     app/, server/, or lib/ before this migration.
--
-- One further, deeper gap the research surfaced, not previously disclosed
-- anywhere in this backlog: there was no way for an invited-but-not-yet-
-- accepted identity to ever DISCOVER their own pending membership id/
-- version to accept it. app.get_customer_portal_scope_context and app.
-- resolve_customer_account_scope both intentionally scope to ACTIVE
-- memberships only (the customer_user-layer principal marker is granted at
-- ACCEPT time, not invite time, per this same migration's own Tier C
-- review fix comment on app.accept_customer_portal_invite), and app.list_
-- customer_portal_account_memberships is account_admin-only -- an invited-
-- but-not-active member cannot call it, since they do not hold that role
-- yet by definition. lib/portal/customer-portal-guard.ts's own "forbidden"
-- branch (actor_holds_customer_user_layer = false) is exactly the state an
-- invited identity is stuck in today: app/(tenant)/[tenantSlug]/customer-
-- portal/page.tsx renders a generic denied message with no path forward.
--
-- Fix, entirely additive, no existing RPC body touched: one new RPC, app.
-- list_my_pending_customer_portal_invites -- the one deliberate exception
-- to "only an active customer_user may read its own scope" (mirrors app.
-- grant_initial_customer_portal_account_admin's own documented exception to
-- "Layer-4-only, never staff RBAC"), self-identity-checked only (app.
-- assert_actor_is_session_identity), returning every still-`invited` row
-- for the caller's own identity in this tenant. No authority/layer check
-- beyond that: the result is scoped to the caller's own auth_user_id, so a
-- caller with zero genuine pending invites simply gets an empty array,
-- exactly like every other self-scoped "list my own X" RPC in this
-- repository -- no new disclosure. RGL-394 Option-2 public.* wrapper
-- included, identical grant set (authenticated, service_role).
--
-- The TS/UI blast radius: server/contracts/customer-portal-scope/customer-
-- portal-scope.ts (CustomerPortalPendingInviteSchema), server/queries/
-- customer-portal-scope.ts (listMyPendingCustomerPortalInvites) --
-- customer-portal/page.tsx's own forbidden branch now checks for a pending
-- invite and renders an "Accept invite" form (a new accept-invite-
-- actions.ts Server Action composing the already-existing, already-tested
-- acceptCustomerPortalInvite mutation wrapper) instead of the generic
-- denied message when one exists; commercial/accounts/[accountId]/page.tsx
-- (the natural staff-facing home for account-scoped actions, already
-- carrying CreditPanel) gains a "Customer portal access" panel wired to the
-- already-existing grantInitialCustomerPortalAccountAdmin mutation wrapper
-- via a new customer-portal-actions.ts Server Action, gated purely by the
-- RPC's own CPT:Create check (the seeded-since-CPL-300, never-until-now-
-- used-from-any-UI action code) -- no new client-side authority re-
-- derivation.
--
-- Deliberately out of this bounded core's own scope, left exactly as the
-- research found it: (1) the vendor principal layer, a ratified PRODUCT
-- deferral, not touched; (2) app/(tenant)/[tenantSlug]/page.tsx's own post-
-- login landing behavior for a customer_user identity (today it resolves
-- "forbidden" via the staff-only app.resolve_access_context and shows a
-- generic denied page rather than redirecting to /customer-portal) -- a
-- real but separate UX-discoverability gap entangled with app.resolve_
-- access_context's own tenant_user_identities-status semantics (a shared,
-- 15+-consumer, load-bearing guard function), not a quick, safely-bounded
-- addition alongside this fix; a customer_user who already knows the
-- /{tenantSlug}/customer-portal URL (from an invite email, an account
-- admin, or this fix's own bootstrap/accept flow) is unaffected.

-- ===========================================================================
-- app.list_my_pending_customer_portal_invites -- self-scoped, the one
-- deliberate pre-layer-grant exception
-- ===========================================================================

create function app.list_my_pending_customer_portal_invites(p_auth_user_id uuid, p_tenant_id uuid)
returns table (
  membership_id uuid,
  account_id uuid,
  account_name text,
  role text,
  record_version integer,
  invited_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- Same free-parameter authority boundary every other self-scoped CPL-300
  -- RPC carries (app.get_customer_portal_scope_context/app.resolve_
  -- customer_account_scope's own Tier C review fix) -- without this, any
  -- authenticated session could pass another identity's uuid and read that
  -- identity's own pending invites.
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  return query
  select cpam.id, cpam.account_id, a.legal_name, cpam.role, cpam.record_version, cpam.invited_at
  from app.customer_portal_account_memberships cpam
  join app.accounts a on a.id = cpam.account_id and a.tenant_id = p_tenant_id
  where cpam.tenant_id = p_tenant_id
    and cpam.auth_user_id = p_auth_user_id
    and cpam.status = 'invited'
  order by cpam.invited_at desc nulls last, cpam.id desc;
end;
$$;

comment on function app.list_my_pending_customer_portal_invites is
  'CG-AUDIT-2026-09-02 A2b: the one deliberate exception to "an invited-but-not-yet-accepted identity holds no customer_user-layer principal and is never in scope" (app.get_customer_portal_scope_context/app.resolve_customer_account_scope both intentionally exclude a status=invited row) -- self-identity-checked only via app.assert_actor_is_session_identity, no layer/authority check beyond that, since the result is already scoped to the caller''s own auth_user_id. Every still-invited app.customer_portal_account_memberships row for this identity in this tenant, joined to the account''s own legal_name for display. A caller with zero genuine pending invites gets an empty array, never an error, mirroring every other self-scoped "list my own X" RPC in this repository.';

revoke execute on function app.list_my_pending_customer_portal_invites(uuid, uuid) from public;
grant execute on function app.list_my_pending_customer_portal_invites(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- RGL-394 Option-2 public.* wrapper
-- ===========================================================================

create function public.list_my_pending_customer_portal_invites(p_auth_user_id uuid, p_tenant_id uuid)
returns table (
  membership_id uuid,
  account_id uuid,
  account_name text,
  role text,
  record_version integer,
  invited_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_my_pending_customer_portal_invites(p_auth_user_id, p_tenant_id);
$wrap$;

comment on function public.list_my_pending_customer_portal_invites(p_auth_user_id uuid, p_tenant_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_my_pending_customer_portal_invites with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- ERR-2026-004: a fresh CREATE FUNCTION in schema public silently inherits the
-- platform-level "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
-- GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role" rule --
-- revoking from public alone does not undo the anon/authenticated/service_role
-- portion of that default. Explicit, directly-provable revoke of all four
-- before the real, narrower re-grant below (mirrors 20260918020000_b4_ar_ap_
-- exposure_currency_fix.sql's own identical fix for the same gotcha).
revoke execute on function public.list_my_pending_customer_portal_invites(p_auth_user_id uuid, p_tenant_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_my_pending_customer_portal_invites(p_auth_user_id uuid, p_tenant_id uuid) to service_role;
grant execute on function public.list_my_pending_customer_portal_invites(p_auth_user_id uuid, p_tenant_id uuid) to authenticated;
