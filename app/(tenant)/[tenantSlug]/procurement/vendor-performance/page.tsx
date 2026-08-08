import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listVendorProfiles, VendorProfileQueryError } from "../../../../../server/queries/vendor-profile.ts";
import { listVendorKpiScorecards, listVendorKpiDefinitions, VendorPerformanceQueryError } from "../../../../../server/queries/vendor-performance.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { VendorPerformanceQueuePanel } from "./vendor-performance-queue-panel.tsx";
import { archiveVendorKpiDefinitionAction, createVendorKpiDefinitionDraftAction, publishVendorKpiDefinitionAction } from "./actions.ts";

/**
 * Vendor Performance queue (PRC-264, CG-S11-PRC-015) -- every active vendor's latest
 * published scorecard (band/score/coverage), plus the tenant's own KPI catalogue
 * (create/publish new categories, versioned per app.vendor_kpi_definitions).
 */
export default async function VendorPerformanceQueuePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let vendors: Awaited<ReturnType<typeof listVendorProfiles>> = [];
  let scorecards: Awaited<ReturnType<typeof listVendorKpiScorecards>> = [];
  let definitions: Awaited<ReturnType<typeof listVendorKpiDefinitions>> = [];
  try {
    [vendors, scorecards, definitions] = await Promise.all([
      listVendorProfiles(supabase, access.tenant.id, access.authUserId, { statusFilter: "active", limit: 100 }),
      listVendorKpiScorecards(supabase, access.tenant.id, access.authUserId, null, 100),
      listVendorKpiDefinitions(supabase, access.tenant.id, access.authUserId, null, 50),
    ]);
  } catch (error) {
    if (!(error instanceof VendorProfileQueryError) && !(error instanceof VendorPerformanceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the vendor performance queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor Performance</h1>
        <p className="text-xs text-neutral-500">
          Source-reconciled KPI scorecards -- on-time pickup/delivery, acceptance, response time, capacity fulfillment, compliance, claims/damage, rate competitiveness/validity, and
          service/complaint signals, each explainable back to its own real evidence. Suspension/blacklist/reactivation is always system-recommended, human-decided.
        </p>
      </div>

      <VendorPerformanceQueuePanel
        tenantSlug={tenantSlug}
        vendors={vendors}
        scorecards={scorecards}
        definitions={definitions}
        createDefinitionAction={createVendorKpiDefinitionDraftAction.bind(null, tenantSlug)}
        publishDefinitionAction={publishVendorKpiDefinitionAction.bind(null, tenantSlug)}
        archiveDefinitionAction={archiveVendorKpiDefinitionAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
