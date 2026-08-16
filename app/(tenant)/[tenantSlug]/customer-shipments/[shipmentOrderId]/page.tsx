import { randomUUID } from "node:crypto";
import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getCustomerShipmentOrder, listCustomerShipmentOrderChangeRequests, CustomerShipmentOrderQueryError } from "../../../../../server/queries/customer-shipment-order.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CustomerShipmentDetailPanel } from "./customer-shipment-detail-panel.tsx";
import { requestCustomerShipmentOrderChangeAction } from "../actions.ts";

/**
 * Customer shipment order detail view (CPL-304, CG-S13-CPL-006). Uses ONLY
 * the customer-safe get RPC (app.get_customer_shipment_order) -- an
 * out-of-scope shipment order id and a genuinely nonexistent id are
 * indistinguishable here (both raise the identical anti-enumerating
 * record_not_found), which is why this page renders a plain 404 rather than
 * a "forbidden" state that would disclose which case occurred (mirrors
 * app/(tenant)/[tenantSlug]/customer-bookings/[bookingRequestId]/page.tsx
 * exactly).
 *
 * Renders app.shipment_orders' own real status plainly (draft/confirmed/
 * cancelled) -- no new "locked" concept exists; the source prompt's own
 * alternative flow ("if Operations has locked the shipment... create a
 * ticket or change request instead") is fully satisfied by this immutable
 * detail plus the "request a change" form plus a plain link to the existing
 * customer-tickets route (design decision 4 of the migration -- ticket
 * CREATION integration is Prompt 313's own job, not built here).
 */
export default async function CustomerShipmentDetailPage({ params }: { params: Promise<{ tenantSlug: string; shipmentOrderId: string }> }) {
  const { tenantSlug, shipmentOrderId } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let notFoundResult = false;
  let detail: Awaited<ReturnType<typeof getCustomerShipmentOrder>> | null = null;
  let changeRequests: Awaited<ReturnType<typeof listCustomerShipmentOrderChangeRequests>> = [];

  try {
    detail = await getCustomerShipmentOrder(supabase, access.tenant.id, access.authUserId, shipmentOrderId);
    changeRequests = await listCustomerShipmentOrderChangeRequests(supabase, access.tenant.id, access.authUserId, { shipmentOrderId, limit: 50 });
  } catch (error) {
    if (!(error instanceof CustomerShipmentOrderQueryError)) throw error;
    if (error.code === "record_not_found") {
      notFoundResult = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundResult) {
    notFound();
  }
  if (loadFailed || !detail) {
    return <ErrorState description="Something went wrong loading this shipment. Please try again." />;
  }

  // Fresh per render, not regenerated per submit -- Tier C fix
  // (spec-compliance), mirrors customer-quotes/[requestId]/page.tsx's own
  // identical fix.
  const requestChangeIdempotencyKey = randomUUID();

  return (
    <CustomerShipmentDetailPanel
      tenantSlug={tenantSlug}
      detail={detail}
      changeRequests={changeRequests}
      requestChangeAction={requestCustomerShipmentOrderChangeAction.bind(null, tenantSlug, shipmentOrderId, requestChangeIdempotencyKey)}
    />
  );
}
