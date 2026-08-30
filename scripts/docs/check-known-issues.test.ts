import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  CLOSED_STATUSES,
  KNOWN_ISSUES_PATH,
  VALID_STATUSES,
  checkKnownIssues,
  lastParentheticalSpan,
  parseHeading,
  parseKnownIssues,
  summarize,
} from "./check-known-issues.ts";

const HEADER = `# KNOWN_ISSUES.md

## 3. Issue index

| Issue ID | Severity | Status | Title |
|---|---|---|---|
`;

/** Builds a minimal but structurally real file: an index section and matching records. */
function build(rows: readonly string[], records: readonly string[]): string {
  return `${HEADER}${rows.join("\n")}\n\n## 4. Issue records\n\n${records.join("\n\n")}\n`;
}

describe("lastParentheticalSpan", () => {
  test("finds the final top-level group, not the first", () => {
    const h = "a (first) middle (last)";
    const span = lastParentheticalSpan(h);
    assert.equal(h.slice(span![0], span![1]), "(last)");
  });

  test("treats a nested group as part of its enclosing one", () => {
    const h = "x (outer (inner) tail)";
    const span = lastParentheticalSpan(h);
    assert.equal(h.slice(span![0], span![1]), "(outer (inner) tail)");
  });

  test("returns null when a heading has no parenthetical at all", () => {
    assert.equal(lastParentheticalSpan("no parens here"), null);
  });

  test("ignores an unclosed group rather than running to the end of the string", () => {
    const h = "a (closed) then (unclosed";
    const span = lastParentheticalSpan(h);
    assert.equal(h.slice(span![0], span![1]), "(closed)");
  });
});

describe("parseHeading", () => {
  test("reads status and severity from the final parenthetical", () => {
    const r = parseHeading("ISS-2026-001", "something broke (OPEN, High)", 1);
    assert.equal(r.status, "OPEN");
    assert.equal(r.severity, "High");
  });

  // The three regressions below are mistakes this session actually made while counting the
  // backlog by hand. Each produced a wrong number that reached a report.
  test("does NOT read a status word out of the heading's prose", () => {
    const r = parseHeading(
      "ISS-2026-284",
      "a fact drifted across 21 `VERIFIED` checkpoints because nothing re-checked it (OPEN, Medium)",
      1,
    );
    assert.equal(r.status, "OPEN", "the prose `VERIFIED` must not win over the declared status");
  });

  test("does NOT read a status out of a cross-reference to another issue", () => {
    const r = parseHeading("ISS-2026-104", "upstream of ISS-2026-072 (OPEN, High) in the same chain (RESOLVED, High)", 1);
    assert.equal(r.status, "RESOLVED");
  });

  test("takes the FIRST status in the final parenthetical, which is the record's own", () => {
    // The file's convention: "OPEN — partial, two of three sub-items RESOLVED".
    const r = parseHeading("ISS-2026-063", "query-budget mechanism has no test (OPEN — partial, two of three sub-items RESOLVED, Low)", 1);
    assert.equal(r.status, "OPEN", "a partially-closed record is open, not resolved");
  });

  test("reports a missing status as null rather than guessing", () => {
    const r = parseHeading("ISS-2026-002", "parallel-session collision (no single-writer discipline)", 1);
    assert.equal(r.status, null);
    assert.equal(r.severity, null);
  });
});

