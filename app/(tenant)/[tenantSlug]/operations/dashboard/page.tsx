import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import {
  getOpsDashboardShipmentStatus,
  getOpsDashboardMilestoneSla,
  getOpsDashboardExceptionQueue,
  getOpsDashboardEpodCompletion,
  getOpsDashboardCostVariance,
  getOpsDashboardBillingReadiness,
  OpsDashboardQueryTimeoutError,
  OpsDashboardQueryError,
} from "../../../../../server/queries/ops-dashboard.ts";
import type {
  ShipmentStatusEntry,
  MilestoneSlaEntry,
  ExceptionQueueEntry,
  EpodCompletionEntry,
  CostVarianceEntry,
  BillingReadinessSummaryEntry,
} from "../../../../../server/contracts/ops-dashboard/ops-dashboard.ts";

/**
 * Operations Dashboard (OPS-182, CG-S8-OPS-016): role-specific live metrics --
 * shipment status, milestone SLA, exceptions, ePOD completion, cost variance and
 * billing readiness -- each sourced from its own app.get_ops_dashboard_* RPC
 * (`security definer`, its own app.can_access_record row filter; see the migration's
 * header for why). No org-unit/owner drill-down filter UI in this bounded slice --
 * every card always reflects the caller's own full accessible scope (every
 * p_org_unit_id/p_owner_user_id is left null), the same disclosed choice the
 * Commercial Dashboard (COM-158) already made for its own summary. Drill-down links go
 * to each metric's existing canonical list route.
 */

const MILESTONE_SLA_LABELS: Record<MilestoneSlaEntry["bucket"], string> = {
  on_time: "On time",
  delayed: "Delayed",
  no_projection: "No projection yet",
};

const EXCEPTION_SEVERITY_LABELS: Record<ExceptionQueueEntry["severity"], string> = {
  low: "Low",
  medium: "Medium",
  high: "High",
  critical: "Critical",
};

const COST_VARIANCE_LABELS: Record<CostVarianceEntry["bucket"], string> = {
  over_budget: "Over budget (>5%)",
  under_budget: "Under budget (<-5%)",
  on_budget: "On budget",
};

const BILLING_READINESS_LABELS: Record<BillingReadinessSummaryEntry["bucket"], string> = {
  ready: "Ready",
  not_ready: "Not ready",
};

type DashboardData = {
  shipmentStatus: ShipmentStatusEntry[];
  milestoneSla: MilestoneSlaEntry[];
  exceptionQueue: ExceptionQueueEntry[];
  epodCompletion: EpodCompletionEntry[];
  costVariance: CostVarianceEntry[];
  billingReadiness: BillingReadinessSummaryEntry[];
};

