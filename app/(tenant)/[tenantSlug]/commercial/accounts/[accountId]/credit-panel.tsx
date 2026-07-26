import type { CreditProfile } from "../../../../../../server/contracts/credit/credit.ts";
import type { CreditProfileApprovalOverview } from "../../../../../../server/queries/credit.ts";
import { RequestCreditForm } from "./request-credit-form.tsx";
import { CreditApprovalDecisionForm } from "./credit-approval-decision-form.tsx";
import { HoldReleaseForm } from "./hold-release-form.tsx";
import { OverrideForm } from "./override-form.tsx";
import { CreditCheckForm } from "./credit-check-form.tsx";

/**
 * Credit and Commercial Control panel (COM-157, CG-S7-COM-016) -- rendered on the Account
 * Detail page. Shows the account's current credit profile (masked per COM:View selling
 * price), the request form when no live profile exists, the decide form when this actor
 * is eligible to decide a pending request, hold/release/override actions when active/held,
 * and the deterministic eligibility check widget.
 */
export function CreditPanel({
  tenantSlug,
  accountId,
  profile,
  overview,
}: {
  tenantSlug: string;
  accountId: string;
  profile: CreditProfile | null;
  overview: CreditProfileApprovalOverview | null;
}) {
  const hasLiveProfile = profile !== null && ["requested", "active", "held"].includes(profile.status);

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Credit</h2>

      {profile ? (
        <dl className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm">
          <dt className="font-medium text-neutral-600">Status</dt>
          <dd className="text-neutral-900">{profile.status}</dd>
          <dt className="font-medium text-neutral-600">Requested limit</dt>
          <dd className="text-neutral-900">{profile.amountMasked ? "Restricted" : `${profile.requestedLimitAmount} ${profile.currency}`}</dd>
          {profile.approvedLimitAmount !== null || profile.amountMasked ? (
            <>
              <dt className="font-medium text-neutral-600">Approved limit</dt>
              <dd className="text-neutral-900">{profile.amountMasked ? "Restricted" : `${profile.approvedLimitAmount} ${profile.currency}`}</dd>
            </>
          ) : null}
          {profile.holdReason ? (
            <>
              <dt className="font-medium text-neutral-600">Hold reason</dt>
              <dd className="text-neutral-900">{profile.holdReason}</dd>
            </>
          ) : null}
          {profile.rejectedReason ? (
            <>
              <dt className="font-medium text-neutral-600">Rejected reason</dt>
              <dd className="text-neutral-900">{profile.rejectedReason}</dd>
            </>
          ) : null}
        </dl>
      ) : (
        <p className="text-sm text-neutral-600">This account has no credit profile yet.</p>
      )}

      {!hasLiveProfile ? <RequestCreditForm tenantSlug={tenantSlug} accountId={accountId} /> : null}

      {overview && overview.myEligibleStepIds.length > 0
        ? overview.myEligibleStepIds.map((stepId) => {
            const entry = overview.history.find((historyEntry) => historyEntry.stepId === stepId);
            return <CreditApprovalDecisionForm key={stepId} tenantSlug={tenantSlug} accountId={accountId} requestStepId={stepId} stepOrder={entry?.stepOrder ?? 0} />;
          })
        : null}

      {profile && (profile.status === "active" || profile.status === "held") ? (
        <>
          <HoldReleaseForm tenantSlug={tenantSlug} accountId={accountId} profileId={profile.id} expectedVersion={profile.recordVersion} status={profile.status} />
          <OverrideForm tenantSlug={tenantSlug} accountId={accountId} profileId={profile.id} />
        </>
      ) : null}

      <CreditCheckForm tenantSlug={tenantSlug} accountId={accountId} />
    </div>
  );
}
