/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the six Operations dashboard summaries resolve. */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function OperationsDashboardLoading() {
  return (
    <SkeletonText lines={3} label="Loading dashboard…" />
  );
}
