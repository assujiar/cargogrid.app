/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary while the utilization summary and coverage table resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function CapacityUtilizationLoading() {
  return <SkeletonTable rows={5} columns={7} label="Loading capacity and tracking coverage…" />;
}
