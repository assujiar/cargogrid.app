/**
 * Operations Dashboard read queries (OPS-182, CG-S8-OPS-016). Thin, typed wrappers
 * around the six app.get_ops_dashboard_* RPCs -- each one is `security definer` with
 * its own explicit app.can_access_record row filter (see the migration's own header
 * for why), so this layer adds no further access check of its own, only shape parsing
 * and the same real query-budget timeout (RPD-014, Prompt 182 §17) `server/queries/
 * dashboard.ts` (COM-158) already established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  DashboardScopeFilterSchema,
  parseShipmentStatusEntry,
  parseMilestoneSlaEntry,
  parseExceptionQueueEntry,
  parseEpodCompletionEntry,
  parseCostVarianceEntry,
  parseBillingReadinessSummaryEntry,
  type DashboardScopeFilter,
  type ShipmentStatusEntry,
  type MilestoneSlaEntry,
  type ExceptionQueueEntry,
  type EpodCompletionEntry,
  type CostVarianceEntry,
  type BillingReadinessSummaryEntry,
} from "../contracts/ops-dashboard/ops-dashboard.ts";

export type OpsDashboardQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class OpsDashboardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OpsDashboardQueryError";
  }
}

/** Thrown when an app.get_ops_dashboard_* call does not resolve within its query budget -- the exception-flow "safe explicit state" Prompt 182 §23 requires, never a silently-hung request. */
export class OpsDashboardQueryTimeoutError extends OpsDashboardQueryError {
  constructor(rpcName: string, budgetMs: number) {
    super(`${rpcName} exceeded its ${budgetMs}ms query budget`);
    this.name = "OpsDashboardQueryTimeoutError";
  }
}

/** RPD-014's own "read-only queries, ... timeouts" live-OLTP control -- no dashboard call may run unbounded. */
export const DEFAULT_OPS_DASHBOARD_QUERY_BUDGET_MS = 5000;

export type OpsDashboardQueryOptions = {
  budgetMs?: number;
};

function withQueryBudget<T>(pending: PromiseLike<T>, rpcName: string, budgetMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new OpsDashboardQueryTimeoutError(rpcName, budgetMs)), budgetMs);
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

function resolveBudgetMs(options?: OpsDashboardQueryOptions): number {
  return options?.budgetMs ?? DEFAULT_OPS_DASHBOARD_QUERY_BUDGET_MS;
}

export async function getOpsDashboardShipmentStatus(
  client: OpsDashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: OpsDashboardQueryOptions,
): Promise<ShipmentStatusEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_ops_dashboard_shipment_status", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_ops_dashboard_shipment_status",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new OpsDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OpsDashboardQueryError("get_ops_dashboard_shipment_status returned a non-array result");
  }
  return data.map((row) => parseShipmentStatusEntry(row as Record<string, unknown>));
}

export async function getOpsDashboardMilestoneSla(
  client: OpsDashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: OpsDashboardQueryOptions,
): Promise<MilestoneSlaEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_ops_dashboard_milestone_sla", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_ops_dashboard_milestone_sla",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new OpsDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OpsDashboardQueryError("get_ops_dashboard_milestone_sla returned a non-array result");
  }
  return data.map((row) => parseMilestoneSlaEntry(row as Record<string, unknown>));
}

export async function getOpsDashboardExceptionQueue(
  client: OpsDashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: OpsDashboardQueryOptions,
): Promise<ExceptionQueueEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_ops_dashboard_exception_queue", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_ops_dashboard_exception_queue",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new OpsDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OpsDashboardQueryError("get_ops_dashboard_exception_queue returned a non-array result");
  }
  return data.map((row) => parseExceptionQueueEntry(row as Record<string, unknown>));
}

export async function getOpsDashboardEpodCompletion(
  client: OpsDashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: OpsDashboardQueryOptions,
): Promise<EpodCompletionEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_ops_dashboard_epod_completion", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_ops_dashboard_epod_completion",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new OpsDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OpsDashboardQueryError("get_ops_dashboard_epod_completion returned a non-array result");
  }
  return data.map((row) => parseEpodCompletionEntry(row as Record<string, unknown>));
}

export async function getOpsDashboardCostVariance(
  client: OpsDashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: OpsDashboardQueryOptions,
): Promise<CostVarianceEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_ops_dashboard_cost_variance", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_ops_dashboard_cost_variance",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new OpsDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OpsDashboardQueryError("get_ops_dashboard_cost_variance returned a non-array result");
  }
  return data.map((row) => parseCostVarianceEntry(row as Record<string, unknown>));
}

export async function getOpsDashboardBillingReadiness(
  client: OpsDashboardQueryRpcClient,
  filter: DashboardScopeFilter,
  options?: OpsDashboardQueryOptions,
): Promise<BillingReadinessSummaryEntry[]> {
  const parsed = DashboardScopeFilterSchema.parse(filter);
  const { data, error } = await withQueryBudget(
    client.rpc("get_ops_dashboard_billing_readiness", { p_tenant_id: parsed.tenantId, p_org_unit_id: parsed.orgUnitId, p_owner_user_id: parsed.ownerUserId }),
    "get_ops_dashboard_billing_readiness",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new OpsDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OpsDashboardQueryError("get_ops_dashboard_billing_readiness returned a non-array result");
  }
  return data.map((row) => parseBillingReadinessSummaryEntry(row as Record<string, unknown>));
}
