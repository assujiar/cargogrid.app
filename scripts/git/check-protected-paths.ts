/**
 * Checks a set of changed file paths against docs/git/GIT_STRATEGY.md §4's
 * protected-path table. Two severities:
 *   - FORBIDDEN: never touched by a runtime agent without the named override
 *     authority (read-only sources, applied migrations, real secrets).
 *   - CAUTION: legitimately edited, but additively/carefully only (e.g.
 *     docs/runtime/** is meant to be updated every checkpoint — this is a
 *     reminder to follow the append-only/reconciliation discipline, not a
 *     block).
 *
 * Rules are evaluated in order and the FIRST match wins, so a narrow rule may
 * be placed ahead of a broader one to override it. The only such narrowing today
 * is CON-016/ADR-0026's: five register/derived-metadata files under the otherwise
 * FORBIDDEN prompt-package tree are CAUTION, because Step 17's own prompts
 * (415-429 §20.4/§31, 429 §4) require the executing agent to correct them.
 * All 324 prompt files and all 18 step READMEs remain FORBIDDEN.
 *
 * The migrations rule is git-status-aware: a brand-new migration file (git
 * status `A`) is never flagged — only a modification to one that already
 * existed before this change (`M`, or any status other than `A`) is. A
 * caller that supplies a bare path with no status (e.g. an existing unit
 * test, or a manual single-path check) gets the previous, conservative
 * behavior — flagged regardless — since "no status" cannot prove the file
 * is new.
 *
 * CLI: node --experimental-strip-types scripts/git/check-protected-paths.ts [<git-diff-range>]
 *      Default range: staged changes (`git diff --cached --name-status`).
 */

export type PathSeverity = "FORBIDDEN" | "CAUTION";

export interface ProtectedPathRule {
  readonly pattern: RegExp;
  readonly severity: PathSeverity;
  readonly reason: string;
}

/** A migration path is exempt from the FORBIDDEN migrations rule only when its git status is known and is exactly "added". */
const MIGRATIONS_PATTERN = /^supabase\/migrations\/\d.*\.sql$/;

/**
 * The five register/derived-metadata files Step 17 (Final Package Validation) may correct, per
 * `CON-016` / `ADR-0026`. Matched LITERALLY and exactly — never by prefix or glob — so no
 * file can be brought inside the exemption by being placed next to one of these. Everything
 * else under docs/ai-agent-build-prompt-package/ stays FORBIDDEN, in particular all 324
 * prompt files and all 18 step READMEs (BUILD_EXECUTION_PROTOCOL.md §3.5, AGENTS.md).
 */
export const STEP17_CORRECTABLE_PACKAGE_PATHS: readonly string[] = [
  // 04 carries CON-016 itself. Its binding authority stays "decision-change protocol only"
  // (GIT_STRATEGY.md §4) -- a policy control a path-based gate cannot express, exactly as
  // docs/runtime/**'s append-only discipline is. CAUTION makes the write visible; the ADR,
  // not this list, is what makes it legitimate.
  "docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md",
  "docs/ai-agent-build-prompt-package/00-control/05_REQUIREMENT_COVERAGE_MATRIX.md",
  "docs/ai-agent-build-prompt-package/00-control/06_PACKAGE_BUILD_STATUS.md",
  "docs/ai-agent-build-prompt-package/00-control/07_PROMPT_PACKAGE_MANIFEST.md",
  "docs/ai-agent-build-prompt-package/START_HERE.md",
];

