import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getVendorProfile, VendorProfileQueryError } from "../../../../../../server/queries/vendor-profile.ts";
import {
  listVendorKpiScorecards,
  getVendorKpiScorecardDrilldown,
  listVendorPerformanceIssues,
  listVendorPerformanceCorrectiveActions,
  listVendorKpiManualAdjustments,
  listVendorLifecycleRecommendations,
  listVendorKpiSourceDisputes,
  VendorPerformanceQueryError,
} from "../../../../../../server/queries/vendor-performance.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { VendorPerformanceDetailPanel } from "./vendor-performance-detail-panel.tsx";
import {
  calculateVendorKpiMetricsAction,
  publishVendorKpiScorecardAction,
  raiseVendorKpiSourceDisputeAction,
  decideVendorKpiSourceDisputeAction,
  raiseVendorPerformanceIssueAction,
  updateVendorPerformanceIssueStatusAction,
  addVendorPerformanceCorrectiveActionAction,
  updateVendorPerformanceCorrectiveActionStatusAction,
  requestVendorKpiManualAdjustmentAction,
  decideVendorKpiManualAdjustmentAction,
  evaluateVendorLifecycleRecommendationAction,
  decideVendorLifecycleRecommendationAction,
} from "./actions.ts";

export default async function VendorPerformanceDetailPage({ params }: { params: Promise<{ tenantSlug: string; vendorMasterId: string }> }) {
  const { tenantSlug, vendorMasterId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let vendor: Awaited<ReturnType<typeof getVendorProfile>> | null = null;
  let scorecardVersions: Awaited<ReturnType<typeof listVendorKpiScorecards>> = [];
  let drilldown: Awaited<ReturnType<typeof getVendorKpiScorecardDrilldown>> = [];
  let issues: Awaited<ReturnType<typeof listVendorPerformanceIssues>> = [];
  let correctiveActionsByIssue: Record<string, Awaited<ReturnType<typeof listVendorPerformanceCorrectiveActions>>> = {};
  let adjustments: Awaited<ReturnType<typeof listVendorKpiManualAdjustments>> = [];
  let recommendations: Awaited<ReturnType<typeof listVendorLifecycleRecommendations>> = [];
  let disputes: Awaited<ReturnType<typeof listVendorKpiSourceDisputes>> = [];

  try {
    vendor = await getVendorProfile(supabase, vendorMasterId, access.authUserId);
    [scorecardVersions, issues, recommendations, disputes] = await Promise.all([
      listVendorKpiScorecards(supabase, access.tenant.id, access.authUserId, vendorMasterId, 25),
      listVendorPerformanceIssues(supabase, access.tenant.id, access.authUserId, vendorMasterId, null, 50),
      listVendorLifecycleRecommendations(supabase, access.tenant.id, access.authUserId, vendorMasterId, null, 25),
      listVendorKpiSourceDisputes(supabase, access.tenant.id, access.authUserId, vendorMasterId, null),
    ]);
    const currentCard = scorecardVersions.find((s) => s.isCurrent) ?? null;
    if (currentCard) {
      drilldown = await getVendorKpiScorecardDrilldown(supabase, currentCard.id, access.authUserId);
      const adjustmentsByCard = await listVendorKpiManualAdjustments(supabase, currentCard.id, access.authUserId);
      adjustments = adjustmentsByCard;
    }
    const actionLists = await Promise.all(issues.map((issue) => listVendorPerformanceCorrectiveActions(supabase, issue.id, access.authUserId)));
    correctiveActionsByIssue = Object.fromEntries(issues.map((issue, index) => [issue.id, actionLists[index] ?? []]));
  } catch (error) {
    if (!(error instanceof VendorProfileQueryError) && !(error instanceof VendorPerformanceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed || !vendor) {
    return <ErrorState description="Something went wrong loading this vendor's performance record. Please try again." />;
  }

  const currentCard = scorecardVersions.find((s) => s.isCurrent) ?? null;

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">{vendor.legalName}</h1>
        <p className="text-xs text-neutral-500">Vendor performance scorecard, source drilldown, issues/corrective actions, manual adjustments, and the governed suspension/blacklist/reactivation surface.</p>
      </div>

      <VendorPerformanceDetailPanel
        tenantSlug={tenantSlug}
        vendorMasterId={vendorMasterId}
        vendorLifecycleStatus={vendor.lifecycleStatus}
        currentCard={currentCard}
        scorecardVersions={scorecardVersions}
        drilldown={drilldown}
        issues={issues}
        correctiveActionsByIssue={correctiveActionsByIssue}
        adjustments={adjustments}
        recommendations={recommendations}
        disputes={disputes}
        calculateAction={calculateVendorKpiMetricsAction.bind(null, tenantSlug, vendorMasterId)}
        publishAction={publishVendorKpiScorecardAction.bind(null, tenantSlug, vendorMasterId)}
        raiseDisputeAction={raiseVendorKpiSourceDisputeAction.bind(null, tenantSlug, vendorMasterId)}
        decideDisputeAction={decideVendorKpiSourceDisputeAction.bind(null, tenantSlug, vendorMasterId)}
        raiseIssueAction={raiseVendorPerformanceIssueAction.bind(null, tenantSlug, vendorMasterId)}
        updateIssueStatusAction={updateVendorPerformanceIssueStatusAction.bind(null, tenantSlug, vendorMasterId)}
        addCorrectiveActionAction={addVendorPerformanceCorrectiveActionAction.bind(null, tenantSlug, vendorMasterId)}
        updateCorrectiveActionStatusAction={updateVendorPerformanceCorrectiveActionStatusAction.bind(null, tenantSlug, vendorMasterId)}
        requestAdjustmentAction={requestVendorKpiManualAdjustmentAction.bind(null, tenantSlug, vendorMasterId)}
        decideAdjustmentAction={decideVendorKpiManualAdjustmentAction.bind(null, tenantSlug, vendorMasterId)}
        evaluateRecommendationAction={evaluateVendorLifecycleRecommendationAction.bind(null, tenantSlug, vendorMasterId)}
        decideRecommendationAction={decideVendorLifecycleRecommendationAction.bind(null, tenantSlug, vendorMasterId)}
      />
    </div>
  );
}
