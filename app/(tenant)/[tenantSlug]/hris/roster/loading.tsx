/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function RosterAdminLoading() {
  return <SkeletonText lines={12} label="Loading the roster workspace…" />;
}
