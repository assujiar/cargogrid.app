/**
 * Commercial portal entry guard (COM-143, CG-S7-COM-002). Same composition
 * `lib/portal/tenant-admin-guard.ts` (PLT-135) already established -- PLT-108's
 * four-layer identity/access context plus the tenant-membership RLS boundary
 * (PLT-113) -- but for a different audience: `org_user` (the regular tenant employee
 * layer sales reps/managers hold) as well as `tenant_admin` (who may also work leads),
 * never `supreme_admin` (a distinct portal) or `customer_user` (Commercial is an
 * internal workspace, not the customer-facing surface).
 *
 * Portal-entry gating only (a coarse, layer-level check) -- every individual query/
 * mutation this portal calls still relies on its own RLS (`leads_select_scoped`) and
 * RBAC (`app.evaluate_permission`) enforcement, unchanged, per the same discipline
 * `tenant-admin-guard.ts`'s own header already states.
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

export interface CommercialGuardDeps {
  getCurrentUserId(): Promise<string | null>;
  findTenantBySlug(slug: string): Promise<TenantLookupResult | null>;
  resolveAccessContext(authUserId: string, tenantId: string): Promise<ResolvedAccessContextResult | null>;
}

export type CommercialGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "tenant_not_found_or_not_member" }
  | { readonly status: "tenant_suspended"; readonly tenant: TenantLookupResult }
  | { readonly status: "forbidden"; readonly tenant: TenantLookupResult; readonly layer: string }
  | { readonly status: "allowed"; readonly tenant: TenantLookupResult; readonly authUserId: string; readonly layer: "tenant_admin" | "org_user" };

const ALLOWED_LAYERS = new Set(["tenant_admin", "org_user"]);

export async function resolveCommercialAccess(deps: CommercialGuardDeps, tenantSlug: string): Promise<CommercialGuardResult> {
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
  if (!context || !ALLOWED_LAYERS.has(context.layer)) {
    return { status: "forbidden", tenant, layer: context?.layer ?? "none" };
  }

  return { status: "allowed", tenant, authUserId, layer: context.layer as "tenant_admin" | "org_user" };
}
