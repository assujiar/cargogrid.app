/**
 * POST /api/v1/customer/bookings/{bookingRequestId}/submit (IAE-010, Prompt 338).
 * Wraps app.submit_customer_booking_request (Customer Portal, CPL-303) verbatim --
 * the idempotent state-transition half of the booking write resource (§21 Main
 * flow / §22 Alternative flow's own idempotent-retry business rule). Dispatched as
 * the presented customer key's own real customer_actor_auth_user_id; requires
 * CPT:CustomerPortal scope.
 */

import { authorizeApiV1Request, recordApiV1Success, apiV1ResponseHeaders, type AuthorizedApiV1Request } from "../../../../../../../lib/api-gateway/authenticate.server.ts";
import { submitCustomerBookingRequest, CustomerBookingRequestMutationError, type CustomerBookingRequestMutationRpcClient } from "../../../../../../../server/mutations/customer-booking-request.ts";
import { getCustomerBookingRequest, CustomerBookingRequestQueryError } from "../../../../../../../server/queries/customer-booking-request.ts";
import { buildApiError } from "../../../../../../../server/contracts/api/api.ts";

/** See app/api/v1/customer/bookings/route.ts's own toBookingClient() for why this cast is needed. */
function toBookingClient(rpcClient: AuthorizedApiV1Request["rpcClient"]): CustomerBookingRequestMutationRpcClient {
  return rpcClient as unknown as CustomerBookingRequestMutationRpcClient;
}

interface SubmitBookingBody {
  expectedVersion?: unknown;
}

export async function POST(request: Request, { params }: { params: Promise<{ bookingRequestId: string }> }): Promise<Response> {
  const startedAt = Date.now();
  const { bookingRequestId } = await params;
  const authorized = await authorizeApiV1Request(request, "submit_customer_booking_request", "CPT:CustomerPortal");
  if (!authorized.ok) {
    return authorized.response;
  }

  let body: SubmitBookingBody;
  try {
    body = (await request.json()) as SubmitBookingBody;
  } catch {
    body = {};
  }
  const expectedVersion = typeof body.expectedVersion === "number" ? body.expectedVersion : Number(body.expectedVersion);

  let statusCode: number;
  let responseBody: unknown;
  if (!Number.isInteger(expectedVersion) || expectedVersion <= 0) {
    statusCode = 400;
    responseBody = { error: buildApiError({ code: "invalid_expected_version", message: "A positive integer expectedVersion is required.", requestId: authorized.request.correlationId }) };
  } else {
    try {
      // HDN-BLK-013: confirm this booking request's own tenant_id actually matches the
      // caller's authorized tenant before ever reaching the mutating RPC below --
      // app.get_customer_booking_request is itself tenant-scoped (p_tenant_id) and
      // anti-enumerating, throwing record_not_found for a cross-tenant id exactly like
      // a genuinely missing one.
      await getCustomerBookingRequest(toBookingClient(authorized.request.rpcClient), authorized.request.tenantId, bookingRequestId, authorized.request.createdByAuthUserId);

      const booking = await submitCustomerBookingRequest(toBookingClient(authorized.request.rpcClient), {
        bookingRequestId,
        expectedVersion,
        actorAuthUserId: authorized.request.createdByAuthUserId,
        actorLabel: authorized.request.createdByAuthUserId,
      });
      statusCode = 200;
      responseBody = { booking };
    } catch (error) {
      if (error instanceof CustomerBookingRequestQueryError) {
        statusCode = 404;
        responseBody = { error: buildApiError({ code: "booking_request_not_found", message: error.message, requestId: authorized.request.correlationId }) };
      } else {
        statusCode = error instanceof CustomerBookingRequestMutationError && error.code === "stale_version" ? 409 : 422;
        responseBody = { error: buildApiError({ code: error instanceof CustomerBookingRequestMutationError ? error.code : "mutation_failed", message: error instanceof Error ? error.message : "Could not submit this booking request.", requestId: authorized.request.correlationId }) };
      }
    }
  }

  await recordApiV1Success(authorized.request, { operation: "submit_customer_booking_request", httpMethod: "POST", path: `/api/v1/customer/bookings/${bookingRequestId}/submit`, statusCode, startedAt });

  return Response.json(responseBody, { status: statusCode, headers: apiV1ResponseHeaders(authorized.request.correlationId) });
}
