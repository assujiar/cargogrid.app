/**
 * WMS Inbound read queries (ATW-012, CG-S10-ATW-012). Thin, typed wrappers around
 * app.get_wms_inbound_order/app.list_wms_inbound_order_lines/
 * app.list_wms_inbound_orders/app.get_wms_inbound_readiness
 * (supabase/migrations/20260730180000_create_advanced_tms_wms_inbound.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWmsInboundOrder,
  parseWmsInboundOrderLine,
  parseWmsInboundReadiness,
  type WmsInboundOrder,
  type WmsInboundOrderLine,
  type WmsInboundReadiness,
  type WmsInboundOrderStatus,
} from "../contracts/wms-inbound/wms-inbound.ts";

export type WmsInboundQueryClient = Pick<SupabaseClient, "rpc">;

export class WmsInboundQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WmsInboundQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC- and record-scope-gated. */
export async function getWmsInboundOrder(client: WmsInboundQueryClient, inboundOrderId: string, actorAuthUserId: string): Promise<WmsInboundOrder> {
  const { data, error } = await client.rpc("get_wms_inbound_order", { p_inbound_order_id: inboundOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsInboundQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsInboundQueryError("get_wms_inbound_order returned no row");
  }
  return parseWmsInboundOrder(row);
}

/** Every line on one inbound order, ordered by line_number. */
export async function listWmsInboundOrderLines(client: WmsInboundQueryClient, inboundOrderId: string, actorAuthUserId: string): Promise<WmsInboundOrderLine[]> {
  const { data, error } = await client.rpc("list_wms_inbound_order_lines", { p_inbound_order_id: inboundOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsInboundQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsInboundOrderLine);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped by warehouse, optionally narrowed to one warehouse/owner/status. */
export async function listWmsInboundOrders(
  client: WmsInboundQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; ownerAccountId?: string | null; statusFilter?: WmsInboundOrderStatus | null; limit?: number },
): Promise<WmsInboundOrder[]> {
  const { data, error } = await client.rpc("list_wms_inbound_orders", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsInboundQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsInboundOrder);
}

/** Read-only preview of exactly what app.confirm_wms_inbound itself will block on. */
export async function getWmsInboundReadiness(client: WmsInboundQueryClient, inboundOrderId: string, actorAuthUserId: string): Promise<WmsInboundReadiness> {
  const { data, error } = await client.rpc("get_wms_inbound_readiness", { p_inbound_order_id: inboundOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsInboundQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsInboundQueryError("get_wms_inbound_readiness returned no row");
  }
  return parseWmsInboundReadiness(row);
}
