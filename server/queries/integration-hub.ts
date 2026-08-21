/**
 * Integration Hub read queries (IAE-008, Prompt 336). All direct,
 * RLS-scoped reads -- no wrapper RPC needed, mirroring app.tenant_dashboards'
 * own precedent (IAE-003). app.integration_connection_credentials is never
 * queried here -- it has zero authenticated/anon grant by design.
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

export type IntegrationHubQueryClient = Pick<SupabaseClient, "from">;

export class IntegrationHubQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IntegrationHubQueryError";
  }
}

/** The full adapter catalog, alphabetical -- the "marketplace" listing (Prompt 336 §15). Global, non-sensitive. */
export async function listIntegrationAdapters(client: IntegrationHubQueryClient): Promise<IntegrationAdapter[]> {
  const { data, error } = await client.from("integration_adapters").select("*").order("name", { ascending: true });
  if (error) {
    throw new IntegrationHubQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationAdapter(row));
}

/** Every connection for one tenant, most recently updated first. */
export async function listIntegrationConnections(client: IntegrationHubQueryClient, tenantId: string): Promise<IntegrationConnection[]> {
  const { data, error } = await client.from("integration_connections").select("*").eq("tenant_id", tenantId).order("updated_at", { ascending: false });
  if (error) {
    throw new IntegrationHubQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationConnection(row));
}

/** A single connection by id -- returns null (never an error) when it does not exist or RLS hides it. */
export async function getIntegrationConnectionById(client: IntegrationHubQueryClient, connectionId: string): Promise<IntegrationConnection | null> {
  const { data, error } = await client.from("integration_connections").select("*").eq("id", connectionId).maybeSingle();
  if (error) {
    throw new IntegrationHubQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseIntegrationConnection(data as Record<string, unknown>);
}

/** Health-check history for one connection, newest first. */
export async function listIntegrationHealthChecks(client: IntegrationHubQueryClient, connectionId: string, limit = 25): Promise<IntegrationHealthCheck[]> {
  const { data, error } = await client
    .from("integration_health_checks")
    .select("*")
    .eq("connection_id", connectionId)
    .order("checked_at", { ascending: false })
    .limit(limit);
  if (error) {
    throw new IntegrationHubQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseIntegrationHealthCheck(row));
}
