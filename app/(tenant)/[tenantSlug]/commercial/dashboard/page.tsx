import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import {
  getDashboardLeadAging,
  getDashboardActivityQueue,
  getDashboardPipelineSummary,
  getDashboardQuoteSla,
  getDashboardMarginSummary,
  getDashboardWinLossSummary,
  getDashboardForecastSummary,
  DashboardQueryTimeoutError,
  DashboardQueryError,
} from "../../../../../server/queries/dashboard.ts";
import type {
  LeadAgingEntry,
  ActivityQueueEntry,
  PipelineSummaryEntry,
  QuoteSlaEntry,
  MarginSummaryEntry,
  WinLossSummaryEntry,
  ForecastSummaryEntry,
} from "../../../../../server/contracts/dashboard/dashboard.ts";

/**
 * Commercial Dashboard (COM-158, CG-S7-COM-017): role-specific live metrics -- lead
 * aging, activity queue, pipeline, quote SLA, margin, win/loss and forecast -- each
 * sourced from its own app.get_dashboard_* RPC (`security definer`, its own
 * app.can_access_record row filter; see the migration's header for why). No org-unit/
 * owner drill-down filter UI in this bounded slice -- every card always reflects the
 * caller's own full accessible scope (every p_org_unit_id/p_owner_user_id is left null),
 * the same disclosed choice COM-146's Pipeline page already made for its own summary.
 * Drill-down links go to each metric's existing canonical list route -- there is no
 * bespoke Activity or Margin list route yet, so those two cards render data only.
 */

const LEAD_AGING_LABELS: Record<LeadAgingEntry["bucket"], string> = {
  "0_2_days": "0–2 days",
  "3_7_days": "3–7 days",
  "8_14_days": "8–14 days",
  "15_plus_days": "15+ days",
};

const ACTIVITY_QUEUE_LABELS: Record<ActivityQueueEntry["bucket"], string> = {
  overdue: "Overdue",
  due_today: "Due today",
  upcoming_7_days: "Upcoming (7 days)",
  no_due_date: "No due date",
};

const QUOTE_SLA_LABELS: Record<QuoteSlaEntry["bucket"], string> = {
  pending_approval: "Pending approval",
  expiring_soon: "Expiring soon",
  expired_no_decision: "Expired, no decision",
  awaiting_customer_decision: "Awaiting customer decision",
};

function formatAmount(amount: number | null, masked: boolean, currency: string | null): string {
  if (masked) {
    return "Masked";
  }
  if (amount === null) {
    return "—";
  }
  return `${currency ?? ""} ${amount.toLocaleString("en-US", { maximumFractionDigits: 2 })}`.trim();
}

type DashboardData = {
  leadAging: LeadAgingEntry[];
  activityQueue: ActivityQueueEntry[];
  pipeline: PipelineSummaryEntry[];
  quoteSla: QuoteSlaEntry[];
  margin: MarginSummaryEntry[];
  winLoss: WinLossSummaryEntry[];
  forecast: ForecastSummaryEntry[];
};

