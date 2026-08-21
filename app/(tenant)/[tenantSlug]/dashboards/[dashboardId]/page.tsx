import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getTenantDashboardById, listTenantDashboardVersions, listDashboardWidgets, TenantDashboardQueryError } from "../../../../../server/queries/tenant-dashboard.ts";
import { listActiveReportTypes, ReportQueryError } from "../../../../../server/queries/report.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { DashboardDetailPanel } from "./dashboard-detail-panel.tsx";
import { addDashboardWidgetAction, removeDashboardWidgetAction, publishTenantDashboardVersionAction, rollbackTenantDashboardAction } from "../actions.ts";

/**
 * Dashboard Builder detail page (IAE-003, Prompt 331): draft-only widget
 * management (add/remove, each binding to an existing app.report_types
 * code -- never raw SQL, §24), publish (opens a fresh draft copying the
 * just-published widgets), and rollback to any older published version.
 */
export default async function DashboardBuilderDetailPage({ params }: { params: Promise<{ tenantSlug: string; dashboardId: string }> }) {
  const { tenantSlug, dashboardId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    dashboard: NonNullable<Awaited<ReturnType<typeof getTenantDashboardById>>>;
    versions: Awaited<ReturnType<typeof listTenantDashboardVersions>>;
    draftWidgets: Awaited<ReturnType<typeof listDashboardWidgets>>;
    publishedWidgets: Awaited<ReturnType<typeof listDashboardWidgets>>;
    reportTypes: Awaited<ReturnType<typeof listActiveReportTypes>>;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const dashboard = await getTenantDashboardById(supabase, dashboardId);
    if (!dashboard) {
      notFound();
    }
    const versions = await listTenantDashboardVersions(supabase, dashboardId);
    const draftVersion = versions.find((v) => v.status === "draft") ?? null;
    const publishedVersion = dashboard.currentVersionId ? (versions.find((v) => v.id === dashboard.currentVersionId) ?? null) : null;
    const [draftWidgets, publishedWidgets, reportTypes] = await Promise.all([
      draftVersion ? listDashboardWidgets(supabase, draftVersion.id) : Promise.resolve([]),
      publishedVersion ? listDashboardWidgets(supabase, publishedVersion.id) : Promise.resolve([]),
      listActiveReportTypes(supabase),
    ]);
    loaded = { dashboard, versions, draftWidgets, publishedWidgets, reportTypes };
  } catch (error) {
    if (!(error instanceof TenantDashboardQueryError) && !(error instanceof ReportQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this dashboard. Please try again." />;
  }

  const { dashboard, versions, draftWidgets, publishedWidgets, reportTypes } = loaded;
  const draftVersion = versions.find((v) => v.status === "draft") ?? null;

  return (
    <DashboardDetailPanel
      dashboard={dashboard}
      versions={versions}
      draftVersion={draftVersion}
      draftWidgets={draftWidgets}
      publishedWidgets={publishedWidgets}
      reportTypes={reportTypes}
      addWidgetAction={draftVersion ? addDashboardWidgetAction.bind(null, tenantSlug, dashboardId, draftVersion.id) : null}
      removeWidgetActionFor={(widgetId) => removeDashboardWidgetAction.bind(null, tenantSlug, dashboardId, widgetId)}
      publishAction={publishTenantDashboardVersionAction.bind(null, tenantSlug, dashboardId)}
      rollbackActionFor={(targetVersionId) => rollbackTenantDashboardAction.bind(null, tenantSlug, dashboardId, targetVersionId)}
    />
  );
}
