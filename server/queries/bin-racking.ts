/**
 * Bin and Racking read queries (ATW-230, CG-S10-ATW-011). Thin, typed wrappers around
 * app.list_warehouse_locations/app.get_warehouse_location_deactivation_impact/
 * app.resolve_warehouse_location_by_barcode
 * (supabase/migrations/20260730150000_create_advanced_tms_bin_racking.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWarehouseLocation,
  parseWarehouseLocationDeactivationImpact,
  type WarehouseLocation,
  type WarehouseLocationDeactivationImpact,
  type WarehouseLocationStatus,
} from "../contracts/bin-racking/bin-racking.ts";

export type BinRackingQueryClient = Pick<SupabaseClient, "rpc">;

export class BinRackingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BinRackingQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Exactly one parent's own direct children (parentId null -- the warehouse's own root nodes), ordered by sequence then code -- bounded subtree loading, never a full recursive tree. */
export async function listWarehouseLocations(
  client: BinRackingQueryClient,
  warehouseId: string,
  actorAuthUserId: string,
  parentId?: string | null,
  statusFilter?: WarehouseLocationStatus | null,
): Promise<WarehouseLocation[]> {
  const { data, error } = await client.rpc("list_warehouse_locations", {
    p_warehouse_id: warehouseId,
    p_actor_auth_user_id: actorAuthUserId,
    p_parent_id: parentId ?? null,
    p_status_filter: statusFilter ?? null,
  });
  if (error) {
    throw new BinRackingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWarehouseLocation);
}

/** Read-only dependency-impact preview mirroring exactly what app.set_warehouse_location_status itself blocks a deactivation on. */
export async function getWarehouseLocationDeactivationImpact(client: BinRackingQueryClient, locationId: string, actorAuthUserId: string): Promise<WarehouseLocationDeactivationImpact> {
  const { data, error } = await client.rpc("get_warehouse_location_deactivation_impact", { p_location_id: locationId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new BinRackingQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new BinRackingQueryError("get_warehouse_location_deactivation_impact returned no row");
  }
  return parseWarehouseLocationDeactivationImpact(row);
}

/** Resolves a scanned barcode to a candidate location row only -- never itself authorizes a downstream action. */
export async function resolveWarehouseLocationByBarcode(client: BinRackingQueryClient, tenantId: string, barcode: string, actorAuthUserId: string): Promise<WarehouseLocation> {
  const { data, error } = await client.rpc("resolve_warehouse_location_by_barcode", { p_tenant_id: tenantId, p_barcode: barcode, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new BinRackingQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new BinRackingQueryError("resolve_warehouse_location_by_barcode returned no row");
  }
  return parseWarehouseLocation(row);
}
