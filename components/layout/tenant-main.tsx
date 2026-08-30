import type { ReactNode } from "react";

/**
 * The `<main>` landmark for a tenant module, and the target of the skip link rendered by
 * `app/(tenant)/[tenantSlug]/layout.tsx`.
 *
 * Closes `ISS-2026-241`: 36 of the 38 tenant module trees had no `<main>` (or `role="main"`)
 * anywhere in their render tree, so a screen-reader user had nothing to jump to and had to
 * arrow through the repeated chrome on every page load — WCAG 2.2 AA 1.3.1 and 2.4.1.
 *
 * **Why this is a per-module component rather than one `<main>` in the shared tenant
 * layout**, which is what `ISS-2026-241` suggests: Next.js nests layouts parent-first, so a
 * `<main>` in `app/(tenant)/[tenantSlug]/layout.tsx` would contain the `<header>`/`<nav>`
 * that `admin/layout.tsx` and `commercial/layout.tsx` render for their own module. A site
 * navigation inside the main landmark defeats the landmark: the whole point of `<main>` is
 * to be what you skip *to*, past the navigation. So the shared tenant layout owns the skip
 * link, and each module owns its own `<main>` — placed after that module's own chrome,
 * wherever the chrome happens to be.
 *
 * `id="main-content"` is the anchor the skip link targets. Exactly one module layout renders
 * at a time, so the id is unique per page despite appearing in many files.
 *
 * `tabIndex={-1}` makes the element programmatically focusable so the skip link actually
 * moves focus rather than only scrolling — without it, Safari and some Firefox versions jump
 * the viewport but leave focus in the navigation, which is the bug that makes skip links
 * feel broken to the people who rely on them.
 */
export function TenantMain({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <main id="main-content" tabIndex={-1} className={className ?? "flex-1 px-6 py-6"}>
      {children}
    </main>
  );
}
