/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the planning workspace query resolves. */
import { SkeletonTable } from "../../../../../../../components/ui/skeleton.tsx";

export default function RoutePlanningLoading() {
  return <SkeletonTable rows={4} columns={4} label="Loading the route and load planning workspace…" />;
}
