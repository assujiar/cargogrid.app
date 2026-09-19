/**
 * Driver Mobile GPS session read queries (ATW-226C). CG-AUDIT-2026-09-02 O1
 * remediation (cluster 4 batch 2,
 * 20260911060000_close_o1_query_layer_cluster4_batch2_tracking_security.sql):
 * getDriverMobileTrackingSession now goes through app.get_driver_mobile_
 * tracking_session, a SECURITY DEFINER RPC (app is not exposed to PostgREST,
 * and ISS-2026-232 also revoked authenticated's table-level SELECT on
 * app.driver_mobile_tracking_sessions in favor of an explicit column-level
 * grant) that hand-picks the safe (token_hash-free) columns server-side and
 * reproduces the table's own RLS predicate explicitly against a real,
 * session-identity-checked actor; position report history goes through
 * app.get_driver_mobile_position_reports for its own computed GeoJSON
 * projection, the same pattern server/queries/multi-leg-shipment.ts already
 * established for stop locations.
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
  actorAuthUserId: string,
): Promise<DriverMobileTrackingSession | null> {
  const { data, error } = await client.rpc("get_driver_mobile_tracking_session", {
    p_shipment_leg_tracking_session_id: shipmentLegTrackingSessionId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new DriverMobileTrackingQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseDriverMobileTrackingSession(row as Record<string, unknown>) : null;
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
