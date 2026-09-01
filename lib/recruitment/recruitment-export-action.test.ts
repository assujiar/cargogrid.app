import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { buildRecruitmentExport, recruitmentExportErrorMessage } from "./recruitment-export-action.ts";
import { RecruitmentQueryError } from "../../server/queries/recruitment.ts";

const NOW = new Date("2026-08-31T10:00:00.000Z");

const HEADER = ["Title", "Status"] as const;
interface Row {
  readonly title: string;
  readonly status: string;
}
const toCells = (row: Row) => [row.title, row.status];

describe("buildRecruitmentExport", () => {
  test("produces a sanitized CSV, a dated filename, and a row count", async () => {
    const result = await buildRecruitmentExport<Row>({
      filenameStem: "job-vacancies",
      header: HEADER,
      fetchRows: async () => [{ title: "Backend Engineer", status: "open" }],
      toCells,
      now: NOW,
    });
    assert.equal(result.error, null);
    assert.equal(result.rowCount, 1);
    assert.equal(result.filename, "job-vacancies-2026-08-31.csv");
    assert.equal(result.csv, "Title,Status\r\nBackend Engineer,open\r\n");
  });

  test("neutralises a formula-injection cell rather than emitting it raw", async () => {
    const result = await buildRecruitmentExport<Row>({
      filenameStem: "x",
      header: HEADER,
      fetchRows: async () => [{ title: "=1+1", status: "open" }],
      toCells,
      now: NOW,
    });
    assert.ok(result.csv?.includes("'=1+1"), `expected the leading apostrophe guard, got ${result.csv}`);
  });

  test("an empty result set produces no file, but still a fresh token", async () => {
    const result = await buildRecruitmentExport<Row>({
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
    assert.ok(result.token);
  });

  test("a thrown insufficient_authority error is mapped to a permission message", async () => {
    const result = await buildRecruitmentExport<Row>({
      filenameStem: "x",
      header: HEADER,
      fetchRows: async () => {
        throw new RecruitmentQueryError("insufficient_authority: identity lacks HRS:Export");
      },
      toCells,
      now: NOW,
    });
    assert.match(result.error ?? "", /permission/);
    assert.equal(result.csv, null);
    assert.equal(result.token, null);
  });

  test("recruitmentExportErrorMessage falls back to a generic message for an unknown error", () => {
    assert.equal(recruitmentExportErrorMessage(new Error("boom")), "Something went wrong preparing this export. Please try again.");
  });
});
