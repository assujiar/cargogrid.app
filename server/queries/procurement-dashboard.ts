/**
 * Procurement Dashboard read queries (PRC-266, CG-S11-PRC-017). Thin, typed wrappers
 * around the ten new `app.get_procurement_dashboard_*`/`app.list_procurement_vendor_
 * risk_dashboard_rows` RPCs (all SECURITY DEFINER, explicit `p_tenant_id`/
 * `p_actor_auth_user_id`, `evaluate_permission` first -- mirrors server/queries/
 * vendor-performance.ts's own "this file calls `.rpc(...)`, never `.from(...)`, on a
 * base table" convention exactly), plus the metric-definition catalogue (a plain
 * `.from()` read -- app.procurement_metric_definitions carries no RLS and no masked
 * column, mirroring server/queries/report.ts's own identical `.from("report_types")`
 * shape) and saved views (RPC, owner-scoped). Every summary RPC also carries the same
 * explicit query-budget timeout server/queries/finance-dashboard.ts (FIN-213)
 * established (RPD-014).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseProcurementMetricDefinition,
  parseProcurementDashboardSavedView,
  parseProcurementDashboardVendorRiskSummaryRow,
  parseProcurementVendorRiskDashboardRow,
  parseProcurementDashboardRateValiditySummaryRow,
  parseProcurementDashboardRateCompetitivenessSummaryRow,
  parseProcurementDashboardRfqCycleSummaryRow,
  parseProcurementDashboardCapacityReservationSummaryRow,
  parseProcurementDashboardAssignmentAcceptanceSummaryRow,
  parseProcurementDashboardPoSummaryRow,
  parseProcurementDashboardContractSummaryRow,
  parseProcurementDashboardPerformanceSummaryRow,
  type ProcurementMetricDefinition,
  type ProcurementDashboardSavedView,
  type ProcurementDashboardMetricGroup,
  type ProcurementDashboardVendorRiskSummaryRow,
  type ProcurementVendorRiskDashboardRow,
  type ProcurementDashboardRateValiditySummaryRow,
  type ProcurementDashboardRateCompetitivenessSummaryRow,
  type ProcurementDashboardRfqCycleSummaryRow,
  type ProcurementDashboardCapacityReservationSummaryRow,
  type ProcurementDashboardAssignmentAcceptanceSummaryRow,
  type ProcurementDashboardPoSummaryRow,
  type ProcurementDashboardContractSummaryRow,
  type ProcurementDashboardPerformanceSummaryRow,
} from "../contracts/procurement-dashboard/procurement-dashboard.ts";

export type ProcurementDashboardQueryClient = Pick<SupabaseClient, "rpc" | "from">;

export class ProcurementDashboardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProcurementDashboardQueryError";
  }
}

/** Thrown when a dashboard RPC does not resolve within its query budget -- the exception-flow "fail visibly for timeout" Prompt 266 section 23 requires, never a silently-hung request. */
export class ProcurementDashboardQueryTimeoutError extends ProcurementDashboardQueryError {
  constructor(rpcName: string, budgetMs: number) {
    super(`${rpcName} exceeded its ${budgetMs}ms query budget`);
    this.name = "ProcurementDashboardQueryTimeoutError";
  }
}

/** RPD-014's own "read-only queries, ... timeouts" live-OLTP control -- no dashboard call may run unbounded. */
export const DEFAULT_PROCUREMENT_DASHBOARD_QUERY_BUDGET_MS = 5000;

export type ProcurementDashboardQueryOptions = { budgetMs?: number };

function withQueryBudget<T>(pending: PromiseLike<T>, rpcName: string, budgetMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new ProcurementDashboardQueryTimeoutError(rpcName, budgetMs)), budgetMs);
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

function resolveBudgetMs(options?: ProcurementDashboardQueryOptions): number {
  return options?.budgetMs ?? DEFAULT_PROCUREMENT_DASHBOARD_QUERY_BUDGET_MS;
}

async function callRpcRows<T>(
  client: ProcurementDashboardQueryClient,
  fn: string,
  args: Record<string, unknown>,
  parse: (row: Record<string, unknown>) => T,
  options?: ProcurementDashboardQueryOptions,
): Promise<T[]> {
  const { data, error } = await withQueryBudget(client.rpc(fn, args), fn, resolveBudgetMs(options));
  if (error) {
    throw new ProcurementDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ProcurementDashboardQueryError(`${fn} returned a non-array result`);
  }
  return data.map((row) => parse(row as Record<string, unknown>));
}

export type ProcurementDashboardScopeFilter = { tenantId: string; actorAuthUserId: string };
export type ProcurementDashboardWindowFilter = ProcurementDashboardScopeFilter & { windowStart?: string | null; windowEnd?: string | null };

// -- Metric definition catalogue -----------------------------------------

/** Broadly readable, non-tenant-scoped, non-sensitive platform metadata (mirrors app.report_types / listActiveReportTypes) -- never masked, never gated on a PRC permission. */
export async function listActiveProcurementMetricDefinitions(client: ProcurementDashboardQueryClient): Promise<ProcurementMetricDefinition[]> {
  const { data, error } = await client.from("procurement_metric_definitions").select("*").eq("is_current", true).eq("status", "active").order("metric_group", { ascending: true });
  if (error) {
    throw new ProcurementDashboardQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseProcurementMetricDefinition(row));
}

// -- Saved views -----------------------------------------

