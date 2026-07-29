/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Settlement queries resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function SettlementsLoading() {
  return <SkeletonTable rows={6} columns={9} label="Loading settlements…" />;
}
