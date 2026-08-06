import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getRateVersionById, RateQueryError } from "../../../../../../server/queries/rate.ts";
import { listVendorRateTiers, ProcurementRateQueryError } from "../../../../../../server/queries/procurement-rate.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { RateTierPanel } from "./rate-tier-panel.tsx";
import { addVendorRateTierAction, removeVendorRateTierAction, calculateVendorRatePreviewAction } from "../actions.ts";

/**
 * Vendor rate detail (PRC-255, CG-S11-PRC-006): rate identity/status, the linked
 * vendor (ADR-0020), the tier grid (add/remove while pending_approval), and a
 * calculation preview (Prompt 255 §15, RPD-040). Approval/reject/withdraw actions
 * are unchanged COM-149 operations, left on the existing Commercial rate detail page
 * (app/(tenant)/[tenantSlug]/commercial/rates/[rateVersionId]/page.tsx) -- this page
 * is additive, not a duplicate of that one.
 */
export default async function ProcurementRateDetailPage({ params }: { params: Promise<{ tenantSlug: string; rateVersionId: string }> }) {
  const { tenantSlug, rateVersionId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let rate: Awaited<ReturnType<typeof getRateVersionById>> = null;
  let tiers: Awaited<ReturnType<typeof listVendorRateTiers>> = [];
  try {
    rate = await getRateVersionById(supabase, rateVersionId);
    tiers = await listVendorRateTiers(supabase, rateVersionId);
  } catch (error) {
    if (!(error instanceof RateQueryError) && !(error instanceof ProcurementRateQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading this vendor rate. Please try again." />;
  }
  if (!rate) {
    notFound();
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">
          {rate.vendorName} · {rate.serviceType}
        </h1>
        <p className="text-xs text-neutral-500">
          {rate.originLane} → {rate.destinationLane}
          {rate.mode ? ` (${rate.mode})` : ""} · {rate.approvalStatus.replace("_", " ")}
        </p>
        {/* Post-review fix: approve/reject/withdraw stayed on the Commercial detail
            page (unchanged COM-149 operation) -- cross-link there so this page
            isn't a dead end for an approver who navigated here first. */}
        <a href={`/${tenantSlug}/commercial/rates/${rateVersionId}`} className="text-xs font-medium text-primary underline">
          View approval status and actions on the Commercial rate page
        </a>
      </div>

      <RateTierPanel
        rateStatus={rate.approvalStatus}
        tiers={tiers}
        addTierAction={addVendorRateTierAction.bind(null, tenantSlug, rateVersionId)}
        removeTierAction={removeVendorRateTierAction.bind(null, tenantSlug, rateVersionId)}
        calculateAction={calculateVendorRatePreviewAction.bind(null, tenantSlug, rateVersionId)}
      />
    </div>
  );
}
