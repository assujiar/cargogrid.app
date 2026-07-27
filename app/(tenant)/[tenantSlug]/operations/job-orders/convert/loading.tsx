/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the conversion review query resolves. */
import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function ConvertJobOrderLoading() {
  return <SkeletonTable rows={2} columns={5} label="Loading conversion review…" />;
}
