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
export type PipelineQueryTableClient = Pick<SupabaseClient, "from">;

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

/** Sales plans for a tenant, most recently created first -- RLS (sales_plans_select_scoped) is the real scope gate. */
export async function listSalesPlans(client: PipelineQueryTableClient, tenantId: string): Promise<SalesPlan[]> {
  const { data, error } = await client
    .from("sales_plans")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSalesPlan(row));
}

/** A single sales plan by id, for the Plan Detail view -- returns null (never an error) when RLS/no-match yields zero rows. */
export async function getSalesPlanById(client: PipelineQueryTableClient, planId: string): Promise<SalesPlan | null> {
  const { data, error } = await client.from("sales_plans").select("*").eq("id", planId).maybeSingle();
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseSalesPlan(data as Record<string, unknown>);
}

/** The targets belonging to one sales plan -- RLS (sales_targets_select_scoped) is the real scope gate. */
export async function listSalesTargetsForPlan(client: PipelineQueryTableClient, salesPlanId: string): Promise<SalesTarget[]> {
  const { data, error } = await client
    .from("sales_targets")
    .select("*")
    .eq("sales_plan_id", salesPlanId)
    .order("metric_type", { ascending: true });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSalesTarget(row));
}

/** Snapshot history for one target, most recent first -- RLS (forecast_snapshots_select_scoped) is the real scope gate. */
export async function listForecastSnapshotsForTarget(client: PipelineQueryTableClient, salesTargetId: string): Promise<ForecastSnapshot[]> {
  const { data, error } = await client
    .from("forecast_snapshots")
    .select("*")
    .eq("sales_target_id", salesTargetId)
    .order("snapshot_at", { ascending: false });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseForecastSnapshot(row));
}

/** Active pipeline categories for a tenant, in display order -- tenant-membership-scoped reference data (see COM-146's build log). */
export async function listPipelineCategories(client: PipelineQueryTableClient, tenantId: string): Promise<PipelineCategory[]> {
  const { data, error } = await client
    .from("pipeline_categories")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("sort_order", { ascending: true });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parsePipelineCategory(row));
}

/** Win/loss reasons for a tenant -- tenant-membership-scoped reference data. */
export async function listWinLossReasons(client: PipelineQueryTableClient, tenantId: string): Promise<WinLossReason[]> {
  const { data, error } = await client
    .from("win_loss_reasons")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("label", { ascending: true });
  if (error) {
    throw new PipelineQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseWinLossReason(row));
}
