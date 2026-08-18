/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../components/ui/skeleton.tsx";

export default function CustomerProfileLoading() {
  return <SkeletonText lines={10} label="Loading your company profile…" />;
}
