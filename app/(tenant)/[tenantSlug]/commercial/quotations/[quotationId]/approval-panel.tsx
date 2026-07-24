import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { QuotationApprovalOverview } from "../../../../../../server/queries/quotation-approval.ts";
import { ApprovalDecisionForm } from "./approval-decision-form.tsx";

const REASON_LABELS: Record<string, string> = {
  below_minimum_margin: "Margin is below the published minimum",
  discount_exceeds_maximum: "Discount exceeds the published maximum",
  value_meets_threshold: "Total value meets or exceeds the published minimum",
};

/**
 * Approval status/history/decide panel (COM-153, CG-S7-COM-012, Prompt 153 §66: "approval
 * inbox/detail/diff"; the diff itself is COM-152's own ComparisonPanel, already rendered
 * on this page). Server component -- `overview` is pre-fetched by the page (composes the
 * Approval Engine's own history/pending-inbox view models, server/queries/
 * quotation-approval.ts); the interactive decide form is the one client island
 * (approval-decision-form.tsx).
 */
export function ApprovalPanel({
  tenantSlug,
  quotationId,
  approvalStatus,
  approvalRequiredReasons,
  overview,
}: {
  tenantSlug: string;
  quotationId: string;
  approvalStatus: Quotation["approvalStatus"];
  approvalRequiredReasons: Quotation["approvalRequiredReasons"];
  overview: QuotationApprovalOverview | null;
}) {
  if (approvalStatus === "not_required") {
    return null;
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Approval</h2>
      <p className="text-sm text-neutral-900">
        Status: <span className="font-medium">{approvalStatus}</span>
      </p>

      {approvalRequiredReasons.length > 0 ? (
        <ul className="list-disc pl-5 text-sm text-neutral-600">
          {approvalRequiredReasons.map((reason) => (
            <li key={reason}>{REASON_LABELS[reason] ?? reason}</li>
          ))}
        </ul>
      ) : null}

      {overview && overview.myEligibleStepIds.length > 0 ? (
        <div className="flex flex-col gap-2">
          {overview.myEligibleStepIds.map((stepId) => {
            const entry = overview.history.find((historyEntry) => historyEntry.stepId === stepId);
            return <ApprovalDecisionForm key={stepId} tenantSlug={tenantSlug} quotationId={quotationId} requestStepId={stepId} stepOrder={entry?.stepOrder ?? 0} />;
          })}
        </div>
      ) : null}

      {overview && overview.history.length > 0 ? (
        <div className="flex flex-col gap-1">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">History</h3>
          <ul className="flex flex-col gap-1 text-sm text-neutral-600">
            {overview.history.map((entry) => (
              <li key={`${entry.stepId}-${entry.decisionId ?? "pending"}`}>
                Step {entry.stepOrder} ({entry.approverType}): {entry.decision ? `${entry.decision} by ${entry.actorLabel ?? "someone"}${entry.reason ? ` — ${entry.reason}` : ""}` : entry.stepStatus}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}
