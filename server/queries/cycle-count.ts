/**
 * Cycle Count and Inventory Adjustment read queries (ATW-020, CG-S10-ATW-020). Thin,
 * typed wrappers around app.get_cycle_count_plan/app.list_cycle_count_plans/app.
 * get_cycle_count_scope_item/app.list_cycle_count_scope_items/app.list_cycle_count_
 * observations
 * (supabase/migrations/20260730270000_create_advanced_tms_cycle_count_adjustment.sql).
 *
 * Blind-count redaction (the migration's own design note 6) is applied server-side --
 * these wrappers simply parse whatever the RPC returns, which already has snapshot
 * ExpectedQuantity/varianceQuantity/variancePct/snapshotRecordVersion nulled out for a
 * plain OPS:Edit-only counter's own actor.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCycleCountPlan,
  parseCycleCountScopeItem,
  parseCycleCountObservation,
  type CycleCountPlan,
  type CycleCountScopeItem,
  type CycleCountObservation,
  type CycleCountPlanStatus,
  type CycleCountScopeItemStatus,
} from "../contracts/cycle-count/cycle-count.ts";

export type CycleCountQueryClient = Pick<SupabaseClient, "rpc">;

export class CycleCountQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CycleCountQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** OPS:View + record-scope by the plan's own warehouse -- a plan itself has no single owner_account_id, unlike a scope item. */
export async function getCycleCountPlan(client: CycleCountQueryClient, planId: string, actorAuthUserId: string): Promise<CycleCountPlan> {
  const { data, error } = await client.rpc("get_cycle_count_plan", { p_plan_id: planId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new CycleCountQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CycleCountQueryError("get_cycle_count_plan returned no row");
  }
  return parseCycleCountPlan(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped by warehouse. */
export async function listCycleCountPlans(
  client: CycleCountQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; statusFilter?: CycleCountPlanStatus | null; limit?: number },
): Promise<CycleCountPlan[]> {
  const { data, error } = await client.rpc("list_cycle_count_plans", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CycleCountQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCycleCountPlan);
}

/** OPS:View + owner-scope. Applies blind-count redaction server-side (design note 6). */
export async function getCycleCountScopeItem(client: CycleCountQueryClient, scopeItemId: string, actorAuthUserId: string): Promise<CycleCountScopeItem> {
  const { data, error } = await client.rpc("get_cycle_count_scope_item", { p_scope_item_id: scopeItemId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new CycleCountQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CycleCountQueryError("get_cycle_count_scope_item returned no row");
  }
  return parseCycleCountScopeItem(row);
}

/** Bounded (default 50, hard-capped 200 server-side), owner-scoped, blind-count-redacted row by row. */
export async function listCycleCountScopeItems(
  client: CycleCountQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { planId?: string | null; statusFilter?: CycleCountScopeItemStatus | null; assignedToAuthUserId?: string | null; limit?: number },
): Promise<CycleCountScopeItem[]> {
  const { data, error } = await client.rpc("list_cycle_count_scope_items", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_plan_id: options?.planId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_assigned_to_auth_user_id: options?.assignedToAuthUserId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CycleCountQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCycleCountScopeItem);
}

/** Every observation for one scope item, ordered by attempt_number. Never redacted -- this table stores only what was actually scanned/observed, never expected/variance values. */
export async function listCycleCountObservations(client: CycleCountQueryClient, scopeItemId: string, actorAuthUserId: string): Promise<CycleCountObservation[]> {
  const { data, error } = await client.rpc("list_cycle_count_observations", { p_scope_item_id: scopeItemId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new CycleCountQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCycleCountObservation);
}
