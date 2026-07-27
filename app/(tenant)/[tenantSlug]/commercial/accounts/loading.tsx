/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the accounts query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function AccountsLoading() {
  return (
    <SkeletonTable rows={2} columns={4} label="Loading accounts…" />
  );
}
