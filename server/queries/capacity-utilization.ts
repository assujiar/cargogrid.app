/**
 * Capacity reservation and tracking coverage/utilization read queries (ATW-227,
 * CG-S10-ATW-008). Thin, typed wrappers around app.get_tenant_tracking_coverage/
 * app.get_tenant_tracking_utilization_summary
 * (supabase/migrations/20260730120000_create_advanced_tms_capacity_utilization.sql),
 * plus a direct RLS-scoped read of app.vehicle_capacity_reservations for a leg or
 * vehicle's own reservation history.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVehicleCapacityReservation,
  parseTenantTrackingCoverageRow,
  parseTenantTrackingUtilizationSummary,
  type VehicleCapacityReservation,
  type TenantTrackingCoverageRow,
  type TenantTrackingUtilizationSummary,
} from "../contracts/capacity-utilization/capacity-utilization.ts";

export type CapacityUtilizationQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class CapacityUtilizationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CapacityUtilizationQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Every capacity reservation ever made for one shipment leg, most recent first -- RLS-scoped (tenant membership), never a cross-tenant read. */
export async function listCapacityReservationsForLeg(client: CapacityUtilizationQueryClient, shipmentLegId: string): Promise<VehicleCapacityReservation[]> {
  const { data, error } = await client.from("vehicle_capacity_reservations").select("*").eq("shipment_leg_id", shipmentLegId).order("created_at", { ascending: false });
  if (error) {
    throw new CapacityUtilizationQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVehicleCapacityReservation);
}

/** Every currently held/consumed reservation against one vehicle, earliest window first -- for a dispatcher checking a vehicle's own committed schedule before assigning another leg. */
export async function listActiveCapacityReservationsForVehicle(client: CapacityUtilizationQueryClient, vehicleMasterId: string): Promise<VehicleCapacityReservation[]> {
  const { data, error } = await client
    .from("vehicle_capacity_reservations")
    .select("*")
    .eq("vehicle_master_id", vehicleMasterId)
    .in("status", ["held", "consumed"])
    .order("window_start", { ascending: true });
  if (error) {
    throw new CapacityUtilizationQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVehicleCapacityReservation);
}

/** One row per active vehicle for a tenant -- source class, coverage status, live utilization snapshot. OPS:View-gated server-side; never exposed to a customer-portal caller. */
export async function getTenantTrackingCoverage(client: CapacityUtilizationQueryClient, tenantId: string, actorAuthUserId: string): Promise<TenantTrackingCoverageRow[]> {
  const { data, error } = await client.rpc("get_tenant_tracking_coverage", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new CapacityUtilizationQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseTenantTrackingCoverageRow);
}

/** One tenant-wide summary row -- entitlement/limits, coverage counts, device/mobile-session utilization, and untracked-required-leg count. OPS:View-gated server-side. */
export async function getTenantTrackingUtilizationSummary(client: CapacityUtilizationQueryClient, tenantId: string, actorAuthUserId: string): Promise<TenantTrackingUtilizationSummary> {
  const { data, error } = await client.rpc("get_tenant_tracking_utilization_summary", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new CapacityUtilizationQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CapacityUtilizationQueryError("get_tenant_tracking_utilization_summary returned no row");
  }
  return parseTenantTrackingUtilizationSummary(row);
}
