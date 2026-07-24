/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the quotation detail resolves. */
export default function QuotationDetailLoading() {
  return (
    <div aria-busy="true" aria-live="polite" className="flex flex-col gap-2">
      <div className="h-6 w-32 animate-pulse rounded bg-neutral-200" />
      <div className="h-4 w-full animate-pulse rounded bg-neutral-100" />
      <div className="h-4 w-full animate-pulse rounded bg-neutral-100" />
      <span className="sr-only">Loading quotation…</span>
    </div>
  );
}
