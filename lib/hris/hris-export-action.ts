/**
 * Shared plumbing for the four HRIS bulk-export Server Actions (ISS-2026-075).
 *
 * Pure and dependency-light on purpose: it takes an already-resolved fetcher and a
 * cell mapper, so it can be unit-tested against a stub without a Supabase client, a
 * request, or a running Next.js. The four `actions.ts` files supply the access check
 * and the fetcher; everything below is the part that would otherwise have been copied
 * four times -- date parsing, CSV assembly, filename, and the error-to-message mapping
 * that decides what a person actually reads when an export fails.
 */

import { rowsToSafeCsv } from "../../server/policies/csv-export-sanitize.ts";
import { HrisExportQueryError } from "../../server/queries/hris-export.ts";

export interface HrisExportResult {
  readonly error: string | null;
  readonly csv: string | null;
  readonly filename: string | null;
  readonly rowCount: number;
  readonly token: string | null;
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/** Filenames end up in a shared folder, so the stem is constrained rather than trusted. */
function safeStem(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]+/g, "-").replace(/(^-|-$)/g, "") || "export";
}

/**
 * Maps a thrown export error onto something a person can act on. `insufficient_authority`
 * is spelled out rather than folded into a generic failure, because distinguishing it
 * from an empty result is the entire reason `assertHrisExportAuthority` exists -- see
 * `server/queries/hris-export.ts`'s own header.
 */
export function hrisExportErrorMessage(error: unknown): string {
  if (error instanceof HrisExportQueryError) {
    switch (error.code) {
      case "insufficient_authority":
        return "You don't have permission to export HR data. Ask your administrator for the HR export permission.";
      case "invalid_date_range":
        return error.message.split(":").slice(1).join(":").trim() || "That date range is not valid.";
      case "actor_identity_mismatch":
        return "Your session no longer matches the identity this export was requested for. Sign in again and retry.";
      default:
        return "Something went wrong preparing this export. Please try again.";
    }
  }
  return "Something went wrong preparing this export. Please try again.";
}

/**
 * Runs one export end to end: validates the two dates, fetches, sanitises into CSV, and
 * returns a state the shared form can render and download.
 *
 * `now` is injected rather than read from the clock so the filename is testable.
 */
export async function buildHrisExport<TRow>(input: {
  readonly fromDate: string;
  readonly toDate: string;
  readonly filenameStem: string;
  readonly header: readonly string[];
  readonly fetchRows: (range: { fromDate: string; toDate: string }) => Promise<TRow[]>;
  readonly toCells: (row: TRow) => readonly (string | number | boolean | null | undefined)[];
  readonly now?: Date;
}): Promise<HrisExportResult> {
  const { fromDate, toDate, filenameStem, header, fetchRows, toCells } = input;
  const now = input.now ?? new Date();

  if (!DATE_RE.test(fromDate) || !DATE_RE.test(toDate)) {
    return { error: "Pick both a from-date and a to-date.", csv: null, filename: null, rowCount: 0, token: null };
  }

  let rows: TRow[];
  try {
    rows = await fetchRows({ fromDate, toDate });
  } catch (error) {
    return { error: hrisExportErrorMessage(error), csv: null, filename: null, rowCount: 0, token: null };
  }

  // The token, not the content, is what makes a repeat export of the same range download
  // again -- two identical ranges produce a byte-identical file, and the second request
  // must still reach the browser.
  const token = `${now.toISOString()}:${rows.length}`;

  if (rows.length === 0) {
    // Deliberately no file: handing someone an empty spreadsheet is a worse answer than
    // telling them the range was empty. A caller lacking HRS:Export never reaches here --
    // they were refused above, with a different message.
    return { error: null, csv: null, filename: null, rowCount: 0, token };
  }

  const csv = rowsToSafeCsv(header, rows.map(toCells));
  const filename = `${safeStem(filenameStem)}-${fromDate}-to-${toDate}.csv`;
  return { error: null, csv, filename, rowCount: rows.length, token };
}
