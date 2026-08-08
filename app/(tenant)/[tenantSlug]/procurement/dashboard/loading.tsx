/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the dashboard's own metric queries resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function ProcurementDashboardLoading() {
  return (
    <div className="flex flex-col gap-6">
      <SkeletonTable rows={4} columns={4} label="Loading the Procurement dashboard…" />
      <SkeletonTable rows={4} columns={4} label="Loading the Procurement dashboard…" />
      <SkeletonTable rows={4} columns={4} label="Loading the Procurement dashboard…" />
    </div>
  );
}
