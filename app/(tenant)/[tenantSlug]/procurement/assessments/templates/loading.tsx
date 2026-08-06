/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the template list query resolves. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function VendorAssessmentTemplatesLoading() {
  return <SkeletonTable rows={6} columns={4} label="Loading assessment templates…" />;
}
