/**
 * Public API Platform read queries (IAE-009, Prompt 337). Thin, typed wrappers around
 * app.list_api_versions / app.list_webhook_event_types / app.list_api_logs_for_tenant
 * (supabase/migrations/20260804010000_create_intelligence_public_api_platform.sql).
 * app.list_api_versions is `authenticated`-callable; the other two are
 * `service_role`-only (app.list_webhook_event_types is called from the gateway itself,
 * already past its own authentication/scope check; app.list_api_logs_for_tenant is
 * SECURITY DEFINER, authority-gated, callable by `authenticated` too).
 */

import { parseApiVersion, ListApiLogsForTenantInputSchema, type ApiVersion, type ListApiLogsForTenantInput } from "../contracts/public-api-platform/public-api-platform.ts";
import { parseWebhookEventType, type WebhookEventType } from "../contracts/api-key-webhook/api-key-webhook.ts";
import { parseApiLog, type ApiLog } from "../contracts/api/api.ts";

export interface PublicApiPlatformQueryRpcClient {
  rpc(fn: "list_api_versions" | "list_webhook_event_types" | "list_api_logs_for_tenant", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class PublicApiPlatformQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PublicApiPlatformQueryError";
  }
}

export async function listApiVersions(client: PublicApiPlatformQueryRpcClient): Promise<ApiVersion[]> {
  const { data, error } = await client.rpc("list_api_versions", {});
  if (error) {
    throw new PublicApiPlatformQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new PublicApiPlatformQueryError("list_api_versions returned a non-array result");
  }
  return data.map((row) => parseApiVersion(row as Record<string, unknown>));
}

/** Never throws for an empty registry -- zero rows is a normal outcome (no real domain event type is seeded until IAE-012/Prompt 340). */
export async function listWebhookEventTypes(client: PublicApiPlatformQueryRpcClient): Promise<WebhookEventType[]> {
  const { data, error } = await client.rpc("list_webhook_event_types", {});
  if (error) {
    throw new PublicApiPlatformQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new PublicApiPlatformQueryError("list_webhook_event_types returned a non-array result");
  }
  return data.map((row) => parseWebhookEventType(row as Record<string, unknown>));
}

export async function listApiLogsForTenant(client: PublicApiPlatformQueryRpcClient, input: ListApiLogsForTenantInput): Promise<ApiLog[]> {
  const parsedInput = ListApiLogsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_api_logs_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_limit: parsedInput.limit,
    p_before: parsedInput.before,
  });
  if (error) {
    throw new PublicApiPlatformQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new PublicApiPlatformQueryError("list_api_logs_for_tenant returned a non-array result");
  }
  return data.map((row) => parseApiLog(row as Record<string, unknown>));
}
