import { Link } from "../../../../components/ui/link.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import {
  CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS,
  CUSTOMER_INBOUND_ORDER_STATUS_LABELS,
  type CustomerInboundOrder,
  type CustomerInboundOrderStatus,
  type CustomerWarehouseOrder,
  type CustomerWarehouseOrderStatus,
} from "../../../../server/contracts/customer-portal-warehouse-order/customer-portal-warehouse-order.ts";
import type { CustomerPortalWarehouseEligibility } from "../../../../server/contracts/customer-portal-inventory/customer-portal-inventory.ts";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";

const ORDER_STATUS_TONE: Record<CustomerWarehouseOrderStatus, StatusTone> = {
  draft: "warning",
  confirmed: "success",
  cancelled: "danger",
};

/**
 * ISS-2026-120. `scheduled` is the one inbound state with no outbound
 * counterpart, and "info" is the honest tone for it: an appointment is booked
 * and nothing is waiting on the customer, which is neither a warning nor a
 * completed step.
 */
const INBOUND_STATUS_TONE: Record<CustomerInboundOrderStatus, StatusTone> = {
  draft: "warning",
  scheduled: "info",
  confirmed: "success",
  cancelled: "danger",
};

/** `warehouse_id` carries no customer-facing name anywhere in this migration's own projection (mirrors CPL-309/ATW-023's identical opaque-id choice). Business rule 3 ("Location detail must not expose internal warehouse layout beyond approved customer-safe level") makes the raw opaque id the deliberately safe choice. */
function shortId(id: string): string {
  return id.slice(0, 8);
}

/** An appointment is a window, not an instant -- rendering only its start would tell a reader to be there at a moment nobody agreed to. */
function formatWindow(start: string | null, end: string | null): string {
  if (!start) return "—";
  const startLabel = new Date(start).toLocaleString();
  if (!end) return startLabel;
  return `${startLabel} – ${new Date(end).toLocaleTimeString()}`;
}

