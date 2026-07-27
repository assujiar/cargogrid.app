/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the approval inbox query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function ApprovalsInboxLoading() {
  return (
    <SkeletonTable rows={2} columns={3} label="Loading approvals…" />
  );
}
