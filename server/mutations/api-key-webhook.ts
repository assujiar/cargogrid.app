/**
 * API key and webhook primitives mutation entry points (PLT-129, CG-S6-PLT-026). Thin,
 * typed wrappers around app.create_api_key / app.rotate_api_key / app.revoke_api_key /
 * app.authenticate_api_key / app.register_webhook_event_type /
 * app.register_webhook_endpoint / app.rotate_webhook_secret /
 * app.disable_webhook_endpoint / app.reenable_webhook_endpoint /
 * app.queue_webhook_delivery / app.record_webhook_delivery_attempt
 * (supabase/migrations/20260719150000_create_api_key_webhook_primitives.sql). Every one
 * of these is service_role-only (see the migration's own grant comment and header) --
 * this capability is server-mediated only, the same design PLT-128 established.
 */

import {
  CreateApiKeyInputSchema,
  RotateApiKeyInputSchema,
  RevokeApiKeyInputSchema,
  AuthenticateApiKeyInputSchema,
  RegisterWebhookEventTypeInputSchema,
  RegisterWebhookEndpointInputSchema,
  RotateWebhookSecretInputSchema,
  DisableWebhookEndpointInputSchema,
  ReenableWebhookEndpointInputSchema,
  QueueWebhookDeliveryInputSchema,
  RecordWebhookDeliveryAttemptInputSchema,
  parseCreatedApiKey,
  parseApiKey,
  parseAuthenticatedApiKey,
  parseWebhookEventType,
  parseCreatedWebhookEndpoint,
  parseWebhookEndpoint,
  parseWebhookDelivery,
  type CreateApiKeyInput,
  type RotateApiKeyInput,
  type RevokeApiKeyInput,
  type AuthenticateApiKeyInput,
  type RegisterWebhookEventTypeInput,
  type RegisterWebhookEndpointInput,
  type RotateWebhookSecretInput,
  type DisableWebhookEndpointInput,
  type ReenableWebhookEndpointInput,
  type QueueWebhookDeliveryInput,
  type RecordWebhookDeliveryAttemptInput,
  type ApiKey,
  type CreatedApiKey,
  type AuthenticatedApiKey,
  type WebhookEventType,
  type WebhookEndpoint,
  type CreatedWebhookEndpoint,
  type WebhookDelivery,
} from "../contracts/api-key-webhook/api-key-webhook.ts";

export interface ApiKeyWebhookMutationRpcClient {
  rpc(
    fn:
      | "create_api_key"
      | "rotate_api_key"
      | "revoke_api_key"
      | "authenticate_api_key"
      | "register_webhook_event_type"
      | "register_webhook_endpoint"
      | "rotate_webhook_secret"
      | "disable_webhook_endpoint"
      | "reenable_webhook_endpoint"
      | "queue_webhook_delivery"
      | "record_webhook_delivery_attempt",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const API_KEY_WEBHOOK_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "api_key_missing_name",
  "api_key_missing_scopes",
  "api_key_invalid_scope_format",
  "api_key_scope_exceeds_actor_authority",
  "api_key_invalid_rate_limit",
  "api_key_invalid_expiry",
  "api_key_not_found",
  "api_key_not_active",
  "api_key_invalid_overlap_minutes",
  "api_key_revoked",
  "api_key_expired",
  "webhook_missing_event_types",
  "webhook_unknown_event_type",
  "webhook_invalid_url_scheme",
  "webhook_unsafe_url_host",
  "webhook_endpoint_not_found",
  "webhook_actor_unauthorized",
  "webhook_unsafe_payload",
  "webhook_missing_idempotency_key",
  "webhook_delivery_not_found",
  "webhook_delivery_already_terminal",
  "webhook_invalid_attempt_status",
] as const;
type KnownApiKeyWebhookMutationErrorCode = (typeof API_KEY_WEBHOOK_KNOWN_MUTATION_ERROR_CODES)[number];
export type ApiKeyWebhookMutationErrorCode = KnownApiKeyWebhookMutationErrorCode | "mutation_failed" | "invalid_response";

export class ApiKeyWebhookMutationError extends Error {
  readonly code: ApiKeyWebhookMutationErrorCode;

