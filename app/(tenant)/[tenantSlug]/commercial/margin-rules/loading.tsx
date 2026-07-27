/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the margin-rules query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function MarginRulesLoading() {
  return (
    <SkeletonTable rows={2} columns={4} label="Loading margin rules…" />
  );
}
