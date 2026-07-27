/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Job Orders query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function JobOrdersLoading() {
  return <SkeletonTable rows={2} columns={5} label="Loading Job Orders…" />;
}
