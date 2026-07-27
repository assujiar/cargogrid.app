/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the rate-version query resolves. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function RateVersionLoading() {
  return (
    <SkeletonText lines={2} label="Loading rate version…" />
  );
}
