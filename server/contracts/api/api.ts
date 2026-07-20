/**
 * Shared REST/GraphQL platform API contract (PLT-130, CG-S6-PLT-027). The error shape,
 * pagination bounds, idempotency/correlation identifiers, and API version constant
 * every future REST route handler and GraphQL resolver reuse identically -- "Neither
 * interface is secondary or may bypass common service/access rules" (Prompt 130 §24).
 * Also mirrors supabase/migrations/20260719160000_create_api_foundation.sql's
 * app.api_logs shape and the app.record_api_request RPC.
 *
 * Error shape source: docs/architecture/08_API_INTEGRATION_WORKSTREAM.md line 74 (Tech
 * Arch §25.6) -- `error.code`, `error.message`, `error.details[]`, `error.request_id`,
 * `error.timestamp`, applied identically to a REST response body and a GraphQL error's
 * `extensions` object. `details[]`'s inner shape is not fixed by that document beyond
 * naming the field -- `ApiErrorDetailSchema` ({ field?, message }) is this checkpoint's
 * own disclosed, reasoned construction (a conventional field-level validation-detail
 * shape), not a blueprint-sourced structure.
 */

import { z } from "zod";

export const API_VERSION = "v1" as const;

export const API_INTERFACES = ["rest", "graphql"] as const;
export const ApiInterfaceSchema = z.enum(API_INTERFACES);
export type ApiInterface = z.infer<typeof ApiInterfaceSchema>;

export const API_ACTOR_TYPES = ["user", "api_key", "service_role", "anon"] as const;
export const ApiActorTypeSchema = z.enum(API_ACTOR_TYPES);
export type ApiActorType = z.infer<typeof ApiActorTypeSchema>;

export const API_LOG_RESULTS = ["success", "failure"] as const;
export const ApiLogResultSchema = z.enum(API_LOG_RESULTS);
export type ApiLogResult = z.infer<typeof ApiLogResultSchema>;

/** Tech Arch §25.6 (docs/architecture/08_API_INTEGRATION_WORKSTREAM.md line 74), applied identically to REST response bodies and GraphQL error extensions. */
export const ApiErrorDetailSchema = z.object({
  field: z.string().nullable().default(null),
  message: z.string(),
});
export type ApiErrorDetail = z.infer<typeof ApiErrorDetailSchema>;

export const ApiErrorSchema = z.object({
  code: z.string().min(1),
  message: z.string().min(1),
  details: z.array(ApiErrorDetailSchema).default([]),
  requestId: z.string().uuid(),
  timestamp: z.string(),
});
export type ApiError = z.infer<typeof ApiErrorSchema>;

/** Builds a well-formed ApiError -- the one place both a REST error handler and a GraphQL error formatter construct this shape, so they can never drift apart. */
export function buildApiError(input: { code: string; message: string; details?: ApiErrorDetail[]; requestId: string; now?: Date }): ApiError {
  return ApiErrorSchema.parse({
    code: input.code,
    message: input.message,
    details: input.details ?? [],
    requestId: input.requestId,
    timestamp: (input.now ?? new Date()).toISOString(),
  });
}

/** docs/architecture/08_API_INTEGRATION_WORKSTREAM.md line 60: offset for small stable lists, cursor for large changing lists, keyset mandatory for high-volume append-ordered tables. Page size is bounded to prevent an unbounded-payload query (Prompt 130 §17). */
export const MAX_PAGE_SIZE = 100;
export const DEFAULT_PAGE_SIZE = 20;

export const CursorPaginationParamsSchema = z.object({
  cursor: z.string().nullable().default(null),
  limit: z.number().int().positive().max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE),
});
export type CursorPaginationParams = z.input<typeof CursorPaginationParamsSchema>;

export const OffsetPaginationParamsSchema = z.object({
  offset: z.number().int().nonnegative().default(0),
  limit: z.number().int().positive().max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE),
});
export type OffsetPaginationParams = z.input<typeof OffsetPaginationParamsSchema>;

export const PageInfoSchema = z.object({
  hasNextPage: z.boolean(),
  hasPreviousPage: z.boolean(),
  nextCursor: z.string().nullable(),
  previousCursor: z.string().nullable(),
});
export type PageInfo = z.infer<typeof PageInfoSchema>;

/** A generic paginated envelope both REST list endpoints and GraphQL connection fields return -- one shape, not two competing ones. */
export function paginatedResultSchema<T extends z.ZodTypeAny>(itemSchema: T) {
  return z.object({
    items: z.array(itemSchema),
    pageInfo: PageInfoSchema,
  });
}
export type PaginatedResult<T> = { items: T[]; pageInfo: PageInfo };

/** docs/architecture/08_API_INTEGRATION_WORKSTREAM.md lines 76-78: required on every external-facing REST POST/PUT/PATCH and GraphQL mutation, stored on the target table's own idempotency_key column. */
export const IdempotencyKeySchema = z.string().min(1).max(255);

/** The value both an X-CargoGrid-Request-Id header and app.capture_audit_event()'s p_correlation_id thread through -- one request's full downstream effect traceable across app.api_logs/app.audit_logs/etc. */
export const CorrelationIdSchema = z.string().uuid();

export const ApiLogSchema = z.object({
  id: z.string().uuid(),
  correlationId: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorType: ApiActorTypeSchema,
  apiKeyId: z.string().uuid().nullable(),
  interface: ApiInterfaceSchema,
  operation: z.string(),
  httpMethod: z.string().nullable(),
  path: z.string().nullable(),
  graphqlOperationName: z.string().nullable(),
  statusCode: z.number().int().nullable(),
  result: ApiLogResultSchema,
  errorCode: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  durationMs: z.number().int().nullable(),
  createdAt: z.string(),
});
export type ApiLog = z.infer<typeof ApiLogSchema>;

export const RecordApiRequestInputSchema = z.object({
  correlationId: CorrelationIdSchema,
  tenantId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid().nullable().default(null),
  actorType: ApiActorTypeSchema,
  apiKeyId: z.string().uuid().nullable().default(null),
  interface: ApiInterfaceSchema,
  operation: z.string().min(1),
  httpMethod: z.string().nullable().default(null),
  path: z.string().nullable().default(null),
  graphqlOperationName: z.string().nullable().default(null),
  statusCode: z.number().int().nullable().default(null),
  result: ApiLogResultSchema,
  errorCode: z.string().nullable().default(null),
  idempotencyKey: z.string().nullable().default(null),
  durationMs: z.number().int().nullable().default(null),
});
export type RecordApiRequestInput = z.input<typeof RecordApiRequestInputSchema>;

/** Maps a raw app.api_logs row (snake_case) to this contract's camelCase shape. */
export function parseApiLog(row: Record<string, unknown>): ApiLog {
  return ApiLogSchema.parse({
    id: row.id,
    correlationId: row.correlation_id,
    tenantId: row.tenant_id,
    actorAuthUserId: row.actor_auth_user_id,
    actorType: row.actor_type,
    apiKeyId: row.api_key_id,
    interface: row.interface,
    operation: row.operation,
    httpMethod: row.http_method,
    path: row.path,
    graphqlOperationName: row.graphql_operation_name,
    statusCode: row.status_code,
    result: row.result,
    errorCode: row.error_code,
    idempotencyKey: row.idempotency_key,
    durationMs: row.duration_ms,
    createdAt: row.created_at,
  });
}
