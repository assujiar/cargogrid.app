/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the analytics view registry/usage data resolve. */
import { SkeletonText } from "../../../../components/ui/skeleton.tsx";

export default function AnalyticsLoading() {
  return <SkeletonText lines={3} label="Loading analytics…" />;
}
