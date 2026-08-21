/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the rule detail resolves. */
import { SkeletonText } from "../../../../../components/ui/skeleton.tsx";

export default function AutomationRuleDetailLoading() {
  return <SkeletonText lines={3} label="Loading automation rule…" />;
}
