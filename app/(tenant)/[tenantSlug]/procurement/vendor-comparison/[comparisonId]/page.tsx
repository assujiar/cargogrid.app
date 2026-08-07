import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  getVendorComparison,
  listVendorComparisonOffers,
  listVendorComparisonOfferScores,
  getVendorComparisonHistory,
  VendorComparisonQueryError,
} from "../../../../../../server/queries/vendor-comparison.ts";
import type { VendorComparisonOfferScore } from "../../../../../../server/contracts/vendor-comparison/vendor-comparison.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { VendorComparisonDetailPanel } from "./vendor-comparison-detail-panel.tsx";
import {
  reviseVendorComparisonAction,
  linkVendorComparisonOfferRateAction,
  setVendorComparisonOfferInclusionAction,
  scoreVendorComparisonOfferCriterionAction,
  recommendVendorComparisonOfferAction,
  submitVendorComparisonForApprovalAction,
  cancelVendorComparisonAction,
} from "../actions.ts";

/**
 * Vendor Comparison detail (PRC-258, CG-S11-PRC-009): normalized offer
 * side-by-side, source/component drilldown, non-price criteria scoring,
 * eligibility/exclusion flags, recommendation with score explanation, and
 * the human selection/submission handoff. Every mutating action below binds
 * the CURRENT record_version at render time (mirrors app/(tenant)/
 * [tenantSlug]/procurement/rfq/[rfqId]/page.tsx's own `.bind()`-per-row
 * convention) -- a concurrent edit between render and submit surfaces as a
 * real stale_version error from the RPC itself, not a silently-accepted
 * overwrite.
 */
export default async function VendorComparisonDetailPage({ params }: { params: Promise<{ tenantSlug: string; comparisonId: string }> }) {
  const { tenantSlug, comparisonId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let notFoundOrDenied = false;
  let comparison: Awaited<ReturnType<typeof getVendorComparison>> | null = null;
  let offers: Awaited<ReturnType<typeof listVendorComparisonOffers>> = [];
  let history: Awaited<ReturnType<typeof getVendorComparisonHistory>> = [];
  const scoresByOfferId = new Map<string, VendorComparisonOfferScore[]>();
  try {
    comparison = await getVendorComparison(supabase, comparisonId, access.authUserId);
    offers = await listVendorComparisonOffers(supabase, comparisonId, access.authUserId);
    history = await getVendorComparisonHistory(supabase, comparisonId, access.authUserId);
    for (const offer of offers) {
      scoresByOfferId.set(offer.id, await listVendorComparisonOfferScores(supabase, offer.id, access.authUserId));
    }
  } catch (error) {
    if (!(error instanceof VendorComparisonQueryError)) throw error;
    if (error.message.includes("vendor_comparison_not_found")) {
      notFoundOrDenied = true;
    } else if (error.message.includes("insufficient_authority")) {
      notFoundOrDenied = false;
      loadFailed = true;
    } else {
      loadFailed = true;
    }
  }

  if (notFoundOrDenied) {
    notFound();
  }
  if (loadFailed || !comparison || !comparison.id) {
    return <ErrorState description="Something went wrong loading this vendor comparison. Please try again." />;
  }

  return (
    <VendorComparisonDetailPanel
      comparison={comparison}
      offers={offers}
      scoresByOfferId={scoresByOfferId}
      history={history}
      reviseAction={reviseVendorComparisonAction.bind(null, tenantSlug, comparisonId, comparison.recordVersion)}
      linkRateActionFor={(offerId, expectedVersion) => linkVendorComparisonOfferRateAction.bind(null, tenantSlug, comparisonId, offerId, expectedVersion)}
      setInclusionActionFor={(offerId, included, expectedVersion) => setVendorComparisonOfferInclusionAction.bind(null, tenantSlug, comparisonId, offerId, included, expectedVersion)}
      scoreCriterionActionFor={(offerId) => scoreVendorComparisonOfferCriterionAction.bind(null, tenantSlug, comparisonId, offerId)}
      recommendAction={recommendVendorComparisonOfferAction.bind(null, tenantSlug, comparisonId, comparison.recordVersion)}
      submitAction={submitVendorComparisonForApprovalAction.bind(null, tenantSlug, comparisonId, comparison.recordVersion)}
      cancelAction={cancelVendorComparisonAction.bind(null, tenantSlug, comparisonId, comparison.recordVersion)}
    />
  );
}
