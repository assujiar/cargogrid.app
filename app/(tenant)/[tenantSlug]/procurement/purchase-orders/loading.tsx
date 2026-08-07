/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the purchase order queue query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function PurchaseOrderQueueLoading() {
  return <SkeletonTable rows={6} columns={5} label="Loading the purchase order queue…" />;
}
