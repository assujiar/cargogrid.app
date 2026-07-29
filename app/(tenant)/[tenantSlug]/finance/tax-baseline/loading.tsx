/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Tax Baseline queries resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function TaxBaselineLoading() {
  return <SkeletonTable rows={4} columns={6} label="Loading tax rules…" />;
}
