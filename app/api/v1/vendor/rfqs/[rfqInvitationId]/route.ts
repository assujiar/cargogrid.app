/**
 * GET /api/v1/vendor/rfqs/{rfqInvitationId} (IAE-011, Prompt 339). Wraps
 * app.get_rfq_for_vendor_api verbatim -- returns this vendor's own invitation
 * ONLY when the presented key's own vendor_master_record_id genuinely
 * matches (design decision 7); a mismatched or nonexistent id returns the
 * SAME 404, never disclosing which. Requires PRC:VendorPortal scope.
 */

import { authorizeApiV1Request, recordApiV1Success, apiV1ResponseHeaders, type AuthorizedApiV1Request } from "../../../../../../lib/api-gateway/authenticate.server.ts";
import { getRfqForVendorApi, VendorApiError, type VendorApiRpcClient } from "../../../../../../server/queries/vendor-api.ts";
import { buildApiError } from "../../../../../../server/contracts/api/api.ts";

/** See app/api/v1/vendor/rfqs/[rfqInvitationId]/response/route.ts's own toVendorApiClient() for why this cast is needed. */
function toVendorApiClient(rpcClient: AuthorizedApiV1Request["rpcClient"]): VendorApiRpcClient {
  return rpcClient as unknown as VendorApiRpcClient;
}

export async function GET(request: Request, { params }: { params: Promise<{ rfqInvitationId: string }> }): Promise<Response> {
  const startedAt = Date.now();
  const { rfqInvitationId } = await params;
  const authorized = await authorizeApiV1Request(request, "get_rfq_for_vendor_api", "PRC:VendorPortal");
  if (!authorized.ok) {
    return authorized.response;
  }

  let statusCode: number;
  let body: unknown;
  if (!authorized.request.vendorMasterRecordId) {
    statusCode = 403;
    body = { error: buildApiError({ code: "forbidden_scope", message: "This endpoint requires a vendor-scoped API key.", requestId: authorized.request.correlationId }) };
  } else {
    try {
      const rfq = await getRfqForVendorApi(toVendorApiClient(authorized.request.rpcClient), authorized.request.tenantId, authorized.request.vendorMasterRecordId, rfqInvitationId);
      statusCode = 200;
      body = { rfq };
    } catch (error) {
      if (error instanceof VendorApiError && error.code === "rfq_invitation_not_found") {
        statusCode = 404;
        body = { error: buildApiError({ code: "rfq_invitation_not_found", message: error.message, requestId: authorized.request.correlationId }) };
      } else {
        statusCode = 422;
        body = { error: buildApiError({ code: "mutation_failed", message: error instanceof Error ? error.message : "Could not retrieve this RFQ invitation.", requestId: authorized.request.correlationId }) };
      }
    }
  }

  await recordApiV1Success(authorized.request, { operation: "get_rfq_for_vendor_api", httpMethod: "GET", path: `/api/v1/vendor/rfqs/${rfqInvitationId}`, statusCode, startedAt });

  return Response.json(body, { status: statusCode, headers: apiV1ResponseHeaders(authorized.request.correlationId) });
}
