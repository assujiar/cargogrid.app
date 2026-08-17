import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getCustomerPortalOutboundOrder, listCustomerPortalOutboundOrderLines, CustomerPortalWarehouseOrderQueryError } from "../../../../../server/queries/customer-portal-warehouse-order.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CustomerWarehouseOrderDetailPanel } from "./customer-warehouse-order-detail-panel.tsx";

/**
 * Customer warehouse order detail view (CPL-310, CG-S13-CPL-012, Prompt 310).
 * Uses ONLY the customer-safe get RPC (app.get_customer_portal_outbound_
 * order) -- an out-of-scope order id and a genuinely nonexistent id are
 * indistinguishable here (both raise the identical anti-enumerating
 * record_not_found), which is why this page renders a plain 404 rather than
 * a "forbidden" state that would disclose which case occurred (mirrors
 * app/(tenant)/[tenantSlug]/customer-shipments/[shipmentOrderId]/page.tsx
 * exactly).
 *
 * Renders app.wms_outbound_orders' own real status plainly (draft/confirmed/
 * cancelled, mapped to a customer-visible label at the presentation layer
 * only, migration design decision 9) -- there is no "in picking"/"in
 * packing"/"loaded"/"shipped" concept exposed here: Business rule 2 ("Pick/
 * pack worker, productivity, internal task queue and other-customer location
 * data are hidden") means this checkpoint's own RPCs never compose app.wms_
 * pick_tasks/app.wms_packages/app.wms_outbound_shipments at all (migration
 * design decision 12).
 *
 * The exception/ticket-handoff action point is a plain link to the existing
 * customer-tickets route (HRT-287, already shipped) -- migration design
 * decision 13: CPL-313 (Ticketing/Support Integration) has not landed yet in
 * this batch's own sequence, so deep entity-link wiring is out of scope here,
 * per this task's own explicit instruction.
 */
export default async function CustomerWarehouseOrderDetailPage({ params }: { params: Promise<{ tenantSlug: string; outboundOrderId: string }> }) {
  const { tenantSlug, outboundOrderId } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let notFoundResult = false;
  let order: Awaited<ReturnType<typeof getCustomerPortalOutboundOrder>> | null = null;
  let lines: Awaited<ReturnType<typeof listCustomerPortalOutboundOrderLines>> = [];

  try {
    order = await getCustomerPortalOutboundOrder(supabase, access.tenant.id, access.authUserId, outboundOrderId);
    lines = await listCustomerPortalOutboundOrderLines(supabase, access.authUserId, outboundOrderId);
  } catch (error) {
    if (!(error instanceof CustomerPortalWarehouseOrderQueryError)) throw error;
    if (error.code === "record_not_found") {
      notFoundResult = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundResult) {
    notFound();
  }
  if (loadFailed || !order) {
    return <ErrorState description="Something went wrong loading this warehouse order. Please try again." />;
  }

  const generatedAt = new Date().toISOString();

  return <CustomerWarehouseOrderDetailPanel tenantSlug={tenantSlug} order={order} lines={lines} generatedAt={generatedAt} />;
}
