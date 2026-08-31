import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getCustomerPortalInboundOrder, listCustomerPortalInboundOrderLines, CustomerPortalWarehouseOrderQueryError } from "../../../../../../server/queries/customer-portal-warehouse-order.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { CustomerInboundOrderDetailPanel } from "./customer-inbound-order-detail-panel.tsx";

/**
 * Customer inbound warehouse-order detail view (ISS-2026-120) -- the inbound
 * twin of ../../[outboundOrderId]/page.tsx, deliberately identical in shape.
 *
 * Uses ONLY the customer-safe get RPC, so an out-of-scope order id and a
 * genuinely nonexistent one are indistinguishable here (both raise the same
 * anti-enumerating record_not_found). That is why this page renders a plain
 * 404 rather than a "forbidden" state, which would disclose which of the two
 * occurred.
 *
 * Its own route segment is `inbound/[inboundOrderId]` rather than a second
 * bare dynamic segment beside `[outboundOrderId]`: the two ids come from
 * different tables and are not interchangeable, and a single segment covering
 * both would have to guess which table an id belongs to -- guessing wrong on a
 * customer-facing gate is exactly the class of mistake this capability's
 * anti-enumeration discipline exists to prevent.
 */
export default async function CustomerInboundOrderDetailPage({ params }: { params: Promise<{ tenantSlug: string; inboundOrderId: string }> }) {
  const { tenantSlug, inboundOrderId } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let notFoundResult = false;
  let order: Awaited<ReturnType<typeof getCustomerPortalInboundOrder>> | null = null;
  let lines: Awaited<ReturnType<typeof listCustomerPortalInboundOrderLines>> = [];

  try {
    order = await getCustomerPortalInboundOrder(supabase, access.tenant.id, access.authUserId, inboundOrderId);
    lines = await listCustomerPortalInboundOrderLines(supabase, access.authUserId, inboundOrderId);
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
    return <ErrorState description="Something went wrong loading this inbound order. Please try again." />;
  }

  const generatedAt = new Date().toISOString();

  return <CustomerInboundOrderDetailPanel tenantSlug={tenantSlug} order={order} lines={lines} generatedAt={generatedAt} />;
}
