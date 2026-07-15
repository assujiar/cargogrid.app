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
 * CLI: node --experimental-strip-types scripts/git/check-protected-paths.ts [<git-diff-range>]
 *      Default range: staged changes (`git diff --cached --name-only`).
 */

export type PathSeverity = "FORBIDDEN" | "CAUTION";

export interface ProtectedPathRule {
  readonly pattern: RegExp;
  readonly severity: PathSeverity;
  readonly reason: string;
}

export const PROTECTED_PATH_RULES: readonly ProtectedPathRule[] = [
  { pattern: /^docs\/blueprint\//, severity: "FORBIDDEN", reason: "read-only authoritative source (decision-change protocol only)" },
  { pattern: /^docs\/ai-agent-build-prompt-package\//, severity: "FORBIDDEN", reason: "read-only execution plan — never edited by a runtime agent" },
  { pattern: /^supabase\/migrations\/\d.*\.sql$/, severity: "FORBIDDEN", reason: "applied migration — never edit, add a new migration instead (AGENTS.md)" },
  { pattern: /(^|\/)\.env(\.(?!example$|sample$|template$)[^/]*)?$/, severity: "FORBIDDEN", reason: "real environment/secret file — must never be committed (.env.example/.sample/.template are the safe, allowed exception)" },
  { pattern: /^docs\/architecture\//, severity: "CAUTION", reason: "VERIFIED once closed — amend with a visible supersession blockquote, never a silent edit" },
  { pattern: /^docs\/runtime\//, severity: "CAUTION", reason: "additive/append-only ledger — historical rows are evidence, never deleted" },
];

export interface PathCheckFinding {
  readonly path: string;
  readonly severity: PathSeverity;
  readonly reason: string;
}

export function checkProtectedPaths(changedPaths: readonly string[]): readonly PathCheckFinding[] {
  const findings: PathCheckFinding[] = [];
  for (const path of changedPaths) {
    for (const rule of PROTECTED_PATH_RULES) {
      if (rule.pattern.test(path)) {
        findings.push({ path, severity: rule.severity, reason: rule.reason });
      }
    }
  }
  return findings;
}

async function changedPathsFromGit(range?: string): Promise<string[]> {
  const { execFileSync } = await import("node:child_process");
  const args = range ? ["diff", "--name-only", range] : ["diff", "--cached", "--name-only"];
  const output = execFileSync("git", args, { encoding: "utf8" });
  return output.split("\n").map((line) => line.trim()).filter(Boolean);
}

async function main(): Promise<void> {
  const range = process.argv[2];
  const paths = await changedPathsFromGit(range);
  const findings = checkProtectedPaths(paths);

  const forbidden = findings.filter((f) => f.severity === "FORBIDDEN");
  const caution = findings.filter((f) => f.severity === "CAUTION");

  for (const f of caution) console.warn(`⚠ CAUTION ${f.path}: ${f.reason}`);
  for (const f of forbidden) console.error(`✖ FORBIDDEN ${f.path}: ${f.reason}`);

  if (forbidden.length > 0) {
    console.error(`\n${forbidden.length} forbidden path(s) touched — see docs/git/GIT_STRATEGY.md §4 for override authority.`);
    process.exit(1);
  }

  console.log(`✔ no forbidden paths touched (${paths.length} file(s) checked, ${caution.length} caution flag(s)).`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
