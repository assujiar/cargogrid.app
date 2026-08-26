-- ISS-2026-264 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- app.revoke_all_actor_sessions's own session-status flip in app.user_sessions was
-- never consulted by any RLS policy, RPC, or app.evaluate_permission -- pure bookkeeping
-- with zero enforcement effect. docs/runbooks/incident-response.md frames session
-- revocation as stopping "future RPC calls that check session status," but nothing ever
-- did. Live-reproduced at HDN-384's own security-incident drill: revoking only sessions
-- left a still-valid identity with full functional access, since the underlying role
-- assignment/tenant membership remained intact.
--
-- Root cause investigated further during this fix: app.register_user_session (the ONLY
-- function that ever creates an app.user_sessions row) was never called from anywhere in
-- this application either -- not the real sign-in path
-- (app/(public)/login/actions.ts), not any other route. A pure "wire evaluate_permission
-- to check session status" fix, on its own, would be a structural no-op in production:
-- since zero session rows would ever exist for any real login, the new check below could
-- never fire. This is why this checkpoint's own fix has two parts, applied together:
-- (1) this migration -- the real enforcement check; (2) a companion application-code
-- change (lib/auth/register-login-session.ts, wired into the sign-in Server Action) that
-- makes app.register_user_session actually get called on every tenant-scoped sign-in
-- going forward, so app.user_sessions rows -- and therefore this new check -- become
-- real for actual users, not merely theoretically wired.
--
-- The check itself is deliberately narrow: it denies ONLY when an actor has AT LEAST ONE
-- tracked app.user_sessions row for this tenant AND every one of them is currently
-- 'revoked'. An actor who has never had a session registered at all (any login that
-- predates this fix, or any future login path that never calls register_user_session)
-- is completely unaffected -- this check can only ever narrow authority for an identity
-- session-revocation was actually exercised against, never deny anyone universally.
-- Placed after the Supreme Admin exception (app.user_sessions.tenant_id is NOT NULL, so
-- a tenant-independent Supreme Admin grant is structurally exempt regardless) and
-- alongside ISS-2026-072's own not_active_platform_user check, before any
-- role_assignments lookup.
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

  -- ISS-2026-072: defense-in-depth re-check of app.users.status,
  -- independent of whatever cascaded (or failed to cascade) into role_assignments. Placed
  -- here, after the Supreme Admin exception (see that migration's own header for why) and
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

  -- ISS-2026-264 (this migration): see this migration's own header for the full
  -- rationale and why it is deliberately narrow (never universally denies an
  -- untracked actor).
  if exists (
    select 1 from app.user_sessions
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id
  ) and not exists (
    select 1 from app.user_sessions
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active'
  ) then
    return row(false, 'all_sessions_revoked', v_permission.id, null, null, p_as_of)::app.rbac_decision;
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
