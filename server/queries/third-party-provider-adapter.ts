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
    // ATW-030 (closes ISS-2026-026): an explicit column list, never `select("*")`.
    // ATW-027's own Finding 1 fix narrowed this table's `authenticated` grant from
    // table-wide to these 14 columns precisely to keep `webhook_secret_value`
    // unreadable; a `select("*")` asks for the ungranted column too, so it would fail
    // (or, under a broader-privileged client, defeat the restriction outright). This
    // list matches that grant exactly -- see
    // `supabase/migrations/20260730350000_harden_advanced_tms_third_party_hybrid_tracking.sql`.
    .select(
      "id, tenant_id, provider_code, integration_mode, poll_cursor, status, consecutive_failure_count, last_successful_ingest_at, record_version, created_by, created_at, updated_at, auto_disabled_at, disabled_reason",
    )
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
