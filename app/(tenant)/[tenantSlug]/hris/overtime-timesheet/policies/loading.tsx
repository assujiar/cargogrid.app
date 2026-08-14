/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function OvertimePoliciesLoading() {
  return <SkeletonText lines={8} label="Loading overtime policies…" />;
}
