/**
 * "Skip to main content" — the bypass mechanism WCAG 2.2 AA 2.4.1 requires, and the reason
 * `TenantMain` exists to be skipped *to*.
 *
 * Visually hidden until focused, then it appears at the top-left. That is deliberate: a
 * permanently visible skip link is the usual first casualty of a design review, and a
 * permanently *hidden* one (`display: none`) is not focusable and therefore does nothing at
 * all. The clip-based pattern below is focusable while taking no visual space, which is the
 * only version that both survives and works.
 *
 * Part of the `ISS-2026-241` fix.
 */
export function SkipToContentLink() {
  return (
    <a
      href="#main-content"
      className="sr-only rounded-b bg-primary px-4 py-2 text-sm font-medium text-white focus:not-sr-only focus:absolute focus:left-2 focus:top-0 focus:z-50"
    >
      Skip to main content
    </a>
  );
}
