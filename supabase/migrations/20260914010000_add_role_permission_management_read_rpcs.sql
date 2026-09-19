-- Audit remediation A2 (docs/audit/2026-09-02-independent-launch-readiness-audit.md,
-- docs/build-log/remediation/CG-AUDIT-2026-09-02-REMEDIATION-BACKLOG.md): "no role can
-- be created or assigned to a user through any UI." PLT-111's mutation RPCs
-- (app.create_role / app.create_role_version / app.set_role_version_permissions /
-- app.publish_role_version / app.assign_role / ...) already existed as real, tested,
-- service_role-only backend capability with zero callers -- server/queries/role-
-- permission.ts already exposes list_permissions_for_module/list_tenant_roles
-- (O1 remediation cluster 2), but nothing exposes a role's OWN versions, a version's
-- OWN permission set, or who currently holds a role -- without those, a UI could
-- create data it could never see or act on again after a page reload. This migration
-- adds exactly those three missing read paths, the minimum needed for a real (not
-- write-only) role management screen.
--
-- app.role_versions and app.role_assignments both already carry a live RLS policy and
-- an `authenticated` table grant (20260716105512_create_rls_tenant_policies.sql,
-- most recently altered by 20260730560000_harden_customer_user_layer_default_deny.sql
-- -- verified as the current, not original, predicate before writing this migration):
--   role_versions_select_own_tenant: exists (select 1 from app.roles r where r.id =
--     role_versions.role_id and app.has_active_tenant_membership(r.tenant_id) and not
--     app.actor_holds_customer_user_layer(r.tenant_id))
--   role_assignments_select_own_tenant: app.has_active_tenant_membership(tenant_id) and
--     not app.actor_holds_customer_user_layer(tenant_id)
-- so app.list_role_versions/app.list_role_assignments_for_role are SECURITY INVOKER with
-- no actor parameter at all -- the live policy already does the filtering via its own
-- auth.uid() default, the same choice this series already made for
-- app.list_org_units/app.get_job_offer_for_application/app.get_approval_request_by_id
-- (cluster 7): simpler than SECURITY DEFINER and correct as long as it stays in sync
-- with a policy this function does not itself reproduce -- which is exactly the point
-- of using invoker mode instead of copying the predicate.
--
-- app.role_version_permissions is a different case: `alter table ... enable row level
-- security` was run (20260716103445:553) but NO policy and NO `authenticated` grant
-- were ever added for it (repo-wide grep confirms zero `create policy ... on app.
-- role_version_permissions` and zero `grant select on app.role_version_permissions`)
-- -- RLS-enabled-with-no-policy is default-deny for every role but the table owner, so
-- SECURITY INVOKER would return zero rows for every real caller regardless of
-- authority. app.list_role_version_permissions is therefore SECURITY DEFINER, RULE A
-- guard present (app.assert_actor_is_session_identity) and the authority predicate
-- manually reproduces role_versions_select_own_tenant's own current predicate above
-- (the same shape app.list_permissions_for_module already established for the sibling
-- ungranted table app.permissions).

-- ===========================================================================
-- 1. app.list_role_versions
-- ===========================================================================
create function app.list_role_versions(
  p_role_id uuid
)
returns setof app.role_versions
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.role_versions where role_id = p_role_id order by version_number desc;
$$;

comment on function app.list_role_versions(uuid) is
  'Audit remediation A2: every version (draft/published/archived) of one role, ordered newest first. SECURITY INVOKER -- app.role_versions already carries a live RLS policy (role_versions_select_own_tenant) and an authenticated table grant, so this function takes no actor parameter and relies entirely on the caller''s own session (auth.uid()) via that policy, never reproducing its predicate here. Returns zero rows, never an exception, for a role_id the caller cannot see or that does not exist.';

create function public.list_role_versions(
  p_role_id uuid
)
returns setof app.role_versions
language sql
stable
security invoker
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_role_versions(p_role_id);
$wrap$;

