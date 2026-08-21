/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while API keys/versions/event types/logs resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function ApiKeysAdminLoading() {
  return <SkeletonTable rows={4} columns={5} label="Loading API keys…" />;
}
