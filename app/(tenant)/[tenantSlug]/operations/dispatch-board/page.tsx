import { notFound } from "next/navigation";
import { randomUUID } from "node:crypto";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listDispatchBoard, DispatchBoardQueryError, type ListDispatchBoardResult } from "../../../../../server/queries/dispatch-board.ts";
import type { DispatchBoardRow } from "../../../../../server/contracts/dispatch-board/dispatch-board.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { Badge } from "../../../../../components/ui/badge.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { DispatchBoardRowAction } from "./dispatch-board-row-action.tsx";
import { dispatchShipmentOrderFromBoardAction } from "./actions.ts";

const STATUS_TONE: Record<DispatchBoardRow["status"], StatusTone> = {
  draft: "neutral",
  confirmed: "neutral",
  planned: "neutral",
  assigned: "info",
  dispatched: "info",
  in_transit: "warning",
  delivered: "success",
  epod: "success",
  closed: "success",
  held: "danger",
  cancelled: "danger",
};

const TRACKING_STATUS_TONE: Record<DispatchBoardRow["trackingStatus"], StatusTone> = {
  not_tracked: "neutral",
  tracked: "success",
  stale: "warning",
  degraded: "warning",
  conflict: "danger",
};

/**
 * Advanced Dispatch Board (ATW-222, CG-S10-ATW-003). A wider operational window
 * (assigned/dispatched/in_transit) than OPS-175's own assigned-only ready queue, with
 * a canonical tracking-health projection layered on top -- a projection, never a
 * tracking source. Tracking columns are honest and feature-gated (not_tracked/
 * unknown/false) until ATW-226 ships a real telemetry source. List view only in this
 * checkpoint -- an interactive map view is deferred (no map library exists in this
 * repository yet), matching the same disclosed boundary ATW-221's own leg/stop
 * timeline already established.
 */
export default async function DispatchBoardPage({
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

  let result: ListDispatchBoardResult | null = null;
  let loadFailed = false;
  try {
    result = await listDispatchBoard(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof DispatchBoardQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<DispatchBoardRow>[] = [
    {
      key: "shipmentNumber",
      header: "Shipment number",
      render: (row) => (
        <a href={`/${tenantSlug}/operations/shipment-orders/${row.id}`} className="font-medium text-primary underline">
          {row.shipmentNumber}
        </a>
      ),
    },
    { key: "status", header: "Status", render: (row) => <StatusBadge tone={STATUS_TONE[row.status]} label={row.status} /> },
    { key: "mode", header: "Mode", render: (row) => <Badge tone="neutral">{row.mode}</Badge> },
    { key: "route", header: "Route", render: (row) => `${row.origin} → ${row.destination}` },
    { key: "plannedPickup", header: "Planned pickup", render: (row) => (row.plannedPickupAt ? new Date(row.plannedPickupAt).toLocaleString() : "—") },
    { key: "assignment", header: "Resource", render: (row) => (row.hasActiveAssignment ? <StatusBadge tone="success" label="Assigned" /> : <StatusBadge tone="warning" label="Unassigned" />) },
    {
      key: "tracking",
      header: "Tracking health",
      render: (row) => (
        <div className="flex flex-col gap-0.5">
          <StatusBadge tone={TRACKING_STATUS_TONE[row.trackingStatus]} label={row.trackingStatus.replace("_", " ")} />
          {!row.trackingEntitled ? <span className="text-xs text-neutral-500">Not entitled</span> : null}
          {row.fallbackActive ? <span className="text-xs text-warning">Fallback active</span> : null}
        </div>
      ),
    },
    {
      key: "action",
      header: "Action",
      render: (row) => (
        <DispatchBoardRowAction
          isReady={row.isReady}
          blockers={row.blockers}
          action={dispatchShipmentOrderFromBoardAction.bind(null, tenantSlug, row.id, row.recordVersion, randomUUID())}
        />
      ),
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-neutral-900">Dispatch board</h1>
        <a href={`/${tenantSlug}/operations/dispatch`} className="text-sm font-medium text-primary underline">
          Ready queue only
        </a>
      </div>
      <p className="text-xs text-neutral-500">
        Assigned, dispatched, and in-transit movements. Tracking health reflects the canonical projection only -- no raw device or provider data is ever shown here. Map view is not yet
        available.
      </p>

      {loadFailed || !result ? (
        <ErrorState description="Something went wrong loading the dispatch board. Please try again." />
      ) : (
        <div className="flex flex-col gap-4">
          <DataTable
            caption="Advanced dispatch board"
            columns={columns}
            rows={result.rows}
            rowKey={(row) => row.id}
            emptyMessage={<>No Shipment Orders are currently assigned, dispatched, or in transit.</>}
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-neutral-500">
              Page {result.page} — {result.totalCount} movement{result.totalCount === 1 ? "" : "s"}
            </p>
            <Pagination
              page={result.page}
              pageSize={result.pageSize}
              totalCount={result.totalCount}
              buildHref={(targetPage) => `/${tenantSlug}/operations/dispatch-board?page=${targetPage}`}
            />
          </div>
        </div>
      )}
    </div>
  );
}
