/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Accounts Payable queries resolve. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function AccountsPayableLoading() {
  return <SkeletonTable rows={6} columns={7} label="Loading AP open items…" />;
}
