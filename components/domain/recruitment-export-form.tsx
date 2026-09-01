"use client";

/**
 * Shared Recruitment/ATS bulk-export form (ISS-2026-067 item 2). Mirrors
 * `components/domain/hris-export-form.tsx`'s own shape exactly -- same
 * `useActionState` + blob-download interaction, same result-state contract, same
 * "nothing downloaded" / "N rows exported" messaging -- minus the date-range fields,
 * because none of the three recruitment export RPCs (`export_job_vacancies`/
 * `export_candidates`/`export_applications`) take one; see
 * `lib/recruitment/recruitment-export-action.ts`'s own header for why that helper is a
 * sibling of `buildHrisExport` rather than a forced reuse of it.
 *
 * The Server Action does the work that must happen on the server -- authority (the RPC's
 * own `HRS:Export` gate), the RPC call, and the CSV sanitisation -- and hands back a
 * finished document; this component only turns that string into a file the browser
 * saves.
 */

import { useActionState, useEffect, useRef } from "react";
import { Button } from "../ui/button.tsx";

export interface RecruitmentExportActionState {
  readonly error: string | null;
  readonly csv: string | null;
  readonly filename: string | null;
  readonly rowCount: number;
  readonly token: string | null;
}

export const RECRUITMENT_EXPORT_INITIAL_STATE: RecruitmentExportActionState = { error: null, csv: null, filename: null, rowCount: 0, token: null };

export function RecruitmentExportForm({
  label,
  description,
  action,
}: {
  /** What is being exported, e.g. "Export vacancies". */
  label: string;
  description: string;
  action: (prevState: RecruitmentExportActionState, formData: FormData) => Promise<RecruitmentExportActionState>;
}) {
  const [state, formAction, pending] = useActionState(action, RECRUITMENT_EXPORT_INITIAL_STATE);
  const downloadedToken = useRef<string | null>(null);

  useEffect(() => {
    if (!state.csv || !state.filename || !state.token) return;
    // Guarded by token rather than by content: two exports of the same filter produce
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

      <form action={formAction}>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Preparing export…">
          Download CSV
        </Button>
      </form>

      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}

      {/* An empty export is stated as a result, not left as a silently empty file. A
          caller without HRS:Export is refused before the RPC returns any rows, with a
          different message. */}
      {!state.error && state.token && state.rowCount === 0 ? (
        <p role="status" className="text-xs text-neutral-500">
          No rows to export. Nothing was downloaded.
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
