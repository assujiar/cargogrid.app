/**
 * GET /api/v1/customer/shipments/{shipmentOrderId}/tracking (IAE-010, Prompt 338).
 * Wraps app.get_customer_shipment_tracking (Customer Portal, CPL-30x) verbatim --
 * dispatched as the presented customer key's own real customer_actor_auth_user_id
 * (IAE-009/010's own gateway design decision 5), so this RPC's own live
 * app.resolve_customer_account_scope re-check is the real authority boundary, not
 * this route. Requires CPT:CustomerPortal scope.
 */

import { authorizeApiV1Request, recordApiV1Success, apiV1ResponseHeaders, type AuthorizedApiV1Request } from "../../../../../../../lib/api-gateway/authenticate.server.ts";
import { getCustomerShipmentTracking, CustomerShipmentTrackingQueryError, type CustomerShipmentTrackingQueryClient } from "../../../../../../../server/queries/customer-shipment-tracking.ts";
import { buildApiError } from "../../../../../../../server/contracts/api/api.ts";

/** See app/api/v1/customer/bookings/route.ts's own toBookingClient() for why this cast is needed. */
function toTrackingClient(rpcClient: AuthorizedApiV1Request["rpcClient"]): CustomerShipmentTrackingQueryClient {
  return rpcClient as unknown as CustomerShipmentTrackingQueryClient;
}

export async function GET(request: Request, { params }: { params: Promise<{ shipmentOrderId: string }> }): Promise<Response> {
  const startedAt = Date.now();
  const { shipmentOrderId } = await params;
  const authorized = await authorizeApiV1Request(request, "get_customer_shipment_tracking", "CPT:CustomerPortal");
  if (!authorized.ok) {
    return authorized.response;
  }

  let statusCode = 200;
  let body: unknown;
  try {
    const tracking = await getCustomerShipmentTracking(toTrackingClient(authorized.request.rpcClient), authorized.request.tenantId, authorized.request.createdByAuthUserId, shipmentOrderId);
    body = { tracking };
  } catch (error) {
    const isAntiEnumeratedNotFound = error instanceof CustomerShipmentTrackingQueryError && (error.code === "record_not_found" || error.code === "actor_identity_mismatch");
    if (isAntiEnumeratedNotFound) {
      statusCode = 404;
      body = { error: buildApiError({ code: "shipment_order_not_found", message: error.message, requestId: authorized.request.correlationId }) };
    } else {
      statusCode = 422;
      body = { error: buildApiError({ code: "mutation_failed", message: error instanceof Error ? error.message : "Could not retrieve this shipment's own tracking data.", requestId: authorized.request.correlationId }) };
    }
  }

  await recordApiV1Success(authorized.request, { operation: "get_customer_shipment_tracking", httpMethod: "GET", path: `/api/v1/customer/shipments/${shipmentOrderId}/tracking`, statusCode, startedAt });

  return Response.json(body, { status: statusCode, headers: apiV1ResponseHeaders(authorized.request) });
}
