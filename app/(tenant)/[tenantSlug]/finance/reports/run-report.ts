import type { SupabaseClient } from "@supabase/supabase-js";
import { getFinanceDashboardBillingSummary, getFinanceDashboardCashSummary, getFinanceDashboardCloseStatus } from "../../../../../server/queries/finance-dashboard.ts";
import { getFinanceAgingSummary } from "../../../../../server/queries/aging.ts";
import { getFinanceProfitabilitySummary } from "../../../../../server/queries/profitability.ts";

const AS_OF_DATE = new Date().toISOString().slice(0, 10);

/**
 * Dispatches a report code to its one named source_function (FIN-213's own migration
 * header: "adds no new aggregation SQL" beyond the three genuinely new widgets),
 * reusing FIN-210/FIN-211/FIN-212's own governed queries verbatim where they already
 * exist -- the same dispatch shape `operations/reports/run-report.ts` (OPS-183)
 * already established. Returns each row already flattened to plain objects so the
 * report page can render a generic table.
 */
export async function runFinanceReportByCode(
  client: SupabaseClient,
  reportTypeCode: string,
  filter: { tenantId: string; actorAuthUserId: string },
): Promise<readonly Record<string, unknown>[]> {
  switch (reportTypeCode) {
    case "finance_billing_summary":
      return getFinanceDashboardBillingSummary(client, { tenantId: filter.tenantId, companyId: null, actorAuthUserId: filter.actorAuthUserId });
    case "finance_ar_aging_summary":
      return getFinanceAgingSummary(client, { tenantId: filter.tenantId, companyId: null, entityType: "ar", asOfDate: AS_OF_DATE, includeHeld: true, actorAuthUserId: filter.actorAuthUserId });
    case "finance_ap_aging_summary":
      return getFinanceAgingSummary(client, { tenantId: filter.tenantId, companyId: null, entityType: "ap", asOfDate: AS_OF_DATE, includeHeld: true, actorAuthUserId: filter.actorAuthUserId });
    case "finance_cash_summary":
      return getFinanceDashboardCashSummary(client, { tenantId: filter.tenantId, companyId: null, actorAuthUserId: filter.actorAuthUserId, asOfDate: AS_OF_DATE });
    case "finance_close_status_summary":
      return getFinanceDashboardCloseStatus(client, { tenantId: filter.tenantId, companyId: null, actorAuthUserId: filter.actorAuthUserId });
    case "finance_profitability_summary":
      return getFinanceProfitabilitySummary(client, { tenantId: filter.tenantId, groupBy: "customer", actorAuthUserId: filter.actorAuthUserId });
    default:
      return [];
  }
}

/** Every `*Masked`-shaped boolean flag that was true in at least one row -- an honest, generic audit signal (Prompt 213 section 18's "field policy"), the same generic collector `operations/reports/run-report.ts` (OPS-183) already established. No Finance report currently emits one -- reserved for a future masked-field report. */
export function collectMaskedColumnFlags(rows: readonly Record<string, unknown>[]): string[] {
  const flags = new Set<string>();
  for (const row of rows) {
    for (const [key, value] of Object.entries(row)) {
      if (key.toLowerCase().endsWith("masked") && value === true) {
        flags.add(key);
      }
    }
  }
  return [...flags].sort();
}
