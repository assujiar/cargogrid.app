import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listAnalyticsViews, getLatestAnalyticsRefreshRun, getReportUsageDaily, AnalyticsQueryError } from "../../../../server/queries/analytics.ts";
import type { AnalyticsViewRegistry, AnalyticsRefreshRun, ReportUsageDailyRow } from "../../../../server/contracts/analytics/analytics.ts";
import { DataTable, type DataTableColumn } from "../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { RefreshViewButton } from "./refresh-view-button.tsx";
import { refreshAnalyticsViewAction } from "./actions.ts";

/**
 * Analytics and Materialized Views admin/freshness screen (IAE-005, Prompt
 * 333 §15: "Analytics admin/freshness screen, metric lineage view and
 * dashboard/report stale indicators"). Lists every registered materialized
 * view with its own latest refresh run (freshness/lineage/reconciliation
 * evidence) plus this tenant's own report-usage projection, read exclusively
 * through app.get_report_usage_daily -- the view itself carries no direct
 * grants. Reuses resolveCommercialAccessForRequest, the same domain-agnostic
 * access gate every other cross-domain Phase 9 surface already established.
 */
export default async function AnalyticsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let views: AnalyticsViewRegistry[] = [];
  let latestRuns: Map<string, AnalyticsRefreshRun | null> = new Map();
  let usageRows: ReportUsageDailyRow[] = [];
  let loadFailed = false;
  try {
    views = await listAnalyticsViews(supabase);
    const runEntries = await Promise.all(views.map(async (v) => [v.viewCode, await getLatestAnalyticsRefreshRun(supabase, v.viewCode)] as const));
    latestRuns = new Map(runEntries);
    usageRows = await getReportUsageDaily(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof AnalyticsQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading analytics. Please try again." />;
  }

  const usageColumns: readonly DataTableColumn<ReportUsageDailyRow>[] = [
    { key: "reportTypeCode", header: "Report", render: (row) => row.reportTypeCode },
    { key: "usageDate", header: "Date", render: (row) => row.usageDate },
    { key: "previewCount", header: "Previews", render: (row) => row.previewCount },
    { key: "exportCount", header: "Exports", render: (row) => row.exportCount },
    // Counts every non-completed run, including a requester's own
    // cancellation alongside a genuine failure (app.report_runs has no
    // separate "cancelled" status) -- disclosed in the header rather than
    // claiming a precision the underlying data doesn't have.
    { key: "failedCount", header: "Failed / Cancelled", render: (row) => row.failedCount },
  ];

  const nowMs = new Date().getTime();

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Analytics</h1>
        <p className="text-xs text-neutral-500">Governed, refreshable analytics projections -- never a second source of truth. Refreshing a view is a Supreme-only, system-wide operation.</p>
      </div>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Registered views</h2>
        <ul className="flex flex-col gap-2">
          {views.map((view) => {
            const run = latestRuns.get(view.viewCode) ?? null;
            const isStale = !run || run.status !== "completed" || (run.completedAt !== null && nowMs - new Date(run.completedAt).getTime() > view.refreshFrequencyMinutes * 60_000);
            return (
              <li key={view.id} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <p className="font-medium text-neutral-900">{view.name}</p>
                  <p className="text-xs text-neutral-500">{view.description}</p>
                  <div className="mt-1 flex flex-wrap gap-2">
                    <StatusBadge tone={view.status === "active" ? "success" : "neutral"} label={view.status} />
                    {run ? (
                      <StatusBadge
                        tone={run.status === "failed" ? "danger" : isStale ? "warning" : "success"}
                        label={run.status === "failed" ? `refresh failed: ${run.errorReason ?? "unknown error"}` : isStale ? "stale" : "fresh"}
                      />
                    ) : (
                      <StatusBadge tone="neutral" label="never refreshed" />
                    )}
                    {run?.status === "completed" ? (
                      <StatusBadge
                        tone={run.reconciled ? "info" : "danger"}
                        label={run.reconciled ? `reconciled (${run.rowCountAfter} rows)` : "reconciliation mismatch"}
                      />
                    ) : null}
                  </div>
                  {run?.completedAt ? <p className="mt-1 text-xs text-neutral-400">Last refreshed: {run.completedAt}</p> : null}
                </div>
                <RefreshViewButton action={refreshAnalyticsViewAction.bind(null, tenantSlug, view.viewCode)} />
              </li>
            );
          })}
        </ul>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Report usage (this tenant)</h2>
        <DataTable caption="Daily report preview/export/failure counts, from app.mv_report_usage_daily" columns={usageColumns} rows={usageRows} rowKey={(row) => `${row.reportTypeCode}-${row.usageDate}`} emptyMessage="No report usage recorded yet." />
      </section>
    </div>
  );
}
