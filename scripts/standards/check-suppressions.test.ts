import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { checkFileContent } from "./check-suppressions.ts";

const TODAY = "2026-07-15";

describe("checkFileContent", () => {
  test("flags a bare eslint-disable-next-line with no metadata", () => {
    const content = ["// eslint-disable-next-line no-console", "console.log('x');"].join("\n");
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 1);
    assert.equal(violations[0]?.kind, "MISSING_METADATA");
    assert.equal(violations[0]?.line, 1);
  });

  test("accepts a suppression with full valid metadata on the same line", () => {
    const content =
      "// eslint-disable-next-line no-console -- SUPPRESS(owner=alice, reason=temporary debug log, expires=2026-12-31, adr=NONE)\nconsole.log('x');";
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 0);
  });

  test("accepts metadata on the line immediately above", () => {
    const content = [
      "// SUPPRESS(owner=bob, reason=known false positive, expires=2027-01-01, adr=NONE)",
      "// eslint-disable-next-line no-unused-vars",
      "const x = 1;",
    ].join("\n");
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 0);
  });

  test("flags an expired suppression", () => {
    const content = "// eslint-disable-next-line no-console -- SUPPRESS(owner=carol, reason=old, expires=2020-01-01, adr=NONE)\nconsole.log('x');";
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 1);
    assert.equal(violations[0]?.kind, "EXPIRED");
  });

  test("does not flag a suppression expiring in the future", () => {
    const content = "// eslint-disable-next-line no-console -- SUPPRESS(owner=carol, reason=ok, expires=2099-01-01, adr=NONE)\nconsole.log('x');";
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 0);
  });

  test("expires=NONE is never treated as expired", () => {
    const content = "// eslint-disable-next-line no-console -- SUPPRESS(owner=dave, reason=standing exception, expires=NONE, adr=ADR-0001)";
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 0);
  });

  test("flags @ts-ignore as discouraged even with valid metadata (in addition to, not instead of, metadata check)", () => {
    const content = "// @ts-ignore -- SUPPRESS(owner=eve, reason=lib types wrong, expires=2027-01-01, adr=NONE)";
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 1);
    assert.equal(violations[0]?.kind, "TS_IGNORE_DISCOURAGED");
  });

  test("@ts-expect-error is not flagged as discouraged", () => {
    const content = "// @ts-expect-error -- SUPPRESS(owner=eve, reason=lib types wrong, expires=2027-01-01, adr=NONE)";
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 0);
  });

  test("a file with no suppression markers at all has zero violations", () => {
    const content = "export function add(a: number, b: number): number {\n  return a + b;\n}\n";
    const violations = checkFileContent("fixture.ts", content, TODAY);
    assert.equal(violations.length, 0);
  });

  test("this repository's own tracked source currently has zero suppression-governance violations", async () => {
    const { checkRepository } = await import("./check-suppressions.ts");
    const violations = checkRepository(TODAY);
    assert.deepEqual(violations, [], `unexpected violations: ${JSON.stringify(violations)}`);
  });
});
