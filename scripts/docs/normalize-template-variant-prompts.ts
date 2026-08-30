/**
 * Closes `FPV-F003` and `FPV-F004` under `ADR-0028`.
 *
 * 14 capability prompts carry every body line indented four spaces, so Markdown renders the
 * whole prompt — metadata, all 36 headings, every table — as one preformatted code block.
 * The content is intact; the structure is invisible to a reader and to every parser. The same
 * 14 use an older wording for five of the 36 field headings.
 *
 * Both are mechanical. That is exactly why they are dangerous: 14 files and 504 headings is
 * enough surface for a transcription error to corrupt the package that Step 17 just certified,
 * and "I read the diff and it looked fine" is not a proof for a change of that shape.
 *
 * So this script does two things, and the second matters more than the first:
 *
 *   1. Applies the transform.
 *   2. **Proves the result is content-identical to the original** modulo exactly two permitted
 *      differences — the leading four spaces, and the five known heading strings. Any third
 *      kind of difference aborts before anything is written.
 *
 * Run:  node --experimental-strip-types scripts/docs/normalize-template-variant-prompts.ts [--write]
 * Without `--write` it reports what it would do and changes nothing.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { KNOWN_TEMPLATE_VARIANT_FILES, LEGACY_HEADING_VARIANTS, REQUIRED_PROMPT_HEADINGS } from "./check-prompt-package.ts";

const PACKAGE_ROOT = "docs/ai-agent-build-prompt-package";
const INDENT = "    ";

export interface NormalizeResult {
  readonly file: string;
  readonly linesDeindented: number;
  readonly headingsRenamed: number;
  readonly changed: boolean;
}

/**
 * The canonical wording for a legacy heading, looked up by field number.
 *
 * REQUIRED_PROMPT_HEADINGS is the single source of truth for canonical wording — deriving
 * from it rather than restating the five strings means this script cannot drift from the
 * validator that will enforce the result.
 */
export function canonicalHeadingFor(fieldNumber: number): string {
  const canonical = REQUIRED_PROMPT_HEADINGS.find((h) => h.startsWith(`${fieldNumber}. `));
  if (!canonical) {
    throw new Error(`no canonical heading for field ${fieldNumber} in REQUIRED_PROMPT_HEADINGS`);
  }
  return canonical;
}

/** Strips exactly one leading four-space indent from every line that carries one. */
export function deindent(content: string): { readonly text: string; readonly count: number } {
  let count = 0;
  const text = content
    .split("\n")
    .map((line) => {
      if (line.startsWith(INDENT)) {
        count += 1;
        return line.slice(INDENT.length);
      }
      return line;
    })
    .join("\n");
  return { text, count };
}

/** Replaces each legacy `## N. …` heading with its canonical wording. */
export function canonicalizeHeadings(content: string): { readonly text: string; readonly count: number } {
  let count = 0;
  let text = content;
  for (const [fieldNumber, legacy] of Object.entries(LEGACY_HEADING_VARIANTS)) {
    const canonical = canonicalHeadingFor(Number(fieldNumber));
    if (canonical === legacy) continue;
    const marker = `## ${legacy}`;
    if (text.includes(marker)) {
      text = text.split(marker).join(`## ${canonical}`);
      count += 1;
    }
  }
  return { text, count };
}

/**
 * The proof.
 *
 * Reduces both texts to a form in which the two permitted differences are erased, and
 * requires the results to be byte-identical. If the transform dropped a table row, mangled a
 * character, or reflowed anything, the reduced forms diverge and this returns a reason.
 *
 * Deliberately not a diff-and-eyeball: the whole point is that no human reads 14 files
 * closely enough to catch a single lost character, and a machine reads all of them the same
 * way every time.
 */
export function verifyOnlyPermittedDifferences(original: string, transformed: string): string | null {
  const reduce = (text: string): string => {
    let reduced = text
      .split("\n")
      .map((line) => (line.startsWith(INDENT) ? line.slice(INDENT.length) : line))
      .join("\n");
    for (const [fieldNumber, legacy] of Object.entries(LEGACY_HEADING_VARIANTS)) {
      const canonical = canonicalHeadingFor(Number(fieldNumber));
      reduced = reduced.split(`## ${legacy}`).join(`## ${canonical}`);
    }
    return reduced;
  };

  const a = reduce(original);
  const b = reduce(transformed);
  if (a === b) return null;

  // Report the first divergent line, so a failure is actionable rather than just "differs".
  const aLines = a.split("\n");
  const bLines = b.split("\n");
  const limit = Math.max(aLines.length, bLines.length);
  for (let i = 0; i < limit; i += 1) {
    if (aLines[i] !== bLines[i]) {
      return `line ${i + 1}: original ${JSON.stringify(aLines[i] ?? "<missing>")} vs transformed ${JSON.stringify(bLines[i] ?? "<missing>")}`;
    }
  }
  return "texts differ but no divergent line was located (length mismatch only)";
}

export function normalizeFile(relativePath: string, write: boolean): NormalizeResult {
  const path = join(PACKAGE_ROOT, relativePath);
  const original = readFileSync(path, "utf8");

  const deindented = deindent(original);
  const canonicalized = canonicalizeHeadings(deindented.text);
  const transformed = canonicalized.text;

  const problem = verifyOnlyPermittedDifferences(original, transformed);
  if (problem) {
    throw new Error(`${relativePath}: transform changed something it must not have — ${problem}`);
  }

  const changed = transformed !== original;
  if (changed && write) {
    writeFileSync(path, transformed);
  }

  return {
    file: relativePath,
    linesDeindented: deindented.count,
    headingsRenamed: canonicalized.count,
    changed,
  };
}

export function normalizeAll(write: boolean): readonly NormalizeResult[] {
  return KNOWN_TEMPLATE_VARIANT_FILES.map((f) => normalizeFile(f, write));
}

function main(): void {
  const write = process.argv.includes("--write");
  const results = normalizeAll(write);

  let totalLines = 0;
  let totalHeadings = 0;
  for (const r of results) {
    totalLines += r.linesDeindented;
    totalHeadings += r.headingsRenamed;
    console.log(
      `${r.changed ? (write ? "✔ rewrote" : "· would rewrite") : "· unchanged"} ${r.file} ` +
        `(${r.linesDeindented} line(s) de-indented, ${r.headingsRenamed} heading(s) canonicalized)`,
    );
  }

  console.log(
    `\n${results.filter((r) => r.changed).length}/${results.length} file(s) ${write ? "rewritten" : "would change"}; ` +
      `${totalLines} line(s) de-indented, ${totalHeadings} heading(s) canonicalized.`,
  );
  console.log("Every file verified content-identical modulo the leading indent and the five known heading strings.");
  if (!write) console.log("Dry run — pass --write to apply.");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
