import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { sanitizeCsvCell, quoteCsvField, rowToSafeCsvLine, rowsToSafeCsv } from "./csv-export-sanitize.ts";

describe("sanitizeCsvCell", () => {
  test("prefixes a leading =", () => {
    assert.equal(sanitizeCsvCell("=cmd|'/c calc'!A1"), "'=cmd|'/c calc'!A1");
  });

  test("prefixes a leading +", () => {
    assert.equal(sanitizeCsvCell("+1+1"), "'+1+1");
  });

  test("prefixes a leading -", () => {
    assert.equal(sanitizeCsvCell("-2+3"), "'-2+3");
  });

  test("prefixes a leading @", () => {
    assert.equal(sanitizeCsvCell("@SUM(A1:A9)"), "'@SUM(A1:A9)");
  });

  test("prefixes a leading tab", () => {
    assert.equal(sanitizeCsvCell("\t=1+1"), "'\t=1+1");
  });

  test("leaves an ordinary value untouched", () => {
    assert.equal(sanitizeCsvCell("Jakarta Branch"), "Jakarta Branch");
  });

  test("leaves a negative-looking business value untouched only when it does not start with a trigger char", () => {
    assert.equal(sanitizeCsvCell("2026-07-26"), "2026-07-26");
  });

  test("does not mutate a hyphenated date that happens to start with a digit", () => {
    assert.equal(sanitizeCsvCell("0_2_days"), "0_2_days");
  });

  test("handles an empty string without indexing past the end", () => {
    assert.equal(sanitizeCsvCell(""), "");
  });
});

describe("quoteCsvField", () => {
  test("wraps a field containing a comma", () => {
    assert.equal(quoteCsvField("Acme, Co"), '"Acme, Co"');
  });

  test("doubles an embedded double quote", () => {
    assert.equal(quoteCsvField('Say "hi"'), '"Say ""hi"""');
  });

  test("leaves a plain field unquoted", () => {
    assert.equal(quoteCsvField("Jakarta"), "Jakarta");
  });
});

describe("rowToSafeCsvLine", () => {
  test("sanitizes and quotes a full row, coercing null/undefined to an empty cell", () => {
    assert.equal(rowToSafeCsvLine(["=SUM(A1)", "Acme, Co", null, undefined, 42, true]), "'=SUM(A1),\"Acme, Co\",,,42,true");
  });
});

describe("rowsToSafeCsv", () => {
  test("joins header and rows with CRLF line endings", () => {
    const csv = rowsToSafeCsv(["bucket", "lead_count"], [["0_2_days", 1], ["=cmd", 2]]);
    assert.equal(csv, "bucket,lead_count\r\n0_2_days,1\r\n'=cmd,2\r\n");
  });
});
