/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function MyLeaveLoading() {
  return <SkeletonText lines={6} label="Loading your leave balances and requests…" />;
}
