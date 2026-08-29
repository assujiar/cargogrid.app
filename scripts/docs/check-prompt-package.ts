/**
 * Mechanical structural validator for the CargoGrid AI Agent Build Prompt Package
 * (`docs/ai-agent-build-prompt-package/`).
 *
 * Written for Step 17 — Final Package Validation (Prompts 414–430), whose §28 requires each
 * audit lane to "create or update package validation checks … including file/path checks, ID
 * uniqueness, heading structure, source coverage, dependency graph or content rules". Running
 * those checks by hand once is an audit; encoding them is a gate, and a gate is what keeps the
 * package from drifting after Step 17 closes.
 *
 * What this script does NOT do: it does not judge whether a prompt is *correct*, whether a
 * requirement is genuinely covered, or whether the package is safe to execute. Those are
 * judgements the Step 17 lanes make with cited evidence. This script checks only the
 * mechanical invariants — the ones where "pass" and "fail" are decidable from the files alone.
 *
 * CLI: node --experimental-strip-types scripts/docs/check-prompt-package.ts [<package-root>]
 *      Exit 0 = no ERROR-severity finding. Exit 1 = at least one.
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";

export type PackageFindingSeverity = "ERROR" | "WARN";

export interface PackageCheckFinding {
  /** Stable machine-readable class, so a build log can cite a finding by code. */
  readonly code: string;
  readonly severity: PackageFindingSeverity;
  /** Package-relative path, when the finding belongs to one file. */
  readonly path?: string;
  readonly detail: string;
}

export interface PackageStats {
  readonly fileCount: number;
  readonly directoryCounts: Readonly<Record<string, number>>;
  readonly structuredPromptCount: number;
  readonly manifestRowCount: number;
  readonly explicitNextEdges: number;
}

export interface PackageCheckResult {
  readonly findings: readonly PackageCheckFinding[];
  readonly stats: PackageStats;
}

/**
 * The 36-field prompt structure, in the exact order and wording every structured prompt
 * carries. Verified uniform across all 324 structured files at 2026-08-29 — not a convention
 * this script invents, a fact it pins so a later edit cannot silently break it.
 */
export const REQUIRED_PROMPT_HEADINGS: readonly string[] = [
  "1. Prompt ID",
  "2. Parent phase",
  "3. Workstream",
  "4. Objective",
  "5. Business value",
  "6. Source requirement",
  "7. Current repository context",
  "8. Preconditions",
  "9. Upstream dependencies",
  "10. Downstream impact",
  "11. Allowed files/folders",
  "12. Forbidden files/folders",
  "13. Database impact",
  "14. API impact",
  "15. UI/UX impact",
  "16. Security impact",
  "17. Performance impact",
  "18. Audit impact",
  "19. Data migration impact",
  "20. Detailed implementation tasks",
  "21. Main flow",
  "22. Alternative flow",
  "23. Exception flow",
  "24. Business rules",
  "25. Validation rules",
  "26. Access rules",
  "27. Test data requirement",
  "28. Tests to create/update",
  "29. Regression tests",
  "30. Commands to run",
  "31. Documentation to update",
  "32. Rollback/recovery note",
  "33. Acceptance criteria",
  "34. Definition of Done",
  "35. Completion report format",
  "36. Next eligible prompt",
];

/** The eight Step 0 control documents. Their absence is a package-fatal defect. */
export const REQUIRED_CONTROL_FILES: readonly string[] = [
  "00-control/00_PACKAGE_README.md",
  "00-control/01_SOURCE_OF_TRUTH_MATRIX.md",
  "00-control/02_CONFIRMED_DECISION_REGISTER.md",
  "00-control/03_ASSUMPTION_REGISTER.md",
  "00-control/04_CONFLICT_REGISTER.md",
  "00-control/05_REQUIREMENT_COVERAGE_MATRIX.md",
  "00-control/06_PACKAGE_BUILD_STATUS.md",
  "00-control/07_PROMPT_PACKAGE_MANIFEST.md",
];

