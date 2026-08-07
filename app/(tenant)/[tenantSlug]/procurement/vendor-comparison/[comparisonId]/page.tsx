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
import { evaluateProcurementApprovalRequirement, ProcurementApprovalQueryError } from "../../../../../../server/queries/procurement-approval.ts";
import type { VendorComparisonOfferScore } from "../../../../../../server/contracts/vendor-comparison/vendor-comparison.ts";
import type { ProcurementApprovalRequirement } from "../../../../../../server/contracts/procurement-approval/procurement-approval.ts";
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
  let approvalPreview: ProcurementApprovalRequirement | null = null;
  const scoresByOfferId = new Map<string, VendorComparisonOfferScore[]>();
  try {
    comparison = await getVendorComparison(supabase, comparisonId, access.authUserId);
    offers = await listVendorComparisonOffers(supabase, comparisonId, access.authUserId);
    history = await getVendorComparisonHistory(supabase, comparisonId, access.authUserId);
    for (const offer of offers) {
      scoresByOfferId.set(offer.id, await listVendorComparisonOfferScores(supabase, offer.id, access.authUserId));
    }
    // Batch 257-259 review (C-20, MEDIUM): app.evaluate_procurement_approval_
    // requirement was built, granted, and unit-tested with zero real UI caller
    // anywhere -- this "will this need governance approval?" preview, shown
    // before the recommending actor submits, is that real caller. Best-effort:
    // previews against the currently-recommended offer's normalized_amount
    // (the value app.submit_vendor_comparison_for_approval itself would route
    // on if the recommendation is accepted as-is); a human overriding the
    // selection to a different offer at submit time may still route
    // differently, so this is a preview, never authoritative -- the real
    // routing decision happens server-side inside submit itself regardless.
    if (comparison.status === "recommended" && comparison.recommendedOfferId) {
      const recommendedOffer = offers.find((offer) => offer.id === comparison?.recommendedOfferId);
      if (recommendedOffer && recommendedOffer.normalizedAmount !== null) {
        try {
          approvalPreview = await evaluateProcurementApprovalRequirement(supabase, {
            entityType: "vendor_selection",
            tenantId: comparison.tenantId,
            valueAmount: recommendedOffer.normalizedAmount,
            actorAuthUserId: access.authUserId,
          });
        } catch (previewError) {
          // Never block the page on a preview failure (e.g. a PRC:View-cost-less
          // actor who can still see this page via plain PRC:View) -- the real
          // authorization/routing decision is enforced server-side by submit
          // itself regardless of whether this preview could be computed.
          if (!(previewError instanceof ProcurementApprovalQueryError)) throw previewError;
        }
      }
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
      approvalPreview={approvalPreview}
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
