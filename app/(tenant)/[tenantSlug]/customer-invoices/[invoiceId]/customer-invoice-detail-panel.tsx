"use client";

import { useState } from "react";
import { Link } from "../../../../../components/ui/link.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  CUSTOMER_PORTAL_INVOICE_STATUS_LABELS,
  CUSTOMER_PORTAL_INVOICE_PAYMENT_STATUS_LABELS,
  type CustomerPortalInvoice,
  type CustomerPortalInvoiceLine,
  type CustomerPortalInvoicePayment,
  type CustomerPortalInvoiceStatus,
  type CustomerPortalInvoicePaymentStatus,
} from "../../../../../server/contracts/customer-portal-invoice/customer-portal-invoice.ts";
import type { CustomerPortalPaymentStatus } from "../../../../../server/contracts/customer-portal-payment/customer-portal-payment.ts";
import { exportCustomerPortalInvoiceAction } from "./actions.ts";

const INVOICE_STATUS_TONE: Record<CustomerPortalInvoiceStatus, StatusTone> = {
  issued: "success",
  void: "neutral",
};

const PAYMENT_STATUS_TONE: Record<CustomerPortalInvoicePaymentStatus, StatusTone> = {
  open: "warning",
  partial: "warning",
  paid: "success",
  not_posted: "neutral",
};

function formatMoney(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(amount);
  } catch {
    return `${currency} ${amount.toFixed(2)}`;
  }
}

/** See app/(tenant)/[tenantSlug]/customer-invoices/customer-invoices-panel.tsx's own identical agingLabel for the "derived, never stored" rationale. */
function agingLabel(invoice: CustomerPortalInvoice): string {
  if (invoice.status !== "issued" || !invoice.dueDate) return "—";
  const due = new Date(invoice.dueDate).getTime();
  const now = Date.now();
  if (Number.isNaN(due)) return "—";
  const daysOverdue = Math.floor((now - due) / 86_400_000);
  return daysOverdue <= 0 ? "Current" : `${daysOverdue} day${daysOverdue === 1 ? "" : "s"} overdue`;
}

