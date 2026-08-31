/**
 * The visible half of `ISS-2026-238`.
 *
 * The finding is that four production routes loaded an entire tenant-wide dataset into the
 * browser with no cap. Adding a cap fixes the cost — and, on its own, creates a worse problem:
 * a reader who believes they are looking at all their accounts while looking at the newest 200.
 * A capped list without this notice would be a regression dressed as a fix.
 *
 * Deliberately plain about what to do next. "Showing the most recent 200" with no further
 * instruction leaves the reader stuck; naming the filter or search they can narrow with is the
 * part that makes the cap workable rather than merely honest.
 */
export function TruncationNotice({
  shown,
  noun,
  hint,
}: {
  shown: number;
  noun: string;
  hint?: string;
}) {
  return (
    <p
      role="status"
      className="rounded-md border border-status-warning-subtle bg-status-warning-subtle px-3 py-2 text-xs text-status-warning-strong"
    >
      Showing the {shown} most recent {noun}. There are more than this — {hint ?? "narrow the list with a search or filter to find a specific record"}.
    </p>
  );
}