comment on function public.list_role_versions(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin invoker pass-through to app.list_role_versions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_role_versions(uuid) from public;
grant execute on function app.list_role_versions(uuid) to authenticated, service_role;

revoke execute on function public.list_role_versions(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_role_versions(uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_role_assignments_for_role
-- ===========================================================================
create function app.list_role_assignments_for_role(
  p_role_id uuid
)
returns setof app.role_assignments
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select ra.*
  from app.role_assignments ra
  join app.role_versions rv on rv.id = ra.role_version_id
  where rv.role_id = p_role_id
  order by ra.granted_at desc;
$$;

comment on function app.list_role_assignments_for_role(uuid) is
  'Audit remediation A2: every assignment (active or revoked) of any version of one role, newest grant first. SECURITY INVOKER -- app.role_assignments already carries a live RLS policy (role_assignments_select_own_tenant, filtering by tenant_id) and an authenticated table grant; app.role_versions'' own RLS applies identically to the join. No actor parameter -- the caller''s own session gates both tables via their live policies, never reproduced here. Returns zero rows, never an exception, for a role_id the caller cannot see or with no assignments yet.';

create function public.list_role_assignments_for_role(
  p_role_id uuid
)
returns setof app.role_assignments
language sql
stable
security invoker
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_role_assignments_for_role(p_role_id);
$wrap$;

comment on function public.list_role_assignments_for_role(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin invoker pass-through to app.list_role_assignments_for_role with an identical grant set, never a reimplementation.';

revoke execute on function app.list_role_assignments_for_role(uuid) from public;
grant execute on function app.list_role_assignments_for_role(uuid) to authenticated, service_role;

revoke execute on function public.list_role_assignments_for_role(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_role_assignments_for_role(uuid) to authenticated, service_role;

-- ===========================================================================
-- 3. app.list_role_version_permissions
-- ===========================================================================
create function app.list_role_version_permissions(
  p_role_version_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.permissions
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select p.*
  from app.role_version_permissions rvp
  join app.permissions p on p.id = rvp.permission_id
  where rvp.role_version_id = p_role_version_id
    and exists (
      select 1 from app.role_versions rv
      join app.roles r on r.id = rv.role_id
      where rv.id = p_role_version_id
        and app.has_active_tenant_membership(r.tenant_id, p_actor_auth_user_id)
        and not app.actor_holds_customer_user_layer(r.tenant_id, p_actor_auth_user_id)
    );
$$;

comment on function app.list_role_version_permissions(uuid, uuid) is
  'Audit remediation A2: the permission set currently bound to one role version. SECURITY DEFINER -- app.role_version_permissions has row level security enabled (20260716103445) but was never given a policy or an authenticated grant (repo-wide grep confirms zero matches for either), so it is default-deny for every role but the table owner regardless of caller; SECURITY INVOKER would return zero rows for every real caller. Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A). Authority predicate manually reproduces role_versions_select_own_tenant''s own current predicate (verified against its most recent alter policy, 20260730560000, not its original 20260716105512 wording) rather than deferring to RLS, since a SECURITY DEFINER function never evaluates the invoker''s own policies. Returns zero rows, never an exception, for a role_version_id the actor cannot see, one with no permissions set yet, or a nonexistent id.';

create function public.list_role_version_permissions(
  p_role_version_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.permissions
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_role_version_permissions(p_role_version_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_role_version_permissions(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_role_version_permissions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_role_version_permissions(uuid, uuid) from public;
grant execute on function app.list_role_version_permissions(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_role_version_permissions(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_role_version_permissions(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 4. app.list_active_tenant_users_for_role_assignment
-- ===========================================================================
-- Audit remediation A2's own "assign role" form needs a real auth_user_id to hand
-- app.assign_role -- app.role_assignments.auth_user_id references auth.users(id)
-- directly, a genuinely different value from app.users.id (a separate surrogate key,
-- 20260716102620_create_users.sql:17-19). server/queries/portal-users.ts's own
-- PortalUser never projects auth_user_id (app.list_portal_users' own returns table
-- has no such column) -- extending that already-shipped, already-db-tested function's
-- return shape would need a drop+create of a function this repository's own
-- CG-AUDIT-2026-09-02 O1 remediation already verified, for a need only this one new
-- form has. A small, single-purpose function scoped to exactly that need is the
-- narrower, lower-risk change, matching this schema's own dominant pattern of one RPC
-- per real UI need rather than widening a shared one. Same authority predicate and
-- RULE A guard as app.list_portal_users (this migration's own header quotes it in
-- full) -- SECURITY DEFINER for the same reason: app.users carries no direct
-- authenticated grant to fall back on in invoker mode.
create function app.list_active_tenant_users_for_role_assignment(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  auth_user_id uuid,
  display_name text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
    select u.auth_user_id, u.display_name
    from app.users u
    where u.tenant_id = p_tenant_id
      and u.status = 'active'
      and app.has_active_tenant_membership(u.tenant_id, p_actor_auth_user_id)
      and not app.actor_holds_customer_user_layer(u.tenant_id, p_actor_auth_user_id)
    order by u.display_name asc, u.auth_user_id asc;
end;
$$;

comment on function app.list_active_tenant_users_for_role_assignment(uuid, uuid) is
  'Audit remediation A2: the option list for the "assign role" form -- every ACTIVE user''s real auth_user_id (never app.users.id, a distinct surrogate key) plus a display label. Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A). Authority predicate mirrors app.list_portal_users'' own current predicate exactly (this migration''s header quotes its derivation in full) -- active tenant membership, excluding a customer_user-layer principal. No email projected: this list exists to pick a person to assign a role to, not to view PII, and the admin/roles/ UI already has admin/users/ for that. Returns zero rows, never an exception, for a nonexistent tenant, a non-member actor, or a tenant with no active users yet.';

create function public.list_active_tenant_users_for_role_assignment(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  auth_user_id uuid,
  display_name text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_active_tenant_users_for_role_assignment(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_active_tenant_users_for_role_assignment(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_active_tenant_users_for_role_assignment with an identical grant set, never a reimplementation.';

revoke execute on function app.list_active_tenant_users_for_role_assignment(uuid, uuid) from public;
grant execute on function app.list_active_tenant_users_for_role_assignment(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_active_tenant_users_for_role_assignment(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_active_tenant_users_for_role_assignment(uuid, uuid) to authenticated, service_role;
