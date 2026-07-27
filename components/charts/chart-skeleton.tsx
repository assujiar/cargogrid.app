/**
 * Chart-shaped loading skeleton (CargoGrid Chart System) -- built from the real
 * `Skeleton` primitive, matching the mission's own "skeletons should resemble the
 * final chart layout, avoid a generic spinner" rule.
 */

import { Skeleton } from "../ui/skeleton.tsx";

export function ChartSkeleton({ height = 280, label = "Loading chart…" }: { readonly height?: number | string; readonly label?: string }) {
  return (
    <div style={{ height }} aria-busy="true" aria-live="polite" className="flex items-end gap-2 p-4">
      {(["h-[40%]", "h-[70%]", "h-[50%]", "h-[90%]", "h-[60%]", "h-[80%]", "h-[45%]"] as const).map((heightClass, index) => (
        <Skeleton key={index} className={`flex-1 ${heightClass}`} />
      ))}
      <span className="sr-only">{label}</span>
    </div>
  );
}
