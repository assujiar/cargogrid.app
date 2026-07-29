import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceInvoices, InvoiceQueryError } from "../../../../../server/queries/invoice.ts";
import type { FinanceInvoice } from "../../../../../server/contracts/invoice/invoice.ts";
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
 * invoice queue -- prepare-from-readiness form, per-row lifecycle actions
 * (submit/discard while draft, approve while submitted, issue-and-post-to-AR
 * while approved) -- and read-only detail once issued. No line-editing UI
 * (Prompt 197's own charge/tax lines are derived deterministically from the
 * governed revenue snapshot plus FIN-195's own tax calculation; amending a
 * prepared draft requires discard-and-reprepare at this MVP checkpoint,
 * disclosed in FIN-197.md).
 */
export default async function InvoicesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let invoices: FinanceInvoice[] = [];
  let loadFailed = false;
  try {
    invoices = await listFinanceInvoices(supabase, { tenantId: access.tenant.id, companyId: null, customerAccountId: null, status: null, actorAuthUserId: access.authUserId });
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
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Customer Invoices</h1>
        <p className="text-sm text-text-secondary">Versioned invoices prepared from verified Operations billing-readiness evidence. A normal role cannot edit a posted (issued) invoice -- correction is a governed reversal, not a direct edit.</p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading invoices. Please try again." />
        ) : invoices.length === 0 ? (
          <EmptyState title="No invoices yet" description="Prepare one from a verified BillingReadinessHandoff below." />
        ) : (
          <DataTable caption="Invoices" columns={columns} rows={invoices} rowKey={(invoice) => invoice.id} emptyMessage="No invoices yet." />
        )}
      </div>

      <PrepareFinanceInvoiceFromReadinessForm action={prepareFinanceInvoiceFromReadinessAction.bind(null, tenantSlug)} />
    </div>
  );
}
