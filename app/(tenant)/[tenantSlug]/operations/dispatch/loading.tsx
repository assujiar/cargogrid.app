/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the dispatch ready queue query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function DispatchQueueLoading() {
  return <SkeletonTable rows={2} columns={6} label="Loading the dispatch queue…" />;
}
