/**
 * Public API Platform read queries (IAE-009, Prompt 337). Thin, typed wrappers around
 * app.list_api_versions / app.list_webhook_event_types / app.list_api_logs_for_tenant
 * (supabase/migrations/20260804010000_create_intelligence_public_api_platform.sql).
 * app.list_api_versions is `authenticated`-callable; the other two are
 * `service_role`-only (app.list_webhook_event_types is called from the gateway itself,
 * already past its own authentication/scope check; app.list_api_logs_for_tenant is
 * SECURITY DEFINER, authority-gated, callable by `authenticated` too).
 */

import { parseApiVersion, parseApiVersionRequestState, ListApiLogsForTenantInputSchema, type ApiVersion, type ApiVersionRequestState, type ListApiLogsForTenantInput } from "../contracts/public-api-platform/public-api-platform.ts";
import { parseWebhookEventType, type WebhookEventType } from "../contracts/api-key-webhook/api-key-webhook.ts";
import { parseApiLog, type ApiLog } from "../contracts/api/api.ts";

export interface PublicApiPlatformQueryRpcClient {
  rpc(fn: "list_api_versions" | "list_webhook_event_types" | "list_api_logs_for_tenant" | "evaluate_api_version_request", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
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
    p_api_key_id: parsedInput.apiKeyId,
  });
  if (error) {
    throw new PublicApiPlatformQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new PublicApiPlatformQueryError("list_api_logs_for_tenant returned a non-array result");
  }
  return data.map((row) => parseApiLog(row as Record<string, unknown>));
}

/**
 * ISS-2026-207: the registry's live request-time decision.
 *
 * **On an unreadable answer this returns `ok`, not `gone`, and the direction matters.** The first
 * draft failed closed. That is wrong here, for a specific reason: `410 Gone` means *permanently*
 * gone. Emitting it because a `SELECT` blipped tells every integrator that the endpoint has been
 * withdrawn, and well-behaved clients stop calling — a transient database error would become a
 * self-inflicted, sticky outage across every integration at once.
 *
 * Failing open costs nothing real here, because it cannot actually serve anything. The very next
 * step is `app.authenticate_and_authorize_api_request`, which reads the same database; if the
 * registry could not be read, authentication will not succeed either, and the caller gets an
 * honest auth error instead of a misleading permanence claim.
 *
 * A genuinely unknown version code is a different case and is **not** this branch: the SQL
 * returns a real `gone` row for it, so an unrecognised version is still refused.
 */
export async function evaluateApiVersionRequest(client: PublicApiPlatformQueryRpcClient, code: string): Promise<ApiVersionRequestState> {
  const unreadable: ApiVersionRequestState = { decision: "ok", status: "unreadable", sunsetAt: null };
  const { data, error } = await client.rpc("evaluate_api_version_request", { p_code: code });
  if (error) {
    return unreadable;
  }
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : (data as Record<string, unknown> | null);
  if (!row) {
    return unreadable;
  }
  try {
    return parseApiVersionRequestState(row);
  } catch {
    return unreadable;
  }
}
