/**
 * HRIS portal entry guard (HRT-274, CG-S12-HRT-002). Same composition
 * `lib/portal/procurement-guard.ts` (PRC-251) already established -- PLT-108's
 * four-layer identity/access context plus the tenant-membership RLS boundary
 * (PLT-113) -- for the same audience (`org_user`/`tenant_admin`, never `supreme_admin`
 * or `customer_user`). HRIS employees are `org_user` (Layer 3) principals per
 * ADR-0023 Part B / the Phase 7 execution index §3 item 7 -- HR staff, managers, and
 * ordinary employees viewing their own profile are all `org_user`-layer, distinguished
 * from each other by RBAC (HRS permissions) and identity-match (own-profile), never by
 * a fifth principal layer.
 *
 * Portal-entry gating only (a coarse, layer-level check) -- every individual query/
 * mutation this portal calls still relies on its own RLS (`employees_select_scoped`)
 * and RBAC (`app.evaluate_permission` against the 'HRS' module) enforcement, unchanged.
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

export interface HrisGuardDeps {
  getCurrentUserId(): Promise<string | null>;
  findTenantBySlug(slug: string): Promise<TenantLookupResult | null>;
  resolveAccessContext(authUserId: string, tenantId: string): Promise<ResolvedAccessContextResult | null>;
}

export type HrisGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "tenant_not_found_or_not_member" }
  | { readonly status: "tenant_suspended"; readonly tenant: TenantLookupResult }
  | { readonly status: "forbidden"; readonly tenant: TenantLookupResult; readonly layer: string }
  | { readonly status: "allowed"; readonly tenant: TenantLookupResult; readonly authUserId: string; readonly layer: "tenant_admin" | "org_user" };

const ALLOWED_LAYERS = new Set(["tenant_admin", "org_user"]);

export async function resolveHrisAccess(deps: HrisGuardDeps, tenantSlug: string): Promise<HrisGuardResult> {
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
