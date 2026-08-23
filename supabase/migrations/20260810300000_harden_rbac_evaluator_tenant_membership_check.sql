-- HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, `CG-S15-HDN-005`) — the headline
-- finding, at the root.
--
-- `app.evaluate_permission` is the single RBAC authority gate roughly 1,124 functions in
-- this schema call (transitively, through `app.assert_actor_is_session_identity`'s own
-- caller graph plus every direct caller). Its body checks `app.role_assignments.status =
-- 'active'` joined to a published `app.role_versions` row — but **never** checks whether
-- the claimed actor is still a genuine, active member of `p_tenant_id` at all.
--
-- `app.tenant_user_identities` (the actual tenant-membership linkage `app.
-- has_active_tenant_membership` reads, PLT-107/PLT-113) and `app.role_assignments` (what
-- `evaluate_permission` reads) are two SEPARATE tables with no FK/trigger cascade between
-- them: `app.revoke_auth_identity` (the sole tenant-membership-revocation RPC) touches
-- only `tenant_user_identities`. It never cascades to `role_assignments`, and nothing
-- else does either. A revoked ex-member therefore retains every role-based permission
-- they held at the moment of revocation — both read AND write — indefinitely, until
-- someone SEPARATELY and manually revokes their `role_assignments` rows too, a step
-- nothing in this codebase automates, enforces, or even surfaces as a required follow-up.
--
-- **Live-forced and confirmed** (Tier C investigation lens, `docs/build-log/full-system-
-- hardening/HDN-373.md` §6): a genuinely revoked ex-member of a tenant (`app.
-- has_active_tenant_membership` confirmed `false` in the same session), acting as
-- themselves (no forged actor — this is not an `ATW-031`-shaped identity-forgery defect,
-- it is a revocation-propagation gap), successfully called both a read RPC
-- (`app.get_procurement_dashboard_saved_view`) and, code-confirmed, a write RPC
-- (`app.create_procurement_dashboard_saved_view`) gated by `evaluate_permission`, with
-- `evaluate_permission` itself returning `allowed=true, reason='role_grant'` for a role
-- assignment the revocation never touched.
--
-- **Fix, mirroring `ATW-031`'s own one-root pattern**: `app.evaluate_permission` now
-- requires `app.has_active_tenant_membership(p_tenant_id, p_auth_user_id)` before it will
-- ever return `allowed=true` via the ordinary role-grant path, denying with a new,
-- explicit reason (`not_active_tenant_member`) otherwise. `has_active_tenant_membership`
-- is the exact same predicate essentially every tenant-scoped RLS policy in this schema
-- already uses, and it already correctly composes three legitimate ways to be a genuine
-- member: an active `tenant_user_identities` row, Supreme Admin (`app.is_supreme_admin`,
-- itself independent of `p_tenant_id` — RPD-022's disclosed cross-tenant residual risk is
-- therefore entirely unaffected by this fix, since a Supreme Admin always satisfies this
-- check regardless of which tenant is asked about), or a live support-access grant into
-- that tenant (`app.has_active_support_grant`). Placed before the Supreme Admin branch
-- (harmless — Supreme Admin always passes it) and before the role-assignment lookup
-- (the actual fix), so every existing legitimate caller — who, per `ATW-031`'s own
-- repository-wide sweep, always evaluates their own genuine actor as a member of their
-- own tenant — is unaffected; only the specific revoked-but-role-assignment-not-cleaned-
-- up case newly denies.
--
-- Full disposition, live re-verification transcript and the broader investigation this
-- fix responds to: `docs/build-log/full-system-hardening/HDN-373.md` §6.
--
-- **Self-caught regression, fixed in the same migration rather than left for a later
-- session to trip over**: `app.evaluate_permission` is itself `SECURITY INVOKER`,
-- granted only to `service_role` (a genuine, real direct-call path -- not merely a
-- theoretical one, since the whole reason it carries its own explicit grant rather than
-- relying on nested-definer-call privilege is that something calls it directly as
-- `service_role`, not only from inside another `SECURITY DEFINER` wrapper). The new
-- `app.has_active_tenant_membership` call this fix adds is itself `SECURITY DEFINER`,
-- but Postgres checks `EXECUTE` privilege at the call site BEFORE the security context
-- switches to the callee's owner -- so a direct `service_role` caller of `evaluate_
-- permission` would have failed with `permission denied for function has_active_tenant_
-- membership`, since that function was, until now, granted only to `authenticated`, not
-- `service_role`. Live-confirmed broken (`begin; set local role service_role; select
-- app.evaluate_permission(...); rollback;` → exactly that error) before this migration's
-- own trailing grants were finalized, and confirmed fixed by the same test afterward.
-- This is the identical class of gap this checkpoint's own investigation separately found
-- at much larger scale across the Finance domain (`HDN-373.md` §6, `HDN-BLK-015`/
-- `ISS-2026-18x`) -- caught here, in this one function, before it ever reached a commit.

create or replace function app.evaluate_permission(p_auth_user_id uuid, p_tenant_id uuid, p_resource_module_code text, p_action text, p_as_of timestamp with time zone default now())
returns app.rbac_decision
language plpgsql
stable
as $function$
declare
  v_permission app.permissions;
  v_match record;
begin
  perform app.assert_actor_is_session_identity(p_auth_user_id);
  select * into v_permission
  from app.permissions
  where resource_module_code = p_resource_module_code and action = p_action;

  if not found then
    return row(false, 'unknown_permission', null, null, null, p_as_of)::app.rbac_decision;
  end if;

  -- HDN-373: a role_assignments row surviving tenant-membership revocation must not
  -- grant authority. app.has_active_tenant_membership already correctly composes
  -- Supreme Admin (tenant-agnostic, RPD-022) and a live support-access grant, so neither
  -- is affected by this check -- only a genuinely non-member (including a revoked
  -- ex-member) is newly denied here, before any role_assignments row is even consulted.
  if not app.has_active_tenant_membership(p_tenant_id, p_auth_user_id) then
    return row(false, 'not_active_tenant_member', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  if exists (
    select 1 from app.principal_memberships
    where auth_user_id = p_auth_user_id and layer = 'supreme_admin' and status = 'active'
  ) then
    return row(true, 'supreme_admin_exception', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  -- The join to role_versions on status = 'published' is what makes a stale assignment
  -- (still 'active' in app.role_assignments, but pointing at a version PLT-111's
  -- publish_role_version() has since archived by superseding it) fail closed -- exactly
  -- Prompt 112 §23's "stale ... permission fails closed." No auto-reassignment to the new
  -- published version happens anywhere in this repository; that is a disclosed, bounded
  -- limitation of this checkpoint, not an oversight (see PLT-112.md §2/§8).
  select ra.id as assignment_id, rv.id as role_version_id, rv.role_id
  into v_match
  from app.role_assignments ra
  join app.role_versions rv on rv.id = ra.role_version_id
  join app.role_version_permissions rvp on rvp.role_version_id = rv.id
  where ra.tenant_id = p_tenant_id
    and ra.auth_user_id = p_auth_user_id
    and ra.status = 'active'
    and rv.status = 'published'
    and rvp.permission_id = v_permission.id
  limit 1;

  if found then
    return row(true, 'role_grant', v_permission.id, v_match.role_id, v_match.role_version_id, p_as_of)::app.rbac_decision;
  end if;

  if exists (
    select 1 from app.role_assignments
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active'
  ) then
    return row(false, 'no_granting_role', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  return row(false, 'no_active_assignment', v_permission.id, null, null, p_as_of)::app.rbac_decision;
end;
$function$;

revoke execute on all functions in schema app from public;

grant execute on function app.evaluate_permission(uuid,uuid,text,text,timestamp with time zone) to service_role;

-- Self-caught regression fix (see this migration's own header): app.evaluate_permission
-- is SECURITY INVOKER and granted only to service_role; the new app.has_active_tenant_
-- membership call this migration adds needs its own EXECUTE grant reachable by that same
-- role, exactly like ATW-031's own original comment already explained for app.assert_
-- actor_is_session_identity. Additive only -- the function's existing `authenticated`
-- grant (used pervasively by RLS policies) is untouched.
grant execute on function app.has_active_tenant_membership(uuid, uuid) to service_role;
