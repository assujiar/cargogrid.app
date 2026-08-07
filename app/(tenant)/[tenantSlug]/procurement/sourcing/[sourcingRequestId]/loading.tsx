/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the sourcing request + candidate longlist + history resolve. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function SourcingRequestDetailLoading() {
  return <SkeletonTable rows={5} columns={5} label="Loading the sourcing request…" />;
}