export default async function CommercialDashboardPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const filter = { tenantId: access.tenant.id };

  let data: DashboardData | null = null;
  let loadError: "timeout" | "failed" | null = null;
  try {
    const [leadAging, activityQueue, pipeline, quoteSla, margin, winLoss, forecast] = await Promise.all([
      getDashboardLeadAging(supabase, filter),
      getDashboardActivityQueue(supabase, filter),
      getDashboardPipelineSummary(supabase, filter),
      getDashboardQuoteSla(supabase, filter),
      getDashboardMarginSummary(supabase, filter),
      getDashboardWinLossSummary(supabase, filter),
      getDashboardForecastSummary(supabase, filter),
    ]);
    data = { leadAging, activityQueue, pipeline, quoteSla, margin, winLoss, forecast };
  } catch (error) {
    if (error instanceof DashboardQueryTimeoutError) {
      loadError = "timeout";
    } else if (error instanceof DashboardQueryError) {
      loadError = "failed";
    } else {
      throw error;
    }
  }

  const asOf = new Date().toISOString();

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold text-neutral-900">Dashboard</h1>
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
            <h2 className="text-sm font-semibold text-neutral-900">Lead aging</h2>
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {(Object.keys(LEAD_AGING_LABELS) as LeadAgingEntry["bucket"][]).map((bucket) => {
                const entry = data.leadAging.find((row) => row.bucket === bucket);
                return (
                  <li key={bucket} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{LEAD_AGING_LABELS[bucket]}</p>
                    <p className="text-lg font-semibold text-neutral-900">{entry?.leadCount ?? 0}</p>
                  </li>
                );
              })}
            </ul>
            <a href={`/${tenantSlug}/commercial/leads`} className="text-sm font-medium text-primary underline">
              Open leads
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Activity queue</h2>
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {(Object.keys(ACTIVITY_QUEUE_LABELS) as ActivityQueueEntry["bucket"][]).map((bucket) => {
                const entry = data.activityQueue.find((row) => row.bucket === bucket);
                return (
                  <li key={bucket} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{ACTIVITY_QUEUE_LABELS[bucket]}</p>
                    <p className="text-lg font-semibold text-neutral-900">{entry?.activityCount ?? 0}</p>
                  </li>
                );
              })}
            </ul>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Pipeline</h2>
            {data.pipeline.length === 0 ? (
              <p className="text-sm text-neutral-600">No open opportunities in scope.</p>
            ) : (
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-neutral-600">
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Stage
                    </th>
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Opportunities
                    </th>
                    <th scope="col" className="py-2 font-medium">
                      Value
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {data.pipeline.map((row) => (
                    <tr key={`${row.stage}-${row.currency ?? "none"}`} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-neutral-900">{row.stage.replace(/_/g, " ")}</td>
                      <td className="py-2 pr-4 text-neutral-600">{row.opportunityCount}</td>
                      <td className="py-2 text-neutral-600">{formatAmount(row.valueAmountTotal, row.valueMasked, row.currency)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            <a href={`/${tenantSlug}/commercial/pipeline`} className="text-sm font-medium text-primary underline">
              Open pipeline
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Quote SLA</h2>
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {(Object.keys(QUOTE_SLA_LABELS) as QuoteSlaEntry["bucket"][]).map((bucket) => {
                const entry = data.quoteSla.find((row) => row.bucket === bucket);
                return (
                  <li key={bucket} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{QUOTE_SLA_LABELS[bucket]}</p>
                    <p className="text-lg font-semibold text-neutral-900">{entry?.quoteCount ?? 0}</p>
                  </li>
                );
              })}
            </ul>
            <a href={`/${tenantSlug}/commercial/quotations`} className="text-sm font-medium text-primary underline">
              Open quotations
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Margin</h2>
            {data.margin.length === 0 ? (
              <p className="text-sm text-neutral-600">No current margin calculations in scope.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {data.margin.map((row) => (
                  <li key={row.currency} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{row.currency}</p>
                    <p className="text-lg font-semibold text-neutral-900">
                      {row.marginMasked ? "Masked" : `${row.avgMarginPct ?? "—"}% avg`}
                    </p>
                    <p className="text-xs text-neutral-500">
                      {row.calculationCount} calculation{row.calculationCount === 1 ? "" : "s"} — {formatAmount(row.totalMarginAmount, row.marginMasked, row.currency)}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Win / loss</h2>
            {data.winLoss.length === 0 ? (
              <p className="text-sm text-neutral-600">No won or lost opportunities in scope.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {data.winLoss.map((row) => (
                  <li key={`${row.outcome}-${row.currency ?? "none"}`} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">
                      {row.outcome === "won" ? "Won" : "Lost"} ({row.currency ?? "—"})
                    </p>
                    <p className="text-lg font-semibold text-neutral-900">{row.opportunityCount}</p>
                    <p className="text-xs text-neutral-500">{formatAmount(row.valueAmountTotal, row.valueMasked, row.currency)}</p>
                  </li>
                ))}
              </ul>
            )}
            <a href={`/${tenantSlug}/commercial/opportunities`} className="text-sm font-medium text-primary underline">
              Open opportunities
            </a>
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-neutral-900">Forecast</h2>
            {data.forecast.length === 0 ? (
              <p className="text-sm text-neutral-600">No open opportunities to forecast.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {data.forecast.map((row) => (
                  <li key={row.currency ?? "none"} className="rounded-md border border-neutral-200 p-3">
                    <p className="text-xs font-medium text-neutral-600">{row.currency ?? "—"}</p>
                    <p className="text-lg font-semibold text-neutral-900">{formatAmount(row.weightedValueTotal, row.valueMasked, row.currency)}</p>
                    <p className="text-xs text-neutral-500">{row.openOpportunityCount} open opportunities</p>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      ) : null}
    </div>
  );
}
