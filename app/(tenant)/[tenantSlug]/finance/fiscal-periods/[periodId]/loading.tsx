/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Fiscal Period detail query resolves. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function FiscalPeriodDetailLoading() {
  return <SkeletonText lines={6} label="Loading fiscal period…" />;
}
