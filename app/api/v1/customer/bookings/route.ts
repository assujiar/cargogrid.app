/**
 * POST /api/v1/customer/bookings (IAE-010, Prompt 338). Wraps
 * app.create_customer_booking_request_draft (Customer Portal, CPL-303) verbatim --
 * the first REAL idempotent-mutation resource this gateway serves (IAE-009's own
 * disclosed "IAE-010/011's own idempotent write resources are the first real
 * consumers"). Requires an `Idempotency-Key` header (the retry-safe convention
 * `server/contracts/api/api.ts`'s own IdempotencyKeySchema documents) -- a retried
 * request with the SAME key against the SAME account returns the identical,
 * already-created draft, never a duplicate. Dispatched as the presented customer
 * key's own real customer_actor_auth_user_id; requires CPT:CustomerPortal scope.
 */

import { authorizeApiV1Request, recordApiV1Success, apiV1ResponseHeaders, type AuthorizedApiV1Request } from "../../../../../lib/api-gateway/authenticate.server.ts";
import { createCustomerBookingRequestDraft, CustomerBookingRequestMutationError, type CustomerBookingRequestMutationRpcClient } from "../../../../../server/mutations/customer-booking-request.ts";
import { buildApiError, IdempotencyKeySchema } from "../../../../../server/contracts/api/api.ts";

/** The gateway's own rpcClient is narrowly typed for its own RPC names; the underlying object is the real service-role SupabaseClient, which structurally satisfies `Pick<SupabaseClient, "rpc">` at runtime -- same cast class as `app/(tenant)/[tenantSlug]/admin/api-keys/page.tsx`'s own `toQueryClient()`. */
function toBookingClient(rpcClient: AuthorizedApiV1Request["rpcClient"]): CustomerBookingRequestMutationRpcClient {
  return rpcClient as unknown as CustomerBookingRequestMutationRpcClient;
}

interface BookingRequestBody {
  accountId?: unknown;
  linkedQuoteRequestId?: unknown;
  cargoDescription?: unknown;
  pickup?: unknown;
  delivery?: unknown;
  requestedPickupAt?: unknown;
  requestedDeliveryAt?: unknown;
  specialInstructions?: unknown;
}

export async function POST(request: Request): Promise<Response> {
  const startedAt = Date.now();
  const authorized = await authorizeApiV1Request(request, "create_customer_booking_request_draft", "CPT:CustomerPortal");
  if (!authorized.ok) {
    return authorized.response;
  }

  const idempotencyKeyHeader = request.headers.get("idempotency-key");
  const idempotencyKeyResult = IdempotencyKeySchema.safeParse(idempotencyKeyHeader);
  if (!idempotencyKeyResult.success) {
    const statusCode = 400;
    await recordApiV1Success(authorized.request, { operation: "create_customer_booking_request_draft", httpMethod: "POST", path: "/api/v1/customer/bookings", statusCode, startedAt });
    return Response.json(
      { error: buildApiError({ code: "missing_idempotency_key", message: "An Idempotency-Key header is required for this mutation.", requestId: authorized.request.correlationId }) },
      { status: statusCode, headers: apiV1ResponseHeaders(authorized.request) },
    );
  }

  let body: BookingRequestBody;
  try {
    body = (await request.json()) as BookingRequestBody;
  } catch {
    body = {};
  }

  const accountId = typeof body.accountId === "string" ? body.accountId : "";

  let statusCode: number;
  let responseBody: unknown;
  try {
    const booking = await createCustomerBookingRequestDraft(toBookingClient(authorized.request.rpcClient), {
      tenantId: authorized.request.tenantId,
      accountId,
      linkedQuoteRequestId: typeof body.linkedQuoteRequestId === "string" ? body.linkedQuoteRequestId : null,
      cargoDescription: typeof body.cargoDescription === "string" ? body.cargoDescription : null,
      pickup: (body.pickup ?? {}) as Record<string, unknown>,
      delivery: (body.delivery ?? {}) as Record<string, unknown>,
      requestedPickupAt: typeof body.requestedPickupAt === "string" ? body.requestedPickupAt : null,
      requestedDeliveryAt: typeof body.requestedDeliveryAt === "string" ? body.requestedDeliveryAt : null,
      specialInstructions: typeof body.specialInstructions === "string" ? body.specialInstructions : null,
      idempotencyKey: idempotencyKeyResult.data,
      actorAuthUserId: authorized.request.createdByAuthUserId,
      actorLabel: authorized.request.createdByAuthUserId,
    });
    statusCode = 201;
    responseBody = { booking };
  } catch (error) {
    statusCode = 422;
    responseBody = { error: buildApiError({ code: error instanceof CustomerBookingRequestMutationError ? error.code : "mutation_failed", message: error instanceof Error ? error.message : "Could not create this booking request.", requestId: authorized.request.correlationId }) };
  }

  await recordApiV1Success(authorized.request, { operation: "create_customer_booking_request_draft", httpMethod: "POST", path: "/api/v1/customer/bookings", statusCode, idempotencyKey: idempotencyKeyResult.data, startedAt });

  return Response.json(responseBody, { status: statusCode, headers: apiV1ResponseHeaders(authorized.request) });
}
