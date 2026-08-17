import { Link } from "../../../../components/ui/link.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS, type CustomerWarehouseOrder, type CustomerWarehouseOrderStatus } from "../../../../server/contracts/customer-portal-warehouse-order/customer-portal-warehouse-order.ts";
import type { CustomerPortalWarehouseEligibility } from "../../../../server/contracts/customer-portal-inventory/customer-portal-inventory.ts";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";

const ORDER_STATUS_TONE: Record<CustomerWarehouseOrderStatus, StatusTone> = {
  draft: "warning",
  confirmed: "success",
  cancelled: "danger",
};

/** `warehouse_id` carries no customer-facing name anywhere in this migration's own projection (mirrors CPL-309/ATW-023's identical opaque-id choice). Business rule 3 ("Location detail must not expose internal warehouse layout beyond approved customer-safe level") makes the raw opaque id the deliberately safe choice. */
function shortId(id: string): string {
  return id.slice(0, 8);
}

export function CustomerWarehouseOrdersPanel({
  tenantSlug,
  accounts,
  eligibility,
  orders,
  warehouseId,
  statusFilter,
  statuses,
  generatedAt,
}: {
  tenantSlug: string;
  accounts: readonly CustomerPortalScopeContextRow[];
  eligibility: readonly CustomerPortalWarehouseEligibility[];
  orders: readonly CustomerWarehouseOrder[];
  warehouseId: string;
  statusFilter: string;
  statuses: readonly CustomerWarehouseOrderStatus[];
  generatedAt: string;
}) {
  const accountNameById = new Map(accounts.map((a) => [a.accountId, a.accountName]));
  const distinctWarehouseIds = Array.from(new Set(eligibility.map((e) => e.warehouseId)));

  return (
    <div className="flex flex-col gap-4">
      {/* Freshness banner (source prompt §20 "source freshness indicators"): every
          RPC below reads app.wms_outbound_orders live, on every request -- there is
          no persisted cache to go "stale," so the honest freshness signal is the
          request's own timestamp, mirroring customer-inventory's own identical
          banner. */}
      <div role="status" className="rounded-md border border-info/30 bg-info/10 p-3 text-xs text-neutral-700">
        Live WMS data as of {new Date(generatedAt).toLocaleString()}. Every order shown is an outbound order -- WMS remains the source of truth for fulfillment.
      </div>

      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="warehouseId" className="text-xs font-medium text-neutral-600">
            Warehouse
          </label>
          <select id="warehouseId" name="warehouseId" defaultValue={warehouseId} className="rounded border border-neutral-300 px-2 py-1 text-sm">
            <option value="">All eligible warehouses</option>
            {distinctWarehouseIds.map((id) => (
              <option key={id} value={id}>
                WH-{shortId(id)}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="status" className="text-xs font-medium text-neutral-600">
            Status
          </label>
          <select id="status" name="status" defaultValue={statusFilter} className="rounded border border-neutral-300 px-2 py-1 text-sm">
            <option value="">Any status</option>
            {statuses.map((status) => (
              <option key={status} value={status}>
                {CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS[status]}
              </option>
            ))}
          </select>
        </div>
        <button type="submit" className="rounded bg-primary px-3 py-1.5 text-sm font-medium text-neutral-50">
          Apply filter
        </button>
        <Link href={`/${tenantSlug}/customer-warehouse-orders`} className="text-xs text-neutral-500 underline">
          Clear filter
        </Link>
      </form>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Orders</h2>
        {orders.length === 0 ? (
          <EmptyState
            title="No warehouse orders found"
            description={warehouseId || statusFilter ? "No order matches this filter right now." : "Outbound orders WMS is fulfilling for your own accounts will appear here."}
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
    </div>
  );
}
