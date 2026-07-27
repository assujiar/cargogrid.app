/**
 * Skeleton primitive (`docs/design-system/02_COMPONENTS.md` "Skeleton", flips
 * `DOCUMENTED_ONLY` -> `IMPLEMENTED`). A loading placeholder matching a known layout --
 * replaces the 27 route-level `loading.tsx` files that each currently hand-roll their
 * own `animate-pulse` bars (`docs/design-system/08_COMPONENT_INVENTORY.md` §4). Respects
 * `prefers-reduced-motion` via Tailwind's `motion-reduce:animate-none`.
 */

export interface SkeletonProps {
  readonly className?: string;
  readonly "aria-hidden"?: boolean;
}

/** One placeholder bar/block. Compose several for a full-page skeleton (see `SkeletonText`/`SkeletonTable` below). */
export function Skeleton({ className, ...rest }: SkeletonProps) {
  return <div aria-hidden="true" className={`animate-pulse rounded bg-neutral-200 motion-reduce:animate-none ${className ?? ""}`} {...rest} />;
}

/** A stack of skeleton lines, matching a text block's rough shape. */
export function SkeletonText({ lines = 3, label = "Loading…" }: { readonly lines?: number; readonly label?: string }) {
  return (
    <div aria-busy="true" aria-live="polite" className="flex flex-col gap-2">
      <Skeleton className="h-6 w-24" />
      {Array.from({ length: lines }, (_, index) => (
        <Skeleton key={index} className="h-4 w-full" />
      ))}
      <span className="sr-only">{label}</span>
    </div>
  );
}

/** A skeleton matching `DataTable`'s own row shape -- for a route's `loading.tsx` that will render a `DataTable` once data resolves. */
export function SkeletonTable({ rows = 5, columns = 4, label = "Loading table…" }: { readonly rows?: number; readonly columns?: number; readonly label?: string }) {
  return (
    <div aria-busy="true" aria-live="polite" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <Skeleton className="h-4 w-32" />
      {Array.from({ length: rows }, (_, rowIndex) => (
        <div key={rowIndex} className="flex gap-3">
          {Array.from({ length: columns }, (_, columnIndex) => (
            <Skeleton key={columnIndex} className="h-4 flex-1" />
          ))}
        </div>
      ))}
      <span className="sr-only">{label}</span>
    </div>
  );
}
