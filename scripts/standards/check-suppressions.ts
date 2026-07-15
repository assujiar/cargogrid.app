/**
 * Exception/suppression governance — docs/standards/CODING_STANDARDS.md §12,
 * business rule §24: "Suppression needs reason/owner/expiry and cannot waive
 * security/integrity."
 *
 * Scans every tracked, non-binary file for an eslint-disable* comment or a
 * TypeScript `@ts-expect-error`/`@ts-ignore` and requires it to carry:
 *
 *   SUPPRESS(owner=<name>, reason=<text>, expires=<YYYY-MM-DD|NONE>, adr=<id|NONE>)
 *
 * on the same line or the line immediately before/after. `@ts-ignore` is
 * additionally flagged outright (use `@ts-expect-error`, which errors if the
 * suppression becomes unnecessary — `@ts-ignore` silently does nothing then).
 *
 * CLI: node --experimental-strip-types scripts/standards/check-suppressions.ts
 */

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const SUPPRESSION_MARKERS = [/eslint-disable(?:-next-line|-line)?/, /@ts-expect-error/, /@ts-ignore/];

const SUPPRESS_METADATA_PATTERN =
  /SUPPRESS\(owner=[^,)]+,\s*reason=[^,)]+,\s*expires=(\d{4}-\d{2}-\d{2}|NONE),\s*adr=[^,)]+\)/;

export type ViolationKind = "MISSING_METADATA" | "TS_IGNORE_DISCOURAGED" | "EXPIRED";

export interface SuppressionViolation {
  readonly file: string;
  readonly line: number;
  readonly kind: ViolationKind;
  readonly content: string;
}

function listTrackedFiles(): string[] {
  const output = execFileSync("git", ["ls-files"], { encoding: "utf8" });
  return output
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .filter((f) => /\.(ts|tsx|js|jsx|mjs|cjs)$/.test(f));
}

function hasNearbySuppressMetadata(lines: readonly string[], index: number): boolean {
  const candidates = [lines[index], lines[index - 1], lines[index + 1]].filter((l): l is string => l !== undefined);
  return candidates.some((l) => SUPPRESS_METADATA_PATTERN.test(l));
}

function parseExpiry(lines: readonly string[], index: number): string | null {
  const candidates = [lines[index], lines[index - 1], lines[index + 1]].filter((l): l is string => l !== undefined);
  for (const l of candidates) {
    const match = SUPPRESS_METADATA_PATTERN.exec(l);
    if (match) return match[1] ?? null;
  }
  return null;
}

export function checkFileContent(file: string, content: string, today: string): SuppressionViolation[] {
  const lines = content.split("\n");
  const violations: SuppressionViolation[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? "";
    const hasMarker = SUPPRESSION_MARKERS.some((re) => re.test(line));
    if (!hasMarker) continue;

    if (/@ts-ignore\b/.test(line) && !/@ts-expect-error/.test(line)) {
      violations.push({ file, line: i + 1, kind: "TS_IGNORE_DISCOURAGED", content: line.trim() });
    }

    if (!hasNearbySuppressMetadata(lines, i)) {
      violations.push({ file, line: i + 1, kind: "MISSING_METADATA", content: line.trim() });
      continue;
    }

    const expiry = parseExpiry(lines, i);
    if (expiry && expiry !== "NONE" && expiry < today) {
      violations.push({ file, line: i + 1, kind: "EXPIRED", content: line.trim() });
    }
  }

  return violations;
}

// This module's own docstring and test fixtures necessarily mention
// "eslint-disable"/"@ts-expect-error"/"@ts-ignore" and the SUPPRESS(...)
// format as prose/examples, not as real suppression usage — scanning them
// produces exactly the false positives a self-referential checker risks
// (confirmed for real during authoring: 9 false violations before this
// exclusion existed, docs/build-log/phase-00/PH0-89.md §5).
const SELF_REFERENTIAL_EXCLUSIONS = new Set(["scripts/standards/check-suppressions.ts", "scripts/standards/check-suppressions.test.ts"]);

export function checkRepository(today: string): SuppressionViolation[] {
  const files = listTrackedFiles().filter((f) => !SELF_REFERENTIAL_EXCLUSIONS.has(f));
  const violations: SuppressionViolation[] = [];
  for (const file of files) {
    const content = readFileSync(file, "utf8");
    violations.push(...checkFileContent(file, content, today));
  }
  return violations;
}

function main(): void {
  const today = new Date().toISOString().slice(0, 10);
  const violations = checkRepository(today);

  if (violations.length === 0) {
    console.log("✔ no suppression-governance violations found.");
    return;
  }

  for (const v of violations) {
    console.error(`✖ ${v.file}:${v.line} [${v.kind}] ${v.content}`);
  }
  console.error(`\n${violations.length} suppression-governance violation(s) — see docs/standards/CODING_STANDARDS.md §12.`);
  process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
