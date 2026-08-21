/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the cross-domain report catalogue/run history resolve. */
import { SkeletonText } from "../../../../components/ui/skeleton.tsx";

export default function ReportLibraryLoading() {
  return (
    <SkeletonText lines={2} label="Loading report library…" />
  );
}
