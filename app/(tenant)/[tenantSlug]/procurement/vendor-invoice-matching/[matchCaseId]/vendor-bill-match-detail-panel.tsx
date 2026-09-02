"use client";

import { useActionState, useId } from "react";
import Link from "next/link";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import {
  type VendorBillMatchCase,
  type VendorBillMatchCaseStatus,
  type VendorBillMatchLine,
  type VendorBillMatchLineStatus,
  type VendorBillMatchEvent,
  type VendorBillMatchDispute,
  type VendorBillMatchExceptionApproval,
} from "../../../../../../server/contracts/vendor-invoice-matching/vendor-invoice-matching.ts";
import type { VendorBillMatchDetailActionState } from "./actions.ts";

const INITIAL_STATE: VendorBillMatchDetailActionState = { error: null };

const CASE_STATUS_TONE: Record<VendorBillMatchCaseStatus, StatusTone> = {
  pending: "neutral",
  matched: "success",
  exception: "warning",
  disputed: "danger",
  blocked: "danger",
  cancelled: "neutral",
};

const LINE_STATUS_TONE: Record<VendorBillMatchLineStatus, StatusTone> = {
  matched: "success",
  variance_within_tolerance: "info",
  variance_exception: "warning",
  missing_evidence: "danger",
  currency_mismatch: "danger",
};

type BoundFormAction = (prevState: VendorBillMatchDetailActionState, formData: FormData) => Promise<VendorBillMatchDetailActionState>;

