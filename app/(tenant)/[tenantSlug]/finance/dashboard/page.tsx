import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import {
  getFinanceDashboardBillingSummary,
  getFinanceDashboardCashSummary,
  getFinanceDashboardCloseStatus,
  FinanceDashboardQueryTimeoutError,
  FinanceDashboardQueryError,
} from "../../../../../server/queries/finance-dashboard.ts";
import { getFinanceAgingSummary, AgingQueryError } from "../../../../../server/queries/aging.ts";
import { getFinanceProfitabilitySummary, ProfitabilityQueryError } from "../../../../../server/queries/profitability.ts";
import type { FinanceDashboardBillingSummaryRow, FinanceDashboardCashSummaryRow, FinanceDashboardCloseStatusRow } from "../../../../../server/contracts/finance-dashboard/finance-dashboard.ts";
import type { FinanceAgingSummaryRow } from "../../../../../server/contracts/aging/aging.ts";
import type { FinanceProfitabilitySummaryRow } from "../../../../../server/contracts/profitability/profitability.ts";

/**
 * Finance Dashboard (FIN-213, CG-S9-FIN-024): permission-safe live Finance metrics --
 * billing/invoice, AR/AP aging, cash, close/reconciliation and profitability -- each
 * sourced from its own already-FIN:View-checked query (four reused verbatim from
 * FIN-210/FIN-211, three genuinely new -- see the migration's own header). Billing,
 * aging, cash and close all share the same FIN:View baseline and are fetched
 * together; a caller who lacks FIN:View entirely sees one page-level denial rather
 * than five separate ones. Profitability additionally requires FIN:View margin
 * (FIN-212's own stricter, "deny outright" gate) and is fetched independently so a
 * caller with FIN:View but not FIN:View margin still sees every other widget --
 * only the profitability card renders as permission-denied, mirroring the Operations
 * Dashboard's own "masked without OPS:View cost" precedent for a stricter sub-permission.
 */

const AS_OF_DATE = new Date().toISOString().slice(0, 10);

type BaselineWidgets = {
  billing: FinanceDashboardBillingSummaryRow[];
  arAging: FinanceAgingSummaryRow[];
  apAging: FinanceAgingSummaryRow[];
  cash: FinanceDashboardCashSummaryRow[];
  close: FinanceDashboardCloseStatusRow[];
};

