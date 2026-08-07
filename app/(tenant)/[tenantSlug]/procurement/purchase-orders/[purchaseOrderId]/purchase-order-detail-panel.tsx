"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import type { PurchaseOrder, PurchaseOrderLine, PurchaseOrderEvent, PurchaseOrderStatus } from "../../../../../../server/contracts/purchase-order/purchase-order.ts";
import type { ProcurementApprovalRequirement } from "../../../../../../server/contracts/procurement-approval/procurement-approval.ts";
import type { PurchaseOrderActionState } from "../actions.ts";

const INITIAL_STATE: PurchaseOrderActionState = { error: null };

const STATUS_TONE: Record<PurchaseOrderStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  issued: "success",
  acknowledged: "success",
  cancelled: "danger",
  superseded: "neutral",
};

type SimpleFormAction = (prevState: PurchaseOrderActionState, formData: FormData) => Promise<PurchaseOrderActionState>;

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

function ConstraintRow({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs font-medium text-neutral-500">{label}</dt>
      <dd className="text-sm text-neutral-900">{value ?? "—"}</dd>
    </div>
  );
}

function formatAmount(currency: string | null, amount: number | null, masked: boolean): string {
  if (masked) return "Masked (requires Procurement: View cost)";
  if (amount == null) return "—";
  return `${currency ?? ""} ${amount.toLocaleString()}`.trim();
}

