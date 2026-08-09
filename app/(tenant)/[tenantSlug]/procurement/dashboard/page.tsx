import Link from "next/link";
import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../components/ui/permission-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import {
  getProcurementDashboardVendorRiskSummary,
  listProcurementVendorRiskDashboardRows,
  getProcurementDashboardRateValiditySummary,
  getProcurementDashboardRateCompetitivenessSummary,
  getProcurementDashboardRfqCycleSummary,
  getProcurementDashboardCapacityReservationSummary,
  getProcurementDashboardAssignmentAcceptanceSummary,
  getProcurementDashboardPoSummary,
  getProcurementDashboardContractSummary,
  getProcurementDashboardPerformanceSummary,
  listActiveProcurementMetricDefinitions,
  listProcurementDashboardSavedViews,
  ProcurementDashboardQueryError,
  ProcurementDashboardQueryTimeoutError,
} from "../../../../../server/queries/procurement-dashboard.ts";
import { getVendorBillMatchReconciliationStatus } from "../../../../../server/queries/vendor-invoice-matching.ts";
import { listReportRuns, ReportQueryError } from "../../../../../server/queries/report.ts";
import { SavedViewsPanel } from "./saved-views-panel.tsx";
import { ExportProcurementReportForm } from "./export-report-form.tsx";
import { VendorRiskQueuePanel } from "./vendor-risk-queue-panel.tsx";
import { createProcurementDashboardSavedViewAction, deleteProcurementDashboardSavedViewAction, requestProcurementReportExportAction } from "./actions.ts";

/**
 * Procurement Dashboard and Reports (PRC-266, CG-S11-PRC-017) -- eleven source-cited,
 * versioned metrics across all seven required groups (vendor status/risk/compliance-
 * expiry, rate validity/competitiveness, RFQ response/cycle, capacity/acceptance, PO/
 * contract, performance, match variance/exception rate), each enforcing the IDENTICAL
 * field/record policy the underlying capability's own RPC already enforces for the
 * same caller. Group 7 (match variance) reuses PRC-265's own already-VERIFIED
 * app.get_vendor_bill_match_reconciliation_status verbatim (zero new SQL). Every
 * widget is fetched independently via Promise.allSettled so a single slow/failed
 * section degrades gracefully rather than blanking the whole page (Prompt 266 section
 * 22's own "degraded cached view with visible freshness" -- freshness here is "live
 * OLTP as of this page load," never a cache).
 */

const PROCUREMENT_REPORT_CODES = new Set([
  "vendor_lifecycle_risk_mix",
  "vendor_rate_validity_mix",
  "vendor_rate_competitiveness_band_mix",
  "rfq_response_cycle_time",
  "vendor_capacity_reservation_mix",
  "vendor_assignment_invitation_acceptance",
  "purchase_order_pipeline_mix",
  "vendor_contract_lifecycle_mix",
  "vendor_performance_scorecard_mix",
  "vendor_bill_match_variance_exception_rate",
]);

function settledOrDenied<T>(result: PromiseSettledResult<T>): { value: T | null; denied: boolean; failed: boolean; timedOut: boolean } {
  if (result.status === "fulfilled") {
    return { value: result.value, denied: false, failed: false, timedOut: false };
  }
  const err = result.reason;
  const message = err instanceof Error ? err.message : String(err);
  const denied = /insufficient_authority/.test(message);
  // ProcurementDashboardQueryTimeoutError is the only query-budget class in this
  // capability; VendorInvoiceMatchingQueryError (group 7's reused RPC) has no
  // distinct timeout subclass of its own, so a group-7 timeout is classified as a
  // generic failure here rather than misreported as denied.
  const timedOut = err instanceof ProcurementDashboardQueryTimeoutError;
  return { value: null, denied, failed: !denied && !timedOut, timedOut };
}

