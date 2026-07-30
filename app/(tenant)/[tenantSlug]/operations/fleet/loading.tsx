/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the fleet workspace queries resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function FleetLoading() {
  return <SkeletonTable rows={4} columns={5} label="Loading the fleet workspace…" />;
}
