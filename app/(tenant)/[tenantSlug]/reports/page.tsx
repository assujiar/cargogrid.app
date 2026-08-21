import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listActiveReportTypes, listReportRuns, ReportQueryError } from "../../../../server/queries/report.ts";
import type { ReportType, ReportRun } from "../../../../server/contracts/report/report.ts";
import { DataTable, type DataTableColumn } from "../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { REPORT_RUN_STATUS_TONE_MAP } from "../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CancelRunButton } from "./cancel-run-button.tsx";
import { cancelReportRunAction } from "./actions.ts";

/**
 * Report Library (IAE-002, Reporting Engine, Prompt 330 §15 "Report library,
 * parameter forms, run history, export status"). The cross-domain read of
 * app.report_types (the single shared, code-shipped catalogue every phase from
 * COM-159 onward has registered into) plus this tenant's own full run history
 * -- a governance/audit view over the already-`VERIFIED` per-domain report
 * engines, never a second query engine (see the migration's own header).
 *
 * Access gate reuses resolveCommercialAccessForRequest: despite its module
 * name, its own logic (lib/portal/commercial-guard.ts) is genuinely
 * domain-agnostic -- any active org_user or tenant_admin in this tenant, the
 * same audience every report in the catalogue is already visible to at the
 * database layer (app.report_types has no RLS; report_runs' own RLS is
 * "any active tenant member or Supreme Admin", not a domain permission).
 * Reused rather than forking a duplicate guard file, per AGENTS.md's "do not
 * create duplicate utilities" discipline.
 *
 * Preview/parameter-entry UX for each of the 29 pre-existing reports remains
 * each domain's own already-`VERIFIED` page (commercial/operations/finance
 * each already have a /reports/[reportCode] detail page; Procurement's own
 * 10 reports currently live under /procurement/dashboard, disclosed, not
 * linked here to avoid a fabricated route) -- this page deep-links to the
 * three that exist and otherwise shows the catalogue entry without a broken
 * link, never a fake one.
 */
const DOMAIN_REPORT_DETAIL_PATH: Record<string, (tenantSlug: string, code: string) => string> = {
  lead_aging: (t, c) => `/${t}/commercial/reports/${c}`,
  activity_queue: (t, c) => `/${t}/commercial/reports/${c}`,
  pipeline_summary: (t, c) => `/${t}/commercial/reports/${c}`,
  quote_sla: (t, c) => `/${t}/commercial/reports/${c}`,
  margin_summary: (t, c) => `/${t}/commercial/reports/${c}`,
  win_loss_summary: (t, c) => `/${t}/commercial/reports/${c}`,
  forecast_summary: (t, c) => `/${t}/commercial/reports/${c}`,
  shipment_status_summary: (t, c) => `/${t}/operations/reports/${c}`,
  milestone_sla_summary: (t, c) => `/${t}/operations/reports/${c}`,
  exception_queue_summary: (t, c) => `/${t}/operations/reports/${c}`,
  epod_completion_summary: (t, c) => `/${t}/operations/reports/${c}`,
  cost_variance_summary: (t, c) => `/${t}/operations/reports/${c}`,
  billing_readiness_summary: (t, c) => `/${t}/operations/reports/${c}`,
  finance_billing_summary: (t, c) => `/${t}/finance/reports/${c}`,
  finance_ar_aging_summary: (t, c) => `/${t}/finance/reports/${c}`,
  finance_ap_aging_summary: (t, c) => `/${t}/finance/reports/${c}`,
  finance_cash_summary: (t, c) => `/${t}/finance/reports/${c}`,
  finance_close_status_summary: (t, c) => `/${t}/finance/reports/${c}`,
  finance_profitability_summary: (t, c) => `/${t}/finance/reports/${c}`,
};

export default async function ReportLibraryPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let reportTypes: ReportType[] = [];
  let runs: ReportRun[] = [];
  let loadFailed = false;
  try {
    [reportTypes, runs] = await Promise.all([listActiveReportTypes(supabase), listReportRuns(supabase, access.tenant.id, 50)]);
  } catch (error) {
    if (!(error instanceof ReportQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const runHistoryColumns: readonly DataTableColumn<ReportRun>[] = [
    { key: "report", header: "Report", render: (run) => reportTypes.find((t) => t.code === run.reportTypeCode)?.name ?? run.reportTypeCode },
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
    {
      key: "actions",
      header: "",
      render: (run) =>
        run.runType === "export" && run.status === "queued" && run.requestedByAuthUserId === access.authUserId ? (
          <CancelRunButton action={cancelReportRunAction.bind(null, tenantSlug, run.id)} />
        ) : null,
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Report Library</h1>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading the report library. Please try again." />
      ) : (
        <>
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Catalogue</h2>
            <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {reportTypes.map((type) => {
                const detailPath = DOMAIN_REPORT_DETAIL_PATH[type.code]?.(tenantSlug, type.code);
                return (
                  <li key={type.code} className="rounded-md border border-neutral-200 p-3">
                    {detailPath ? (
                      <a href={detailPath} className="font-medium text-primary underline">
                        {type.name}
                      </a>
                    ) : (
                      <span className="font-medium text-neutral-900">{type.name}</span>
                    )}
                    <p className="mt-1 text-xs text-neutral-500">{type.description}</p>
                    {Object.keys(type.parameterSchema).length > 0 ? (
                      <p className="mt-1 text-xs text-neutral-400">Parameters: {Object.keys(type.parameterSchema).join(", ")}</p>
                    ) : null}
                  </li>
                );
              })}
            </ul>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Run history</h2>
            <DataTable
              caption="Report run history across every module"
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
