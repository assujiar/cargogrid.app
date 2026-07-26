import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getReportTypeByCode, listReportRunsForType } from "../../../../../../server/queries/report.ts";
import { recordReportRun, ReportMutationError } from "../../../../../../server/mutations/report.ts";
import { runReportByCode, collectMaskedColumnFlags } from "../run-report.ts";
import { requestReportExportAction } from "../actions.ts";
import { ExportReportForm } from "../export-report-form.tsx";

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
  const columns = rows.length > 0 ? Object.keys(rows[0] as Record<string, unknown>) : [];

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
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong running this report. Please try again.</p>
        </div>
      ) : (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Preview</h2>
          {rows.length === 0 ? (
            <p className="text-sm text-neutral-600">No rows in your current accessible scope.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-neutral-600">
                    {columns.map((column) => (
                      <th key={column} scope="col" className="whitespace-nowrap py-2 pr-4 font-medium">
                        {column}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row, index) => (
                    <tr key={index} className="border-b border-neutral-100">
                      {columns.map((column) => (
                        <td key={column} className="whitespace-nowrap py-2 pr-4 text-neutral-600">
                          {String(row[column] ?? "—")}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Export</h2>
        <p className="text-xs text-neutral-500">Requires the Export permission. Large reports are always asynchronous -- there is no direct browser dataset download.</p>
        <ExportReportForm action={boundExportAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Run history</h2>
        {history.length === 0 ? (
          <p className="text-sm text-neutral-600">No prior runs.</p>
        ) : (
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-600">
                <th scope="col" className="py-2 pr-4 font-medium">
                  Type
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Status
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Rows
                </th>
                <th scope="col" className="py-2 font-medium">
                  Requested
                </th>
              </tr>
            </thead>
            <tbody>
              {history.map((run) => (
                <tr key={run.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">{run.runType}</td>
                  <td className="py-2 pr-4 text-neutral-600">{run.status}</td>
                  <td className="py-2 pr-4 text-neutral-600">{run.rowCount ?? "—"}</td>
                  <td className="py-2 text-neutral-600">{run.requestedAt}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  );
}
