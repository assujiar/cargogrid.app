/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the opportunity/stage-history/readiness data resolves. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function OpportunityDetailLoading() {
  return (
    <SkeletonText lines={2} label="Loading opportunity…" />
  );
}
