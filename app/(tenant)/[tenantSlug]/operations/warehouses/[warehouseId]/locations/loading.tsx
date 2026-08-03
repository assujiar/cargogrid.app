/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary while one level of the location topology resolves. */
import { SkeletonTable } from "../../../../../../../components/ui/skeleton.tsx";

export default function WarehouseLocationsLoading() {
  return <SkeletonTable rows={5} columns={7} label="Loading bin and racking locations…" />;
}
