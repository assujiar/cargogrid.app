/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the prospects query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function ProspectsLoading() {
  return (
    <SkeletonTable rows={2} columns={3} label="Loading prospects…" />
  );
}
