import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import {
  checkProtectedPaths,
  REVISION_0_19_CORRECTABLE_PROMPT_PATHS,
  REVISION_0_19_NEW_PROMPT_PATHS,
  REVISION_0_19_VERSION_LINE_ONLY_PATHS,
  STEP17_CORRECTABLE_PACKAGE_PATHS,
} from "./check-protected-paths.ts";

describe("checkProtectedPaths", () => {
  test("flags docs/blueprint/** as FORBIDDEN", () => {
    const findings = checkProtectedPaths(["docs/blueprint/02_CargoGrid_Business_Process_Product_Requirements_Blueprint.md"]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.severity, "FORBIDDEN");
  });

  test("flags docs/ai-agent-build-prompt-package/** as FORBIDDEN", () => {
    // Was `00-control/02_CONFIRMED_DECISION_REGISTER.md` until package revision 0.19.0, which
    // unlocked that file for its `**Package version:**` header line alone (see the
    // REVISION_0_19_VERSION_LINE_ONLY tests below). Re-pointed at a prompt file, which is the
    // asset the blanket rule exists to protect and which no narrowing has ever touched.
    const findings = checkProtectedPaths(["docs/ai-agent-build-prompt-package/07-phase-02-commercial/151_QUOTATION_BUILDER_PROMPT.md"]);
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
      // A governance template.
      "docs/ai-agent-build-prompt-package/01-agent-governance/10_MASTER_AGENT_SYSTEM_PROMPT.md",
      // Control files 00-03 used to be listed here, and CON-016 genuinely did leave all four
      // FORBIDDEN. Package revision 0.19.0 unlocked them for one header line (FPV-F009); they
      // are asserted CAUTION-with-the-narrow-reason below instead of being dropped, so the
      // boundary is still pinned in both directions -- it has only moved.
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

  // --- CON-017 / ADR-0028: package revision 0.19.0's enumerated prompt-file unlocks ----------
  // Same shape as CON-016's tests, plus one kind CON-016's set never needed: an existence
  // check. These lists name individual files by exact path, so a list entry that matches no
  // real file is not a harmless typo -- it means the file the revision actually wrote was
  // never unlocked, and the file the list names does not exist. That happened: the new-prompt
  // entry read `137_TENANT_MERGE_SPLIT_PROMPT.md` while the authored file was `431_…`, and
  // nothing but a manual gate run caught it. These two tests are why it cannot recur.

  test("CON-017: every enumerated unlock names a file that actually exists", () => {
    const all = [
      ...REVISION_0_19_CORRECTABLE_PROMPT_PATHS,
      ...REVISION_0_19_NEW_PROMPT_PATHS,
      ...REVISION_0_19_VERSION_LINE_ONLY_PATHS,
      ...STEP17_CORRECTABLE_PACKAGE_PATHS,
    ];
    const missing = all.filter((p) => !existsSync(p));
    assert.deepEqual(missing, [], "an unlock naming a non-existent file unlocks nothing and hides a real FORBIDDEN write");
  });

  test("CON-017: the unlocked prompt files are CAUTION, and cite ADR-0028 rather than CON-016", () => {
    const findings = checkProtectedPaths([
      ...REVISION_0_19_CORRECTABLE_PROMPT_PATHS,
      ...REVISION_0_19_NEW_PROMPT_PATHS,
    ]);
    assert.equal(findings.length, REVISION_0_19_CORRECTABLE_PROMPT_PATHS.length + REVISION_0_19_NEW_PROMPT_PATHS.length);
    assert.ok(findings.every((f) => f.severity === "CAUTION"));
    assert.ok(findings.every((f) => f.reason.includes("CON-017") && f.reason.includes("ADR-0028")),
      "a reader of the warning must be able to find the authority that permitted the write");
  });

  test("CON-017: the four version-line-only control files carry their own narrower reason", () => {
    const findings = checkProtectedPaths([...REVISION_0_19_VERSION_LINE_ONLY_PATHS]);
    assert.equal(findings.length, 4);
    assert.ok(findings.every((f) => f.severity === "CAUTION"));
    // The reason string is the only place the narrowness lives -- a path gate cannot tell a
    // version-line edit from a decision-row edit in 02/03, so the warning has to say so.
    assert.ok(findings.every((f) => f.reason.includes("Package version")),
      "the reason must name the single line this unlock covers");
    assert.ok(findings.every((f) => f.reason.includes("FPV-F009")));
  });

  test("CON-017 does not widen: a Phase 5 neighbour outside the enumerated cluster stays FORBIDDEN", () => {
    // 10-phase-05-advanced-tms-wms is the directory most of the unlocks live in, so a
    // directory-shaped mistake would show up here first. 244 was read by FPV-415 and is
    // deliberately NOT on any list.
    const findings = checkProtectedPaths([
      "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/244_ADVANCED_CLAIM_INCIDENT_PROMPT.md",
      // The new prompt's own neighbours in Platform Core.
      "docs/ai-agent-build-prompt-package/06-phase-01-platform-core/105_TENANT_PROVISIONING_LIFECYCLE_PROMPT.md",
      // And the number the new-prompt list wrongly named for a while: it does not exist, and
      // if it ever does it must not be pre-authorized.
      "docs/ai-agent-build-prompt-package/06-phase-01-platform-core/137_TENANT_MERGE_SPLIT_PROMPT.md",
    ]);
    assert.equal(findings.length, 3);
    assert.ok(findings.every((f) => f.severity === "FORBIDDEN"));
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
