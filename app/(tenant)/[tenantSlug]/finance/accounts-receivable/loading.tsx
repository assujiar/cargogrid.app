/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Accounts Receivable queries resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function AccountsReceivableLoading() {
  return <SkeletonTable rows={6} columns={7} label="Loading AR open items…" />;
}