function MapLineForm({ line, expectedCaseVersion, mapLineAction }: { line: VendorBillMatchLine; expectedCaseVersion: number; mapLineAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(mapLineAction, INITIAL_STATE);
  const errorId = `map-line-${line.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="matchLineId" value={line.id} />
      <input type="hidden" name="expectedCaseVersion" value={expectedCaseVersion} />
      <div className="flex flex-wrap items-center gap-1">
        <label htmlFor={`map-line-po-${line.id}`} className="sr-only">
          PO line id
        </label>
        <Input id={`map-line-po-${line.id}`} name="poLineId" placeholder="PO line id" defaultValue={line.poLineId ?? ""} className="w-40 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <label htmlFor={`map-line-rate-${line.id}`} className="sr-only">
          Rate version id
        </label>
        <Input id={`map-line-rate-${line.id}`} name="rateVersionId" placeholder="Rate version id" defaultValue={line.rateVersionId ?? ""} className="w-40 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Mapping…" className="text-xs">
          Map
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function RaiseDisputeForm({ matchLineId, raiseDisputeAction }: { matchLineId: string | null; raiseDisputeAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(raiseDisputeAction, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      {matchLineId ? <input type="hidden" name="matchLineId" value={matchLineId} /> : null}
      <div className="flex flex-wrap items-center gap-1">
        <label htmlFor={`${reactId}-reason`} className="sr-only">
          Dispute reason
        </label>
        <Input id={`${reactId}-reason`} name="reason" placeholder="Dispute reason (required)" required className="w-56 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <label htmlFor={`${reactId}-amount`} className="sr-only">
          Disputed amount
        </label>
        <Input id={`${reactId}-amount`} name="disputedAmount" type="number" step="0.01" placeholder="Disputed amount" invalid={Boolean(state.error)} aria-describedby={describedBy} className="w-32 text-xs" />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Raising…" className="text-xs">
          Raise dispute
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function RespondDisputeForm({ dispute, respondDisputeAction }: { dispute: VendorBillMatchDispute; respondDisputeAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(respondDisputeAction, INITIAL_STATE);
  const errorId = `respond-dispute-${dispute.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="disputeId" value={dispute.id} />
      <input type="hidden" name="expectedVersion" value={dispute.recordVersion} />
      <div className="flex flex-wrap items-center gap-1">
        <label htmlFor={`respond-dispute-text-${dispute.id}`} className="sr-only">
          Vendor&apos;s response
        </label>
        <Input id={`respond-dispute-text-${dispute.id}`} name="vendorResponse" placeholder="Vendor's response (staff-recorded)" required className="w-64 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…" className="text-xs">
          Record response
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ResolveDisputeForm({ dispute, resolveDisputeAction }: { dispute: VendorBillMatchDispute; resolveDisputeAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(resolveDisputeAction, INITIAL_STATE);
  const errorId = `resolve-dispute-${dispute.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="disputeId" value={dispute.id} />
      <input type="hidden" name="expectedVersion" value={dispute.recordVersion} />
      <div className="flex flex-wrap items-center gap-1">
        <label htmlFor={`resolve-dispute-decision-${dispute.id}`} className="sr-only">
          Decision
        </label>
        <Select id={`resolve-dispute-decision-${dispute.id}`} name="decision" required defaultValue="" className="text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Decision…
          </option>
          <option value="upheld">Upheld</option>
          <option value="rejected">Rejected</option>
          <option value="withdrawn">Withdrawn</option>
        </Select>
        <label htmlFor={`resolve-dispute-note-${dispute.id}`} className="sr-only">
          Resolution note
        </label>
        <Input id={`resolve-dispute-note-${dispute.id}`} name="resolutionNote" placeholder="Resolution note (required)" required className="w-56 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <Button type="submit" loading={pending} loadingLabel="Resolving…" className="text-xs">
          Resolve
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      <p className="text-[11px] text-neutral-500">You may not resolve a dispute you yourself raised (self-approval is blocked).</p>
    </form>
  );
}

function RequestExceptionForm({ requestExceptionAction }: { requestExceptionAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(requestExceptionAction, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex flex-wrap items-center gap-1">
        <label htmlFor={reactId} className="sr-only">
          Exception reason
        </label>
        <Input id={reactId} name="reason" placeholder="Why this exception should be allowed to proceed (required)" required className="w-64 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <Button type="submit" loading={pending} loadingLabel="Requesting…" className="text-xs">
          Request exception approval
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function DecideExceptionForm({ approval, decideExceptionAction }: { approval: VendorBillMatchExceptionApproval; decideExceptionAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(decideExceptionAction, INITIAL_STATE);
  const errorId = `decide-exception-${approval.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="approvalId" value={approval.id} />
      <input type="hidden" name="expectedVersion" value={approval.recordVersion} />
      <div className="flex flex-wrap items-center gap-1">
        <label htmlFor={`decide-exception-decision-${approval.id}`} className="sr-only">
          Decision
        </label>
        <Select id={`decide-exception-decision-${approval.id}`} name="decision" required defaultValue="" className="text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Decision…
          </option>
          <option value="approved">Approve</option>
          <option value="rejected">Reject</option>
        </Select>
        <label htmlFor={`decide-exception-note-${approval.id}`} className="sr-only">
          Decision note
        </label>
        <Input id={`decide-exception-note-${approval.id}`} name="decisionNote" placeholder="Decision note (required)" required className="w-56 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <Button type="submit" loading={pending} loadingLabel="Deciding…" className="text-xs">
          Decide
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      <p className="text-[11px] text-neutral-500">You may not decide an exception approval you yourself requested (self-approval is blocked).</p>
    </form>
  );
}

function ReEvaluateForm({ matchCase, lines, reEvaluateAction }: { matchCase: VendorBillMatchCase; lines: readonly VendorBillMatchLine[]; reEvaluateAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(reEvaluateAction, INITIAL_STATE);
  const errorId = "re-evaluate-error";
  const describedBy = state.error ? errorId : undefined;
  return (
    <details className="rounded-md border border-neutral-200 p-3">
      <summary className="cursor-pointer text-sm font-semibold text-neutral-900">Re-evaluate (creates a new version)</summary>
      <form action={formAction} className="mt-2 flex flex-col gap-2">
        <label htmlFor="re-evaluate-po" className="sr-only">
          Purchase order id
        </label>
        <Input id="re-evaluate-po" name="purchaseOrderId" placeholder="Purchase order id (optional)" defaultValue={matchCase.purchaseOrderId ?? ""} className="w-80 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-xs">
            <thead className="bg-neutral-50 text-left uppercase text-neutral-500">
              <tr>
                <th className="px-2 py-1">Line</th>
                <th className="px-2 py-1">Vendor qty</th>
                <th className="px-2 py-1">Vendor UOM</th>
                <th className="px-2 py-1">Vendor rate</th>
                <th className="px-2 py-1">Vendor amount</th>
              </tr>
            </thead>
            <tbody>
              {lines.map((line) => (
                <tr key={line.billLineId} className="border-t border-neutral-200">
                  <td className="px-2 py-1">{line.lineNo}</td>
                  <td className="px-2 py-1">
                    <label htmlFor={`re-evaluate-qty-${line.billLineId}`} className="sr-only">
                      Vendor quantity, line {line.lineNo}
                    </label>
                    <Input id={`re-evaluate-qty-${line.billLineId}`} name={`quantity_${line.billLineId}`} type="number" step="0.0001" defaultValue={line.vendorStatedQuantity ?? undefined} className="w-20" invalid={Boolean(state.error)} aria-describedby={describedBy} />
                  </td>
                  <td className="px-2 py-1">
                    <label htmlFor={`re-evaluate-uom-${line.billLineId}`} className="sr-only">
                      Vendor UOM, line {line.lineNo}
                    </label>
                    <Input id={`re-evaluate-uom-${line.billLineId}`} name={`uom_${line.billLineId}`} defaultValue={line.vendorStatedUom ?? undefined} className="w-16" invalid={Boolean(state.error)} aria-describedby={describedBy} />
                  </td>
                  <td className="px-2 py-1">
                    <label htmlFor={`re-evaluate-rate-${line.billLineId}`} className="sr-only">
                      Vendor rate, line {line.lineNo}
                    </label>
                    <Input id={`re-evaluate-rate-${line.billLineId}`} name={`rate_${line.billLineId}`} type="number" step="0.0001" defaultValue={line.vendorStatedRate ?? undefined} className="w-20" invalid={Boolean(state.error)} aria-describedby={describedBy} />
                  </td>
                  <td className="px-2 py-1">
                    <label htmlFor={`re-evaluate-amount-${line.billLineId}`} className="sr-only">
                      Vendor amount, line {line.lineNo}
                    </label>
                    <Input id={`re-evaluate-amount-${line.billLineId}`} name={`amount_${line.billLineId}`} type="number" step="0.01" required defaultValue={line.vendorStatedAmount ?? undefined} className="w-24" invalid={Boolean(state.error)} aria-describedby={describedBy} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
        <Button type="submit" loading={pending} loadingLabel="Re-evaluating…" className="w-fit">
          Re-evaluate
        </Button>
      </form>
    </details>
  );
}

export function VendorBillMatchDetailPanel({
  tenantSlug,
  matchCase,
  lines,
  events,
  disputes,
  exceptionApprovals,
  versions,
  reEvaluateAction,
  mapLineAction,
  acceptAction,
  cancelAction,
  raiseDisputeAction,
  respondDisputeAction,
  resolveDisputeAction,
  requestExceptionAction,
  decideExceptionAction,
}: {
  tenantSlug: string;
  matchCase: VendorBillMatchCase;
  lines: readonly VendorBillMatchLine[];
  events: readonly VendorBillMatchEvent[];
  disputes: readonly VendorBillMatchDispute[];
  exceptionApprovals: readonly VendorBillMatchExceptionApproval[];
  versions: readonly VendorBillMatchCase[];
  reEvaluateAction: BoundFormAction;
  mapLineAction: BoundFormAction;
  acceptAction: BoundFormAction;
  cancelAction: BoundFormAction;
  raiseDisputeAction: BoundFormAction;
  respondDisputeAction: BoundFormAction;
  resolveDisputeAction: BoundFormAction;
  requestExceptionAction: BoundFormAction;
  decideExceptionAction: BoundFormAction;
}) {
  const [acceptState, acceptFormAction, acceptPending] = useActionState(acceptAction, INITIAL_STATE);
  const [cancelState, cancelFormAction, cancelPending] = useActionState(cancelAction, INITIAL_STATE);
  const openDispute = disputes.find((d) => d.status === "open") ?? null;
  const pendingApproval = exceptionApprovals.find((a) => a.status === "pending") ?? null;

  return (
    <div className="flex flex-col gap-6">
      <section className="grid grid-cols-2 gap-2 rounded-md border border-neutral-200 p-4 text-sm sm:grid-cols-4">
        <div>
          <div className="text-xs text-neutral-500">Status</div>
          <StatusBadge tone={CASE_STATUS_TONE[matchCase.overallStatus]} label={matchCase.overallStatus} />
        </div>
        <div>
          <div className="text-xs text-neutral-500">Readiness</div>
          <div className="font-medium text-neutral-900">{matchCase.readinessStatus}</div>
        </div>
        <div>
          <div className="text-xs text-neutral-500">Match mode</div>
          <div className="font-medium text-neutral-900">{matchCase.matchMode}</div>
        </div>
        <div>
          <div className="text-xs text-neutral-500">Duplicate</div>
          <div className="font-medium text-neutral-900">{matchCase.isDuplicateFlagged ? `flagged (see ${matchCase.duplicateOfCaseId ?? "an earlier case"})` : "no"}</div>
        </div>
        <div>
          <div className="text-xs text-neutral-500">Vendor-stated total</div>
          <div className="font-medium text-neutral-900">{matchCase.totalVendorStatedAmount === null ? "masked" : `${matchCase.totalVendorStatedAmount} ${matchCase.currency}`}</div>
        </div>
        <div>
          <div className="text-xs text-neutral-500">Evidence total</div>
          <div className="font-medium text-neutral-900">{matchCase.totalEvidenceAmount === null ? "masked" : `${matchCase.totalEvidenceAmount} ${matchCase.currency}`}</div>
        </div>
        <div>
          <div className="text-xs text-neutral-500">Variance</div>
          <div className="font-medium text-neutral-900">{matchCase.totalVariancePct === null ? "masked" : `${matchCase.totalVariancePct}%`}</div>
        </div>
        <div>
          <div className="text-xs text-neutral-500">ePOD / delivery evidence</div>
          <div className="font-medium text-neutral-900">
            {matchCase.hasEpodEvidence ? "ePOD complete" : "no ePOD"} / {matchCase.hasDeliveryMilestoneEvidence ? "delivery milestone" : "no delivery milestone"}
          </div>
        </div>
        {matchCase.readinessNote ? <div className="col-span-full text-xs text-neutral-600">{matchCase.readinessNote}</div> : null}
      </section>

      <section className="flex flex-wrap items-start gap-4">
        {matchCase.overallStatus === "pending" ? (
          <form action={acceptFormAction} className="flex flex-col gap-1">
            <Button type="submit" loading={acceptPending} loadingLabel="Accepting…">
              Accept within tolerance
            </Button>
            {acceptState.error ? <ValidationMessage>{acceptState.error}</ValidationMessage> : null}
          </form>
        ) : null}
        {matchCase.overallStatus === "exception" && !pendingApproval ? <RequestExceptionForm requestExceptionAction={requestExceptionAction} /> : null}
        {pendingApproval ? <DecideExceptionForm approval={pendingApproval} decideExceptionAction={decideExceptionAction} /> : null}
        {!openDispute && matchCase.overallStatus !== "cancelled" ? <RaiseDisputeForm matchLineId={null} raiseDisputeAction={raiseDisputeAction} /> : null}
        {matchCase.overallStatus !== "cancelled" && matchCase.overallStatus !== "matched" ? (
          <form action={cancelFormAction} className="flex flex-col gap-1">
            <label htmlFor="cancel-case-reason" className="sr-only">
              Cancel reason
            </label>
            <Input id="cancel-case-reason" name="reason" placeholder="Cancel reason (required)" required className="w-56 text-xs" invalid={Boolean(cancelState.error)} aria-describedby={cancelState.error ? "cancel-case-error" : undefined} />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…" className="text-xs">
              Cancel case
            </Button>
            {cancelState.error ? <ValidationMessage id="cancel-case-error">{cancelState.error}</ValidationMessage> : null}
          </form>
        ) : null}
      </section>

      {openDispute ? (
        <section className="rounded-md border border-danger/40 bg-danger/5 p-3">
          <h2 className="text-sm font-semibold text-neutral-900">Open dispute</h2>
          <p className="text-xs text-neutral-700">{openDispute.reason}</p>
          {openDispute.vendorResponse ? <p className="mt-1 text-xs text-neutral-600">Vendor response: {openDispute.vendorResponse}</p> : <RespondDisputeForm dispute={openDispute} respondDisputeAction={respondDisputeAction} />}
          <div className="mt-2">
            <ResolveDisputeForm dispute={openDispute} resolveDisputeAction={resolveDisputeAction} />
          </div>
        </section>
      ) : null}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Lines</h2>
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-xs">
            <thead className="bg-neutral-50 text-left uppercase text-neutral-500">
              <tr>
                <th className="px-2 py-1">#</th>
                <th className="px-2 py-1">Type</th>
                <th className="px-2 py-1">Vendor stated</th>
                <th className="px-2 py-1">Evidence</th>
                <th className="px-2 py-1">Variance</th>
                <th className="px-2 py-1">Status</th>
                <th className="px-2 py-1">Map evidence</th>
              </tr>
            </thead>
            <tbody>
              {lines.map((line) => (
                <tr key={line.id} className="border-t border-neutral-200 align-top">
                  <td className="px-2 py-1">{line.lineNo}</td>
                  <td className="px-2 py-1">{line.lineType}</td>
                  <td className="px-2 py-1">
                    {line.vendorStatedAmount === null ? "masked" : line.vendorStatedAmount}
                    {line.vendorStatedQuantity !== null ? ` (${line.vendorStatedQuantity} ${line.vendorStatedUom ?? ""})` : ""}
                  </td>
                  <td className="px-2 py-1">
                    {line.evidenceAmount === null ? "missing" : line.evidenceAmount}
                    {line.evidenceQuantity !== null ? ` (${line.evidenceQuantity} ${line.evidenceUom ?? ""})` : ""}
                  </td>
                  <td className="px-2 py-1">
                    {line.currencyMismatch ? "currency mismatch" : line.amountVariancePct === null ? "-" : `${line.amountVariancePct}%`}
                    {line.uomMismatch ? " (UOM mismatch)" : ""}
                  </td>
                  <td className="px-2 py-1">
                    <StatusBadge tone={LINE_STATUS_TONE[line.lineStatus]} label={line.lineStatus} />
                  </td>
                  <td className="px-2 py-1">
                    {matchCase.overallStatus === "pending" || matchCase.overallStatus === "exception" ? (
                      <MapLineForm line={line} expectedCaseVersion={matchCase.recordVersion} mapLineAction={mapLineAction} />
                    ) : (
                      <span className="text-neutral-400">locked</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <ReEvaluateForm matchCase={matchCase} lines={lines} reEvaluateAction={reEvaluateAction} />

      {exceptionApprovals.length > 0 ? (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Exception approval history</h2>
          <ul className="flex flex-col gap-1 text-xs text-neutral-700">
            {exceptionApprovals.map((a) => (
              <li key={a.id}>
                {a.status} -- {a.reason} {a.decisionNote ? `(${a.decisionNote})` : ""}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {disputes.length > 0 ? (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Dispute history</h2>
          <ul className="flex flex-col gap-1 text-xs text-neutral-700">
            {disputes.map((d) => (
              <li key={d.id}>
                {d.status} -- {d.reason} {d.resolutionNote ? `(${d.resolutionNote})` : ""}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {versions.length > 1 ? (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Version history</h2>
          <p className="text-xs text-neutral-500">Each re-evaluation opens a new version and re-runs the duplicate check; earlier versions stay visible for audit but only the current version is actionable.</p>
          <ul className="flex flex-col gap-1 text-xs text-neutral-700">
            {versions.map((v) => (
              <li key={v.id}>
                {v.id === matchCase.id ? (
                  <span className="font-medium text-neutral-900">v{v.versionNo} (viewing)</span>
                ) : (
                  <Link href={`/${tenantSlug}/procurement/vendor-invoice-matching/${v.id}`} className="font-medium text-primary hover:underline">
                    v{v.versionNo}
                  </Link>
                )}{" "}
                -- {v.overallStatus} / {v.readinessStatus}
                {v.isCurrent ? "" : " (superseded)"}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">History</h2>
        <ul className="flex flex-col gap-1 text-xs text-neutral-700">
          {events.map((e) => (
            <li key={e.id}>
              {e.createdAt} -- {e.eventType}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
