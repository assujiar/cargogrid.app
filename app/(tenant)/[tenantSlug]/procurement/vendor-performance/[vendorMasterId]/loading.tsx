/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the vendor performance detail queries resolve. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function VendorPerformanceDetailLoading() {
  return <SkeletonTable rows={8} columns={4} label="Loading this vendor's performance record…" />;
}
