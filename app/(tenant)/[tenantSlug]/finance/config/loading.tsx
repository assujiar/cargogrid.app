/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Finance Configuration query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function FinanceConfigLoading() {
  return <SkeletonTable rows={3} columns={4} label="Loading Finance Configuration…" />;
}
