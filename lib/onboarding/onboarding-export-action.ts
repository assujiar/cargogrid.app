/**
 * Onboarding/Offboarding bulk-export plumbing (ISS-2026-070 item 3). Sibling of
 * `lib/recruitment/recruitment-export-action.ts` (ISS-2026-067 item 2), itself a
 * sibling of `lib/hris/hris-export-action.ts` (ISS-2026-075) -- same rationale:
 * pure and dependency-light so it can be unit-tested against a stub fetcher, and a
 * separate file per domain because each domain's own query layer throws its own
 * error class (`OnboardingQueryError` here), which the shared `rowsToSafeCsv`/
 * row-count/token-per-submission mechanism does not otherwise need to know about.
 *
 * `app.export_onboarding_cases` takes `p_status_filter`/`p_limit`, not a date range,
 * so this mirrors `buildRecruitmentExport`'s shape rather than `buildHrisExport`'s
 * (which forces a `fromDate`/`toDate` every one of ITS four exports actually takes).
 */

import { rowsToSafeCsv } from "../../server/policies/csv-export-sanitize.ts";
import { OnboardingQueryError } from "../../server/queries/onboarding.ts";

export interface OnboardingExportResult {
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

/** app.export_onboarding_cases raises insufficient_authority for a caller lacking HRS:Export -- distinguished here from a genuinely empty result. */
export function onboardingExportErrorMessage(error: unknown): string {
  if (error instanceof OnboardingQueryError) {
    if (error.message.startsWith("insufficient_authority")) {
      return "You don't have permission to export onboarding/offboarding data. Ask your administrator for the HR export permission.";
    }
    return "Something went wrong preparing this export. Please try again.";
  }
  return "Something went wrong preparing this export. Please try again.";
}

/**
 * Runs one export end to end: fetches, sanitises into CSV, and returns a state the
 * shared export-form component can render and download. `now` is injected rather than
 * read from the clock so the filename is testable.
 */
export async function buildOnboardingExport<TRow>(input: {
  readonly filenameStem: string;
  readonly header: readonly string[];
  readonly fetchRows: () => Promise<TRow[]>;
  readonly toCells: (row: TRow) => readonly (string | number | boolean | null | undefined)[];
  readonly now?: Date;
}): Promise<OnboardingExportResult> {
  const { filenameStem, header, fetchRows, toCells } = input;
  const now = input.now ?? new Date();

  let rows: TRow[];
  try {
    rows = await fetchRows();
  } catch (error) {
    return { error: onboardingExportErrorMessage(error), csv: null, filename: null, rowCount: 0, token: null };
  }

  const token = `${now.toISOString()}:${rows.length}`;

  if (rows.length === 0) {
    return { error: null, csv: null, filename: null, rowCount: 0, token };
  }

  const csv = rowsToSafeCsv(header, rows.map(toCells));
  const filename = `${safeStem(filenameStem)}-${now.toISOString().slice(0, 10)}.csv`;
  return { error: null, csv, filename, rowCount: rows.length, token };
}
