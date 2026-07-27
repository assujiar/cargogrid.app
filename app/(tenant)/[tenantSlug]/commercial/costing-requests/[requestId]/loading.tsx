/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the request/components/responses data resolves. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function CostingRequestDetailLoading() {
  return (
    <SkeletonText lines={2} label="Loading costing request…" />
  );
}
