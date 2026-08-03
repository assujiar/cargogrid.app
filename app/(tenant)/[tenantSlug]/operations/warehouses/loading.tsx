/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary while the warehouse/zone topology resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function WarehouseZoneLoading() {
  return <SkeletonTable rows={5} columns={5} label="Loading warehouses and zones…" />;
}
