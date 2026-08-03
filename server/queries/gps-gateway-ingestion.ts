/**
 * Direct-device (GPS Gateway) telemetry read queries (ATW-226D). Dispatcher/
 * administration read only (226H's own future Fleet Control Tower UI) -- goes through
 * app.get_direct_device_telemetry_reports for its own computed GeoJSON projection, the
 * same pattern server/queries/driver-mobile-tracking.ts already established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseDirectDeviceTelemetryReport, type DirectDeviceTelemetryReport } from "../contracts/gps-gateway-ingestion/gps-gateway-ingestion.ts";

export type GpsGatewayIngestionQueryClient = Pick<SupabaseClient, "rpc">;

export class GpsGatewayIngestionQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GpsGatewayIngestionQueryError";
  }
}

/** Every raw telemetry report for one direct-hardware device, newest first. */
export async function listDirectDeviceTelemetryReports(
  client: GpsGatewayIngestionQueryClient,
  deviceId: string,
): Promise<DirectDeviceTelemetryReport[]> {
  const { data, error } = await client.rpc("get_direct_device_telemetry_reports", { p_device_id: deviceId });
  if (error) {
    throw new GpsGatewayIngestionQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseDirectDeviceTelemetryReport(row));
}
