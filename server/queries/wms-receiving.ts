/**
 * WMS Receiving read queries (ATW-013, CG-S10-ATW-013). Thin, typed wrappers around
 * app.get_wms_receipt_session/app.list_wms_receipt_lines/app.list_wms_receipt_sessions
 * (supabase/migrations/20260730200000_create_advanced_tms_wms_receiving.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWmsReceiptSession,
  parseWmsReceiptLine,
  type WmsReceiptSession,
  type WmsReceiptLine,
  type WmsReceiptSessionStatus,
} from "../contracts/wms-receiving/wms-receiving.ts";

export type WmsReceivingQueryClient = Pick<SupabaseClient, "rpc">;

export class WmsReceivingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WmsReceivingQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC- and record-scope-gated. */
export async function getWmsReceiptSession(client: WmsReceivingQueryClient, sessionId: string, actorAuthUserId: string): Promise<WmsReceiptSession> {
  const { data, error } = await client.rpc("get_wms_receipt_session", { p_session_id: sessionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsReceivingQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsReceivingQueryError("get_wms_receipt_session returned no row");
  }
  return parseWmsReceiptSession(row);
}

/** Every line on one receipt session, ordered by line_number. */
export async function listWmsReceiptLines(client: WmsReceivingQueryClient, sessionId: string, actorAuthUserId: string): Promise<WmsReceiptLine[]> {
  const { data, error } = await client.rpc("list_wms_receipt_lines", { p_session_id: sessionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsReceivingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsReceiptLine);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped by warehouse, optionally narrowed to one warehouse/inbound order/status. */
export async function listWmsReceiptSessions(
  client: WmsReceivingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; inboundOrderId?: string | null; statusFilter?: WmsReceiptSessionStatus | null; limit?: number },
): Promise<WmsReceiptSession[]> {
  const { data, error } = await client.rpc("list_wms_receipt_sessions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_inbound_order_id: options?.inboundOrderId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsReceivingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsReceiptSession);
}
