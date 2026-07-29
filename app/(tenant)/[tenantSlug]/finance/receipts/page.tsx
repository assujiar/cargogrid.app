import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceReceipts, getFinanceReceiptAllocations, ReceiptAllocationQueryError } from "../../../../../server/queries/receipt-allocation.ts";
import type { FinanceReceipt, FinanceReceiptAllocation } from "../../../../../server/contracts/receipt-allocation/receipt-allocation.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_RECEIPT_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { captureFinanceReceiptAction, allocateFinanceReceiptAction, requestFinanceReceiptDeallocationAction } from "./actions.ts";
import { CaptureFinanceReceiptForm, AllocateFinanceReceiptForm, RequestFinanceReceiptDeallocationForm } from "./receipt-forms.tsx";

/**
 * Receipt and Payment Allocation workspace (FIN-198, CG-S9-FIN-009). A
 * bounded (200-row) receipt list with unapplied-cash visibility, a capture
 * form, a per-receipt JSON allocate form (bounded MVP UI, mirrors FIN-191's
 * own config-items JSON-editor precedent), and a per-receipt allocation
 * detail with a governed reversal action. Bank/payment fields are sensitive
 * -- this workspace is restricted to authorized Accounting staff at the
 * portal-guard layer (`FIN:View`/`FIN:Edit`/`FIN:Approve`); per-field
 * masking beyond role gating is FIN-214's own dedicated scope.
 */
export default async function ReceiptsPage({ params, searchParams }: { params: Promise<{ tenantSlug: string }>; searchParams: Promise<{ receiptId?: string }> }) {
  const { tenantSlug } = await params;
  const { receiptId } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let receipts: FinanceReceipt[] = [];
  let loadFailed = false;
  try {
    receipts = await listFinanceReceipts(supabase, { tenantId: access.tenant.id, companyId: null, customerAccountId: null, status: null, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof ReceiptAllocationQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  let selectedAllocations: FinanceReceiptAllocation[] = [];
  let selectedLoadFailed = false;
  if (receiptId) {
    try {
      selectedAllocations = await getFinanceReceiptAllocations(supabase, { receiptId, actorAuthUserId: access.authUserId });
    } catch (error) {
      if (!(error instanceof ReceiptAllocationQueryError)) {
        throw error;
      }
      selectedLoadFailed = true;
    }
  }

  const columns: readonly DataTableColumn<FinanceReceipt>[] = [
    { key: "reference", header: "Bank reference", render: (receipt) => receipt.receiptReference ?? "—" },
    { key: "customer", header: "Customer account", render: (receipt) => receipt.customerAccountId },
    { key: "date", header: "Date", render: (receipt) => receipt.receiptDate },
    { key: "amount", header: "Amount", render: (receipt) => `${receipt.amount} ${receipt.currency}` },
    { key: "allocated", header: "Allocated", render: (receipt) => receipt.allocatedAmount },
    { key: "unapplied", header: "Unapplied", render: (receipt) => receipt.unappliedAmount },
    {
      key: "status",
      header: "Status",
      render: (receipt) => {
        const { tone, label } = FINANCE_RECEIPT_STATUS_TONE_MAP[receipt.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (receipt) => (receipt.unappliedAmount > 0 ? <AllocateFinanceReceiptForm action={allocateFinanceReceiptAction.bind(null, tenantSlug, receipt.id)} /> : "—"),
    },
  ];

  const allocationColumns: readonly DataTableColumn<FinanceReceiptAllocation>[] = [
    { key: "openItem", header: "AR open item", render: (allocation) => allocation.arOpenItemId },
    { key: "amount", header: "Amount", render: (allocation) => allocation.amount },
    { key: "status", header: "Status", render: (allocation) => allocation.status },
    { key: "reason", header: "Reason", render: (allocation) => allocation.reason ?? "—" },
    {
      key: "actions",
      header: "Actions",
      render: (allocation) => (allocation.status === "applied" ? <RequestFinanceReceiptDeallocationForm action={requestFinanceReceiptDeallocationAction.bind(null, tenantSlug, allocation.id)} /> : "—"),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Receipt and Payment Allocation</h1>
        <p className="text-sm text-text-secondary">Customer receipt capture and exact allocation to AR open items. Deallocation is a governed reversal (FIN:Approve, mandatory reason) -- never a direct edit.</p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading receipts. Please try again." />
        ) : receipts.length === 0 ? (
          <EmptyState title="No receipts yet" description="Capture one below." />
        ) : (
          <DataTable caption="Receipts" columns={columns} rows={receipts} rowKey={(receipt) => receipt.id} emptyMessage="No receipts yet." />
        )}
      </div>

      <CaptureFinanceReceiptForm action={captureFinanceReceiptAction.bind(null, tenantSlug)} />

      <div>
        <h2 className="mb-2 text-sm font-semibold text-text-primary">Allocation detail</h2>
        <p className="mb-2 text-xs text-text-secondary">Append <code>?receiptId=…</code> to this page&apos;s URL to view one receipt&apos;s own allocation lineage and reverse an applied line.</p>
        {receiptId ? (
          selectedLoadFailed ? (
            <ErrorState description="Something went wrong loading this receipt's allocations. Please try again." />
          ) : selectedAllocations.length === 0 ? (
            <EmptyState title="No allocations yet" description="This receipt has not been allocated." />
          ) : (
            <DataTable caption="Allocations" columns={allocationColumns} rows={selectedAllocations} rowKey={(allocation) => allocation.id} emptyMessage="No allocations yet." />
          )
        ) : null}
      </div>
    </div>
  );
}
