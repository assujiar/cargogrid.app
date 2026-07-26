/** Loading state (`docs/standards/DESIGN_SYSTEM.md` §4) -- Next's own Suspense boundary for this route segment while the report runs and its history resolve. */
export default function ReportDetailLoading() {
  return (
    <div aria-busy="true" aria-live="polite" className="flex flex-col gap-2">
      <div className="h-6 w-40 animate-pulse rounded bg-neutral-200" />
      <div className="h-32 w-full animate-pulse rounded bg-neutral-100" />
      <span className="sr-only">Loading report…</span>
    </div>
  );
}
