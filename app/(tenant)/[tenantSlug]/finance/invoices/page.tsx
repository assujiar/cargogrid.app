import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceInvoices, listBillableReadinessHandoffs, InvoiceQueryError } from "../../../../../server/queries/invoice.ts";
import type { FinanceInvoice, BillableReadinessHandoff } from "../../../../../server/contracts/invoice/invoice.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_INVOICE_STATUS_TONE_MAP, FINANCE_LIFECYCLE_CANONICAL_STATE_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { resolveFinanceLifecycleEditability } from "../../../../../server/contracts/lifecycle/lifecycle-editability-matrix.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  prepareFinanceInvoiceFromReadinessAction,
  submitFinanceInvoiceForApprovalAction,
  discardFinanceInvoiceDraftAction,
  approveFinanceInvoiceAction,
  issueFinanceInvoiceAction,
} from "./actions.ts";
import {
  PrepareFinanceInvoiceFromReadinessForm,
  SubmitFinanceInvoiceForApprovalForm,
  DiscardFinanceInvoiceDraftForm,
  ApproveFinanceInvoiceForm,
  IssueFinanceInvoiceForm,
} from "./invoice-forms.tsx";

/**
 * Customer Invoice workspace (FIN-197, CG-S9-FIN-008). A bounded (200-row)
 * invoice queue -- a billable-jobs worklist to prepare from, per-row
 * lifecycle actions (submit/discard while draft, approve while submitted,
 * issue-and-post-to-AR while approved) -- and read-only detail once issued.
 * No line-editing UI (Prompt 197's own charge/tax lines are derived
 * deterministically from the governed revenue snapshot plus FIN-195's own
 * tax calculation; amending a prepared draft requires discard-and-reprepare
 * at this MVP checkpoint, disclosed in FIN-197.md).
 *
 * CG-AUDIT-2026-09-02 B7 (worklist half -- "Invoicing is driven by a
 * hand-copied UUID... Finance has no billable-jobs worklist"): the worklist
 * table below (app.list_billable_readiness_handoffs) replaces the free-text
 * BillingReadinessHandoff-ID field this page used to require. The second
 * half of B7 (app.check_customer_credit/credit control) is untouched --
 * separate, larger, deliberately deferred work.
 */
