/**
 * POST /api/v1/vendor/assignments/{invitationId}/decline (IAE-011, Prompt 339).
 * Wraps app.decline_vendor_assignment_invitation_via_vendor_api -- mirrors
 * ../accept/route.ts's own vendor-scope authority, requiring a non-empty
 * reason. Requires PRC:VendorPortal scope.
 */

import { authorizeApiV1Request, recordApiV1Success, apiV1ResponseHeaders, type AuthorizedApiV1Request } from "../../../../../../../lib/api-gateway/authenticate.server.ts";
import { declineVendorAssignmentInvitationViaVendorApi, VendorApiMutationError, type VendorApiMutationRpcClient } from "../../../../../../../server/mutations/vendor-api.ts";
import { buildApiError } from "../../../../../../../server/contracts/api/api.ts";

/** See app/api/v1/vendor/rfqs/[rfqInvitationId]/response/route.ts's own toVendorApiClient() for why this cast is needed. */
function toVendorApiClient(rpcClient: AuthorizedApiV1Request["rpcClient"]): VendorApiMutationRpcClient {
  return rpcClient as unknown as VendorApiMutationRpcClient;
}

interface DeclineBody {
  expectedVersion?: unknown;
  reason?: unknown;
}

export async function POST(request: Request, { params }: { params: Promise<{ invitationId: string }> }): Promise<Response> {
  const startedAt = Date.now();
  const { invitationId } = await params;
  const authorized = await authorizeApiV1Request(request, "decline_vendor_assignment_invitation_via_vendor_api", "PRC:VendorPortal");
  if (!authorized.ok) {
    return authorized.response;
  }

  let body: DeclineBody;
  try {
    body = (await request.json()) as DeclineBody;
  } catch {
    body = {};
  }
  const expectedVersion = typeof body.expectedVersion === "number" ? body.expectedVersion : Number(body.expectedVersion);
  const reason = typeof body.reason === "string" ? body.reason : "";

  let statusCode: number;
  let responseBody: unknown;
  if (!authorized.request.vendorMasterRecordId) {
    statusCode = 403;
    responseBody = { error: buildApiError({ code: "forbidden_scope", message: "This endpoint requires a vendor-scoped API key.", requestId: authorized.request.correlationId }) };
  } else if (!Number.isInteger(expectedVersion) || expectedVersion <= 0) {
    statusCode = 400;
    responseBody = { error: buildApiError({ code: "invalid_expected_version", message: "A positive integer expectedVersion is required.", requestId: authorized.request.correlationId }) };
  } else {
    try {
      const invitation = await declineVendorAssignmentInvitationViaVendorApi(toVendorApiClient(authorized.request.rpcClient), {
        tenantId: authorized.request.tenantId,
        vendorMasterRecordId: authorized.request.vendorMasterRecordId,
        invitationId,
        expectedVersion,
        reason,
      });
      statusCode = 200;
      responseBody = { invitation };
    } catch (error) {
      statusCode = error instanceof VendorApiMutationError && error.code === "stale_version" ? 409 : error instanceof VendorApiMutationError && error.code === "vendor_assignment_invitation_not_found" ? 404 : 422;
      responseBody = { error: buildApiError({ code: error instanceof VendorApiMutationError ? error.code : "mutation_failed", message: error instanceof Error ? error.message : "Could not decline this assignment invitation.", requestId: authorized.request.correlationId }) };
    }
  }

  await recordApiV1Success(authorized.request, { operation: "decline_vendor_assignment_invitation_via_vendor_api", httpMethod: "POST", path: `/api/v1/vendor/assignments/${invitationId}/decline`, statusCode, startedAt });

  return Response.json(responseBody, { status: statusCode, headers: apiV1ResponseHeaders(authorized.request.correlationId) });
}
