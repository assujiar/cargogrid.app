/**
 * Driver Mobile GPS session read queries (ATW-226C). app.driver_mobile_tracking_sessions
 * has no masked column so reads go directly against the base table (RLS-scoped
 * tenant-wide); position report history goes through app.get_driver_mobile_position_reports
 * for its own computed GeoJSON projection, the same pattern
 * server/queries/multi-leg-shipment.ts already established for stop locations.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseDriverMobileTrackingSession,
  parseDriverMobilePositionReport,
  type DriverMobileTrackingSession,
  type DriverMobilePositionReport,
} from "../contracts/driver-mobile-tracking/driver-mobile-tracking.ts";

export type DriverMobileTrackingQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class DriverMobileTrackingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DriverMobileTrackingQueryError";
  }
}

/** The mobile session token record for one ATW-225 tracking session, or null if none has ever been issued. Never exposes the token itself -- only token_hash-free metadata (status/expiry/last_seen_at). */
export async function getDriverMobileTrackingSession(
  client: DriverMobileTrackingQueryClient,
  shipmentLegTrackingSessionId: string,
): Promise<DriverMobileTrackingSession | null> {
  const { data, error } = await client
    .from("driver_mobile_tracking_sessions")
    .select("*")
    .eq("shipment_leg_tracking_session_id", shipmentLegTrackingSessionId)
    .eq("status", "active")
    .maybeSingle();
  if (error) {
    throw new DriverMobileTrackingQueryError(error.message);
  }
  return data ? parseDriverMobileTrackingSession(data as Record<string, unknown>) : null;
}

/** Every raw position report for one driver-mobile tracking session, newest first. */
export async function listDriverMobilePositionReports(
  client: DriverMobileTrackingQueryClient,
  driverMobileTrackingSessionId: string,
): Promise<DriverMobilePositionReport[]> {
  const { data, error } = await client.rpc("get_driver_mobile_position_reports", { p_driver_mobile_tracking_session_id: driverMobileTrackingSessionId });
  if (error) {
    throw new DriverMobileTrackingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseDriverMobilePositionReport(row));
}
