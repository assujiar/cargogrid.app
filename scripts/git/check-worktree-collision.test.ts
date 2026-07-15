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

  test("the current branch is reported as diverged from origin/main", () => {
    const branch = currentBranch();
    const result = checkWorktreeCollision();
    const current = result.divergedBranches.find((b) => b.branch === branch);
    assert.ok(current, `expected ${branch} to have commits ahead of origin/main`);
    assert.ok(current!.commitsAheadOfMain > 0);
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
