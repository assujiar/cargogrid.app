import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { checkProtectedPaths } from "./check-protected-paths.ts";

describe("checkProtectedPaths", () => {
  test("flags docs/blueprint/** as FORBIDDEN", () => {
    const findings = checkProtectedPaths(["docs/blueprint/02_CargoGrid_Business_Process_Product_Requirements_Blueprint.md"]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.severity, "FORBIDDEN");
  });

  test("flags docs/ai-agent-build-prompt-package/** as FORBIDDEN", () => {
    const findings = checkProtectedPaths(["docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md"]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.severity, "FORBIDDEN");
  });

  test("flags an applied migration as FORBIDDEN, but not a new/unapplied one", () => {
    const findings = checkProtectedPaths(["supabase/migrations/20260101000000_init.sql"]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.severity, "FORBIDDEN");
  });

  test("flags .env / .env.local as FORBIDDEN but not .env.example", () => {
    const findings = checkProtectedPaths([".env.local", ".env.example"]);
    const flaggedPaths = findings.map((f) => f.path);
    assert.ok(flaggedPaths.includes(".env.local"));
    assert.ok(!flaggedPaths.includes(".env.example"));
  });

  test("flags docs/architecture/** and docs/runtime/** as CAUTION, not FORBIDDEN", () => {
    const findings = checkProtectedPaths(["docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md", "docs/runtime/TASK_LEDGER.md"]);
    assert.equal(findings.length, 2);
    assert.ok(findings.every((f) => f.severity === "CAUTION"));
  });

  test("does not flag ordinary source paths", () => {
    const findings = checkProtectedPaths(["scripts/git/check-protected-paths.ts", "README.md", "package.json"]);
    assert.equal(findings.length, 0);
  });

  test("this checkpoint's own real changed-file set produces the expected mix", () => {
    // Real paths from this exact task's own checkpoint (docs/build-log/phase-00/PH0-87.md §6).
    const findings = checkProtectedPaths([
      "docs/git/GIT_STRATEGY.md",
      "scripts/git/check-protected-paths.ts",
      "docs/runtime/TASK_LEDGER.md",
      "docs/build-log/phase-00/PH0-87.md",
    ]);
    const forbidden = findings.filter((f) => f.severity === "FORBIDDEN");
    const caution = findings.filter((f) => f.severity === "CAUTION");
    assert.equal(forbidden.length, 0);
    assert.equal(caution.length, 1);
    assert.equal(caution[0]?.path, "docs/runtime/TASK_LEDGER.md");
  });
});
