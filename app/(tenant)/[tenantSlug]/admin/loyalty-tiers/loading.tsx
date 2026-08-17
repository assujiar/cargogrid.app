/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function LoyaltyTierAdminLoading() {
  return <SkeletonTable rows={6} columns={4} label="Loading membership tier…" />;
}
