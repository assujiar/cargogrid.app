import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { extractCheckablePaths, checkLinks, checkAdrIndexConsistency, checkHandoffTaskCoherence, checkCanonicalRuntimeFiles } from "./check-doc-links.ts";

describe("extractCheckablePaths", () => {
  test("extracts a concrete repository-relative path with a real extension", () => {
    const paths = extractCheckablePaths("See `docs/standards/CODING_STANDARDS.md` §6 for the rationale.");
    assert.deepEqual(paths, ["docs/standards/CODING_STANDARDS.md"]);
  });

  test("extracts an allowlisted root file", () => {
    assert.deepEqual(extractCheckablePaths("Read `AGENTS.md` first."), ["AGENTS.md"]);
    assert.deepEqual(extractCheckablePaths("See `package.json`."), ["package.json"]);
  });

  test("strips a trailing anchor before checking existence", () => {
    assert.deepEqual(extractCheckablePaths("`docs/adr/README.md#5-open` explains this."), ["docs/adr/README.md"]);
  });

  test("skips a glob citation containing a wildcard", () => {
    assert.deepEqual(extractCheckablePaths("See `docs/architecture/01_*.md`–`13_*.md`."), []);
  });

  test("skips a template placeholder", () => {
    assert.deepEqual(extractCheckablePaths("Link: `{{LINK_OR_NONE}}`."), []);
  });

  test("skips a bare filename with no directory prefix", () => {
    assert.deepEqual(extractCheckablePaths("See `PH0-90.md` for detail."), []);
  });

  test("skips an angle-bracket domain placeholder", () => {
    assert.deepEqual(extractCheckablePaths("Per-domain factory: `tests/factories/<domain>.ts`."), []);
  });

  test("skips an npm/node module specifier", () => {
    assert.deepEqual(extractCheckablePaths("Uses `node:test` and `@playwright/test`."), []);
  });

  test("skips a shell command (contains a space)", () => {
    assert.deepEqual(extractCheckablePaths("Run `pnpm run test` first."), []);
  });

  test("skips a bare ID with no path-like prefix or extension", () => {
    assert.deepEqual(extractCheckablePaths("Task `CG-S5-PH0-012` is VERIFIED."), []);
  });

  test("skips an en-dash range's second bare span while keeping the first concrete one", () => {
    assert.deepEqual(extractCheckablePaths("See `docs/build-log/phase-00/PH0-83.md`–`PH0-90.md`."), ["docs/build-log/phase-00/PH0-83.md"]);
  });
});

describe("checkLinks", () => {
  test("finds zero broken links across this repository's real, already-authored docs", () => {
    const issues = checkLinks(["docs/adr/README.md", "docs/standards/DOCUMENTATION_STANDARDS.md", "AGENTS.md"]);
    assert.deepEqual(issues, []);
  });

  test("does not scan a file outside the checked prefixes", () => {
    const issues = checkLinks(["docs/blueprint/tes.md"]);
    assert.deepEqual(issues, []);
  });

  test("does not scan a non-markdown file", () => {
    const issues = checkLinks(["package.json"]);
    assert.deepEqual(issues, []);
  });

  test("excludes the two forward-referencing Phase 0 planning documents (regression guard)", () => {
    const issues = checkLinks(["docs/build-log/phase-00/00_PHASE0_EXECUTION_INDEX.md", "docs/build-log/phase-00/00_PHASE0_WBS.md"]);
    assert.deepEqual(issues, []);
  });

  test("excuses the known, disclosed historical docs/build-logs/ references without hiding a genuinely new break", () => {
    const issues = checkLinks(["docs/runtime/CHANGE_MANIFEST.md", "docs/runtime/ERROR_LEDGER.md"]);
    assert.deepEqual(issues, []);
  });

  test("excuses PH0-99.md's failure-matrix quote of a not-yet-created runbook path (ISS-2026-008-adjacent, file-scoped not global)", () => {
    const issues = checkLinks(["docs/build-log/phase-00/PH0-99.md"]);
    assert.deepEqual(issues, []);
  });
});

describe("checkCanonicalRuntimeFiles", () => {
  test("finds all 7 required runtime files present and non-empty in this repository", () => {
    const issues = checkCanonicalRuntimeFiles();
    assert.deepEqual(issues, []);
  });
});

describe("checkAdrIndexConsistency", () => {
  test("flags an index row with no matching ADR file", () => {
    const fixture = "## 6. Index of accepted/active ADRs\n\n| ADR | Title |\n|---|---|\n| `ADR-9999` | Nonexistent |\n";
    const issues = checkAdrIndexConsistency(fixture);
    assert.equal(issues.length, 1);
    assert.equal(issues[0]?.kind, "ADR_INDEX_MISMATCH");
  });

  test("passes when every indexed ADR has a matching file", () => {
    const fixture = "## 6. Index of accepted/active ADRs\n\n| ADR | Title |\n|---|---|\n| `ADR-0001` | No empty domain-folder stubs |\n";
    const issues = checkAdrIndexConsistency(fixture);
    assert.deepEqual(issues, []);
  });
});

describe("checkHandoffTaskCoherence", () => {
  test("flags a HANDOFF active task with no matching TASK_LEDGER row", () => {
    const handoff = "| Task ID/name | `CG-S9-FAKE-999` — Fake Task |";
    const ledger = "| `CG-S5-PH0-012` | Testing Foundation |";
    const issues = checkHandoffTaskCoherence(handoff, ledger);
    assert.equal(issues.length, 1);
    assert.equal(issues[0]?.kind, "HANDOFF_TASK_MISMATCH");
  });

  test("passes when the active task has a matching TASK_LEDGER row", () => {
    const handoff = "| Task ID/name | `CG-S5-PH0-013` — Documentation Foundation |";
    const ledger = "| `CG-S5-PH0-013` | Documentation Foundation |";
    const issues = checkHandoffTaskCoherence(handoff, ledger);
    assert.deepEqual(issues, []);
  });

  test("flags a missing Task ID/name row entirely", () => {
    const issues = checkHandoffTaskCoherence("no such row here", "irrelevant");
    assert.equal(issues.length, 1);
    assert.match(issues[0]?.detail ?? "", /no '\| Task ID\/name/);
  });
});
