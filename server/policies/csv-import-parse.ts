/**
 * RFC 4180 CSV parser for import UIs (CG-AUDIT-2026-09-02 A4). Pairs with
 * `csv-export-sanitize.ts`'s own writer side -- this is the reader half no
 * import UI in this repository has ever needed until now. Deliberately does
 * NOT apply any formula-injection neutralization on read: a cell like `-5`
 * is a legitimate negative number on import, and the CSV-injection mitigation
 * belongs at export-time cell-writing, not import-time row-shape parsing
 * (the exact distinction `20260719170000_create_import_export_job_framework.sql`'s
 * own header draws for `app.sanitize_formula_injection`).
 *
 * Field quoting only (double-quote wrapping, doubled-quote escaping, embedded
 * commas/newlines inside quotes) -- no numeric/date coercion, since
 * `app.validate_staging_row`/the domain-specific row validator already do
 * that structural work server-side against the tenant's own published column
 * definition.
 */

export class CsvParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CsvParseError";
  }
}

function splitCsvLines(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;
  let i = 0;

  while (i < text.length) {
    const char = text[i];

    if (inQuotes) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i += 1;
        continue;
      }
      field += char;
      i += 1;
      continue;
    }

    if (char === '"') {
      inQuotes = true;
      i += 1;
      continue;
    }
    if (char === ",") {
      row.push(field);
      field = "";
      i += 1;
      continue;
    }
    if (char === "\r") {
      i += 1;
      continue;
    }
    if (char === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
      i += 1;
      continue;
    }
    field += char;
    i += 1;
  }

  if (inQuotes) {
    throw new CsvParseError("unterminated quoted field");
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

/** Parses a CSV document's first line as headers and every following non-blank line as one row, keyed by header. A row with a different column count than the header throws CsvParseError naming the 1-indexed line -- never silently drops or pads a misaligned row. */
export function parseCsvToRows(csvText: string): Record<string, string>[] {
  const lines = splitCsvLines(csvText).filter((line) => !(line.length === 1 && line[0] === ""));
  if (lines.length === 0) {
    throw new CsvParseError("the file is empty");
  }

  const header = lines[0] as string[];
  if (header.some((key) => key.trim().length === 0)) {
    throw new CsvParseError("the header row contains an empty column name");
  }

  const rows: Record<string, string>[] = [];
  for (let lineIndex = 1; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex] as string[];
    if (line.length !== header.length) {
      throw new CsvParseError(`line ${lineIndex + 1}: has ${line.length} column(s), expected ${header.length} (matching the header row)`);
    }
    const row: Record<string, string> = {};
    header.forEach((key, columnIndex) => {
      row[key] = line[columnIndex] as string;
    });
    rows.push(row);
  }

  return rows;
}
