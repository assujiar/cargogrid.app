/**
 * Fleet Control Tower read queries (ATW-226H). Thin, typed wrappers around the three
 * new tenant-wide aggregating reads app.get_tenant_vehicle_tracking_overview/app.get_
 * tenant_pending_milestone_candidates/app.get_tenant_pending_exception_signals.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseTenantVehicleTrackingOverviewRow,
  parseTenantPendingMilestoneCandidateRow,
  parseTenantPendingExceptionSignalRow,
  GetTenantVehicleTrackingOverviewInputSchema,
  GetTenantPendingSignalsInputSchema,
  type TenantVehicleTrackingOverviewRow,
  type TenantPendingMilestoneCandidateRow,
  type TenantPendingExceptionSignalRow,
  type GetTenantVehicleTrackingOverviewInput,
  type GetTenantPendingSignalsInput,
} from "../contracts/fleet-control-tower/fleet-control-tower.ts";

export type FleetControlTowerQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class FleetControlTowerQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FleetControlTowerQueryError";
  }
}

/** One row per active vehicle for a tenant, left-joined against its own current position -- a never-tracked vehicle carries null position fields, not a missing row. */
export async function getTenantVehicleTrackingOverview(
  client: FleetControlTowerQueryRpcClient,
  input: GetTenantVehicleTrackingOverviewInput,
): Promise<TenantVehicleTrackingOverviewRow[]> {
  const parsedInput = GetTenantVehicleTrackingOverviewInputSchema.parse(input);
  const { data, error } = await client.rpc("get_tenant_vehicle_tracking_overview", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new FleetControlTowerQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseTenantVehicleTrackingOverviewRow(row));
}

/** The tenant-wide pending-review queue -- 200-row hard cap regardless of the caller's own limit. */
export async function getTenantPendingMilestoneCandidates(
  client: FleetControlTowerQueryRpcClient,
  input: GetTenantPendingSignalsInput,
): Promise<TenantPendingMilestoneCandidateRow[]> {
  const parsedInput = GetTenantPendingSignalsInputSchema.parse(input);
  const { data, error } = await client.rpc("get_tenant_pending_milestone_candidates", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new FleetControlTowerQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseTenantPendingMilestoneCandidateRow(row));
}

/** The tenant-wide pending-review queue -- 200-row hard cap regardless of the caller's own limit. */
export async function getTenantPendingExceptionSignals(
  client: FleetControlTowerQueryRpcClient,
  input: GetTenantPendingSignalsInput,
): Promise<TenantPendingExceptionSignalRow[]> {
  const parsedInput = GetTenantPendingSignalsInputSchema.parse(input);
  const { data, error } = await client.rpc("get_tenant_pending_exception_signals", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new FleetControlTowerQueryError(error.message);
  }
  return ((data as Record<string, unknown>[]) ?? []).map((row) => parseTenantPendingExceptionSignalRow(row));
}
