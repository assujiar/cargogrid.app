/**
 * Spinner primitive (`docs/design-system/02_COMPONENTS.md` "Spinner") -- indeterminate
 * loading indicator. `docs/standards/DESIGN_SYSTEM.md`'s own identity statement says
 * "avoid spinners whenever possible" (prefer `Skeleton` matching the real layout) -- this
 * exists for the genuinely indeterminate case (e.g. an inline action's own busy state,
 * distinct from a page/section load), not as the default loading pattern.
 */

export function Spinner({ label = "Loading" }: { readonly label?: string }) {
  return (
    <span role="status" className="inline-flex items-center gap-2 text-sm text-text-secondary">
      <span
        aria-hidden="true"
        className="h-4 w-4 animate-spin rounded-full border-2 border-neutral-300 border-t-primary motion-reduce:animate-none"
      />
      <span className="sr-only">{label}</span>
    </span>
  );
}
