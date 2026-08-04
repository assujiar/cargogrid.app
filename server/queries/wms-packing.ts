/**
 * WMS Packing read queries (ATW-018, CG-S10-ATW-018). Thin, typed wrappers around
 * app.get_wms_packing_task/app.list_wms_packing_tasks/app.get_wms_package/
 * app.list_wms_package_lines/app.list_wms_package_line_scans/
 * app.list_wms_package_confirmations/app.list_wms_packages
 * (supabase/migrations/20260730250000_create_advanced_tms_wms_packing.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWmsPackingTask,
  parseWmsPackage,
  parseWmsPackageLine,
  parseWmsPackageLineScan,
  parseWmsPackageConfirmation,
  type WmsPackingTask,
  type WmsPackage,
  type WmsPackageLine,
  type WmsPackageLineScan,
  type WmsPackageConfirmation,
  type WmsPackageStatus,
} from "../contracts/wms-packing/wms-packing.ts";

export type WmsPackingQueryClient = Pick<SupabaseClient, "rpc">;

export class WmsPackingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WmsPackingQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC- and record/owner-scope-gated. */
export async function getWmsPackingTask(client: WmsPackingQueryClient, packingTaskId: string, actorAuthUserId: string): Promise<WmsPackingTask> {
  const { data, error } = await client.rpc("get_wms_packing_task", { p_packing_task_id: packingTaskId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPackingQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsPackingQueryError("get_wms_packing_task returned no row");
  }
  return parseWmsPackingTask(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record- and owner-scoped, optionally narrowed to one warehouse/outbound order. */
export async function listWmsPackingTasks(
  client: WmsPackingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; outboundOrderId?: string | null; limit?: number },
): Promise<WmsPackingTask[]> {
  const { data, error } = await client.rpc("list_wms_packing_tasks", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_outbound_order_id: options?.outboundOrderId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsPackingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPackingTask);
}

/** Single-row read by id, RBAC- and record/owner-scope-gated. */
export async function getWmsPackage(client: WmsPackingQueryClient, packageId: string, actorAuthUserId: string): Promise<WmsPackage> {
  const { data, error } = await client.rpc("get_wms_package", { p_package_id: packageId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPackingQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsPackingQueryError("get_wms_package returned no row");
  }
  return parseWmsPackage(row);
}

/** Live current contents of one package, ordered by first_added_at. */
export async function listWmsPackageLines(client: WmsPackingQueryClient, packageId: string, actorAuthUserId: string): Promise<WmsPackageLine[]> {
  const { data, error } = await client.rpc("list_wms_package_lines", { p_package_id: packageId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPackingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPackageLine);
}

/** Every real add/remove scan event on one package, ordered by occurred_at. */
export async function listWmsPackageLineScans(client: WmsPackingQueryClient, packageId: string, actorAuthUserId: string): Promise<WmsPackageLineScan[]> {
  const { data, error } = await client.rpc("list_wms_package_line_scans", { p_package_id: packageId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPackingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPackageLineScan);
}

/** Every real confirm event on one package, ordered by confirmed_at. */
export async function listWmsPackageConfirmations(client: WmsPackingQueryClient, packageId: string, actorAuthUserId: string): Promise<WmsPackageConfirmation[]> {
  const { data, error } = await client.rpc("list_wms_package_confirmations", { p_package_id: packageId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPackingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPackageConfirmation);
}

/** Bounded (default 50, hard-capped 200 server-side), record- and owner-scoped, optionally narrowed to one packing task/outbound order/owner/parent/status. */
export async function listWmsPackages(
  client: WmsPackingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: {
    packingTaskId?: string | null;
    outboundOrderId?: string | null;
    ownerAccountId?: string | null;
    parentPackageId?: string | null;
    statusFilter?: WmsPackageStatus | null;
    limit?: number;
  },
): Promise<WmsPackage[]> {
  const { data, error } = await client.rpc("list_wms_packages", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_packing_task_id: options?.packingTaskId ?? null,
    p_outbound_order_id: options?.outboundOrderId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_parent_package_id: options?.parentPackageId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsPackingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPackage);
}
