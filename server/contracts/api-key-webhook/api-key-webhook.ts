/**
 * API key and webhook primitives contract (PLT-129, CG-S6-PLT-026). Mirrors
 * supabase/migrations/20260719150000_create_api_key_webhook_primitives.sql's
 * app.api_keys/app.webhook_event_types/app.webhook_endpoints/app.webhook_subscriptions/
 * app.webhook_deliveries/app.webhook_delivery_attempts shape and the
 * app.create_api_key / app.rotate_api_key / app.revoke_api_key / app.authenticate_api_key /
 * app.list_api_keys_for_tenant / app.register_webhook_event_type /
 * app.register_webhook_endpoint / app.rotate_webhook_secret / app.disable_webhook_endpoint /
 * app.reenable_webhook_endpoint / app.list_webhook_endpoints_for_tenant /
 * app.queue_webhook_delivery / app.record_webhook_delivery_attempt RPCs.
 *
 * A raw API key / webhook secret is never modeled as a persisted field here -- it only
 * ever appears in the one-time `rawKey`/`rawSecret` field of a create/rotate response
 * type, matching the migration's own "shown exactly once" design.
 */

import { z } from "zod";

export const API_KEY_STATUSES = ["active", "revoked", "expired"] as const;
export const ApiKeyStatusSchema = z.enum(API_KEY_STATUSES);
export type ApiKeyStatus = z.infer<typeof ApiKeyStatusSchema>;

export const WEBHOOK_ENDPOINT_STATUSES = ["active", "disabled"] as const;
export const WebhookEndpointStatusSchema = z.enum(WEBHOOK_ENDPOINT_STATUSES);
export type WebhookEndpointStatus = z.infer<typeof WebhookEndpointStatusSchema>;

export const WEBHOOK_DELIVERY_STATUSES = ["pending", "delivered", "dead_letter"] as const;
export const WebhookDeliveryStatusSchema = z.enum(WEBHOOK_DELIVERY_STATUSES);
export type WebhookDeliveryStatus = z.infer<typeof WebhookDeliveryStatusSchema>;

export const DELIVERY_ATTEMPT_STATUSES = ["success", "failed"] as const;
export const DeliveryAttemptStatusSchema = z.enum(DELIVERY_ATTEMPT_STATUSES);
export type DeliveryAttemptStatus = z.infer<typeof DeliveryAttemptStatusSchema>;

export const ApiKeySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  name: z.string(),
  keyPrefix: z.string(),
  scopes: z.array(z.string()),
  status: ApiKeyStatusSchema,
  rateLimitPerMinute: z.number().int().positive().nullable(),
  expiresAt: z.string().nullable(),
  lastUsedAt: z.string().nullable().optional(),
  createdAt: z.string(),
  updatedAt: z.string().optional(),
});
export type ApiKey = z.infer<typeof ApiKeySchema>;

export const CreatedApiKeySchema = ApiKeySchema.extend({ rawKey: z.string() });
export type CreatedApiKey = z.infer<typeof CreatedApiKeySchema>;

export const AuthenticatedApiKeySchema = z.object({
  apiKeyId: z.string().uuid(),
  tenantId: z.string().uuid(),
  scopes: z.array(z.string()),
  rateLimitPerMinute: z.number().int().positive().nullable(),
});
export type AuthenticatedApiKey = z.infer<typeof AuthenticatedApiKeySchema>;

export const WebhookEventTypeSchema = z.object({
  code: z.string(),
  name: z.string(),
  ownerPrimitiveCode: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type WebhookEventType = z.infer<typeof WebhookEventTypeSchema>;

export const WebhookEndpointSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  url: z.string(),
  status: WebhookEndpointStatusSchema,
  consecutiveFailureCount: z.number().int().nonnegative(),
  autoDisabledAt: z.string().nullable().optional(),
  disabledReason: z.string().nullable().optional(),
  createdAt: z.string(),
  updatedAt: z.string().optional(),
});
export type WebhookEndpoint = z.infer<typeof WebhookEndpointSchema>;

export const CreatedWebhookEndpointSchema = WebhookEndpointSchema.extend({ rawSecret: z.string() });
export type CreatedWebhookEndpoint = z.infer<typeof CreatedWebhookEndpointSchema>;

export const WebhookDeliverySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  webhookEndpointId: z.string().uuid(),
  eventTypeCode: z.string(),
  eventId: z.string().uuid(),
  payload: z.record(z.string(), z.unknown()),
  idempotencyKey: z.string(),
  status: WebhookDeliveryStatusSchema,
  attempts: z.number().int().nonnegative(),
  maxAttempts: z.number().int().positive(),
  nextAttemptAt: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WebhookDelivery = z.infer<typeof WebhookDeliverySchema>;

