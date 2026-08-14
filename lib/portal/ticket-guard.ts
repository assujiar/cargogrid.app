/**
 * Ticketing portal entry guard (HRT-286, CG-S12-HRT-014). Same composition
 * every top-level portal guard in this repository already uses (`hris-guard.ts`,
 * `procurement-guard.ts`, ...) -- PLT-108's four-layer identity/access context
 * plus the tenant-membership RLS boundary (PLT-113) -- for the same audience
 * (`org_user`/`tenant_admin`, never `supreme_admin` or `customer_user`).
 * Internal ticket requesters/queue staff are `org_user` (Layer 3) principals
 * per 272_HRIS_TICKETING_README.md section 7 -- distinguished from each other
 * by explicit queue staffing and RBAC (TKT permissions), never by a fifth
 * principal layer.
 *
 * A dedicated guard file, not a reuse of `resolveHrisAccessForRequest` --
 * Ticketing is its own top-level workstream/route family (sibling of HRIS,
 * not a sub-feature of it, per this checkpoint's own routing decision), even
 * though the underlying layer check is identical in shape. Portal-entry
 * gating only (a coarse, layer-level check) -- every individual query/
 * mutation this portal calls still relies on its own RLS
 * (`app.can_access_ticket`/`app.is_ticket_staff`) and RBAC
 * (`app.evaluate_permission` against the 'TKT' module), unchanged.
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

export interface TicketGuardDeps {
  getCurrentUserId(): Promise<string | null>;
  findTenantBySlug(slug: string): Promise<TenantLookupResult | null>;
  resolveAccessContext(authUserId: string, tenantId: string): Promise<ResolvedAccessContextResult | null>;
}

export type TicketGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "tenant_not_found_or_not_member" }
  | { readonly status: "tenant_suspended"; readonly tenant: TenantLookupResult }
  | { readonly status: "forbidden"; readonly tenant: TenantLookupResult; readonly layer: string }
  | { readonly status: "allowed"; readonly tenant: TenantLookupResult; readonly authUserId: string; readonly layer: "tenant_admin" | "org_user" };

const ALLOWED_LAYERS = new Set(["tenant_admin", "org_user"]);

export async function resolveTicketAccess(deps: TicketGuardDeps, tenantSlug: string): Promise<TicketGuardResult> {
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
