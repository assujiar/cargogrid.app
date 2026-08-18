/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function CustomerLoyaltyRedemptionsLoading() {
  return <SkeletonTable rows={4} columns={3} label="Loading your redemptions…" />;
}
