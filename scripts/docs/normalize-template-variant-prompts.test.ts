/**
 * Tests for the transform that closed `FPV-F003`/`FPV-F004` at package revision `0.19.0`
 * (`ADR-0028`).
 *
 * The transform itself is trivial. `verifyOnlyPermittedDifferences` is not, and it is the
 * whole safety argument for a change that rewrote 14 prompt files and 70 headings inside a
 * package Step 17 had just certified. "The verifier passed" is worth exactly nothing unless
 * the verifier actually rejects a corrupting transform — a function that returns `null`
 * unconditionally would also have "passed".
 *
 * So the tests below spend most of their effort on the negative direction: proving the
 * verifier catches a dropped line, an added line, a mangled character, and a change that
 * hides inside a line the transform is allowed to touch.
 */

import { describe, test } from "node:test";
import assert from "node:assert/strict";

import {
  canonicalHeadingFor,
  canonicalizeHeadings,
  deindent,
  normalizeAll,
  verifyOnlyPermittedDifferences,
} from "./normalize-template-variant-prompts.ts";
import { KNOWN_TEMPLATE_VARIANT_FILES, LEGACY_HEADING_VARIANTS } from "./check-prompt-package.ts";

/** A miniature stand-in for the real defect: indented body, legacy heading wording. */
const INDENTED = [
  "# Prompt 222 — Advanced Dispatch Board",
  "",
  "    **Prompt ID:** `CG-S10-ATW-003`",
  "",
  "    ## 1. Prompt ID",
  "",
  "    `{{TASK_ID}}` maps to `CG-S10-ATW-003`.",
  "",
  "    ## 14. API and integration impact",
  "",
  "    Provide shared REST/GraphQL reads.",
  "",
  "    | Column | Value |",
  "    |---|---|",
  "    | a | b |",
  "",
].join("\n");

describe("deindent", () => {
  test("strips exactly one four-space indent from every line that carries one", () => {
    const { text, count } = deindent(INDENTED);
    assert.equal(count, 8, "8 of the 16 lines carry the indent; the blank lines and the H1 do not");
    assert.ok(text.includes("\n## 1. Prompt ID\n"), "headings reach column 0");
    assert.ok(text.includes("\n| Column | Value |\n"), "table rows reach column 0");
    assert.ok(text.startsWith("# Prompt 222"), "an unindented line is untouched");
  });

  test("strips one level only, so deeper indentation survives as real indentation", () => {
    // This matters: inside a prompt, an eight-space line is a genuine nested list or code
    // sample. Stripping to column 0 would change the rendered meaning, not just the wrapper.
    const { text } = deindent("    ## 20. Tasks\n        1. a nested item\n");
    assert.equal(text, "## 20. Tasks\n    1. a nested item\n");
  });

  test("leaves a line with fewer than four leading spaces alone", () => {
    const { text, count } = deindent("  two spaces\n   three spaces\n");
    assert.equal(count, 0);
    assert.equal(text, "  two spaces\n   three spaces\n");
  });

  test("is idempotent — running it on already-normalized text changes nothing", () => {
    const once = deindent(INDENTED).text;
    const twice = deindent(once);
    assert.equal(twice.count, 0);
    assert.equal(twice.text, once);
  });
});

describe("canonicalHeadingFor", () => {
  test("derives the canonical wording from REQUIRED_PROMPT_HEADINGS rather than restating it", () => {
    // The point of deriving: this script cannot drift from the validator that enforces the result.
    assert.equal(canonicalHeadingFor(14), "14. API impact");
    assert.equal(canonicalHeadingFor(16), "16. Security impact");
  });

  test("throws rather than guessing when a field number has no canonical heading", () => {
    assert.throws(() => canonicalHeadingFor(99), /no canonical heading for field 99/);
  });
});

