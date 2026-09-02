"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import type { VendorAssignmentInvitation, VendorAssignmentInvitationStatus, VendorAssignmentEligibilityPreview } from "../../../../../../server/contracts/vendor-assignment/vendor-assignment.ts";
import type { VendorAssignmentActionState } from "../actions.ts";

const INITIAL_STATE: VendorAssignmentActionState = { error: null };

const STATUS_TONE: Record<VendorAssignmentInvitationStatus, StatusTone> = {
  invited: "info",
  accepted: "info",
  declined: "danger",
  expired: "neutral",
  assigned: "success",
  cancelled: "neutral",
  superseded: "neutral",
};

type SimpleFormAction = (prevState: VendorAssignmentActionState, formData: FormData) => Promise<VendorAssignmentActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
}: {
  action: SimpleFormAction;
  children?: (describedBy: string | undefined) => React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2">
      {children?.(describedBy)}
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

function NoArgActionButton({ action, label, loadingLabel, variant = "secondary" }: { action: SimpleFormAction; label: string; loadingLabel?: string; variant?: "primary" | "secondary" | "destructive" }) {
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

export function VendorAssignmentInvitationDetailPanel({
  invitation,
  livePreview,
  acceptAction,
  declineAction,
  cancelAction,
  confirmAction,
  reassignAction,
}: {
  invitation: VendorAssignmentInvitation;
  livePreview: VendorAssignmentEligibilityPreview | null;
  acceptAction: SimpleFormAction;
  declineAction: SimpleFormAction;
  cancelAction: SimpleFormAction;
  confirmAction: SimpleFormAction;
  reassignAction: SimpleFormAction;
}) {
  const canAccept = invitation.status === "invited";
  const canDecline = invitation.status === "invited";
  const canCancel = invitation.status === "invited" || invitation.status === "accepted";
  const canConfirm = invitation.status === "accepted";
  const canReassign = invitation.status === "assigned";
  const snapshot = invitation.eligibilitySnapshot;
  const hasSnapshot = snapshot && Object.keys(snapshot).length > 0;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor assignment invitation</h1>
        <div className="mt-1 flex flex-wrap gap-2">
          <StatusBadge tone={STATUS_TONE[invitation.status]} label={invitation.status} />
          {invitation.isOverride ? <StatusBadge tone="danger" label="emergency override" /> : null}
        </div>
      </div>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Evidence</h2>
        <dl className="mt-2 grid grid-cols-1 gap-3 text-sm sm:grid-cols-3">
          <ConstraintRow label="Shipment order" value={invitation.shipmentOrderId} />
          <ConstraintRow label="Vendor" value={invitation.vendorMasterId} />
          <ConstraintRow label="Governing contract" value={invitation.contractId} />
          <ConstraintRow label="Purchase order" value={invitation.poId} />
          <ConstraintRow label="Rate version" value={invitation.rateVersionId} />
          <ConstraintRow label="Capacity reservation" value={invitation.capacityReservationId} />
          <ConstraintRow label="Response deadline" value={invitation.responseDeadline ? new Date(invitation.responseDeadline).toLocaleString() : null} />
          <ConstraintRow label="Canonical assignment" value={invitation.assignmentId} />
          <ConstraintRow label="Superseded by" value={invitation.supersededById} />
        </dl>
        {hasSnapshot ? (
          <div className="mt-3">
            <p className="text-xs font-medium text-neutral-500">Eligibility snapshot (taken at propose time, re-verified fresh at confirm -- never trusted stale)</p>
            <dl className="mt-1 grid grid-cols-1 gap-2 text-xs sm:grid-cols-3">
              <ConstraintRow label="Vendor lifecycle status" value={snapshot.vendor_lifecycle_status != null ? String(snapshot.vendor_lifecycle_status) : null} />
              <ConstraintRow label="Compliance hold" value={snapshot.compliance_hold != null ? String(snapshot.compliance_hold) : null} />
              <ConstraintRow label="Contract status" value={snapshot.contract_status != null ? String(snapshot.contract_status) : null} />
              <ConstraintRow label="PO status" value={snapshot.po_status != null ? String(snapshot.po_status) : null} />
              <ConstraintRow label="Capacity reservation status" value={snapshot.capacity_reservation_status != null ? String(snapshot.capacity_reservation_status) : null} />
              <ConstraintRow label="Evaluated at" value={snapshot.evaluated_at != null ? new Date(String(snapshot.evaluated_at)).toLocaleString() : null} />
            </dl>
          </div>
        ) : null}
        {livePreview ? (
          <div className="mt-3">
            <p className="text-xs font-medium text-neutral-500">Live eligibility (re-checked now -- not the stored snapshot above, which was taken at propose time)</p>
            <div className="mt-1 flex flex-wrap items-center gap-2">
              <StatusBadge tone={livePreview.eligible ? "success" : "danger"} label={livePreview.eligible ? "eligible now" : "not eligible now"} />
              {livePreview.reasons.map((r) => (
                <span key={r} className="text-xs text-neutral-500">
                  {r}
                </span>
              ))}
            </div>
            <p className="mt-1 text-xs text-neutral-500">This is a best-effort preview only -- accept/confirm each re-verify eligibility fresh server-side regardless.</p>
          </div>
        ) : null}
        {invitation.declineReason ? <p className="mt-2 text-xs text-neutral-500">Declined: {invitation.declineReason}</p> : null}
        {invitation.cancelReason ? <p className="mt-2 text-xs text-neutral-500">Cancelled: {invitation.cancelReason}</p> : null}
        {invitation.overrideReason ? <p className="mt-2 text-xs text-neutral-500">Override reason: {invitation.overrideReason}</p> : null}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

        {canAccept ? <NoArgActionButton action={acceptAction} label="Accept (record vendor's own response)" loadingLabel="Accepting…" variant="primary" /> : null}

        {canDecline ? (
          <ActionForm action={declineAction} submitLabel="Decline" loadingLabel="Declining…" variant="destructive">
            {(describedBy) => (
              <>
                <label htmlFor="decline-reason" className="sr-only">
                  Reason
                </label>
                <Input id="decline-reason" name="reason" type="text" placeholder="Reason (required)" required aria-describedby={describedBy} />
              </>
            )}
          </ActionForm>
        ) : null}

        {canCancel ? (
          <ActionForm action={cancelAction} submitLabel="Cancel invitation" loadingLabel="Cancelling…" variant="destructive">
            {(describedBy) => (
              <>
                <label htmlFor="cancel-reason" className="sr-only">
                  Reason
                </label>
                <Input id="cancel-reason" name="reason" type="text" placeholder="Reason (required)" required aria-describedby={describedBy} />
              </>
            )}
          </ActionForm>
        ) : null}

        {canConfirm ? (
          <div>
            <NoArgActionButton action={confirmAction} label="Confirm assignment (dispatcher, OPS:Assign)" loadingLabel="Confirming…" variant="primary" />
            <p className="mt-1 text-xs text-neutral-500">Re-verifies eligibility fresh, commits the canonical Operations resource assignment, and consumes any linked capacity reservation.</p>
          </div>
        ) : null}

        {canReassign ? (
          <ActionForm action={reassignAction} submitLabel="Reassign to a new vendor" loadingLabel="Reassigning…" variant="secondary">
            {(describedBy) => (
              <>
                <FormField id="reassign-newVendorMasterId" label="Replacement vendor master ID (required)">
                  <Input id="reassign-newVendorMasterId" name="newVendorMasterId" type="text" required placeholder="uuid" aria-describedby={describedBy} />
                </FormField>
                <FormField id="reassign-newContractId" label="New governing contract ID">
                  <Input id="reassign-newContractId" name="newContractId" type="text" placeholder="optional uuid" aria-describedby={describedBy} />
                </FormField>
                <FormField id="reassign-newCapacityReservationId" label="New capacity reservation ID">
                  <Input id="reassign-newCapacityReservationId" name="newCapacityReservationId" type="text" placeholder="optional uuid" aria-describedby={describedBy} />
                </FormField>
                <FormField id="reassign-reason" label="Reason (required)">
                  <Input id="reassign-reason" name="reason" type="text" required aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        ) : null}

        {!canAccept && !canDecline && !canCancel && !canConfirm && !canReassign ? <p className="text-xs text-neutral-500">No action is currently available for this invitation in its {invitation.status} state.</p> : null}
      </section>
    </div>
  );
}
