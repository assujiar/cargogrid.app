/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while one dashboard's versions/widgets resolve. */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function DashboardBuilderDetailLoading() {
  return <SkeletonText lines={4} label="Loading dashboard…" />;
}
