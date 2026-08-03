import Link from "next/link";
import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getTenantVehicleTrackingOverview, getTenantPendingMilestoneCandidates, getTenantPendingExceptionSignals, FleetControlTowerQueryError } from "../../../../../server/queries/fleet-control-tower.ts";
import type {
  TenantVehicleTrackingOverviewRow,
  TenantPendingMilestoneCandidateRow,
  TenantPendingExceptionSignalRow,
} from "../../../../../server/contracts/fleet-control-tower/fleet-control-tower.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { VehicleMap } from "./vehicle-map.tsx";
import { MilestoneCandidatesPanel, ExceptionSignalsPanel } from "./signals-panel.tsx";
import { confirmMilestoneCandidateAction, dismissMilestoneCandidateAction, confirmExceptionSignalAction, dismissExceptionSignalAction } from "./actions.ts";

/**
 * Fleet Control Tower (ATW-226H, closing Prompt 226's Advanced TMS/WMS GPS Tracking &
 * Live Location decomposition). Tenant-wide live vehicle map (app.get_tenant_vehicle_
 * tracking_overview) plus the pending milestone-candidate/exception-signal review queues
 * (ATW-226G's own staged-signal design, app.get_tenant_pending_milestone_candidates/app.
 * get_tenant_pending_exception_signals) -- the sole UI where a dispatcher confirms or
 * dismisses a derived signal into a real milestone event / operational exception.
 */
export default async function FleetControlTowerPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const tenantId = access.tenant.id;

  let loadFailed = false;
  let vehicles: TenantVehicleTrackingOverviewRow[] = [];
  let milestoneCandidates: TenantPendingMilestoneCandidateRow[] = [];
  let exceptionSignals: TenantPendingExceptionSignalRow[] = [];
  try {
    const [overview, candidates, signals] = await Promise.all([
      getTenantVehicleTrackingOverview(supabase, { tenantId, actorAuthUserId: access.authUserId }),
      getTenantPendingMilestoneCandidates(supabase, { tenantId, actorAuthUserId: access.authUserId }),
      getTenantPendingExceptionSignals(supabase, { tenantId, actorAuthUserId: access.authUserId }),
    ]);
    vehicles = overview;
    milestoneCandidates = candidates;
    exceptionSignals = signals;
  } catch (error) {
    if (!(error instanceof FleetControlTowerQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">Fleet Control Tower</h1>
        <ErrorState description="Something went wrong loading the fleet control tower. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Fleet Control Tower</h1>
        <p className="text-xs text-neutral-500">Live vehicle positions and pending derived-signal review, tenant-wide.</p>
      </div>

      <VehicleMap vehicles={vehicles} />

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Vehicles</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                <th className="py-2 pr-3 font-medium">Vehicle</th>
                <th className="py-2 pr-3 font-medium">Eligible sources</th>
                <th className="py-2 pr-3 font-medium">Current source</th>
                <th className="py-2 pr-3 font-medium">Speed</th>
                <th className="py-2 pr-3 font-medium">Last event</th>
                <th className="py-2 pr-3 font-medium">Detail</th>
              </tr>
            </thead>
            <tbody>
              {vehicles.length === 0 ? (
                <tr>
                  <td colSpan={6} className="py-3 text-sm text-neutral-500">
                    No vehicles registered yet.
                  </td>
                </tr>
              ) : (
                vehicles.map((vehicle) => (
                  <tr key={vehicle.vehicleMasterId} className="border-b border-neutral-100">
                    <td className="py-2 pr-3">
                      <div className="font-medium text-neutral-900">{vehicle.vehicleCode}</div>
                      <div className="text-xs text-neutral-500">{vehicle.vehicleName}</div>
                    </td>
                    <td className="py-2 pr-3">
                      <div className="flex flex-wrap gap-1">
                        {vehicle.mobileTrackingEligible ? <StatusBadge tone="info" label="mobile" /> : null}
                        {vehicle.directDeviceTrackingEligible ? <StatusBadge tone="info" label="device" /> : null}
                        {vehicle.thirdPartyTrackingEligible ? <StatusBadge tone="info" label="third-party" /> : null}
                      </div>
                    </td>
                    <td className="py-2 pr-3">
                      {vehicle.currentSourceType ? <StatusBadge tone="success" label={vehicle.currentSourceType} /> : <StatusBadge tone="neutral" label="never tracked" />}
                    </td>
                    <td className="py-2 pr-3 text-neutral-700">{vehicle.currentSpeedKmh !== null ? `${vehicle.currentSpeedKmh.toFixed(0)} km/h` : "—"}</td>
                    <td className="py-2 pr-3 text-neutral-500">{vehicle.currentEventAt ? new Date(vehicle.currentEventAt).toLocaleString() : "—"}</td>
                    <td className="py-2 pr-3">
                      <Link href={`/${tenantSlug}/operations/fleet-control-tower/${vehicle.vehicleMasterId}`} className="text-primary underline">
                        View
                      </Link>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>

      <MilestoneCandidatesPanel
        candidates={milestoneCandidates}
        confirmActionFor={(candidateId) => confirmMilestoneCandidateAction.bind(null, tenantSlug, candidateId)}
        dismissActionFor={(candidateId) => dismissMilestoneCandidateAction.bind(null, tenantSlug, candidateId)}
      />

      <ExceptionSignalsPanel
        signals={exceptionSignals}
        confirmActionFor={(signalId) => confirmExceptionSignalAction.bind(null, tenantSlug, signalId)}
        dismissActionFor={(signalId) => dismissExceptionSignalAction.bind(null, tenantSlug, signalId)}
      />
    </div>
  );
}
