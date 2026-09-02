"use client";

/**
 * Pending milestone candidate / exception signal review panels (ATW-226H). Wires
 * ATW-226G's own confirm/dismiss RPCs (via ./actions.ts) -- this UI never creates a
 * real app.milestone_events/app.operational_exceptions row itself, it only invokes the
 * RPC that does, with the signed-in reviewer's own real identity.
 */

import { useActionState, useId } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { TenantPendingMilestoneCandidateRow, TenantPendingExceptionSignalRow } from "../../../../../server/contracts/fleet-control-tower/fleet-control-tower.ts";
import type { FleetControlTowerFormState } from "./actions.ts";

const INITIAL_STATE: FleetControlTowerFormState = { error: null };

const SEVERITY_TONE: Record<string, StatusTone> = { low: "info", medium: "warning", high: "warning", critical: "danger" };

type BoundAction = (prevState: FleetControlTowerFormState, formData: FormData) => Promise<FleetControlTowerFormState>;

export function MilestoneCandidatesPanel({
  candidates,
  confirmActionFor,
  dismissActionFor,
}: {
  candidates: readonly TenantPendingMilestoneCandidateRow[];
  confirmActionFor: (candidateId: string) => BoundAction;
  dismissActionFor: (candidateId: string) => BoundAction;
}) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Pending milestone candidates</h2>
        <p className="text-xs text-neutral-500">Detected from geofence dwell -- confirm to create a real milestone event, or dismiss with a reason.</p>
      </div>
      {candidates.length === 0 ? (
        <p className="text-sm text-neutral-500">No pending milestone candidates.</p>
      ) : (
        <ol className="flex flex-col gap-3">
          {candidates.map((candidate) => (
            <MilestoneCandidateRow key={candidate.id} candidate={candidate} confirmAction={confirmActionFor(candidate.id)} dismissAction={dismissActionFor(candidate.id)} />
          ))}
        </ol>
      )}
    </section>
  );
}

function MilestoneCandidateRow({ candidate, confirmAction, dismissAction }: { candidate: TenantPendingMilestoneCandidateRow; confirmAction: BoundAction; dismissAction: BoundAction }) {
  const [confirmState, confirmFormAction, confirmPending] = useActionState(confirmAction, INITIAL_STATE);
  const [dismissState, dismissFormAction, dismissPending] = useActionState(dismissAction, INITIAL_STATE);
  // This component renders once per candidate row, so every id must be row-unique.
  const rowId = useId();
  const overrideConflictId = `${rowId}-override-conflict`;
  const reviewNoteId = `${rowId}-review-note`;
  const confirmErrorId = `${rowId}-confirm-error`;
  const dismissErrorId = `${rowId}-dismiss-error`;

  return (
    <li className="flex flex-col gap-2 border-b border-neutral-100 pb-3 last:border-b-0 last:pb-0">
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium text-neutral-900">
          {candidate.shipmentNumber} — {candidate.milestoneCode}
        </span>
      </div>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-neutral-600">
        <dt>Candidate event time</dt>
        <dd>{new Date(candidate.candidateEventTime).toLocaleString()}</dd>
        <dt>Detected</dt>
        <dd>{new Date(candidate.detectedAt).toLocaleString()}</dd>
      </dl>

      <div className="flex flex-wrap items-end gap-2">
        <form action={confirmFormAction} className="flex items-center gap-2">
          <Checkbox
            id={overrideConflictId}
            name="overrideConflict"
            label="Override conflict"
            aria-describedby={confirmState.error ? confirmErrorId : undefined}
          />
          <Button type="submit" loading={confirmPending} loadingLabel="Confirming…">
            Confirm
          </Button>
        </form>
        <form action={dismissFormAction} className="flex items-center gap-2">
          <FormField id={reviewNoteId} label={<span className="sr-only">Reason for dismissal</span>}>
            <Input
              id={reviewNoteId}
              name="reviewNote"
              type="text"
              required
              placeholder="Reason for dismissal"
              invalid={Boolean(dismissState.error)}
              aria-describedby={dismissState.error ? dismissErrorId : undefined}
            />
          </FormField>
          <Button type="submit" variant="secondary" loading={dismissPending} loadingLabel="Dismissing…">
            Dismiss
          </Button>
        </form>
      </div>
      {confirmState.error ? <ValidationMessage id={confirmErrorId}>{confirmState.error}</ValidationMessage> : null}
      {dismissState.error ? <ValidationMessage id={dismissErrorId}>{dismissState.error}</ValidationMessage> : null}
    </li>
  );
}

