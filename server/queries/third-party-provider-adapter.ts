/**
 * Third-party GPS platform adapter read queries (ATW-226E). Connection metadata reads go
 * directly against the base table (RLS-scoped tenant-wide, never exposes
 * webhook_secret_value -- that column carries zero authenticated/anon grant at the
 * schema-privilege layer regardless of what a caller selects); telemetry history goes
 * through app.get_third_party_telemetry_reports for its own computed GeoJSON
 * projection, the same pattern server/queries/gps-gateway-ingestion.ts already
 * established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseThirdPartyProviderConnection,
  parseThirdPartyTelemetryReport,
  type ThirdPartyProviderConnection,
  type ThirdPartyTelemetryReport,
} from "../contracts/third-party-provider-adapter/third-party-provider-adapter.ts";

export type ThirdPartyProviderAdapterQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class ThirdPartyProviderAdapterQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ThirdPartyProviderAdapterQueryError";
  }
}

/** One tenant's own connection to one provider_code, or null if never registered. */
export async function getThirdPartyProviderConnection(
  client: ThirdPartyProviderAdapterQueryClient,
  tenantId: string,
  providerCode: string,
): Promise<ThirdPartyProviderConnection | null> {
  const { data, error } = await client
    .from("third_party_provider_connections")
    .select("*")
    .eq("tenant_id", tenantId)
    .eq("provider_code", providerCode)
    .maybeSingle();
  if (error) {
    throw new ThirdPartyProviderAdapterQueryError(error.message);
  }
  return data ? parseThirdPartyProviderConnection(data as Record<string, unknown>) : null;
}

/** Every raw telemetry report for one connection, newest first. */
export async function listThirdPartyTelemetryReports(
  client: ThirdPartyProviderAdapterQueryClient,
  connectionId: string,
): Promise<ThirdPartyTelemetryReport[]> {
  const { data, error } = await client.rpc("get_third_party_telemetry_reports", { p_connection_id: connectionId });
  if (error) {
    throw new ThirdPartyProviderAdapterQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseThirdPartyTelemetryReport(row));
}
