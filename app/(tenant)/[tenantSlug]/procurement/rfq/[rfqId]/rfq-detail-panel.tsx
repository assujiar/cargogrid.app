"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type {
  Rfq,
  RfqRequirementLine,
  RfqInvitation,
  RfqInvitationStatus,
  RfqClarification,
  RfqResponse,
  RfqResponseAttachment,
  RfqStatus,
  RfqEvent,
} from "../../../../../../server/contracts/rfq/rfq.ts";
import type { RfqActionState } from "../actions.ts";

const INITIAL_STATE: RfqActionState = { error: null };

const RFQ_STATUS_TONE: Record<RfqStatus, StatusTone> = {
  draft: "neutral",
  issued: "info",
  closed: "success",
  cancelled: "danger",
  superseded: "neutral",
};

const INVITATION_STATUS_TONE: Record<RfqInvitationStatus, StatusTone> = {
  invited: "info",
  declined: "danger",
  no_response: "warning",
  responded: "success",
  withdrawn: "neutral",
};

type SimpleFormAction = (prevState: RfqActionState, formData: FormData) => Promise<RfqActionState>;
type NoArgFormAction = (prevState: RfqActionState) => Promise<RfqActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
  className = "flex flex-col gap-2",
}: {
  action: SimpleFormAction;
  children?: React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className={className}>
      {children}
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
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
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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

export function RfqDetailPanel({
  rfq,
  requirementLines,
  invitations,
  clarifications,
  responses,
  attachmentsByResponseId,
  history,
  reviseAction,
  issueAction,
  inviteAdditionalAction,
  extendDeadlineAction,
  closeAction,
  cancelAction,
  declineInvitationActionFor,
  recordClarificationAction,
  answerClarificationActionFor,
  submitResponseActionFor,
  withdrawResponseActionFor,
}: {
  rfq: Rfq;
  requirementLines: readonly RfqRequirementLine[];
  invitations: readonly RfqInvitation[];
  clarifications: readonly RfqClarification[];
  responses: readonly RfqResponse[];
  attachmentsByResponseId: ReadonlyMap<string, RfqResponseAttachment[]>;
  history: readonly RfqEvent[];
  reviseAction: SimpleFormAction;
  issueAction: SimpleFormAction;
  inviteAdditionalAction: SimpleFormAction;
  extendDeadlineAction: SimpleFormAction;
  closeAction: NoArgFormAction;
  cancelAction: SimpleFormAction;
  declineInvitationActionFor: (invitationId: string, expectedVersion: number) => SimpleFormAction;
  recordClarificationAction: SimpleFormAction;
  answerClarificationActionFor: (clarificationId: string, expectedVersion: number) => SimpleFormAction;
  submitResponseActionFor: (invitationId: string) => SimpleFormAction;
  withdrawResponseActionFor: (responseId: string, expectedVersion: number) => SimpleFormAction;
}) {
  const isDraft = rfq.status === "draft";
  const isIssued = rfq.status === "issued";
  const responsesByInvitation = new Map<string, RfqResponse[]>();
  for (const response of responses) {
    const list = responsesByInvitation.get(response.rfqInvitationId) ?? [];
    list.push(response);
    responsesByInvitation.set(response.rfqInvitationId, list);
  }

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">
            {rfq.rfqNumber} <span className="text-sm font-normal text-neutral-500">v{rfq.version}</span>
          </h1>
          <p className="text-xs text-neutral-500">
            {rfq.originLane} → {rfq.destinationLane} · {rfq.serviceType}
            {rfq.mode ? ` (${rfq.mode})` : ""}
          </p>
        </div>
        <StatusBadge tone={RFQ_STATUS_TONE[rfq.status]} label={rfq.status} />
      </header>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Inherited requirements</h2>
        <p className="text-xs text-neutral-500">Read-only -- never a re-typeable form. A changed requirement is a governed revision (below), never a silent edit.</p>
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <ConstraintRow label="Cargo weight max" value={rfq.cargoWeightMax != null ? String(rfq.cargoWeightMax) : null} />
          <ConstraintRow label="Cargo volume max" value={rfq.cargoVolumeMax != null ? String(rfq.cargoVolumeMax) : null} />
          <ConstraintRow label="Currency" value={rfq.currency} />
          <ConstraintRow label="Response deadline" value={rfq.responseDeadlineAt ? new Date(rfq.responseDeadlineAt).toLocaleString() : null} />
          <ConstraintRow label="Issued" value={rfq.issuedAt ? new Date(rfq.issuedAt).toLocaleString() : null} />
          <ConstraintRow label="Closed reason" value={rfq.closedReason} />
        </dl>

        {requirementLines.length > 0 ? (
          <div className="overflow-x-auto rounded-md border border-neutral-100">
            <table className="w-full text-xs">
              <thead className="bg-neutral-50 text-left uppercase text-neutral-500">
                <tr>
                  <th className="px-2 py-1">#</th>
                  <th className="px-2 py-1">Description</th>
                  <th className="px-2 py-1">Quantity</th>
                  <th className="px-2 py-1">UoM</th>
                </tr>
              </thead>
              <tbody>
                {requirementLines.map((line) => (
                  <tr key={line.id} className="border-t border-neutral-100">
                    <td className="px-2 py-1">{line.lineNo}</td>
                    <td className="px-2 py-1">{line.description}</td>
                    <td className="px-2 py-1">{line.quantity ?? "—"}</td>
                    <td className="px-2 py-1">{line.uom ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}

        {isIssued ? (
          <details className="text-xs">
            <summary className="cursor-pointer text-primary">Revise (governed exception -- creates a new version)</summary>
            <ActionForm action={reviseAction} submitLabel="Revise RFQ" loadingLabel="Revising…" variant="secondary" className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-4">
              <div className="flex flex-col gap-1">
                <label htmlFor="reviseCargoWeightMax" className="text-xs font-medium text-neutral-700">
                  New cargo weight max
                </label>
                <Input id="reviseCargoWeightMax" name="cargoWeightMax" type="number" min={0} />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="reviseCargoVolumeMax" className="text-xs font-medium text-neutral-700">
                  New cargo volume max
                </label>
                <Input id="reviseCargoVolumeMax" name="cargoVolumeMax" type="number" min={0} />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="reviseDestinationLane" className="text-xs font-medium text-neutral-700">
                  New destination lane
                </label>
                <Input id="reviseDestinationLane" name="destinationLane" type="text" />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="reviseCurrency" className="text-xs font-medium text-neutral-700">
                  New currency
                </label>
                <Input id="reviseCurrency" name="currency" type="text" maxLength={3} />
              </div>
              <div className="flex flex-col gap-1 sm:col-span-4">
                <label htmlFor="reviseReason" className="text-xs font-medium text-neutral-700">
                  Reason (required)
                </label>
                <Input id="reviseReason" name="reason" type="text" required />
              </div>
            </ActionForm>
          </details>
        ) : null}
      </section>

      <section className="flex flex-wrap gap-3 rounded-md border border-neutral-200 p-4">
        {isDraft ? (
          <ActionForm action={issueAction} submitLabel="Issue RFQ" loadingLabel="Issuing…" variant="primary" className="flex items-end gap-2">
            <div className="flex flex-col gap-1">
              <label htmlFor="responseDeadlineAt" className="text-xs font-medium text-neutral-700">
                Response deadline (required)
              </label>
              <Input id="responseDeadlineAt" name="responseDeadlineAt" type="datetime-local" required />
            </div>
          </ActionForm>
        ) : null}
        {isIssued ? (
          <ActionForm action={extendDeadlineAction} submitLabel="Extend deadline" loadingLabel="Extending…" variant="secondary" className="flex items-end gap-2">
            <div className="flex flex-col gap-1">
              <label htmlFor="newDeadlineAt" className="text-xs font-medium text-neutral-700">
                New deadline (widen only)
              </label>
              <Input id="newDeadlineAt" name="newDeadlineAt" type="datetime-local" required />
            </div>
          </ActionForm>
        ) : null}
        {isIssued ? <NoArgActionButton action={closeAction} label="Close for comparison" loadingLabel="Closing…" variant="primary" /> : null}
        {isDraft || isIssued ? (
          <ActionForm action={cancelAction} submitLabel="Cancel" loadingLabel="Cancelling…" variant="destructive" className="flex items-center gap-2">
            <Input name="reason" type="text" placeholder="Reason (required)" required className="w-64" />
          </ActionForm>
        ) : null}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Invited vendors</h2>
        <p className="text-xs text-neutral-500">Every invitation traces to an eligible PRC-256 sourcing candidate. Vendors see only their own invitation and responses -- no such surface exists in this checkpoint.</p>

        {isIssued ? (
          <details className="text-xs">
            <summary className="cursor-pointer text-primary">Invite an additional eligible vendor (governed exception)</summary>
            <ActionForm action={inviteAdditionalAction} submitLabel="Invite" loadingLabel="Inviting…" variant="secondary" className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-end">
              <div className="flex flex-1 flex-col gap-1">
                <label htmlFor="sourcingCandidateId" className="text-xs font-medium text-neutral-700">
                  Sourcing candidate id (must be eligible)
                </label>
                <Input id="sourcingCandidateId" name="sourcingCandidateId" type="text" required />
              </div>
              <div className="flex flex-1 flex-col gap-1">
                <label htmlFor="inviteReason" className="text-xs font-medium text-neutral-700">
                  Reason (required)
                </label>
                <Input id="inviteReason" name="reason" type="text" required />
              </div>
            </ActionForm>
          </details>
        ) : null}

        {invitations.length === 0 ? (
          <EmptyState title="No vendors invited yet" description={isDraft ? "Issue the RFQ above to invite every shortlisted candidate." : undefined} />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Vendor</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Response capture</th>
                  <th className="px-3 py-2">Action</th>
                </tr>
              </thead>
              <tbody>
                {invitations.map((invitation) => {
                  const invitationResponses = (responsesByInvitation.get(invitation.id) ?? []).sort((a, b) => b.version - a.version);
                  const latest = invitationResponses[0];
                  const latestAttachmentCount = latest ? (attachmentsByResponseId.get(latest.id)?.length ?? 0) : 0;
                  return (
                    <tr key={invitation.id} className="border-t border-neutral-200 align-top">
                      <td className="px-3 py-2 font-mono text-xs text-neutral-700">{invitation.vendorMasterId}</td>
                      <td className="px-3 py-2">
                        <StatusBadge tone={INVITATION_STATUS_TONE[invitation.status]} label={invitation.status.replace(/_/g, " ")} />
                        {invitation.declineReason ? <p className="mt-1 text-xs text-neutral-500">{invitation.declineReason}</p> : null}
                      </td>
                      <td className="px-3 py-2">
                        {latest ? (
                          <div className="flex flex-col gap-1">
                            <span className="text-xs text-neutral-700">
                              v{latest.version} · {latest.status}
                              {latest.costMasked ? " · masked" : latest.totalAmount != null ? ` · ${latest.currency} ${latest.totalAmount}` : ""}
                            </span>
                            {latest.lateCapture ? <StatusBadge tone="warning" label="late capture" /> : null}
                            {latestAttachmentCount > 0 ? <span className="text-xs text-neutral-500">{latestAttachmentCount} attachment(s)</span> : null}
                            {latest.status === "submitted" ? (
                              <ActionForm
                                action={withdrawResponseActionFor(latest.id, latest.recordVersion)}
                                submitLabel="Withdraw"
                                loadingLabel="Withdrawing…"
                                variant="destructive"
                                className="flex flex-col gap-1"
                              >
                                <Input name="reason" type="text" placeholder="Reason (required)" required className="w-48 text-xs" />
                              </ActionForm>
                            ) : null}
                          </div>
                        ) : (
                          "—"
                        )}
                        {isIssued && (invitation.status === "invited" || invitation.status === "responded") ? (
                          <details className="mt-2 text-xs">
                            <summary className="cursor-pointer text-primary">{latest ? "Capture a revised response" : "Capture a response"}</summary>
                            <ActionForm
                              action={submitResponseActionFor(invitation.id)}
                              submitLabel="Capture response"
                              loadingLabel="Capturing…"
                              variant="secondary"
                              className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2"
                            >
                              <Input name="currency" type="text" placeholder="Currency (required)" maxLength={3} required />
                              <Input name="totalAmount" type="number" min={0} step="0.01" placeholder="Total amount (required)" required />
                              <Input name="leadTimeDays" type="number" min={0} placeholder="Lead time (days)" />
                              <Input name="validityUntil" type="datetime-local" />
                              <Input name="receivedAt" type="datetime-local" required />
                              <select name="captureMode" defaultValue="offline" className="rounded-md border border-neutral-300 px-2 py-1 text-xs">
                                <option value="offline">offline</option>
                                <option value="email">email</option>
                              </select>
                              <Input name="sourceMessageRef" type="text" placeholder="Source message reference" className="sm:col-span-2" />
                              <Input name="fileIds" type="text" placeholder="Attachment file id(s), comma-separated" className="sm:col-span-2" />
                              <Input name="lateReason" type="text" placeholder="Late-capture reason (only if past deadline)" className="sm:col-span-2" />
                              <label className="flex items-center gap-1 text-xs text-neutral-700 sm:col-span-2">
                                <input type="checkbox" name="vendorConfirmed" /> Vendor confirmed this offer
                              </label>
                            </ActionForm>
                          </details>
                        ) : null}
                      </td>
                      <td className="px-3 py-2">
                        {isIssued && invitation.status === "invited" ? (
                          <ActionForm
                            action={declineInvitationActionFor(invitation.id, invitation.recordVersion)}
                            submitLabel="Record decline"
                            loadingLabel="Recording…"
                            variant="destructive"
                            className="flex flex-col gap-1"
                          >
                            <Input name="reason" type="text" placeholder="Reason (required)" required className="w-40 text-xs" />
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
        <h2 className="text-sm font-semibold text-neutral-900">Clarifications</h2>

        {isIssued ? (
          <ActionForm action={recordClarificationAction} submitLabel="Record clarification" loadingLabel="Recording…" variant="secondary" className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="clarQuestion" className="text-xs font-medium text-neutral-700">
                Question (required)
              </label>
              <Input id="clarQuestion" name="question" type="text" required />
            </div>
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="clarVendor" className="text-xs font-medium text-neutral-700">
                Vendor id (blank = broadcast to all invited)
              </label>
              <Input id="clarVendor" name="vendorMasterId" type="text" />
            </div>
          </ActionForm>
        ) : null}

        {clarifications.length === 0 ? (
          <EmptyState title="No clarifications recorded yet" />
        ) : (
          <ul className="flex flex-col gap-3">
            {clarifications.map((clarification) => (
              <li key={clarification.id} className="border-t border-neutral-100 pt-2 text-sm first:border-t-0 first:pt-0">
                <p className="text-xs text-neutral-500">
                  {new Date(clarification.askedAt).toLocaleString()} · {clarification.vendorMasterId ? "vendor-scoped" : "broadcast"}
                </p>
                <p className="text-neutral-900">{clarification.question}</p>
                {clarification.answer ? (
                  <p className="mt-1 text-neutral-700">
                    <span className="font-medium">Answer:</span> {clarification.answer}
                  </p>
                ) : isIssued ? (
                  <ActionForm
                    action={answerClarificationActionFor(clarification.id, clarification.recordVersion)}
                    submitLabel="Answer"
                    loadingLabel="Saving…"
                    variant="secondary"
                    className="mt-1 flex items-center gap-2"
                  >
                    <Input name="answer" type="text" placeholder="Answer (required)" required className="w-64 text-xs" />
                  </ActionForm>
                ) : null}
              </li>
            ))}
          </ul>
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
