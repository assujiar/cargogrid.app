import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getReportTypeByCode, listReportRunsForType } from "../../../../../../server/queries/report.ts";
import { recordReportRun, ReportMutationError } from "../../../../../../server/mutations/report.ts";
import { runFinanceReportByCode, collectMaskedColumnFlags } from "../run-report.ts";
import { requestFinanceReportExportAction } from "../actions.ts";
import { ExportFinanceReportForm } from "../export-report-form.tsx";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { REPORT_RUN_STATUS_TONE_MAP } from "../../../../../../components/domain/status-tone-map.ts";
import type { ReportRun } from "../../../../../../server/contracts/report/report.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";

/** The exact six codes FIN-213 itself registered -- app.report_types is shared, schema-wide infrastructure (COM-159/OPS-183 register their own codes into the identical table), so a direct-URL lookup must not render a report belonging to another module. */
const FINANCE_REPORT_CODES = new Set(["finance_billing_summary", "finance_ar_aging_summary", "finance_ap_aging_summary", "finance_cash_summary", "finance_close_status_summary", "finance_profitability_summary"]);

/**
 * Report detail/run page (FIN-213, CG-S9-FIN-024): runs the report's one named
 * source_function, records the preview evidence via app.record_report_run (reused
 * directly from COM-159 -- no module-specific gate), and renders a generic table.
 * A permission-denied preview (e.g. finance_profitability_summary without FIN:View
 * margin) renders as an explicit denial, never a silently empty table.
 */
export default async function FinanceReportDetailPage({
  params,
}: {
  params: Promise<{ tenantSlug: string; reportCode: string }>;
}) {
  const { tenantSlug, reportCode } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  const reportType = await getReportTypeByCode(supabase, reportCode);
  if (!reportType || reportType.status !== "active" || !FINANCE_REPORT_CODES.has(reportCode)) {
    notFound();
  }

  let rows: readonly Record<string, unknown>[] = [];
  let runFailed = false;
  try {
    rows = await runFinanceReportByCode(supabase, reportCode, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    await recordReportRun(supabase, {
      tenantId: access.tenant.id,
      reportTypeCode: reportCode,
      rowCount: rows.length,
      maskedColumns: collectMaskedColumnFlags(rows),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (!(error instanceof ReportMutationError) && !(error instanceof Error)) {
      throw error;
    }
    runFailed = true;
  }

  const history = await listReportRunsForType(supabase, access.tenant.id, reportCode, 10);
  const columnNames = rows.length > 0 ? Object.keys(rows[0] as Record<string, unknown>) : [];
  const previewRows = rows.map((row, index) => ({ index, row }));
  const previewColumns: readonly DataTableColumn<(typeof previewRows)[number]>[] = columnNames.map((column) => ({
    key: column,
    header: column,
    render: (entry) => String(entry.row[column] ?? "—"),
  }));

  const historyColumns: readonly DataTableColumn<ReportRun>[] = [
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

  const boundExportAction = requestFinanceReportExportAction.bind(null, tenantSlug, reportCode);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <a href={`/${tenantSlug}/finance/reports`} className="text-sm font-medium text-primary underline">
          Back to Reports
        </a>
        <h1 className="text-xl font-semibold text-text-primary">{reportType.name}</h1>
        <p className="text-sm text-text-secondary">{reportType.description}</p>
      </div>

      {runFailed ? (
        <ErrorState description="Something went wrong running this report. You may lack the required Finance permission for this report's source data." />
      ) : (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-text-primary">Preview</h2>
          <DataTable
            caption="Report preview"
            columns={previewColumns}
            rows={previewRows}
            rowKey={(entry) => String(entry.index)}
            emptyMessage="No rows in your current accessible scope."
          />
        </section>
      )}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-text-primary">Export</h2>
        <p className="text-xs text-text-secondary">Requires the Export permission. Large reports are always asynchronous -- there is no direct browser dataset download.</p>
        <ExportFinanceReportForm action={boundExportAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-text-primary">Run history</h2>
        <DataTable
          caption="Run history for this report"
          columns={historyColumns}
          rows={history}
          rowKey={(run) => run.id}
          emptyMessage="No prior runs."
        />
      </section>
    </div>
  );
}
