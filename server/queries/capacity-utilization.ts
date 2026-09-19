/**
 * Capacity reservation and tracking coverage/utilization read queries (ATW-227,
 * CG-S10-ATW-008). Thin, typed wrappers around app.get_tenant_tracking_coverage/
 * app.get_tenant_tracking_utilization_summary
 * (supabase/migrations/20260730120000_create_advanced_tms_capacity_utilization.sql).
 * CG-AUDIT-2026-09-02 O1 remediation (cluster 3 batch 4,
 * 20260911040000_close_o1_query_layer_cluster3_batch4_shipment_order_capacity_exceptions.sql):
 * the leg/vehicle reservation-history reads also now go through thin,
 * security-invoker RPC wrappers (app is not exposed to PostgREST, so a
 * `.from()` call against app.vehicle_capacity_reservations has never worked in
 * production) -- RLS-scoped by tenant membership, never a cross-tenant read.
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
  const { data, error } = await client.rpc("list_capacity_reservations_for_leg", { p_shipment_leg_id: shipmentLegId });
  if (error) {
    throw new CapacityUtilizationQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVehicleCapacityReservation);
}

/** Every currently held/consumed reservation against one vehicle, earliest window first -- for a dispatcher checking a vehicle's own committed schedule before assigning another leg. */
export async function listActiveCapacityReservationsForVehicle(client: CapacityUtilizationQueryClient, vehicleMasterId: string): Promise<VehicleCapacityReservation[]> {
  const { data, error } = await client.rpc("list_active_capacity_reservations_for_vehicle", { p_vehicle_master_id: vehicleMasterId });
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
