/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while one schedule's own recipients/run history resolve. */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function ScheduledReportDetailLoading() {
  return <SkeletonText lines={4} label="Loading scheduled report…" />;
}
