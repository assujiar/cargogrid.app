/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function LoyaltyFraudReviewAdminLoading() {
  return <SkeletonTable rows={6} columns={5} label="Loading the fraud review workbench…" />;
}
