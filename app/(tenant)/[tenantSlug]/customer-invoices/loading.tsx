/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function CustomerInvoicesLoading() {
  return <SkeletonTable rows={8} columns={6} label="Loading your invoices…" />;
}
