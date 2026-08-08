/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the vendor capacity offer detail query resolves. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function VendorCapacityOfferDetailLoading() {
  return <SkeletonTable rows={8} columns={5} label="Loading this vendor capacity offer…" />;
}
