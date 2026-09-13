/**
 * Integration Hub read queries (IAE-008, Prompt 336). All RLS-scoped reads via
 * RPC (O1 remediation, cluster 6) -- app is not exposed to PostgREST. All 4
 * functions are SECURITY INVOKER, zero actor parameter.
 * app.integration_connection_credentials is never queried here -- it has zero
 * authenticated/anon grant by design.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseIntegrationAdapter,
  parseIntegrationConnection,
  parseIntegrationHealthCheck,
  type IntegrationAdapter,
  type IntegrationConnection,
  type IntegrationHealthCheck,
} from "../contracts/integration-hub/integration-hub.ts";

export type IntegrationHubQueryClient = Pick<SupabaseClient, "rpc">;

export class IntegrationHubQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IntegrationHubQueryError";
  }
}

/** The full adapter catalog, alphabetical -- the "marketplace" listing (Prompt 336 §15). Global, non-sensitive. */
export async function listIntegrationAdapters(client: IntegrationHubQueryClient): Promise<IntegrationAdapter[]> {
  const { data, error } = await client.rpc("list_integration_adapters");
  if (error) {
    throw new IntegrationHubQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationAdapter(row));
}

/** Every connection for one tenant, most recently updated first. */
export async function listIntegrationConnections(client: IntegrationHubQueryClient, tenantId: string): Promise<IntegrationConnection[]> {
  const { data, error } = await client.rpc("list_integration_connections", { p_tenant_id: tenantId });
  if (error) {
    throw new IntegrationHubQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationConnection(row));
}

/** A single connection by id -- returns null (never an error) when it does not exist or RLS hides it. */
export async function getIntegrationConnectionById(client: IntegrationHubQueryClient, connectionId: string): Promise<IntegrationConnection | null> {
  const { data, error } = await client.rpc("get_integration_connection_by_id", { p_connection_id: connectionId });
  if (error) {
    throw new IntegrationHubQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseIntegrationConnection(row as Record<string, unknown>);
}

/** Health-check history for one connection, newest first. */
export async function listIntegrationHealthChecks(client: IntegrationHubQueryClient, connectionId: string, limit = 25): Promise<IntegrationHealthCheck[]> {
  const { data, error } = await client.rpc("list_integration_health_checks", { p_connection_id: connectionId, p_limit: limit });
  if (error) {
    throw new IntegrationHubQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationHealthCheck(row));
}
