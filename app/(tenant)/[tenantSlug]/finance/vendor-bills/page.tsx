import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceVendorBills, VendorBillQueryError } from "../../../../../server/queries/vendor-bill.ts";
import type { FinanceVendorBill } from "../../../../../server/contracts/vendor-bill/vendor-bill.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_VENDOR_BILL_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  prepareFinanceVendorBillFromActualCostAction,
  submitFinanceVendorBillForApprovalAction,
  discardFinanceVendorBillDraftAction,
  approveFinanceVendorBillAction,
  postFinanceVendorBillAction,
} from "./actions.ts";
import {
  PrepareFinanceVendorBillFromActualCostForm,
  SubmitFinanceVendorBillForApprovalForm,
  DiscardFinanceVendorBillDraftForm,
  ApproveFinanceVendorBillForm,
  PostFinanceVendorBillForm,
} from "./vendor-bill-forms.tsx";

/**
 * Vendor Bill workspace (FIN-200, CG-S9-FIN-011). A bounded (200-row) vendor
 * bill queue -- prepare-from-actual-cost form, per-row lifecycle actions
 * (submit/discard while draft, approve while submitted, post-to-AP while
 * approved) -- and read-only detail once posted. Basic-match variance
 * (vendor-stated amount vs. computed subtotal) discloses to the approver in
 * the status column but never itself blocks approval. No line-editing UI
 * (Prompt 200's own cost/tax lines are derived deterministically from the
 * verified, approved actual cost's own vendor-sourced components plus
 * FIN-195's own tax calculation; amending a prepared draft requires
 * discard-and-reprepare at this MVP checkpoint, disclosed in FIN-200.md).
 */
export default async function VendorBillsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let bills: FinanceVendorBill[] = [];
  let loadFailed = false;
  try {
    bills = await listFinanceVendorBills(supabase, { tenantId: access.tenant.id, companyId: null, vendorMasterId: null, status: null, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof VendorBillQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinanceVendorBill>[] = [
    { key: "number", header: "Bill #", render: (bill) => bill.billNumber ?? "(unposted)" },
    { key: "vendor", header: "Vendor", render: (bill) => bill.vendorMasterId },
    { key: "currency", header: "Currency", render: (bill) => bill.currency },
    { key: "subtotal", header: "Subtotal", render: (bill) => bill.subtotalAmount },
    { key: "tax", header: "Tax", render: (bill) => bill.taxAmount },
    { key: "total", header: "Total", render: (bill) => bill.totalAmount },
    { key: "variance", header: "Variance", render: (bill) => (bill.varianceStatus === "requires_approval" ? `Requires approval (${bill.varianceAmount})` : "Within tolerance") },
    { key: "dueDate", header: "Due date", render: (bill) => bill.dueDate },
    {
      key: "status",
      header: "Status",
      render: (bill) => {
        const { tone, label } = FINANCE_VENDOR_BILL_STATUS_TONE_MAP[bill.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (bill) => {
        if (bill.status === "draft") {
          return (
            <div className="flex flex-wrap gap-2">
              <SubmitFinanceVendorBillForApprovalForm action={submitFinanceVendorBillForApprovalAction.bind(null, tenantSlug, bill.id, bill.recordVersion)} />
              <DiscardFinanceVendorBillDraftForm action={discardFinanceVendorBillDraftAction.bind(null, tenantSlug, bill.id, bill.recordVersion)} />
            </div>
          );
        }
        if (bill.status === "submitted") {
          return (
            <div className="flex flex-wrap gap-2">
              <ApproveFinanceVendorBillForm action={approveFinanceVendorBillAction.bind(null, tenantSlug, bill.id, bill.recordVersion)} />
              <DiscardFinanceVendorBillDraftForm action={discardFinanceVendorBillDraftAction.bind(null, tenantSlug, bill.id, bill.recordVersion)} />
            </div>
          );
        }
        if (bill.status === "approved") {
          return <PostFinanceVendorBillForm action={postFinanceVendorBillAction.bind(null, tenantSlug, bill.id, bill.recordVersion)} />;
        }
        return "—";
      },
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Vendor Bills</h1>
        <p className="text-sm text-text-secondary">
          Versioned vendor bills prepared from verified, approved Operations actual-cost evidence. A normal role cannot edit a posted bill -- correction is
          a governed reversal, not a direct edit.
        </p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading vendor bills. Please try again." />
        ) : bills.length === 0 ? (
          <EmptyState title="No vendor bills yet" description="Prepare one from a verified, approved actual cost below." />
        ) : (
          <DataTable caption="Vendor bills" columns={columns} rows={bills} rowKey={(bill) => bill.id} emptyMessage="No vendor bills yet." />
        )}
      </div>

      <PrepareFinanceVendorBillFromActualCostForm action={prepareFinanceVendorBillFromActualCostAction.bind(null, tenantSlug)} />
    </div>
  );
}
