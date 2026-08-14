/**
 * Customer ticket portal entry guard (HRT-287, CG-S12-HRT-015). A genuinely
 * separate route family from `lib/portal/ticket-guard.ts` (the internal/
 * staff ticket workspace) -- distinguished by PRINCIPAL LAYER, not by a role
 * within the same layer: this guard admits ONLY `customer_user` (Layer 4),
 * `ticket-guard.ts` admits ONLY `org_user`/`tenant_admin` (Layer 2/3). No
 * identity holds both simultaneously in the intended model, and this guard
 * does not attempt to arbitrate a dual-membership edge case -- it asks one
 * narrow question (`app.actor_holds_customer_user_layer`) and admits or
 * refuses on that alone. Every actual data scope decision still happens at
 * the RPC layer (`app.resolve_customer_owner_account_scope`), never here --
 * this is portal-entry gating only, mirroring every other guard file's own
 * documented boundary.
 */

export interface TenantLookupResult {
  readonly id: string;
  readonly slug: string;
  readonly canonicalStatus: string;
}

export interface CustomerTicketGuardDeps {
  getCurrentUserId(): Promise<string | null>;
  findTenantBySlug(slug: string): Promise<TenantLookupResult | null>;
  actorHoldsCustomerUserLayer(tenantId: string, authUserId: string): Promise<boolean>;
}

export type CustomerTicketGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "tenant_not_found" }
  | { readonly status: "tenant_suspended"; readonly tenant: TenantLookupResult }
  | { readonly status: "forbidden"; readonly tenant: TenantLookupResult }
  | { readonly status: "allowed"; readonly tenant: TenantLookupResult; readonly authUserId: string };

export async function resolveCustomerTicketAccess(deps: CustomerTicketGuardDeps, tenantSlug: string): Promise<CustomerTicketGuardResult> {
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
