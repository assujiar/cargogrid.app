/** Loading state (docs/standards/DESIGN_SYSTEM.md §4). */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function MyTrainingTalentLoading() {
  return <SkeletonText lines={8} label="Loading your training and development view…" />;
}
