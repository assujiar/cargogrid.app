import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinancePeriodStatusSchema,
  GenerateFinanceFiscalCalendarInputSchema,
  ReopenFinancePeriodInputSchema,
  parseFinanceFiscalPeriod,
  parseFinancePeriodCloseReadiness,
  parseFinancePeriodDateResolution,
} from "./fiscal-period.ts";

describe("FinancePeriodStatusSchema", () => {
  test("accepts the three canonical lifecycle states", () => {
    for (const status of ["open", "soft_closed", "closed"]) {
      assert.doesNotThrow(() => FinancePeriodStatusSchema.parse(status));
    }
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => FinancePeriodStatusSchema.parse("archived"));
  });
});

describe("GenerateFinanceFiscalCalendarInputSchema", () => {
  test("parses a well-formed 12-month calendar request", () => {
    const parsed = GenerateFinanceFiscalCalendarInputSchema.parse({
      tenantId: "123e4567-e89b-12d3-a456-426614174000",
      code: "FY2026",
      name: "Fiscal Year 2026",
      startDate: "2026-01-01",
      periodCount: 12,
      actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
      createdBy: "finance-manager",
    });
    assert.equal(parsed.periodCount, 12);
    assert.equal(parsed.companyId, null);
  });

  test("rejects a period count outside 1-24", () => {
    assert.throws(() =>
      GenerateFinanceFiscalCalendarInputSchema.parse({
        tenantId: "123e4567-e89b-12d3-a456-426614174000",
        code: "FY2026",
        name: "Fiscal Year 2026",
        startDate: "2026-01-01",
        periodCount: 30,
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
        createdBy: "finance-manager",
      }),
    );
  });
});

describe("ReopenFinancePeriodInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      ReopenFinancePeriodInputSchema.parse({
        periodId: "323e4567-e89b-12d3-a456-426614174000",
        expectedVersion: 1,
        reason: "",
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
        actorLabel: "finance-manager",
      }),
    );
  });
});

describe("parseFinanceFiscalPeriod", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const parsed = parseFinanceFiscalPeriod({
      id: "323e4567-e89b-12d3-a456-426614174000",
      calendar_id: "423e4567-e89b-12d3-a456-426614174000",
      tenant_id: "123e4567-e89b-12d3-a456-426614174000",
      company_id: null,
      period_code: "2026-01",
      name: "2026-01",
      start_date: "2026-01-01",
      end_date: "2026-01-31",
      sequence_number: 1,
      status: "open",
      closed_at: null,
      closed_by: null,
      record_version: 1,
      created_by: "finance-manager",
      created_at: "2026-07-28T00:00:00.000Z",
      updated_at: "2026-07-28T00:00:00.000Z",
    });
    assert.equal(parsed.status, "open");
    assert.equal(parsed.periodCode, "2026-01");
  });
});

describe("parseFinancePeriodCloseReadiness", () => {
  test("maps a raw close-readiness jsonb result", () => {
    const parsed = parseFinancePeriodCloseReadiness({
      periodId: "323e4567-e89b-12d3-a456-426614174000",
      status: "soft_closed",
      ready: false,
      unsatisfiedRequiredItems: ["ar_aging_reconciled"],
    });
    assert.equal(parsed.ready, false);
    assert.deepEqual(parsed.unsatisfiedRequiredItems, ["ar_aging_reconciled"]);
  });
});

describe("parseFinancePeriodDateResolution", () => {
  test("maps a raw date-resolution row", () => {
    const parsed = parseFinancePeriodDateResolution({
      period_id: "323e4567-e89b-12d3-a456-426614174000",
      period_code: "2026-01",
      status: "open",
      posting_eligible: true,
    });
    assert.equal(parsed.postingEligible, true);
  });
});
