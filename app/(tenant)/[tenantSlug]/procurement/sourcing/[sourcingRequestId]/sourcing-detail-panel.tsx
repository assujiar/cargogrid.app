"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { SourcingRequest, SourcingCandidate, SourcingRequestEvent, SourcingRequestStatus, SourcingCandidateExclusionReason } from "../../../../../../server/contracts/sourcing/sourcing.ts";
import type { SourcingActionState } from "../actions.ts";

const INITIAL_STATE: SourcingActionState = { error: null };

const STATUS_TONE: Record<SourcingRequestStatus, StatusTone> = {
  draft: "neutral",
  open: "info",
  shortlisted: "success",
  closed_no_source: "warning",
  cancelled: "danger",
};

const EXCLUSION_REASON_LABEL: Record<SourcingCandidateExclusionReason, string> = {
  vendor_not_active: "vendor not active",
  service_mismatch: "service mismatch",
  coverage_mismatch: "coverage mismatch",
  compliance_ineligible: "compliance hold",
};

const SOURCE_TYPE_LABEL: Record<SourcingRequest["sourceType"], string> = {
  costing_request: "Commercial costing request",
  operational_demand: "Operations shipment order",
  proactive: "Proactive (no source)",
};

type SimpleFormAction = (prevState: SourcingActionState, formData: FormData) => Promise<SourcingActionState>;
type NoArgFormAction = (prevState: SourcingActionState) => Promise<SourcingActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
  className = "flex flex-col gap-2",
}: {
  action: SimpleFormAction;
  children?: (describedBy: string | undefined) => React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className={className}>
      {children?.(describedBy)}
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

function NoArgActionButton({ action, label, loadingLabel, variant = "secondary" }: { action: NoArgFormAction; label: string; loadingLabel?: string; variant?: "primary" | "secondary" | "destructive" }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"}>
        {label}
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ConstraintRow({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs font-medium text-neutral-500">{label}</dt>
      <dd className="text-sm text-neutral-900">{value ?? "—"}</dd>
    </div>
  );
}

export function SourcingDetailPanel({
  request,
  candidates,
  history,
  submitAction,
  overrideAction,
  evaluateEligibilityAction,
  shortlistActionFor,
  submitShortlistAction,
  closeNoSourceAction,
  cancelAction,
  reopenAction,
}: {
  request: SourcingRequest;
  candidates: readonly SourcingCandidate[];
  history: readonly SourcingRequestEvent[];
  submitAction: NoArgFormAction;
  overrideAction: SimpleFormAction;
  evaluateEligibilityAction: NoArgFormAction;
  shortlistActionFor: (candidateId: string, expectedVersion: number, shortlisted: boolean) => SimpleFormAction;
  submitShortlistAction: NoArgFormAction;
  closeNoSourceAction: SimpleFormAction;
  cancelAction: SimpleFormAction;
  reopenAction: SimpleFormAction;
}) {
  const isOpen = request.status === "open";
  const isDraft = request.status === "draft";
  const canReopen = request.status === "shortlisted" || request.status === "closed_no_source" || request.status === "cancelled";
  const shortlistedCount = candidates.filter((c) => c.shortlisted).length;

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">
            {request.originLane} → {request.destinationLane}
          </h1>
          <p className="text-xs text-neutral-500">
            {request.serviceType}
            {request.mode ? ` (${request.mode})` : ""} · {SOURCE_TYPE_LABEL[request.sourceType]}
          </p>
        </div>
        <StatusBadge tone={STATUS_TONE[request.status]} label={request.status.replace(/_/g, " ")} />
      </header>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Inherited demand constraints</h2>
        <p className="text-xs text-neutral-500">Read-only -- never a re-typeable form. Widen cargo_weight_max/cargo_volume_max/destination_lane only through the governed override below.</p>
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <ConstraintRow label="Cargo weight min" value={request.cargoWeightMin != null ? String(request.cargoWeightMin) : null} />
          <ConstraintRow label="Cargo weight max" value={request.cargoWeightMax != null ? String(request.cargoWeightMax) : null} />
          <ConstraintRow label="Cargo volume min" value={request.cargoVolumeMin != null ? String(request.cargoVolumeMin) : null} />
          <ConstraintRow label="Cargo volume max" value={request.cargoVolumeMax != null ? String(request.cargoVolumeMax) : null} />
          <ConstraintRow label="Requested pickup" value={request.requestedPickupAt ? new Date(request.requestedPickupAt).toLocaleString() : null} />
          <ConstraintRow label="Requested delivery" value={request.requestedDeliveryAt ? new Date(request.requestedDeliveryAt).toLocaleString() : null} />
          <ConstraintRow label="Currency" value={request.currency} />
          <ConstraintRow label="Budget" value={request.costMasked ? "masked" : request.budgetAmount != null ? String(request.budgetAmount) : null} />
          <ConstraintRow label="SLA due" value={request.slaDueAt ? new Date(request.slaDueAt).toLocaleString() : null} />
          <ConstraintRow label="Closed reason" value={request.closedReason} />
        </dl>

        {isOpen ? (
          <details className="text-xs">
            <summary className="cursor-pointer text-primary">Override constraints (governed exception)</summary>
            <ActionForm action={overrideAction} submitLabel="Apply override" loadingLabel="Applying…" variant="secondary" className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-4">
              {(describedBy) => (
                <>
                  <FormField id="cargoWeightMax" label="New cargo weight max (widen only)">
                    <Input id="cargoWeightMax" name="cargoWeightMax" type="number" min={0} aria-describedby={describedBy} />
                  </FormField>
                  <FormField id="cargoVolumeMax" label="New cargo volume max (widen only)">
                    <Input id="cargoVolumeMax" name="cargoVolumeMax" type="number" min={0} aria-describedby={describedBy} />
                  </FormField>
                  <FormField id="destinationLane" label="New destination lane">
                    <Input id="destinationLane" name="destinationLane" type="text" aria-describedby={describedBy} />
                  </FormField>
                  <FormField id="overrideExpiresAt" label="Override expires (optional)">
                    <Input id="overrideExpiresAt" name="overrideExpiresAt" type="datetime-local" aria-describedby={describedBy} />
                  </FormField>
                  <div className="sm:col-span-4">
                    <FormField id="overrideReason" label="Reason (required)">
                      <Input id="overrideReason" name="reason" type="text" required aria-describedby={describedBy} />
                    </FormField>
                  </div>
                </>
              )}
            </ActionForm>
          </details>
        ) : null}
      </section>

      <section className="flex flex-wrap gap-3 rounded-md border border-neutral-200 p-4">
        {isDraft ? <NoArgActionButton action={submitAction} label="Submit (draft → open)" loadingLabel="Submitting…" variant="primary" /> : null}
        {isOpen ? <NoArgActionButton action={evaluateEligibilityAction} label="Evaluate candidate eligibility" loadingLabel="Evaluating…" variant="primary" /> : null}
        {isOpen ? <NoArgActionButton action={submitShortlistAction} label={`Submit shortlist (${shortlistedCount} selected)`} loadingLabel="Submitting…" variant="primary" /> : null}
        {isOpen ? (
          <ActionForm action={closeNoSourceAction} submitLabel="Close: no source" loadingLabel="Closing…" variant="destructive" className="flex items-center gap-2">
            {(describedBy) => (
              <>
                <label htmlFor="close-no-source-reason" className="sr-only">
                  Reason
                </label>
                <Input id="close-no-source-reason" name="reason" type="text" placeholder="Reason (required)" required className="w-64" aria-describedby={describedBy} />
              </>
            )}
          </ActionForm>
        ) : null}
        {isDraft || isOpen ? (
          <ActionForm action={cancelAction} submitLabel="Cancel" loadingLabel="Cancelling…" variant="destructive" className="flex items-center gap-2">
            {(describedBy) => (
              <>
                <label htmlFor="cancel-sourcing-reason" className="sr-only">
                  Reason
                </label>
                <Input id="cancel-sourcing-reason" name="reason" type="text" placeholder="Reason (required)" required className="w-64" aria-describedby={describedBy} />
              </>
            )}
          </ActionForm>
        ) : null}
        {canReopen ? (
          <ActionForm action={reopenAction} submitLabel="Reopen" loadingLabel="Reopening…" variant="secondary" className="flex items-center gap-2">
            {(describedBy) => (
              <>
                <label htmlFor="reopen-sourcing-reason" className="sr-only">
                  Reason
                </label>
                <Input id="reopen-sourcing-reason" name="reason" type="text" placeholder="Reason (required)" required className="w-64" aria-describedby={describedBy} />
              </>
            )}
          </ActionForm>
        ) : null}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Candidate longlist</h2>
        <p className="text-xs text-neutral-500">
          Explainable eligibility -- an excluded candidate may still be shortlisted through a governed exception (reason required, elevated authority). No algorithm autonomously selects a vendor.
        </p>

        {candidates.length === 0 ? (
          <EmptyState title="No candidates evaluated yet" description={isOpen ? "Evaluate candidate eligibility above to populate the longlist." : "This sourcing request is not open -- candidates can only be (re-)evaluated while open."} />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Vendor</th>
                  <th className="px-3 py-2">Eligible</th>
                  <th className="px-3 py-2">Exclusion reasons</th>
                  <th className="px-3 py-2">Has active rate</th>
                  <th className="px-3 py-2">Shortlist</th>
                </tr>
              </thead>
              <tbody>
                {candidates.map((candidate) => {
                  const vendorName = typeof candidate.evaluationSnapshot.vendor_name === "string" ? candidate.evaluationSnapshot.vendor_name : candidate.vendorMasterId;
                  const vendorCode = typeof candidate.evaluationSnapshot.vendor_code === "string" ? ` (${candidate.evaluationSnapshot.vendor_code})` : "";
                  const hasActiveRate = candidate.evaluationSnapshot.has_active_rate === true;
                  return (
                    <tr key={candidate.id} className="border-t border-neutral-200 align-top">
                      <td className="px-3 py-2 font-medium text-neutral-900">
                        {vendorName}
                        {vendorCode}
                      </td>
                      <td className="px-3 py-2">
                        <StatusBadge tone={candidate.eligible ? "success" : "danger"} label={candidate.eligible ? "eligible" : "excluded"} />
                      </td>
                      <td className="px-3 py-2">
                        {candidate.exclusionReasons.length === 0 ? (
                          "—"
                        ) : (
                          <div className="flex flex-wrap gap-1">
                            {candidate.exclusionReasons.map((reason) => (
                              <StatusBadge key={reason} tone="warning" label={EXCLUSION_REASON_LABEL[reason as SourcingCandidateExclusionReason] ?? reason} />
                            ))}
                          </div>
                        )}
                      </td>
                      <td className="px-3 py-2 text-xs text-neutral-500">{hasActiveRate ? "yes (informational only)" : "no"}</td>
                      <td className="px-3 py-2">
                        {candidate.shortlisted ? (
                          <div className="flex flex-col gap-1">
                            <StatusBadge tone="success" label="shortlisted" />
                            {candidate.shortlistReason ? <p className="text-xs text-neutral-600">{candidate.shortlistReason}</p> : null}
                            {isOpen ? (
                              <ActionForm
                                action={shortlistActionFor(candidate.id, candidate.recordVersion, false)}
                                submitLabel="Remove from shortlist"
                                loadingLabel="Removing…"
                                variant="secondary"
                                className="flex flex-col gap-1"
                              />
                            ) : null}
                          </div>
                        ) : isOpen ? (
                          <ActionForm
                            action={shortlistActionFor(candidate.id, candidate.recordVersion, true)}
                            submitLabel={candidate.eligible ? "Shortlist" : "Shortlist (override)"}
                            loadingLabel="Shortlisting…"
                            variant={candidate.eligible ? "primary" : "destructive"}
                            className="flex flex-col gap-1"
                          >
                            {(describedBy) => (
                              <>
                                <label htmlFor={`shortlist-reason-${candidate.id}`} className="sr-only">
                                  Reason
                                </label>
                                <Input id={`shortlist-reason-${candidate.id}`} name="reason" type="text" placeholder="Reason (required)" required className="w-48 text-xs" aria-describedby={describedBy} />
                              </>
                            )}
                          </ActionForm>
                        ) : (
                          "—"
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Lifecycle history</h2>
        {history.length === 0 ? (
          <EmptyState title="No lifecycle events yet" />
        ) : (
          <ul className="flex flex-col gap-2">
            {history.map((event) => (
              <li key={event.id} className="flex flex-col gap-0.5 border-t border-neutral-100 pt-2 text-sm first:border-t-0 first:pt-0">
                <span className="text-xs text-neutral-500">{new Date(event.occurredAt).toLocaleString()}</span>
                <span className="text-neutral-900">
                  {event.fromStatus} → {event.toStatus}
                  {event.actorLabel ? ` · ${event.actorLabel}` : ""}
                </span>
                {event.reason ? <span className="text-xs text-neutral-600">{event.reason}</span> : null}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
