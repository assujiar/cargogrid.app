/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the connection detail resolves. */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function IntegrationConnectionDetailLoading() {
  return <SkeletonText lines={3} label="Loading integration connection…" />;
}
