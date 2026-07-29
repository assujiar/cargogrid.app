import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  getFinanceDashboardBillingSummary,
  getFinanceDashboardReconciliationSummary,
  getFinanceDashboardCashSummary,
  FinanceDashboardQueryError,
} from "../../../../../server/queries/finance-dashboard.ts";
import { getFinanceAgingSummary, AgingQueryError } from "../../../../../server/queries/aging.ts";
import { getFinanceProfitabilitySummary, ProfitabilityQueryError } from "../../../../../server/queries/profitability.ts";
import type { FinanceDashboardBillingRow, FinanceDashboardReconciliationRow, FinanceDashboardCashRow } from "../../../../../server/contracts/finance-dashboard/finance-dashboard.ts";
import type { FinanceAgingSummaryRow } from "../../../../../server/contracts/aging/aging.ts";
import type { FinanceProfitabilitySummaryRow } from "../../../../../server/contracts/profitability/profitability.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_RECONCILIATION_RUN_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";

/**
 * Finance Dashboard and Reports (FIN-213, CG-S9-FIN-024). A permission-safe,
 * source-reconciled Finance overview composed entirely from already-governed
 * sections: billing (invoice status), AR/AP aging (FIN-210), cash (FIN-211),
 * close/reconciliation (FIN-209) and profitability (FIN-212). Zero new
 * stored figure exists anywhere -- every number is read live from its own
 * owning capability. Profitability requires FIN:View margin in addition to
 * FIN:View; a caller lacking it sees every other section but a disclosed
 * permission-denied card in profitability's own place, never a fabricated
 * zero or a failed page.
 *
 * Disclosed, bounded checkpoint scope: trial balance, profit-and-loss/
 * balance-sheet statements, budget-versus-actual and tax liability summaries
 * are not built here -- no such engine exists anywhere in this repository
 * yet to source them from. A full report catalogue with saved views,
 * scheduling and async export is equally out of this checkpoint's bounded
 * scope.
 */
