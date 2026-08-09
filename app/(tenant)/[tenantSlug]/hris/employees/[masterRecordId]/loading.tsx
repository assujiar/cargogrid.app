/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary while the employee detail read resolves. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function EmployeeDetailLoading() {
  return (
    <div className="flex flex-col gap-4">
      <SkeletonText lines={2} label="Loading employee profile…" />
      <SkeletonText lines={6} label="Loading employee detail…" />
    </div>
  );
}
