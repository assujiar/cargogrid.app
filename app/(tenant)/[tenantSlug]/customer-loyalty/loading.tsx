/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function CustomerLoyaltyLoading() {
  return <SkeletonTable rows={6} columns={4} label="Loading your loyalty program…" />;
}
