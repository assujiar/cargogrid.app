import Link from "next/link";
import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getTenantVehicleTrackingOverview, FleetControlTowerQueryError } from "../../../../../../server/queries/fleet-control-tower.ts";
import { listVehicleTelemetryHistory, listVehicleSourceHealth, listVehicleSourceSwitches, CanonicalTelemetryQueryError } from "../../../../../../server/queries/canonical-telemetry.ts";
import type { TenantVehicleTrackingOverviewRow } from "../../../../../../server/contracts/fleet-control-tower/fleet-control-tower.ts";
import type { CanonicalTelemetryEvent, VehicleSourceHealth, VehicleSourceSwitch, VehicleSourceHealthStatus } from "../../../../../../server/contracts/canonical-telemetry/canonical-telemetry.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";

const HEALTH_TONE: Record<VehicleSourceHealthStatus, StatusTone> = { healthy: "success", stale: "warning", offline: "danger", unknown: "neutral" };

/**
 * Vehicle detail (ATW-226H) -- one vehicle's own current position, per-source health, and
 * source-switch/telemetry history. Reuses ATW-226F's already-existing per-vehicle read
 * queries (server/queries/canonical-telemetry.ts) unchanged; the only new read here is
 * finding this one vehicle's row inside ATW-226H's own tenant-wide overview.
 */
