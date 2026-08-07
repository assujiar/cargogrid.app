import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listPurchaseOrders, PurchaseOrderQueryError } from "../../../../../server/queries/purchase-order.ts";
import { PURCHASE_ORDER_STATUSES, type PurchaseOrderStatus } from "../../../../../server/contracts/purchase-order/purchase-order.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { PurchaseOrderQueuePanel } from "./purchase-order-queue-panel.tsx";
import { draftPurchaseOrderFromSelectionAction } from "./actions.ts";

/**
 * Purchase Order queue (PRC-260, CG-S11-PRC-011) -- purchase orders drafted from an
 * approved, submitted app.vendor_comparisons selection (PRC-258/259), filterable by
 * status. With no status filter, superseded (amended-away, historical) versions are
 * excluded by default. Mirrors app/(tenant)/[tenantSlug]/procurement/vendor-comparison/
 * page.tsx's own exact shape.
 */
export default async function PurchaseOrderQueuePage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status } = await searchParams;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const statusFilter: PurchaseOrderStatus | null = status && (PURCHASE_ORDER_STATUSES as readonly string[]).includes(status) ? (status as PurchaseOrderStatus) : null;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let purchaseOrders: Awaited<ReturnType<typeof listPurchaseOrders>> = [];
  try {
    purchaseOrders = await listPurchaseOrders(supabase, access.tenant.id, access.authUserId, statusFilter, null, 100);
  } catch (error) {
    if (!(error instanceof PurchaseOrderQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the purchase order queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Purchase Orders</h1>
        <p className="text-xs text-neutral-500">
          Governed vendor commitments, drafted only from an approved vendor comparison selection. Approval, issue, acknowledgement, and amendments preserve exact versions -- a purchase
          order commitment never creates AP, journal, settlement, or cash movement (Finance boundary is enforced structurally, not by convention alone).
        </p>
      </div>

      <PurchaseOrderQueuePanel tenantSlug={tenantSlug} purchaseOrders={purchaseOrders} statusFilter={statusFilter} draftAction={draftPurchaseOrderFromSelectionAction.bind(null, tenantSlug)} />
    </div>
  );
}
