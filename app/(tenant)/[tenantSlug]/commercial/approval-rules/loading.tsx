/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the approval-rules query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function ApprovalRulesLoading() {
  return (
    <SkeletonTable rows={2} columns={5} label="Loading approval rules…" />
  );
}
