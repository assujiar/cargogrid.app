import { Link } from "../../../../components/ui/link.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { CUSTOMER_PORTAL_INVOICE_STATUS_LABELS, type CustomerPortalInvoice, type CustomerPortalInvoiceStatus } from "../../../../server/contracts/customer-portal-invoice/customer-portal-invoice.ts";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";

const INVOICE_STATUS_TONE: Record<CustomerPortalInvoiceStatus, StatusTone> = {
  issued: "success",
  void: "neutral",
};

/**
 * Aging derived client-side from the invoice's own real due_date -- no
 * persisted aging column exists anywhere (FIN-210's own header: "aging
 * numbers themselves are never stored, only computed"), matching this
 * checkpoint's own "aging derived client-side... from finance_ar_open_
 * items.due_date"-equivalent latitude (the invoice's own due_date IS the
 * same due_date FIN-197's own app.issue_finance_invoice copies onto the AR
 * open item it posts, so deriving here from the invoice row alone is not a
 * second, independently-drifting source). Only meaningful for an issued
 * invoice with a real due_date -- a voided-before-ever-issued invoice has
 * neither.
 */
function agingLabel(invoice: CustomerPortalInvoice, nowIso: string): string {
  if (invoice.status !== "issued" || !invoice.dueDate) return "—";
  const due = new Date(invoice.dueDate).getTime();
  const now = new Date(nowIso).getTime();
  if (Number.isNaN(due) || Number.isNaN(now)) return "—";
  const daysOverdue = Math.floor((now - due) / 86_400_000);
  if (daysOverdue <= 0) return "Current";
  return `${daysOverdue}d overdue`;
}

function agingTone(invoice: CustomerPortalInvoice, nowIso: string): StatusTone {
  if (invoice.status !== "issued" || !invoice.dueDate) return "neutral";
  const due = new Date(invoice.dueDate).getTime();
  const now = new Date(nowIso).getTime();
  if (Number.isNaN(due) || Number.isNaN(now) || now <= due) return "success";
  return "danger";
}

function formatMoney(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(amount);
  } catch {
    return `${currency} ${amount.toFixed(2)}`;
  }
}

export function CustomerInvoicesPanel({
  tenantSlug,
  invoices,
  accounts,
  statusFilter,
  statuses,
  generatedAt,
}: {
  tenantSlug: string;
  invoices: readonly CustomerPortalInvoice[];
  /** ISS-2026-124: the reader's own accounts, so an invoice row can name the one it belongs to. */
  accounts: readonly CustomerPortalScopeContextRow[];
  statusFilter: string;
  statuses: readonly CustomerPortalInvoiceStatus[];
  generatedAt: string;
}) {
  const accountNameById = new Map(accounts.map((a) => [a.accountId, a.accountName]));
  // ISS-2026-124: a single-account customer already knows whose invoice it is, and a column
  // repeating one name on every row is noise. The cue is only shown to the readers who need it --
  // the same judgement CPL-310's own owner-account column makes.
  const showAccountColumn = accounts.length > 1;
  return (
    <div className="flex flex-col gap-4">
      {/* Freshness banner: every RPC below reads app.finance_invoices live, on
          every request -- there is no persisted cache to go "stale," mirroring
          every other customer-portal-nav route's own identical banner. */}
      <div role="status" className="rounded-md border border-info/30 bg-info/10 p-3 text-xs text-neutral-700">
        Live billing data as of {new Date(generatedAt).toLocaleString()}. Only issued invoices (and any later voided) are shown -- draft/in-review invoices are internal to Finance until issued.
      </div>

      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="status" className="text-xs font-medium text-neutral-600">
            Status
          </label>
          <Select id="status" name="status" defaultValue={statusFilter}>
            <option value="">Any status</option>
            {statuses.map((status) => (
              <option key={status} value={status}>
                {CUSTOMER_PORTAL_INVOICE_STATUS_LABELS[status]}
              </option>
            ))}
          </Select>
        </div>
        <button type="submit" className="rounded bg-primary px-3 py-1.5 text-sm font-medium text-neutral-50">
          Apply filter
        </button>
        <Link href={`/${tenantSlug}/customer-invoices`} className="text-xs text-neutral-500 underline">
          Clear filter
        </Link>
      </form>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Invoices</h2>
        {invoices.length === 0 ? (
          <EmptyState title="No invoices found" description={statusFilter ? "No invoice matches this filter right now." : "Invoices issued for your own accounts will appear here."} />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Invoice</th>
                  {showAccountColumn ? <th className="p-2">Account</th> : null}
                  <th className="p-2">Status</th>
                  <th className="p-2 text-right">Amount</th>
                  <th className="p-2">Due date</th>
                  <th className="p-2">Aging</th>
                  <th className="p-2">Updated</th>
                </tr>
              </thead>
              <tbody>
                {invoices.map((invoice) => (
                  <tr key={invoice.id} className="border-t border-neutral-100">
                    <td className="p-2 text-sm">
                      <Link href={`/${tenantSlug}/customer-invoices/${invoice.id}`}>{invoice.invoiceNumber ?? "Unnumbered"}</Link>
                    </td>
                    {showAccountColumn ? (
                      <td className="p-2 text-xs text-neutral-500">
                        {invoice.customerAccountId ? (accountNameById.get(invoice.customerAccountId) ?? "—") : "—"}
                      </td>
                    ) : null}
                    <td className="p-2 text-sm">
                      <StatusBadge tone={INVOICE_STATUS_TONE[invoice.status] ?? "neutral"} label={CUSTOMER_PORTAL_INVOICE_STATUS_LABELS[invoice.status] ?? invoice.status} />
                    </td>
                    <td className="p-2 text-right text-sm tabular-nums">{formatMoney(invoice.totalAmount, invoice.currency)}</td>
                    <td className="p-2 text-xs text-neutral-500">{invoice.dueDate ? new Date(invoice.dueDate).toLocaleDateString() : "—"}</td>
                    <td className="p-2 text-xs">
                      <StatusBadge tone={agingTone(invoice, generatedAt)} label={agingLabel(invoice, generatedAt)} />
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(invoice.updatedAt).toLocaleString()}</td>
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
