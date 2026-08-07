/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the approval step detail query resolves. */
import { SkeletonText, SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function ProcurementApprovalStepDetailLoading() {
  return (
    <div className="flex flex-col gap-4">
      <SkeletonText lines={4} label="Loading decision context…" />
      <SkeletonTable rows={3} columns={4} label="Loading decision history…" />
    </div>
  );
}
