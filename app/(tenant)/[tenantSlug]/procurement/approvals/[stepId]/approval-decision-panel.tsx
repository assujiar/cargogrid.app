"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import type { ApprovalRequestHistoryEntry } from "../../../../../../server/contracts/approval/approval.ts";
import type { ProcurementApprovalContextSnapshot, ProcurementApprovalEntityType } from "../../../../../../server/contracts/procurement-approval/procurement-approval.ts";
import type { ProcurementApprovalActionState } from "../actions.ts";

const INITIAL_STATE: ProcurementApprovalActionState = { error: null };

const ENTITY_TYPE_LABELS: Record<string, string> = {
  vendor_activation: "Vendor activation",
  rate_version: "Rate approval",
  vendor_selection: "Vendor selection",
  purchase_order: "Purchase order",
  vendor_contract: "Vendor contract",
  exception_override: "Exception / override",
};

const STEP_STATUS_TONE: Record<string, StatusTone> = { pending: "neutral", active: "info", approved: "success", rejected: "danger", skipped: "neutral" };
const REQUEST_STATUS_TONE: Record<string, StatusTone> = { pending: "info", approved: "success", rejected: "danger", cancelled: "neutral" };

type DecideFormAction = (prevState: ProcurementApprovalActionState, formData: FormData) => Promise<ProcurementApprovalActionState>;

export function ProcurementApprovalDecisionPanel({
  tenantSlug,
  stepOrder,
  stepStatus,
  requestId,
  requestStatus,
  entityType,
  snapshot,
  history,
  canDecide,
  decideAction,
}: {
  tenantSlug: string;
  stepOrder: number;
  stepStatus: string;
  requestId: string;
  requestStatus: string;
  entityType: ProcurementApprovalEntityType;
  snapshot: ProcurementApprovalContextSnapshot;
  history: readonly ApprovalRequestHistoryEntry[];
  canDecide: boolean;
  decideAction: DecideFormAction;
}) {
  const [decideState, decideFormAction, decidePending] = useActionState(decideAction, INITIAL_STATE);
  // Prompt 259 §16's MFA-for-privileged-approvers gate (batch 257-259 review, C-18,
  // HIGH) -- mirrors CreditApprovalDecisionForm's (COM-157) own reauth-freshness
  // checkbox exactly. No live MFA challenge UI exists yet anywhere in this repository
  // (the migration's own disclosed boundary) -- checking the box captures the current
  // timestamp as the caller's own attestation, which the server independently
  // re-validates for freshness (<=5 minutes) on every call, never trusted blindly.
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const [reauthConfirmedAt, setReauthConfirmedAt] = useState("");

  const historyColumns: readonly DataTableColumn<ApprovalRequestHistoryEntry>[] = [
    { key: "step", header: "Step", render: (row) => `${row.stepOrder}` },
    { key: "status", header: "Status", render: (row) => <StatusBadge tone={STEP_STATUS_TONE[row.stepStatus] ?? "neutral"} label={row.stepStatus} /> },
    { key: "decision", header: "Decision", render: (row) => row.decision ?? "—" },
    { key: "actor", header: "Decided by", render: (row) => row.actorLabel ?? "—" },
    { key: "reason", header: "Reason", render: (row) => row.reason ?? "—" },
    { key: "decidedAt", header: "Decided at", render: (row) => (row.decidedAt ? new Date(row.decidedAt).toLocaleString() : "—") },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <a href={`/${tenantSlug}/procurement/approvals`} className="text-xs font-medium text-primary underline">
          ← Back to approvals
        </a>
        <h1 className="text-xl font-semibold text-neutral-900">{ENTITY_TYPE_LABELS[entityType] ?? entityType} approval</h1>
        <p className="text-xs text-neutral-500">
          Step {stepOrder} of approval request {requestId}. Request status: <StatusBadge tone={REQUEST_STATUS_TONE[requestStatus] ?? "neutral"} label={requestStatus} />
        </p>
      </div>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Decision context (immutable snapshot at routing time)</h2>
        <dl className="mt-2 grid grid-cols-1 gap-2 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium text-neutral-500">Governed entity</dt>
            <dd className="text-neutral-900">
              {ENTITY_TYPE_LABELS[snapshot.entityType] ?? snapshot.entityType} ({snapshot.entityId ?? "—"})
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium text-neutral-500">Reasons this decision was routed</dt>
            <dd className="text-neutral-900">{snapshot.reasons.length > 0 ? snapshot.reasons.join(", ") : "—"}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium text-neutral-500">Value</dt>
            <dd className="text-neutral-900">
              {snapshot.costMasked ? "Masked (requires Procurement: View cost)" : snapshot.valueAmount !== null ? `${snapshot.valueAmount} ${snapshot.currency ?? ""}` : "—"}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium text-neutral-500">Snapshotted at</dt>
            <dd className="text-neutral-900">{new Date(snapshot.createdAt).toLocaleString()}</dd>
          </div>
        </dl>
        {Object.keys(snapshot.context).length > 0 ? (
          <div className="mt-2">
            <dt className="text-xs font-medium text-neutral-500">Additional context</dt>
            <dd className="text-sm text-neutral-900">
              {Object.entries(snapshot.context)
                .map(([key, value]) => `${key}: ${String(value)}`)
                .join(" · ")}
            </dd>
          </div>
        ) : null}
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Decision history</h2>
        <div className="mt-2">
          <DataTable caption="Approval decision history" columns={historyColumns} rows={history} rowKey={(row) => `${row.stepId}-${row.decisionId ?? "none"}`} emptyMessage="No decisions recorded yet." />
        </div>
      </section>

      {canDecide ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Your decision</h2>
          <form action={decideFormAction} className="mt-2 flex flex-col gap-2" noValidate>
            <FormField id="reason" label="Reason (required to reject)" error={decideState.error ?? undefined}>
              <Input id="reason" name="reason" type="text" invalid={Boolean(decideState.error)} aria-describedby={decideState.error ? "reason-error" : undefined} />
            </FormField>
            <input type="hidden" name="reauthConfirmedAt" value={reauthConfirmedAt} />
            <Checkbox
              checked={reauthConfirmed}
              onChange={(e) => {
                setReauthConfirmed(e.target.checked);
                setReauthConfirmedAt(e.target.checked ? new Date().toISOString() : "");
              }}
              label="I have recently re-authenticated (required for this decision)"
            />
            <div className="flex gap-2">
              <Button type="submit" name="decision" value="approved" disabled={decidePending || !reauthConfirmed}>
                {decidePending ? "Recording…" : "Approve"}
              </Button>
              <Button type="submit" name="decision" value="rejected" variant="destructive" disabled={decidePending || !reauthConfirmed}>
                {decidePending ? "Recording…" : "Reject"}
              </Button>
            </div>
          </form>
        </section>
      ) : (
        <p className="text-xs text-neutral-500">
          {stepStatus === "active" && requestStatus === "pending" ? "You are not currently an eligible approver for this step." : "This step is no longer awaiting a decision."}
        </p>
      )}
    </div>
  );
}
