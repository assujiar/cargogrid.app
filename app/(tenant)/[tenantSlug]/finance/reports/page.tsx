import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listActiveReportTypes, listReportRuns, ReportQueryError } from "../../../../../server/queries/report.ts";
import type { ReportType, ReportRun } from "../../../../../server/contracts/report/report.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { REPORT_RUN_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";

/** The exact six codes FIN-213 itself registered -- app.report_types is a single, shared, schema-wide catalogue (COM-159/OPS-183 register their own codes into the identical table), so this catalogue view must filter to its own module rather than listing every active row regardless of source. */
const FINANCE_REPORT_CODES = new Set(["finance_billing_summary", "finance_ar_aging_summary", "finance_ap_aging_summary", "finance_cash_summary", "finance_close_status_summary", "finance_profitability_summary"]);

/**
 * Finance Reports catalogue (FIN-213, CG-S9-FIN-024): the code-shipped report
 * catalogue plus this tenant's own run history. Every report reuses an existing
 * governed Finance query -- see app/.../reports/run-report.ts.
 */
export default async function FinanceReportsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let reportTypes: ReportType[] = [];
  let runs: ReportRun[] = [];
  let loadFailed = false;
  try {
    const [allReportTypes, allRuns] = await Promise.all([listActiveReportTypes(supabase), listReportRuns(supabase, access.tenant.id, 20)]);
    reportTypes = allReportTypes.filter((type) => FINANCE_REPORT_CODES.has(type.code));
    runs = allRuns.filter((run) => FINANCE_REPORT_CODES.has(run.reportTypeCode));
  } catch (error) {
    if (!(error instanceof ReportQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const runHistoryColumns: readonly DataTableColumn<ReportRun>[] = [
    { key: "report", header: "Report", render: (run) => run.reportTypeCode },
    { key: "type", header: "Type", render: (run) => run.runType },
    {
      key: "status",
      header: "Status",
      render: (run) => {
        const { tone, label } = REPORT_RUN_STATUS_TONE_MAP[run.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "rows", header: "Rows", render: (run) => run.rowCount ?? "—" },
    { key: "requested", header: "Requested", render: (run) => run.requestedAt },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-text-primary">Finance reports</h1>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading the report catalogue. Please try again." />
      ) : (
        <>
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">Catalogue</h2>
            <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {reportTypes.map((type) => (
                <li key={type.code} className="rounded-md border border-neutral-200 p-3">
                  <a href={`/${tenantSlug}/finance/reports/${type.code}`} className="font-medium text-primary underline">
                    {type.name}
                  </a>
                  <p className="mt-1 text-xs text-text-secondary">{type.description}</p>
                </li>
              ))}
            </ul>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-text-primary">Run history</h2>
            <DataTable
              caption="Report run history"
              columns={runHistoryColumns}
              rows={runs}
              rowKey={(run) => run.id}
              emptyMessage="No report has been run yet."
            />
          </section>
        </>
      )}
    </div>
  );
}
