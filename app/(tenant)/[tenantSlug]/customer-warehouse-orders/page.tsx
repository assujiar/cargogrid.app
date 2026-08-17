import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import { listCustomerPortalWarehouseEligibility, CustomerPortalInventoryQueryError } from "../../../../server/queries/customer-portal-inventory.ts";
import { listCustomerPortalOutboundOrders, CustomerPortalWarehouseOrderQueryError } from "../../../../server/queries/customer-portal-warehouse-order.ts";
import { CUSTOMER_WAREHOUSE_ORDER_STATUSES, CustomerWarehouseOrderStatusSchema } from "../../../../server/contracts/customer-portal-warehouse-order/customer-portal-warehouse-order.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerWarehouseOrdersPanel } from "./customer-warehouse-orders-panel.tsx";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Warehouse Order and Order Fulfillment Visibility list view (CPL-310,
 * CG-S13-CPL-012, Prompt 310). Read projection over WMS-owned
 * app.wms_outbound_orders -- Business rule 1 ("Customer portal cannot create
 * hidden WMS truth or bypass warehouse approvals"), so there is no create/
 * edit/confirm/cancel action on this page; a customer cannot mutate a
 * warehouse order from the portal. Every order shown is labeled "Outbound" --
 * inbound-order visibility is a deliberate, disclosed out-of-scope decision
 * for this checkpoint (ISS-2026-120, migration design decision 11).
 *
 * Uses lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard) with the SAME denied/redirect shape app/(tenant)/
 * [tenantSlug]/customer-inventory/page.tsx already established -- this route
 * carries `CustomerPortalNav` (CPL-301's own shared shell), a natural sibling
 * of the account-access/dashboard/inventory screens that nav already links
 * between.
 *
 * The RPCs this page calls resolve scope via app.resolve_customer_account_
 * scope (CPL-300's widened resolver) rather than ATW-023's own app.list_
 * customer_outbound_orders -- the ISS-2026-117 fix, applied to warehouse
 * orders: an account granted only through CPL-300's new multi-account grant
 * table is visible here.
 */
export default async function CustomerWarehouseOrdersPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ warehouseId?: string; status?: string }>;
}) {
  const { tenantSlug } = await params;
  const { warehouseId: rawWarehouseId, status: rawStatus } = await searchParams;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={
          access.status === "tenant_suspended"
            ? "This organization's customer portal is currently unavailable."
            : "You don't have access to this organization's warehouse orders. Contact your account administrator if you believe this is a mistake."
        }
      />
    );
  }

  // A forged/malformed warehouseId is silently ignored (never surfaced as an
  // error) -- the RPC itself is deny-by-default and would return zero rows
  // for an out-of-scope or nonexistent warehouse regardless; this check only
  // avoids sending an obviously non-uuid value to the RPC at all. Same for an
  // unrecognized status value -- it would simply match zero rows server-side
  // (migration design decision 10), but validating it here keeps the filter
  // form itself honest about which values are real.
  const warehouseId = rawWarehouseId && UUID_RE.test(rawWarehouseId) ? rawWarehouseId : null;
  const statusParse = CustomerWarehouseOrderStatusSchema.safeParse(rawStatus);
  const statusFilter = statusParse.success ? statusParse.data : null;

  const supabase = await createSupabaseServerClient();
  const generatedAt = new Date().toISOString();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];
  let eligibility: Awaited<ReturnType<typeof listCustomerPortalWarehouseEligibility>> = [];
  let orders: Awaited<ReturnType<typeof listCustomerPortalOutboundOrders>> = [];

  try {
    [accounts, eligibility, orders] = await Promise.all([
      getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id),
      listCustomerPortalWarehouseEligibility(supabase, access.tenant.id, access.authUserId),
      listCustomerPortalOutboundOrders(supabase, access.tenant.id, access.authUserId, { warehouseId, statusFilter, limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError) && !(error instanceof CustomerPortalInventoryQueryError) && !(error instanceof CustomerPortalWarehouseOrderQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="warehouse-orders" />
        <ErrorState description="Something went wrong loading your warehouse orders. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="warehouse-orders" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Warehouse orders</h1>
        <p className="text-xs text-neutral-500">
          Outbound orders WMS is fulfilling for your own accounts, in warehouses you&apos;re eligible to view. This is a read-only projection -- WMS remains the source of truth; you cannot confirm, cancel, or
          edit an order from here.
        </p>
      </div>

      <CustomerWarehouseOrdersPanel
        tenantSlug={tenantSlug}
        accounts={accounts}
        eligibility={eligibility}
        orders={orders}
        warehouseId={warehouseId ?? ""}
        statusFilter={statusFilter ?? ""}
        statuses={CUSTOMER_WAREHOUSE_ORDER_STATUSES}
        generatedAt={generatedAt}
      />
    </div>
  );
}
