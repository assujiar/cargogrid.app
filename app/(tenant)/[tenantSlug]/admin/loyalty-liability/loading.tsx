/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function LoyaltyLiabilityAdminLoading() {
  return <SkeletonTable rows={6} columns={7} label="Loading the liability reconciliation dashboard…" />;
}
