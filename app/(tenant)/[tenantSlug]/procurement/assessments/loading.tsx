/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the assessment queue query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function VendorAssessmentQueueLoading() {
  return <SkeletonTable rows={6} columns={5} label="Loading the assessment queue…" />;
}
