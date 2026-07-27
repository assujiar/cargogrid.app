import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listJobOrderHandoffs, JobOrderLineageQueryError } from "../../../../../../server/queries/job-order-lineage.ts";
import { getJobOrderConversionReadiness, JobOrderQueryError } from "../../../../../../server/queries/job-order.ts";
import type { JobOrderHandoff } from "../../../../../../server/contracts/job-order-lineage/job-order-lineage.ts";
import type { JobOrderConversionReadiness } from "../../../../../../server/contracts/job-order/job-order.ts";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PrepareJobOrderForm } from "./prepare-job-order-form.tsx";
import { prepareJobOrderAction } from "./actions.ts";

/**
 * Conversion review (OPS-168, CG-S8-OPS-002, Prompt 168 §15) -- the one surface that
 * turns a Commercial `JobOrderDraftInput` handoff (COM-160) into a canonical Job
 * Order. Selecting a handoff (`?handoffId=`) shows the real structural readiness
 * check (`app.get_job_order_conversion_readiness`) -- already-converted or a missing
 * payload both block, reason codes only, never a dollar figure -- before the one
 * bounded, idempotent conversion action.
 */
export default async function ConvertJobOrderPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ handoffId?: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { handoffId } = await searchParams;
  const supabase = await createSupabaseServerClient();

  let handoffs: JobOrderHandoff[];
  let loadFailed = false;
  try {
    handoffs = await listJobOrderHandoffs(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof JobOrderLineageQueryError)) {
      throw error;
    }
    loadFailed = true;
    handoffs = [];
  }

  let readiness: JobOrderConversionReadiness | null = null;
  let readinessFailed = false;
  if (handoffId) {
    try {
      readiness = await getJobOrderConversionReadiness(supabase, { sourceHandoffId: handoffId, actorAuthUserId: access.authUserId });
    } catch (error) {
      if (!(error instanceof JobOrderQueryError)) {
        throw error;
      }
      readinessFailed = true;
    }
  }

  const columns: readonly DataTableColumn<JobOrderHandoff>[] = [
    {
      key: "quotation",
      header: "Source quotation",
      render: (handoff) => handoff.quotationId,
    },
    { key: "status", header: "Handoff status", render: (handoff) => handoff.status },
    { key: "schemaVersion", header: "Schema version", render: (handoff) => handoff.schemaVersion },
    { key: "prepared", header: "Prepared", render: (handoff) => new Date(handoff.createdAt).toLocaleDateString() },
    {
      key: "review",
      header: "",
      render: (handoff) => (
        <a href={`/${tenantSlug}/operations/job-orders/convert?handoffId=${handoff.id}`} className="font-medium text-primary underline">
          Review conversion
        </a>
      ),
    },
  ];

  const boundAction = prepareJobOrderAction.bind(null, tenantSlug, handoffId ?? "");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Convert a Commercial handoff</h1>

      {handoffId ? (
        <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Conversion readiness</h2>
          {readinessFailed || !readiness ? (
            <ErrorState description="Something went wrong checking conversion readiness. Please try again." />
          ) : readiness.ready ? (
            <>
              <p className="text-sm text-success">Ready to convert -- no blockers found.</p>
              <PrepareJobOrderForm action={boundAction} />
            </>
          ) : (
            <div className="flex flex-col gap-1">
              <p className="text-sm text-danger">This handoff cannot be converted yet:</p>
              <ul className="list-inside list-disc text-sm text-neutral-700">
                {readiness.blockingReasons.map((reason) => (
                  <li key={reason}>{reason}</li>
                ))}
              </ul>
              {readiness.existingJobOrderId ? (
                <a href={`/${tenantSlug}/operations/job-orders/${readiness.existingJobOrderId}`} className="text-sm font-medium text-primary underline">
                  View the existing Job Order
                </a>
              ) : null}
            </div>
          )}
        </div>
      ) : null}

      <div className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Prepared handoffs</h2>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading Commercial handoffs. Please try again." />
        ) : (
          <DataTable
            caption="Prepared Commercial handoffs"
            columns={columns}
            rows={handoffs}
            rowKey={(handoff) => handoff.id}
            emptyMessage={<>No Commercial handoffs have been prepared yet.</>}
          />
        )}
      </div>
    </div>
  );
}
