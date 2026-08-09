/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the employee directory query resolves. */
import { SkeletonTable } from "../../../../../components/ui/skeleton.tsx";

export default function EmployeeDirectoryLoading() {
  return <SkeletonTable rows={8} columns={6} label="Loading the employee directory…" />;
}
