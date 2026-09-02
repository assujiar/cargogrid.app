import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getFinanceProfitabilitySummary, ProfitabilityQueryError } from "../../../../../server/queries/profitability.ts";
import type { FinanceProfitabilitySummaryRow, FinanceProfitabilityGroupBy } from "../../../../../server/contracts/profitability/profitability.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { calculateFinanceJobProfitabilityAction } from "./actions.ts";
import { CalculateFinanceJobProfitabilityForm } from "./profitability-forms.tsx";

/**
 * Job, Customer and Service Profitability workspace (FIN-212, CG-S9-FIN-023).
 * A grouped summary (customer/branch/service) of every calculated, current
 * profitability fact -- billed revenue minus approved actual cost, never a
 * fabricated or editable figure -- plus a governed lookup/recalculate form
 * for a single Job Order. Every read here requires FIN:View margin and is
 * denied outright (no partial result) without it.
 */
export default async function ProfitabilityPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ groupBy?: string }>;
}) {
  const { tenantSlug } = await params;
  const { groupBy: rawGroupBy } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const groupBy: FinanceProfitabilityGroupBy = rawGroupBy === "branch" || rawGroupBy === "service" ? rawGroupBy : "customer";

  const supabase = await createSupabaseServerClient();
  let summary: FinanceProfitabilitySummaryRow[] = [];
  let loadFailed = false;
  try {
    summary = await getFinanceProfitabilitySummary(supabase, { tenantId: access.tenant.id, groupBy, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof ProfitabilityQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const summaryColumns: readonly DataTableColumn<FinanceProfitabilitySummaryRow>[] = [
    { key: "label", header: groupBy === "customer" ? "Customer" : groupBy === "branch" ? "Branch" : "Service", render: (row) => row.dimensionLabel ?? "(unspecified)" },
    { key: "currency", header: "Currency", render: (row) => row.currency ?? "-" },
    { key: "jobCount", header: "Jobs", render: (row) => row.jobCount },
    { key: "revenue", header: "Revenue (billed)", render: (row) => row.revenueAmount ?? "-" },
    { key: "cost", header: "Cost (approved)", render: (row) => row.costAmount ?? "-" },
    { key: "profit", header: "Profit", render: (row) => row.profitAmount ?? "-" },
    { key: "margin", header: "Margin %", render: (row) => (row.marginPercent === null ? "-" : `${row.marginPercent}%`) },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Job, Customer and Service Profitability</h1>
        <p className="text-sm text-text-secondary">
          Billed revenue (issued invoices) minus approved actual cost (Operations&apos; own governed actual-cost evidence) -- never an editable
          summary figure. A blocked fact (missing revenue/cost or a currency mismatch) is excluded from every total below, never guessed into one.
        </p>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-4">
        <FormField id="profitability-groupBy" label="Group by">
          <Select id="profitability-groupBy" name="groupBy" defaultValue={groupBy} className="w-32">
            <option value="customer">Customer</option>
            <option value="branch">Branch</option>
            <option value="service">Service</option>
          </Select>
        </FormField>
        <button type="submit" className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium">
          Apply
        </button>
      </form>

      <div>
        <h2 className="text-sm font-semibold text-text-primary">Summary</h2>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading the profitability summary. Please try again." />
        ) : summary.length === 0 ? (
          <EmptyState title="Nothing calculated yet" description="No calculated profitability facts exist for this grouping yet." />
        ) : (
          <DataTable caption="Profitability summary" columns={summaryColumns} rows={summary} rowKey={(row) => `${row.dimensionKey}-${row.currency}`} emptyMessage="Nothing calculated yet." />
        )}
      </div>

      <CalculateFinanceJobProfitabilityForm action={calculateFinanceJobProfitabilityAction.bind(null, tenantSlug)} />
    </div>
  );
}