describe("checkKnownIssues", () => {
  test("a consistent file produces no findings", () => {
    const text = build(
      ["| `ISS-2026-001` | High | `OPEN` | a thing |"],
      ["### ISS-2026-001 — a thing (OPEN, High)\n\nbody"],
    );
    assert.deepEqual(checkKnownIssues(text), []);
  });

  // This is the exact drift that left the index covering 63 of 261 records.
  test("REJECTS a record with no index row", () => {
    const text = build(
      ["| `ISS-2026-001` | High | `OPEN` | a thing |"],
      ["### ISS-2026-001 — a thing (OPEN, High)\n\nbody", "### ISS-2026-002 — unindexed (OPEN, Low)\n\nbody"],
    );
    const f = checkKnownIssues(text);
    assert.equal(f.length, 1);
    assert.equal(f[0]?.code, "RECORD_WITHOUT_INDEX_ROW");
    assert.match(f[0]!.message, /ISS-2026-002/);
  });

  test("REJECTS an index row with no record", () => {
    const text = build(
      ["| `ISS-2026-001` | High | `OPEN` | a thing |", "| `ISS-2026-999` | Low | `OPEN` | ghost |"],
      ["### ISS-2026-001 — a thing (OPEN, High)\n\nbody"],
    );
    const codes = checkKnownIssues(text).map((x) => x.code);
    assert.ok(codes.includes("INDEX_ROW_WITHOUT_RECORD"));
  });

  // The defect that made every backlog count wrong: heading and index disagreeing.
  test("REJECTS a status disagreement between the index and the record's own heading", () => {
    const text = build(
      ["| `ISS-2026-001` | High | `OPEN` | a thing |"],
      ["### ISS-2026-001 — a thing (RESOLVED, High)\n\nbody"],
    );
    const f = checkKnownIssues(text);
    assert.equal(f.length, 1);
    assert.equal(f[0]?.code, "STATUS_DISAGREEMENT");
    assert.match(f[0]!.message, /§3 says OPEN.*heading says RESOLVED/);
  });

  test("REJECTS a severity disagreement", () => {
    const text = build(
      ["| `ISS-2026-001` | Low | `OPEN` | a thing |"],
      ["### ISS-2026-001 — a thing (OPEN, High)\n\nbody"],
    );
    assert.equal(checkKnownIssues(text)[0]?.code, "SEVERITY_DISAGREEMENT");
  });

  test("REJECTS a status outside the §1 vocabulary rather than accepting a new one", () => {
    const text = build(
      ["| `ISS-2026-001` | High | `MOSTLY_FIXED` | a thing |"],
      ["### ISS-2026-001 — a thing (OPEN, High)\n\nbody"],
    );
    const codes = checkKnownIssues(text).map((x) => x.code);
    assert.ok(codes.includes("UNKNOWN_STATUS"));
  });

  test("REJECTS a record whose heading declares no status", () => {
    const text = build(
      ["| `ISS-2026-001` | High | `OPEN` | a thing |"],
      ["### ISS-2026-001 — a thing with no declared status\n\nbody"],
    );
    const codes = checkKnownIssues(text).map((x) => x.code);
    assert.ok(codes.includes("RECORD_NO_STATUS"));
    assert.ok(codes.includes("RECORD_NO_SEVERITY"));
  });

  test("REJECTS duplicate ids in either section", () => {
    const text = build(
      ["| `ISS-2026-001` | High | `OPEN` | a thing |", "| `ISS-2026-001` | High | `OPEN` | again |"],
      ["### ISS-2026-001 — a thing (OPEN, High)\n\nbody", "### ISS-2026-001 — again (OPEN, High)\n\nbody"],
    );
    const codes = checkKnownIssues(text).map((x) => x.code);
    assert.ok(codes.includes("DUPLICATE_RECORD"));
    assert.ok(codes.includes("DUPLICATE_INDEX_ROW"));
  });

  test("does not read a §4 narrative table as index rows", () => {
    // §4 records contain their own tables whose first cell can be an issue id. Picking those up
    // would manufacture phantom index rows for records that genuinely have none.
    const text = build(
      ["| `ISS-2026-001` | High | `OPEN` | a thing |"],
      ["### ISS-2026-001 — a thing (OPEN, High)\n\n| `ISS-2026-999` | Low | `OPEN` | inside a record |"],
    );
    assert.deepEqual(checkKnownIssues(text), []);
  });
});

describe("summarize", () => {
  test("counts accepted dispositions apart from open work", () => {
    const text = build(
      [
        "| `ISS-2026-001` | High | `OPEN` | a |",
        "| `ISS-2026-002` | Low | `ACCEPTED_RISK` | b |",
        "| `ISS-2026-003` | Low | `RESOLVED` | c |",
      ],
      [
        "### ISS-2026-001 — a (OPEN, High)\n\nx",
        "### ISS-2026-002 — b (ACCEPTED_RISK, Low)\n\nx",
        "### ISS-2026-003 — c (RESOLVED, Low)\n\nx",
      ],
    );
    const s = summarize(text);
    assert.deepEqual(
      { total: s.total, open: s.open, accepted: s.accepted, closed: s.closed },
      { total: 3, open: 1, accepted: 1, closed: 1 },
      "an accepted risk is a disposition, not a to-do and not a fix",
    );
    assert.deepEqual(s.openBySeverity, { High: 1 });
  });

  test("every closed status is in the valid vocabulary", () => {
    for (const s of CLOSED_STATUSES) assert.ok((VALID_STATUSES as readonly string[]).includes(s), s);
  });
});

describe("the real ledger", () => {
  test("docs/runtime/KNOWN_ISSUES.md passes with zero findings", () => {
    const text = readFileSync(KNOWN_ISSUES_PATH, "utf8");
    const findings = checkKnownIssues(text);
    assert.deepEqual(findings, [], `ledger problems:\n${findings.map((f) => `${f.code} ${f.message}`).join("\n")}`);
  });

  test("the index covers every record, both ways", () => {
    const { records, indexRows } = parseKnownIssues(readFileSync(KNOWN_ISSUES_PATH, "utf8"));
    assert.ok(records.length > 250, "sanity: the parser found the records at all");
    assert.equal(
      indexRows.length,
      records.length,
      "the index once carried 63 rows for 261 records; that is the state this asserts against",
    );
  });
});
