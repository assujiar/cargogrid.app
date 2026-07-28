/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Chart of Accounts query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function ChartOfAccountsLoading() {
  return <SkeletonTable rows={5} columns={5} label="Loading Chart of Accounts…" />;
}
