import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { checkProtectedPaths, STEP17_CORRECTABLE_PACKAGE_PATHS } from "./check-protected-paths.ts";

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
    // A bare path with no known git status is the conservative case (e.g. a
    // manual single-path check) -- still flagged, since "no status" cannot
    // prove the file is new.
    const bareFindings = checkProtectedPaths(["supabase/migrations/20260101000000_init.sql"]);
    assert.equal(bareFindings.length, 1);
    assert.equal(bareFindings[0]?.severity, "FORBIDDEN");

    // A real git-status-aware entry is what `main()` actually passes
    // (`git diff --name-status`). Status "M" (modifying an already-applied
    // migration) is FORBIDDEN...
    const modified = checkProtectedPaths([{ path: "supabase/migrations/20260101000000_init.sql", status: "M" }]);
    assert.equal(modified.length, 1);
    assert.equal(modified[0]?.severity, "FORBIDDEN");

    // ...but status "A" (a brand-new migration file, never previously
    // committed -- the normal, expected shape of every checkpoint's own new
    // migration) must NOT be flagged. Regression test for the real defect
    // this repository's own git:check-paths gate exhibited every checkpoint
    // that added a new migration: the path-pattern-only check could never
    // tell a new file from an edit to an applied one, so it flagged both
    // identically -- confirmed live (ATW-017, 2026-08-04) when running the
    // gate against a real staged new-migration diff for the first time.
    const added = checkProtectedPaths([{ path: "supabase/migrations/20260101000000_init.sql", status: "A" }]);
    assert.equal(added.length, 0);
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

  // --- CON-016 / ADR-0026: Step 17's four correctable package-metadata paths ---------------
  // The narrowing is deliberately tiny (5 of the package's 430 files). These tests pin BOTH
  // directions, because the risk of a path-based exemption is always that it is wider than
  // it reads.

  test("CON-016: the five Step 17 metadata paths are CAUTION, not FORBIDDEN", () => {
    const findings = checkProtectedPaths([...STEP17_CORRECTABLE_PACKAGE_PATHS]);
    assert.equal(findings.length, 5);
    assert.ok(findings.every((f) => f.severity === "CAUTION"), "all five must be CAUTION");
    assert.ok(findings.every((f) => f.reason.includes("CON-016")), "reason must cite its authority");
  });

  test("CON-016 does not widen: prompt files and step READMEs stay FORBIDDEN", () => {
    const stillForbidden = [
      // An executable prompt file -- the asset the FORBIDDEN rule exists to protect.
      "docs/ai-agent-build-prompt-package/17-final-validation/415_REQUIREMENT_COVERAGE_AUDIT_PROMPT.md",
      "docs/ai-agent-build-prompt-package/17-final-validation/430_FINAL_PACKAGE_VALIDATION_CLOSURE_VERIFICATION_PROMPT.md",
      // A step README.
      "docs/ai-agent-build-prompt-package/17-final-validation/413_FINAL_PACKAGE_VALIDATION_README.md",
      // Control files NOT in the exemption -- 02/03 stay decision-change-protocol-only.
      "docs/ai-agent-build-prompt-package/00-control/00_PACKAGE_README.md",
      "docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md",
      "docs/ai-agent-build-prompt-package/00-control/03_ASSUMPTION_REGISTER.md",
      "docs/ai-agent-build-prompt-package/00-control/01_SOURCE_OF_TRUTH_MATRIX.md",
      // A governance template.
      "docs/ai-agent-build-prompt-package/01-agent-governance/10_MASTER_AGENT_SYSTEM_PROMPT.md",
    ];
    const findings = checkProtectedPaths(stillForbidden);
    assert.equal(findings.length, stillForbidden.length);
    assert.ok(findings.every((f) => f.severity === "FORBIDDEN"), "none of these may be exempted");
  });

  test("CON-016 matches literally, not by prefix or directory", () => {
    // A neighbour in the same directory, a same-named file elsewhere, and a path that merely
    // extends an exempt one must all still be FORBIDDEN. This is the concrete failure mode a
    // prefix/glob exemption would have.
    const nearMisses = [
      "docs/ai-agent-build-prompt-package/00-control/08_SOMETHING_NEW.md",
      "docs/ai-agent-build-prompt-package/17-final-validation/START_HERE.md",
      "docs/ai-agent-build-prompt-package/00-control/07_PROMPT_PACKAGE_MANIFEST.md.bak",
      "docs/ai-agent-build-prompt-package/START_HERE.md.orig",
    ];
    const findings = checkProtectedPaths(nearMisses);
    assert.equal(findings.length, nearMisses.length);
    assert.ok(findings.every((f) => f.severity === "FORBIDDEN"), `near-miss paths must not be exempted: ${JSON.stringify(findings)}`);
  });

  test("CON-016: first match wins, so exactly one finding is produced per exempt path", () => {
    // Regression guard for the ordering bug this narrowing could have had: if the blanket
    // package rule also fired, the path would still carry a FORBIDDEN finding and the gate
    // would still block, silently defeating the exemption.
    const findings = checkProtectedPaths(["docs/ai-agent-build-prompt-package/START_HERE.md"]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.severity, "CAUTION");
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
