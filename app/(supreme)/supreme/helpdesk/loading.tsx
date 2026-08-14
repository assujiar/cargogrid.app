/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4). */
import { SkeletonTable } from "../../../../components/ui/skeleton.tsx";

export default function SupremeHelpdeskLoading() {
  return <SkeletonTable rows={5} columns={6} label="Loading the CargoGrid support queue…" />;
}
