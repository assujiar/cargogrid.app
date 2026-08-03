/**
 * WMS Outbound Order read queries (ATW-016A, CG-S10-ATW-016A). Thin, typed wrappers
 * around app.get_wms_outbound_order/app.list_wms_outbound_order_lines/
 * app.list_wms_outbound_orders/app.get_wms_outbound_readiness
 * (supabase/migrations/20260730230000_create_advanced_tms_wms_outbound_order.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWmsOutboundOrder,
  parseWmsOutboundOrderLine,
  parseWmsOutboundReadiness,
  type WmsOutboundOrder,
  type WmsOutboundOrderLine,
  type WmsOutboundReadiness,
  type WmsOutboundOrderStatus,
} from "../contracts/wms-outbound-order/wms-outbound-order.ts";

export type WmsOutboundOrderQueryClient = Pick<SupabaseClient, "rpc">;

export class WmsOutboundOrderQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WmsOutboundOrderQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC-, record-scope- and owner-scope-gated. */
export async function getWmsOutboundOrder(client: WmsOutboundOrderQueryClient, outboundOrderId: string, actorAuthUserId: string): Promise<WmsOutboundOrder> {
  const { data, error } = await client.rpc("get_wms_outbound_order", { p_outbound_order_id: outboundOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsOutboundOrderQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsOutboundOrderQueryError("get_wms_outbound_order returned no row");
  }
  return parseWmsOutboundOrder(row);
}

/** Every line on one outbound order, ordered by line_number. */
export async function listWmsOutboundOrderLines(client: WmsOutboundOrderQueryClient, outboundOrderId: string, actorAuthUserId: string): Promise<WmsOutboundOrderLine[]> {
  const { data, error } = await client.rpc("list_wms_outbound_order_lines", { p_outbound_order_id: outboundOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsOutboundOrderQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsOutboundOrderLine);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped by warehouse and owner-account, optionally narrowed to one warehouse/owner/status. */
export async function listWmsOutboundOrders(
  client: WmsOutboundOrderQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; ownerAccountId?: string | null; statusFilter?: WmsOutboundOrderStatus | null; limit?: number },
): Promise<WmsOutboundOrder[]> {
  const { data, error } = await client.rpc("list_wms_outbound_orders", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsOutboundOrderQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsOutboundOrder);
}

/** Read-only preview of exactly what app.confirm_wms_outbound_order itself will block on. */
export async function getWmsOutboundReadiness(client: WmsOutboundOrderQueryClient, outboundOrderId: string, actorAuthUserId: string): Promise<WmsOutboundReadiness> {
  const { data, error } = await client.rpc("get_wms_outbound_readiness", { p_outbound_order_id: outboundOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsOutboundOrderQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsOutboundOrderQueryError("get_wms_outbound_readiness returned no row");
  }
  return parseWmsOutboundReadiness(row);
}
