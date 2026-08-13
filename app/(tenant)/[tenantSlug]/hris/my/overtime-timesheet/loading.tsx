/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function MyOvertimeTimesheetLoading() {
  return <SkeletonText lines={10} label="Loading your overtime and timesheet workspace…" />;
}
