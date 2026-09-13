/**
 * Fleet, Vehicle, Driver, Device and SIM Operational Baseline read queries
 * (ATW-223, CG-S10-ATW-004). CG-AUDIT-2026-09-02 O1 remediation (cluster 4
 * batch 1, 20260911050000_close_o1_query_layer_cluster4_batch1_fleet_driver_device.sql):
 * reads go through thin, security-invoker RPC wrappers (app is not exposed to
 * PostgREST, so a `.from()` call against any of these tables has never worked
 * in production) -- no masked column exists on any of these tables, so each
 * wrapper is a plain, RLS-scoped passthrough (tenant-wide, mirroring
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

export type FleetDriverDeviceQueryTableClient = Pick<SupabaseClient, "rpc">;

export class FleetDriverDeviceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FleetDriverDeviceQueryError";
  }
}

/** Every vehicle operational profile for one tenant. */
export async function listVehicleOperationalProfiles(client: FleetDriverDeviceQueryTableClient, tenantId: string): Promise<VehicleOperationalProfile[]> {
  const { data, error } = await client.rpc("list_vehicle_operational_profiles", { p_tenant_id: tenantId });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVehicleOperationalProfile(row));
}

/** Every driver operational profile for one tenant. */
export async function listDriverOperationalProfiles(client: FleetDriverDeviceQueryTableClient, tenantId: string): Promise<DriverOperationalProfile[]> {
  const { data, error } = await client.rpc("list_driver_operational_profiles", { p_tenant_id: tenantId });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseDriverOperationalProfile(row));
}

/** Every GPS device for one tenant. */
export async function listGpsDevices(client: FleetDriverDeviceQueryTableClient, tenantId: string): Promise<GpsDevice[]> {
  const { data, error } = await client.rpc("list_gps_devices", { p_tenant_id: tenantId });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseGpsDevice(row));
}

/** Every SIM card for one tenant. */
export async function listSimCards(client: FleetDriverDeviceQueryTableClient, tenantId: string): Promise<SimCard[]> {
  const { data, error } = await client.rpc("list_sim_cards", { p_tenant_id: tenantId });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSimCard(row));
}

/** Every device-vehicle assignment for one device, ordered most recent first (full history, never overwritten). */
export async function listDeviceVehicleAssignmentHistory(client: FleetDriverDeviceQueryTableClient, deviceId: string): Promise<DeviceVehicleAssignment[]> {
  const { data, error } = await client.rpc("list_device_vehicle_assignment_history", { p_device_id: deviceId });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseDeviceVehicleAssignment(row));
}

/** Every provider mapping for one vehicle master record. */
export async function listProviderVehicleMappings(client: FleetDriverDeviceQueryTableClient, vehicleMasterId: string): Promise<ProviderVehicleMapping[]> {
  const { data, error } = await client.rpc("list_provider_vehicle_mappings", { p_vehicle_master_id: vehicleMasterId });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseProviderVehicleMapping(row));
}

/** Every declared source-priority row for one vehicle master record, ordered by rank ascending. */
export async function listVehicleTrackingSourcePriorities(client: FleetDriverDeviceQueryTableClient, vehicleMasterId: string): Promise<VehicleTrackingSourcePriority[]> {
  const { data, error } = await client.rpc("list_vehicle_tracking_source_priorities", { p_vehicle_master_id: vehicleMasterId });
  if (error) {
    throw new FleetDriverDeviceQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVehicleTrackingSourcePriority(row));
}
