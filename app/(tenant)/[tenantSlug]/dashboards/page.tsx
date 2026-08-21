import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listTenantDashboards, TenantDashboardQueryError } from "../../../../server/queries/tenant-dashboard.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { DashboardManagementPanel } from "./dashboard-management-panel.tsx";
import { createTenantDashboardDraftAction } from "./actions.ts";

/**
 * Dashboard Builder (IAE-003, Prompt 331 §15): a real, tenant-configurable
 * dashboard canvas -- lists every dashboard this tenant has created and
 * offers a create-draft form. Reuses resolveCommercialAccessForRequest, the
 * same domain-agnostic access gate ../reports/page.tsx already established
 * for this cross-domain surface: REP:Configure gates the real mutations
 * server-side, this page only needs "any active tenant member" visibility.
 */
export default async function DashboardBuilderPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let dashboards: Awaited<ReturnType<typeof listTenantDashboards>> = [];
  let loadFailed = false;
  try {
    dashboards = await listTenantDashboards(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof TenantDashboardQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your dashboards. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Dashboards</h1>
        <p className="text-xs text-neutral-500">Configure widget-based dashboards from the shared report catalogue. Publishing a version never mutates an already-published snapshot.</p>
      </div>

      <DashboardManagementPanel tenantSlug={tenantSlug} dashboards={dashboards} createAction={createTenantDashboardDraftAction.bind(null, tenantSlug)} />
    </div>
  );
}
