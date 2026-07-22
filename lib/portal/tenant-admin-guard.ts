/**
 * Tenant Admin portal entry guard (PLT-135, CG-S6-PLT-032). Composes PLT-108's
 * four-layer identity/access context with the tenant-membership RLS boundary
 * (PLT-113) to answer exactly one question: may this authenticated principal enter
 * this tenant's admin portal? Prompt 135 §26: "Tenant Admin only; Supreme/customer/
 * organizational roles route to appropriate surfaces."
 *
 * This is portal-entry gating (a coarse, layer-level check), not a substitute for
 * RBAC/RLS/field/record enforcement (PLT-111/112/113/114) -- those still gate every
 * individual query and mutation a page inside the portal makes, unchanged. A future
 * checkpoint that registers a real, seeded permission catalog entry for a specific
 * admin action can layer `app.evaluate_permission()` on top of this guard's own
 * `allowed` result for that finer-grained check -- deliberately not invented here
 * without a real permission code to check against (no unresolved placeholder).
 *
 * Pure business logic, decoupled from the concrete Supabase client (the same
 * `RpcClient`-interface pattern every `server/queries|mutations/*.ts` file in this
 * repository already uses) -- fully unit-testable with mocked collaborators, no live
 * database required.
 */

export interface TenantLookupResult {
  readonly id: string;
  readonly slug: string;
  readonly canonicalStatus: string;
}

export interface ResolvedAccessContextResult {
  readonly layer: string;
  readonly tenantId: string | null;
}

export interface TenantAdminGuardDeps {
  /** Resolves to the authenticated principal's `auth.users.id`, or `null` if unauthenticated. Backed by `supabase.auth.getUser()` (RLS-scoped client) -- never `getSession()`, which does not revalidate the JWT server-side. */
  getCurrentUserId(): Promise<string | null>;
  /** Resolves the tenant by slug through the RLS-scoped client (`app.tenants`'s own `tenants_select_own_tenant` policy, PLT-113) -- returns `null` for both "does not exist" and "caller is not a member," deliberately not distinguished (no tenant-enumeration signal, the same posture `app.resolve_tenant_by_domain` already established). */
  findTenantBySlug(slug: string): Promise<TenantLookupResult | null>;
  /** Calls `app.resolve_access_context` via the service-role client (PLT-108) -- `service_role`-only, the actor's id is passed explicitly rather than inferred from RLS context. Returns `null` if no active membership exists for this (authUserId, tenantId) pair. */
  resolveAccessContext(authUserId: string, tenantId: string): Promise<ResolvedAccessContextResult | null>;
}

export type TenantAdminGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "tenant_not_found_or_not_member" }
  | { readonly status: "tenant_suspended"; readonly tenant: TenantLookupResult }
  | { readonly status: "forbidden"; readonly tenant: TenantLookupResult; readonly layer: string }
  | { readonly status: "allowed"; readonly tenant: TenantLookupResult; readonly authUserId: string; readonly layer: "tenant_admin" };

const REQUIRED_LAYER = "tenant_admin";

export async function resolveTenantAdminAccess(deps: TenantAdminGuardDeps, tenantSlug: string): Promise<TenantAdminGuardResult> {
  const authUserId = await deps.getCurrentUserId();
  if (!authUserId) {
    return { status: "unauthenticated" };
  }

  const tenant = await deps.findTenantBySlug(tenantSlug);
  if (!tenant) {
    return { status: "tenant_not_found_or_not_member" };
  }

  if (tenant.canonicalStatus !== "active") {
    return { status: "tenant_suspended", tenant };
  }

  const context = await deps.resolveAccessContext(authUserId, tenant.id);
  if (!context || context.layer !== REQUIRED_LAYER) {
    return { status: "forbidden", tenant, layer: context?.layer ?? "none" };
  }

  return { status: "allowed", tenant, authUserId, layer: "tenant_admin" };
}
