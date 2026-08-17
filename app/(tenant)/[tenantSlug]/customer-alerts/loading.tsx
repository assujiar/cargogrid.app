/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../components/ui/skeleton.tsx";

export default function CustomerAlertsLoading() {
  return <SkeletonText lines={8} label="Loading your alerts…" />;
}
