/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the leads query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function LeadsLoading() {
  return (
    <SkeletonTable rows={3} columns={5} label="Loading leads…" />
  );
}
