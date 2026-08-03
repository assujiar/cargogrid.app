/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary while the vehicle overview, milestone candidate, and exception signal queues resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function FleetControlTowerLoading() {
  return <SkeletonTable rows={5} columns={6} label="Loading the fleet control tower…" />;
}
