/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the report catalogue/run history resolve. */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function ReportsLoading() {
  return (
    <SkeletonText lines={2} label="Loading reports…" />
  );
}