export default async function FinanceDashboardPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const filter = { tenantId: access.tenant.id, companyId: null, actorAuthUserId: access.authUserId };

  let baseline: BaselineWidgets | null = null;
  let baselineError: "timeout" | "denied" | "failed" | null = null;
  try {
    const [billing, arAging, apAging, cash, close] = await Promise.all([
      getFinanceDashboardBillingSummary(supabase, filter),
      getFinanceAgingSummary(supabase, { tenantId: filter.tenantId, companyId: null, entityType: "ar", asOfDate: AS_OF_DATE, includeHeld: true, actorAuthUserId: filter.actorAuthUserId }),
      getFinanceAgingSummary(supabase, { tenantId: filter.tenantId, companyId: null, entityType: "ap", asOfDate: AS_OF_DATE, includeHeld: true, actorAuthUserId: filter.actorAuthUserId }),
      getFinanceDashboardCashSummary(supabase, { ...filter, asOfDate: AS_OF_DATE }),
      getFinanceDashboardCloseStatus(supabase, filter),
    ]);
    baseline = { billing, arAging, apAging, cash, close };
  } catch (error) {
    if (error instanceof FinanceDashboardQueryTimeoutError) {
      baselineError = "timeout";
    } else if (error instanceof FinanceDashboardQueryError || error instanceof AgingQueryError) {
      baselineError = /insufficient_authority/.test(error.message) ? "denied" : "failed";
    } else {
      throw error;
    }
  }

  let profitability: FinanceProfitabilitySummaryRow[] | null = null;
  let profitabilityDenied = false;
  try {
    profitability = await getFinanceProfitabilitySummary(supabase, { tenantId: filter.tenantId, groupBy: "customer", actorAuthUserId: filter.actorAuthUserId });
  } catch (error) {
    if (!(error instanceof ProfitabilityQueryError)) {
      throw error;
    }
    profitabilityDenied = true;
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold text-text-primary">Finance dashboard</h1>
        {baseline ? <p className="text-xs text-text-secondary">As of {AS_OF_DATE}</p> : null}
      </div>

      {baselineError === "denied" ? (
        <ErrorState description="You don't hold the View permission for Finance. Ask a Finance administrator to grant FIN:View." />
      ) : baselineError === "timeout" ? (
        <ErrorState description="The dashboard is taking longer than expected to load. Please try again." />
      ) : baselineError === "failed" ? (
        <ErrorState description="Something went wrong loading the dashboard. Please try again." />
      ) : null}

      {baseline ? (
        <>
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">Billing</h2>
            {baseline.billing.length === 0 ? (
              <p className="text-sm text-text-secondary">No invoices in scope.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-5">
                {baseline.billing.map((row) => (
                  <li key={`${row.status}-${row.currency}`} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-text-secondary">
                      {row.status.replace(/_/g, " ")} ({row.currency})
                    </p>
                    <p className="text-lg font-semibold text-text-primary">{row.invoiceCount}</p>
                    <p className="text-xs text-text-secondary">Open: {row.openAmount}</p>
                  </li>
                ))}
              </ul>
            )}
            <a href={`/${tenantSlug}/finance/invoices`} className="text-sm font-medium text-primary underline">
              Open invoices
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">AR aging</h2>
            {baseline.arAging.length === 0 ? (
              <p className="text-sm text-text-secondary">No open AR items in scope.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {baseline.arAging.map((row) => (
                  <li key={`${row.bucketLabel}-${row.currency}`} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-text-secondary">
                      {row.bucketLabel} ({row.currency})
                    </p>
                    <p className="text-lg font-semibold text-text-primary">{row.openAmount}</p>
                    <p className="text-xs text-text-secondary">{row.itemCount} items</p>
                  </li>
                ))}
              </ul>
            )}
            <a href={`/${tenantSlug}/finance/aging?entityType=ar`} className="text-sm font-medium text-primary underline">
              Open AR aging report
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">AP aging</h2>
            {baseline.apAging.length === 0 ? (
              <p className="text-sm text-text-secondary">No open AP items in scope.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {baseline.apAging.map((row) => (
                  <li key={`${row.bucketLabel}-${row.currency}`} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-text-secondary">
                      {row.bucketLabel} ({row.currency})
                    </p>
                    <p className="text-lg font-semibold text-text-primary">{row.openAmount}</p>
                    <p className="text-xs text-text-secondary">{row.itemCount} items</p>
                  </li>
                ))}
              </ul>
            )}
            <a href={`/${tenantSlug}/finance/aging?entityType=ap`} className="text-sm font-medium text-primary underline">
              Open AP aging report
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">Cash</h2>
            {baseline.cash.length === 0 ? (
              <p className="text-sm text-text-secondary">No active bank accounts in scope.</p>
            ) : (
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-text-secondary">
                    <th scope="col" className="py-2 pr-4 font-medium">Account</th>
                    <th scope="col" className="py-2 pr-4 font-medium">Currency</th>
                    <th scope="col" className="py-2 pr-4 font-medium">Statement</th>
                    <th scope="col" className="py-2 pr-4 font-medium">GL</th>
                    <th scope="col" className="py-2 font-medium">Variance</th>
                  </tr>
                </thead>
                <tbody>
                  {baseline.cash.map((row) => (
                    <tr key={row.bankAccountId} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-text-primary">{row.accountName}</td>
                      <td className="py-2 pr-4 text-text-secondary">{row.currency}</td>
                      <td className="py-2 pr-4 text-text-secondary">{row.statementBalance}</td>
                      <td className="py-2 pr-4 text-text-secondary">{row.glBalance}</td>
                      <td className="py-2 text-text-secondary">{row.varianceAmount}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            <a href={`/${tenantSlug}/finance/cash-bank`} className="text-sm font-medium text-primary underline">
              Open cash and bank
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">Close and reconciliation</h2>
            {baseline.close.length === 0 ? (
              <p className="text-sm text-text-secondary">No fiscal periods in scope.</p>
            ) : (
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-text-secondary">
                    <th scope="col" className="py-2 pr-4 font-medium">Period</th>
                    <th scope="col" className="py-2 pr-4 font-medium">Period status</th>
                    <th scope="col" className="py-2 pr-4 font-medium">Lock status</th>
                    <th scope="col" className="py-2 font-medium">Reconciliation</th>
                  </tr>
                </thead>
                <tbody>
                  {baseline.close.map((row) => (
                    <tr key={row.periodId} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-text-primary">{row.periodName}</td>
                      <td className="py-2 pr-4 text-text-secondary">{row.periodStatus.replace(/_/g, " ")}</td>
                      <td className="py-2 pr-4 text-text-secondary">{row.lockStatus?.replace(/_/g, " ") ?? "Not locked"}</td>
                      <td className="py-2 text-text-secondary">
                        {row.reconciliationStatus
                          ? `${row.reconciliationStatus} (${row.reconciliationWithinTolerance ? "within tolerance" : "out of tolerance"})`
                          : "Not reconciled"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            <a href={`/${tenantSlug}/finance/reconciliation`} className="text-sm font-medium text-primary underline">
              Open reconciliation
            </a>
          </section>
        </>
      ) : null}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-text-primary">Profitability</h2>
        {profitabilityDenied ? (
          <p className="text-sm text-text-secondary">You don&apos;t hold the View margin permission. This card is denied outright, never a masked or partial figure.</p>
        ) : !profitability || profitability.length === 0 ? (
          <p className="text-sm text-text-secondary">No calculated profitability facts yet.</p>
        ) : (
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-text-secondary">
                <th scope="col" className="py-2 pr-4 font-medium">Customer</th>
                <th scope="col" className="py-2 pr-4 font-medium">Currency</th>
                <th scope="col" className="py-2 pr-4 font-medium">Jobs</th>
                <th scope="col" className="py-2 pr-4 font-medium">Profit</th>
                <th scope="col" className="py-2 font-medium">Margin %</th>
              </tr>
            </thead>
            <tbody>
              {profitability.map((row) => (
                <tr key={`${row.dimensionKey}-${row.currency}`} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-text-primary">{row.dimensionLabel ?? "(unspecified)"}</td>
                  <td className="py-2 pr-4 text-text-secondary">{row.currency ?? "-"}</td>
                  <td className="py-2 pr-4 text-text-secondary">{row.jobCount}</td>
                  <td className="py-2 pr-4 text-text-secondary">{row.profitAmount ?? "-"}</td>
                  <td className="py-2 text-text-secondary">{row.marginPercent === null ? "-" : `${row.marginPercent}%`}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <a href={`/${tenantSlug}/finance/profitability`} className="text-sm font-medium text-primary underline">
          Open profitability
        </a>
      </section>
    </div>
  );
}
