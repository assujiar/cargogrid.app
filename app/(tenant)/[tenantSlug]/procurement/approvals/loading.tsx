/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the procurement approvals workspace query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function ProcurementApprovalsLoading() {
  return (
    <div className="flex flex-col gap-4">
      <SkeletonTable rows={4} columns={4} label="Loading your pending approvals…" />
      <SkeletonTable rows={3} columns={5} label="Loading governed policies…" />
      <SkeletonTable rows={3} columns={5} label="Loading exception/override requests…" />
    </div>
  );
}
