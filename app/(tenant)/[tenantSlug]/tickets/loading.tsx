/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../components/ui/skeleton.tsx";

export default function TicketsListLoading() {
  return <SkeletonText lines={8} label="Loading the ticketing workspace…" />;
}