export default async function VehicleControlTowerDetailPage({ params }: { params: Promise<{ tenantSlug: string; vehicleMasterId: string }> }) {
  const { tenantSlug, vehicleMasterId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const tenantId = access.tenant.id;

  let loadFailed = false;
  let vehicle: TenantVehicleTrackingOverviewRow | null = null;
  let history: CanonicalTelemetryEvent[] = [];
  let sourceHealth: VehicleSourceHealth[] = [];
  let sourceSwitches: VehicleSourceSwitch[] = [];
  try {
    const [overview, telemetryHistory, health, switches] = await Promise.all([
      getTenantVehicleTrackingOverview(supabase, { tenantId, actorAuthUserId: access.authUserId }),
      listVehicleTelemetryHistory(supabase, vehicleMasterId, null, 50),
      listVehicleSourceHealth(supabase, tenantId, vehicleMasterId),
      listVehicleSourceSwitches(supabase, vehicleMasterId, 20),
    ]);
    vehicle = overview.find((row) => row.vehicleMasterId === vehicleMasterId) ?? null;
    history = telemetryHistory;
    sourceHealth = health;
    sourceSwitches = switches;
  } catch (error) {
    if (!(error instanceof FleetControlTowerQueryError) && !(error instanceof CanonicalTelemetryQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">Vehicle detail</h1>
        <ErrorState description="Something went wrong loading this vehicle's tracking detail. Please try again." />
      </div>
    );
  }

  if (!vehicle) {
    notFound();
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <Link href={`/${tenantSlug}/operations/fleet-control-tower`} className="w-fit text-xs text-primary underline">
          ← Back to Fleet Control Tower
        </Link>
        <h1 className="text-xl font-semibold text-neutral-900">
          {vehicle.vehicleCode} — {vehicle.vehicleName}
        </h1>
      </div>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Current position</h2>
        {vehicle.currentLocation ? (
          <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm sm:grid-cols-4">
            <dt className="text-xs text-neutral-500">Source</dt>
            <dd className="text-neutral-900">{vehicle.currentSourceType ?? "—"}</dd>
            <dt className="text-xs text-neutral-500">Coordinates</dt>
            <dd className="text-neutral-900">
              {vehicle.currentLocation.coordinates[1].toFixed(5)}, {vehicle.currentLocation.coordinates[0].toFixed(5)}
            </dd>
            <dt className="text-xs text-neutral-500">Speed</dt>
            <dd className="text-neutral-900">{vehicle.currentSpeedKmh !== null ? `${vehicle.currentSpeedKmh.toFixed(0)} km/h` : "—"}</dd>
            <dt className="text-xs text-neutral-500">Heading</dt>
            <dd className="text-neutral-900">{vehicle.currentHeadingDegrees !== null ? `${vehicle.currentHeadingDegrees.toFixed(0)}°` : "—"}</dd>
            <dt className="text-xs text-neutral-500">Event time</dt>
            <dd className="text-neutral-900">{vehicle.currentEventAt ? new Date(vehicle.currentEventAt).toLocaleString() : "—"}</dd>
            <dt className="text-xs text-neutral-500">Received</dt>
            <dd className="text-neutral-900">{vehicle.currentReceivedAt ? new Date(vehicle.currentReceivedAt).toLocaleString() : "—"}</dd>
          </dl>
        ) : (
          <p className="text-sm text-neutral-500">This vehicle has never had a canonical position applied.</p>
        )}
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Source health</h2>
        {sourceHealth.length === 0 ? (
          <p className="text-sm text-neutral-500">No telemetry source has ever reported for this vehicle.</p>
        ) : (
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                <th className="py-2 pr-3 font-medium">Source</th>
                <th className="py-2 pr-3 font-medium">Status</th>
                <th className="py-2 pr-3 font-medium">Last event</th>
                <th className="py-2 pr-3 font-medium">Last received</th>
              </tr>
            </thead>
            <tbody>
              {sourceHealth.map((row) => (
                <tr key={row.sourceType} className="border-b border-neutral-100">
                  <td className="py-2 pr-3">{row.sourceType}</td>
                  <td className="py-2 pr-3">
                    <StatusBadge tone={HEALTH_TONE[row.status]} label={row.status} />
                  </td>
                  <td className="py-2 pr-3 text-neutral-500">{row.lastSeenEventAt ? new Date(row.lastSeenEventAt).toLocaleString() : "—"}</td>
                  <td className="py-2 pr-3 text-neutral-500">{row.lastSeenReceivedAt ? new Date(row.lastSeenReceivedAt).toLocaleString() : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Source switches</h2>
        {sourceSwitches.length === 0 ? (
          <p className="text-sm text-neutral-500">No source switch has been recorded for this vehicle.</p>
        ) : (
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                <th className="py-2 pr-3 font-medium">From</th>
                <th className="py-2 pr-3 font-medium">To</th>
                <th className="py-2 pr-3 font-medium">Reason</th>
                <th className="py-2 pr-3 font-medium">Switched at</th>
              </tr>
            </thead>
            <tbody>
              {sourceSwitches.map((row) => (
                <tr key={row.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-3">{row.fromSourceType ?? "—"}</td>
                  <td className="py-2 pr-3">{row.toSourceType}</td>
                  <td className="py-2 pr-3 text-neutral-500">{row.reason}</td>
                  <td className="py-2 pr-3 text-neutral-500">{new Date(row.switchedAt).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Recent telemetry (up to 50)</h2>
        {history.length === 0 ? (
          <p className="text-sm text-neutral-500">No canonical telemetry event exists yet for this vehicle.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                  <th className="py-2 pr-3 font-medium">Event time</th>
                  <th className="py-2 pr-3 font-medium">Source</th>
                  <th className="py-2 pr-3 font-medium">Coordinates</th>
                  <th className="py-2 pr-3 font-medium">Speed</th>
                  <th className="py-2 pr-3 font-medium">Applied</th>
                  <th className="py-2 pr-3 font-medium">Rejection reason</th>
                </tr>
              </thead>
              <tbody>
                {history.map((event) => (
                  <tr key={event.id} className="border-b border-neutral-100">
                    <td className="py-2 pr-3 text-neutral-500">{new Date(event.eventAt).toLocaleString()}</td>
                    <td className="py-2 pr-3">{event.sourceType}</td>
                    <td className="py-2 pr-3">{event.latitude !== null && event.longitude !== null ? `${event.latitude.toFixed(5)}, ${event.longitude.toFixed(5)}` : "—"}</td>
                    <td className="py-2 pr-3">{event.speedKmh !== null ? `${event.speedKmh.toFixed(0)} km/h` : "—"}</td>
                    <td className="py-2 pr-3">
                      <StatusBadge tone={event.appliedToCurrentPosition ? "success" : "neutral"} label={event.appliedToCurrentPosition ? "applied" : "not applied"} />
                    </td>
                    <td className="py-2 pr-3 text-neutral-500">{event.rejectionReason ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
