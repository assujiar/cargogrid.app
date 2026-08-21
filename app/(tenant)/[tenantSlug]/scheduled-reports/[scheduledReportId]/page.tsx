import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getScheduledReportById, listScheduledReportRecipients, listScheduledReportRuns, ScheduledReportQueryError } from "../../../../../server/queries/scheduled-report.ts";
import { getReportTypeByCode, ReportQueryError } from "../../../../../server/queries/report.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { ScheduledReportDetailPanel } from "./scheduled-report-detail-panel.tsx";
import {
  setScheduledReportStatusAction,
  addScheduledReportRecipientAction,
  removeScheduledReportRecipientAction,
  runScheduledReportAction,
} from "../actions.ts";

/**
 * Scheduled Report detail page (IAE-006, Prompt 334): recipients (add/remove,
 * internal tenant members only), run history (freshness/failure evidence,
 * job_id links to the shared app.jobs queue), a "run now" action, and
 * pause/resume/archive controls (Prompt 334's own "unsubscribe/suspend").
 */
export default async function ScheduledReportDetailPage({ params }: { params: Promise<{ tenantSlug: string; scheduledReportId: string }> }) {
  const { tenantSlug, scheduledReportId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    schedule: NonNullable<Awaited<ReturnType<typeof getScheduledReportById>>>;
    recipients: Awaited<ReturnType<typeof listScheduledReportRecipients>>;
    runs: Awaited<ReturnType<typeof listScheduledReportRuns>>;
    reportTypeName: string;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const schedule = await getScheduledReportById(supabase, scheduledReportId);
    if (!schedule) {
      notFound();
    }
    const [recipients, runs, reportType] = await Promise.all([
      listScheduledReportRecipients(supabase, scheduledReportId),
      listScheduledReportRuns(supabase, scheduledReportId),
      getReportTypeByCode(supabase, schedule.reportTypeCode),
    ]);
    loaded = { schedule, recipients, runs, reportTypeName: reportType?.name ?? schedule.reportTypeCode };
  } catch (error) {
    if (!(error instanceof ScheduledReportQueryError) && !(error instanceof ReportQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this scheduled report. Please try again." />;
  }

  const { schedule, recipients, runs, reportTypeName } = loaded;

  return (
    <ScheduledReportDetailPanel
      schedule={schedule}
      reportTypeName={reportTypeName}
      recipients={recipients}
      runs={runs}
      setStatusActionFor={(status) => setScheduledReportStatusAction.bind(null, tenantSlug, scheduledReportId, status)}
      addRecipientAction={addScheduledReportRecipientAction.bind(null, tenantSlug, scheduledReportId)}
      removeRecipientActionFor={(recipientRowId) => removeScheduledReportRecipientAction.bind(null, tenantSlug, scheduledReportId, recipientRowId)}
      runNowAction={runScheduledReportAction.bind(null, tenantSlug, scheduledReportId)}
    />
  );
}
