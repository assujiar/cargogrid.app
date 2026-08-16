/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../components/ui/skeleton.tsx";

export default function CustomerQuotesLoading() {
  return <SkeletonText lines={8} label="Loading your quote requests…" />;
}