/** Control files that must declare the package version. Prompt 430 §1 requires this. */
export const VERSION_BEARING_CONTROL_FILES: readonly string[] = [
  "00-control/00_PACKAGE_README.md",
  "00-control/06_PACKAGE_BUILD_STATUS.md",
  "00-control/07_PROMPT_PACKAGE_MANIFEST.md",
  "START_HERE.md",
];

export const EXPECTED_PACKAGE_VERSION = "0.18.0-step17";

const MANIFEST_PATH = "00-control/07_PROMPT_PACKAGE_MANIFEST.md";
const START_HERE_PATH = "START_HERE.md";

/**
 * How a prompt's §36 names what comes next. The package deliberately uses several forms, and
 * conflating them would manufacture false "orphan prompt" findings:
 *
 *  - `EXPLICIT`       — names a concrete prompt number (e.g. "continue only to `FPV-416`").
 *                       Only these carry a checkable graph edge.
 *  - `INDEX_DELEGATED`— defers to the phase execution index ("only the execution index may
 *                       release the next dependency-clean … prompt"). Correct by design: the
 *                       index owns the ordering, not the prompt.
 *  - `TEMPLATE`       — a `{{...}}` placeholder the executing agent substitutes at runtime.
 *  - `TERMINAL`       — a closure prompt with no successor.
 */
export type NextKind = "EXPLICIT" | "INDEX_DELEGATED" | "TEMPLATE" | "TERMINAL";

export interface NextReference {
  readonly kind: NextKind;
  /** Prompt numbers named explicitly in §36, when kind is EXPLICIT. */
  readonly targets: readonly number[];
}

/**
 * Reads §36's body and classifies it. Exported so the audit lanes can reuse the same parse.
 *
 * `promptRange` is the [min, max] prompt number of the step directory the referencing file
 * lives in. It exists to separate two references that share a shape but not a meaning. A
 * §36 commonly reads:
 *
 *     `CG-S7-COM-011` / `COM-152` only after acceptance/dependencies pass; …
 *
 * where `COM-011` is the *task sequence* ID and `COM-152` is the *prompt number*. Both match
 * `PREFIX-NNN`. Reading the first as a prompt number manufactures a backward edge to prompt 11
 * from a Phase 2 prompt — which is exactly the false "cycle" this classifier must not report.
 * A successor is in its own step's range, or is the first prompt of the next step, so numbers
 * outside `[min, max + 1]` are task IDs and are discarded.
 */
export function classifyNextSection(sectionBody: string, promptRange?: readonly [number, number]): NextReference {
  const body = sectionBody.trim();

  if (/\{\{[^}]+\}\}/.test(body)) {
    return { kind: "TEMPLATE", targets: [] };
  }

  // "Prompt 412" / "FPV-416" / "RGL-404" all denote a prompt number. A bare number with no
  // such prefix is not assumed to be one -- too many false positives from counts and version
  // fragments.
  const targets = new Set<number>();
  for (const m of body.matchAll(/(?:Prompt\s+|[A-Z][A-Z0-9]*-)(\d{2,3})\b/g)) {
    const n = Number(m[1]);
    if (n < 10 || n > 430) continue;
    if (promptRange && (n < promptRange[0] || n > promptRange[1] + 1)) continue;
    targets.add(n);
  }

  const indexDelegated = /execution index may release|execution index owns|per the execution index/i.test(body);

  // "only Prompt N may do so" is a prohibition, not a successor edge. When the ONLY numbers in
  // §36 appear in that construction and the section also delegates to the index, the prompt has
  // no explicit successor of its own.
  const onlyProhibitions = [...body.matchAll(/only\s+Prompt\s+(\d{2,3})\s+may/gi)].map((m) => Number(m[1]));
  const nonProhibition = [...targets].filter((t) => !onlyProhibitions.includes(t));

  if (indexDelegated && nonProhibition.length === 0) {
    return { kind: "INDEX_DELEGATED", targets: [] };
  }
  if (nonProhibition.length > 0) {
    return { kind: "EXPLICIT", targets: nonProhibition.sort((a, b) => a - b) };
  }
  if (indexDelegated) {
    return { kind: "INDEX_DELEGATED", targets: [] };
  }
  return { kind: "TERMINAL", targets: [] };
}

