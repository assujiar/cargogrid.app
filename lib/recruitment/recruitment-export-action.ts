/**
 * Shared Recruitment/ATS bulk-export plumbing (ISS-2026-067 item 2). Same rationale as
 * `lib/hris/hris-export-action.ts` (ISS-2026-075) -- pure and dependency-light so it can
 * be unit-tested against a stub fetcher, and shared by the three export Server Actions
 * (`export_job_vacancies`, `export_candidates`, `export_applications`) rather than
 * copied three times.
 *
 * Deliberately NOT `buildHrisExport` reused directly: that helper's contract is a
 * `fromDate`/`toDate` range, because all four HRIS exports it serves are date-ranged.
 * None of the three recruitment export RPCs take a date range (`p_status_filter`/
 * `p_vacancy_id` instead) -- reusing it here would mean inventing fake dates just to
 * satisfy an unrelated validation branch. What IS reused, unchanged, is the actual
 * shared mechanism underneath both: `rowsToSafeCsv` (the OWASP formula-injection guard),
 * the row-count/empty-result contract, and the token-per-submission download-dedup
 * contract `components/domain/hris-export-form.tsx` established -- this file's sibling
 * `components/domain/recruitment-export-form.tsx` mirrors that component's shape
 * exactly, minus the date fields neither RPC accepts.
 */

import { rowsToSafeCsv } from "../../server/policies/csv-export-sanitize.ts";
import { RecruitmentQueryError } from "../../server/queries/recruitment.ts";

export interface RecruitmentExportResult {
  readonly error: string | null;
  readonly csv: string | null;
  readonly filename: string | null;
  readonly rowCount: number;
  readonly token: string | null;
}

/** Filenames end up in a shared folder, so the stem is constrained rather than trusted. */
function safeStem(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]+/g, "-").replace(/(^-|-$)/g, "") || "export";
}

/**
 * Maps a thrown export error onto something a person can act on. Every one of the
 * three RPCs raises `insufficient_authority` for a caller lacking `HRS:Export`
 * (confirmed live: `app.export_job_vacancies`/`app.export_candidates`/
 * `app.export_applications`, `supabase/migrations/20260730860000_...sql` lines
 * 2913-2915/3023-3025/3173-3175) -- distinguished here from a genuinely empty result,
 * the same reason `hrisExportErrorMessage` exists.
 */
export function recruitmentExportErrorMessage(error: unknown): string {
  if (error instanceof RecruitmentQueryError) {
    if (error.message.startsWith("insufficient_authority")) {
      return "You don't have permission to export recruitment data. Ask your administrator for the HR export permission.";
    }
    return "Something went wrong preparing this export. Please try again.";
  }
  return "Something went wrong preparing this export. Please try again.";
}

/**
 * Runs one export end to end: fetches, sanitises into CSV, and returns a state the
 * shared `RecruitmentExportForm` can render and download. `now` is injected rather than
 * read from the clock so the filename is testable.
 */
export async function buildRecruitmentExport<TRow>(input: {
  readonly filenameStem: string;
  readonly header: readonly string[];
  readonly fetchRows: () => Promise<TRow[]>;
  readonly toCells: (row: TRow) => readonly (string | number | boolean | null | undefined)[];
  readonly now?: Date;
}): Promise<RecruitmentExportResult> {
  const { filenameStem, header, fetchRows, toCells } = input;
  const now = input.now ?? new Date();

  let rows: TRow[];
  try {
    rows = await fetchRows();
  } catch (error) {
    return { error: recruitmentExportErrorMessage(error), csv: null, filename: null, rowCount: 0, token: null };
  }

  // The token, not the content, is what makes a repeat export download again -- two
  // identical exports produce a byte-identical file, and the second request must still
  // reach the browser.
  const token = `${now.toISOString()}:${rows.length}`;

  if (rows.length === 0) {
    // Deliberately no file: handing someone an empty spreadsheet is a worse answer than
    // telling them there was nothing to export. A caller lacking HRS:Export never
    // reaches here -- the RPC itself raises `insufficient_authority` first.
    return { error: null, csv: null, filename: null, rowCount: 0, token };
  }

  const csv = rowsToSafeCsv(header, rows.map(toCells));
  const filename = `${safeStem(filenameStem)}-${now.toISOString().slice(0, 10)}.csv`;
  return { error: null, csv, filename, rowCount: rows.length, token };
}
