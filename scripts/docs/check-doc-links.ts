/**
 * Documentation validation — docs/standards/DOCUMENTATION_STANDARDS.md §5,
 * CG-S5-PH0-013 (Prompt 92). Checks what is mechanically checkable without
 * false positives in a prose-heavy, backtick-code-span-citation corpus (this
 * repository never uses Markdown `[text](path)` links — confirmed via grep
 * across every existing doc before choosing this design, §5's own text) —
 * deliberately conservative (§5 "Deliberately not mechanically checked").
 *
 * CLI: node --experimental-strip-types scripts/docs/check-doc-links.ts
 */

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";

const DOC_SCAN_PREFIXES = [
  "docs/runtime/",
  "docs/adr/",
  "docs/standards/",
  "docs/build-log/",
  "docs/build-logs/",
  "docs/git/",
  "docs/templates/",
];
const DOC_SCAN_ROOT_FILES = new Set(["AGENTS.md", "README.md"]);

// A backtick span is only checked when it unambiguously names one real file —
// must start with one of these root-relative prefixes (or be an exact
// allowlisted root file) and carry a real extension. Everything else (glob
// citations with "*", "NN"/".." placeholders, npm/node module specifiers,
// commands, IDs, enum values) is silently skipped rather than risk a false
// positive — under-checking is the safe failure mode for a first-run tool.
const CHECKABLE_PATH_PREFIXES = ["docs/", "scripts/", "tests/", "e2e/", ".github/", "supabase/"];
const CHECKABLE_ROOT_FILES = new Set([
  "AGENTS.md",
  "README.md",
  "package.json",
  "pnpm-lock.yaml",
  "tsconfig.json",
  "playwright.config.ts",
  "eslint.config.js",
  ".gitignore",
]);
const PLACEHOLDER_MARKERS = ["*", "{{", "}}", "<", ">", "NN", "..", " "];

// Forward-referencing planning documents: their whole job is to name a
// future task's not-yet-created evidence path (e.g. "PH0-99" before Prompt 99
// has run) — checking their citations for present-tense existence is the
// wrong tool for this file type, the same self-referential-exclusion
// reasoning scripts/standards/check-suppressions.ts already applies to
// itself (that checker's own docstring/fixtures mention suppression syntax
// as prose, not real usage — found for real, PH0-89.md §5).
const PLANNING_DOCUMENT_EXCLUSIONS = new Set(["docs/build-log/phase-00/00_PHASE0_EXECUTION_INDEX.md", "docs/build-log/phase-00/00_PHASE0_WBS.md"]);

// Historical, append-only evidence records (build logs, and the checkpoints
// of docs/runtime/CHANGE_MANIFEST.md / ERROR_LEDGER.md written before it)
// cited the now-deleted plural docs/build-logs/CG-S5-PH0-00N_*.md files —
// correct at authoring time, broken only because a *later* checkpoint
// consolidated/removed those files during the ERR-2026-003 recovery
// (docs/runtime/HANDOFF.md §1). Rewriting historical build-log/manifest prose
// to erase what a past checkpoint actually cited would itself violate the
// append-only evidence discipline these documents exist to provide — so
// these specific, dated, enumerated paths are a known baseline exception
// (docs/runtime/KNOWN_ISSUES.md ISS-2026-006), not silently hidden and not
// fixed by rewriting history. Any *new* broken link is still caught — this
// list does not weaken the checker's logic, only excuses these named,
// already-disclosed, pre-existing breaks.
const KNOWN_HISTORICAL_BROKEN_LINKS = new Set([
  "docs/build-logs/CG-S5-PH0-001_phase0_execution_index.md",
  "docs/build-logs/CG-S5-PH0-001_phase0_wbs.md",
  "docs/build-logs/CG-S5-PH0-002_source_alignment_context_bootstrap.md",
  "docs/build-logs/CG-S5-PH0-003_requirement_traceability_baseline.md",
]);

export const REQUIRED_RUNTIME_FILES = [
  "docs/runtime/CARGOGRID_CONTEXT.md",
  "docs/runtime/CARGOGRID_BUILD_STATUS.md",
  "docs/runtime/TASK_LEDGER.md",
  "docs/runtime/CHANGE_MANIFEST.md",
  "docs/runtime/ERROR_LEDGER.md",
  "docs/runtime/KNOWN_ISSUES.md",
  "docs/runtime/HANDOFF.md",
];

export type DocIssueKind = "BROKEN_LINK" | "MISSING_CANONICAL_FILE" | "EMPTY_CANONICAL_FILE" | "ADR_INDEX_MISMATCH" | "HANDOFF_TASK_MISMATCH";

export interface DocIssue {
  readonly kind: DocIssueKind;
  readonly file: string;
  readonly line?: number;
  readonly detail: string;
}

function listTrackedFiles(): string[] {
  return execFileSync("git", ["ls-files"], { encoding: "utf8" })
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
}

function isScannedDoc(file: string): boolean {
  if (!file.endsWith(".md")) return false;
  if (PLANNING_DOCUMENT_EXCLUSIONS.has(file)) return false;
  if (DOC_SCAN_ROOT_FILES.has(file)) return true;
  return DOC_SCAN_PREFIXES.some((prefix) => file.startsWith(prefix));
}

