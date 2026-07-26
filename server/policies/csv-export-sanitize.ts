/**
 * CSV formula-injection guard for Commercial report exports (COM-159, Prompt 158 §16/
 * §25: "prevent formula injection... sanitize cells"). Pure, disclosed-scoped primitive
 * -- no live export pipeline exists in this repository to generate a real file end to
 * end (see supabase/migrations/20260724330000_create_commercial_reports.sql's own
 * header), so this is the provable unit a future worker would call, not a claim that a
 * file has actually been produced and proven safe.
 *
 * Follows OWASP's CSV Injection guidance: a cell whose first character is one a
 * spreadsheet application would interpret as a formula/command trigger (=, +, -, @, a
 * tab, or a carriage return) is prefixed with a single leading apostrophe, which every
 * mainstream spreadsheet application renders as literal text, never evaluates.
 */

const FORMULA_TRIGGER_CHARS = new Set(["=", "+", "-", "@", "\t", "\r"]);

/** Neutralizes a single cell value against CSV/formula injection. Never mutates a value that does not start with a trigger character. */
export function sanitizeCsvCell(value: string): string {
  if (value.length === 0) {
    return value;
  }
  return FORMULA_TRIGGER_CHARS.has(value[0] as string) ? `'${value}` : value;
}

/** RFC 4180 field quoting: a field containing a comma, double quote, or newline is wrapped in double quotes, with any embedded double quote doubled. Applied after sanitizeCsvCell so a formula-neutralized leading apostrophe is preserved literally. */
export function quoteCsvField(value: string): string {
  if (/[",\n\r]/.test(value)) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}

/** Sanitizes and quotes one full row of cell values into a single CSV line (no trailing newline). */
export function rowToSafeCsvLine(cells: readonly (string | number | boolean | null | undefined)[]): string {
  return cells.map((cell) => quoteCsvField(sanitizeCsvCell(cell === null || cell === undefined ? "" : String(cell)))).join(",");
}

/** Sanitizes and joins a header row plus every data row into a complete CSV document, CRLF-terminated per RFC 4180. */
export function rowsToSafeCsv(header: readonly string[], rows: readonly (readonly (string | number | boolean | null | undefined)[])[]): string {
  const lines = [rowToSafeCsvLine(header), ...rows.map((row) => rowToSafeCsvLine(row))];
  return lines.join("\r\n") + "\r\n";
}
