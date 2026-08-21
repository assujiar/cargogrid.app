/**
 * n8n Integration mutation entry points (IAE-013, Prompt 341). Thin, typed
 * wrapper around app.create_n8n_connector
 * (supabase/migrations/20260804050000_create_intelligence_n8n_integration.sql).
 * Revoke reuses ../mutations/api-key-webhook.ts's own revokeApiKey directly --
 * app.revoke_n8n_connector delegates entirely to app.revoke_api_key
 * (PLT-129), unchanged.
 */

import { CreateN8nConnectorInputSchema, parseCreatedN8nConnector, type CreateN8nConnectorInput, type CreatedN8nConnector } from "../contracts/n8n-integration/n8n-integration.ts";

export interface N8nIntegrationMutationRpcClient {
  rpc(fn: "create_n8n_connector", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const N8N_INTEGRATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "n8n_connector_missing_name",
  "api_key_missing_scopes",
  "n8n_scope_not_allowlisted",
  "webhook_endpoint_not_found",
  "api_key_invalid_rate_limit",
] as const;
type KnownN8nIntegrationMutationErrorCode = (typeof N8N_INTEGRATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type N8nIntegrationMutationErrorCode = KnownN8nIntegrationMutationErrorCode | "mutation_failed" | "invalid_response";

export class N8nIntegrationMutationError extends Error {
  readonly code: N8nIntegrationMutationErrorCode;

  constructor(code: N8nIntegrationMutationErrorCode, message: string) {
    super(message);
    this.name = "N8nIntegrationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): N8nIntegrationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (N8N_INTEGRATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownN8nIntegrationMutationErrorCode)
    : "mutation_failed";
}

/** Authority: Supreme or the tenant's own active tenant_admin. Every requested scope must pass BOTH the n8n allowlist AND the creating actor's own current RBAC. Returns the raw key exactly once. */
export async function createN8nConnector(client: N8nIntegrationMutationRpcClient, input: CreateN8nConnectorInput): Promise<CreatedN8nConnector> {
  const parsedInput = CreateN8nConnectorInputSchema.parse(input);
  const { data, error } = await client.rpc("create_n8n_connector", {
    p_tenant_id: parsedInput.tenantId,
    p_name: parsedInput.name,
    p_scopes: parsedInput.scopes,
    p_webhook_endpoint_id: parsedInput.webhookEndpointId,
    p_rate_limit_per_minute: parsedInput.rateLimitPerMinute,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new N8nIntegrationMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new N8nIntegrationMutationError("invalid_response", "create_n8n_connector returned no row");
  }
  return parseCreatedN8nConnector(row as Record<string, unknown>);
}
