/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the tenants query resolves. */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function TenantsLoading() {
  return (
    <SkeletonTable rows={3} columns={3} label="Loading tenants…" />
  );
}