export function ExceptionSignalsPanel({
  signals,
  confirmActionFor,
  dismissActionFor,
}: {
  signals: readonly TenantPendingExceptionSignalRow[];
  confirmActionFor: (signalId: string) => BoundAction;
  dismissActionFor: (signalId: string) => BoundAction;
}) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Pending exception signals</h2>
        <p className="text-xs text-neutral-500">Detected from route deviation or overdue geofence arrival -- confirm to create a real operational exception, or dismiss with a reason.</p>
      </div>
      {signals.length === 0 ? (
        <p className="text-sm text-neutral-500">No pending exception signals.</p>
      ) : (
        <ol className="flex flex-col gap-3">
          {signals.map((signal) => (
            <ExceptionSignalRow key={signal.id} signal={signal} confirmAction={confirmActionFor(signal.id)} dismissAction={dismissActionFor(signal.id)} />
          ))}
        </ol>
      )}
    </section>
  );
}

function ExceptionSignalRow({ signal, confirmAction, dismissAction }: { signal: TenantPendingExceptionSignalRow; confirmAction: BoundAction; dismissAction: BoundAction }) {
  const [confirmState, confirmFormAction, confirmPending] = useActionState(confirmAction, INITIAL_STATE);
  const [dismissState, dismissFormAction, dismissPending] = useActionState(dismissAction, INITIAL_STATE);
  // This component renders once per signal row, so every id must be row-unique.
  const rowId = useId();
  const reviewNoteId = `${rowId}-review-note`;
  const confirmErrorId = `${rowId}-confirm-error`;
  const dismissErrorId = `${rowId}-dismiss-error`;

  return (
    <li className="flex flex-col gap-2 border-b border-neutral-100 pb-3 last:border-b-0 last:pb-0">
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium text-neutral-900">
          {signal.shipmentNumber} — {signal.exceptionType}
        </span>
        <StatusBadge tone={SEVERITY_TONE[signal.severity] ?? "neutral"} label={signal.severity} />
        <StatusBadge tone="neutral" label={signal.signalType} />
      </div>
      <p className="text-sm text-neutral-700">{signal.description}</p>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-neutral-600">
        <dt>Detected</dt>
        <dd>{new Date(signal.detectedAt).toLocaleString()}</dd>
      </dl>

      <div className="flex flex-wrap items-end gap-2">
        <form action={confirmFormAction}>
          <Button type="submit" loading={confirmPending} loadingLabel="Confirming…">
            Confirm
          </Button>
        </form>
        <form action={dismissFormAction} className="flex items-center gap-2">
          <FormField id={reviewNoteId} label={<span className="sr-only">Reason for dismissal</span>}>
            <Input
              id={reviewNoteId}
              name="reviewNote"
              type="text"
              required
              placeholder="Reason for dismissal"
              invalid={Boolean(dismissState.error)}
              aria-describedby={dismissState.error ? dismissErrorId : undefined}
            />
          </FormField>
          <Button type="submit" variant="secondary" loading={dismissPending} loadingLabel="Dismissing…">
            Dismiss
          </Button>
        </form>
      </div>
      {confirmState.error ? <ValidationMessage id={confirmErrorId}>{confirmState.error}</ValidationMessage> : null}
      {dismissState.error ? <ValidationMessage id={dismissErrorId}>{dismissState.error}</ValidationMessage> : null}
    </li>
  );
}
