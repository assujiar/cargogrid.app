import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { buildHrisExport, hrisExportErrorMessage } from "./hris-export-action.ts";
import { HrisExportQueryError } from "../../server/queries/hris-export.ts";

const NOW = new Date("2026-08-31T10:00:00.000Z");

const HEADER = ["Employee", "Minutes"] as const;
interface Row {
  readonly employee: string;
  readonly minutes: number;
}
const toCells = (row: Row) => [row.employee, row.minutes];

describe("buildHrisExport", () => {
  test("produces a sanitized CSV, a dated filename, and a row count", async () => {
    const result = await buildHrisExport<Row>({
      fromDate: "2026-08-01",
      toDate: "2026-08-31",
      filenameStem: "timesheet-entries",
      header: HEADER,
      fetchRows: async () => [{ employee: "Ada", minutes: 480 }],
      toCells,
      now: NOW,
    });
    assert.equal(result.error, null);
    assert.equal(result.rowCount, 1);
    assert.equal(result.filename, "timesheet-entries-2026-08-01-to-2026-08-31.csv");
    assert.equal(result.csv, "Employee,Minutes\r\nAda,480\r\n");
  });

  test("neutralises a formula-injection cell rather than emitting it raw", async () => {
    const result = await buildHrisExport<Row>({
      fromDate: "2026-08-01",
      toDate: "2026-08-31",
      filenameStem: "x",
      header: HEADER,
      // A real employee name can start with any of the trigger characters, and a
      // malicious one is chosen to. Either way the spreadsheet must render it as text.
      fetchRows: async () => [{ employee: "=1+1", minutes: 0 }],
      toCells,
      now: NOW,
    });
    assert.ok(result.csv?.includes("'=1+1"), `expected the leading apostrophe guard, got ${result.csv}`);
  });

  test("passes the parsed range straight through to the fetcher", async () => {
    let seen: { fromDate: string; toDate: string } | null = null;
    await buildHrisExport<Row>({
      fromDate: "2026-01-02",
      toDate: "2026-01-03",
      filenameStem: "x",
      header: HEADER,
      fetchRows: async (range) => {
        seen = range;
        return [];
      },
      toCells,
      now: NOW,
    });
    assert.deepEqual(seen, { fromDate: "2026-01-02", toDate: "2026-01-03" });
  });

  test("an empty range yields no file at all -- an empty spreadsheet would read as 'nothing happened'", async () => {
    const result = await buildHrisExport<Row>({
      fromDate: "2026-08-01",
      toDate: "2026-08-31",
      filenameStem: "x",
      header: HEADER,
      fetchRows: async () => [],
      toCells,
      now: NOW,
    });
    assert.equal(result.error, null);
    assert.equal(result.csv, null);
    assert.equal(result.filename, null);
    assert.equal(result.rowCount, 0);
    // Still a token, so the form can say "no rows" rather than staying blank.
    assert.ok(result.token);
  });

  test("a malformed date is refused without calling the fetcher", async () => {
    let called = false;
    const result = await buildHrisExport<Row>({
      fromDate: "not-a-date",
      toDate: "2026-08-31",
      filenameStem: "x",
      header: HEADER,
      fetchRows: async () => {
        called = true;
        return [];
      },
      toCells,
      now: NOW,
    });
    assert.equal(called, false);
    assert.match(result.error ?? "", /from-date/);
    assert.equal(result.token, null);
  });

  test("an authority failure becomes a message about permission, never an empty file", async () => {
    const result = await buildHrisExport<Row>({
      fromDate: "2026-08-01",
      toDate: "2026-08-31",
      filenameStem: "x",
      header: HEADER,
      fetchRows: async () => {
        throw new HrisExportQueryError("insufficient_authority: HRS:Export is required to export HR data (no_role_grants_permission)");
      },
      toCells,
      now: NOW,
    });
    assert.match(result.error ?? "", /permission to export HR data/);
    assert.equal(result.csv, null);
    // No token: nothing was produced, so the form must not render a "0 rows" result
    // that would read as "the range was empty".
    assert.equal(result.token, null);
  });

  test("the filename stem is constrained, not trusted", async () => {
    const result = await buildHrisExport<Row>({
      fromDate: "2026-08-01",
      toDate: "2026-08-31",
      filenameStem: "../../etc/passwd",
      header: HEADER,
      fetchRows: async () => [{ employee: "Ada", minutes: 1 }],
      toCells,
      now: NOW,
    });
    assert.equal(result.filename, "etc-passwd-2026-08-01-to-2026-08-31.csv");
  });

  test("two exports of the same range carry different tokens, so the second still downloads", async () => {
    const run = (now: Date) =>
      buildHrisExport<Row>({
        fromDate: "2026-08-01",
        toDate: "2026-08-31",
        filenameStem: "x",
        header: HEADER,
        fetchRows: async () => [{ employee: "Ada", minutes: 1 }],
        toCells,
        now,
      });
    const first = await run(new Date("2026-08-31T10:00:00.000Z"));
    const second = await run(new Date("2026-08-31T10:00:01.000Z"));
    assert.equal(first.csv, second.csv);
    assert.notEqual(first.token, second.token);
  });
});

describe("hrisExportErrorMessage", () => {
  test("names the permission for an authority failure", () => {
    assert.match(hrisExportErrorMessage(new HrisExportQueryError("insufficient_authority: nope")), /permission to export HR data/);
  });

  test("passes the server's own range explanation through, minus the error code", () => {
    assert.equal(hrisExportErrorMessage(new HrisExportQueryError("invalid_date_range: export date range must be at most 366 days")), "export date range must be at most 366 days");
  });

  test("an unrecognised failure is generic rather than leaking internals", () => {
    assert.equal(hrisExportErrorMessage(new Error("relation app.timesheet_entries does not exist")), "Something went wrong preparing this export. Please try again.");
  });
});
