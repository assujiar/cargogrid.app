/**
 * Finance Dashboard read queries (FIN-213, CG-S9-FIN-024). Thin, typed wrappers
 * around the three genuinely new app.get_finance_dashboard_* RPCs -- each is a plain
 * `stable` function with its own explicit FIN:View check (see the migration's own
 * header for why none is `security definer`), so this layer adds no further access
 * check of its own, only shape parsing and the same real query-budget timeout
 * (RPD-014, Prompt 213 section 17) `server/queries/ops-dashboard.ts` (OPS-182)
 * already established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceDashboardBillingSummaryRow,
  parseFinanceDashboardCashSummaryRow,
  parseFinanceDashboardCloseStatusRow,
  type FinanceDashboardBillingSummaryRow,
  type FinanceDashboardCashSummaryRow,
  type FinanceDashboardCloseStatusRow,
} from "../contracts/finance-dashboard/finance-dashboard.ts";

export type FinanceDashboardQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class FinanceDashboardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FinanceDashboardQueryError";
  }
}

/** Thrown when an app.get_finance_dashboard_* call does not resolve within its query budget -- the exception-flow "fail visibly for timeout" Prompt 213 section 23 requires, never a silently-hung request. */
export class FinanceDashboardQueryTimeoutError extends FinanceDashboardQueryError {
  constructor(rpcName: string, budgetMs: number) {
    super(`${rpcName} exceeded its ${budgetMs}ms query budget`);
    this.name = "FinanceDashboardQueryTimeoutError";
  }
}

/** RPD-014's own "read-only queries, ... timeouts" live-OLTP control -- no dashboard call may run unbounded. */
export const DEFAULT_FINANCE_DASHBOARD_QUERY_BUDGET_MS = 5000;

export type FinanceDashboardQueryOptions = {
  budgetMs?: number;
};

function withQueryBudget<T>(pending: PromiseLike<T>, rpcName: string, budgetMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new FinanceDashboardQueryTimeoutError(rpcName, budgetMs)), budgetMs);
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

function resolveBudgetMs(options?: FinanceDashboardQueryOptions): number {
  return options?.budgetMs ?? DEFAULT_FINANCE_DASHBOARD_QUERY_BUDGET_MS;
}

export type FinanceDashboardScopeFilter = {
  tenantId: string;
  companyId: string | null;
  actorAuthUserId: string;
};

/** FIN:View-gated. Invoice count/total/open amount by (status, currency). */
export async function getFinanceDashboardBillingSummary(
  client: FinanceDashboardQueryRpcClient,
  filter: FinanceDashboardScopeFilter,
  options?: FinanceDashboardQueryOptions,
): Promise<FinanceDashboardBillingSummaryRow[]> {
  const { data, error } = await withQueryBudget(
    client.rpc("get_finance_dashboard_billing_summary", {
      p_tenant_id: filter.tenantId,
      p_company_id: filter.companyId,
      p_actor_auth_user_id: filter.actorAuthUserId,
    }),
    "get_finance_dashboard_billing_summary",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new FinanceDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new FinanceDashboardQueryError("get_finance_dashboard_billing_summary returned a non-array result");
  }
  return data.map((row) => parseFinanceDashboardBillingSummaryRow(row as Record<string, unknown>));
}

/** FIN:View-gated. One row per active bank account, reusing app.get_finance_cash_position (FIN-211) verbatim. */
export async function getFinanceDashboardCashSummary(
  client: FinanceDashboardQueryRpcClient,
  filter: FinanceDashboardScopeFilter & { asOfDate: string },
  options?: FinanceDashboardQueryOptions,
): Promise<FinanceDashboardCashSummaryRow[]> {
  const { data, error } = await withQueryBudget(
    client.rpc("get_finance_dashboard_cash_summary", {
      p_tenant_id: filter.tenantId,
      p_company_id: filter.companyId,
      p_as_of_date: filter.asOfDate,
      p_actor_auth_user_id: filter.actorAuthUserId,
    }),
    "get_finance_dashboard_cash_summary",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new FinanceDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new FinanceDashboardQueryError("get_finance_dashboard_cash_summary returned a non-array result");
  }
  return data.map((row) => parseFinanceDashboardCashSummaryRow(row as Record<string, unknown>));
}

/** FIN:View-gated. Per fiscal period (latest 12): most recent lock event and most recent in-range reconciliation run. */
export async function getFinanceDashboardCloseStatus(
  client: FinanceDashboardQueryRpcClient,
  filter: FinanceDashboardScopeFilter,
  options?: FinanceDashboardQueryOptions,
): Promise<FinanceDashboardCloseStatusRow[]> {
  const { data, error } = await withQueryBudget(
    client.rpc("get_finance_dashboard_close_status", {
      p_tenant_id: filter.tenantId,
      p_company_id: filter.companyId,
      p_actor_auth_user_id: filter.actorAuthUserId,
    }),
    "get_finance_dashboard_close_status",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new FinanceDashboardQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new FinanceDashboardQueryError("get_finance_dashboard_close_status returned a non-array result");
  }
  return data.map((row) => parseFinanceDashboardCloseStatusRow(row as Record<string, unknown>));
}
