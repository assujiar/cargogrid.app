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
import { evaluateApiVersionRequest, type PublicApiPlatformQueryRpcClient } from "../../server/queries/public-api-platform.ts";
import { recordApiRequest, type ApiLogMutationRpcClient } from "../../server/mutations/api-log.ts";
import { buildApiError, API_VERSION, type ApiError } from "../../server/contracts/api/api.ts";
import type { ApiGatewayOutcome, ApiVersionRequestState } from "../../server/contracts/public-api-platform/public-api-platform.ts";

/**
 * ISS-2026-207: RFC 8594 deprecation signalling.
 *
 * `Deprecation: true` says the version is deprecated now; `Sunset: <HTTP-date>` says when it
 * stops answering. Both are advisory headers on an otherwise normal response, which is precisely
 * why the registry decision could not be folded into the auth outcome — a deprecated request
 * still succeeds, and the signal has to ride along with the success.
 */
export function apiVersionHeaders(state: ApiVersionRequestState): Record<string, string> {
  if (state.decision !== "deprecated") return {};
  const headers: Record<string, string> = { deprecation: "true" };
  if (state.sunsetAt) {
    const parsed = new Date(state.sunsetAt);
    // An unparseable stored date must not produce `Sunset: Invalid Date`. Better to send the
    // deprecation signal alone than a header a client cannot act on.
    if (!Number.isNaN(parsed.getTime())) headers.sunset = parsed.toUTCString();
  }
  return headers;
}

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
  /** IAE-011: only non-null for a vendor-scoped key -- a DATA-scope binding to one app.vendor_profiles row, never an actor identity (no vendor auth.users identity exists anywhere in this repository). */
  readonly vendorMasterRecordId: string | null;
  /** ISS-2026-207: RFC 8594 headers this request's own version state requires, empty when active. */
  readonly versionHeaders: Record<string, string>;
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

  // ISS-2026-207: the version gate runs BEFORE authentication, deliberately. Whether a caller's
  // key is valid is irrelevant to an endpoint that no longer exists, and answering "410 Gone"
  // only to holders of good keys would leave everyone else guessing. Version state is a published
  // contract fact, not a secret.
  const versionState = await evaluateApiVersionRequest(rpcClient, API_VERSION);

  if (versionState.decision === "gone") {
    await recordApiRequest(rpcClient, {
      correlationId, tenantId: null, actorAuthUserId: null, actorType: "anon", apiKeyId: null,
      interface: "rest", operation, httpMethod, path: url.pathname, statusCode: 410, result: "failure",
      errorCode: "api_version_gone", durationMs: Date.now() - startedAt,
    });
    return {
      ok: false,
      response: apiErrorResponse(
        410,
        "api_version_gone",
        `API version ${API_VERSION} has reached its sunset date and no longer accepts requests.`,
        correlationId,
      ),
    };
  }

  const authResult = await authenticateAndAuthorizeApiRequest(rpcClient, { rawKey, requiredScope });

  if (authResult.outcome !== "ok") {
    const statusCode = HTTP_STATUS_BY_DENIAL_OUTCOME[authResult.outcome];
    // RGL-401: an "unauthenticated" outcome means the presented key never resolved to a real
    // app.api_keys row, so authResult.apiKeyId is null -- logging actorType "api_key" with a
    // null apiKeyId violates app.api_logs' own api_logs_actor_shape_check constraint
    // ("api_key" requires a non-null api_key_id), crashing this entire request with an
    // uncaught 500 instead of the intended clean denial response. Only forbidden_scope/
    // rate_limited outcomes have a real, resolved apiKeyId -- unauthenticated never does.
    await recordApiRequest(rpcClient, {
      correlationId, tenantId: authResult.tenantId, actorAuthUserId: null, actorType: authResult.apiKeyId ? "api_key" : "anon", apiKeyId: authResult.apiKeyId,
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
      vendorMasterRecordId: authResult.vendorMasterRecordId,
      versionHeaders: apiVersionHeaders(versionState),
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

/**
 * Accepts the authorized request rather than only its correlation id, so a deprecated version's
 * RFC 8594 headers ride on every success response as well as on errors. The correlation-id
 * overload is kept because the denial paths above have no authorized request to pass.
 */
export function apiV1ResponseHeaders(source: string | AuthorizedApiV1Request): Record<string, string> {
  if (typeof source === "string") {
    return { "x-cargogrid-request-id": source, "x-cargogrid-api-version": API_VERSION };
  }
  return {
    "x-cargogrid-request-id": source.correlationId,
    "x-cargogrid-api-version": API_VERSION,
    ...source.versionHeaders,
  };
}
