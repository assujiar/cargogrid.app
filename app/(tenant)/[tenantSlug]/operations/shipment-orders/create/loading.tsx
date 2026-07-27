/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the Job Order/allocation-balance queries resolve. */
import { SkeletonText } from "../../../../../../components/ui/skeleton.tsx";

export default function CreateShipmentOrderLoading() {
  return <SkeletonText lines={2} label="Loading Shipment Order creation…" />;
}
