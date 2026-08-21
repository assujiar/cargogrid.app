/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while account scope/API keys resolve. */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function CustomerPortalApiKeysLoading() {
  return <SkeletonTable rows={3} columns={5} label="Loading API keys…" />;
}
