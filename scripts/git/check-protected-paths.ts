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

export const PROTECTED_PATH_RULES: readonly ProtectedPathRule[] = [
  { pattern: /^docs\/blueprint\//, severity: "FORBIDDEN", reason: "read-only authoritative source (decision-change protocol only)" },
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
