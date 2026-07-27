import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getReportTypeByCode, listReportRunsForType } from "../../../../../../server/queries/report.ts";
import { recordReportRun, ReportMutationError } from "../../../../../../server/mutations/report.ts";
import { runReportByCode, collectMaskedColumnFlags } from "../run-report.ts";
import { requestReportExportAction } from "../actions.ts";
import { ExportReportForm } from "../export-report-form.tsx";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { REPORT_RUN_STATUS_TONE_MAP } from "../../../../../../components/domain/status-tone-map.ts";
import type { ReportRun } from "../../../../../../server/contracts/report/report.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";

/**
 * Report detail/run page (COM-159, CG-S7-COM-018): runs the report's one named
 * source_function (COM-158's own dashboard query, reused verbatim), records the
 * preview evidence via app.record_report_run, and renders a generic table -- every
 * column this report's underlying query returns, including its own `*Masked` flags, so
 * a masked figure reads as an explicit "false"/"—" rather than a silently blank cell.
 */
export default async function CommercialReportDetailPage({
  params,
}: {
  params: Promise<{ tenantSlug: string; reportCode: string }>;
}) {
  const { tenantSlug, reportCode } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  const reportType = await getReportTypeByCode(supabase, reportCode);
  if (!reportType || reportType.status !== "active") {
    notFound();
  }

  let rows: readonly Record<string, unknown>[] = [];
  let runFailed = false;
  try {
    rows = await runReportByCode(supabase, reportCode, { tenantId: access.tenant.id });
    await recordReportRun(supabase, {
      tenantId: access.tenant.id,
      reportTypeCode: reportCode,
      rowCount: rows.length,
      maskedColumns: collectMaskedColumnFlags(rows),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (!(error instanceof ReportMutationError)) {
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

  const boundExportAction = requestReportExportAction.bind(null, tenantSlug, reportCode);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <a href={`/${tenantSlug}/commercial/reports`} className="text-sm font-medium text-primary underline">
          Back to Reports
        </a>
        <h1 className="text-xl font-semibold text-neutral-900">{reportType.name}</h1>
        <p className="text-sm text-neutral-600">{reportType.description}</p>
      </div>

      {runFailed ? (
        <ErrorState description="Something went wrong running this report. Please try again." />
      ) : (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Preview</h2>
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
        <h2 className="text-sm font-semibold text-neutral-900">Export</h2>
        <p className="text-xs text-neutral-500">Requires the Export permission. Large reports are always asynchronous -- there is no direct browser dataset download.</p>
        <ExportReportForm action={boundExportAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Run history</h2>
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
