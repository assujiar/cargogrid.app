import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getFinanceAgingReport, getFinanceAgingSummary, AgingQueryError } from "../../../../../server/queries/aging.ts";
import type { FinanceAgingReportRow, FinanceAgingSummaryRow, FinanceAgingEntityType } from "../../../../../server/contracts/aging/aging.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { setFinanceAgingBucketConfigAction } from "./actions.ts";
import { SetFinanceAgingBucketConfigForm } from "./aging-forms.tsx";

function bucketTone(daysOverdue: number): StatusTone {
  if (daysOverdue <= 0) return "success";
  if (daysOverdue <= 30) return "info";
  if (daysOverdue <= 90) return "warning";
  return "danger";
}

/**
 * AR and AP Aging workspace (FIN-210, CG-S9-FIN-021). An as-of, filterable
 * summary and detail report -- derived only, never a stored balance --
 * plus a governed, versioned bucket-configuration form. The summary always
 * reconciles exactly to the detail report, since both are computed from
 * the identical underlying open-item rows.
 */
export default async function AgingPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ entityType?: string; asOfDate?: string; includeHeld?: string }>;
}) {
  const { tenantSlug } = await params;
  const { entityType: rawEntityType, asOfDate: rawAsOfDate, includeHeld: rawIncludeHeld } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const entityType: FinanceAgingEntityType = rawEntityType === "ap" ? "ap" : "ar";
  const asOfDate = rawAsOfDate ?? new Date().toISOString().slice(0, 10);
  const includeHeld = rawIncludeHeld !== "false";

  const supabase = await createSupabaseServerClient();
  let summary: FinanceAgingSummaryRow[] = [];
  let detail: FinanceAgingReportRow[] = [];
  let loadFailed = false;
  try {
    summary = await getFinanceAgingSummary(supabase, { tenantId: access.tenant.id, companyId: null, entityType, asOfDate, includeHeld, actorAuthUserId: access.authUserId });
    detail = await getFinanceAgingReport(supabase, { tenantId: access.tenant.id, companyId: null, entityType, asOfDate, includeHeld, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof AgingQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const summaryColumns: readonly DataTableColumn<FinanceAgingSummaryRow>[] = [
    {
      key: "bucket",
      header: "Bucket",
      render: (row) => <StatusBadge tone={row.bucketLabel === "Current" ? "success" : "neutral"} label={row.bucketLabel} />,
    },
    { key: "currency", header: "Currency", render: (row) => row.currency },
    { key: "openAmount", header: "Open amount", render: (row) => row.openAmount },
    { key: "itemCount", header: "Items", render: (row) => row.itemCount },
  ];

  const detailColumns: readonly DataTableColumn<FinanceAgingReportRow>[] = [
    { key: "party", header: entityType === "ar" ? "Customer" : "Vendor", render: (row) => row.partyId },
    { key: "currency", header: "Currency", render: (row) => row.currency },
    { key: "open", header: "Open amount", render: (row) => row.openAmount },
    { key: "due", header: "Due date", render: (row) => row.dueDate },
    { key: "daysOverdue", header: "Days overdue", render: (row) => <StatusBadge tone={bucketTone(row.daysOverdue)} label={`${row.daysOverdue}`} /> },
    { key: "bucket", header: "Bucket", render: (row) => row.bucketLabel },
    { key: "held", header: "Held", render: (row) => (row.isHeld ? "Yes" : "No") },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">AR / AP Aging</h1>
        <p className="text-sm text-text-secondary">
          Exact as-of aging, derived only from FIN-196/199&apos;s own open items -- never a manually editable summary balance. The summary always
          reconciles exactly to the detail below, since both are computed from the identical rows.
        </p>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="aging-filter-entityType" className="text-sm font-medium text-text-primary">
            Entity type
          </label>
          <select id="aging-filter-entityType" name="entityType" defaultValue={entityType} className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm">
            <option value="ar">ar</option>
            <option value="ap">ap</option>
          </select>
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="aging-filter-asOfDate" className="text-sm font-medium text-text-primary">
            As-of date
          </label>
          <input id="aging-filter-asOfDate" name="asOfDate" type="date" defaultValue={asOfDate} className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex items-center gap-2">
          <input id="aging-filter-includeHeld" name="includeHeld" type="checkbox" value="true" defaultChecked={includeHeld} className="h-4 w-4" />
          <label htmlFor="aging-filter-includeHeld" className="text-sm text-text-primary">
            Include held items
          </label>
        </div>

        <button type="submit" className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium">
          Apply
        </button>
      </form>

      <div>
        <h2 className="text-sm font-semibold text-text-primary">Summary</h2>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading the aging report. Please try again." />
        ) : summary.length === 0 ? (
          <EmptyState title="Nothing outstanding" description="No open items match this scope as of the selected date." />
        ) : (
          <DataTable caption="Aging summary" columns={summaryColumns} rows={summary} rowKey={(row) => `${row.bucketLabel}-${row.currency}`} emptyMessage="Nothing outstanding." />
        )}
      </div>

      {!loadFailed && detail.length > 0 ? (
        <div>
          <h2 className="text-sm font-semibold text-text-primary">Detail</h2>
          <DataTable caption="Aging detail" columns={detailColumns} rows={detail} rowKey={(row) => row.openItemId} emptyMessage="No open items." />
        </div>
      ) : null}

      <SetFinanceAgingBucketConfigForm action={setFinanceAgingBucketConfigAction.bind(null, tenantSlug)} />
    </div>
  );
}
