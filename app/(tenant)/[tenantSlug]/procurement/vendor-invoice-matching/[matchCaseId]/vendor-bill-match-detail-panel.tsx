"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
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

function ErrorText({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="text-xs text-danger">
      {error}
    </p>
  );
}

function MapLineForm({ line, expectedCaseVersion, mapLineAction }: { line: VendorBillMatchLine; expectedCaseVersion: number; mapLineAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(mapLineAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="matchLineId" value={line.id} />
      <input type="hidden" name="expectedCaseVersion" value={expectedCaseVersion} />
      <div className="flex flex-wrap items-center gap-1">
        <Input name="poLineId" placeholder="PO line id" defaultValue={line.poLineId ?? ""} className="w-40 text-xs" />
        <Input name="rateVersionId" placeholder="Rate version id" defaultValue={line.rateVersionId ?? ""} className="w-40 text-xs" />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Mapping…" className="text-xs">
          Map
        </Button>
      </div>
      <ErrorText error={state.error} />
    </form>
  );
}

function RaiseDisputeForm({ matchLineId, raiseDisputeAction }: { matchLineId: string | null; raiseDisputeAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(raiseDisputeAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      {matchLineId ? <input type="hidden" name="matchLineId" value={matchLineId} /> : null}
      <div className="flex flex-wrap items-center gap-1">
        <Input name="reason" placeholder="Dispute reason (required)" required className="w-56 text-xs" />
        <Input name="disputedAmount" type="number" step="0.01" placeholder="Disputed amount" className="w-32 text-xs" />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Raising…" className="text-xs">
          Raise dispute
        </Button>
      </div>
      <ErrorText error={state.error} />
    </form>
  );
}

function RespondDisputeForm({ dispute, respondDisputeAction }: { dispute: VendorBillMatchDispute; respondDisputeAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(respondDisputeAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="disputeId" value={dispute.id} />
      <input type="hidden" name="expectedVersion" value={dispute.recordVersion} />
      <div className="flex flex-wrap items-center gap-1">
        <Input name="vendorResponse" placeholder="Vendor's response (staff-recorded)" required className="w-64 text-xs" />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…" className="text-xs">
          Record response
        </Button>
      </div>
      <ErrorText error={state.error} />
    </form>
  );
}

function ResolveDisputeForm({ dispute, resolveDisputeAction }: { dispute: VendorBillMatchDispute; resolveDisputeAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(resolveDisputeAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="disputeId" value={dispute.id} />
      <input type="hidden" name="expectedVersion" value={dispute.recordVersion} />
      <div className="flex flex-wrap items-center gap-1">
        <select name="decision" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-xs">
          <option value="" disabled>
            Decision…
          </option>
          <option value="upheld">Upheld</option>
          <option value="rejected">Rejected</option>
          <option value="withdrawn">Withdrawn</option>
        </select>
        <Input name="resolutionNote" placeholder="Resolution note (required)" required className="w-56 text-xs" />
        <Button type="submit" loading={pending} loadingLabel="Resolving…" className="text-xs">
          Resolve
        </Button>
      </div>
      <ErrorText error={state.error} />
      <p className="text-[11px] text-neutral-500">You may not resolve a dispute you yourself raised (self-approval is blocked).</p>
    </form>
  );
}

function RequestExceptionForm({ requestExceptionAction }: { requestExceptionAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(requestExceptionAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex flex-wrap items-center gap-1">
        <Input name="reason" placeholder="Why this exception should be allowed to proceed (required)" required className="w-64 text-xs" />
        <Button type="submit" loading={pending} loadingLabel="Requesting…" className="text-xs">
          Request exception approval
        </Button>
      </div>
      <ErrorText error={state.error} />
    </form>
  );
}

function DecideExceptionForm({ approval, decideExceptionAction }: { approval: VendorBillMatchExceptionApproval; decideExceptionAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(decideExceptionAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="approvalId" value={approval.id} />
      <input type="hidden" name="expectedVersion" value={approval.recordVersion} />
      <div className="flex flex-wrap items-center gap-1">
        <select name="decision" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-xs">
          <option value="" disabled>
            Decision…
          </option>
          <option value="approved">Approve</option>
          <option value="rejected">Reject</option>
        </select>
        <Input name="decisionNote" placeholder="Decision note (required)" required className="w-56 text-xs" />
        <Button type="submit" loading={pending} loadingLabel="Deciding…" className="text-xs">
          Decide
        </Button>
      </div>
      <ErrorText error={state.error} />
      <p className="text-[11px] text-neutral-500">You may not decide an exception approval you yourself requested (self-approval is blocked).</p>
    </form>
  );
}

function ReEvaluateForm({ matchCase, lines, reEvaluateAction }: { matchCase: VendorBillMatchCase; lines: readonly VendorBillMatchLine[]; reEvaluateAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(reEvaluateAction, INITIAL_STATE);
  return (
    <details className="rounded-md border border-neutral-200 p-3">
      <summary className="cursor-pointer text-sm font-semibold text-neutral-900">Re-evaluate (creates a new version)</summary>
      <form action={formAction} className="mt-2 flex flex-col gap-2">
        <Input name="purchaseOrderId" placeholder="Purchase order id (optional)" defaultValue={matchCase.purchaseOrderId ?? ""} className="w-80 text-xs" />
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
                    <Input name={`quantity_${line.billLineId}`} type="number" step="0.0001" defaultValue={line.vendorStatedQuantity ?? undefined} className="w-20" />
                  </td>
                  <td className="px-2 py-1">
                    <Input name={`uom_${line.billLineId}`} defaultValue={line.vendorStatedUom ?? undefined} className="w-16" />
                  </td>
                  <td className="px-2 py-1">
                    <Input name={`rate_${line.billLineId}`} type="number" step="0.0001" defaultValue={line.vendorStatedRate ?? undefined} className="w-20" />
                  </td>
                  <td className="px-2 py-1">
                    <Input name={`amount_${line.billLineId}`} type="number" step="0.01" required defaultValue={line.vendorStatedAmount ?? undefined} className="w-24" />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <ErrorText error={state.error} />
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
            <ErrorText error={acceptState.error} />
          </form>
        ) : null}
        {matchCase.overallStatus === "exception" && !pendingApproval ? <RequestExceptionForm requestExceptionAction={requestExceptionAction} /> : null}
        {pendingApproval ? <DecideExceptionForm approval={pendingApproval} decideExceptionAction={decideExceptionAction} /> : null}
        {!openDispute && matchCase.overallStatus !== "cancelled" ? <RaiseDisputeForm matchLineId={null} raiseDisputeAction={raiseDisputeAction} /> : null}
        {matchCase.overallStatus !== "cancelled" && matchCase.overallStatus !== "matched" ? (
          <form action={cancelFormAction} className="flex flex-col gap-1">
            <Input name="reason" placeholder="Cancel reason (required)" required className="w-56 text-xs" />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…" className="text-xs">
              Cancel case
            </Button>
            <ErrorText error={cancelState.error} />
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
