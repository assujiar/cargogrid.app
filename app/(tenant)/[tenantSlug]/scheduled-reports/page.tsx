import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listScheduledReports, ScheduledReportQueryError } from "../../../../server/queries/scheduled-report.ts";
import { listActiveReportTypes, ReportQueryError } from "../../../../server/queries/report.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { ScheduledReportManagementPanel } from "./scheduled-report-management-panel.tsx";
import { createScheduledReportAction } from "./actions.ts";

/**
 * Scheduled Reports (IAE-006, Prompt 334 §15): recurring report generation
 * and delivery to internal tenant recipients. Reuses resolveCommercialAccessForRequest,
 * the same domain-agnostic access gate every other cross-domain Phase 9
 * surface already established.
 */
export default async function ScheduledReportsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let schedules: Awaited<ReturnType<typeof listScheduledReports>> = [];
  let reportTypes: Awaited<ReturnType<typeof listActiveReportTypes>> = [];
  let loadFailed = false;
  try {
    [schedules, reportTypes] = await Promise.all([listScheduledReports(supabase, access.tenant.id), listActiveReportTypes(supabase)]);
  } catch (error) {
    if (!(error instanceof ScheduledReportQueryError) && !(error instanceof ReportQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading scheduled reports. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Scheduled reports</h1>
        <p className="text-xs text-neutral-500">Recurring report generation and delivery to internal recipients only. Recipient access is reauthorized on every run, not only when added.</p>
      </div>

      <ScheduledReportManagementPanel tenantSlug={tenantSlug} schedules={schedules} reportTypes={reportTypes} createAction={createScheduledReportAction.bind(null, tenantSlug)} />
    </div>
  );
}
