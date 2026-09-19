/**
 * GPS device installation evidence read queries (ATW-226B). CG-AUDIT-2026-09-02
 * O1 remediation (cluster 4 batch 2,
 * 20260911060000_close_o1_query_layer_cluster4_batch2_tracking_security.sql):
 * reads go through thin, security-invoker RPC wrappers (app is not exposed to
 * PostgREST, so a `.from()` call against app.gps_device_installations has
 * never worked in production) -- no masked column exists, so each wrapper is
 * a plain, RLS-scoped passthrough (tenant-wide, mirroring ATW-223's own
 * device/SIM tables' scope).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseGpsDeviceInstallation, type GpsDeviceInstallation } from "../contracts/gps-device-installation/gps-device-installation.ts";

export type GpsDeviceInstallationQueryClient = Pick<SupabaseClient, "rpc">;

export class GpsDeviceInstallationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GpsDeviceInstallationQueryError";
  }
}

/** Every installation evidence row for one tenant. */
export async function listGpsDeviceInstallations(client: GpsDeviceInstallationQueryClient, tenantId: string): Promise<GpsDeviceInstallation[]> {
  const { data, error } = await client.rpc("list_gps_device_installations", { p_tenant_id: tenantId });
  if (error) {
    throw new GpsDeviceInstallationQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseGpsDeviceInstallation(row));
}

/** The installation evidence row for one device-vehicle assignment, or null if none was ever recorded. */
export async function getGpsDeviceInstallationForAssignment(
  client: GpsDeviceInstallationQueryClient,
  deviceVehicleAssignmentId: string,
): Promise<GpsDeviceInstallation | null> {
  const { data, error } = await client.rpc("get_gps_device_installation_for_assignment", { p_device_vehicle_assignment_id: deviceVehicleAssignmentId });
  if (error) {
    throw new GpsDeviceInstallationQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseGpsDeviceInstallation(row as Record<string, unknown>) : null;
}
