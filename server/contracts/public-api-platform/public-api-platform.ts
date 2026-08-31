/**
 * Public API Platform contract (IAE-009, Prompt 337). Mirrors
 * supabase/migrations/20260804010000_create_intelligence_public_api_platform.sql's
 * app.api_versions shape and the app.authenticate_and_authorize_api_request /
 * app.register_api_version / app.set_api_version_status RPCs. Reuses
 * ../api-key-webhook/api-key-webhook.ts's own WebhookEventType/parseWebhookEventType
 * for app.list_webhook_event_types, and ../api/api.ts's own ApiLog/parseApiLog for
 * app.list_api_logs_for_tenant -- neither is re-declared here.
 */

import { z } from "zod";

export const API_VERSION_STATUSES = ["active", "deprecated", "sunset"] as const;
export const ApiVersionStatusSchema = z.enum(API_VERSION_STATUSES);
export type ApiVersionStatus = z.infer<typeof ApiVersionStatusSchema>;

export const ApiVersionSchema = z.object({
  code: z.string(),
  status: ApiVersionStatusSchema,
  sunsetAt: z.string().nullable(),
  notes: z.string().nullable(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ApiVersion = z.infer<typeof ApiVersionSchema>;

export function parseApiVersion(row: Record<string, unknown>): ApiVersion {
  return ApiVersionSchema.parse({
    code: row.code,
    status: row.status,
    sunsetAt: row.sunset_at,
    notes: row.notes,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RegisterApiVersionInputSchema = z.object({
  code: z.string().min(1),
  status: ApiVersionStatusSchema.default("active"),
  sunsetAt: z.string().nullable().default(null),
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterApiVersionInput = z.input<typeof RegisterApiVersionInputSchema>;

export const SetApiVersionStatusInputSchema = z.object({
  code: z.string().min(1),
  status: ApiVersionStatusSchema,
  sunsetAt: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetApiVersionStatusInput = z.input<typeof SetApiVersionStatusInputSchema>;

/** The four routine, non-exceptional outcomes app.authenticate_and_authorize_api_request reports -- never thrown for any of these. */
export const API_GATEWAY_OUTCOMES = ["ok", "unauthenticated", "forbidden_scope", "rate_limited"] as const;
export const ApiGatewayOutcomeSchema = z.enum(API_GATEWAY_OUTCOMES);
export type ApiGatewayOutcome = z.infer<typeof ApiGatewayOutcomeSchema>;

export const AuthenticateAndAuthorizeApiRequestInputSchema = z.object({
  rawKey: z.string().min(1),
  requiredScope: z.string().nullable().default(null),
});
export type AuthenticateAndAuthorizeApiRequestInput = z.input<typeof AuthenticateAndAuthorizeApiRequestInputSchema>;

export const AuthenticateAndAuthorizeApiRequestResultSchema = z.object({
  outcome: ApiGatewayOutcomeSchema,
  apiKeyId: z.string().uuid().nullable(),
  tenantId: z.string().uuid().nullable(),
  /** Only populated when outcome === "ok" -- the downstream actor identity a dispatched domain RPC call is made as (design decision 5: the key's own creator, a real, accountable, live-re-checked identity). */
  createdByAuthUserId: z.string().uuid().nullable(),
  rateLimitPerMinute: z.number().int().nullable(),
  rateLimitRemaining: z.number().int().nullable(),
  /** IAE-011: only populated for a vendor-scoped key -- a DATA-scope binding, never an actor identity (no vendor auth.users identity exists). Never coalesced into createdByAuthUserId. */
  vendorMasterRecordId: z.string().uuid().nullable(),
});
export type AuthenticateAndAuthorizeApiRequestResult = z.infer<typeof AuthenticateAndAuthorizeApiRequestResultSchema>;

export function parseAuthenticateAndAuthorizeApiRequestResult(row: Record<string, unknown>): AuthenticateAndAuthorizeApiRequestResult {
  return AuthenticateAndAuthorizeApiRequestResultSchema.parse({
    outcome: row.outcome,
    apiKeyId: row.api_key_id,
    tenantId: row.tenant_id,
    createdByAuthUserId: row.created_by_auth_user_id,
    rateLimitPerMinute: row.rate_limit_per_minute,
    rateLimitRemaining: row.rate_limit_remaining,
    vendorMasterRecordId: row.vendor_master_record_id ?? null,
  });
}

/**
 * ISS-2026-207: the request-time decision `app.api_versions` now drives.
 *
 *   ok         — serve normally.
 *   deprecated — serve, and emit RFC 8594 `Deprecation`/`Sunset` headers.
 *   gone       — refuse with 410; the version is past its announced sunset, or unknown.
 */
export const ApiVersionDecisionSchema = z.enum(["ok", "deprecated", "gone"]);
export type ApiVersionDecision = z.infer<typeof ApiVersionDecisionSchema>;

export const ApiVersionRequestStateSchema = z.object({
  decision: ApiVersionDecisionSchema,
  status: z.string(),
  sunsetAt: z.string().nullable(),
});
export type ApiVersionRequestState = z.infer<typeof ApiVersionRequestStateSchema>;

export function parseApiVersionRequestState(row: Record<string, unknown>): ApiVersionRequestState {
  return ApiVersionRequestStateSchema.parse({
    decision: row.decision,
    status: row.status,
    sunsetAt: row.sunset_at ?? null,
  });
}

export const ListApiLogsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  limit: z.number().int().positive().max(100).default(20),
  before: z.string().nullable().default(null),
  /**
   * ISS-2026-147 item 2: the per-connector filter. An integration authenticates with its own
   * API key, so scoping to a key id is what "this connector's execution history" means here.
   * Null keeps the tenant-wide list, which is what every pre-existing caller gets.
   */
  apiKeyId: z.string().uuid().nullable().default(null),
});
export type ListApiLogsForTenantInput = z.input<typeof ListApiLogsForTenantInputSchema>;
