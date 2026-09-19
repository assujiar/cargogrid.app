/**
 * CRM Sales Plan and Pipeline read queries (COM-146, CG-S7-COM-005). Thin, typed
 * wrappers around app.get_pipeline_summary / app.get_sales_target_actual and direct
 * RLS-scoped selects for plans/targets/forecast snapshots/categories/reasons/outcomes --
 * the underlying RLS policies (and, for the pipeline summary, app.commercial_pipeline_view's
 * own security_invoker RLS pass-through) are the real access gate, not a second check here.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  GetPipelineSummaryInputSchema,
  parsePipelineStageSummaryEntry,
  parseSalesPlan,
  parseSalesTarget,
  parseForecastSnapshot,
  parsePipelineCategory,
  parseWinLossReason,
  type GetPipelineSummaryInput,
  type PipelineStageSummaryEntry,
  type SalesPlan,
  type SalesTarget,
  type ForecastSnapshot,
  type PipelineCategory,
  type WinLossReason,
} from "../contracts/pipeline/pipeline.ts";

export type PipelineQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class PipelineQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PipelineQueryError";
  }
}

/** The governed pipeline stage-count summary. SECURITY INVOKER end-to-end -- relies on the caller's own RLS, never a second scope check here. */
export async function getPipelineSummary(client: PipelineQueryRpcClient, input: GetPipelineSummaryInput): Promise<PipelineStageSummaryEntry[]> {
  const parsedInput = GetPipelineSummaryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_pipeline_summary", {
    p_tenant_id: parsedInput.tenantId,
    p_org_unit_id: parsedInput.orgUnitId,
  });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new PipelineQueryError("get_pipeline_summary returned a non-array result");
  }
  return data.map((row) => parsePipelineStageSummaryEntry(row as Record<string, unknown>));
}

/** Live drill-down parity check -- the same reconciled count a forecast snapshot would capture right now. */
export async function getSalesTargetActual(
  client: PipelineQueryRpcClient,
  salesTargetId: string,
  actorAuthUserId: string,
): Promise<number> {
  const { data, error } = await client.rpc("get_sales_target_actual", {
    p_sales_target_id: salesTargetId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  const parsed = Number(data);
  if (!Number.isFinite(parsed)) {
    throw new PipelineQueryError("get_sales_target_actual returned a non-numeric result");
  }
  return parsed;
}

/** Sales plans for a tenant, most recently created first -- app.list_sales_plans (SECURITY DEFINER) is the real scope gate. */
export async function listSalesPlans(client: PipelineQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<SalesPlan[]> {
  const { data, error } = await client.rpc("list_sales_plans", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: 200,
  });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSalesPlan(row));
}

/** A single sales plan by id, for the Plan Detail view -- returns null (never an error) when denied/no-match yields zero rows. */
export async function getSalesPlanById(client: PipelineQueryRpcClient, planId: string, actorAuthUserId: string): Promise<SalesPlan | null> {
  const { data, error } = await client.rpc("get_sales_plan_by_id", {
    p_plan_id: planId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  const row = Array.isArray(data) ? (data[0] ?? null) : data;
  if (!row) {
    return null;
  }
  return parseSalesPlan(row as Record<string, unknown>);
}

/** The targets belonging to one sales plan -- app.list_sales_targets_for_plan (SECURITY DEFINER) is the real scope gate. */
export async function listSalesTargetsForPlan(client: PipelineQueryRpcClient, salesPlanId: string, actorAuthUserId: string): Promise<SalesTarget[]> {
  const { data, error } = await client.rpc("list_sales_targets_for_plan", {
    p_sales_plan_id: salesPlanId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSalesTarget(row));
}

/** Snapshot history for one target, most recent first -- app.list_forecast_snapshots_for_target (SECURITY DEFINER) is the real scope gate. */
export async function listForecastSnapshotsForTarget(client: PipelineQueryRpcClient, salesTargetId: string, actorAuthUserId: string): Promise<ForecastSnapshot[]> {
  const { data, error } = await client.rpc("list_forecast_snapshots_for_target", {
    p_sales_target_id: salesTargetId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: 200,
  });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseForecastSnapshot(row));
}

/** Active pipeline categories for a tenant, in display order -- app.list_pipeline_categories (SECURITY DEFINER) is the real scope gate (see COM-146's build log). */
export async function listPipelineCategories(client: PipelineQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<PipelineCategory[]> {
  const { data, error } = await client.rpc("list_pipeline_categories", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: 200,
  });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parsePipelineCategory(row));
}

/** Win/loss reasons for a tenant -- app.list_win_loss_reasons (SECURITY DEFINER) is the real scope gate. */
export async function listWinLossReasons(client: PipelineQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<WinLossReason[]> {
  const { data, error } = await client.rpc("list_win_loss_reasons", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseWinLossReason(row));
}
