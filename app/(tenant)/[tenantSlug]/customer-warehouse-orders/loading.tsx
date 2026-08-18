/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function CustomerWarehouseOrdersLoading() {
  return <SkeletonTable rows={8} columns={7} label="Loading your warehouse orders…" />;
}
