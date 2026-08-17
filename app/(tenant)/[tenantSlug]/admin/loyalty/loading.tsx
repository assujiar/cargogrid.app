/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while loyalty programs/rule versions/accounts/earning events resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function LoyaltyAdminLoading() {
  return <SkeletonTable rows={4} columns={3} label="Loading loyalty programs…" />;
}