  constructor(code: ApiKeyWebhookMutationErrorCode, message: string) {
    super(message);
    this.name = "ApiKeyWebhookMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ApiKeyWebhookMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (API_KEY_WEBHOOK_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownApiKeyWebhookMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Every requested scope must already be held by the actor via app.evaluate_permission() -- can only narrow, never widen. Returns the raw key exactly once. */
export async function createApiKey(client: ApiKeyWebhookMutationRpcClient, input: CreateApiKeyInput): Promise<CreatedApiKey> {
  const parsedInput = CreateApiKeyInputSchema.parse(input);
  const { data, error } = await client.rpc("create_api_key", {
    p_tenant_id: parsedInput.tenantId,
    p_name: parsedInput.name,
    p_scopes: parsedInput.scopes,
    p_expires_at: parsedInput.expiresAt,
    p_rate_limit_per_minute: parsedInput.rateLimitPerMinute,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ApiKeyWebhookMutationError("invalid_response", "create_api_key returned no row");
  }
  return parseCreatedApiKey(row);
}

/** Overlap-window rotation: the old key remains valid for at most overlapMinutes longer (0 = immediate revoke), never extending an already-sooner expiry. Returns the new raw key exactly once. */
export async function rotateApiKey(client: ApiKeyWebhookMutationRpcClient, input: RotateApiKeyInput): Promise<CreatedApiKey> {
  const parsedInput = RotateApiKeyInputSchema.parse(input);
  const { data, error } = await client.rpc("rotate_api_key", {
    p_key_id: parsedInput.keyId,
    p_overlap_minutes: parsedInput.overlapMinutes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ApiKeyWebhookMutationError("invalid_response", "rotate_api_key returned no row");
  }
  return parseCreatedApiKey(row);
}

/** Idempotent -- a repeated revoke of an already-revoked key returns it unchanged. */
export async function revokeApiKey(client: ApiKeyWebhookMutationRpcClient, input: RevokeApiKeyInput): Promise<ApiKey> {
  const parsedInput = RevokeApiKeyInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_api_key", {
    p_key_id: parsedInput.keyId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApiKeyWebhookMutationError("invalid_response", "revoke_api_key returned no row");
  }
  return parseApiKey(data as Record<string, unknown>);
}

/** The real authentication entry point a future API-gateway middleware would call (disclosed NOT_RUN as a live HTTP consumer -- no such gateway exists yet). */
export async function authenticateApiKey(client: ApiKeyWebhookMutationRpcClient, input: AuthenticateApiKeyInput): Promise<AuthenticatedApiKey> {
  const parsedInput = AuthenticateApiKeyInputSchema.parse(input);
  const { data, error } = await client.rpc("authenticate_api_key", { p_raw_key: parsedInput.rawKey });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ApiKeyWebhookMutationError("invalid_response", "authenticate_api_key returned no row");
  }
  return parseAuthenticatedApiKey(row);
}

/** Idempotent -- Supreme-Admin-only. */
export async function registerWebhookEventType(client: ApiKeyWebhookMutationRpcClient, input: RegisterWebhookEventTypeInput): Promise<WebhookEventType> {
  const parsedInput = RegisterWebhookEventTypeInputSchema.parse(input);
  const { data, error } = await client.rpc("register_webhook_event_type", {
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_owner_primitive_code: parsedInput.ownerPrimitiveCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApiKeyWebhookMutationError("invalid_response", "register_webhook_event_type returned no row");
  }
  return parseWebhookEventType(data as Record<string, unknown>);
}

/** Validates the URL against a bounded, disclosed-partial SSRF check (https-only, rejects literal localhost/private/link-local hosts) and every event_type_code against the registry. Returns the raw signing secret exactly once. */
export async function registerWebhookEndpoint(client: ApiKeyWebhookMutationRpcClient, input: RegisterWebhookEndpointInput): Promise<CreatedWebhookEndpoint> {
  const parsedInput = RegisterWebhookEndpointInputSchema.parse(input);
  const { data, error } = await client.rpc("register_webhook_endpoint", {
    p_tenant_id: parsedInput.tenantId,
    p_url: parsedInput.url,
    p_event_type_codes: parsedInput.eventTypeCodes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ApiKeyWebhookMutationError("invalid_response", "register_webhook_endpoint returned no row");
  }
  return parseCreatedWebhookEndpoint(row);
}

/** Returns the new raw signing secret exactly once. */
export async function rotateWebhookSecret(client: ApiKeyWebhookMutationRpcClient, input: RotateWebhookSecretInput): Promise<CreatedWebhookEndpoint> {
  const parsedInput = RotateWebhookSecretInputSchema.parse(input);
  const { data, error } = await client.rpc("rotate_webhook_secret", {
    p_endpoint_id: parsedInput.endpointId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ApiKeyWebhookMutationError("invalid_response", "rotate_webhook_secret returned no row");
  }
  return parseCreatedWebhookEndpoint(row);
}

/** Idempotent. */
export async function disableWebhookEndpoint(client: ApiKeyWebhookMutationRpcClient, input: DisableWebhookEndpointInput): Promise<WebhookEndpoint> {
  const parsedInput = DisableWebhookEndpointInputSchema.parse(input);
  const { data, error } = await client.rpc("disable_webhook_endpoint", {
    p_endpoint_id: parsedInput.endpointId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApiKeyWebhookMutationError("invalid_response", "disable_webhook_endpoint returned no row");
  }
  return parseWebhookEndpoint(data as Record<string, unknown>);
}

/** Resets the consecutive-failure counter -- the operator is asserting the endpoint is now believed healthy. */
export async function reenableWebhookEndpoint(client: ApiKeyWebhookMutationRpcClient, input: ReenableWebhookEndpointInput): Promise<WebhookEndpoint> {
  const parsedInput = ReenableWebhookEndpointInputSchema.parse(input);
  const { data, error } = await client.rpc("reenable_webhook_endpoint", {
    p_endpoint_id: parsedInput.endpointId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApiKeyWebhookMutationError("invalid_response", "reenable_webhook_endpoint returned no row");
  }
  return parseWebhookEndpoint(data as Record<string, unknown>);
}

/** Idempotent per (tenant, endpoint, idempotencyKey). Fans out to every active endpoint subscribed to eventTypeCode -- an empty array is a normal, non-error outcome when nobody is subscribed. */
export async function queueWebhookDelivery(client: ApiKeyWebhookMutationRpcClient, input: QueueWebhookDeliveryInput): Promise<WebhookDelivery[]> {
  const parsedInput = QueueWebhookDeliveryInputSchema.parse(input);
  const { data, error } = await client.rpc("queue_webhook_delivery", {
    p_tenant_id: parsedInput.tenantId,
    p_event_type_code: parsedInput.eventTypeCode,
    p_payload: parsedInput.payload,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_triggered_by: parsedInput.triggeredBy,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  if (!Array.isArray(data)) {
    throw new ApiKeyWebhookMutationError("invalid_response", "queue_webhook_delivery returned a non-array result");
  }
  return data.map((row) => parseWebhookDelivery(row as Record<string, unknown>));
}

/** The bounded delivery adapter interface a real delivery worker calls to report one HTTP attempt's outcome -- this repository never calls it against a fabricated HTTP response itself. */
export async function recordWebhookDeliveryAttempt(client: ApiKeyWebhookMutationRpcClient, input: RecordWebhookDeliveryAttemptInput): Promise<WebhookDelivery> {
  const parsedInput = RecordWebhookDeliveryAttemptInputSchema.parse(input);
  const { data, error } = await client.rpc("record_webhook_delivery_attempt", {
    p_delivery_id: parsedInput.deliveryId,
    p_status: parsedInput.status,
    p_http_status_code: parsedInput.httpStatusCode,
    p_error_message: parsedInput.errorMessage,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApiKeyWebhookMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApiKeyWebhookMutationError("invalid_response", "record_webhook_delivery_attempt returned no row");
  }
  return parseWebhookDelivery(data as Record<string, unknown>);
}
