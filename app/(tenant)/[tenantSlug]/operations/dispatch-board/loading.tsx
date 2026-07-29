/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the dispatch board query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function DispatchBoardLoading() {
  return <SkeletonTable rows={3} columns={8} label="Loading the dispatch board…" />;
}
