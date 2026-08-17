/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function CustomerLoyaltyBenefitsLoading() {
  return <SkeletonTable rows={4} columns={3} label="Loading your benefits…" />;
}
