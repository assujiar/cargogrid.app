/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function PayrollAdminLoading() {
  return <SkeletonText lines={10} label="Loading the payroll workspace…" />;
}
