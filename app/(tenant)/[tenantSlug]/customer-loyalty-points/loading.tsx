/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function CustomerLoyaltyPointsLoading() {
  return <SkeletonTable rows={5} columns={3} label="Loading your points balance…" />;
}
