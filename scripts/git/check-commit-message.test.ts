import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { checkCommitMessage } from "./check-commit-message.ts";

describe("checkCommitMessage", () => {
  test("accepts the established convention (task ID + Prompt N together in parens)", () => {
    const result = checkCommitMessage("agent: close Step 3 architecture and execution blueprint (CG-S3-ARCH-016, Prompt 51)");
    assert.equal(result.valid, true);
    assert.equal(result.errors.length, 0);
    assert.equal(result.warnings.length, 0);
  });

  test("accepts but warns when Prompt N is outside the task-ID parens (real drift found in this repository's recent history)", () => {
    const result = checkCommitMessage("agent: complete Phase 0 Prompt 86 (CG-S5-PH0-007) environment validation");
    assert.equal(result.valid, true);
    assert.ok(result.warnings.some((w) => w.includes("Prompt")));
  });

  test("rejects an empty message", () => {
    const result = checkCommitMessage("");
    assert.equal(result.valid, false);
  });

  test("rejects a subject line not starting with 'agent: '", () => {
    const result = checkCommitMessage("fix: something (CG-S5-PH0-008, Prompt 87)");
    assert.equal(result.valid, false);
    assert.ok(result.errors[0]?.includes("agent:"));
  });

  test("warns on an undocumented verb but still passes", () => {
    const result = checkCommitMessage("agent: refactor the thing (CG-S5-PH0-008, Prompt 87)");
    assert.equal(result.valid, true);
    assert.ok(result.warnings.some((w) => w.includes("refactor")));
  });

  test("multi-line message: only the first line is the subject", () => {
    const result = checkCommitMessage("agent: implement widget (CG-S5-PH0-008, Prompt 87)\n\nBody text here.");
    assert.equal(result.valid, true);
  });
});
