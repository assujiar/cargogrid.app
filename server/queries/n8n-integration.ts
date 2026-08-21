/**
 * n8n Integration query entry points (IAE-013, Prompt 341). Thin, typed
 * wrappers around app.list_n8n_connectors_for_tenant /
 * app.list_n8n_action_allowlist
 * (supabase/migrations/20260804050000_create_intelligence_n8n_integration.sql).
 */

import { ListN8nConnectorsForTenantInputSchema, parseN8nConnector, parseN8nAllowlistedAction, type ListN8nConnectorsForTenantInput, type N8nConnector, type N8nAllowlistedAction } from "../contracts/n8n-integration/n8n-integration.ts";

export interface N8nIntegrationQueryRpcClient {
  rpc(fn: "list_n8n_connectors_for_tenant" | "list_n8n_action_allowlist", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class N8nIntegrationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "N8nIntegrationQueryError";
  }
}

/** Authority: Supreme or the tenant's own active tenant_admin (app.check_api_webhook_admin_authority). */
export async function listN8nConnectorsForTenant(client: N8nIntegrationQueryRpcClient, input: ListN8nConnectorsForTenantInput): Promise<N8nConnector[]> {
  const parsedInput = ListN8nConnectorsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_n8n_connectors_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new N8nIntegrationQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseN8nConnector);
}

/** Globally readable -- the platform-wide catalog of scopes considered safe for external no-code automation. */
export async function listN8nActionAllowlist(client: N8nIntegrationQueryRpcClient): Promise<N8nAllowlistedAction[]> {
  const { data, error } = await client.rpc("list_n8n_action_allowlist", {});
  if (error) {
    throw new N8nIntegrationQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseN8nAllowlistedAction);
}
