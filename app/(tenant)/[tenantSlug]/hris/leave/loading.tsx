/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function LeaveAdminLoading() {
  return <SkeletonText lines={6} label="Loading the leave workspace…" />;
}
