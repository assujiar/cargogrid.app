/**
 * Finance Dashboard and Reports read queries (FIN-213, CG-S9-FIN-024). Thin,
 * typed wrappers around app.get_finance_dashboard_billing_summary /
 * app.get_finance_dashboard_reconciliation_summary /
 * app.get_finance_dashboard_cash_summary
 * (supabase/migrations/20260729270000_create_finance_dashboard.sql). The
 * AR/AP aging and profitability sections of the dashboard reuse
 * server/queries/aging.ts and server/queries/profitability.ts directly --
 * no duplicate read path is added here.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceDashboardBillingRow,
  parseFinanceDashboardReconciliationRow,
  parseFinanceDashboardCashRow,
  type FinanceDashboardBillingRow,
  type FinanceDashboardReconciliationRow,
  type FinanceDashboardCashRow,
} from "../contracts/finance-dashboard/finance-dashboard.ts";

export type FinanceDashboardQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class FinanceDashboardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FinanceDashboardQueryError";
  }
}

/** FIN:View-gated. Real invoices grouped by status/currency -- never a raw per-invoice row. */
export async function getFinanceDashboardBillingSummary(
  client: FinanceDashboardQueryRpcClient,
  input: { tenantId: string; companyId: string | null; actorAuthUserId: string },
): Promise<FinanceDashboardBillingRow[]> {
  const { data, error } = await client.rpc("get_finance_dashboard_billing_summary", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new FinanceDashboardQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceDashboardBillingRow(row as Record<string, unknown>));
}

/** FIN:View-gated. The most recent reconciliation run per scope (ar/ap), reusing FIN-209's own computed variance. */
export async function getFinanceDashboardReconciliationSummary(
  client: FinanceDashboardQueryRpcClient,
  input: { tenantId: string; companyId: string | null; actorAuthUserId: string },
): Promise<FinanceDashboardReconciliationRow[]> {
  const { data, error } = await client.rpc("get_finance_dashboard_reconciliation_summary", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new FinanceDashboardQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceDashboardReconciliationRow(row as Record<string, unknown>));
}

/** FIN:View-gated. Composed across every one of the tenant's own bank accounts, grouped by currency. */
export async function getFinanceDashboardCashSummary(
  client: FinanceDashboardQueryRpcClient,
  input: { tenantId: string; companyId: string | null; asOfDate: string; actorAuthUserId: string },
): Promise<FinanceDashboardCashRow[]> {
  const { data, error } = await client.rpc("get_finance_dashboard_cash_summary", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_as_of_date: input.asOfDate,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new FinanceDashboardQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceDashboardCashRow(row as Record<string, unknown>));
}
