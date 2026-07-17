-- Platform Core capability PLT-113 (RLS Tenant Policy Foundation, CG-S6-PLT-010)
-- Stage 7 of the 8-stage access-evaluation flow (docs/architecture/06_RLS_RBAC_WORKSTREAM.md
-- §3: "7 RLS enforcement at database"). Every table PLT-105 through PLT-112 created has
-- had `row level security` ENABLED since its own migration, but until now `authenticated`
-- held no `USAGE` grant on the `app` schema at all -- the schema-privilege layer denied
-- everything before RLS was ever evaluated (the "defense in depth" pattern every prior
-- db-test proved). This migration is the one that finally grants `authenticated` a real,
-- narrow, RLS-governed path -- making tenant isolation a database guarantee an
-- authenticated end-user session can actually reach, not just a theoretical policy no
-- session could ever exercise.
--
-- Scope, disclosed rather than left implicit (Prompt 113 §4: "INITIAL policies" -- not a
-- claim of full production authorization):
--
-- * SELECT only. `authenticated` receives no INSERT/UPDATE/DELETE grant on any table in
--   this migration. Every write in this repository so far flows through an already-built,
--   already-tested `service_role`-only plpgsql function (app.provision_tenant,
--   app.invite_user, app.assign_role, ...) -- granting direct table writes to
--   `authenticated` today would let a session bypass those functions' own idempotency,
--   lifecycle-transition, and cross-table-sync logic entirely. Writing INSERT/UPDATE/DELETE
--   RLS policies with no matching grant to exercise them would be untestable busywork, not
--   real coverage -- disclosed here, not silently skipped. A future capability that
--   introduces direct-write RPC-free paths (if one ever does) would need its own explicit
--   write policies at that time.
-- * Tenant-scoped *primary* tables only (`app.tenants`, `app.tenant_entitlements`,
--   `app.tenant_entitlement_overrides`, `app.tenant_user_identities`,
--   `app.principal_memberships`, `app.org_units`, `app.users`, `app.roles`,
--   `app.role_versions`, `app.role_assignments`). Every capability's own bounded
--   `*_history` audit table (`tenant_status_history`, `entitlement_assignment_history`,
--   `tenant_user_identity_history`, `principal_membership_history`, `org_unit_history`,
--   `user_lifecycle_history`, `role_lifecycle_history`) is deliberately left
--   `service_role`-only here -- `PLT-116` (Audit Trail Foundation) is the more coherent
--   single decision point for a canonical audit-read policy across all of them at once,
--   rather than seven ad hoc one-off policies now. Global, non-tenant-scoped catalogues
--   (`app.entitlement_modules`/`features`/`packages`, `app.permissions`) are out of this
--   checkpoint's scope entirely -- no live UI consumes them yet.

-- Two stable, non-recursive, SECURITY DEFINER helper functions (Prompt 113 §17/§20 task 2)
-- -- SECURITY DEFINER because `authenticated` is never granted direct SELECT on
-- app.tenant_user_identities/app.principal_memberships themselves (membership tables are
-- not meant to be end-user-browsable), so the *helper* runs with the elevated privilege of
-- its owner to answer the membership question, while the *caller* still only ever sees a
-- boolean. `set search_path` is set explicitly to close the well-known SECURITY DEFINER
-- search-path-injection footgun.
create function app.is_supreme_admin(p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.principal_memberships
    where auth_user_id = p_auth_user_id and layer = 'supreme_admin' and status = 'active'
  );
$$;

comment on function app.is_supreme_admin is
  'RLS helper (PLT-113): true if the identity holds a live global supreme_admin principal membership (RPD-022''s disclosed absolute-CRUD exception, docs/architecture/06_RLS_RBAC_WORKSTREAM.md §8) -- the same exception app.evaluate_permission() (PLT-112) already implements at the RBAC layer, now also honored at the RLS layer.';

create function app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.tenant_user_identities
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active'
  ) or app.is_supreme_admin(p_auth_user_id);
$$;

comment on function app.has_active_tenant_membership is
  'RLS helper (PLT-113): true if the identity has an active app.tenant_user_identities linkage (PLT-107) to the given tenant, or is a Supreme Admin. The single reusable predicate every tenant-scoped SELECT policy below uses -- stage 2 (tenant membership) of the 8-stage flow, now enforced at the database boundary, not only inside plpgsql functions.';

grant usage on schema app to authenticated;
grant execute on function app.is_supreme_admin(uuid) to authenticated;
grant execute on function app.has_active_tenant_membership(uuid, uuid) to authenticated;

-- app.tenants: visible only if the caller has an active identity linkage to it, or is
-- Supreme Admin. Note the predicate is on `id`, not `tenant_id` -- this table IS the tenant.
grant select on app.tenants to authenticated;
create policy tenants_select_own_tenant
  on app.tenants for select
  to authenticated
  using (app.has_active_tenant_membership(id));

grant select on app.tenant_entitlements to authenticated;
create policy tenant_entitlements_select_own_tenant
  on app.tenant_entitlements for select
  to authenticated
  using (app.has_active_tenant_membership(tenant_id));

grant select on app.tenant_entitlement_overrides to authenticated;
create policy tenant_entitlement_overrides_select_own_tenant
  on app.tenant_entitlement_overrides for select
  to authenticated
  using (app.has_active_tenant_membership(tenant_id));

grant select on app.tenant_user_identities to authenticated;
create policy tenant_user_identities_select_own_tenant
  on app.tenant_user_identities for select
  to authenticated
  using (app.has_active_tenant_membership(tenant_id));

grant select on app.principal_memberships to authenticated;
create policy principal_memberships_select_own_tenant
  on app.principal_memberships for select
  to authenticated
  using (
    (tenant_id is null and auth_user_id = auth.uid())
    or (tenant_id is not null and app.has_active_tenant_membership(tenant_id))
  );

comment on policy principal_memberships_select_own_tenant on app.principal_memberships is
  'tenant_id is null only for a supreme_admin-layer row (PLT-108''s own layer-scope-shape constraint). The null-tenant branch is deliberately scoped to auth_user_id = auth.uid() -- without that, "tenant_id is null" alone would let any authenticated caller see every OTHER identity''s global supreme_admin row too (revealing who is a Supreme Admin platform-wide), which app.is_supreme_admin()''s own tenant-scoped OR-branch does not need and must not leak.';

grant select on app.org_units to authenticated;
create policy org_units_select_own_tenant
  on app.org_units for select
  to authenticated
  using (app.has_active_tenant_membership(tenant_id));

grant select on app.users to authenticated;
create policy users_select_own_tenant
  on app.users for select
  to authenticated
  using (app.has_active_tenant_membership(tenant_id));

grant select on app.roles to authenticated;
create policy roles_select_own_tenant
  on app.roles for select
  to authenticated
  using (app.has_active_tenant_membership(tenant_id));

-- app.role_versions carries no tenant_id column of its own -- scope is derived through its
-- parent app.roles row, the correct non-duplicated ownership per Tech Arch's "one
-- authoritative owner" principle (docs/architecture/06_RLS_RBAC_WORKSTREAM.md §5.3).
grant select on app.role_versions to authenticated;
create policy role_versions_select_own_tenant
  on app.role_versions for select
  to authenticated
  using (exists (
    select 1 from app.roles r
    where r.id = role_versions.role_id and app.has_active_tenant_membership(r.tenant_id)
  ));

grant select on app.role_assignments to authenticated;
create policy role_assignments_select_own_tenant
  on app.role_assignments for select
  to authenticated
  using (app.has_active_tenant_membership(tenant_id));
