import { Link } from "../../../../../../components/ui/link.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import {
  CUSTOMER_INBOUND_ORDER_STATUS_LABELS,
  type CustomerInboundOrder,
  type CustomerInboundOrderLine,
  type CustomerInboundOrderStatus,
} from "../../../../../../server/contracts/customer-portal-warehouse-order/customer-portal-warehouse-order.ts";

const INBOUND_STATUS_TONE: Record<CustomerInboundOrderStatus, StatusTone> = {
  draft: "warning",
  scheduled: "info",
  confirmed: "success",
  cancelled: "danger",
};

/**
 * Receiving progress copy, derived entirely from the order's own real status --
 * never a fabricated received-quantity or unloading percentage. The inbound
 * RPCs never compose any receiving/putaway task table, so there is no permitted
 * data source for one, exactly as the outbound panel has none for pick/pack.
 */
const RECEIVING_PROGRESS_COPY: Record<CustomerInboundOrderStatus, string> = {
  draft: "Inbound captured -- no receiving appointment booked yet.",
  scheduled: "Appointment booked. Bring the goods within the window below; the warehouse confirms the inbound once it has been accepted.",
  confirmed: "Confirmed -- the warehouse has accepted this inbound. WMS owns receiving and putaway from here.",
  cancelled: "This inbound was cancelled and will not be received.",
};

function shortId(id: string): string {
  return id.slice(0, 8);
}

function formatAge(updatedAt: string, nowIso: string): string {
  const updated = new Date(updatedAt).getTime();
  const now = new Date(nowIso).getTime();
  if (Number.isNaN(updated) || Number.isNaN(now)) return "—";
  const diffMs = Math.max(0, now - updated);
  const minutes = Math.floor(diffMs / 60_000);
  if (minutes < 1) return "Just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  return `${months}mo ago`;
}

export function CustomerInboundOrderDetailPanel({
  tenantSlug,
  order,
  lines,
  generatedAt,
}: {
  tenantSlug: string;
  order: CustomerInboundOrder;
  lines: readonly CustomerInboundOrderLine[];
  generatedAt: string;
}) {
  const totalExpectedQuantity = lines.reduce((sum, line) => sum + line.expectedQuantity, 0);

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">{order.inboundNumber}</h1>
        <p className="text-xs text-neutral-500">
          Inbound order. This is a read-only projection of WMS-owned receiving data -- WMS remains the source of truth; you cannot confirm, cancel, reschedule, or edit this order from here.
        </p>
      </div>

      <div role="status" className="rounded-md border border-info/30 bg-info/10 p-3 text-xs text-neutral-700">
        Live WMS data as of {new Date(generatedAt).toLocaleString()}. Order last updated {formatAge(order.updatedAt, generatedAt)} ({new Date(order.updatedAt).toLocaleString()}).
      </div>

      <section className="grid grid-cols-2 gap-4 rounded-md border border-neutral-200 p-4 sm:grid-cols-3">
        <div>
          <p className="text-xs font-medium text-neutral-500">Type</p>
          <p className="text-sm text-neutral-900">Inbound</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Status</p>
          <StatusBadge tone={INBOUND_STATUS_TONE[order.status] ?? "neutral"} label={CUSTOMER_INBOUND_ORDER_STATUS_LABELS[order.status] ?? order.status} />
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Warehouse</p>
          <p className="font-mono text-sm text-neutral-900" title={order.warehouseId}>
            WH-{shortId(order.warehouseId)}
          </p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Expected date</p>
          <p className="text-sm text-neutral-900">{order.expectedDate ? new Date(order.expectedDate).toLocaleDateString() : "Not scheduled yet"}</p>
        </div>
        {/* Rendered as a window, never as its start alone -- a single instant
            would tell the reader to arrive at a time nobody agreed to. */}
        <div>
          <p className="text-xs font-medium text-neutral-500">Appointment window</p>
          <p className="text-sm text-neutral-900">
            {order.appointmentWindowStart && order.appointmentWindowEnd
              ? `${new Date(order.appointmentWindowStart).toLocaleString()} – ${new Date(order.appointmentWindowEnd).toLocaleTimeString()}`
              : "Not booked yet"}
          </p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Lines / total expected qty</p>
          <p className="text-sm text-neutral-900 tabular-nums">
            {lines.length} / {totalExpectedQuantity}
          </p>
        </div>
        {order.status === "cancelled" && order.cancelledReason ? (
          <div className="col-span-2 sm:col-span-3">
            <p className="text-xs font-medium text-neutral-500">Cancellation reason</p>
            <p className="text-sm text-neutral-900">{order.cancelledReason}</p>
          </div>
        ) : null}
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Receiving progress</h2>
        <p className="mt-1 text-sm text-text-secondary">{RECEIVING_PROGRESS_COPY[order.status] ?? "Status unavailable."}</p>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Order lines</h2>
        {lines.length === 0 ? (
          <EmptyState title="No lines yet" description="This inbound order has no lines recorded yet." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Line</th>
                  <th className="p-2">Item</th>
                  <th className="p-2">UOM</th>
                  <th className="p-2 text-right">Expected qty</th>
                  <th className="p-2">Line controls</th>
                  <th className="p-2">Updated</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line) => (
                  <tr key={line.id} className="border-t border-neutral-100">
                    <td className="p-2 text-sm tabular-nums">{line.lineNumber}</td>
                    <td className="p-2 font-mono text-xs text-neutral-900" title={line.itemMasterId}>
                      {shortId(line.itemMasterId)}
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{line.expectedUomCode}</td>
                    <td className="p-2 text-right text-sm tabular-nums">{line.expectedQuantity}</td>
                    <td className="p-2 text-xs text-neutral-500">
                      {[line.lotControlled ? "Lot" : null, line.serialControlled ? "Serial" : null, line.expiryControlled ? "Expiry" : null].filter(Boolean).join(", ") || "—"}
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{formatAge(line.updatedAt, generatedAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="rounded-md border border-neutral-200 bg-neutral-50 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Something wrong with this inbound?</h2>
        <p className="mt-1 text-sm text-text-secondary">
          If the appointment, quantities or items look incorrect, <Link href={`/${tenantSlug}/customer-tickets`}>open a ticket</Link> -- your request is routed to Warehouse/Operations rather than edited here
          directly.
        </p>
      </section>
    </div>
  );
}