export const CreateApiKeyInputSchema = z.object({
  tenantId: z.string().uuid(),
  name: z.string().min(1),
  scopes: z.array(z.string().min(1)).min(1),
  expiresAt: z.string().nullable().default(null),
  rateLimitPerMinute: z.number().int().positive().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateApiKeyInput = z.input<typeof CreateApiKeyInputSchema>;

export const RotateApiKeyInputSchema = z.object({
  keyId: z.string().uuid(),
  overlapMinutes: z.number().int().min(0).max(10080),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RotateApiKeyInput = z.input<typeof RotateApiKeyInputSchema>;

export const RevokeApiKeyInputSchema = z.object({
  keyId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RevokeApiKeyInput = z.input<typeof RevokeApiKeyInputSchema>;

export const AuthenticateApiKeyInputSchema = z.object({
  rawKey: z.string().min(1),
});
export type AuthenticateApiKeyInput = z.input<typeof AuthenticateApiKeyInputSchema>;

export const ListApiKeysForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ListApiKeysForTenantInput = z.input<typeof ListApiKeysForTenantInputSchema>;

export const RegisterWebhookEventTypeInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  ownerPrimitiveCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterWebhookEventTypeInput = z.input<typeof RegisterWebhookEventTypeInputSchema>;

export const RegisterWebhookEndpointInputSchema = z.object({
  tenantId: z.string().uuid(),
  url: z.string().min(1),
  eventTypeCodes: z.array(z.string().min(1)).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RegisterWebhookEndpointInput = z.input<typeof RegisterWebhookEndpointInputSchema>;

export const RotateWebhookSecretInputSchema = z.object({
  endpointId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RotateWebhookSecretInput = z.input<typeof RotateWebhookSecretInputSchema>;

export const DisableWebhookEndpointInputSchema = z.object({
  endpointId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DisableWebhookEndpointInput = z.input<typeof DisableWebhookEndpointInputSchema>;

export const ReenableWebhookEndpointInputSchema = z.object({
  endpointId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReenableWebhookEndpointInput = z.input<typeof ReenableWebhookEndpointInputSchema>;

export const ListWebhookEndpointsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ListWebhookEndpointsForTenantInput = z.input<typeof ListWebhookEndpointsForTenantInputSchema>;

export const QueueWebhookDeliveryInputSchema = z.object({
  tenantId: z.string().uuid(),
  eventTypeCode: z.string().min(1),
  payload: z.record(z.string(), z.unknown()).default({}),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  triggeredBy: z.string().min(1),
});
export type QueueWebhookDeliveryInput = z.input<typeof QueueWebhookDeliveryInputSchema>;

export const RecordWebhookDeliveryAttemptInputSchema = z.object({
  deliveryId: z.string().uuid(),
  status: DeliveryAttemptStatusSchema,
  httpStatusCode: z.number().int().nullable().default(null),
  errorMessage: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordWebhookDeliveryAttemptInput = z.input<typeof RecordWebhookDeliveryAttemptInputSchema>;

/** Maps a raw app.api_keys(-shaped) row (snake_case) to this contract's camelCase shape. Never includes key_hash -- the RPC layer never selects it. */
export function parseApiKey(row: Record<string, unknown>): ApiKey {
  return ApiKeySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    keyPrefix: row.key_prefix,
    scopes: row.scopes,
    status: row.status,
    rateLimitPerMinute: row.rate_limit_per_minute,
    expiresAt: row.expires_at,
    lastUsedAt: row.last_used_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps app.create_api_key()/app.rotate_api_key()'s one-time return row, including raw_key. */
export function parseCreatedApiKey(row: Record<string, unknown>): CreatedApiKey {
  return CreatedApiKeySchema.parse({ ...parseApiKey(row), rawKey: row.raw_key });
}

export function parseAuthenticatedApiKey(row: Record<string, unknown>): AuthenticatedApiKey {
  return AuthenticatedApiKeySchema.parse({
    apiKeyId: row.api_key_id,
    tenantId: row.tenant_id,
    scopes: row.scopes,
    rateLimitPerMinute: row.rate_limit_per_minute,
  });
}

export function parseWebhookEventType(row: Record<string, unknown>): WebhookEventType {
  return WebhookEventTypeSchema.parse({
    code: row.code,
    name: row.name,
    ownerPrimitiveCode: row.owner_primitive_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Never includes secret_value -- the RPC layer never selects it. */
export function parseWebhookEndpoint(row: Record<string, unknown>): WebhookEndpoint {
  return WebhookEndpointSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    url: row.url,
    status: row.status,
    consecutiveFailureCount: row.consecutive_failure_count,
    autoDisabledAt: row.auto_disabled_at,
    disabledReason: row.disabled_reason,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps app.register_webhook_endpoint()/app.rotate_webhook_secret()'s one-time return row, including raw_secret. */
export function parseCreatedWebhookEndpoint(row: Record<string, unknown>): CreatedWebhookEndpoint {
  return CreatedWebhookEndpointSchema.parse({ ...parseWebhookEndpoint(row), rawSecret: row.raw_secret });
}

export function parseWebhookDelivery(row: Record<string, unknown>): WebhookDelivery {
  return WebhookDeliverySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    webhookEndpointId: row.webhook_endpoint_id,
    eventTypeCode: row.event_type_code,
    eventId: row.event_id,
    payload: row.payload,
    idempotencyKey: row.idempotency_key,
    status: row.status,
    attempts: row.attempts,
    maxAttempts: row.max_attempts,
    nextAttemptAt: row.next_attempt_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
