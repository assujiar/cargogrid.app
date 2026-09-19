import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseCsvToRows, CsvParseError } from "./csv-import-parse.ts";

describe("parseCsvToRows", () => {
  test("parses a simple header + rows document", () => {
    const rows = parseCsvToRows("a,b\n1,2\n3,4\n");
    assert.deepEqual(rows, [
      { a: "1", b: "2" },
      { a: "3", b: "4" },
    ]);
  });

  test("handles CRLF line endings", () => {
    const rows = parseCsvToRows("a,b\r\n1,2\r\n");
    assert.deepEqual(rows, [{ a: "1", b: "2" }]);
  });

  test("handles quoted fields containing commas and embedded newlines", () => {
    const rows = parseCsvToRows('name,note\n"Acme, Inc.","line one\nline two"\n');
    assert.deepEqual(rows, [{ name: "Acme, Inc.", note: "line one\nline two" }]);
  });

  test("handles a doubled quote as one literal quote inside a quoted field", () => {
    const rows = parseCsvToRows('name\n"Say ""hi"""\n');
    assert.deepEqual(rows, [{ name: 'Say "hi"' }]);
  });

  test("does not sanitize a legitimate negative number", () => {
    const rows = parseCsvToRows("amount\n-5\n");
    assert.deepEqual(rows, [{ amount: "-5" }]);
  });

  test("skips a trailing blank line", () => {
    const rows = parseCsvToRows("a\n1\n\n");
    assert.deepEqual(rows, [{ a: "1" }]);
  });

  test("throws CsvParseError on an empty file", () => {
    assert.throws(() => parseCsvToRows(""), CsvParseError);
  });

  test("throws CsvParseError on an empty header column name", () => {
    assert.throws(() => parseCsvToRows("a,\n1,2\n"), CsvParseError);
  });

  test("throws CsvParseError naming the line when a row's column count does not match the header", () => {
    assert.throws(() => parseCsvToRows("a,b\n1\n"), (error: unknown) => {
      assert.ok(error instanceof CsvParseError);
      assert.match(error.message, /line 2/);
      return true;
    });
  });

  test("throws CsvParseError on an unterminated quoted field", () => {
    assert.throws(() => parseCsvToRows('a\n"unterminated\n'), CsvParseError);
  });
});
