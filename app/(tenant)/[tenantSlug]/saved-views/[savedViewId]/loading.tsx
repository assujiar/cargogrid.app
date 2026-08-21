/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while one saved view's own config resolves. */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function SavedReportViewDetailLoading() {
  return <SkeletonText lines={3} label="Loading saved view…" />;
}
