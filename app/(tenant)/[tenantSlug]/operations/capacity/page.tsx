import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getTenantTrackingCoverage, getTenantTrackingUtilizationSummary, CapacityUtilizationQueryError } from "../../../../../server/queries/capacity-utilization.ts";
import type { TenantTrackingCoverageRow, TenantTrackingUtilizationSummary } from "../../../../../server/contracts/capacity-utilization/capacity-utilization.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";

const COVERAGE_STATUS_TONE = { tracked: "success", stale: "warning", offline: "danger", not_tracked: "neutral" } as const;
const SOURCE_CLASS_LABEL = { none: "none", mobile_only: "mobile", direct_device_only: "device", third_party_only: "third-party", hybrid: "hybrid" } as const;

/**
 * Capacity, Utilization and Tracking Coverage dashboard (ATW-227, CG-S10-ATW-008).
 * Read-only tenant-wide view over app.get_tenant_tracking_utilization_summary/
 * app.get_tenant_tracking_coverage -- entitlement/limits, coverage counts, device and
 * mobile-session utilization, and untracked-required-leg count, plus a per-vehicle
 * coverage table with the live capacity-reservation snapshot.
 *
 * The reserve/consume/release capacity operations (app.reserve_vehicle_capacity and
 * friends) are dispatch/planning-integration APIs, not a human data-entry form here --
 * this checkpoint ships the read surface a manager needs first; a capacity calendar
 * wired to actual dispatch actions is deferred to that integration's own task.
 */
export default async function CapacityUtilizationPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const tenantId = access.tenant.id;

  let summary: TenantTrackingUtilizationSummary | null = null;
  let coverage: TenantTrackingCoverageRow[] = [];
  let loadError: "denied" | "failed" | null = null;
  try {
    const [summaryResult, coverageResult] = await Promise.all([
      getTenantTrackingUtilizationSummary(supabase, tenantId, access.authUserId),
      getTenantTrackingCoverage(supabase, tenantId, access.authUserId),
    ]);
    summary = summaryResult;
    coverage = coverageResult;
  } catch (error) {
    if (!(error instanceof CapacityUtilizationQueryError)) {
      throw error;
    }
    loadError = /insufficient_authority/.test(error.message) ? "denied" : "failed";
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Capacity and tracking coverage</h1>
        <p className="text-xs text-neutral-500">Physical vehicle capacity utilization and tracking-package coverage, tenant-wide. Capacity and tracking usage are separate dimensions.</p>
      </div>

      {loadError === "denied" ? (
        <ErrorState description="You don't hold the OPS View permission needed to see this dashboard." />
      ) : loadError === "failed" ? (
        <ErrorState description="Something went wrong loading capacity and tracking coverage. Please try again." />
      ) : null}

      {summary ? (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Tracking package utilization</h2>
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <li className="rounded-md border border-neutral-200 p-3">
              <p className="text-xs font-medium text-neutral-500">Package</p>
              <p className="text-lg font-semibold text-neutral-900">{summary.trackingEnabled ? (summary.packageCode ?? "enabled") : "not enabled"}</p>
              <p className="text-xs text-neutral-500">{summary.maxTrackedVehicles === null ? "no vehicle limit" : `limit ${summary.maxTrackedVehicles} vehicles`}</p>
            </li>
            <li className="rounded-md border border-neutral-200 p-3">
              <p className="text-xs font-medium text-neutral-500">Tracked vehicles</p>
              <p className="text-lg font-semibold text-neutral-900">
                {summary.trackedVehicleCount} / {summary.totalActiveVehicleCount}
              </p>
              <p className="text-xs text-neutral-500">{summary.trackedVehicleLimitRemaining === null ? "no subscription limit" : `${summary.trackedVehicleLimitRemaining} remaining`}</p>
            </li>
            <li className="rounded-md border border-neutral-200 p-3">
              <p className="text-xs font-medium text-neutral-500">Offline / not tracked</p>
              <p className="text-lg font-semibold text-neutral-900">
                {summary.offlineVehicleCount} / {summary.notTrackedVehicleCount}
              </p>
              <p className="text-xs text-neutral-500">{summary.staleVehicleCount} stale</p>
            </li>
            <li className="rounded-md border border-neutral-200 p-3">
              <p className="text-xs font-medium text-neutral-500">Devices active</p>
              <p className="text-lg font-semibold text-neutral-900">
                {summary.deviceActiveCount} / {summary.deviceTotalCount}
              </p>
              <p className="text-xs text-neutral-500">{summary.mobileSessionActiveCount} active mobile sessions</p>
            </li>
          </ul>
          {summary.untrackedRequiredLegCount > 0 ? (
            <div className="rounded-md border border-danger/30 bg-danger/10 p-3 text-sm text-danger">
              {summary.untrackedRequiredLegCount} dispatched/in-transit leg{summary.untrackedRequiredLegCount === 1 ? "" : "s"} require tracking but have no active tracking session.
            </div>
          ) : null}
        </section>
      ) : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Vehicle coverage and capacity</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                <th className="py-2 pr-3 font-medium">Vehicle</th>
                <th className="py-2 pr-3 font-medium">Source class</th>
                <th className="py-2 pr-3 font-medium">Coverage</th>
                <th className="py-2 pr-3 font-medium">Provider mapping</th>
                <th className="py-2 pr-3 font-medium">Reserved / capacity (kg)</th>
                <th className="py-2 pr-3 font-medium">Reserved / capacity (cbm)</th>
                <th className="py-2 pr-3 font-medium">Last position</th>
              </tr>
            </thead>
            <tbody>
              {coverage.length === 0 ? (
                <tr>
                  <td colSpan={7} className="py-3 text-sm text-neutral-500">
                    No active vehicles registered yet.
                  </td>
                </tr>
              ) : (
                coverage.map((row) => (
                  <tr key={row.vehicleMasterId} className="border-b border-neutral-100">
                    <td className="py-2 pr-3">
                      <div className="font-medium text-neutral-900">{row.vehicleCode}</div>
                      <div className="text-xs text-neutral-500">{row.vehicleName}</div>
                    </td>
                    <td className="py-2 pr-3 text-neutral-700">{SOURCE_CLASS_LABEL[row.sourceClass]}</td>
                    <td className="py-2 pr-3">
                      <StatusBadge tone={COVERAGE_STATUS_TONE[row.coverageStatus]} label={row.coverageStatus.replace(/_/g, " ")} />
                    </td>
                    <td className="py-2 pr-3">{row.hasActiveProviderMapping ? <StatusBadge tone="success" label="mapped" /> : <StatusBadge tone="neutral" label="unmapped" />}</td>
                    <td className="py-2 pr-3 text-neutral-700">
                      {row.reservedWeightKg} / {row.capacityWeightKg ?? "—"}
                    </td>
                    <td className="py-2 pr-3 text-neutral-700">
                      {row.reservedVolumeCbm} / {row.capacityVolumeCbm ?? "—"}
                    </td>
                    <td className="py-2 pr-3 text-neutral-500">{row.lastPositionAt ? new Date(row.lastPositionAt).toLocaleString() : "—"}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
