/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function CustomerLoyaltyRewardDetailLoading() {
  return <SkeletonTable rows={5} columns={1} label="Loading this reward…" />;
}
