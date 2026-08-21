import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listSavedReportViews, SavedReportViewQueryError } from "../../../../server/queries/saved-report-view.ts";
import { listActiveReportTypes, ReportQueryError } from "../../../../server/queries/report.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { SavedViewManagementPanel } from "./saved-view-management-panel.tsx";
import { createSavedReportViewAction } from "./actions.ts";

/**
 * Saved View and Configurable Report (IAE-004, Prompt 332 §15): a named,
 * optionally tenant-shared bookmark of one app.report_types code plus
 * columns/filters -- lists the actor's own views plus every tenant-shared
 * view, and offers a create form. Reuses resolveCommercialAccessForRequest,
 * the same domain-agnostic access gate ../reports/page.tsx and
 * ../dashboards/page.tsx already established for this cross-domain surface.
 */
export default async function SavedReportViewsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let views: Awaited<ReturnType<typeof listSavedReportViews>> = [];
  let reportTypes: Awaited<ReturnType<typeof listActiveReportTypes>> = [];
  let loadFailed = false;
  try {
    [views, reportTypes] = await Promise.all([
      listSavedReportViews(supabase, access.tenant.id, access.authUserId, { limit: 100 }),
      listActiveReportTypes(supabase),
    ]);
  } catch (error) {
    if (!(error instanceof SavedReportViewQueryError) && !(error instanceof ReportQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading saved views. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Saved views</h1>
        <p className="text-xs text-neutral-500">Bookmark a report&apos;s own columns and filters. Sharing a view shares its configuration only -- running it still requires whatever authority that report has always required.</p>
      </div>

      <SavedViewManagementPanel tenantSlug={tenantSlug} views={views} reportTypes={reportTypes} ownerAuthUserId={access.authUserId} createAction={createSavedReportViewAction.bind(null, tenantSlug)} />
    </div>
  );
}