export default async function FinanceDashboardPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const asOfDate = new Date().toISOString().slice(0, 10);
  const supabase = await createSupabaseServerClient();
  const filter = { tenantId: access.tenant.id, companyId: null as string | null, actorAuthUserId: access.authUserId };

  let billing: FinanceDashboardBillingRow[] = [];
  let reconciliation: FinanceDashboardReconciliationRow[] = [];
  let cash: FinanceDashboardCashRow[] = [];
  let arAging: FinanceAgingSummaryRow[] = [];
  let apAging: FinanceAgingSummaryRow[] = [];
  let coreLoadFailed = false;
  try {
    [billing, reconciliation, cash, arAging, apAging] = await Promise.all([
      getFinanceDashboardBillingSummary(supabase, filter),
      getFinanceDashboardReconciliationSummary(supabase, filter),
      getFinanceDashboardCashSummary(supabase, { ...filter, asOfDate }),
      getFinanceAgingSummary(supabase, { ...filter, entityType: "ar", asOfDate, includeHeld: true }),
      getFinanceAgingSummary(supabase, { ...filter, entityType: "ap", asOfDate, includeHeld: true }),
    ]);
  } catch (error) {
    if (!(error instanceof FinanceDashboardQueryError) && !(error instanceof AgingQueryError)) {
      throw error;
    }
    coreLoadFailed = true;
  }

  let profitability: FinanceProfitabilitySummaryRow[] = [];
  let profitabilityDenied = false;
  try {
    profitability = await getFinanceProfitabilitySummary(supabase, { tenantId: access.tenant.id, groupBy: "customer", actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof ProfitabilityQueryError)) {
      throw error;
    }
    profitabilityDenied = true;
  }

  const billingColumns: readonly DataTableColumn<FinanceDashboardBillingRow>[] = [
    { key: "status", header: "Status", render: (row) => row.status },
    { key: "currency", header: "Currency", render: (row) => row.currency },
    { key: "count", header: "Invoices", render: (row) => row.invoiceCount },
    { key: "total", header: "Total", render: (row) => row.totalAmount },
  ];

  const agingColumns: readonly DataTableColumn<FinanceAgingSummaryRow>[] = [
    { key: "bucket", header: "Bucket", render: (row) => row.bucketLabel },
    { key: "currency", header: "Currency", render: (row) => row.currency },
    { key: "open", header: "Open amount", render: (row) => row.openAmount },
    { key: "count", header: "Items", render: (row) => row.itemCount },
  ];

  const cashColumns: readonly DataTableColumn<FinanceDashboardCashRow>[] = [
    { key: "currency", header: "Currency", render: (row) => row.currency },
    { key: "accounts", header: "Accounts", render: (row) => row.accountCount },
    { key: "statement", header: "Statement balance", render: (row) => row.statementBalance },
    { key: "gl", header: "GL balance", render: (row) => row.glBalance },
    { key: "variance", header: "Variance", render: (row) => row.varianceAmount },
  ];

  const profitabilityColumns: readonly DataTableColumn<FinanceProfitabilitySummaryRow>[] = [
    { key: "label", header: "Customer", render: (row) => row.dimensionLabel ?? "(unspecified)" },
    { key: "currency", header: "Currency", render: (row) => row.currency ?? "-" },
    { key: "jobs", header: "Jobs", render: (row) => row.jobCount },
    { key: "profit", header: "Profit", render: (row) => row.profitAmount ?? "-" },
    { key: "margin", header: "Margin %", render: (row) => (row.marginPercent === null ? "-" : `${row.marginPercent}%`) },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold text-text-primary">Finance dashboard</h1>
        <p className="text-xs text-text-secondary">As of {asOfDate}</p>
      </div>
      <p className="text-sm text-text-secondary">
        Every section below is a live, source-reconciled read of its own owning capability -- no figure here is independently stored or editable.
        Billing/aging/cash/close require FIN:View; profitability additionally requires FIN:View margin.
      </p>

      {coreLoadFailed ? (
        <ErrorState description="Something went wrong loading the Finance dashboard. Please try again." />
      ) : (
        <>
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">Billing</h2>
            {billing.length === 0 ? <EmptyState title="No invoices" description="No invoices exist yet for this scope." /> : <DataTable caption="Billing summary" columns={billingColumns} rows={billing} rowKey={(row) => `${row.status}-${row.currency}`} emptyMessage="No invoices." />}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">AR aging</h2>
            {arAging.length === 0 ? <EmptyState title="Nothing outstanding" description="No open AR items as of today." /> : <DataTable caption="AR aging summary" columns={agingColumns} rows={arAging} rowKey={(row) => `${row.bucketLabel}-${row.currency}`} emptyMessage="Nothing outstanding." />}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">AP aging</h2>
            {apAging.length === 0 ? <EmptyState title="Nothing outstanding" description="No open AP items as of today." /> : <DataTable caption="AP aging summary" columns={agingColumns} rows={apAging} rowKey={(row) => `${row.bucketLabel}-${row.currency}`} emptyMessage="Nothing outstanding." />}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">Cash</h2>
            {cash.length === 0 ? <EmptyState title="No bank accounts" description="No bank accounts exist yet for this scope." /> : <DataTable caption="Cash summary" columns={cashColumns} rows={cash} rowKey={(row) => row.currency} emptyMessage="No bank accounts." />}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">Close / reconciliation</h2>
            {reconciliation.length === 0 ? (
              <EmptyState title="No reconciliation run yet" description="No AR/AP reconciliation has been run yet for this scope." />
            ) : (
              <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                {reconciliation.map((row) => (
                  <li key={row.scope} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium uppercase text-text-secondary">{row.scope}</p>
                    <StatusBadge tone={FINANCE_RECONCILIATION_RUN_STATUS_TONE_MAP[row.status as keyof typeof FINANCE_RECONCILIATION_RUN_STATUS_TONE_MAP]?.tone ?? "neutral"} label={row.status} />
                    <p className="mt-1 text-sm text-text-primary">In tolerance: {row.isWithinTolerance ? "Yes" : "No"} (variance {row.varianceAmount})</p>
                    <p className="text-xs text-text-secondary">As of {row.asOfDate}, checked {row.checkedAt}</p>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-text-primary">Profitability by customer</h2>
        {profitabilityDenied ? (
          <ErrorState description="You don't have FIN:View margin -- profitability is restricted and excluded from this dashboard." />
        ) : profitability.length === 0 ? (
          <EmptyState title="Nothing calculated yet" description="No calculated profitability facts exist yet." />
        ) : (
          <DataTable caption="Profitability by customer" columns={profitabilityColumns} rows={profitability} rowKey={(row) => `${row.dimensionKey}-${row.currency}`} emptyMessage="Nothing calculated yet." />
        )}
        <a href={`/${tenantSlug}/finance/profitability`} className="text-sm font-medium text-primary underline">
          Open profitability workspace
        </a>
      </section>
    </div>
  );
}