export function PurchaseOrderDetailPanel({
  purchaseOrder,
  lines,
  history,
  approvalPreview,
  submitAction,
  issueAction,
  acknowledgeAction,
  recordFulfillmentAction,
  amendAction,
  cancelAction,
}: {
  purchaseOrder: PurchaseOrder;
  lines: readonly PurchaseOrderLine[];
  history: readonly PurchaseOrderEvent[];
  approvalPreview: ProcurementApprovalRequirement | null;
  submitAction: SimpleFormAction;
  issueAction: SimpleFormAction;
  acknowledgeAction: SimpleFormAction;
  recordFulfillmentAction: SimpleFormAction;
  amendAction: SimpleFormAction;
  cancelAction: SimpleFormAction;
}) {
  const canSubmit = purchaseOrder.status === "draft";
  const canIssue = purchaseOrder.status === "submitted";
  const canAcknowledge = purchaseOrder.status === "issued";
  const canRecordFulfillment = purchaseOrder.status === "issued" || purchaseOrder.status === "acknowledged";
  const canAmend = (purchaseOrder.status === "issued" || purchaseOrder.status === "acknowledged") && purchaseOrder.fulfillmentStatus === "not_started";
  const canCancel =
    purchaseOrder.status === "draft" ||
    purchaseOrder.status === "submitted" ||
    ((purchaseOrder.status === "issued" || purchaseOrder.status === "acknowledged") && purchaseOrder.fulfillmentStatus === "not_started");

  const lineColumns: readonly DataTableColumn<PurchaseOrderLine>[] = [
    { key: "lineNo", header: "#", render: (row) => `${row.lineNo}` },
    { key: "description", header: "Description", render: (row) => row.description },
    { key: "quantity", header: "Quantity", render: (row) => (row.quantity !== null ? row.quantity.toLocaleString() : "—") },
    { key: "uom", header: "UOM", render: (row) => row.uom ?? "—" },
  ];

  const historyColumns: readonly DataTableColumn<PurchaseOrderEvent>[] = [
    { key: "from", header: "From", render: (row) => row.fromStatus ?? "—" },
    { key: "to", header: "To", render: (row) => row.toStatus },
    { key: "reason", header: "Reason", render: (row) => (row.costMasked ? "Masked" : (row.reason ?? "—")) },
    { key: "actor", header: "Actor", render: (row) => row.actorLabel ?? "—" },
    { key: "occurredAt", header: "Occurred", render: (row) => new Date(row.occurredAt).toLocaleString() },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">
          {purchaseOrder.poNumber} <span className="text-sm font-normal text-neutral-500">v{purchaseOrder.version}</span>
        </h1>
        <div className="mt-1 flex flex-wrap gap-2">
          <StatusBadge tone={STATUS_TONE[purchaseOrder.status]} label={purchaseOrder.status} />
          <StatusBadge tone={purchaseOrder.approvalStatus === "rejected" ? "danger" : purchaseOrder.approvalStatus === "approved" ? "success" : "neutral"} label={`approval: ${purchaseOrder.approvalStatus}`} />
          <StatusBadge tone={purchaseOrder.fulfillmentStatus === "fulfilled" ? "success" : purchaseOrder.fulfillmentStatus === "partial" ? "info" : "neutral"} label={`fulfillment: ${purchaseOrder.fulfillmentStatus}`} />
        </div>
      </div>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Commitment</h2>
        <dl className="mt-2 grid grid-cols-1 gap-3 text-sm sm:grid-cols-3">
          <ConstraintRow label="Vendor comparison" value={purchaseOrder.comparisonId} />
          <ConstraintRow label="Selected offer" value={purchaseOrder.selectedOfferId} />
          <ConstraintRow label="Vendor" value={purchaseOrder.vendorMasterId} />
          <ConstraintRow label="Subtotal" value={formatAmount(purchaseOrder.currency, purchaseOrder.subtotalAmount, purchaseOrder.costMasked)} />
          <ConstraintRow label="Tax" value={purchaseOrder.costMasked ? "Masked" : `${purchaseOrder.taxCode ?? "none"} ${purchaseOrder.taxAmount ?? 0}`} />
          <ConstraintRow label="Total" value={formatAmount(purchaseOrder.currency, purchaseOrder.totalAmount, purchaseOrder.costMasked)} />
          <ConstraintRow label="Payment terms (days)" value={purchaseOrder.costMasked ? "Masked" : (purchaseOrder.paymentTermDays?.toString() ?? "—")} />
          <ConstraintRow label="Expected delivery" value={purchaseOrder.expectedDeliveryDate} />
          <ConstraintRow label="Service period" value={purchaseOrder.servicePeriodStart || purchaseOrder.servicePeriodEnd ? `${purchaseOrder.servicePeriodStart ?? "—"} → ${purchaseOrder.servicePeriodEnd ?? "—"}` : null} />
          <ConstraintRow label="Commercial terms" value={purchaseOrder.costMasked ? "Masked" : purchaseOrder.commercialTerms} />
          <ConstraintRow label="Notes" value={purchaseOrder.notes} />
          <ConstraintRow label="Fulfillment reference" value={purchaseOrder.fulfillmentReference} />
        </dl>
        {approvalPreview ? (
          <p className="mt-2 text-xs text-neutral-500">
            Submitting this PO for approval {approvalPreview.required ? "WILL" : "will NOT"} route for governance approval
            {approvalPreview.reasons.length > 0 ? ` (${approvalPreview.reasons.join(", ")})` : ""}. This is a preview only -- the real routing decision happens server-side at submit.
          </p>
        ) : null}
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Lines (inherited from source RFQ requirement, snapshotted at draft/amend time)</h2>
        <div className="mt-2">
          <DataTable caption="Purchase order lines" columns={lineColumns} rows={lines} rowKey={(row) => row.id} emptyMessage="No lines on this purchase order." />
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

        {canSubmit ? <ActionForm action={submitAction} submitLabel="Submit for approval" loadingLabel="Submitting…" /> : null}
        {canIssue ? <ActionForm action={issueAction} submitLabel="Issue" loadingLabel="Issuing…" /> : null}

        {canAcknowledge ? (
          <ActionForm action={acknowledgeAction} submitLabel="Record vendor acknowledgement" loadingLabel="Recording…">
            <label htmlFor="acknowledgementNote" className="text-xs font-medium text-neutral-700">
              Acknowledgement note (required)
            </label>
            <Input id="acknowledgementNote" name="acknowledgementNote" type="text" required />
          </ActionForm>
        ) : null}

        {canRecordFulfillment ? (
          <ActionForm action={recordFulfillmentAction} submitLabel="Record fulfillment status" loadingLabel="Recording…">
            <label htmlFor="fulfillmentStatus" className="text-xs font-medium text-neutral-700">
              New fulfillment status
            </label>
            <select id="fulfillmentStatus" name="fulfillmentStatus" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" defaultValue="partial">
              <option value="partial">partial</option>
              <option value="fulfilled">fulfilled</option>
            </select>
            <label htmlFor="fulfillmentReference" className="text-xs font-medium text-neutral-700">
              Fulfillment reference (canonical shipment/service evidence, required)
            </label>
            <Input id="fulfillmentReference" name="fulfillmentReference" type="text" required />
          </ActionForm>
        ) : null}

        {canAmend ? (
          <ActionForm action={amendAction} submitLabel="Amend (creates a new version)" loadingLabel="Amending…" variant="secondary">
            <label htmlFor="amend-reason" className="text-xs font-medium text-neutral-700">
              Reason (required)
            </label>
            <Input id="amend-reason" name="reason" type="text" required />
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label htmlFor="amend-paymentTermDays" className="text-xs font-medium text-neutral-700">
                  New payment term days
                </label>
                <Input id="amend-paymentTermDays" name="paymentTermDays" type="number" min={0} />
              </div>
              <div>
                <label htmlFor="amend-expectedDeliveryDate" className="text-xs font-medium text-neutral-700">
                  New expected delivery date
                </label>
                <Input id="amend-expectedDeliveryDate" name="expectedDeliveryDate" type="date" />
              </div>
            </div>
            <label htmlFor="amend-commercialTerms" className="text-xs font-medium text-neutral-700">
              New commercial terms
            </label>
            <Input id="amend-commercialTerms" name="commercialTerms" type="text" />
          </ActionForm>
        ) : null}

        {canCancel ? (
          <ActionForm action={cancelAction} submitLabel="Cancel" loadingLabel="Cancelling…" variant="destructive">
            <label htmlFor="cancel-reason" className="text-xs font-medium text-neutral-700">
              Reason (required)
            </label>
            <Input id="cancel-reason" name="reason" type="text" required />
          </ActionForm>
        ) : null}

        {!canSubmit && !canIssue && !canAcknowledge && !canRecordFulfillment && !canAmend && !canCancel ? (
          <p className="text-xs text-neutral-500">No action is currently available for this purchase order in its {purchaseOrder.status} state.</p>
        ) : null}
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Lifecycle history</h2>
        <div className="mt-2">
          <DataTable caption="Purchase order lifecycle history" columns={historyColumns} rows={history} rowKey={(row) => row.id} emptyMessage="No lifecycle events recorded yet." />
        </div>
      </section>
    </div>
  );
}
