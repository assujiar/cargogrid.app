/**
 * Integration test against this repository's own real git state — consistent
 * with this checkpoint's practice of validating against real, executed
 * evidence rather than mocks (see docs/build-log/phase-00/PH0-87.md §6 for
 * the real CLI run that first caught the origin/main-vs-stale-local-main bug
 * this test guards against regressing).
 */

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { checkWorktreeCollision } from "./check-worktree-collision.ts";

// ISS-2026-004 (docs/runtime/KNOWN_ISSUES.md, fixed CG-S5-PH0-012/Prompt 91):
// this suite previously hardcoded the literal branch name
// "agent/cargogrid-autonomous-build", which only happened to work because
// every prior checkpoint's designated branch was named exactly that. It
// failed as soon as a session's designated branch had a different name
// (this checkpoint's own `claude/lanjut-btusq6`) — a session-identity fact,
// not a property of checkWorktreeCollision()'s divergence logic. Resolved by
// reading the actual current branch instead of assuming a fixed name.
function currentBranch(): string {
  return execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf8" }).trim();
}

describe("checkWorktreeCollision — against this repository's real state", () => {
  test("returns a well-formed result shape", () => {
    const result = checkWorktreeCollision();
    assert.ok(Array.isArray(result.divergedBranches));
    assert.ok(Array.isArray(result.forkedPairs));
    assert.ok(Array.isArray(result.dirtyFiles));
    assert.equal(typeof result.worktreeDirty, "boolean");
    assert.equal(typeof result.collisionRisk, "boolean");
  });

  test("the current branch is reported as diverged from origin/main", (t) => {
    const branch = currentBranch();
    // HDN-387 (HDN-BLK-007): checkWorktreeCollision() only ever considers
    // agent/*/claude/* branches as candidates (see listCandidateBranches()) --
    // a checkout of `main` itself (the exact state CI runs a push to main in)
    // never matches that glob and is never a candidate, so it can never be
    // reported as "diverged from origin/main" by construction; asserting
    // otherwise here was never a real regression guard for that branch, only
    // for a genuine agent/claude session branch. Skip rather than fail: this
    // is a fact about which branch happens to be checked out, not a property
    // of checkWorktreeCollision()'s own divergence logic under test.
    if (!branch.startsWith("agent/") && !branch.startsWith("claude/")) {
      t.skip(`current branch "${branch}" is not an agent/*/claude/* candidate branch -- checkWorktreeCollision() never considers it, so it cannot be "diverged"`);
      return;
    }
    // 2026-08-31: this test used to assert flatly that the session branch IS diverged. That
    // encoded a workflow assumption -- "a claude/* branch is always ahead of origin/main" --
    // which held only while session work was never merged until the very end. Once the owner
    // authorised merging this branch to `main`, the branch became legitimately level with
    // origin/main, and the test failed on a repository that was in a perfectly healthy state.
    //
    // The real property under test is checkWorktreeCollision()'s divergence LOGIC, so the
    // expectation is now derived from git itself rather than assumed. This is a stricter guard
    // than before: it checks agreement in BOTH directions, so a bug that under-reports OR
    // over-reports divergence fails, where the old assertion could only catch under-reporting.
    const actualAhead = Number(
      execFileSync("git", ["rev-list", "--count", `origin/main..${branch}`], { encoding: "utf8" }).trim(),
    );
    const result = checkWorktreeCollision();
    const current = result.divergedBranches.find((b) => b.branch === branch);

    if (actualAhead === 0) {
      assert.equal(
        current,
        undefined,
        `${branch} is fully contained in origin/main (merged), so it must NOT be reported as diverged`,
      );
      return;
    }

    assert.ok(current, `git says ${branch} is ${actualAhead} commit(s) ahead of origin/main, but it was not reported as diverged`);
    assert.equal(
      current!.commitsAheadOfMain,
      actualAhead,
      `divergence count disagrees with git for ${branch}`,
    );
  });

  test("no genuine collision is currently present (regression guard for the origin/main-vs-stale-local-main bug)", () => {
    // This is the exact bug found and fixed while authoring this task: comparing
    // against a stale local `main` ref falsely flagged claude/sleepy-ride-8pg1em
    // (fully contained in origin/main) as an independent fork. Fixed by comparing
    // against origin/main. This test pins that fix.
    const result = checkWorktreeCollision();
    assert.equal(result.collisionRisk, false, `unexpected fork(s): ${JSON.stringify(result.forkedPairs)}`);
  });

  test("dirtyFiles entries are non-empty strings when the worktree is dirty", () => {
    const result = checkWorktreeCollision();
    if (result.worktreeDirty) {
      assert.ok(result.dirtyFiles.every((f) => f.length > 0));
    }
  });
});