function CustomerInvoiceDownloadButton({ tenantSlug, invoiceId }: { tenantSlug: string; invoiceId: string }) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleDownload() {
    setPending(true);
    setError(null);
    try {
      const result = await exportCustomerPortalInvoiceAction(tenantSlug, invoiceId);
      if (!result.ok || !result.json || !result.filename) {
        setError(result.error ?? "Could not prepare this export.");
        return;
      }
      const blob = new Blob([result.json], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = result.filename;
      link.click();
      URL.revokeObjectURL(url);
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="flex flex-col gap-1">
      <Button type="button" variant="secondary" onClick={handleDownload} loading={pending} loadingLabel="Preparing…">
        Download invoice data (JSON)
      </Button>
      <p className="text-xs text-neutral-500">A structured export of this invoice, its lines, and its current payment status.</p>
      {error ? (
        <p role="alert" className="text-xs text-danger">
          {error}
        </p>
      ) : null}
    </div>
  );
}

export function CustomerInvoiceDetailPanel({
  tenantSlug,
  invoice,
  accountName,
  lines,
  payment,
  paymentDetail,
}: {
  tenantSlug: string;
  invoice: CustomerPortalInvoice;
  /** ISS-2026-124: the owning account's name, or null when there is only one account to be. */
  accountName: string | null;
  lines: readonly CustomerPortalInvoiceLine[];
  payment: CustomerPortalInvoicePayment;
  paymentDetail: CustomerPortalPaymentStatus;
}) {
  const disputeHref = `/${tenantSlug}/customer-tickets?disputeInvoiceId=${encodeURIComponent(invoice.id)}&disputeInvoiceNumber=${encodeURIComponent(invoice.invoiceNumber ?? invoice.id)}`;

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">{invoice.invoiceNumber ?? "Unnumbered invoice"}</h1>
        {/*
          ISS-2026-124: named right under the invoice number rather than buried in the field grid.
          A customer holding several accounts opening a disputed invoice needs to know whose it is
          before reading anything else on the page. Shown only when there is more than one account
          to distinguish -- otherwise it restates what the reader already knows.
        */}
        {accountName ? <p className="text-sm text-neutral-700">{accountName}</p> : null}
        <p className="text-xs text-neutral-500">
          This is a read-only projection of Finance-owned billing data -- Finance remains the source of truth; you cannot edit, approve, or post this invoice from here.
        </p>
      </div>

      <section className="grid grid-cols-2 gap-4 rounded-md border border-neutral-200 p-4 sm:grid-cols-3">
        <div>
          <p className="text-xs font-medium text-neutral-500">Status</p>
          <StatusBadge tone={INVOICE_STATUS_TONE[invoice.status] ?? "neutral"} label={CUSTOMER_PORTAL_INVOICE_STATUS_LABELS[invoice.status] ?? invoice.status} />
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Payment status</p>
          <StatusBadge tone={PAYMENT_STATUS_TONE[payment.paymentStatus] ?? "neutral"} label={CUSTOMER_PORTAL_INVOICE_PAYMENT_STATUS_LABELS[payment.paymentStatus] ?? payment.paymentStatus} />
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Aging</p>
          <p className="text-sm text-neutral-900">{agingLabel(invoice)}</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Total amount</p>
          <p className="text-sm text-neutral-900 tabular-nums">{formatMoney(invoice.totalAmount, invoice.currency)}</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Balance outstanding</p>
          <p className="text-sm text-neutral-900 tabular-nums">{payment.openAmount === null ? "—" : formatMoney(payment.openAmount, invoice.currency)}</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Issue date</p>
          <p className="text-sm text-neutral-900">{invoice.issueDate ? new Date(invoice.issueDate).toLocaleDateString() : "—"}</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Due date</p>
          <p className="text-sm text-neutral-900">{invoice.dueDate ? new Date(invoice.dueDate).toLocaleDateString() : "—"}</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Currency</p>
          <p className="text-sm text-neutral-900">{invoice.currency}</p>
        </div>
        {payment.isHeld ? (
          <div className="col-span-2 sm:col-span-3">
            <StatusBadge tone="warning" label="Payment on hold" />
            <p className="mt-1 text-xs text-neutral-500">Finance has placed a hold on this balance -- open a dispute below if you have questions.</p>
          </div>
        ) : null}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Charges &amp; tax lines</h2>
        {lines.length === 0 ? (
          <EmptyState title="No lines yet" description="This invoice has no lines recorded yet." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Line</th>
                  <th className="p-2">Type</th>
                  <th className="p-2">Description</th>
                  <th className="p-2 text-right">Amount</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line) => (
                  <tr key={line.lineNumber} className="border-t border-neutral-100">
                    <td className="p-2 text-sm tabular-nums">{line.lineNumber}</td>
                    <td className="p-2 text-xs text-neutral-500">{line.lineType === "tax" ? "Tax" : "Charge"}</td>
                    <td className="p-2 text-sm text-neutral-900">{line.description}</td>
                    <td className="p-2 text-right text-sm tabular-nums">{formatMoney(line.amount, invoice.currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* Payments & receipts (CPL-312, CG-S13-CPL-014, Prompt 312, §21 main
          flow: "customer finance user opens an invoice and sees payment
          allocation and receipt status"). Sourced from app.get_customer_
          portal_payment_status, a DIFFERENT RPC than the "Payment status"
          summary card above (CPL-311's own app.get_customer_portal_invoice_
          payment_status) -- this section adds the applied-receipt-allocation
          detail that RPC deliberately never returns (it never exposes
          ar_open_item_id, the internal linkage this migration's own RPC
          uses only server-side to reach app.finance_receipt_allocations).
          Never bank_account_label/payer_name -- neither RPC ever returns
          either field (migration design decisions 5/6). */}
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Payments &amp; receipts</h2>
        {paymentDetail.paymentStatus === "not_posted" ? (
          <p className="text-sm text-text-secondary">This invoice was voided before it was ever posted for payment -- no receipts apply.</p>
        ) : paymentDetail.allocations.length === 0 ? (
          <EmptyState
            title="No receipts applied yet"
            description={paymentDetail.isHeld ? "This balance is currently on hold -- see the status above." : "Receipts applied to this invoice's balance will appear here as Finance records them."}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Receipt</th>
                  <th className="p-2">Date</th>
                  <th className="p-2 text-right">Applied amount</th>
                </tr>
              </thead>
              <tbody>
                {paymentDetail.allocations.map((allocation, index) => (
                  <tr key={`${allocation.receiptReference ?? "unreferenced"}-${index}`} className="border-t border-neutral-100">
                    <td className="p-2 text-sm text-neutral-900">{allocation.receiptReference ?? "Unreferenced receipt"}</td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(allocation.receiptDate).toLocaleDateString()}</td>
                    <td className="p-2 text-right text-sm tabular-nums">{formatMoney(allocation.amount, allocation.currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="text-xs text-neutral-500">
          This is a read-only projection of Finance-owned receipt/allocation data -- see <Link href={`/${tenantSlug}/customer-receipts`}>your full receipts list</Link> for every receipt across your accounts.
        </p>
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Download</h2>
        <CustomerInvoiceDownloadButton tenantSlug={tenantSlug} invoiceId={invoice.id} />
      </section>

      {/* Dispute action (source prompt §20 "dispute/ticket action"). Per this
          prompt's own business rule ("Portal dispute is a workflow/ticket, not
          direct invoice edit") -- a real, working link into the ALREADY-
          VERIFIED HRT-287 customer-ticket creation flow, pre-filled with this
          invoice's own id/number, which auto-links the resulting ticket to
          this invoice via the ALREADY-VERIFIED HRT-292 app.ticket_links
          mechanism (migration design decision 13). */}
      <section className="rounded-md border border-neutral-200 bg-neutral-50 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Questions about this invoice?</h2>
        <p className="mt-1 text-sm text-text-secondary">
          If a charge looks wrong or you need clarification, <Link href={disputeHref}>open a dispute ticket</Link> -- your question is routed to Finance and linked to this invoice, rather than edited here
          directly.
        </p>
      </section>
    </div>
  );
}
