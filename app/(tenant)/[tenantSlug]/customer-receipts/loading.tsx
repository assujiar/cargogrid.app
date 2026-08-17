/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function CustomerReceiptsLoading() {
  return <SkeletonTable rows={8} columns={5} label="Loading your receipts…" />;
}