export async function listProcurementDashboardSavedViews(
  client: ProcurementDashboardQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  metricGroup: ProcurementDashboardMetricGroup | null = null,
  limit = 25,
  cursor: string | null = null,
  cursorId: string | null = null,
): Promise<ProcurementDashboardSavedView[]> {
  // Tier C batch-5 fix: p_cursor_id (composite created_at+id keyset) closes a
  // live-reproduced tie-drop defect on the single-column created_at cursor -- always
  // pass both together when paginating past page 1.
  const { data, error } = await client.rpc("list_procurement_dashboard_saved_views", { p_tenant_id: tenantId, p_metric_group: metricGroup, p_actor_auth_user_id: actorAuthUserId, p_limit: limit, p_cursor: cursor, p_cursor_id: cursorId });
  if (error) throw new ProcurementDashboardQueryError(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => parseProcurementDashboardSavedView(row));
}

export async function getProcurementDashboardSavedView(client: ProcurementDashboardQueryClient, viewId: string, actorAuthUserId: string): Promise<ProcurementDashboardSavedView> {
  const { data, error } = await client.rpc("get_procurement_dashboard_saved_view", { p_view_id: viewId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new ProcurementDashboardQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) throw new ProcurementDashboardQueryError("get_procurement_dashboard_saved_view returned no row");
  return parseProcurementDashboardSavedView(row as Record<string, unknown>);
}

// -- Group 1: vendor risk / compliance-expiry -----------------------------------------

export async function getProcurementDashboardVendorRiskSummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardScopeFilter, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardVendorRiskSummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_vendor_risk_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId }, parseProcurementDashboardVendorRiskSummaryRow, options);
}

export type ListProcurementVendorRiskDashboardRowsFilter = ProcurementDashboardScopeFilter & {
  lifecycleStatus?: string | null;
  complianceHoldOnly?: boolean | null;
  band?: string | null;
  search?: string | null;
  limit?: number;
  cursor?: string | null;
  cursorId?: string | null;
};

export async function listProcurementVendorRiskDashboardRows(client: ProcurementDashboardQueryClient, filter: ListProcurementVendorRiskDashboardRowsFilter, options?: ProcurementDashboardQueryOptions): Promise<ProcurementVendorRiskDashboardRow[]> {
  // Tier C batch-5 fix: p_cursor_id (composite created_at+vendor_master_id keyset)
  // closes a live-reproduced tie-drop defect on the single-column created_at cursor --
  // always pass both together when paginating past page 1.
  return callRpcRows(
    client,
    "list_procurement_vendor_risk_dashboard_rows",
    {
      p_tenant_id: filter.tenantId,
      p_actor_auth_user_id: filter.actorAuthUserId,
      p_lifecycle_status: filter.lifecycleStatus ?? null,
      p_compliance_hold_only: filter.complianceHoldOnly ?? null,
      p_band: filter.band ?? null,
      p_search: filter.search ?? null,
      p_limit: filter.limit ?? 25,
      p_cursor: filter.cursor ?? null,
      p_cursor_id: filter.cursorId ?? null,
    },
    parseProcurementVendorRiskDashboardRow,
    options,
  );
}

// -- Group 2: rate validity / competitiveness -----------------------------------------

export async function getProcurementDashboardRateValiditySummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardScopeFilter & { asOf?: string | null }, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardRateValiditySummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_rate_validity_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId, p_as_of: filter.asOf ?? null }, parseProcurementDashboardRateValiditySummaryRow, options);
}

export async function getProcurementDashboardRateCompetitivenessSummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardScopeFilter, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardRateCompetitivenessSummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_rate_competitiveness_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId }, parseProcurementDashboardRateCompetitivenessSummaryRow, options);
}

// -- Group 3: RFQ response rate / cycle time -----------------------------------------

export async function getProcurementDashboardRfqCycleSummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardWindowFilter, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardRfqCycleSummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_rfq_cycle_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId, p_window_start: filter.windowStart ?? null, p_window_end: filter.windowEnd ?? null }, parseProcurementDashboardRfqCycleSummaryRow, options);
}

// -- Group 4: capacity / acceptance -----------------------------------------

export async function getProcurementDashboardCapacityReservationSummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardWindowFilter, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardCapacityReservationSummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_capacity_reservation_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId, p_window_start: filter.windowStart ?? null, p_window_end: filter.windowEnd ?? null }, parseProcurementDashboardCapacityReservationSummaryRow, options);
}

export async function getProcurementDashboardAssignmentAcceptanceSummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardWindowFilter, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardAssignmentAcceptanceSummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_assignment_acceptance_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId, p_window_start: filter.windowStart ?? null, p_window_end: filter.windowEnd ?? null }, parseProcurementDashboardAssignmentAcceptanceSummaryRow, options);
}

// -- Group 5: PO / contract -----------------------------------------

export async function getProcurementDashboardPoSummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardScopeFilter, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardPoSummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_po_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId }, parseProcurementDashboardPoSummaryRow, options);
}

export async function getProcurementDashboardContractSummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardScopeFilter & { asOf?: string | null }, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardContractSummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_contract_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId, p_as_of: filter.asOf ?? null }, parseProcurementDashboardContractSummaryRow, options);
}

// -- Group 6: performance -----------------------------------------

export async function getProcurementDashboardPerformanceSummary(client: ProcurementDashboardQueryClient, filter: ProcurementDashboardScopeFilter, options?: ProcurementDashboardQueryOptions): Promise<ProcurementDashboardPerformanceSummaryRow[]> {
  return callRpcRows(client, "get_procurement_dashboard_performance_summary", { p_tenant_id: filter.tenantId, p_actor_auth_user_id: filter.actorAuthUserId }, parseProcurementDashboardPerformanceSummaryRow, options);
}

// -- Group 7: match variance / exception rate -----------------------------------------
// Entirely reused from PRC-265 -- see server/queries/vendor-invoice-matching.ts's own
// getVendorBillMatchReconciliationStatus. No wrapper is duplicated here (design note 2).
