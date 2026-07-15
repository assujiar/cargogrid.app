import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { checkBranchName } from "./check-branch-name.ts";

describe("checkBranchName", () => {
  test("accepts the actual current branch of this repository", () => {
    const result = checkBranchName("agent/cargogrid-autonomous-build");
    assert.equal(result.valid, true);
    assert.equal(result.matchedPattern, "agent/<slug>");
  });

  test("accepts a claude/ harness-assigned branch", () => {
    const result = checkBranchName("claude/sleepy-ride-8pg1em");
    assert.equal(result.valid, true);
  });

  test("accepts main (informational)", () => {
    const result = checkBranchName("main");
    assert.equal(result.valid, true);
  });

  test("accepts a well-formed feature branch", () => {
    const result = checkBranchName("feature/CG-S5-PH0-009-cicd-baseline");
    assert.equal(result.valid, true);
  });

  test("accepts a well-formed hotfix branch", () => {
    const result = checkBranchName("hotfix/FIN-204-posting-lock-race");
    assert.equal(result.valid, true);
  });

  test("rejects a feature branch missing a task ID", () => {
    const result = checkBranchName("feature/some-random-work");
    assert.equal(result.valid, false);
  });

  test("rejects an arbitrary unstructured branch name", () => {
    const result = checkBranchName("my-random-branch");
    assert.equal(result.valid, false);
  });
});
