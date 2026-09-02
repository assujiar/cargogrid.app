import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { buildOnboardingExport, onboardingExportErrorMessage } from "./onboarding-export-action.ts";
import { OnboardingQueryError } from "../../server/queries/onboarding.ts";

const NOW = new Date("2026-09-02T10:00:00.000Z");

const HEADER = ["Case type", "Status"] as const;
interface Row {
  readonly caseType: string;
  readonly status: string;
}
const toCells = (row: Row) => [row.caseType, row.status];

describe("buildOnboardingExport", () => {
  test("produces a sanitized CSV, a dated filename, and a row count", async () => {
    const result = await buildOnboardingExport<Row>({
      filenameStem: "onboarding-cases",
      header: HEADER,
      fetchRows: async () => [{ caseType: "onboarding", status: "active" }],
      toCells,
      now: NOW,
    });
    assert.equal(result.error, null);
    assert.equal(result.rowCount, 1);
    assert.equal(result.filename, "onboarding-cases-2026-09-02.csv");
    assert.equal(result.csv, "Case type,Status\r\nonboarding,active\r\n");
  });

  test("neutralises a formula-injection cell rather than emitting it raw", async () => {
    const result = await buildOnboardingExport<Row>({
      filenameStem: "x",
      header: HEADER,
      fetchRows: async () => [{ caseType: "=1+1", status: "active" }],
      toCells,
      now: NOW,
    });
    assert.ok(result.csv?.includes("'=1+1"), `expected the leading apostrophe guard, got ${result.csv}`);
  });

  test("an empty result set produces no file, but still a fresh token", async () => {
    const result = await buildOnboardingExport<Row>({
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
    const result = await buildOnboardingExport<Row>({
      filenameStem: "x",
      header: HEADER,
      fetchRows: async () => {
        throw new OnboardingQueryError("insufficient_authority: identity lacks HRS:Export");
      },
      toCells,
      now: NOW,
    });
    assert.match(result.error ?? "", /permission/);
    assert.equal(result.csv, null);
    assert.equal(result.token, null);
  });

  test("onboardingExportErrorMessage falls back to a generic message for an unknown error", () => {
    assert.equal(onboardingExportErrorMessage(new Error("boom")), "Something went wrong preparing this export. Please try again.");
  });
});
