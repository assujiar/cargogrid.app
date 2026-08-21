import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getSavedReportViewById, SavedReportViewQueryError } from "../../../../../server/queries/saved-report-view.ts";
import { getReportTypeByCode, listReportTypeVersions, ReportQueryError } from "../../../../../server/queries/report.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { SavedViewDetailPanel } from "./saved-view-detail-panel.tsx";
import { updateSavedReportViewAction, deleteSavedReportViewAction, exportSavedReportViewAction } from "../actions.ts";

/**
 * Saved View detail page (IAE-004, Prompt 332): shows the view's own config,
 * and -- owner only -- lets it be edited or deleted (sharing a view never
 * grants write access, so a non-owner sees a read-only page). isStale
 * disclosure compares the view's own stamped report_type_version_id against
 * the report's own current version, per Prompt 332's own Alternative flow
 * ("a saved view becomes invalid after source schema change... safe
 * fallback") -- disclosed, never blocking; the underlying report's own live
 * parameter validation remains the real gate on export/run.
 */
export default async function SavedReportViewDetailPage({ params }: { params: Promise<{ tenantSlug: string; savedViewId: string }> }) {
  const { tenantSlug, savedViewId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    view: NonNullable<Awaited<ReturnType<typeof getSavedReportViewById>>>;
    reportType: Awaited<ReturnType<typeof getReportTypeByCode>>;
    currentVersionId: string | null;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const view = await getSavedReportViewById(supabase, savedViewId);
    if (!view) {
      notFound();
    }
    const [reportType, versions] = await Promise.all([getReportTypeByCode(supabase, view.reportTypeCode), listReportTypeVersions(supabase, view.reportTypeCode)]);
    loaded = { view, reportType, currentVersionId: versions[0]?.id ?? null };
  } catch (error) {
    if (!(error instanceof SavedReportViewQueryError) && !(error instanceof ReportQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this saved view. Please try again." />;
  }

  const { view, reportType, currentVersionId } = loaded;
  const isOwner = view.ownerAuthUserId === access.authUserId;
  const isStale = currentVersionId !== null && view.reportTypeVersionId !== null && view.reportTypeVersionId !== currentVersionId;

  return (
    <SavedViewDetailPanel
      view={view}
      reportType={reportType}
      isOwner={isOwner}
      isStale={isStale}
      updateAction={updateSavedReportViewAction.bind(null, tenantSlug, savedViewId, view.recordVersion)}
      deleteAction={deleteSavedReportViewAction.bind(null, tenantSlug, savedViewId, view.recordVersion)}
      exportAction={exportSavedReportViewAction.bind(null, tenantSlug, savedViewId)}
    />
  );
}
