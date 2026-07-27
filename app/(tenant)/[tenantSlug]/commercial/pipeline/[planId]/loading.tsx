/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the plan/target/snapshot data resolves. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function SalesPlanDetailLoading() {
  return (
    <SkeletonText lines={2} label="Loading sales plan…" />
  );
}
