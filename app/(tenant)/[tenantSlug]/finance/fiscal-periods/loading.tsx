/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Fiscal Period query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function FiscalPeriodsLoading() {
  return <SkeletonTable rows={4} columns={5} label="Loading fiscal periods…" />;
}
