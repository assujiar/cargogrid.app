/**
 * GET /api/v1/status (IAE-009, Prompt 337). The public API platform's own version/
 * deprecation introspection resource -- requires a valid API key (any scope; passing
 * `requiredScope: null` to the gateway) but no INTHUB-specific authority, so any issued
 * key can always check compatibility before calling a scoped resource.
 */

import { authorizeApiV1Request, recordApiV1Success, apiV1ResponseHeaders } from "../../../../lib/api-gateway/authenticate.server.ts";
import { listApiVersions } from "../../../../server/queries/public-api-platform.ts";

export async function GET(request: Request): Promise<Response> {
  const startedAt = Date.now();
  const authorized = await authorizeApiV1Request(request, "get_status", null);
  if (!authorized.ok) {
    return authorized.response;
  }

  const versions = await listApiVersions(authorized.request.rpcClient);

  const statusCode = 200;
  await recordApiV1Success(authorized.request, { operation: "get_status", httpMethod: "GET", path: "/api/v1/status", statusCode, startedAt });

  return Response.json(
    {
      versions: versions.map((v) => ({ code: v.code, status: v.status, sunsetAt: v.sunsetAt, notes: v.notes })),
      rateLimit: { limitPerMinute: authorized.request.rateLimitPerMinute, remaining: authorized.request.rateLimitRemaining },
    },
    { status: statusCode, headers: apiV1ResponseHeaders(authorized.request) },
  );
}
