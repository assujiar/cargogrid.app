import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listShipmentOrders, ShipmentOrderQueryError, type ListShipmentOrdersResult } from "../../../../../server/queries/shipment-order.ts";
import type { ShipmentOrder } from "../../../../../server/contracts/shipment-order/shipment-order.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { Badge } from "../../../../../components/ui/badge.tsx";
import { SHIPMENT_ORDER_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";

/**
 * Shipment Order list (OPS-169, CG-S8-OPS-003). Tenant-wide -- no masked column
 * exists on this table (cost/selling data stays in Job Order's own revenue_snapshot/
 * credit_snapshot). A Shipment Order is created only from a confirmed Job Order's own
 * detail page (linking to `shipment-orders/create?jobOrderId=`), not from a
 * standalone creation form here.
 */
export default async function ShipmentOrdersPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { page: pageParam } = await searchParams;
  const page = Math.max(Number.parseInt(pageParam ?? "1", 10) || 1, 1);

  const supabase = await createSupabaseServerClient();

  let result: ListShipmentOrdersResult | null = null;
  let loadFailed = false;
  try {
    result = await listShipmentOrders(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof ShipmentOrderQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<ShipmentOrder>[] = [
    {
      key: "shipmentNumber",
      header: "Shipment number",
      render: (shipment) => (
        <a href={`/${tenantSlug}/operations/shipment-orders/${shipment.id}`} className="font-medium text-primary underline">
          {shipment.shipmentNumber}
        </a>
      ),
    },
    { key: "mode", header: "Mode", render: (shipment) => <Badge tone="neutral">{shipment.mode}</Badge> },
    { key: "route", header: "Route", render: (shipment) => `${shipment.origin} → ${shipment.destination}` },
    {
      key: "status",
      header: "Status",
      render: (shipment) => {
        const { tone, label } = SHIPMENT_ORDER_STATUS_TONE_MAP[shipment.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "created", header: "Created", render: (shipment) => new Date(shipment.createdAt).toLocaleDateString() },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-neutral-900">Shipment Orders</h1>
        <div className="flex items-center gap-4">
          <a href={`/${tenantSlug}/operations/dispatch`} className="text-sm font-medium text-primary underline">
            Dispatch queue
          </a>
          <a href={`/${tenantSlug}/operations/job-orders`} className="text-sm font-medium text-primary underline">
            Create from a confirmed Job Order
          </a>
        </div>
      </div>

      {loadFailed || !result ? (
        <ErrorState description="Something went wrong loading Shipment Orders. Please try again." />
      ) : (
        <div className="flex flex-col gap-4">
          <DataTable
            caption="Shipment Orders"
            columns={columns}
            rows={result.shipmentOrders}
            rowKey={(shipment) => shipment.id}
            emptyMessage={<>No Shipment Orders yet. Create one from a confirmed Job Order&apos;s detail page.</>}
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-neutral-500">
              Page {result.page} — {result.totalCount} total Shipment Order{result.totalCount === 1 ? "" : "s"}
            </p>
            <Pagination
              page={result.page}
              pageSize={result.pageSize}
              totalCount={result.totalCount}
              buildHref={(targetPage) => `/${tenantSlug}/operations/shipment-orders?page=${targetPage}`}
            />
          </div>
        </div>
      )}
    </div>
  );
}
