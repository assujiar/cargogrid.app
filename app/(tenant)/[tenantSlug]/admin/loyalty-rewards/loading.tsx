/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function LoyaltyRewardsAdminLoading() {
  return <SkeletonTable rows={6} columns={5} label="Loading the reward catalogue…" />;
}
