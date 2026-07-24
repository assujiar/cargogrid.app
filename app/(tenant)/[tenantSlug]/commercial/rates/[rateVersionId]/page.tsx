import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getRateVersionById, RateQueryError } from "../../../../../../server/queries/rate.ts";
import { RateActionsPanel } from "./rate-actions-panel.tsx";

/**
 * Rate Version Detail (COM-149, CG-S7-COM-008). `getRateVersionById` returns `null` for
 * both "does not exist" and "exists but RLS denies it" -- deliberately not distinguished,
 * the same posture every prior Commercial detail page uses. Reads through
 * `app.vendor_rate_versions_directory` (field-masked, every approval_status visible).
 */
export default async function RateVersionDetailPage({ params }: { params: Promise<{ tenantSlug: string; rateVersionId: string }> }) {
  const { tenantSlug, rateVersionId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let rate;
  try {
    rate = await getRateVersionById(supabase, rateVersionId);
  } catch (error) {
    if (!(error instanceof RateQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this rate version. Please try again.</p>
      </div>
    );
  }

  if (!rate || rate.tenantId !== access.tenant.id) {
    notFound();
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">
        {rate.vendorName} — {rate.originLane} → {rate.destinationLane}
      </h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Vendor code</dt>
        <dd className="text-neutral-900">{rate.vendorCode}</dd>
        <dt className="font-medium text-neutral-600">Service</dt>
        <dd className="text-neutral-900">{rate.serviceType}{rate.mode ? ` (${rate.mode})` : ""}</dd>
        <dt className="font-medium text-neutral-600">Approval status</dt>
        <dd className="text-neutral-900">{rate.approvalStatus}</dd>
        <dt className="font-medium text-neutral-600">Cost</dt>
        <dd className="text-neutral-900">{rate.costMasked ? "Restricted" : `${rate.baseAmount} ${rate.currency ?? ""}`}</dd>
        <dt className="font-medium text-neutral-600">Effective</dt>
        <dd className="text-neutral-900">
          {new Date(rate.effectiveFrom).toLocaleDateString()} — {rate.effectiveTo ? new Date(rate.effectiveTo).toLocaleDateString() : "no end date"}
        </dd>
        {rate.approvalStatus === "rejected" ? (
          <>
            <dt className="font-medium text-neutral-600">Rejected reason</dt>
            <dd className="text-neutral-900">{rate.rejectedReason}</dd>
          </>
        ) : null}
        {rate.approvalStatus === "withdrawn" ? (
          <>
            <dt className="font-medium text-neutral-600">Withdrawn reason</dt>
            <dd className="text-neutral-900">{rate.withdrawnReason}</dd>
          </>
        ) : null}
        {rate.supersedesVersionId ? (
          <>
            <dt className="font-medium text-neutral-600">Supersedes</dt>
            <dd className="text-neutral-900">
              <a href={`/${tenantSlug}/commercial/rates/${rate.supersedesVersionId}`} className="font-medium text-primary underline">
                View prior version
              </a>
            </dd>
          </>
        ) : null}
      </dl>

      <RateActionsPanel tenantSlug={tenantSlug} rateVersionId={rate.rateVersionId} recordVersion={rate.recordVersion} approvalStatus={rate.approvalStatus} />
    </div>
  );
}
