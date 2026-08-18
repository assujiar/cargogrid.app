/**
 * Generalized customer portal entry guard (CPL-300, CG-S13-CPL-002). Read
 * lib/portal/customer-ticket-guard.ts in full before this file was written --
 * this guard has the IDENTICAL shape (unauthenticated / tenant_not_found /
 * tenant_suspended / forbidden / allowed discriminated union, using
 * app.actor_holds_customer_user_layer), because it is the general-purpose
 * version every future Phase 8 capability route (dashboard, quotation,
 * booking, etc.) will use, while customer-ticket-guard.ts stays exactly as it
 * is (Phase 7, already VERIFIED, not edited or renamed by this checkpoint) --
 * a new, separate, deliberately-parallel file, exactly how ticket-guard.ts and
 * customer-ticket-guard.ts already coexist by design.
 *
 * Every actual data SCOPE decision still happens at the RPC layer
 * (app.resolve_customer_account_scope/app.get_customer_portal_scope_context),
 * never here -- this is portal-entry gating only, mirroring every other guard
 * file's own documented boundary.
 */

export interface TenantLookupResult {
  readonly id: string;
  readonly slug: string;
  readonly canonicalStatus: string;
}

export interface CustomerPortalGuardDeps {
  getCurrentUserId(): Promise<string | null>;
  findTenantBySlug(slug: string): Promise<TenantLookupResult | null>;
  actorHoldsCustomerUserLayer(tenantId: string, authUserId: string): Promise<boolean>;
}

export type CustomerPortalGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "tenant_not_found" }
  | { readonly status: "tenant_suspended"; readonly tenant: TenantLookupResult }
  | { readonly status: "forbidden"; readonly tenant: TenantLookupResult }
  | { readonly status: "allowed"; readonly tenant: TenantLookupResult; readonly authUserId: string };

export async function resolveCustomerPortalAccess(deps: CustomerPortalGuardDeps, tenantSlug: string): Promise<CustomerPortalGuardResult> {
  const authUserId = await deps.getCurrentUserId();
  if (!authUserId) {
    return { status: "unauthenticated" };
  }

  const tenant = await deps.findTenantBySlug(tenantSlug);
  if (!tenant) {
    return { status: "tenant_not_found" };
  }

  if (tenant.canonicalStatus !== "active") {
    return { status: "tenant_suspended", tenant };
  }

  const isCustomer = await deps.actorHoldsCustomerUserLayer(tenant.id, authUserId);
  if (!isCustomer) {
    return { status: "forbidden", tenant };
  }

  return { status: "allowed", tenant, authUserId };
}
