/**
 * Commercial Dashboard read queries (COM-158, CG-S7-COM-017). Thin, typed wrappers
 * around the seven app.get_dashboard_* RPCs -- each one is `security definer` with its
 * own explicit app.can_access_record row filter (see the migration's own header for why
 * an invoker-mode read cannot work here), so this layer adds no further access check of
 * its own, only shape parsing and a real query-budget timeout (RPD-014, Prompt 158 §17).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  DashboardScopeFilterSchema,
  DashboardPeriodFilterSchema,
  parseLeadAgingEntry,
  parseActivityQueueEntry,
  parsePipelineSummaryEntry,
  parseQuoteSlaEntry,
  parseMarginSummaryEntry,
  parseWinLossSummaryEntry,
  parseForecastSummaryEntry,
  type DashboardScopeFilter,
  type DashboardPeriodFilter,
  type LeadAgingEntry,
  type ActivityQueueEntry,
  type PipelineSummaryEntry,
  type QuoteSlaEntry,
  type MarginSummaryEntry,
  type WinLossSummaryEntry,
  type ForecastSummaryEntry,
} from "../contracts/dashboard/dashboard.ts";

export type DashboardQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class DashboardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DashboardQueryError";
  }
}

/** Thrown when an app.get_dashboard_* call does not resolve within its query budget -- the exception-flow "safe explicit state" Prompt 158 §23 requires, never a silently-hung request. */
export class DashboardQueryTimeoutError extends DashboardQueryError {
  constructor(rpcName: string, budgetMs: number) {
    super(`${rpcName} exceeded its ${budgetMs}ms query budget`);
    this.name = "DashboardQueryTimeoutError";
  }
}

/** RPD-014's own "read-only queries, ... timeouts" live-OLTP control -- no dashboard call may run unbounded. */
export const DEFAULT_DASHBOARD_QUERY_BUDGET_MS = 5000;

export type DashboardQueryOptions = {
  budgetMs?: number;
};

function withQueryBudget<T>(pending: PromiseLike<T>, rpcName: string, budgetMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new DashboardQueryTimeoutError(rpcName, budgetMs)), budgetMs);
    Promise.resolve(pending).then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err: unknown) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

function resolveBudgetMs(options?: DashboardQueryOptions): number {
  return options?.budgetMs ?? DEFAULT_DASHBOARD_QUERY_BUDGET_MS;
}

export async function getDashboardLeadAging(
  client: DashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: DashboardQueryOptions,
): Promise<LeadAgingEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_dashboard_lead_aging", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_dashboard_lead_aging",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new DashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new DashboardQueryError("get_dashboard_lead_aging returned a non-array result");
  }
  return data.map((row) => parseLeadAgingEntry(row as Record<string, unknown>));
}

export async function getDashboardActivityQueue(
  client: DashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: DashboardQueryOptions,
): Promise<ActivityQueueEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_dashboard_activity_queue", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_dashboard_activity_queue",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new DashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new DashboardQueryError("get_dashboard_activity_queue returned a non-array result");
  }
  return data.map((row) => parseActivityQueueEntry(row as Record<string, unknown>));
}

export async function getDashboardPipelineSummary(
  client: DashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: DashboardQueryOptions,
): Promise<PipelineSummaryEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_dashboard_pipeline_summary", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_dashboard_pipeline_summary",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new DashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new DashboardQueryError("get_dashboard_pipeline_summary returned a non-array result");
  }
  return data.map((row) => parsePipelineSummaryEntry(row as Record<string, unknown>));
}

export async function getDashboardQuoteSla(
  client: DashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: DashboardQueryOptions,
): Promise<QuoteSlaEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_dashboard_quote_sla", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_dashboard_quote_sla",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new DashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new DashboardQueryError("get_dashboard_quote_sla returned a non-array result");
  }
  return data.map((row) => parseQuoteSlaEntry(row as Record<string, unknown>));
}

export async function getDashboardMarginSummary(
  client: DashboardQueryRpcClient,
  filter: DashboardPeriodFilter,
  options?: DashboardQueryOptions,
): Promise<MarginSummaryEntry[]> {
  const parsed = DashboardPeriodFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_dashboard_margin_summary", {
      p_tenant_id: parsed.tenantId,
      p_org_unit_id: parsed.orgUnitId,
      p_owner_user_id: parsed.ownerUserId,
      p_period_start: parsed.periodStart,
      p_period_end: parsed.periodEnd,
    }),
    "get_dashboard_margin_summary",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new DashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new DashboardQueryError("get_dashboard_margin_summary returned a non-array result");
  }
  return data.map((row) => parseMarginSummaryEntry(row as Record<string, unknown>));
}

export async function getDashboardWinLossSummary(
  client: DashboardQueryRpcClient,
  filter: DashboardPeriodFilter,
  options?: DashboardQueryOptions,
): Promise<WinLossSummaryEntry[]> {
  const parsed = DashboardPeriodFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_dashboard_win_loss_summary", {
      p_tenant_id: parsed.tenantId,
      p_org_unit_id: parsed.orgUnitId,
      p_owner_user_id: parsed.ownerUserId,
      p_period_start: parsed.periodStart,
      p_period_end: parsed.periodEnd,
    }),
    "get_dashboard_win_loss_summary",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new DashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new DashboardQueryError("get_dashboard_win_loss_summary returned a non-array result");
  }
  return data.map((row) => parseWinLossSummaryEntry(row as Record<string, unknown>));
}

export async function getDashboardForecastSummary(
  client: DashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: DashboardQueryOptions,
): Promise<ForecastSummaryEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_dashboard_forecast_summary", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_dashboard_forecast_summary",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new DashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new DashboardQueryError("get_dashboard_forecast_summary returned a non-array result");
  }
  return data.map((row) => parseForecastSummaryEntry(row as Record<string, unknown>));
}
