/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the report runs and its history resolve. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function ReportDetailLoading() {
  return (
    <SkeletonText lines={1} label="Loading report…" />
  );
}
