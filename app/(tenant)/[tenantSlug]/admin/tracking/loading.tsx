/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the tracking package/source policy queries resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function TenantAdminTrackingLoading() {
  return <SkeletonTable rows={2} columns={4} label="Loading the tracking package and source policy…" />;
}
