import { Link } from "../../../../../components/ui/link.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS,
  type CustomerWarehouseOrder,
  type CustomerWarehouseOrderLine,
  type CustomerWarehouseOrderStatus,
} from "../../../../../server/contracts/customer-portal-warehouse-order/customer-portal-warehouse-order.ts";

const ORDER_STATUS_TONE: Record<CustomerWarehouseOrderStatus, StatusTone> = {
  draft: "warning",
  confirmed: "success",
  cancelled: "danger",
};

/**
 * Fulfillment progress copy, derived entirely from the order's own real
 * status -- never a fabricated pick/pack percentage (migration design
 * decision 12: this capability's own RPCs never compose app.wms_pick_tasks/
 * app.wms_packages/app.wms_outbound_shipments, so there is no permitted data
 * source for a granular progress bar).
 */
const FULFILLMENT_PROGRESS_COPY: Record<CustomerWarehouseOrderStatus, string> = {
  draft: "Order captured -- not yet confirmed for warehouse fulfillment.",
  confirmed: "Confirmed -- ready for warehouse fulfillment. WMS owns picking, packing, and shipment execution from here.",
  cancelled: "This order was cancelled and will not be fulfilled.",
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

export function CustomerWarehouseOrderDetailPanel({
  tenantSlug,
  order,
  lines,
  generatedAt,
}: {
  tenantSlug: string;
  order: CustomerWarehouseOrder;
  lines: readonly CustomerWarehouseOrderLine[];
  generatedAt: string;
}) {
  const totalRequestedQuantity = lines.reduce((sum, line) => sum + line.requestedQuantity, 0);

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">{order.outboundNumber}</h1>
        <p className="text-xs text-neutral-500">
          Outbound order. This is a read-only projection of WMS-owned fulfillment data -- WMS remains the source of truth; you cannot confirm, cancel, or edit this order from here.
        </p>
      </div>

      {/* Freshness indicator (source prompt §20 "source freshness indicators"), the
          row's own real updated_at -- never a fabricated separate source-version
          field, mirroring customer-inventory/customer-warehouse-orders list's own
          identical banner convention. */}
      <div role="status" className="rounded-md border border-info/30 bg-info/10 p-3 text-xs text-neutral-700">
        Live WMS data as of {new Date(generatedAt).toLocaleString()}. Order last updated {formatAge(order.updatedAt, generatedAt)} ({new Date(order.updatedAt).toLocaleString()}).
      </div>

      <section className="grid grid-cols-2 gap-4 rounded-md border border-neutral-200 p-4 sm:grid-cols-3">
        <div>
          <p className="text-xs font-medium text-neutral-500">Type</p>
          <p className="text-sm text-neutral-900">Outbound</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Status</p>
          <StatusBadge tone={ORDER_STATUS_TONE[order.status] ?? "neutral"} label={CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS[order.status] ?? order.status} />
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Warehouse</p>
          <p className="font-mono text-sm text-neutral-900" title={order.warehouseId}>
            WH-{shortId(order.warehouseId)}
          </p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Requested ship date</p>
          <p className="text-sm text-neutral-900">{order.requestedShipDate ? new Date(order.requestedShipDate).toLocaleDateString() : "—"}</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Created</p>
          <p className="text-sm text-neutral-900">{new Date(order.createdAt).toLocaleDateString()}</p>
        </div>
        <div>
          <p className="text-xs font-medium text-neutral-500">Lines / total requested qty</p>
          <p className="text-sm text-neutral-900 tabular-nums">
            {lines.length} / {totalRequestedQuantity}
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
        <h2 className="text-sm font-semibold text-neutral-900">Fulfillment progress</h2>
        <p className="mt-1 text-sm text-text-secondary">{FULFILLMENT_PROGRESS_COPY[order.status] ?? "Status unavailable."}</p>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Order lines</h2>
        {lines.length === 0 ? (
          <EmptyState title="No lines yet" description="This order has no lines recorded yet." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Line</th>
                  <th className="p-2">Item</th>
                  <th className="p-2">UOM</th>
                  <th className="p-2 text-right">Requested qty</th>
                  <th className="p-2">Line status</th>
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
                    <td className="p-2 text-xs text-neutral-500">{line.requestedUomCode}</td>
                    <td className="p-2 text-right text-sm tabular-nums">{line.requestedQuantity}</td>
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

      {/* Exception/ticket-handoff action point (source prompt §20 "Add
          exception/ticket handoff"). CPL-313 (Ticketing/Support Integration)
          has not landed yet in this batch's own sequence -- points at the
          existing HRT-287 customer-ticket creation flow already shipped,
          mirroring the identical convention app/(tenant)/[tenantSlug]/
          customer-shipments/[shipmentOrderId]/customer-shipment-detail-
          panel.tsx already uses. */}
      <section className="rounded-md border border-neutral-200 bg-neutral-50 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Something wrong with this order?</h2>
        <p className="mt-1 text-sm text-text-secondary">
          If fulfillment looks incorrect, is delayed, or you need a change, <Link href={`/${tenantSlug}/customer-tickets`}>open a ticket</Link> -- your request is routed to Warehouse/Operations rather than
          edited here directly.
        </p>
      </section>
    </div>
  );
}