describe("canonicalizeHeadings", () => {
  test("replaces a legacy heading with the canonical wording", () => {
    const { text, count } = canonicalizeHeadings("## 14. API and integration impact\n");
    assert.equal(count, 1);
    assert.equal(text, "## 14. API impact\n");
  });

  test("only matches at heading position, so the legacy phrase inside prose survives", () => {
    const prose = "See 14. API and integration impact for detail.\n";
    const { text, count } = canonicalizeHeadings(prose);
    assert.equal(count, 0, "no `## ` prefix, so it is body text, not a heading");
    assert.equal(text, prose);
  });

  test("covers every legacy variant the validator knows about", () => {
    const all = Object.values(LEGACY_HEADING_VARIANTS).map((h) => `## ${h}`).join("\n");
    const { count } = canonicalizeHeadings(all);
    assert.equal(count, Object.keys(LEGACY_HEADING_VARIANTS).length);
  });
});

describe("verifyOnlyPermittedDifferences — the proof", () => {
  test("permits the two intended differences", () => {
    const transformed = canonicalizeHeadings(deindent(INDENTED).text).text;
    assert.equal(verifyOnlyPermittedDifferences(INDENTED, transformed), null);
  });

  test("permits nothing at all when nothing changed", () => {
    assert.equal(verifyOnlyPermittedDifferences(INDENTED, INDENTED), null);
  });

  // Everything below is the direction that matters. A verifier that never rejects is not a
  // verifier, and each of these is a real way a hand-applied edit to 14 files goes wrong.

  test("REJECTS a dropped line, and names it", () => {
    const good = canonicalizeHeadings(deindent(INDENTED).text).text;
    const lines = good.split("\n");
    const dropped = [...lines.slice(0, 12), ...lines.slice(13)].join("\n");
    const problem = verifyOnlyPermittedDifferences(INDENTED, dropped);
    assert.ok(problem, "a lost table row must not pass");
    assert.match(problem, /^line 13:/, "the report is actionable, not just 'differs'");
  });

  test("REJECTS an added line", () => {
    const good = canonicalizeHeadings(deindent(INDENTED).text).text;
    const problem = verifyOnlyPermittedDifferences(INDENTED, `${good}\nan extra sentence\n`);
    assert.ok(problem, "an accidental paste must not pass");
  });

  test("REJECTS a single mangled character", () => {
    // The failure a human reviewer reliably misses across 14 files: one backtick gone.
    const good = canonicalizeHeadings(deindent(INDENTED).text).text;
    const mangled = good.replace("`CG-S10-ATW-003`", "CG-S10-ATW-003`");
    assert.notEqual(mangled, good, "fixture guard: the mangling must actually apply");
    assert.ok(verifyOnlyPermittedDifferences(INDENTED, mangled));
  });

  test("REJECTS a substantive edit hidden inside a line the transform is allowed to touch", () => {
    // The subtlest case: the line legitimately loses its indent, and its words change too.
    // Reducing both sides erases the indent, so the word change stands exposed.
    const good = canonicalizeHeadings(deindent(INDENTED).text).text;
    const reworded = good.replace("Provide shared REST/GraphQL reads.", "Provide direct database reads.");
    assert.notEqual(reworded, good, "fixture guard");
    const problem = verifyOnlyPermittedDifferences(INDENTED, reworded);
    assert.ok(problem, "changing what a prompt tells an agent to build must never pass as mechanical");
    assert.match(problem, /database reads/);
  });

  test("REJECTS canonicalizing a heading to the wrong field's wording", () => {
    const good = canonicalizeHeadings(deindent(INDENTED).text).text;
    const crossed = good.replace("## 14. API impact", "## 14. Security impact");
    assert.ok(verifyOnlyPermittedDifferences(INDENTED, crossed));
  });

  test("REJECTS a length mismatch even when every compared line agrees", () => {
    const good = canonicalizeHeadings(deindent(INDENTED).text).text;
    const problem = verifyOnlyPermittedDifferences(INDENTED, `${good}\n`);
    assert.ok(problem);
  });
});

describe("FPV-F003 closure, asserted from the script's own side", () => {
  test("the allowlist is empty, so there is nothing left for this script to normalize", () => {
    // The two halves of the closure must agree. check-prompt-package.test.ts asserts the
    // package has 0 indented bodies; this asserts no file is still exempted from that rule.
    // Either alone could be true while the defect persisted.
    assert.deepEqual([...KNOWN_TEMPLATE_VARIANT_FILES], []);
    assert.deepEqual([...normalizeAll(false)], [], "a no-op over an empty list, not a silent skip");
  });
});
