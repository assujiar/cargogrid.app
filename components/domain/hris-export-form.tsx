"use client";

/**
 * Shared HRIS bulk-export form (ISS-2026-075). One component for Attendance,
 * Shift/Roster, Leave and Overtime-Timesheet, because all four exports take the same
 * two dates, enforce the same `HRS:Export` gate and produce the same kind of file.
 * Four near-identical copies would be four places for the download plumbing and the
 * empty-result wording to drift apart.
 *
 * WHY THE SERVER ACTION RETURNS CSV TEXT RATHER THAN A FILE
 *
 *   A download has to be started by the browser. The Server Action does the work that
 *   must happen on the server -- authority, the RPC call, and the CSV sanitisation --
 *   and hands back a finished document; this component only turns that string into a
 *   file the browser saves. Nothing about the export decision happens here, so a reader
 *   of this file cannot mistake it for the gate.
 *
 * The CSV itself is built server-side with `rowsToSafeCsv`
 * (`server/policies/csv-export-sanitize.ts`), the OWASP formula-injection guard this
 * repository already owns -- never a second, ad-hoc join in the browser.
 */

import { useActionState, useEffect, useRef } from "react";
import { Button } from "../ui/button.tsx";

export interface HrisExportActionState {
  readonly error: string | null;
  /** The finished CSV document, or null when nothing was produced (an error, or a genuinely empty range). */
  readonly csv: string | null;
  readonly filename: string | null;
  /** Row count excluding the header, so the form can say "12 rows" rather than leaving the reader to open the file. */
  readonly rowCount: number;
  /** Changes on every completed submission, so re-exporting the same range downloads again instead of being swallowed as an unchanged result. */
  readonly token: string | null;
}

export const HRIS_EXPORT_INITIAL_STATE: HrisExportActionState = { error: null, csv: null, filename: null, rowCount: 0, token: null };

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function isoDaysAgo(days: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

export function HrisExportForm({
  label,
  description,
  action,
}: {
  /** What is being exported, e.g. "Export attendance sessions". */
  label: string;
  description: string;
  action: (prevState: HrisExportActionState, formData: FormData) => Promise<HrisExportActionState>;
}) {
  const [state, formAction, pending] = useActionState(action, HRIS_EXPORT_INITIAL_STATE);
  const downloadedToken = useRef<string | null>(null);

  useEffect(() => {
    if (!state.csv || !state.filename || !state.token) return;
    // Guarded by token rather than by content: two exports of the same range produce
    // an identical string, and the second one must still download.
    if (downloadedToken.current === state.token) return;
    downloadedToken.current = state.token;

    const blob = new Blob([state.csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = state.filename;
    link.click();
    URL.revokeObjectURL(url);
  }, [state]);

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">{label}</h2>
        <p className="mt-1 text-xs text-neutral-500">{description}</p>
      </div>

      <form action={formAction} className="flex flex-wrap items-end gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor={`${label}-fromDate`} className="text-xs font-medium text-neutral-600">
            From
          </label>
          <input
            id={`${label}-fromDate`}
            name="fromDate"
            type="date"
            required
            defaultValue={isoDaysAgo(30)}
            className="min-h-11 rounded border border-neutral-300 px-2 py-1 text-sm"
          />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor={`${label}-toDate`} className="text-xs font-medium text-neutral-600">
            To
          </label>
          <input id={`${label}-toDate`} name="toDate" type="date" required defaultValue={todayIso()} className="min-h-11 rounded border border-neutral-300 px-2 py-1 text-sm" />
        </div>
        <Button type="submit" loading={pending} loadingLabel="Preparing export…">
          Download CSV
        </Button>
      </form>

      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}

      {/* An empty export is stated as a result, not left as a silently empty file. It can
          only mean "no rows in this range" -- a caller without HRS:Export is refused
          before the RPC runs, with a different message. */}
      {!state.error && state.token && state.rowCount === 0 ? (
        <p role="status" className="text-xs text-neutral-500">
          No rows in that date range. Nothing was downloaded.
        </p>
      ) : null}

      {!state.error && state.token && state.rowCount > 0 ? (
        <p role="status" className="text-xs text-neutral-500">
          {state.rowCount} row{state.rowCount === 1 ? "" : "s"} exported to {state.filename}.
        </p>
      ) : null}
    </section>
  );
}
