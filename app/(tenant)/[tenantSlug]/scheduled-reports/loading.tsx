/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the schedule list resolves. */
import { SkeletonText } from "../../../../components/ui/skeleton.tsx";

export default function ScheduledReportsLoading() {
  return <SkeletonText lines={2} label="Loading scheduled reports…" />;
}
