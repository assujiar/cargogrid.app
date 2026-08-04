/**
 * WMS Putaway read queries (ATW-014, CG-S10-ATW-014). Thin, typed wrappers around
 * app.get_wms_putaway_task/app.list_wms_putaway_task_confirmations/
 * app.list_wms_putaway_tasks
 * (supabase/migrations/20260730210000_create_advanced_tms_wms_putaway.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWmsPutawayTask,
  parseWmsPutawayConfirmation,
  type WmsPutawayTask,
  type WmsPutawayConfirmation,
  type WmsPutawayTaskStatus,
} from "../contracts/wms-putaway/wms-putaway.ts";

export type WmsPutawayQueryClient = Pick<SupabaseClient, "rpc">;

export class WmsPutawayQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WmsPutawayQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC- and record-scope-gated. */
export async function getWmsPutawayTask(client: WmsPutawayQueryClient, taskId: string, actorAuthUserId: string): Promise<WmsPutawayTask> {
  const { data, error } = await client.rpc("get_wms_putaway_task", { p_task_id: taskId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPutawayQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsPutawayQueryError("get_wms_putaway_task returned no row");
  }
  return parseWmsPutawayTask(row);
}

/** Every confirmation event on one task, ordered by confirmed_at. */
export async function listWmsPutawayTaskConfirmations(client: WmsPutawayQueryClient, taskId: string, actorAuthUserId: string): Promise<WmsPutawayConfirmation[]> {
  const { data, error } = await client.rpc("list_wms_putaway_task_confirmations", { p_task_id: taskId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPutawayQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPutawayConfirmation);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped by warehouse, optionally narrowed to one warehouse/receipt line/status/claimant. */
export async function listWmsPutawayTasks(
  client: WmsPutawayQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; receiptLineId?: string | null; statusFilter?: WmsPutawayTaskStatus | null; claimedByAuthUserId?: string | null; limit?: number },
): Promise<WmsPutawayTask[]> {
  const { data, error } = await client.rpc("list_wms_putaway_tasks", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_receipt_line_id: options?.receiptLineId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_claimed_by_auth_user_id: options?.claimedByAuthUserId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsPutawayQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPutawayTask);
}
