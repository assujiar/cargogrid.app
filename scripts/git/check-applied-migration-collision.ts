/**
 * Applied-migration collision check (ISS-2026-288).
 *
 * WHAT THIS CATCHES THAT THE EXISTING PROTECTED-PATH CHECK DOES NOT
 *
 *   `check-protected-paths.ts` already forbids MODIFYING a migration, and exempts a
 *   brand-new one -- "a migration path is exempt only when its git status is exactly
 *   added". That is correct as far as it goes, and it is blind to the one shape that
 *   actually caused `ERR-2026-001`, `ERR-2026-002` and `ERR-2026-003` in this
 *   repository's own history.
 *
 *   Git status is computed against the MERGE BASE. A branch that cut from `main` before a
 *   migration existed, then created its own file under that same timestamped filename
 *   while a different version of that file landed on `main`, shows the file as **added**
 *   on both sides. Every status-based rule waves it through. `ISS-2026-288` is exactly
 *   that shape, sitting on a real remote branch today: a 113-insertion / 236-deletion
 *   divergent copy of `20260729270000_create_finance_dashboard.sql`, an applied migration,
 *   under an identical filename.
 *
 *   So this check does not look at status at all. It compares each migration file in the
 *   working tree against **the base branch's current content**, and fails when the same
 *   filename exists there with different bytes. Same name, different content, already
 *   applied -- that is the collision, whatever git calls it.
 *
 * WHY THIS RATHER THAN DELETING THE BRANCH
 *
 *   `ISS-2026-288`'s own recommended remediation is either deleting the offending remote
 *   branch -- a destructive operation on shared history that `AGENTS.md` forbids without
 *   explicit authorization -- or "a pre-merge collision check on `main`... a durable
 *   structural control rather than a one-time cleanup". This is that control. It needs
 *   nobody's permission, it outlives the one branch that prompted it, and it turns
 *   `ADR-0027` Part C's "no applied migration may be edited" from a rule people follow
 *   into a rule the pipeline enforces.
 *
 *   It does NOT delete anything, and it does not make the branch safe to merge. It makes
 *   merging it fail loudly instead of silently replacing an applied migration's content.
 */

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

export interface MigrationComparison {
  readonly path: string;
  /** The base branch's current content for this path, or null when the base branch does not have this file at all (a genuinely new migration). */
  readonly baseContent: string | null;
  readonly headContent: string;
}

export interface CollisionFinding {
  readonly path: string;
  readonly reason: string;
}

/**
 * Pure decision core. A collision is: the base branch already has this exact filename, and
 * our content differs from it.
 *
 * Deliberately byte-exact rather than normalised. A "harmless" whitespace-only difference in
 * an applied migration is still a different file under a name the database has already
 * recorded as run, and normalising would mean deciding which differences are harmless --
 * which is the judgement this check exists to remove.
 */
export function findAppliedMigrationCollisions(comparisons: readonly MigrationComparison[]): CollisionFinding[] {
  const findings: CollisionFinding[] = [];
  for (const comparison of comparisons) {
    if (comparison.baseContent === null) continue;
    if (comparison.baseContent === comparison.headContent) continue;
    findings.push({
      path: comparison.path,
      reason:
        "this filename already exists on the base branch with different content. An applied migration is never edited or replaced -- " +
        "add a corrective migration under a new timestamp instead (ADR-0027 Part C, AGENTS.md). " +
        "Note that git may report this file as ADDED if the branch predates the base branch's own copy: that is exactly the " +
        "parallel-lineage shape ERR-2026-001..003 came from, and why this check compares content rather than status.",
    });
  }
  return findings;
}

const MIGRATION_DIR = "supabase/migrations";
const MIGRATION_PATTERN = /^supabase\/migrations\/\d.*\.sql$/;

function git(args: readonly string[]): string {
  return execFileSync("git", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

function baseRefExists(ref: string): boolean {
  try {
    git(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]);
    return true;
  } catch {
    return false;
  }
}

function readBaseContent(ref: string, path: string): string | null {
  try {
    return git(["show", `${ref}:${path}`]);
  } catch {
    // Not present on the base branch -- a genuinely new migration, which is the normal case.
    return null;
  }
}

function main(): void {
  const ref = process.argv[2] ?? "origin/main";

  if (!baseRefExists(ref)) {
    // A shallow or single-branch checkout genuinely cannot answer this question. Say so and
    // fail, rather than passing: a check that silently no-ops when it cannot see the base
    // branch is worse than no check, because the green tick claims something it never looked at.
    console.error(`✖ base ref '${ref}' is not available in this checkout, so applied-migration collisions cannot be detected.`);
    console.error("  Fetch it first (e.g. `git fetch origin main`), or pass an available ref as the first argument.");
    process.exit(1);
  }

  const tracked = git(["ls-files", MIGRATION_DIR])
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => MIGRATION_PATTERN.test(line));

  const comparisons: MigrationComparison[] = tracked.map((path) => ({
    path,
    baseContent: readBaseContent(ref, path),
    headContent: readFileSync(path, "utf8"),
  }));

  const findings = findAppliedMigrationCollisions(comparisons);

  if (findings.length > 0) {
    console.error(`✖ ${findings.length} applied-migration collision(s) against '${ref}':`);
    for (const finding of findings) {
      console.error(`  - ${finding.path}`);
      console.error(`    ${finding.reason}`);
    }
    process.exit(1);
  }

  const newCount = comparisons.filter((c) => c.baseContent === null).length;
  console.log(
    `✔ no applied migration differs from '${ref}' (${comparisons.length} tracked migration(s) compared by content, ${newCount} new to this branch).`,
  );
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
