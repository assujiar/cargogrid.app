/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function CustomerInvoiceDetailLoading() {
  return <SkeletonTable rows={4} columns={4} label="Loading this invoice…" />;
}
