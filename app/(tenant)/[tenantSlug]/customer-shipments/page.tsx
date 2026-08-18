import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import { listCustomerShipmentOrders, CustomerShipmentOrderQueryError } from "../../../../server/queries/customer-shipment-order.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerShipmentsPanel } from "./customer-shipments-panel.tsx";

/**
 * Customer shipment order list view (CPL-304, CG-S13-CPL-006). Uses
 * lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard), mirroring app/(tenant)/[tenantSlug]/customer-bookings/
 * page.tsx's own structure. This is a READ PROJECTION over the
 * Operations-owned app.shipment_orders (never a parallel shipment-truth
 * table) -- there is no "create" action on this page; Operations remains
 * the sole creator of a shipment order (app.create_shipment_order_from_job,
 * OPS:Create, unchanged and unreachable from any customer RPC).
 */
export default async function CustomerShipmentsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];
  let shipments: Awaited<ReturnType<typeof listCustomerShipmentOrders>> = [];

  try {
    [accounts, shipments] = await Promise.all([
      getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id),
      listCustomerShipmentOrders(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError) && !(error instanceof CustomerShipmentOrderQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your shipments. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Shipments</h1>
        <p className="text-xs text-neutral-500">
          Every shipment order across your account/site scope, reflecting Operations&apos; own real status. Operations remains the sole owner of shipment execution -- this view is a read-only projection; open a
          shipment to request a change.
        </p>
      </div>

      <CustomerShipmentsPanel tenantSlug={tenantSlug} accounts={accounts} shipments={shipments} />
    </div>
  );
}
