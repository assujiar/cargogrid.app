/**
 * Canonical telemetry, current position, source health, and source switches read
 * queries (ATW-226F). Every read goes through its own GeoJSON/computed-status
 * projection RPC -- none of these tables is queried directly via `.from()`, since
 * app.vehicle_current_positions/app.canonical_telemetry_events store PostGIS geography
 * columns (opaque WKB through PostgREST without projection) and app.vehicle_source_
 * health's own status is deliberately computed on read, never stored.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVehicleCurrentPosition,
  parseCanonicalTelemetryEvent,
  parseVehicleSourceHealth,
  parseVehicleSourceSwitch,
  type VehicleCurrentPosition,
  type CanonicalTelemetryEvent,
  type VehicleSourceHealth,
  type VehicleSourceSwitch,
} from "../contracts/canonical-telemetry/canonical-telemetry.ts";

export type CanonicalTelemetryQueryClient = Pick<SupabaseClient, "rpc">;

export class CanonicalTelemetryQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CanonicalTelemetryQueryError";
  }
}

/** The sole authoritative "where is this vehicle right now" read. Null if the vehicle has never had a canonical position applied. */
export async function getVehicleCurrentPosition(client: CanonicalTelemetryQueryClient, vehicleMasterId: string): Promise<VehicleCurrentPosition | null> {
  const { data, error } = await client.rpc("get_vehicle_current_position", { p_vehicle_master_id: vehicleMasterId });
  if (error) {
    throw new CanonicalTelemetryQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseVehicleCurrentPosition(row as Record<string, unknown>) : null;
}

/** Newest-first, hard-capped server-side at 500 rows regardless of the caller's own limit. */
export async function listVehicleTelemetryHistory(
  client: CanonicalTelemetryQueryClient,
  vehicleMasterId: string,
  since: string | null = null,
  limit = 200,
): Promise<CanonicalTelemetryEvent[]> {
  const { data, error } = await client.rpc("get_vehicle_telemetry_history", { p_vehicle_master_id: vehicleMasterId, p_since: since, p_limit: limit });
  if (error) {
    throw new CanonicalTelemetryQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseCanonicalTelemetryEvent(row));
}

/** One row per source type ever seen for this vehicle -- status computed live against the tenant's own freshness_threshold_seconds. */
export async function listVehicleSourceHealth(client: CanonicalTelemetryQueryClient, tenantId: string, vehicleMasterId: string): Promise<VehicleSourceHealth[]> {
  const { data, error } = await client.rpc("get_vehicle_source_health", { p_tenant_id: tenantId, p_vehicle_master_id: vehicleMasterId });
  if (error) {
    throw new CanonicalTelemetryQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseVehicleSourceHealth(row));
}

/** Newest-first source-switch audit trail for one vehicle. */
export async function listVehicleSourceSwitches(client: CanonicalTelemetryQueryClient, vehicleMasterId: string, limit = 50): Promise<VehicleSourceSwitch[]> {
  const { data, error } = await client.rpc("get_vehicle_source_switches", { p_vehicle_master_id: vehicleMasterId, p_limit: limit });
  if (error) {
    throw new CanonicalTelemetryQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseVehicleSourceSwitch(row));
}
