/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the pipeline summary/plan list resolve. */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function PipelineLoading() {
  return (
    <SkeletonText lines={2} label="Loading pipeline…" />
  );
}