/** Extracts the `## N. Title` sections of a markdown document, preserving order. */
export function parseSections(content: string): { heading: string; body: string }[] {
  const lines = content.split("\n");
  const sections: { heading: string; body: string }[] = [];
  let current: { heading: string; body: string[] } | null = null;

  for (const line of lines) {
    const m = /^##\s+(.+?)\s*$/.exec(line);
    if (m) {
      if (current) sections.push({ heading: current.heading, body: current.body.join("\n") });
      current = { heading: m[1] ?? "", body: [] };
    } else if (current) {
      current.body.push(line);
    }
  }
  if (current) sections.push({ heading: current.heading, body: current.body.join("\n") });
  return sections;
}

/** Leading `**Key:** \`value\`` metadata lines. */
function readMetaField(content: string, key: string): string | undefined {
  const re = new RegExp(`^\\*\\*${key}:\\*\\*\\s*\`([^\`]+)\``, "m");
  return re.exec(content)?.[1];
}

function listMarkdownFiles(root: string): string[] {
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else out.push(relative(root, full).split(sep).join("/"));
    }
  };
  walk(root);
  return out;
}

/** Parses the manifest's `| M-### | \`path\` | … |` rows. */
export function parseManifestRows(manifestContent: string): { id: string; path: string }[] {
  const rows: { id: string; path: string }[] = [];
  for (const line of manifestContent.split("\n")) {
    const m = /^\|\s*(M-\d+)\s*\|\s*`([^`]+)`\s*\|/.exec(line);
    if (m) rows.push({ id: m[1] ?? "", path: m[2] ?? "" });
  }
  return rows;
}

export function checkPromptPackage(root: string): PackageCheckResult {
  const findings: PackageCheckFinding[] = [];
  const add = (code: string, severity: PackageFindingSeverity, detail: string, path?: string): void => {
    findings.push({ code, severity, detail, ...(path ? { path } : {}) });
  };

  const files = listMarkdownFiles(root);
  const fileSet = new Set(files);

  // --- 1. Inventory -----------------------------------------------------------------------
  const directoryCounts: Record<string, number> = {};
  for (const f of files) {
    const dir = f.includes("/") ? f.slice(0, f.indexOf("/")) : "(root)";
    directoryCounts[dir] = (directoryCounts[dir] ?? 0) + 1;
    if (!f.endsWith(".md")) {
      add("NON_MARKDOWN_FILE", "ERROR", `package contains a non-markdown file`, f);
    }
    if (statSync(join(root, f)).size === 0) {
      add("EMPTY_FILE", "ERROR", `file is empty — empty placeholders are forbidden (manifest §1 rule 4)`, f);
    }
  }
  if (!fileSet.has(START_HERE_PATH)) {
    add("MISSING_START_HERE", "ERROR", `${START_HERE_PATH} is the package entry point and must exist`);
  }

  // --- 2. Control files -------------------------------------------------------------------
  for (const cf of REQUIRED_CONTROL_FILES) {
    if (!fileSet.has(cf)) add("MISSING_CONTROL_FILE", "ERROR", `required control file is absent`, cf);
  }
  for (const vf of VERSION_BEARING_CONTROL_FILES) {
    if (!fileSet.has(vf)) continue;
    const content = readFileSync(join(root, vf), "utf8");
    if (!content.includes(EXPECTED_PACKAGE_VERSION)) {
      add(
        "CONTROL_FILE_VERSION_MISMATCH",
        "ERROR",
        `does not reference package version ${EXPECTED_PACKAGE_VERSION} (Prompt 430 required-verification item 1)`,
        vf,
      );
    }
  }

  // --- 3. Manifest bijection --------------------------------------------------------------
  let manifestRows: { id: string; path: string }[] = [];
  if (fileSet.has(MANIFEST_PATH)) {
    manifestRows = parseManifestRows(readFileSync(join(root, MANIFEST_PATH), "utf8"));

    const seenIds = new Set<string>();
    const seenPaths = new Map<string, string>();
    for (const row of manifestRows) {
      if (seenIds.has(row.id)) {
        add("DUPLICATE_MANIFEST_ID", "ERROR", `manifest item ${row.id} appears more than once`, MANIFEST_PATH);
      }
      seenIds.add(row.id);

      const prior = seenPaths.get(row.path);
      if (prior) {
        add("DUPLICATE_MANIFEST_PATH", "ERROR", `${row.path} is claimed by both ${prior} and ${row.id}`, MANIFEST_PATH);
      }
      seenPaths.set(row.path, row.id);

      if (!fileSet.has(row.path)) {
        add("MANIFEST_PATH_MISSING", "ERROR", `manifest row ${row.id} points at ${row.path}, which does not exist`, MANIFEST_PATH);
      }
    }
    for (const f of files) {
      if (!seenPaths.has(f)) {
        add("FILE_NOT_IN_MANIFEST", "ERROR", `file exists but has no manifest row (manifest §1 rule 1)`, f);
      }
    }
  }

  // --- 4. Per-file structure, IDs, and the next-prompt graph ------------------------------
  const promptIdOwners = new Map<string, string>();
  const documentIdOwners = new Map<string, string>();
  const explicitEdges: { from: string; fromNumber: number; to: number }[] = [];
  const promptNumbers = new Map<number, string>();
  const pendingNextSections: { file: string; fileNumber: number; body: string }[] = [];
  let structuredPromptCount = 0;

  for (const f of files) {
    const content = readFileSync(join(root, f), "utf8");

    const promptId = readMetaField(content, "Prompt ID");
    if (promptId) {
      const prior = promptIdOwners.get(promptId);
      if (prior) add("DUPLICATE_PROMPT_ID", "ERROR", `Prompt ID ${promptId} is used by both ${prior} and ${f}`, f);
      else promptIdOwners.set(promptId, f);
    }

    const docId = readMetaField(content, "Package document");
    if (docId) {
      const prior = documentIdOwners.get(docId);
      if (prior) add("DUPLICATE_DOCUMENT_ID", "ERROR", `Package document ID ${docId} is used by both ${prior} and ${f}`, f);
      else documentIdOwners.set(docId, f);
    }

    const fileNumber = /(?:^|\/)(\d{2,3})_/.exec(f)?.[1];
    if (fileNumber) promptNumbers.set(Number(fileNumber), f);

    const sections = parseSections(content);
    const isStructured = sections.some((s) => s.heading === REQUIRED_PROMPT_HEADINGS[0]);
    if (!isStructured) continue;
    structuredPromptCount += 1;

    // 36 headings, present and in order.
    const numbered = sections.filter((s) => /^\d+\.\s/.test(s.heading)).map((s) => s.heading);
    if (numbered.length !== REQUIRED_PROMPT_HEADINGS.length) {
      add(
        "HEADING_COUNT",
        "ERROR",
        `has ${numbered.length} numbered sections, expected ${REQUIRED_PROMPT_HEADINGS.length}`,
        f,
      );
    }
    for (let i = 0; i < REQUIRED_PROMPT_HEADINGS.length; i += 1) {
      const expected = REQUIRED_PROMPT_HEADINGS[i];
      const actual = numbered[i];
      if (actual !== expected) {
        add(
          "HEADING_ORDER",
          "ERROR",
          `section ${i + 1} is "${actual ?? "(missing)"}", expected "${expected}"`,
          f,
        );
        break; // one report per file — a single insertion would otherwise cascade 30 findings
      }
    }

    // No structured section may be empty. §24 fails "no-acceptance, no-regression,
    // no-security, no-docs or no-recovery" prompts, and an empty body is the extreme case.
    for (const s of sections) {
      if (/^\d+\.\s/.test(s.heading) && s.body.trim().length === 0) {
        add("EMPTY_SECTION", "ERROR", `section "${s.heading}" has no content`, f);
      }
    }

    // Next-prompt graph. Deferred to a second pass -- the per-step ranges the classifier
    // needs are only known once every file has been numbered.
    const nextSection = sections.find((s) => s.heading === "36. Next eligible prompt");
    if (nextSection && fileNumber) {
      pendingNextSections.push({ file: f, fileNumber: Number(fileNumber), body: nextSection.body });
    }
  }

  // Per-step prompt-number ranges, derived from the files themselves rather than hardcoded.
  const stepRanges = new Map<string, [number, number]>();
  for (const [num, file] of promptNumbers) {
    const dir = file.includes("/") ? file.slice(0, file.indexOf("/")) : "(root)";
    const cur = stepRanges.get(dir);
    stepRanges.set(dir, cur ? [Math.min(cur[0], num), Math.max(cur[1], num)] : [num, num]);
  }

  for (const pending of pendingNextSections) {
    const dir = pending.file.includes("/") ? pending.file.slice(0, pending.file.indexOf("/")) : "(root)";
    const ref = classifyNextSection(pending.body, stepRanges.get(dir));
    for (const t of ref.targets) {
      explicitEdges.push({ from: pending.file, fromNumber: pending.fileNumber, to: t });
    }
  }

  // Explicit edges must resolve to a real prompt file, and must move forward. A backward or
  // self edge is the concrete shape a cycle takes in a linearly-numbered package (Prompt 419).
  for (const edge of explicitEdges) {
    if (!promptNumbers.has(edge.to)) {
      add("NEXT_TARGET_MISSING", "ERROR", `§36 names prompt ${edge.to}, which has no file in the package`, edge.from);
    }
    if (edge.to === edge.fromNumber) {
      add("NEXT_SELF_LOOP", "ERROR", `§36 names its own prompt number ${edge.to} as the successor`, edge.from);
    }
    if (edge.to < edge.fromNumber) {
      add(
        "NEXT_BACKWARD_EDGE",
        "WARN",
        `§36 names prompt ${edge.to}, which precedes this prompt (${edge.fromNumber}) — a backward edge is how a cycle appears in a linearly-ordered package; confirm it is a documented resume path, not an ordering defect`,
        edge.from,
      );
    }
  }

  return {
    findings,
    stats: {
      fileCount: files.length,
      directoryCounts,
      structuredPromptCount,
      manifestRowCount: manifestRows.length,
      explicitNextEdges: explicitEdges.length,
    },
  };
}

async function main(): Promise<void> {
  const root = process.argv[2] ?? "docs/ai-agent-build-prompt-package";
  const { findings, stats } = checkPromptPackage(root);

  const errors = findings.filter((f) => f.severity === "ERROR");
  const warns = findings.filter((f) => f.severity === "WARN");

  for (const f of warns) console.warn(`⚠ ${f.code} ${f.path ?? ""}: ${f.detail}`);
  for (const f of errors) console.error(`✖ ${f.code} ${f.path ?? ""}: ${f.detail}`);

  const dirs = Object.entries(stats.directoryCounts)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([d, n]) => `${d}=${n}`)
    .join(" ");

  console.log(
    `\npackage: ${stats.fileCount} files (${dirs}); ` +
      `${stats.structuredPromptCount} structured prompts × ${REQUIRED_PROMPT_HEADINGS.length} fields; ` +
      `${stats.manifestRowCount} manifest rows; ${stats.explicitNextEdges} explicit §36 edges.`,
  );

  if (errors.length > 0) {
    console.error(`${errors.length} package structure error(s), ${warns.length} warning(s).`);
    process.exit(1);
  }
  console.log(`✔ prompt package structure checks passed (${warns.length} warning(s)).`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
