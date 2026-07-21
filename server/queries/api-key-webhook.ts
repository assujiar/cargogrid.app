/**
 * API key and webhook primitives read queries (PLT-129, CG-S6-PLT-026). Thin, typed
 * wrappers around app.list_api_keys_for_tenant / app.list_webhook_endpoints_for_tenant /
 * app.api_key_has_scope / app.compute_webhook_signature / app.verify_webhook_signature
 * (supabase/migrations/20260719150000_create_api_key_webhook_primitives.sql). The two
 * list functions are `authenticated`-callable (SECURITY DEFINER, authority-gated,
 * excluding key_hash/secret_value from their result shape entirely); the remaining
 * three are service_role-only, matching the migration's own server-mediated design.
 */

import {
  ListApiKeysForTenantInputSchema,
  ListWebhookEndpointsForTenantInputSchema,
  parseApiKey,
  parseWebhookEndpoint,
  type ListApiKeysForTenantInput,
  type ListWebhookEndpointsForTenantInput,
  type ApiKey,
  type WebhookEndpoint,
} from "../contracts/api-key-webhook/api-key-webhook.ts";

export interface ApiKeyWebhookQueryRpcClient {
  rpc(
    fn: "list_api_keys_for_tenant" | "list_webhook_endpoints_for_tenant" | "api_key_has_scope" | "compute_webhook_signature" | "verify_webhook_signature",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class ApiKeyWebhookQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ApiKeyWebhookQueryError";
  }
}

/** Never includes key_hash -- the function's own result shape structurally excludes it. */
export async function listApiKeysForTenant(client: ApiKeyWebhookQueryRpcClient, input: ListApiKeysForTenantInput): Promise<ApiKey[]> {
  const parsedInput = ListApiKeysForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_api_keys_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ApiKeyWebhookQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ApiKeyWebhookQueryError("list_api_keys_for_tenant returned a non-array result");
  }
  return data.map((row) => parseApiKey(row as Record<string, unknown>));
}

/** Never includes secret_value -- the function's own result shape structurally excludes it. */
export async function listWebhookEndpointsForTenant(client: ApiKeyWebhookQueryRpcClient, input: ListWebhookEndpointsForTenantInput): Promise<WebhookEndpoint[]> {
  const parsedInput = ListWebhookEndpointsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_webhook_endpoints_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ApiKeyWebhookQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ApiKeyWebhookQueryError("list_webhook_endpoints_for_tenant returned a non-array result");
  }
  return data.map((row) => parseWebhookEndpoint(row as Record<string, unknown>));
}

export async function apiKeyHasScope(client: ApiKeyWebhookQueryRpcClient, apiKeyId: string, scope: string): Promise<boolean> {
  const { data, error } = await client.rpc("api_key_has_scope", { p_api_key_id: apiKeyId, p_scope: scope });
  if (error) {
    throw new ApiKeyWebhookQueryError(error.message);
  }
  if (typeof data !== "boolean") {
    throw new ApiKeyWebhookQueryError("api_key_has_scope returned a non-boolean result");
  }
  return data;
}

/** ADR-0011: HMAC-SHA256 over "<unix_timestamp>.<payload>" -- pure cryptographic computation, no live HTTP call involved. */
export async function computeWebhookSignature(client: ApiKeyWebhookQueryRpcClient, endpointId: string, payload: string, timestamp: number): Promise<string> {
  const { data, error } = await client.rpc("compute_webhook_signature", { p_endpoint_id: endpointId, p_payload: payload, p_timestamp: timestamp });
  if (error) {
    throw new ApiKeyWebhookQueryError(error.message);
  }
  if (typeof data !== "string") {
    throw new ApiKeyWebhookQueryError("compute_webhook_signature returned a non-string result");
  }
  return data;
}

/** ADR-0011: recomputes and compares, plus the 5-minute timestamp-tolerance replay check. Fails closed to false, never throws on a tampered payload or stale timestamp. */
export async function verifyWebhookSignature(client: ApiKeyWebhookQueryRpcClient, endpointId: string, payload: string, timestamp: number, signature: string): Promise<boolean> {
  const { data, error } = await client.rpc("verify_webhook_signature", { p_endpoint_id: endpointId, p_payload: payload, p_timestamp: timestamp, p_signature: signature });
  if (error) {
    throw new ApiKeyWebhookQueryError(error.message);
  }
  if (typeof data !== "boolean") {
    throw new ApiKeyWebhookQueryError("verify_webhook_signature returned a non-boolean result");
  }
  return data;
}
