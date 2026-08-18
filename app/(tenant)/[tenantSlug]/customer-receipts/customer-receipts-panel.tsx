import { Link } from "../../../../components/ui/link.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { CUSTOMER_PORTAL_RECEIPT_STATUS_LABELS, type CustomerPortalReceipt, type CustomerPortalReceiptStatus } from "../../../../server/contracts/customer-portal-payment/customer-portal-payment.ts";

const RECEIPT_STATUS_TONE: Record<CustomerPortalReceiptStatus, StatusTone> = {
  captured: "success",
  void: "neutral",
};

function formatMoney(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(amount);
  } catch {
    return `${currency} ${amount.toFixed(2)}`;
  }
}

export function CustomerReceiptsPanel({
  tenantSlug,
  receipts,
  statusFilter,
  statuses,
  generatedAt,
}: {
  tenantSlug: string;
  receipts: readonly CustomerPortalReceipt[];
  statusFilter: string;
  statuses: readonly CustomerPortalReceiptStatus[];
  generatedAt: string;
}) {
  return (
    <div className="flex flex-col gap-4">
      {/* Freshness banner: app.list_customer_portal_receipts reads app.
          finance_receipts live, on every request -- there is no persisted
          cache to go "stale," mirroring every other customer-portal-nav
          route's own identical banner. */}
      <div role="status" className="rounded-md border border-info/30 bg-info/10 p-3 text-xs text-neutral-700">
        Live payment data as of {new Date(generatedAt).toLocaleString()}.
      </div>

      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="status" className="text-xs font-medium text-neutral-600">
            Status
          </label>
          <select id="status" name="status" defaultValue={statusFilter} className="rounded border border-neutral-300 px-2 py-1 text-sm">
            <option value="">Any status</option>
            {statuses.map((status) => (
              <option key={status} value={status}>
                {CUSTOMER_PORTAL_RECEIPT_STATUS_LABELS[status]}
              </option>
            ))}
          </select>
        </div>
        <button type="submit" className="rounded bg-primary px-3 py-1.5 text-sm font-medium text-neutral-50">
          Apply filter
        </button>
        <Link href={`/${tenantSlug}/customer-receipts`} className="text-xs text-neutral-500 underline">
          Clear filter
        </Link>
      </form>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Receipts</h2>
        {receipts.length === 0 ? (
          <EmptyState title="No receipts found" description={statusFilter ? "No receipt matches this filter right now." : "Payments Finance records against your own accounts will appear here."} />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Receipt</th>
                  <th className="p-2">Status</th>
                  <th className="p-2 text-right">Amount</th>
                  <th className="p-2 text-right">Unapplied</th>
                  <th className="p-2">Date</th>
                  <th className="p-2">Updated</th>
                </tr>
              </thead>
              <tbody>
                {receipts.map((receipt) => (
                  <tr key={receipt.id} className="border-t border-neutral-100">
                    <td className="p-2 text-sm text-neutral-900">{receipt.receiptReference ?? "Unreferenced"}</td>
                    <td className="p-2 text-sm">
                      <StatusBadge tone={RECEIPT_STATUS_TONE[receipt.status] ?? "neutral"} label={CUSTOMER_PORTAL_RECEIPT_STATUS_LABELS[receipt.status] ?? receipt.status} />
                    </td>
                    <td className="p-2 text-right text-sm tabular-nums">{formatMoney(receipt.amount, receipt.currency)}</td>
                    <td className="p-2 text-right text-xs tabular-nums text-neutral-500">{receipt.unappliedAmount > 0 ? formatMoney(receipt.unappliedAmount, receipt.currency) : "—"}</td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(receipt.receiptDate).toLocaleDateString()}</td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(receipt.updatedAt).toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
