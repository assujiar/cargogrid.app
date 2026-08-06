/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the vendor rate + tier detail resolves. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function ProcurementRateDetailLoading() {
  return <SkeletonTable rows={4} columns={5} label="Loading the vendor rate…" />;
}
