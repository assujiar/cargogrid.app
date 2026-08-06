/** Loading state (docs/standards/DESIGN_SYSTEM.md §4) -- Next's own Suspense boundary for this route segment while the document/version-viewer query resolves. */
import { Skeleton } from "../../../../../../../../../components/ui/skeleton.tsx";

export default function VendorComplianceDocumentVersionsLoading() {
  return (
    <div aria-busy="true" aria-live="polite" className="flex flex-col gap-4">
      <Skeleton className="h-6 w-64" />
      <Skeleton className="h-24 w-full" />
      <Skeleton className="h-24 w-full" />
    </div>
  );
}
