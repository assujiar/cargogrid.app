/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary while this vehicle's position, source health, source switches, and telemetry history resolve. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function VehicleControlTowerDetailLoading() {
  return <SkeletonTable rows={4} columns={4} label="Loading this vehicle's tracking detail…" />;
}
