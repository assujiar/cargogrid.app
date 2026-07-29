/**
 * Finance portal entry guard (FIN-191, CG-S9-FIN-002). Same composition
 * `lib/portal/commercial-guard.ts` (COM-143) and `lib/portal/operations-guard.ts`
 * (OPS-168) already established -- PLT-108's four-layer identity/access context
 * plus the tenant-membership RLS boundary (PLT-113) -- for the same audience:
 * `org_user` (the regular tenant employee layer, which any Finance-role holder
 * uses) as well as `tenant_admin` (who also administers Finance Configuration
 * under this capability's own two-factor authority model -- see the migration's
 * own header for why `app.create_finance_config_draft`/`publish_finance_config_version`
 * require both tenant_admin/Supreme authority (inherited from the reused
 * Configuration Engine) AND FIN:Edit/FIN:Approve (this capability's own RBAC
 * layer)), never `supreme_admin` (a distinct portal) or `customer_user` (Finance
 * Configuration is internal Finance UX only -- Prompt 191 §15, never a Customer
 * Portal surface).
 *
 * Portal-entry gating only (a coarse, layer-level check) -- every individual
 * query/mutation this portal calls still relies on its own RLS and RBAC
 * (`app.evaluate_permission`) enforcement, unchanged, per the same discipline
 * `commercial-guard.ts`/`operations-guard.ts`'s own header already states.
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

export interface FinanceGuardDeps {
  getCurrentUserId(): Promise<string | null>;
  findTenantBySlug(slug: string): Promise<TenantLookupResult | null>;
  resolveAccessContext(authUserId: string, tenantId: string): Promise<ResolvedAccessContextResult | null>;
}

export type FinanceGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "tenant_not_found_or_not_member" }
  | { readonly status: "tenant_suspended"; readonly tenant: TenantLookupResult }
  | { readonly status: "forbidden"; readonly tenant: TenantLookupResult; readonly layer: string }
  | { readonly status: "allowed"; readonly tenant: TenantLookupResult; readonly authUserId: string; readonly layer: "tenant_admin" | "org_user" };

const ALLOWED_LAYERS = new Set(["tenant_admin", "org_user"]);

export async function resolveFinanceAccess(deps: FinanceGuardDeps, tenantSlug: string): Promise<FinanceGuardResult> {
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