export function CustomerWarehouseOrdersPanel({
  tenantSlug,
  accounts,
  eligibility,
  orders,
  inboundOrders,
  warehouseId,
  statusFilter,
  statuses,
  outboundStatuses,
  statusAppliesToOutbound,
  statusAppliesToInbound,
  generatedAt,
}: {
  tenantSlug: string;
  accounts: readonly CustomerPortalScopeContextRow[];
  eligibility: readonly CustomerPortalWarehouseEligibility[];
  orders: readonly CustomerWarehouseOrder[];
  inboundOrders: readonly CustomerInboundOrder[];
  warehouseId: string;
  statusFilter: string;
  /** The union vocabulary the filter offers -- inbound's four values, which are a superset of outbound's three. */
  statuses: readonly CustomerInboundOrderStatus[];
  /** Outbound's own three, used only to tell the reader which filter values that half can honour. */
  outboundStatuses: readonly CustomerWarehouseOrderStatus[];
  statusAppliesToOutbound: boolean;
  statusAppliesToInbound: boolean;
  generatedAt: string;
}) {
  const accountNameById = new Map(accounts.map((a) => [a.accountId, a.accountName]));
  const distinctWarehouseIds = Array.from(new Set(eligibility.map((e) => e.warehouseId)));
  const outboundOnlyStatuses = new Set<string>(outboundStatuses);

  return (
    <div className="flex flex-col gap-4">
      {/* Freshness banner (source prompt §20 "source freshness indicators"): every
          RPC below reads app.wms_outbound_orders/app.wms_inbound_orders live, on
          every request -- there is no persisted cache to go "stale," so the honest
          freshness signal is the request's own timestamp, mirroring
          customer-inventory's own identical banner. */}
      <div role="status" className="rounded-md border border-info/30 bg-info/10 p-3 text-xs text-neutral-700">
        Live WMS data as of {new Date(generatedAt).toLocaleString()}. WMS remains the source of truth for both fulfillment and receiving.
      </div>

      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="warehouseId" className="text-xs font-medium text-neutral-600">
            Warehouse
          </label>
          <Select id="warehouseId" name="warehouseId" defaultValue={warehouseId}>
            <option value="">All eligible warehouses</option>
            {distinctWarehouseIds.map((id) => (
              <option key={id} value={id}>
                WH-{shortId(id)}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="status" className="text-xs font-medium text-neutral-600">
            Status
          </label>
          <Select id="status" name="status" defaultValue={statusFilter}>
            <option value="">Any status</option>
            {statuses.map((status) => (
              <option key={status} value={status}>
                {CUSTOMER_INBOUND_ORDER_STATUS_LABELS[status]}
                {outboundOnlyStatuses.has(status) ? "" : " (inbound only)"}
              </option>
            ))}
          </Select>
        </div>
        <button type="submit" className="rounded bg-primary px-3 py-1.5 text-sm font-medium text-neutral-50">
          Apply filter
        </button>
        <Link href={`/${tenantSlug}/customer-warehouse-orders`} className="text-xs text-neutral-500 underline">
          Clear filter
        </Link>
      </form>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Outbound orders</h2>
        {!statusAppliesToOutbound ? (
          <EmptyState
            title="This status applies to inbound orders only"
            description="Outbound orders never reach an appointment-booked state, so none can match this filter. Clear the filter or pick a shared status to see them."
          />
        ) : orders.length === 0 ? (
          <EmptyState
            title="No outbound orders found"
            description={warehouseId || statusFilter ? "No outbound order matches this filter right now." : "Outbound orders WMS is fulfilling for your own accounts will appear here."}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Order</th>
                  <th className="p-2">Type</th>
                  <th className="p-2">Account</th>
                  <th className="p-2">Warehouse</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Requested ship date</th>
                  <th className="p-2">Updated</th>
                </tr>
              </thead>
              <tbody>
                {orders.map((order) => (
                  <tr key={order.id} className="border-t border-neutral-100">
                    <td className="p-2 text-sm">
                      <Link href={`/${tenantSlug}/customer-warehouse-orders/${order.id}`}>{order.outboundNumber}</Link>
                    </td>
                    <td className="p-2 text-xs text-neutral-500">Outbound</td>
                    <td className="p-2 text-xs text-neutral-500">{accountNameById.get(order.ownerAccountId) ?? "—"}</td>
                    <td className="p-2 font-mono text-xs text-neutral-500" title={order.warehouseId}>
                      WH-{shortId(order.warehouseId)}
                    </td>
                    <td className="p-2 text-sm">
                      <StatusBadge tone={ORDER_STATUS_TONE[order.status] ?? "neutral"} label={CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS[order.status] ?? order.status} />
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{order.requestedShipDate ? new Date(order.requestedShipDate).toLocaleDateString() : "—"}</td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(order.updatedAt).toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* ISS-2026-120: the inbound half. Kept a separate section rather than
          merged into one table -- the two carry genuinely different columns (a
          requested ship date versus a booked receiving window) and merging them
          would mean blanking half of each row, which reads as missing data
          rather than as a different kind of order. */}
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Inbound orders</h2>
        {!statusAppliesToInbound ? (
          <EmptyState title="This status applies to outbound orders only" description="No inbound order can match this filter. Clear the filter or pick a shared status to see them." />
        ) : inboundOrders.length === 0 ? (
          <EmptyState
            title="No inbound orders found"
            description={warehouseId || statusFilter ? "No inbound order matches this filter right now." : "Goods WMS is expecting to receive for your own accounts will appear here."}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Order</th>
                  <th className="p-2">Type</th>
                  <th className="p-2">Account</th>
                  <th className="p-2">Warehouse</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Expected / appointment</th>
                  <th className="p-2">Updated</th>
                </tr>
              </thead>
              <tbody>
                {inboundOrders.map((order) => (
                  <tr key={order.id} className="border-t border-neutral-100">
                    <td className="p-2 text-sm">
                      <Link href={`/${tenantSlug}/customer-warehouse-orders/inbound/${order.id}`}>{order.inboundNumber}</Link>
                    </td>
                    <td className="p-2 text-xs text-neutral-500">Inbound</td>
                    <td className="p-2 text-xs text-neutral-500">{accountNameById.get(order.ownerAccountId) ?? "—"}</td>
                    <td className="p-2 font-mono text-xs text-neutral-500" title={order.warehouseId}>
                      WH-{shortId(order.warehouseId)}
                    </td>
                    <td className="p-2 text-sm">
                      <StatusBadge tone={INBOUND_STATUS_TONE[order.status] ?? "neutral"} label={CUSTOMER_INBOUND_ORDER_STATUS_LABELS[order.status] ?? order.status} />
                    </td>
                    <td className="p-2 text-xs text-neutral-500">
                      {order.appointmentWindowStart ? formatWindow(order.appointmentWindowStart, order.appointmentWindowEnd) : order.expectedDate ? new Date(order.expectedDate).toLocaleDateString() : "—"}
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(order.updatedAt).toLocaleString()}</td>
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