function WidgetStatus({ denied, failed, timedOut }: { denied: boolean; failed: boolean; timedOut: boolean }) {
  if (denied) {
    return <PermissionState description="You don't hold the View permission for Procurement. Ask a Procurement administrator to grant PRC:View." />;
  }
  if (timedOut) {
    return <ErrorState description="This section is taking longer than expected to load. Please refresh." />;
  }
  if (failed) {
    return <ErrorState description="Something went wrong loading this section. Please refresh." />;
  }
  return null;
}

export default async function ProcurementDashboardPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string; band?: string; hold?: string; q?: string; after?: string; afterId?: string }>;
}) {
  const { tenantSlug } = await params;
  const sp = await searchParams;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const filter = { tenantId: access.tenant.id, actorAuthUserId: access.authUserId };
  const asOf = new Date().toISOString();

  // Tier C batch-5 fix (HIGH, spec-compliance): the vendor risk/compliance-expiry
  // drilldown queue's own filter/search/band/hold and cursor-pagination parameters were
  // previously never populated by any caller -- URL query params are this repository's
  // own established convention for a server-filtered/searched list (matches
  // app/(tenant)/[tenantSlug]/procurement/vendors/page.tsx's identical `status`/`q`
  // shape), threaded through to the RPC below and back out to VendorRiskQueuePanel/
  // SavedViewsPanel so a saved view can capture the actually-applied filter state.
  const vendorRiskFilters = {
    status: sp.status ?? "",
    band: sp.band ?? "",
    hold: sp.hold === "true",
    search: sp.q ?? "",
  };

  const [
    vendorRiskSummaryR,
    vendorRiskRowsR,
    rateValidityR,
    rateCompetitivenessR,
    rfqCycleR,
    capacityReservationR,
    assignmentAcceptanceR,
    poSummaryR,
    contractSummaryR,
    performanceR,
    matchVarianceR,
    metricDefinitionsR,
    savedViewsR,
    reportRunsR,
  ] = await Promise.allSettled([
    getProcurementDashboardVendorRiskSummary(supabase, filter),
    listProcurementVendorRiskDashboardRows(supabase, {
      ...filter,
      lifecycleStatus: vendorRiskFilters.status || null,
      band: vendorRiskFilters.band || null,
      complianceHoldOnly: vendorRiskFilters.hold || null,
      search: vendorRiskFilters.search || null,
      cursor: sp.after ?? null,
      cursorId: sp.afterId ?? null,
      limit: 25,
    }),
    getProcurementDashboardRateValiditySummary(supabase, filter),
    getProcurementDashboardRateCompetitivenessSummary(supabase, filter),
    getProcurementDashboardRfqCycleSummary(supabase, filter),
    getProcurementDashboardCapacityReservationSummary(supabase, filter),
    getProcurementDashboardAssignmentAcceptanceSummary(supabase, filter),
    getProcurementDashboardPoSummary(supabase, filter),
    getProcurementDashboardContractSummary(supabase, filter),
    getProcurementDashboardPerformanceSummary(supabase, filter),
    getVendorBillMatchReconciliationStatus(supabase, access.tenant.id, access.authUserId),
    listActiveProcurementMetricDefinitions(supabase),
    listProcurementDashboardSavedViews(supabase, access.tenant.id, access.authUserId, null, 25, null),
    listReportRuns(supabase, access.tenant.id, 20),
  ]);

  const vendorRiskSummary = settledOrDenied(vendorRiskSummaryR);
  const vendorRiskRows = settledOrDenied(vendorRiskRowsR);
  const rateValidity = settledOrDenied(rateValidityR);
  const rateCompetitiveness = settledOrDenied(rateCompetitivenessR);
  const rfqCycle = settledOrDenied(rfqCycleR);
  const capacityReservation = settledOrDenied(capacityReservationR);
  const assignmentAcceptance = settledOrDenied(assignmentAcceptanceR);
  const poSummary = settledOrDenied(poSummaryR);
  const contractSummary = settledOrDenied(contractSummaryR);
  const performance = settledOrDenied(performanceR);
  const matchVariance = settledOrDenied(matchVarianceR);

  const metricDefinitions = metricDefinitionsR.status === "fulfilled" ? metricDefinitionsR.value : [];
  const savedViews = savedViewsR.status === "fulfilled" ? savedViewsR.value : [];
  const reportRuns = (reportRunsR.status === "fulfilled" ? reportRunsR.value : []).filter((run) => PROCUREMENT_REPORT_CODES.has(run.reportTypeCode));

  // Whole-page denial: if the very first, baseline PRC:View-gated widget is denied,
  // every other widget will be too (identical gate) -- render one page-level denial
  // rather than eleven identical ones. Any load-level exception this bundle did not
  // itself catch and classify (a genuine bug, not a permission/timeout/data condition)
  // still propagates and renders Next's own error boundary, never swallowed silently.
  if (vendorRiskSummary.denied) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-neutral-900">Procurement dashboard</h1>
        <PermissionState description="You don't hold the View permission for Procurement. Ask a Procurement administrator to grant PRC:View." />
      </div>
    );
  }

  const degraded = [vendorRiskSummary, vendorRiskRows, rateValidity, rateCompetitiveness, rfqCycle, capacityReservation, assignmentAcceptance, poSummary, contractSummary, performance, matchVariance].some(
    (w) => w.failed || w.timedOut,
  );

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-baseline justify-between">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Procurement dashboard</h1>
          <p className="text-xs text-neutral-500">Live OLTP as-of {new Date(asOf).toLocaleString()} -- every summary, drilldown, filter, and export enforces the identical field/record policy the underlying capability&apos;s own RPC already enforces.</p>
        </div>
        {degraded ? <span className="rounded-full bg-warning/10 px-3 py-1 text-xs font-medium text-warning">Degraded -- some sections could not load</span> : null}
      </div>

      {/* Group 1 -- vendor status/risk/compliance-expiry */}
      <section className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">Vendor status, risk &amp; compliance expiry</h2>
          <Link href={`/${tenantSlug}/procurement/vendors`} className="text-xs font-medium text-primary hover:underline">
            Open vendors
          </Link>
        </div>
        <WidgetStatus {...vendorRiskSummary} />
        {vendorRiskSummary.value ? (
          vendorRiskSummary.value.length === 0 ? (
            <EmptyState title="No vendors yet" description="No vendor profiles exist in this tenant." />
          ) : (
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {vendorRiskSummary.value.map((row) => (
                <div key={row.lifecycleStatus} className="rounded-md border border-neutral-200 p-3">
                  <p className="text-xs font-medium text-neutral-500">{row.lifecycleStatus.replace(/_/g, " ")}</p>
                  <p className="text-lg font-semibold text-neutral-900">{row.vendorCount}</p>
                  <p className="text-xs text-neutral-500">{row.complianceHoldCount} on hold</p>
                </div>
              ))}
            </div>
          )
        ) : null}

        <WidgetStatus {...vendorRiskRows} />
        {vendorRiskRows.value ? <VendorRiskQueuePanel tenantSlug={tenantSlug} rows={vendorRiskRows.value} filters={vendorRiskFilters} /> : null}
      </section>

      {/* Group 2 -- rate validity/competitiveness */}
      <section className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">Rate validity &amp; competitiveness</h2>
          <Link href={`/${tenantSlug}/procurement/rates`} className="text-xs font-medium text-primary hover:underline">
            Open rates
          </Link>
        </div>
        <WidgetStatus {...rateValidity} />
        {rateValidity.value && rateValidity.value.length > 0 ? (
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {rateValidity.value.map((row) => (
              <li key={`${row.currency ?? "masked"}-${row.validityBucket}`} className="rounded-md border border-neutral-200 p-3">
                <p className="text-xs font-medium text-neutral-500">
                  {row.validityBucket.replace(/_/g, " ")} ({row.currency ?? "requires View cost"})
                </p>
                <p className="text-lg font-semibold text-neutral-900">{row.rateCount}</p>
              </li>
            ))}
          </ul>
        ) : rateValidity.value ? (
          <EmptyState title="No rate versions yet" description="No vendor rate versions exist in this tenant." />
        ) : null}

        <WidgetStatus {...rateCompetitiveness} />
        {rateCompetitiveness.value && rateCompetitiveness.value.length > 0 ? (
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {rateCompetitiveness.value.map((row) => (
              <li key={row.competitivenessBand} className="rounded-md border border-neutral-200 p-3">
                <p className="text-xs font-medium text-neutral-500">{row.competitivenessBand.replace(/_/g, " ")}</p>
                <p className="text-lg font-semibold text-neutral-900">{row.vendorCount}</p>
                <p className="text-xs text-neutral-500">{row.avgScore != null ? `avg score ${row.avgScore}` : "—"}</p>
              </li>
            ))}
          </ul>
        ) : null}
      </section>

      {/* Group 3 -- RFQ response rate / cycle time */}
      <section className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">RFQ response rate &amp; cycle time</h2>
          <Link href={`/${tenantSlug}/procurement/rfq`} className="text-xs font-medium text-primary hover:underline">
            Open RFQs
          </Link>
        </div>
        <WidgetStatus {...rfqCycle} />
        {rfqCycle.value ? (
          rfqCycle.value.length === 0 ? (
            <EmptyState title="No RFQs yet" description="No RFQs have been issued in this tenant." />
          ) : (
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-left text-neutral-500">
                  <th className="py-2 pr-4 font-medium">Status</th>
                  <th className="py-2 pr-4 font-medium">Invitations</th>
                  <th className="py-2 pr-4 font-medium">Responses</th>
                  <th className="py-2 pr-4 font-medium">Response rate</th>
                  <th className="py-2 font-medium">Avg cycle (hours)</th>
                </tr>
              </thead>
              <tbody>
                {rfqCycle.value.map((row) => (
                  <tr key={row.rfqStatus} className="border-b border-neutral-100">
                    <td className="py-2 pr-4 text-neutral-900">{row.rfqStatus}</td>
                    <td className="py-2 pr-4 text-neutral-700">{row.invitationCount}</td>
                    <td className="py-2 pr-4 text-neutral-700">{row.responseCount}</td>
                    <td className="py-2 pr-4 text-neutral-700">{row.responseRatePct != null ? `${row.responseRatePct}%` : "—"}</td>
                    <td className="py-2 text-neutral-700">{row.avgCycleHours ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        ) : null}
      </section>

      {/* Group 4 -- capacity / acceptance */}
      <section className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">Capacity &amp; acceptance</h2>
          <div className="flex gap-3">
            <Link href={`/${tenantSlug}/procurement/vendor-capacity`} className="text-xs font-medium text-primary hover:underline">
              Open capacity
            </Link>
            <Link href={`/${tenantSlug}/procurement/vendor-assignments`} className="text-xs font-medium text-primary hover:underline">
              Open assignments
            </Link>
          </div>
        </div>
        <WidgetStatus {...capacityReservation} />
        {capacityReservation.value && capacityReservation.value.length > 0 ? (
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-5">
            {capacityReservation.value.map((row) => (
              <li key={row.status} className="rounded-md border border-neutral-200 p-3">
                <p className="text-xs font-medium text-neutral-500">{row.status}</p>
                <p className="text-lg font-semibold text-neutral-900">{row.reservationCount}</p>
              </li>
            ))}
          </ul>
        ) : capacityReservation.value ? (
          <EmptyState title="No capacity reservations yet" description="No vendor capacity has been reserved in this tenant." />
        ) : null}

        <WidgetStatus {...assignmentAcceptance} />
        {assignmentAcceptance.value && assignmentAcceptance.value.length > 0 ? (
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-500">
                <th className="py-2 pr-4 font-medium">Status</th>
                <th className="py-2 pr-4 font-medium">Invitations</th>
                <th className="py-2 font-medium">Avg response (hours)</th>
              </tr>
            </thead>
            <tbody>
              {assignmentAcceptance.value.map((row) => (
                <tr key={row.status} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">{row.status}</td>
                  <td className="py-2 pr-4 text-neutral-700">{row.invitationCount}</td>
                  <td className="py-2 text-neutral-700">{row.avgResponseHours ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
      </section>

      {/* Group 5 -- PO / contract */}
      <section className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">Purchase orders &amp; contracts</h2>
          <div className="flex gap-3">
            <Link href={`/${tenantSlug}/procurement/purchase-orders`} className="text-xs font-medium text-primary hover:underline">
              Open POs
            </Link>
            <Link href={`/${tenantSlug}/procurement/vendor-contracts`} className="text-xs font-medium text-primary hover:underline">
              Open contracts
            </Link>
          </div>
        </div>
        <WidgetStatus {...poSummary} />
        {poSummary.value && poSummary.value.length > 0 ? (
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-500">
                <th className="py-2 pr-4 font-medium">Status</th>
                <th className="py-2 pr-4 font-medium">Currency</th>
                <th className="py-2 pr-4 font-medium">POs</th>
                <th className="py-2 font-medium">Committed amount</th>
              </tr>
            </thead>
            <tbody>
              {poSummary.value.map((row) => (
                <tr key={`${row.status}-${row.currency ?? "masked"}`} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">{row.status}</td>
                  <td className="py-2 pr-4 text-neutral-700">{row.currency ?? <span className="text-neutral-400">masked</span>}</td>
                  <td className="py-2 pr-4 text-neutral-700">{row.poCount}</td>
                  <td className="py-2 text-neutral-700">{row.costMasked ? <span className="text-neutral-400">masked (requires View cost)</span> : row.committedAmount}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : poSummary.value ? (
          <EmptyState title="No purchase orders yet" description="No purchase orders exist in this tenant." />
        ) : null}

        <WidgetStatus {...contractSummary} />
        {contractSummary.value && contractSummary.value.length > 0 ? (
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {contractSummary.value.map((row) => (
              <li key={row.status} className="rounded-md border border-neutral-200 p-3">
                <p className="text-xs font-medium text-neutral-500">{row.status}</p>
                <p className="text-lg font-semibold text-neutral-900">{row.contractCount}</p>
                {row.expiringSoonCount > 0 ? <p className="text-xs text-warning">{row.expiringSoonCount} expiring within 30 days</p> : null}
              </li>
            ))}
          </ul>
        ) : null}
      </section>

      {/* Group 6 -- performance */}
      <section className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">Vendor performance</h2>
          <Link href={`/${tenantSlug}/procurement/vendor-performance`} className="text-xs font-medium text-primary hover:underline">
            Open performance
          </Link>
        </div>
        <WidgetStatus {...performance} />
        {performance.value && performance.value.length > 0 ? (
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {performance.value.map((row) => (
              <li key={row.band} className="rounded-md border border-neutral-200 p-3">
                <p className="text-xs font-medium text-neutral-500">{row.band}</p>
                <p className="text-lg font-semibold text-neutral-900">{row.vendorCount}</p>
                <p className="text-xs text-neutral-500">{row.avgCompositeScore != null ? `avg score ${row.avgCompositeScore}` : "—"}</p>
              </li>
            ))}
          </ul>
        ) : performance.value ? (
          <EmptyState title="No published scorecards yet" description="No vendor has a published KPI scorecard in this tenant." />
        ) : null}
      </section>

      {/* Group 7 -- match variance / exception rate (entirely reused from PRC-265) */}
      <section className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">Vendor bill match variance &amp; exceptions</h2>
          <Link href={`/${tenantSlug}/procurement/vendor-invoice-matching`} className="text-xs font-medium text-primary hover:underline">
            Open invoice matching
          </Link>
        </div>
        <WidgetStatus {...matchVariance} />
        {matchVariance.value ? (
          matchVariance.value.length === 0 ? (
            <EmptyState title="No match cases yet" description="No vendor bill match cases exist in this tenant." />
          ) : (
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-left text-neutral-500">
                  <th className="py-2 pr-4 font-medium">Status</th>
                  <th className="py-2 pr-4 font-medium">Readiness</th>
                  <th className="py-2 pr-4 font-medium">Cases</th>
                  <th className="py-2 font-medium">Total variance</th>
                </tr>
              </thead>
              <tbody>
                {matchVariance.value.map((row) => (
                  <tr key={`${row.overallStatus}-${row.readinessStatus}`} className="border-b border-neutral-100">
                    <td className="py-2 pr-4 text-neutral-900">{row.overallStatus}</td>
                    <td className="py-2 pr-4 text-neutral-700">{row.readinessStatus}</td>
                    <td className="py-2 pr-4 text-neutral-700">{row.caseCount}</td>
                    <td className="py-2 text-neutral-700">{row.totalVarianceAmount ?? <span className="text-neutral-400">masked (requires View cost)</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        ) : null}
      </section>

      {/* Saved views */}
      <SavedViewsPanel
        tenantSlug={tenantSlug}
        views={savedViews}
        vendorRiskFilters={vendorRiskFilters}
        createAction={createProcurementDashboardSavedViewAction.bind(null, tenantSlug)}
        deleteAction={deleteProcurementDashboardSavedViewAction.bind(null, tenantSlug)}
      />

      {/* Reports / export */}
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Reports</h2>
        <p className="text-xs text-neutral-500">Every metric above is also a governed, exportable report. Definitions below cite the exact source tables/columns, formula, grain, freshness rule, and PRC action gate each one requires.</p>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {metricDefinitions.map((def) => (
            <div key={def.code} className="rounded-md border border-neutral-200 p-3">
              <p className="text-sm font-medium text-neutral-900">{def.name}</p>
              <p className="mt-1 text-xs text-neutral-500">{def.description}</p>
              <p className="mt-1 text-xs text-neutral-400">
                Source: {def.sourceTables.join(", ")} · Grain: {def.grain} · Gate: PRC:{def.requiredAction}
                {def.additionalMaskAction ? ` (+ PRC:${def.additionalMaskAction} unmasks cost)` : ""}
              </p>
              {PROCUREMENT_REPORT_CODES.has(def.code) ? (
                <div className="mt-2">
                  <ExportProcurementReportForm action={requestProcurementReportExportAction.bind(null, tenantSlug, def.code)} label="Request export" />
                </div>
              ) : (
                <p className="mt-2 text-xs text-neutral-400">Live work-queue view -- not individually exportable.</p>
              )}
            </div>
          ))}
        </div>

        <h3 className="mt-2 text-sm font-semibold text-neutral-900">Recent export runs</h3>
        {reportRuns.length === 0 ? (
          <EmptyState title="No export has been requested yet" description="Request an export above to see it here." />
        ) : (
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-500">
                <th className="py-2 pr-4 font-medium">Report</th>
                <th className="py-2 pr-4 font-medium">Status</th>
                <th className="py-2 font-medium">Requested</th>
              </tr>
            </thead>
            <tbody>
              {reportRuns.map((run) => (
                <tr key={run.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">{run.reportTypeCode}</td>
                  <td className="py-2 pr-4 text-neutral-700">
                    <StatusBadge tone={run.status === "completed" ? "success" : run.status === "failed" ? "danger" : "neutral"} label={run.status} />
                  </td>
                  <td className="py-2 text-neutral-700">{new Date(run.requestedAt).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  );
}
