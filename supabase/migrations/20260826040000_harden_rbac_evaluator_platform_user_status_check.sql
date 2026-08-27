-- ISS-2026-072 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- the OPEN half of a two-part finding. HRT-295 already fixed the role_assignments-
-- cascade half (a status transition through app.transition_user_status correctly strips
-- active role_assignments). HDN-373 (20260810300000) already closed the tenant-membership
-- half (app.evaluate_permission now requires app.has_active_tenant_membership before any
-- role-grant path). What remained explicitly OPEN, per this entry's own text: app.
-- evaluate_permission never independently re-checks app.users.status as defense in
-- depth -- so a role_assignments row that survives an app.users.status flip made
-- OUTSIDE app.transition_user_status (a direct UPDATE, or any future caller that doesn't
-- go through the one governed transition path) would still grant authority.
--
-- This is a real, live-forceable gap distinct from both prior fixes: app.transition_
-- user_status's own role_assignments cascade only fires when THAT function is the one
-- flipping status. Nothing in this schema prevents (or has ever prevented) a direct
-- `update app.users set status = ...` -- and evaluate_permission's own body never reads
-- app.users at all today, confirmed by grep across all 3 historical definitions
-- (20260716104519_create_rbac_evaluator.sql, 20260730440000_harden_actor_identity_
-- session_crosscheck.sql, 20260810300000_harden_rbac_evaluator_tenant_membership_check.sql
-- -- none queries app.users).
--
-- Fix, additive-only body change on the identical existing signature (the same technique
-- 20260810300000 itself used successfully for the tenant-membership half): one new
-- `if not exists (...) then return ... end if` branch, requiring the acting app.users row
-- to be status = 'active'.
--
-- Placement (the one real design decision here, everything else is mechanical):
-- deliberately placed AFTER the Supreme Admin branch, not before it (unlike the
-- tenant-membership check, which is safe to place before Supreme Admin only because
-- has_active_tenant_membership's OWN body already special-cases Supreme Admin as a
-- passing condition). app.users is tenant-scoped (unique on (tenant_id, auth_user_id),
-- supabase/migrations/20260716102620_create_users.sql:37) and a Supreme Admin, by
-- design, can act across tenants without necessarily holding an app.users row in every
-- tenant they touch (their authority comes from app.principal_memberships, layer=
-- 'supreme_admin', entirely independent of app.users). Placing this new check before the
-- Supreme Admin branch would incorrectly deny a genuine Supreme Admin acting in a tenant
-- where they simply have no app.users row at all -- a real regression, not a hypothetical
-- one, live-verified against in this migration's own regression test below (see
-- scripts/db-tests/rbac-enforcement.sql's new "Supreme Admin unaffected" assertion).
--
-- A distinct, new reason string (`not_active_platform_user`) is used rather than reusing
-- `not_active_tenant_member`, so callers/audit logs/tests can distinguish "never a tenant
-- member at all" from "was a member, and still has an active role_assignments row, but
-- their app.users account itself is suspended/revoked" -- mirroring how `no_granting_role`
-- and `no_active_assignment` are already kept distinct today for the analogous reason.
--
-- Deliberately NOT attempted in this same migration: app.user_sessions.status
-- (ISS-2026-264/RGL-BLK-010's own underlying gap). That is an architecturally larger
-- change -- evaluate_permission's signature carries no session identifier at all, and
-- wiring one through the JWT/RLS/RPC layer is a real design task, not a body-only edit.
-- RGL-BLK-010 already re-ruled this a non-blocking, folded-into-the-"tenant zero"-group
-- hardening item (docs/build-log/release-go-live/BLOCKER_LEDGER.md) for exactly this
-- reason; this migration does not reopen or reverse that ruling.
--
-- No call-site changes required anywhere: this is a body-only change to a single-
-- signature, single-definition function (confirmed: grep across every migration for
-- `FUNCTION app.evaluate_permission(` finds exactly one signature, never overloaded).
-- Every one of its callers is syntactically untouched.
--
-- Lockout-safety analysis (why this cannot newly false-deny a legitimate actor):
-- app.users.status/app.tenant_user_identities.status/app.user_sessions.status are all
-- `not null default ...` since their own CREATE TABLE (this is a from-scratch build, no
-- legacy backfill gap). More specifically, app.assign_role
-- (20260716103445_create_roles_permissions.sql:480-483) already hard-requires
-- `app.users.status = 'active'` at grant time before it will create a role_assignments
-- row at all -- so no actor can reach the role_grant branch below while their app.users
-- row is not 'active' AT THE MOMENT OF GRANT. The only way status and an active
-- role_assignments row can diverge today is exactly the out-of-band-status-change drift
-- this fix is closing. A direct app.users.status='active' re-check therefore only ever
-- denies actors who genuinely should be denied under this schema's own pre-existing
-- invariant.

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

  -- ISS-2026-072 (this migration): defense-in-depth re-check of app.users.status,
  -- independent of whatever cascaded (or failed to cascade) into role_assignments. Placed
  -- here, after the Supreme Admin exception (see this migration's own header for why) and
  -- before any role_assignments lookup. app.users is tenant-scoped -- an actor with no
  -- app.users row at all in this tenant already failed has_active_tenant_membership above
  -- (unless they are Supreme Admin, already exempted by the branch above this one), so
  -- `not exists` here correctly reaches only a genuine member whose own account status is
  -- not 'active'.
  if not exists (
    select 1 from app.users
    where tenant_id = p_tenant_id
      and auth_user_id = p_auth_user_id
      and status = 'active'
  ) then
    return row(false, 'not_active_platform_user', v_permission.id, null, null, p_as_of)::app.rbac_decision;
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