export default async function InvoicesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let invoices: FinanceInvoice[] = [];
  let handoffs: BillableReadinessHandoff[] = [];
  let loadFailed = false;
  try {
    invoices = await listFinanceInvoices(supabase, { tenantId: access.tenant.id, companyId: null, customerAccountId: null, status: null, actorAuthUserId: access.authUserId });
    handoffs = await listBillableReadinessHandoffs(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof InvoiceQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinanceInvoice>[] = [
    { key: "number", header: "Invoice #", render: (invoice) => invoice.invoiceNumber ?? "(unissued)" },
    { key: "customer", header: "Customer account", render: (invoice) => invoice.customerAccountId },
    { key: "currency", header: "Currency", render: (invoice) => invoice.currency },
    { key: "subtotal", header: "Subtotal", render: (invoice) => invoice.subtotalAmount },
    { key: "tax", header: "Tax", render: (invoice) => invoice.taxAmount },
    { key: "withheld", header: "Withheld", render: (invoice) => (invoice.withholdingTaxAmount > 0 ? invoice.withholdingTaxAmount : "—") },
    { key: "total", header: "Total", render: (invoice) => invoice.totalAmount },
    { key: "dueDate", header: "Due date", render: (invoice) => invoice.dueDate ?? "—" },
    {
      key: "status",
      header: "Status",
      render: (invoice) => {
        const { tone, label } = FINANCE_INVOICE_STATUS_TONE_MAP[invoice.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "lifecycle",
      header: "Lifecycle",
      render: (invoice) => {
        const editability = resolveFinanceLifecycleEditability("invoice", invoice.status);
        const { tone, label } = FINANCE_LIFECYCLE_CANONICAL_STATE_TONE_MAP[editability.canonicalState];
        return (
          <div className="flex flex-col gap-1">
            <StatusBadge tone={tone} label={label} />
            {editability.lockedReason ? <span className="text-xs text-text-secondary">{editability.lockedReason.replaceAll("_", " ")}</span> : null}
          </div>
        );
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (invoice) => {
        if (invoice.status === "draft") {
          return (
            <div className="flex flex-wrap gap-2">
              <SubmitFinanceInvoiceForApprovalForm action={submitFinanceInvoiceForApprovalAction.bind(null, tenantSlug, invoice.id, invoice.recordVersion)} />
              <DiscardFinanceInvoiceDraftForm action={discardFinanceInvoiceDraftAction.bind(null, tenantSlug, invoice.id, invoice.recordVersion)} />
            </div>
          );
        }
        if (invoice.status === "submitted") {
          return (
            <div className="flex flex-wrap gap-2">
              <ApproveFinanceInvoiceForm action={approveFinanceInvoiceAction.bind(null, tenantSlug, invoice.id, invoice.recordVersion)} />
              <DiscardFinanceInvoiceDraftForm action={discardFinanceInvoiceDraftAction.bind(null, tenantSlug, invoice.id, invoice.recordVersion)} />
            </div>
          );
        }
        if (invoice.status === "approved") {
          return <IssueFinanceInvoiceForm action={issueFinanceInvoiceAction.bind(null, tenantSlug, invoice.id, invoice.recordVersion)} />;
        }
        return "—";
      },
    },
    {
      /* CG-AUDIT-2026-09-02 A7: the fourth printable document. No invoice
         detail page exists (only this list, unlike surat-jalan/POD/purchase-
         order's own precedents) -- printing directly from this list row is
         the narrowest fix that closes the finding without building a new UI
         page. */
      key: "print",
      header: "Print",
      render: (invoice) => (
        <a href={`/${tenantSlug}/finance/invoices/${invoice.id}/print`} target="_blank" rel="noopener noreferrer" className="text-sm font-medium text-primary underline">
          Print
        </a>
      ),
    },
  ];

  const handoffColumns: readonly DataTableColumn<BillableReadinessHandoff>[] = [
    { key: "jobNumber", header: "Job #", render: (handoff) => handoff.jobNumber },
    { key: "customer", header: "Customer", render: (handoff) => handoff.customerLegalName },
    { key: "amount", header: "Amount", render: (handoff) => (handoff.amountMasked ? "Masked" : handoff.amount !== null ? `${handoff.currency} ${handoff.amount}` : "—") },
    { key: "handedOffAt", header: "Ready since", render: (handoff) => handoff.handedOffAt },
    {
      key: "prepare",
      header: "Prepare invoice",
      render: (handoff) => <PrepareFinanceInvoiceFromReadinessForm action={prepareFinanceInvoiceFromReadinessAction.bind(null, tenantSlug, handoff.id)} />,
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Customer Invoices</h1>
        <p className="text-sm text-text-secondary">Versioned invoices prepared from verified Operations billing-readiness evidence. A normal role cannot edit a posted (issued) invoice -- correction is a governed reversal, not a direct edit.</p>
      </div>

      <section aria-labelledby="worklist-heading" className="rounded-md border border-neutral-200 p-4">
        <h2 id="worklist-heading" className="text-sm font-semibold text-text-primary">
          Billable jobs
        </h2>
        <p className="mt-1 text-xs text-text-secondary">Every BillingReadinessHandoff not yet consumed by an invoice. Requires FIN:Edit to prepare -- idempotent per handoff, inherits the exact governed revenue snapshot from Operations, never re-entered.</p>
        <div className="mt-2">
          {loadFailed ? (
            <ErrorState description="Something went wrong loading billable jobs. Please try again." />
          ) : (
            <DataTable caption="Billable jobs" columns={handoffColumns} rows={handoffs} rowKey={(handoff) => handoff.id} emptyMessage="No jobs are currently ready to invoice." />
          )}
        </div>
      </section>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading invoices. Please try again." />
        ) : invoices.length === 0 ? (
          <EmptyState title="No invoices yet" description="Prepare one from a billable job above." />
        ) : (
          <DataTable caption="Invoices" columns={columns} rows={invoices} rowKey={(invoice) => invoice.id} emptyMessage="No invoices yet." />
        )}
      </div>
    </div>
  );
}