function isCheckablePath(candidate: string): boolean {
  if (PLACEHOLDER_MARKERS.some((marker) => candidate.includes(marker))) return false;
  if (CHECKABLE_ROOT_FILES.has(candidate)) return true;
  if (!CHECKABLE_PATH_PREFIXES.some((prefix) => candidate.startsWith(prefix))) return false;
  return /\.(md|ts|tsx|json|yml|yaml|toml|js)$/.test(candidate);
}

const BACKTICK_SPAN = /`([^`]+)`/g;

export function extractCheckablePaths(content: string): string[] {
  const found: string[] = [];
  let match: RegExpExecArray | null;
  BACKTICK_SPAN.lastIndex = 0;
  while ((match = BACKTICK_SPAN.exec(content)) !== null) {
    const candidate = match[1] ?? "";
    const withoutAnchor = candidate.split("#")[0] ?? candidate;
    if (isCheckablePath(withoutAnchor)) {
      found.push(withoutAnchor);
    }
  }
  return found;
}

export function checkLinks(files: readonly string[]): DocIssue[] {
  const issues: DocIssue[] = [];
  for (const file of files) {
    if (!isScannedDoc(file)) continue;
    const content = readFileSync(file, "utf8");
    const lines = content.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i] ?? "";
      for (const candidate of extractCheckablePaths(line)) {
        if (KNOWN_HISTORICAL_BROKEN_LINKS.has(candidate)) continue;
        if (!existsSync(candidate)) {
          issues.push({ kind: "BROKEN_LINK", file, line: i + 1, detail: `references \`${candidate}\`, which does not exist` });
        }
      }
    }
  }
  return issues;
}

export function checkCanonicalRuntimeFiles(): DocIssue[] {
  const issues: DocIssue[] = [];
  for (const file of REQUIRED_RUNTIME_FILES) {
    if (!existsSync(file)) {
      issues.push({ kind: "MISSING_CANONICAL_FILE", file, detail: "required by AGENTS.md 'Required pre-flight' but does not exist" });
      continue;
    }
    if (statSync(file).size === 0) {
      issues.push({ kind: "EMPTY_CANONICAL_FILE", file, detail: "required runtime file is empty" });
    }
  }
  return issues;
}

export function checkAdrIndexConsistency(readmeContent: string): DocIssue[] {
  const issues: DocIssue[] = [];
  const indexSection = readmeContent.split("## 6. Index of accepted/active ADRs")[1] ?? "";
  const idPattern = /`(ADR-\d{4})`/g;
  const seen = new Set<string>();
  let match: RegExpExecArray | null;
  idPattern.lastIndex = 0;
  while ((match = idPattern.exec(indexSection)) !== null) {
    const id = match[1];
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const found = execFileSync("sh", ["-c", `ls docs/adr/${id}-*.md 2>/dev/null || true`], { encoding: "utf8" }).trim();
    if (!found) {
      issues.push({ kind: "ADR_INDEX_MISMATCH", file: "docs/adr/README.md", detail: `${id} is indexed but no docs/adr/${id}-*.md file exists` });
    }
  }
  return issues;
}

export function checkHandoffTaskCoherence(handoffContent: string, taskLedgerContent: string): DocIssue[] {
  const match = /\|\s*Task ID\/name\s*\|\s*`(CG-[A-Z0-9-]+)`/.exec(handoffContent);
  if (!match) {
    return [{ kind: "HANDOFF_TASK_MISMATCH", file: "docs/runtime/HANDOFF.md", detail: "no '| Task ID/name | `CG-...`' row found in §4" }];
  }
  const taskId = match[1];
  if (!taskLedgerContent.includes(`\`${taskId}\``)) {
    return [{ kind: "HANDOFF_TASK_MISMATCH", file: "docs/runtime/HANDOFF.md", detail: `active task ${taskId} has no row in docs/runtime/TASK_LEDGER.md` }];
  }
  return [];
}

export function runAllChecks(): DocIssue[] {
  const files = listTrackedFiles();
  const issues: DocIssue[] = [
    ...checkLinks(files),
    ...checkCanonicalRuntimeFiles(),
    ...checkAdrIndexConsistency(readFileSync("docs/adr/README.md", "utf8")),
    ...checkHandoffTaskCoherence(readFileSync("docs/runtime/HANDOFF.md", "utf8"), readFileSync("docs/runtime/TASK_LEDGER.md", "utf8")),
  ];
  return issues;
}

function main(): void {
  const issues = runAllChecks();
  if (issues.length === 0) {
    console.log("✔ documentation checks passed (link resolution, canonical files, ADR index, HANDOFF/TASK_LEDGER coherence).");
    return;
  }
  for (const issue of issues) {
    const location = issue.line ? `${issue.file}:${issue.line}` : issue.file;
    console.error(`✖ ${location} [${issue.kind}] ${issue.detail}`);
  }
  console.error(`\n${issues.length} documentation issue(s) — see docs/standards/DOCUMENTATION_STANDARDS.md §5.`);
  process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
