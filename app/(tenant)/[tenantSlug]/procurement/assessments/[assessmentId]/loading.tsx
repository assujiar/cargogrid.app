/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the assessment detail queries resolve. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function VendorAssessmentDetailLoading() {
  return <SkeletonTable rows={8} columns={4} label="Loading assessment detail…" />;
}
