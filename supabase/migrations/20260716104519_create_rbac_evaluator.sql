-- Platform Core capability PLT-112 (RBAC Enforcement, CG-S6-PLT-009)
-- Stage 3 of the 8-stage access-evaluation flow (docs/architecture/06_RLS_RBAC_WORKSTREAM.md
-- §3: "3 RBAC action: role allows action"). Reads PLT-111's published role/permission
-- bindings and answers exactly one question -- does this identity, in this tenant, hold a
-- published role granting this canonical permission -- and nothing more. This migration
-- writes no RLS policy (PLT-113's scope) and adds no permission/role schema of its own
-- (PLT-111's scope); it only adds the evaluator function and one indexed hot path.
--
-- "Role names/titles never authorize; canonical permissions and scope do" (Prompt 112 §24)
-- is enforced structurally: app.evaluate_permission() never references app.roles.name
-- anywhere in its logic -- proven directly in scripts/db-tests/rbac-enforcement.sql by a
-- role literally named to sound like a bypass, with no matching permission bound, still
-- denying.
--
-- Multiple granted roles combine additively (union) -- there is no "explicit deny" role
-- assignment concept in this model, unlike PLT-106's entitlement overrides which did carry
-- an explicit deny direction. This is a disclosed, deliberate difference: RBAC roles only
-- ever grant, so the only coherent combination policy is "any granting role permits."
--
-- Supreme Admin's disclosed absolute-CRUD exception (RPD-022, docs/architecture/06_RLS_RBAC_WORKSTREAM.md
-- §8) is real and implemented here: a live global supreme_admin principal membership
-- (PLT-108) bypasses the role/permission lookup entirely.

-- Hot-path index for the evaluator's active-assignment lookup (Prompt 112 §17: "Bound
-- evaluator queries ... by tenant/principal/role version").
create index role_assignments_tenant_auth_active_idx
  on app.role_assignments (tenant_id, auth_user_id)
  where status = 'active';

create type app.rbac_decision as (
  allowed boolean,
  reason text,
  permission_id uuid,
  role_id uuid,
  role_version_id uuid,
  evaluated_at timestamptz
);

create function app.evaluate_permission(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_resource_module_code text,
  p_action text,
  p_as_of timestamptz default now()
)
returns app.rbac_decision
language plpgsql
stable
as $$
declare
  v_permission app.permissions;
  v_match record;
begin
  select * into v_permission
  from app.permissions
  where resource_module_code = p_resource_module_code and action = p_action;

  if not found then
    return row(false, 'unknown_permission', null, null, null, p_as_of)::app.rbac_decision;
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
$$;

comment on function app.evaluate_permission is
  'RBAC stage 3 evaluator (PLT-112). Never replaces RLS (PLT-113) or field/record checks (PLT-114) -- answers only "does this identity in this tenant hold a published role granting this canonical permission," structurally ignoring role names/titles.';

grant execute on function app.evaluate_permission(uuid, uuid, text, text, timestamptz) to service_role;
