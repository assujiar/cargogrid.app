/**
 * Fleet, Vehicle, Driver, Device and SIM Operational Baseline read queries
 * (ATW-223, CG-S10-ATW-004). No masked column exists on any of these tables, so
 * reads go directly against the base tables (RLS-scoped tenant-wide, mirroring
 * app.master_records' own scope, not owner/record-scoped).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVehicleOperationalProfile,
  parseDriverOperationalProfile,
  parseGpsDevice,
  parseSimCard,
  parseDeviceVehicleAssignment,
  parseProviderVehicleMapping,
  parseVehicleTrackingSourcePriority,
  type VehicleOperationalProfile,
  type DriverOperationalProfile,
  type GpsDevice,
  type SimCard,
  type DeviceVehicleAssignment,
  type ProviderVehicleMapping,
  type VehicleTrackingSourcePriority,
} from "../contracts/fleet-driver-device/fleet-driver-device.ts";

export type FleetDriverDeviceQueryTableClient = Pick<SupabaseClient, "from">;

export class FleetDriverDeviceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FleetDriverDeviceQueryError";
  }
}

/** Every vehicle operational profile for one tenant. */
export async function listVehicleOperationalProfiles(client: FleetDriverDeviceQueryTableClient, tenantId: string): Promise<VehicleOperationalProfile[]> {
  const { data, error } = await client.from("vehicle_operational_profiles").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVehicleOperationalProfile(row));
}

/** Every driver operational profile for one tenant. */
export async function listDriverOperationalProfiles(client: FleetDriverDeviceQueryTableClient, tenantId: string): Promise<DriverOperationalProfile[]> {
  const { data, error } = await client.from("driver_operational_profiles").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseDriverOperationalProfile(row));
}

/** Every GPS device for one tenant. */
export async function listGpsDevices(client: FleetDriverDeviceQueryTableClient, tenantId: string): Promise<GpsDevice[]> {
  const { data, error } = await client.from("gps_devices").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseGpsDevice(row));
}

/** Every SIM card for one tenant. */
export async function listSimCards(client: FleetDriverDeviceQueryTableClient, tenantId: string): Promise<SimCard[]> {
  const { data, error } = await client.from("sim_cards").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSimCard(row));
}

/** Every device-vehicle assignment for one device, ordered most recent first (full history, never overwritten). */
export async function listDeviceVehicleAssignmentHistory(client: FleetDriverDeviceQueryTableClient, deviceId: string): Promise<DeviceVehicleAssignment[]> {
  const { data, error } = await client.from("device_vehicle_assignments").select("*").eq("device_id", deviceId).order("created_at", { ascending: false });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseDeviceVehicleAssignment(row));
}

/** Every provider mapping for one vehicle master record. */
export async function listProviderVehicleMappings(client: FleetDriverDeviceQueryTableClient, vehicleMasterId: string): Promise<ProviderVehicleMapping[]> {
  const { data, error } = await client.from("provider_vehicle_mappings").select("*").eq("vehicle_master_id", vehicleMasterId).order("created_at", { ascending: false });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseProviderVehicleMapping(row));
}

/** Every declared source-priority row for one vehicle master record, ordered by rank ascending. */
export async function listVehicleTrackingSourcePriorities(client: FleetDriverDeviceQueryTableClient, vehicleMasterId: string): Promise<VehicleTrackingSourcePriority[]> {
  const { data, error } = await client.from("vehicle_tracking_source_priorities").select("*").eq("vehicle_master_id", vehicleMasterId).order("priority_rank", { ascending: true });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVehicleTrackingSourcePriority(row));
}
