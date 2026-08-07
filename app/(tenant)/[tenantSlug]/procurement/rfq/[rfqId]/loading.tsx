/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the RFQ detail query resolves. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function RfqDetailLoading() {
  return <SkeletonText lines={10} label="Loading the RFQ…" />;
}
