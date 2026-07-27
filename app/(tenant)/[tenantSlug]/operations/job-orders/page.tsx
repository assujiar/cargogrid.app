import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listJobOrders, JobOrderQueryError, type ListJobOrdersResult } from "../../../../../server/queries/job-order.ts";
import type { JobOrder } from "../../../../../server/contracts/job-order/job-order.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { JOB_ORDER_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";

/**
 * Job Order list (OPS-168, CG-S8-OPS-002). Tenant-wide, field-masked via
 * app.job_orders_directory (COM:View selling price gates the revenue total, reused
 * directly from Commercial -- conversion never broadens Commercial access). A Job
 * Order is created only via the conversion review flow at `job-orders/convert`, not
 * from a standalone creation form here, mirroring how Commercial's own quotation list
 * never lets a caller create a quotation directly either.
 */
export default async function JobOrdersPage({
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

  let result: ListJobOrdersResult | null = null;
  let loadFailed = false;
  try {
    result = await listJobOrders(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof JobOrderQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<JobOrder>[] = [
    {
      key: "jobNumber",
      header: "Job number",
      render: (jobOrder) => (
        <a href={`/${tenantSlug}/operations/job-orders/${jobOrder.id}`} className="font-medium text-primary underline">
          {jobOrder.jobNumber}
        </a>
      ),
    },
    {
      key: "customer",
      header: "Customer",
      render: (jobOrder) => (jobOrder.customerSnapshot as { customerSnapshot?: { legal_name?: string } }).customerSnapshot?.legal_name ?? "—",
    },
    {
      key: "status",
      header: "Status",
      render: (jobOrder) => {
        const { tone, label } = JOB_ORDER_STATUS_TONE_MAP[jobOrder.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "revenue",
      header: "Revenue",
      render: (jobOrder) =>
        jobOrder.revenueMasked
          ? "Restricted"
          : jobOrder.revenueSnapshot
            ? `${(jobOrder.revenueSnapshot as { currency?: string }).currency ?? ""} ${((jobOrder.revenueSnapshot as { totalAmount?: number }).totalAmount ?? 0).toLocaleString("en-US")}`
            : "—",
    },
    { key: "created", header: "Created", render: (jobOrder) => new Date(jobOrder.createdAt).toLocaleDateString() },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-neutral-900">Job Orders</h1>
        <a href={`/${tenantSlug}/operations/job-orders/convert`} className="text-sm font-medium text-primary underline">
          Convert a Commercial handoff
        </a>
      </div>

      {loadFailed || !result ? (
        <ErrorState description="Something went wrong loading Job Orders. Please try again." />
      ) : (
        <div className="flex flex-col gap-4">
          <DataTable
            caption="Job Orders"
            columns={columns}
            rows={result.jobOrders}
            rowKey={(jobOrder) => jobOrder.id}
            emptyMessage={<>No Job Orders yet. Convert an accepted Commercial handoff to create one.</>}
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-neutral-500">
              Page {result.page} — {result.totalCount} total Job Order{result.totalCount === 1 ? "" : "s"}
            </p>
            <Pagination
              page={result.page}
              pageSize={result.pageSize}
              totalCount={result.totalCount}
              buildHref={(targetPage) => `/${tenantSlug}/operations/job-orders?page=${targetPage}`}
            />
          </div>
        </div>
      )}
    </div>
  );
}
