/**
 * POST /api/v1/vendor/rfqs/{rfqInvitationId}/response (IAE-011, Prompt 339).
 * Wraps app.submit_rfq_response_via_vendor_api -- the Vendor API's own write
 * path into the SAME app.rfq_responses table app.submit_rfq_response
 * (staff-only) already writes into. Requires an `Idempotency-Key` header
 * (server/contracts/api/api.ts's own IdempotencyKeySchema convention).
 * Dispatched by vendor-scope containment, never a staff/customer identity;
 * requires PRC:VendorPortal scope.
 */

import { authorizeApiV1Request, recordApiV1Success, apiV1ResponseHeaders, type AuthorizedApiV1Request } from "../../../../../../../lib/api-gateway/authenticate.server.ts";
import { submitRfqResponseViaVendorApi, VendorApiMutationError, type VendorApiMutationRpcClient } from "../../../../../../../server/mutations/vendor-api.ts";
import { buildApiError, IdempotencyKeySchema, PathParamUuidSchema } from "../../../../../../../server/contracts/api/api.ts";

/** The gateway's own rpcClient is narrowly typed for its own RPC names; the underlying object is the real service-role SupabaseClient, which structurally satisfies `Pick<SupabaseClient, "rpc">` at runtime -- same cast class as app/api/v1/customer/bookings/route.ts's own toBookingClient(). */
function toVendorApiClient(rpcClient: AuthorizedApiV1Request["rpcClient"]): VendorApiMutationRpcClient {
  return rpcClient as unknown as VendorApiMutationRpcClient;
}

interface RfqResponseBody {
  currency?: unknown;
  totalAmount?: unknown;
  validityUntil?: unknown;
  leadTimeDays?: unknown;
  commercialTerms?: unknown;
  vendorConfirmed?: unknown;
}

export async function POST(request: Request, { params }: { params: Promise<{ rfqInvitationId: string }> }): Promise<Response> {
  const startedAt = Date.now();
  const { rfqInvitationId } = await params;
  const authorized = await authorizeApiV1Request(request, "submit_rfq_response_via_vendor_api", "PRC:VendorPortal");
  if (!authorized.ok) {
    return authorized.response;
  }

  const idempotencyKeyHeader = request.headers.get("idempotency-key");
  const idempotencyKeyResult = IdempotencyKeySchema.safeParse(idempotencyKeyHeader);

  let statusCode: number;
  let responseBody: unknown;

  if (!authorized.request.vendorMasterRecordId) {
    statusCode = 403;
    responseBody = { error: buildApiError({ code: "forbidden_scope", message: "This endpoint requires a vendor-scoped API key.", requestId: authorized.request.correlationId }) };
  } else if (!PathParamUuidSchema.safeParse(rfqInvitationId).success) {
    // ISS-2026-214: rejected here, before any downstream call, so a malformed id never
    // reaches submitRfqResponseViaVendorApi's own z.string().uuid().parse() (whose thrown
    // ZodError would otherwise leak its raw issue array into the response).
    statusCode = 400;
    responseBody = { error: buildApiError({ code: "invalid_path_parameter", message: "rfqInvitationId must be a valid UUID.", requestId: authorized.request.correlationId }) };
  } else if (!idempotencyKeyResult.success) {
    statusCode = 400;
    responseBody = { error: buildApiError({ code: "missing_idempotency_key", message: "An Idempotency-Key header is required for this mutation.", requestId: authorized.request.correlationId }) };
  } else {
    let body: RfqResponseBody;
    try {
      body = (await request.json()) as RfqResponseBody;
    } catch {
      body = {};
    }

    try {
      const response = await submitRfqResponseViaVendorApi(toVendorApiClient(authorized.request.rpcClient), {
        tenantId: authorized.request.tenantId,
        vendorMasterRecordId: authorized.request.vendorMasterRecordId,
        rfqInvitationId,
        currency: typeof body.currency === "string" ? body.currency : "",
        totalAmount: typeof body.totalAmount === "number" ? body.totalAmount : Number(body.totalAmount),
        validityUntil: typeof body.validityUntil === "string" ? body.validityUntil : null,
        leadTimeDays: typeof body.leadTimeDays === "number" ? body.leadTimeDays : null,
        commercialTerms: (body.commercialTerms ?? {}) as Record<string, unknown>,
        vendorConfirmed: typeof body.vendorConfirmed === "boolean" ? body.vendorConfirmed : true,
        idempotencyKey: idempotencyKeyResult.data,
      });
      statusCode = 201;
      responseBody = { response };
    } catch (error) {
      statusCode = error instanceof VendorApiMutationError && error.code === "rfq_invitation_not_found" ? 404 : 422;
      responseBody = { error: buildApiError({ code: error instanceof VendorApiMutationError ? error.code : "mutation_failed", message: error instanceof Error ? error.message : "Could not submit this RFQ response.", requestId: authorized.request.correlationId }) };
    }
  }

  await recordApiV1Success(authorized.request, {
    operation: "submit_rfq_response_via_vendor_api",
    httpMethod: "POST",
    path: `/api/v1/vendor/rfqs/${rfqInvitationId}/response`,
    statusCode,
    idempotencyKey: idempotencyKeyResult.success ? idempotencyKeyResult.data : null,
    startedAt,
  });

  return Response.json(responseBody, { status: statusCode, headers: apiV1ResponseHeaders(authorized.request) });
}
