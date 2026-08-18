/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../components/ui/skeleton.tsx";

export default function CustomerPortalDashboardLoading() {
  return <SkeletonText lines={9} label="Loading your dashboard…" />;
}
