"use client";

import { useActionState, useId } from "react";
import Link from "next/link";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import { isVendorContractCostMasked, type VendorContract, type VendorContractEvent, type VendorContractStatus } from "../../../../../../server/contracts/vendor-contract/vendor-contract.ts";
import type { VendorContractActionState } from "../actions.ts";

const INITIAL_STATE: VendorContractActionState = { error: null };

const STATUS_TONE: Record<VendorContractStatus, StatusTone> = {
  draft: "neutral",
  pending_approval: "info",
  active: "success",
  rejected: "danger",
  suspended: "danger",
  terminated: "danger",
  superseded: "neutral",
  cancelled: "neutral",
};

type SimpleFormAction = (prevState: VendorContractActionState, formData: FormData) => Promise<VendorContractActionState>;

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

function ConstraintRow({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs font-medium text-neutral-500">{label}</dt>
      <dd className="text-sm text-neutral-900">{value ?? "—"}</dd>
    </div>
  );
}

export function VendorContractDetailPanel({
  contract,
  versions,
  history,
  updateAction,
  submitAction,
  signAction,
  activateAction,
  amendAction,
  renewAction,
  suspendAction,
  reactivateAction,
  terminateAction,
  cancelAction,
}: {
  contract: VendorContract;
  versions: readonly VendorContract[];
  history: readonly VendorContractEvent[];
  updateAction: SimpleFormAction;
  submitAction: SimpleFormAction;
  signAction: SimpleFormAction;
  activateAction: SimpleFormAction;
  amendAction: SimpleFormAction;
  renewAction: SimpleFormAction;
  suspendAction: SimpleFormAction;
  reactivateAction: SimpleFormAction;
  terminateAction: SimpleFormAction;
  cancelAction: SimpleFormAction;
}) {
  const masked = isVendorContractCostMasked(contract as unknown as Record<string, unknown>);
  const canUpdate = contract.status === "draft";
  const canSubmit = contract.status === "draft";
  const canSign = (contract.status === "draft" || contract.status === "pending_approval") && contract.signatureRequired && contract.signatureStatus !== "signed";
  const canActivate = contract.status === "pending_approval" && contract.approvalStatus !== "pending" && (!contract.signatureRequired || contract.signatureStatus === "signed");
  const canAmend = contract.status === "active";
  const canRenew = contract.status === "active";
  const canSuspend = contract.status === "active";
  const canReactivate = contract.status === "suspended";
  const canTerminate = contract.status === "active" || contract.status === "suspended";
  const canCancel = contract.status === "draft" || contract.status === "pending_approval";

  const versionColumns: readonly DataTableColumn<VendorContract>[] = [
    { key: "version", header: "Version", render: (row) => `v${row.versionNo} (${row.versionKind})` },
    { key: "status", header: "Status", render: (row) => <StatusBadge tone={STATUS_TONE[row.status]} label={row.status} /> },
    { key: "effective", header: "Effective", render: (row) => `${row.effectiveStart} → ${row.effectiveEnd ?? "open-ended"}` },
    { key: "link", header: "", render: (row) => (row.id === contract.id ? "(this version)" : <Link href={`../${row.id}`} className="text-primary hover:underline">view</Link>) },
  ];

  const historyColumns: readonly DataTableColumn<VendorContractEvent>[] = [
    { key: "from", header: "From", render: (row) => row.fromStatus },
    { key: "to", header: "To", render: (row) => row.toStatus },
    { key: "reason", header: "Reason", render: (row) => row.reason ?? "—" },
    { key: "actor", header: "Actor", render: (row) => row.actorLabel ?? "—" },
    { key: "occurredAt", header: "Occurred", render: (row) => new Date(row.occurredAt).toLocaleString() },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">
          {contract.contractNumber} <span className="text-sm font-normal text-neutral-500">v{contract.versionNo} ({contract.versionKind})</span>
        </h1>
        <div className="mt-1 flex flex-wrap gap-2">
          <StatusBadge tone={STATUS_TONE[contract.status]} label={contract.status} />
          <StatusBadge tone={contract.approvalStatus === "rejected" ? "danger" : contract.approvalStatus === "approved" ? "success" : "neutral"} label={`approval: ${contract.approvalStatus}`} />
          <StatusBadge tone={contract.signatureStatus === "signed" ? "success" : "neutral"} label={`signature: ${contract.signatureStatus}`} />
        </div>
        {contract.approvalStatus === "pending" && contract.approvalRequestId ? (
          <p className="mt-1 text-xs text-neutral-500">
            This contract is awaiting a governance decision --{" "}
            <span className="text-primary underline">see the Procurement Approvals inbox</span> to decide (or track) the pending step.
          </p>
        ) : null}
      </div>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Terms</h2>
        <dl className="mt-2 grid grid-cols-1 gap-3 text-sm sm:grid-cols-3">
          <ConstraintRow label="Vendor" value={contract.vendorMasterId} />
          <ConstraintRow label="Contract type" value={contract.contractType} />
          <ConstraintRow label="Effective" value={`${contract.effectiveStart} → ${contract.effectiveEnd ?? "open-ended"}`} />
          <ConstraintRow label="Payment terms (days)" value={masked ? "Masked (requires Procurement: View cost)" : (contract.paymentTermDays?.toString() ?? "—")} />
          <ConstraintRow label="Linked rate version" value={masked ? "Masked (requires Procurement: View cost)" : (contract.rateVersionId ?? "—")} />
          <ConstraintRow label="Tax terms" value={masked ? "Masked (requires Procurement: View cost)" : JSON.stringify(contract.taxTerms)} />
          <ConstraintRow label="SLA terms" value={JSON.stringify(contract.slaTerms)} />
          <ConstraintRow label="Capacity terms" value={masked ? "Masked (requires Procurement: View cost)" : JSON.stringify(contract.capacityTerms)} />
          <ConstraintRow label="Coverage terms" value={JSON.stringify(contract.coverageTerms)} />
          <ConstraintRow label="Required compliance" value={contract.complianceRequired.length > 0 ? contract.complianceRequired.join(", ") : "—"} />
          <ConstraintRow label="Signed by" value={contract.signedBy ? `${contract.signedBy} (${contract.signedAt ? new Date(contract.signedAt).toLocaleString() : "—"})` : "—"} />
          <ConstraintRow label="Amend reason" value={contract.amendReason} />
          <ConstraintRow label="Termination" value={contract.terminationReason ? `${contract.terminationReason} (${contract.terminationEvidenceRef})` : null} />
        </dl>
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Version lineage (same contract_number)</h2>
        <div className="mt-2">
          <DataTable caption="Vendor contract versions" columns={versionColumns} rows={versions} rowKey={(row) => row.id} emptyMessage="No other versions." />
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

        {canUpdate ? (
          <ActionForm action={updateAction} submitLabel="Save draft terms" loadingLabel="Saving…" variant="secondary">
            {(describedBy) => (
              <>
                <FormField id="update-effectiveStart" label="Effective start (required)">
                  <Input id="update-effectiveStart" name="effectiveStart" type="date" defaultValue={contract.effectiveStart} required aria-describedby={describedBy} />
                </FormField>
                <FormField id="update-effectiveEnd" label="Effective end">
                  <Input id="update-effectiveEnd" name="effectiveEnd" type="date" defaultValue={contract.effectiveEnd ?? undefined} aria-describedby={describedBy} />
                </FormField>
                <FormField id="update-paymentTermDays" label={`Payment term days ${masked ? "(masked -- leave blank to keep the current value)" : ""}`}>
                  <Input id="update-paymentTermDays" name="paymentTermDays" type="number" min={0} defaultValue={masked ? undefined : (contract.paymentTermDays ?? undefined)} aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        ) : null}

        {canSubmit ? <ActionForm action={submitAction} submitLabel="Submit for approval" loadingLabel="Submitting…" /> : null}

        {canSign ? (
          <ActionForm action={signAction} submitLabel="Record signature" loadingLabel="Recording…">
            {(describedBy) => (
              <FormField id="signedBy" label="Signatory name (required)">
                <Input id="signedBy" name="signedBy" type="text" required aria-describedby={describedBy} />
              </FormField>
            )}
          </ActionForm>
        ) : null}

        {canActivate ? <ActionForm action={activateAction} submitLabel="Activate" loadingLabel="Activating…" /> : null}

        {canAmend ? (
          <ActionForm action={amendAction} submitLabel="Amend (creates a new version)" loadingLabel="Amending…" variant="secondary">
            {(describedBy) => (
              <>
                <FormField id="amend-reason" label="Reason (required)">
                  <Input id="amend-reason" name="reason" type="text" required aria-describedby={describedBy} />
                </FormField>
                <FormField id="amend-effectiveEnd" label="New effective end">
                  <Input id="amend-effectiveEnd" name="effectiveEnd" type="date" aria-describedby={describedBy} />
                </FormField>
                <FormField id="amend-paymentTermDays" label="New payment term days">
                  <Input id="amend-paymentTermDays" name="paymentTermDays" type="number" min={0} aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        ) : null}

        {canRenew ? (
          <ActionForm action={renewAction} submitLabel="Renew (creates a new version, no coverage gap)" loadingLabel="Renewing…" variant="secondary">
            {(describedBy) => (
              <>
                <FormField id="renew-newEffectiveStart" label="New effective start (required)">
                  <Input id="renew-newEffectiveStart" name="newEffectiveStart" type="date" required aria-describedby={describedBy} />
                </FormField>
                <FormField id="renew-newEffectiveEnd" label="New effective end">
                  <Input id="renew-newEffectiveEnd" name="newEffectiveEnd" type="date" aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        ) : null}

        {canSuspend ? (
          <ActionForm action={suspendAction} submitLabel="Suspend" loadingLabel="Suspending…" variant="destructive">
            {(describedBy) => (
              <FormField id="suspend-reason" label="Reason (required)">
                <Input id="suspend-reason" name="reason" type="text" required aria-describedby={describedBy} />
              </FormField>
            )}
          </ActionForm>
        ) : null}

        {canReactivate ? <ActionForm action={reactivateAction} submitLabel="Reactivate" loadingLabel="Reactivating…" /> : null}

        {canTerminate ? (
          <ActionForm action={terminateAction} submitLabel="Terminate" loadingLabel="Terminating…" variant="destructive">
            {(describedBy) => (
              <>
                <FormField id="terminate-reason" label="Reason (required)">
                  <Input id="terminate-reason" name="reason" type="text" required aria-describedby={describedBy} />
                </FormField>
                <FormField id="terminate-evidenceRef" label="Evidence reference (required)">
                  <Input id="terminate-evidenceRef" name="evidenceRef" type="text" required aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        ) : null}

        {canCancel ? (
          <ActionForm action={cancelAction} submitLabel="Cancel" loadingLabel="Cancelling…" variant="destructive">
            {(describedBy) => (
              <FormField id="cancel-reason" label="Reason (required)">
                <Input id="cancel-reason" name="reason" type="text" required aria-describedby={describedBy} />
              </FormField>
            )}
          </ActionForm>
        ) : null}

        {!canSubmit && !canSign && !canActivate && !canAmend && !canRenew && !canSuspend && !canReactivate && !canTerminate && !canCancel ? (
          <p className="text-xs text-neutral-500">No action is currently available for this vendor contract in its {contract.status} state.</p>
        ) : null}
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Lifecycle history</h2>
        <div className="mt-2">
          <DataTable caption="Vendor contract lifecycle history" columns={historyColumns} rows={history} rowKey={(row) => row.id} emptyMessage="No lifecycle events recorded yet." />
        </div>
      </section>
    </div>
  );
}