export default async function OperationsDashboardPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const filter = { tenantId: access.tenant.id };

  let data: DashboardData | null = null;
  let loadError: "timeout" | "failed" | null = null;
  try {
    const [shipmentStatus, milestoneSla, exceptionQueue, epodCompletion, costVariance, billingReadiness] = await Promise.all([
      getOpsDashboardShipmentStatus(supabase, filter),
      getOpsDashboardMilestoneSla(supabase, filter),
      getOpsDashboardExceptionQueue(supabase, filter),
      getOpsDashboardEpodCompletion(supabase, filter),
      getOpsDashboardCostVariance(supabase, filter),
      getOpsDashboardBillingReadiness(supabase, filter),
    ]);
    data = { shipmentStatus, milestoneSla, exceptionQueue, epodCompletion, costVariance, billingReadiness };
  } catch (error) {
    if (error instanceof OpsDashboardQueryTimeoutError) {
      loadError = "timeout";
    } else if (error instanceof OpsDashboardQueryError) {
      loadError = "failed";
    } else {
      throw error;
    }
  }

  const asOf = new Date().toISOString();

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold text-neutral-900">Operations dashboard</h1>
        {data ? <p className="text-xs text-neutral-500">As of {asOf}</p> : null}
      </div>

      {loadError ? (
        <ErrorState
          description={
            loadError === "timeout"
              ? "The dashboard is taking longer than expected to load. Please try again."
              : "Something went wrong loading the dashboard. Please try again."
          }
        />
      ) : null}

      {data ? (
        <>
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Shipment status</h2>
            {data.shipmentStatus.length === 0 ? (
              <p className="text-sm text-neutral-600">No Shipment Orders in scope.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {data.shipmentStatus.map((row) => (
                  <li key={row.status} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{row.status.replace(/_/g, " ")}</p>
                    <p className="text-lg font-semibold text-neutral-900">{row.shipmentCount}</p>
                  </li>
                ))}
              </ul>
            )}
            <a href={`/${tenantSlug}/operations/shipment-orders`} className="text-sm font-medium text-primary underline">
              Open shipment orders
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Milestone SLA</h2>
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {(Object.keys(MILESTONE_SLA_LABELS) as MilestoneSlaEntry["bucket"][]).map((bucket) => {
                const entry = data.milestoneSla.find((row) => row.bucket === bucket);
                return (
                  <li key={bucket} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{MILESTONE_SLA_LABELS[bucket]}</p>
                    <p className="text-lg font-semibold text-neutral-900">{entry?.shipmentCount ?? 0}</p>
                  </li>
                );
              })}
            </ul>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Exception queue</h2>
            {data.exceptionQueue.length === 0 ? (
              <p className="text-sm text-neutral-600">No active exceptions in scope.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {data.exceptionQueue.map((row) => (
                  <li key={row.severity} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{EXCEPTION_SEVERITY_LABELS[row.severity]}</p>
                    <p className="text-lg font-semibold text-neutral-900">{row.exceptionCount}</p>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">ePOD completion</h2>
            {data.epodCompletion.length === 0 ? (
              <p className="text-sm text-neutral-600">No ePOD captures in scope.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {data.epodCompletion.map((row) => (
                  <li key={row.status} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{row.status.replace(/_/g, " ")}</p>
                    <p className="text-lg font-semibold text-neutral-900">{row.captureCount}</p>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Cost variance</h2>
            {data.costVariance.length === 0 ? (
              <p className="text-sm text-neutral-600">No approved actual costs with an estimate in scope.</p>
            ) : (
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-neutral-600">
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Bucket
                    </th>
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Currency
                    </th>
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Shipments
                    </th>
                    <th scope="col" className="py-2 font-medium">
                      Avg variance
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {data.costVariance.map((row) => (
                    <tr key={`${row.bucket}-${row.currency}`} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-neutral-900">{COST_VARIANCE_LABELS[row.bucket]}</td>
                      <td className="py-2 pr-4 text-neutral-600">{row.currency}</td>
                      <td className="py-2 pr-4 text-neutral-600">{row.shipmentCount}</td>
                      <td className="py-2 text-neutral-600">{row.varianceMasked ? "Masked" : `${row.avgVariancePct ?? "—"}%`}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Billing readiness</h2>
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {(Object.keys(BILLING_READINESS_LABELS) as BillingReadinessSummaryEntry["bucket"][]).map((bucket) => {
                const entry = data.billingReadiness.find((row) => row.bucket === bucket);
                return (
                  <li key={bucket} className="rounded-md border border-neutral-200 p-3">
                    <div className="flex items-center gap-2">
                      <StatusBadge tone={bucket === "ready" ? "success" : "warning"} label={BILLING_READINESS_LABELS[bucket]} />
                    </div>
                    <p className="mt-1 text-lg font-semibold text-neutral-900">{entry?.jobCount ?? 0}</p>
                  </li>
                );
              })}
            </ul>
            <a href={`/${tenantSlug}/operations/job-orders`} className="text-sm font-medium text-primary underline">
              Open job orders
            </a>
          </section>
        </>
      ) : null}
    </div>
  );
}
