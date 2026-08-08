/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the vendor contract detail query resolves. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function VendorContractDetailLoading() {
  return <SkeletonTable rows={8} columns={5} label="Loading this vendor contract…" />;
}