/** Escapes a literal path so it can anchor an exact-match RegExp. */
function exactPathPattern(paths: readonly string[]): RegExp {
  const alternation = paths.map((p) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
  return new RegExp(`^(?:${alternation})$`);
}

const STEP17_CORRECTABLE_PATTERN = exactPathPattern(STEP17_CORRECTABLE_PACKAGE_PATHS);

export const PROTECTED_PATH_RULES: readonly ProtectedPathRule[] = [
  { pattern: /^docs\/blueprint\//, severity: "FORBIDDEN", reason: "read-only authoritative source (decision-change protocol only)" },
  // Ordered BEFORE the blanket package rule below: first match wins for these four paths
  // (see the loop in checkProtectedPaths, which breaks on the first matching rule).
  { pattern: STEP17_CORRECTABLE_PATTERN, severity: "CAUTION", reason: "package metadata correctable by Step 17 only, mechanical/source-safe corrections with cited evidence (CON-016, ADR-0026) — re-verify with `pnpm run package:check`" },
  { pattern: /^docs\/ai-agent-build-prompt-package\//, severity: "FORBIDDEN", reason: "read-only execution plan — never edited by a runtime agent" },
  { pattern: MIGRATIONS_PATTERN, severity: "FORBIDDEN", reason: "applied migration — never edit, add a new migration instead (AGENTS.md)" },
  { pattern: /(^|\/)\.env(\.(?!example$|sample$|template$)[^/]*)?$/, severity: "FORBIDDEN", reason: "real environment/secret file — must never be committed (.env.example/.sample/.template are the safe, allowed exception)" },
  { pattern: /^docs\/architecture\//, severity: "CAUTION", reason: "VERIFIED once closed — amend with a visible supersession blockquote, never a silent edit" },
  { pattern: /^docs\/runtime\//, severity: "CAUTION", reason: "additive/append-only ledger — historical rows are evidence, never deleted" },
];

export interface PathCheckFinding {
  readonly path: string;
  readonly severity: PathSeverity;
  readonly reason: string;
}

export type ChangedPathEntry = string | { readonly path: string; readonly status?: string };

export function checkProtectedPaths(changedPaths: readonly ChangedPathEntry[]): readonly PathCheckFinding[] {
  const findings: PathCheckFinding[] = [];
  for (const entry of changedPaths) {
    const path = typeof entry === "string" ? entry : entry.path;
    const status = typeof entry === "string" ? undefined : entry.status;
    for (const rule of PROTECTED_PATH_RULES) {
      if (!rule.pattern.test(path)) continue;
      if (rule.pattern === MIGRATIONS_PATTERN && status === "A") continue;
      findings.push({ path, severity: rule.severity, reason: rule.reason });
      // First match wins, so a narrowing rule placed ahead of a broader one (CON-016's four
      // Step 17 metadata paths ahead of the blanket package rule) genuinely overrides it
      // instead of both firing and the FORBIDDEN one still blocking.
      break;
    }
  }
  return findings;
}

async function changedPathsFromGit(range?: string): Promise<{ path: string; status: string }[]> {
  const { execFileSync } = await import("node:child_process");
  const args = range ? ["diff", "--name-status", range] : ["diff", "--cached", "--name-status"];
  const output = execFileSync("git", args, { encoding: "utf8" });
  return output
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [status, ...pathParts] = line.split("\t");
      // Rename/copy lines are "R100\told\tnew" — the changed path is the last field.
      return { status: (status ?? "").charAt(0), path: pathParts[pathParts.length - 1] ?? "" };
    })
    .filter((entry) => entry.path.length > 0);
}

async function main(): Promise<void> {
  const range = process.argv[2];
  const entries = await changedPathsFromGit(range);
  const findings = checkProtectedPaths(entries);

  const forbidden = findings.filter((f) => f.severity === "FORBIDDEN");
  const caution = findings.filter((f) => f.severity === "CAUTION");

  for (const f of caution) console.warn(`⚠ CAUTION ${f.path}: ${f.reason}`);
  for (const f of forbidden) console.error(`✖ FORBIDDEN ${f.path}: ${f.reason}`);

  if (forbidden.length > 0) {
    console.error(`\n${forbidden.length} forbidden path(s) touched — see docs/git/GIT_STRATEGY.md §4 for override authority.`);
    process.exit(1);
  }

  console.log(`✔ no forbidden paths touched (${entries.length} file(s) checked, ${caution.length} caution flag(s)).`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
