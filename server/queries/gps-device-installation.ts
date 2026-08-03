/**
 * GPS device installation evidence read queries (ATW-226B). No masked column exists on
 * app.gps_device_installations, so reads go directly against the base table
 * (RLS-scoped tenant-wide, mirroring ATW-223's own device/SIM tables' scope).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseGpsDeviceInstallation, type GpsDeviceInstallation } from "../contracts/gps-device-installation/gps-device-installation.ts";

export type GpsDeviceInstallationQueryClient = Pick<SupabaseClient, "from">;

export class GpsDeviceInstallationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GpsDeviceInstallationQueryError";
  }
}

/** Every installation evidence row for one tenant. */
export async function listGpsDeviceInstallations(client: GpsDeviceInstallationQueryClient, tenantId: string): Promise<GpsDeviceInstallation[]> {
  const { data, error } = await client.from("gps_device_installations").select("*").eq("tenant_id", tenantId).order("installed_at", { ascending: false });
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
  const { data, error } = await client.from("gps_device_installations").select("*").eq("device_vehicle_assignment_id", deviceVehicleAssignmentId).maybeSingle();
  if (error) {
    throw new GpsDeviceInstallationQueryError(error.message);
  }
  return data ? parseGpsDeviceInstallation(data as Record<string, unknown>) : null;
}
