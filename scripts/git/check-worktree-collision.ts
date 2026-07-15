/**
 * Local half of the ISS-2026-002 pre-flight collision check
 * (docs/git/GIT_STRATEGY.md §7). Detects the two locally-checkable signals
 * that preceded every prior occurrence of this repository's parallel-session
 * corruption (ERR-2026-001, ERR-2026-002, ERR-2026-003):
 *
 *   1. Two `agent/*`/`claude/*` branches that have each independently added
 *      commits beyond their common ancestor (a genuine fork, checked via
 *      `git merge-base`) — this is the exact ERR-2026-002/003 precondition.
 *      A branch that is merely a stale, unmoved pointer at an ancestor of
 *      another branch (e.g. a harness-assigned session branch nobody pushed
 *      further commits to) is correctly NOT flagged.
 *   2. A dirty worktree at session start with changes not explainable by
 *      the current session's own known writes.
 *
 * Compares against `origin/main`, not the local `main` ref — a local `main`
 * can be stale relative to the remote (confirmed during this task's own
 * authoring: local `main` was 6 commits behind `origin/main` in this exact
 * sandbox), which would otherwise produce false "commits ahead" positives.
 *
 * This does NOT replace the GitHub-side check (open PRs, remote branches
 * this sandbox hasn't fetched) — that half requires this agent's own
 * GitHub API/MCP access and is a documented procedure
 * (docs/git/GIT_STRATEGY.md §7 item 1), not a portable script, since no
 * committed script can carry this agent's credentials.
 *
 * CLI: node --experimental-strip-types scripts/git/check-worktree-collision.ts
 */

import { execFileSync } from "node:child_process";

export interface DivergedBranch {
  readonly branch: string;
  readonly commitsAheadOfMain: number;
  readonly headSha: string;
}

export interface ForkPair {
  readonly branchA: string;
  readonly branchB: string;
}

export interface CollisionCheckResult {
  readonly divergedBranches: readonly DivergedBranch[];
  readonly forkedPairs: readonly ForkPair[];
  readonly worktreeDirty: boolean;
  readonly dirtyFiles: readonly string[];
  readonly collisionRisk: boolean;
}

function git(args: readonly string[]): string {
  return execFileSync("git", args as string[], { encoding: "utf8" }).trim();
}

function listCandidateBranches(): string[] {
  const raw = git(["branch", "--list", "agent/*", "claude/*", "--format=%(refname:short)"]);
  return raw.split("\n").map((l) => l.trim()).filter(Boolean);
}

function commitsAheadOfMain(branch: string): number {
  try {
    const count = git(["rev-list", "--count", `origin/main..${branch}`]);
    return Number.parseInt(count, 10);
  } catch {
    // `main` or the branch may not be resolvable in a shallow/partial clone — treat as unknown, not zero.
    return -1;
  }
}

function headSha(branch: string): string {
  return git(["rev-parse", branch]);
}

/**
 * Two branches are a genuine fork (real collision risk — the exact
 * ERR-2026-002/003 precondition) only if EACH has commits the other lacks:
 * i.e. their merge-base is neither branch's own tip. If one branch's tip
 * *is* the merge-base, it is a plain ancestor of the other (e.g. a stale,
 * unmoved harness-assigned branch pointer) — same lineage, not a collision.
 */
function isGenuineFork(branchA: string, shaA: string, branchB: string, shaB: string): boolean {
  const mergeBase = git(["merge-base", branchA, branchB]);
  return mergeBase !== shaA && mergeBase !== shaB;
}

export function checkWorktreeCollision(): CollisionCheckResult {
  const candidates = listCandidateBranches();
  const divergedBranches: DivergedBranch[] = candidates
    .map((branch) => ({ branch, commitsAheadOfMain: commitsAheadOfMain(branch), headSha: headSha(branch) }))
    .filter((entry) => entry.commitsAheadOfMain > 0);

  const forkedPairs: ForkPair[] = [];
  for (let i = 0; i < divergedBranches.length; i++) {
    for (let j = i + 1; j < divergedBranches.length; j++) {
      const a = divergedBranches[i]!;
      const b = divergedBranches[j]!;
      if (isGenuineFork(a.branch, a.headSha, b.branch, b.headSha)) {
        forkedPairs.push({ branchA: a.branch, branchB: b.branch });
      }
    }
  }

  const statusOutput = git(["status", "--short"]);
  const dirtyFiles = statusOutput.split("\n").map((l) => l.trim()).filter(Boolean);

  // A genuine fork pair — not merely >1 branch ahead of main — is the real ERR-2026-002/003 precondition.
  const collisionRisk = forkedPairs.length > 0;

  return {
    divergedBranches,
    forkedPairs,
    worktreeDirty: dirtyFiles.length > 0,
    dirtyFiles,
    collisionRisk,
  };
}

function main(): void {
  const result = checkWorktreeCollision();

  console.log(`Branches with unmerged commits ahead of origin/main: ${result.divergedBranches.length}`);
  for (const b of result.divergedBranches) {
    console.log(`  - ${b.branch}: ${b.commitsAheadOfMain} commit(s) ahead`);
  }

  if (result.worktreeDirty) {
    console.log(`Worktree has ${result.dirtyFiles.length} uncommitted change(s) — inspect before proceeding (AGENTS.md: never reset/discard without reviewing).`);
  } else {
    console.log("Worktree is clean.");
  }

  if (result.collisionRisk) {
    console.error(`\n✖ Collision risk: ${result.forkedPairs.length} genuinely forked branch pair(s) found:`);
    for (const pair of result.forkedPairs) {
      console.error(`  - "${pair.branchA}" and "${pair.branchB}" each have commits the other lacks`);
    }
    console.error("This is the exact precondition behind ERR-2026-002/003. Reconcile before proceeding — see docs/git/GIT_STRATEGY.md §7.");
    process.exit(1);
  }

  console.log("\n✔ No local collision risk detected. (This does not check GitHub-side open PRs — see docs/git/GIT_STRATEGY.md §7 item 1.)");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
