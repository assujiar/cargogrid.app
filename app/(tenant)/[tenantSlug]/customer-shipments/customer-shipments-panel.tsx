import Link from "next/link";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { ShipmentOrderStatus, CustomerShipmentOrder } from "../../../../server/contracts/customer-shipment-order/customer-shipment-order.ts";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";

const STATUS_TONE: Record<ShipmentOrderStatus, StatusTone> = {
  draft: "neutral",
  confirmed: "success",
  cancelled: "danger",
};

const STATUS_LABEL: Record<ShipmentOrderStatus, string> = {
  draft: "draft",
  confirmed: "confirmed",
  cancelled: "cancelled",
};

function ShipmentRow({ tenantSlug, shipment, accountName }: { tenantSlug: string; shipment: CustomerShipmentOrder; accountName: string }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <Link href={`/${tenantSlug}/customer-shipments/${shipment.id}`} className="text-primary underline">
          {shipment.shipmentNumber}
        </Link>
      </td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[shipment.status]} label={STATUS_LABEL[shipment.status]} />
      </td>
      <td className="p-2 text-xs text-neutral-500">{accountName}</td>
      <td className="p-2 text-xs text-neutral-500">
        {shipment.origin} → {shipment.destination}
      </td>
      <td className="p-2 text-xs text-neutral-500">{shipment.plannedPickupAt ? new Date(shipment.plannedPickupAt).toLocaleString() : "—"}</td>
      <td className="p-2 text-xs text-neutral-500">{new Date(shipment.updatedAt).toLocaleString()}</td>
    </tr>
  );
}

export function CustomerShipmentsPanel({
  tenantSlug,
  accounts,
  shipments,
}: {
  tenantSlug: string;
  accounts: readonly CustomerPortalScopeContextRow[];
  shipments: readonly CustomerShipmentOrder[];
}) {
  const accountNameById = new Map(accounts.map((a) => [a.accountId, a.accountName]));

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Your shipments</h2>
      {shipments.length === 0 ? (
        <EmptyState title="No shipments yet" description="Shipments confirmed by Operations from your bookings will appear here." />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <thead>
              <tr className="text-left text-xs font-medium text-neutral-500">
                <th className="p-2">Shipment</th>
                <th className="p-2">Status</th>
                <th className="p-2">Account</th>
                <th className="p-2">Route</th>
                <th className="p-2">Planned pickup</th>
                <th className="p-2">Updated</th>
              </tr>
            </thead>
            <tbody>
              {shipments.map((s) => (
                <ShipmentRow key={s.id} tenantSlug={tenantSlug} shipment={s} accountName={accountNameById.get(s.shipperAccountId) ?? "—"} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
