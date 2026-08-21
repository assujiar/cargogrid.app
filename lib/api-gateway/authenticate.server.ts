/**
 * Shared REST /v1 gateway authentication (IAE-009, Prompt 337). Every
 * `app/api/v1/**` route handler calls `authorizeApiV1Request()` first -- the one place
 * Bearer-key extraction, `app.authenticate_and_authorize_api_request()` (rate-limit +
 * scope enforcement), the `X-CargoGrid-Request-Id` correlation-id convention
 * (`server/contracts/api/api.ts`'s own header comment), and the standard `ApiError`
 * response shape (PLT-130) are composed once, so IAE-010/011/012's own `/v1` routes
 * reuse this instead of re-deriving auth/rate-limit/error-shape logic per capability.
 *
 * Never imported by a Client Component -- uses the service-role client
 * (`lib/supabase/service-role.ts`), the same "explicit actor, service-role execution"
 * pattern every other route handler and privileged Server Action in this repository
 * already uses.
 */

import { randomUUID } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../supabase/service-role.ts";
import { authenticateAndAuthorizeApiRequest, type PublicApiPlatformMutationRpcClient } from "../../server/mutations/public-api-platform.ts";
import type { PublicApiPlatformQueryRpcClient } from "../../server/queries/public-api-platform.ts";
import { recordApiRequest, type ApiLogMutationRpcClient } from "../../server/mutations/api-log.ts";
import { buildApiError, API_VERSION, type ApiError } from "../../server/contracts/api/api.ts";
import type { ApiGatewayOutcome } from "../../server/contracts/public-api-platform/public-api-platform.ts";

const HTTP_STATUS_BY_DENIAL_OUTCOME: Record<Exclude<ApiGatewayOutcome, "ok">, number> = {
  unauthenticated: 401,
  forbidden_scope: 403,
  rate_limited: 429,
};

const ERROR_MESSAGE_BY_DENIAL_OUTCOME: Record<Exclude<ApiGatewayOutcome, "ok">, string> = {
  unauthenticated: "The presented API key is missing, unknown, revoked, or expired.",
  forbidden_scope: "The presented API key does not carry the scope this endpoint requires.",
  rate_limited: "The presented API key has exceeded its own rate_limit_per_minute for the current window.",
};

export interface AuthorizedApiV1Request {
  readonly correlationId: string;
  readonly rpcClient: PublicApiPlatformMutationRpcClient & PublicApiPlatformQueryRpcClient & ApiLogMutationRpcClient;
  readonly apiKeyId: string;
  readonly tenantId: string;
  /** design decision 5 (20260804010000's own header): the presented key's own creator -- the real, accountable, live-re-checked actor identity a dispatched domain RPC call is made as. */
  readonly createdByAuthUserId: string;
  readonly rateLimitPerMinute: number | null;
  readonly rateLimitRemaining: number | null;
}

export type ApiV1AuthorizeResult = { readonly ok: true; readonly request: AuthorizedApiV1Request } | { readonly ok: false; readonly response: Response };

function apiErrorResponse(status: number, code: string, message: string, correlationId: string, extraHeaders?: Record<string, string>): Response {
  const body: ApiError = buildApiError({ code, message, requestId: correlationId });
  return Response.json(
    { error: body },
    { status, headers: { "x-cargogrid-request-id": correlationId, "x-cargogrid-api-version": API_VERSION, ...extraHeaders } },
  );
}

/**
 * Extracts the Bearer key, runs it through app.authenticate_and_authorize_api_request(),
 * and records exactly one app.api_logs row for a DENIED call before returning (a denial
 * is this function's own terminal outcome -- there is no further work the caller could
 * do). An `ok` outcome returns the authorized context WITHOUT logging yet -- the calling
 * route handler logs success itself via `recordApiV1Success()` once it knows its own
 * real HTTP status code and duration.
 */
export async function authorizeApiV1Request(request: Request, operation: string, requiredScope: string | null): Promise<ApiV1AuthorizeResult> {
  const startedAt = Date.now();
  const correlationId = randomUUID();
  const url = new URL(request.url);
  const httpMethod = request.method;
  const rpcClient = createSupabaseServiceRoleClient() as unknown as PublicApiPlatformMutationRpcClient & PublicApiPlatformQueryRpcClient & ApiLogMutationRpcClient;

  const authorizationHeader = request.headers.get("authorization") ?? "";
  const rawKey = authorizationHeader.startsWith("Bearer ") ? authorizationHeader.slice("Bearer ".length).trim() : "";

  if (rawKey.length === 0) {
    await recordApiRequest(rpcClient, {
      correlationId, tenantId: null, actorAuthUserId: null, actorType: "anon", apiKeyId: null,
      interface: "rest", operation, httpMethod, path: url.pathname, statusCode: 401, result: "failure",
      errorCode: "unauthenticated", durationMs: Date.now() - startedAt,
    });
    return { ok: false, response: apiErrorResponse(401, "unauthenticated", "A Bearer API key is required.", correlationId) };
  }

  const authResult = await authenticateAndAuthorizeApiRequest(rpcClient, { rawKey, requiredScope });

  if (authResult.outcome !== "ok") {
    const statusCode = HTTP_STATUS_BY_DENIAL_OUTCOME[authResult.outcome];
    await recordApiRequest(rpcClient, {
      correlationId, tenantId: authResult.tenantId, actorAuthUserId: null, actorType: "api_key", apiKeyId: authResult.apiKeyId,
      interface: "rest", operation, httpMethod, path: url.pathname, statusCode, result: "failure",
      errorCode: authResult.outcome, durationMs: Date.now() - startedAt,
    });
    return {
      ok: false,
      response: apiErrorResponse(statusCode, authResult.outcome, ERROR_MESSAGE_BY_DENIAL_OUTCOME[authResult.outcome], correlationId, statusCode === 429 ? { "retry-after": "60" } : undefined),
    };
  }

  // outcome === "ok" implies every field below is non-null (the migration's own
  // app.authenticate_and_authorize_api_request only omits them on a denial branch).
  return {
    ok: true,
    request: {
      correlationId,
      rpcClient,
      apiKeyId: authResult.apiKeyId as string,
      tenantId: authResult.tenantId as string,
      createdByAuthUserId: authResult.createdByAuthUserId as string,
      rateLimitPerMinute: authResult.rateLimitPerMinute,
      rateLimitRemaining: authResult.rateLimitRemaining,
    },
  };
}

/** The route handler's own success-path log call -- one app.api_logs row per accepted request, mirroring the denial path's own single-row discipline above. */
export async function recordApiV1Success(
  authorized: AuthorizedApiV1Request,
  params: { operation: string; httpMethod: string; path: string; statusCode: number; idempotencyKey?: string | null; startedAt: number },
): Promise<void> {
  await recordApiRequest(authorized.rpcClient, {
    correlationId: authorized.correlationId,
    tenantId: authorized.tenantId,
    actorAuthUserId: authorized.createdByAuthUserId,
    actorType: "api_key",
    apiKeyId: authorized.apiKeyId,
    interface: "rest",
    operation: params.operation,
    httpMethod: params.httpMethod,
    path: params.path,
    statusCode: params.statusCode,
    result: params.statusCode < 400 ? "success" : "failure",
    idempotencyKey: params.idempotencyKey ?? null,
    durationMs: Date.now() - params.startedAt,
  });
}

export function apiV1ResponseHeaders(correlationId: string): Record<string, string> {
  return { "x-cargogrid-request-id": correlationId, "x-cargogrid-api-version": API_VERSION };
}
