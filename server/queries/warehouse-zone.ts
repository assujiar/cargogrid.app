/**
 * Warehouse and Zone read queries (ATW-229, CG-S10-ATW-010). Thin, typed wrappers
 * around app.list_tenant_warehouses/app.list_warehouse_zones/
 * app.list_warehouse_customer_eligibility/app.get_warehouse_deactivation_impact
 * (supabase/migrations/20260730140000_create_advanced_tms_warehouse_zone.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseTenantWarehouseListRow,
  parseWarehouseZone,
  parseWarehouseCustomerEligibilityListRow,
  parseWarehouseDeactivationImpact,
  type TenantWarehouseListRow,
  type WarehouseZone,
  type WarehouseCustomerEligibilityListRow,
  type WarehouseDeactivationImpact,
  type WarehouseStatus,
  type WarehouseZoneStatus,
} from "../contracts/warehouse-zone/warehouse-zone.ts";

export type WarehouseZoneQueryClient = Pick<SupabaseClient, "rpc">;

export class WarehouseZoneQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WarehouseZoneQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** One row per warehouse the caller can access for a tenant, including zone_count/active_zone_count. OPS:View-gated and record-scope-gated server-side. */
export async function listTenantWarehouses(
  client: WarehouseZoneQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  statusFilter?: WarehouseStatus | null,
): Promise<TenantWarehouseListRow[]> {
  const { data, error } = await client.rpc("list_tenant_warehouses", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: statusFilter ?? null,
  });
  if (error) {
    throw new WarehouseZoneQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseTenantWarehouseListRow);
}

/** Every zone under one warehouse the caller can access, ordered by code. */
export async function listWarehouseZones(
  client: WarehouseZoneQueryClient,
  warehouseId: string,
  actorAuthUserId: string,
  statusFilter?: WarehouseZoneStatus | null,
): Promise<WarehouseZone[]> {
  const { data, error } = await client.rpc("list_warehouse_zones", {
    p_warehouse_id: warehouseId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: statusFilter ?? null,
  });
  if (error) {
    throw new WarehouseZoneQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWarehouseZone);
}

/** Every customer eligibility grant/revocation for one warehouse the caller can access, joined to the account's own legal_name. */
export async function listWarehouseCustomerEligibility(
  client: WarehouseZoneQueryClient,
  warehouseId: string,
  actorAuthUserId: string,
): Promise<WarehouseCustomerEligibilityListRow[]> {
  const { data, error } = await client.rpc("list_warehouse_customer_eligibility", {
    p_warehouse_id: warehouseId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new WarehouseZoneQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWarehouseCustomerEligibilityListRow);
}

/** Read-only dependency-impact preview for an admin considering deactivation -- active_zone_count/on_hold_zone_count mirror exactly what app.set_warehouse_status itself will block on. */
export async function getWarehouseDeactivationImpact(client: WarehouseZoneQueryClient, warehouseId: string, actorAuthUserId: string): Promise<WarehouseDeactivationImpact> {
  const { data, error } = await client.rpc("get_warehouse_deactivation_impact", { p_warehouse_id: warehouseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WarehouseZoneQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseZoneQueryError("get_warehouse_deactivation_impact returned no row");
  }
  return parseWarehouseDeactivationImpact(row);
}
