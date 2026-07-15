/**
 * Integration test against this repository's own real git state — consistent
 * with this checkpoint's practice of validating against real, executed
 * evidence rather than mocks (see docs/build-log/phase-00/PH0-87.md §6 for
 * the real CLI run that first caught the origin/main-vs-stale-local-main bug
 * this test guards against regressing).
 */

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { checkWorktreeCollision } from "./check-worktree-collision.ts";

describe("checkWorktreeCollision — against this repository's real state", () => {
  test("returns a well-formed result shape", () => {
    const result = checkWorktreeCollision();
    assert.ok(Array.isArray(result.divergedBranches));
    assert.ok(Array.isArray(result.forkedPairs));
    assert.ok(Array.isArray(result.dirtyFiles));
    assert.equal(typeof result.worktreeDirty, "boolean");
    assert.equal(typeof result.collisionRisk, "boolean");
  });

  test("agent/cargogrid-autonomous-build (the current branch) is reported as diverged from origin/main", () => {
    const result = checkWorktreeCollision();
    const current = result.divergedBranches.find((b) => b.branch === "agent/cargogrid-autonomous-build");
    assert.ok(current, "expected agent/cargogrid-autonomous-build to have commits ahead of origin/main");
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
