/**
 * Purchase Order read queries (PRC-260, CG-S11-PRC-011). Thin, typed wrappers around the
 * dedicated read RPCs (supabase/migrations/20260730680000_create_procurement_purchase_
 * order.sql) -- mirrors server/queries/vendor-comparison.ts exactly: every RPC already
 * carries its own explicit evaluate_permission check, so this file calls `.rpc(...)`,
 * never `.from(...)`, on a base table or a view.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parsePurchaseOrder,
  parsePurchaseOrderLine,
  parsePurchaseOrderEvent,
  type PurchaseOrder,
  type PurchaseOrderLine,
  type PurchaseOrderEvent,
} from "../contracts/purchase-order/purchase-order.ts";

export type PurchaseOrderQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class PurchaseOrderQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PurchaseOrderQueryError";
  }
}

// app.list_purchase_orders itself clamps server-side to <=200 rows regardless of what
// is requested (PRC-256/PRC-257/PRC-258's own disclosed .limit(200) precedent) -- this
// client-side default only picks a reasonable per-request page size.
const PURCHASE_ORDER_LIST_DEFAULT_LIMIT = 50;

/** A single purchase order. Throws on a real error; the RPC itself raises purchase_order_not_found/insufficient_privilege as thrown errors, never a null return. */
export async function getPurchaseOrder(client: PurchaseOrderQueryRpcClient, purchaseOrderId: string, actorAuthUserId: string): Promise<PurchaseOrder> {
  const { data, error } = await client.rpc("get_purchase_order", { p_purchase_order_id: purchaseOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new PurchaseOrderQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new PurchaseOrderQueryError("get_purchase_order returned no row");
  }
  return parsePurchaseOrder(row as Record<string, unknown>);
}

/** Tenant-scoped PO queue, optionally filtered by status and/or vendor. With no status filter, superseded (historical) versions are excluded by default. Server-side clamped to <=200 rows. */
export async function listPurchaseOrders(
  client: PurchaseOrderQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  statusFilter: string | null = null,
  vendorMasterId: string | null = null,
  limit: number = PURCHASE_ORDER_LIST_DEFAULT_LIMIT,
): Promise<PurchaseOrder[]> {
  const { data, error } = await client.rpc("list_purchase_orders", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: statusFilter,
    p_vendor_master_id: vendorMasterId,
    p_limit: limit,
  });
  if (error) {
    throw new PurchaseOrderQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parsePurchaseOrder(row));
}

/** Every itemized line for one PO, ordered by line_no. No cost data -- plain. */
export async function listPurchaseOrderLines(client: PurchaseOrderQueryRpcClient, purchaseOrderId: string, actorAuthUserId: string): Promise<PurchaseOrderLine[]> {
  const { data, error } = await client.rpc("list_purchase_order_lines", { p_purchase_order_id: purchaseOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new PurchaseOrderQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parsePurchaseOrderLine(row));
}

/** The full lifecycle timeline (PO-root transitions only) for one PO, in occurrence order. */
export async function getPurchaseOrderHistory(client: PurchaseOrderQueryRpcClient, purchaseOrderId: string, actorAuthUserId: string): Promise<PurchaseOrderEvent[]> {
  const { data, error } = await client.rpc("get_purchase_order_history", { p_purchase_order_id: purchaseOrderId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new PurchaseOrderQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parsePurchaseOrderEvent(row));
}
