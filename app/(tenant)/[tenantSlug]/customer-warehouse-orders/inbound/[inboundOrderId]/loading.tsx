/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function CustomerInboundOrderDetailLoading() {
  return <SkeletonTable rows={6} columns={6} label="Loading this inbound order…" />;
}
