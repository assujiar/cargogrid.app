/**
 * GET /api/v1/webhook-event-types (IAE-009, Prompt 337). Lists the subscribable
 * webhook event registry (PLT-129's own app.webhook_event_types, read via this
 * capability's new app.list_webhook_event_types -- PLT-129 never shipped a list
 * function for its own broadly-readable registry). Requires INTHUB:View scope.
 * Zero real domain event type exists yet (IAE-012/Prompt 340 seeds the first ones) --
 * an empty array is this endpoint's own normal, documented response today, not an
 * error.
 */

import { authorizeApiV1Request, recordApiV1Success, apiV1ResponseHeaders } from "../../../../lib/api-gateway/authenticate.server.ts";
import { listWebhookEventTypes } from "../../../../server/queries/public-api-platform.ts";

export async function GET(request: Request): Promise<Response> {
  const startedAt = Date.now();
  const authorized = await authorizeApiV1Request(request, "list_webhook_event_types", "INTHUB:View");
  if (!authorized.ok) {
    return authorized.response;
  }

  const eventTypes = await listWebhookEventTypes(authorized.request.rpcClient);

  const statusCode = 200;
  await recordApiV1Success(authorized.request, { operation: "list_webhook_event_types", httpMethod: "GET", path: "/api/v1/webhook-event-types", statusCode, startedAt });

  return Response.json(
    { eventTypes: eventTypes.map((e) => ({ code: e.code, name: e.name, ownerPrimitiveCode: e.ownerPrimitiveCode })) },
    { status: statusCode, headers: apiV1ResponseHeaders(authorized.request) },
  );
}
