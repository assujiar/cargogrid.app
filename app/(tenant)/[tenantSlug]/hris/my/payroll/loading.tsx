/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function MyPayrollLoading() {
  return <SkeletonText lines={8} label="Loading your payslips and benefits…" />;
}
