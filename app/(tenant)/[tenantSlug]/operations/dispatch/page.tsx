import { notFound } from "next/navigation";
import { randomUUID } from "node:crypto";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listDispatchReadyQueue, BasicDispatchQueryError, type ListDispatchReadyQueueResult } from "../../../../../server/queries/basic-dispatch.ts";
import type { DispatchReadyQueueRow } from "../../../../../server/contracts/basic-dispatch/basic-dispatch.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { Badge } from "../../../../../components/ui/badge.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { DispatchRowAction } from "./dispatch-row-action.tsx";
import { dispatchShipmentOrderFromQueueAction } from "./actions.ts";

/**
 * Basic Dispatch ready queue (OPS-175, CG-S8-OPS-009). Every `assigned` Shipment
 * Order the caller can access, is_ready/blockers precomputed by the same
 * `app.evaluate_dispatch_readiness` the commit-time recheck itself uses -- list/queue
 * only, not a dispatch board or route/load/capacity optimization.
 */
export default async function DispatchQueuePage({
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

  let result: ListDispatchReadyQueueResult | null = null;
  let loadFailed = false;
  try {
    result = await listDispatchReadyQueue(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof BasicDispatchQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<DispatchReadyQueueRow>[] = [
    {
      key: "shipmentNumber",
      header: "Shipment number",
      render: (row) => (
        <a href={`/${tenantSlug}/operations/shipment-orders/${row.id}`} className="font-medium text-primary underline">
          {row.shipmentNumber}
        </a>
      ),
    },
    { key: "mode", header: "Mode", render: (row) => <Badge tone="neutral">{row.mode}</Badge> },
    { key: "route", header: "Route", render: (row) => `${row.origin} → ${row.destination}` },
    { key: "plannedPickup", header: "Planned pickup", render: (row) => (row.plannedPickupAt ? new Date(row.plannedPickupAt).toLocaleString() : "—") },
    {
      key: "readiness",
      header: "Readiness",
      render: (row) => (row.isReady ? <StatusBadge tone="success" label="Ready" /> : <StatusBadge tone="warning" label="Not ready" />),
    },
    {
      key: "action",
      header: "Action",
      render: (row) => (
        <DispatchRowAction
          isReady={row.isReady}
          blockers={row.blockers}
          action={dispatchShipmentOrderFromQueueAction.bind(null, tenantSlug, row.id, row.recordVersion, randomUUID())}
        />
      ),
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-neutral-900">Dispatch queue</h1>
        <a href={`/${tenantSlug}/operations/shipment-orders`} className="text-sm font-medium text-primary underline">
          All Shipment Orders
        </a>
      </div>

      {loadFailed || !result ? (
        <ErrorState description="Something went wrong loading the dispatch queue. Please try again." />
      ) : (
        <div className="flex flex-col gap-4">
          <DataTable
            caption="Dispatch ready queue"
            columns={columns}
            rows={result.rows}
            rowKey={(row) => row.id}
            emptyMessage={<>No Shipment Orders are currently assigned and awaiting dispatch.</>}
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-neutral-500">
              Page {result.page} — {result.totalCount} assigned Shipment Order{result.totalCount === 1 ? "" : "s"}
            </p>
            <Pagination
              page={result.page}
              pageSize={result.pageSize}
              totalCount={result.totalCount}
              buildHref={(targetPage) => `/${tenantSlug}/operations/dispatch?page=${targetPage}`}
            />
          </div>
        </div>
      )}
    </div>
  );
}
