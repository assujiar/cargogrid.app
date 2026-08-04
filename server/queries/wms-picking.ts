/**
 * WMS Picking read queries (ATW-017, CG-S10-ATW-017). Thin, typed wrappers around
 * app.get_wms_pick_task/app.list_wms_pick_task_confirmations/app.list_wms_pick_task_
 * shorts/app.list_wms_pick_substitution_approvals/app.list_wms_pick_tasks/app.
 * list_wms_pick_waves
 * (supabase/migrations/20260730240000_create_advanced_tms_wms_picking.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWmsPickTask,
  parseWmsPickTaskConfirmation,
  parseWmsPickTaskShort,
  parseWmsPickSubstitutionApproval,
  parseWmsPickWave,
  type WmsPickTask,
  type WmsPickTaskConfirmation,
  type WmsPickTaskShort,
  type WmsPickSubstitutionApproval,
  type WmsPickWave,
  type WmsPickTaskStatus,
} from "../contracts/wms-picking/wms-picking.ts";

export type WmsPickingQueryClient = Pick<SupabaseClient, "rpc">;

export class WmsPickingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WmsPickingQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC-, record-scope- and owner-scope-gated (bug class f). */
export async function getWmsPickTask(client: WmsPickingQueryClient, taskId: string, actorAuthUserId: string): Promise<WmsPickTask> {
  const { data, error } = await client.rpc("get_wms_pick_task", { p_task_id: taskId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPickingQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsPickingQueryError("get_wms_pick_task returned no row");
  }
  return parseWmsPickTask(row);
}

/** Every confirm-scan event on one task, ordered by confirmed_at. */
export async function listWmsPickTaskConfirmations(client: WmsPickingQueryClient, taskId: string, actorAuthUserId: string): Promise<WmsPickTaskConfirmation[]> {
  const { data, error } = await client.rpc("list_wms_pick_task_confirmations", { p_task_id: taskId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPickingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPickTaskConfirmation);
}

/** Every recorded short event on one task, ordered by recorded_at. */
export async function listWmsPickTaskShorts(client: WmsPickingQueryClient, taskId: string, actorAuthUserId: string): Promise<WmsPickTaskShort[]> {
  const { data, error } = await client.rpc("list_wms_pick_task_shorts", { p_task_id: taskId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPickingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPickTaskShort);
}

/** Every governed substitution approval on one task, ordered by approved_at. */
export async function listWmsPickSubstitutionApprovals(client: WmsPickingQueryClient, taskId: string, actorAuthUserId: string): Promise<WmsPickSubstitutionApproval[]> {
  const { data, error } = await client.rpc("list_wms_pick_substitution_approvals", { p_task_id: taskId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsPickingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPickSubstitutionApproval);
}

/** Bounded (default 50, hard-capped 200 server-side), record- and owner-scoped, optionally narrowed to one warehouse/outbound order/line/wave/owner/status/claimant. */
export async function listWmsPickTasks(
  client: WmsPickingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: {
    warehouseId?: string | null;
    outboundOrderId?: string | null;
    outboundOrderLineId?: string | null;
    waveId?: string | null;
    ownerAccountId?: string | null;
    statusFilter?: WmsPickTaskStatus | null;
    claimedByAuthUserId?: string | null;
    limit?: number;
  },
): Promise<WmsPickTask[]> {
  const { data, error } = await client.rpc("list_wms_pick_tasks", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_outbound_order_id: options?.outboundOrderId ?? null,
    p_outbound_order_line_id: options?.outboundOrderLineId ?? null,
    p_wave_id: options?.waveId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_claimed_by_auth_user_id: options?.claimedByAuthUserId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsPickingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPickTask);
}

/** Bounded (default 50, hard-capped 200 server-side), warehouse-scoped only (a wave is never owner-scoped). */
export async function listWmsPickWaves(
  client: WmsPickingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; limit?: number },
): Promise<WmsPickWave[]> {
  const { data, error } = await client.rpc("list_wms_pick_waves", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsPickingQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsPickWave);
}
