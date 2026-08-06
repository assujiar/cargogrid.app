/**
 * Procurement portal entry guard (PRC-251, CG-S11-PRC-002). Same composition
 * `lib/portal/commercial-guard.ts` (COM-143) already established -- PLT-108's
 * four-layer identity/access context plus the tenant-membership RLS boundary
 * (PLT-113) -- for the same audience (`org_user`/`tenant_admin`, never `supreme_admin`
 * or `customer_user`), since Procurement is an internal workspace, not the
 * customer-facing surface (Prompt 251 §15/§16: "internal procurement first").
 *
 * Portal-entry gating only (a coarse, layer-level check) -- every individual query/
 * mutation this portal calls still relies on its own RLS (`vendor_profiles_select_
 * scoped`) and RBAC (`app.evaluate_permission` against the 'PRC' module) enforcement,
 * unchanged.
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

export interface ProcurementGuardDeps {
  getCurrentUserId(): Promise<string | null>;
  findTenantBySlug(slug: string): Promise<TenantLookupResult | null>;
  resolveAccessContext(authUserId: string, tenantId: string): Promise<ResolvedAccessContextResult | null>;
}

export type ProcurementGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "tenant_not_found_or_not_member" }
  | { readonly status: "tenant_suspended"; readonly tenant: TenantLookupResult }
  | { readonly status: "forbidden"; readonly tenant: TenantLookupResult; readonly layer: string }
  | { readonly status: "allowed"; readonly tenant: TenantLookupResult; readonly authUserId: string; readonly layer: "tenant_admin" | "org_user" };

const ALLOWED_LAYERS = new Set(["tenant_admin", "org_user"]);

export async function resolveProcurementAccess(deps: ProcurementGuardDeps, tenantSlug: string): Promise<ProcurementGuardResult> {
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
