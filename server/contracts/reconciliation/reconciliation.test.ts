import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { FinanceReconciliationScopeSchema, ExecuteFinanceReconciliationRunInputSchema, parseFinanceReconciliationRun, parseFinanceReconciliationException } from "./reconciliation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "323e4567-e89b-12d3-a456-426614174001";
const EXCEPTION_ID = "323e4567-e89b-12d3-a456-426614174002";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("FinanceReconciliationScopeSchema", () => {
  test("accepts ar/ap", () => {
    for (const scope of ["ar", "ap"]) {
      assert.doesNotThrow(() => FinanceReconciliationScopeSchema.parse(scope));
    }
  });

  test("rejects an unrecognized scope", () => {
    assert.throws(() => FinanceReconciliationScopeSchema.parse("gl"));
  });
});

describe("ExecuteFinanceReconciliationRunInputSchema", () => {
  test("defaults toleranceAmount to zero", () => {
    const parsed = ExecuteFinanceReconciliationRunInputSchema.parse({
      tenantId: TENANT_ID, scope: "ar", asOfDate: "2026-06-30", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(parsed.toleranceAmount, 0);
  });

  test("rejects a negative tolerance", () => {
    assert.throws(() => ExecuteFinanceReconciliationRunInputSchema.parse({
      tenantId: TENANT_ID, scope: "ar", asOfDate: "2026-06-30", toleranceAmount: -5, actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });
});

describe("parseFinanceReconciliationRun", () => {
  test("maps a raw snake_case row to camelCase, coercing numeric strings", () => {
    const parsed = parseFinanceReconciliationRun({
      id: RUN_ID, tenant_id: TENANT_ID, company_id: null, scope: "ar", as_of_date: "2026-06-30",
      tolerance_amount: "0.00", control_total: "1000.00", source_total: "1000.00", variance_amount: "0.00",
      is_within_tolerance: true, status: "completed", certify_reason: null, certified_by: null, certified_at: null,
      prepared_by: "fm", record_version: 1, created_at: "2026-06-30T00:00:00.000Z", updated_at: "2026-06-30T00:00:00.000Z",
    });
    assert.equal(parsed.controlTotal, 1000);
    assert.equal(parsed.isWithinTolerance, true);
  });
});

describe("parseFinanceReconciliationException", () => {
  test("maps a raw snake_case row to camelCase", () => {
    const parsed = parseFinanceReconciliationException({
      id: EXCEPTION_ID, run_id: RUN_ID, tenant_id: TENANT_ID, item_type: "control_account_variance",
      description: "AR control account does not match", expected_amount: "1000.00", actual_amount: "900.00", variance_amount: "-100.00",
      status: "open", owner: null, resolution_reason: null, resolved_by: null, resolved_at: null,
      record_version: 1, created_at: "2026-06-30T00:00:00.000Z", updated_at: "2026-06-30T00:00:00.000Z",
    });
    assert.equal(parsed.status, "open");
    assert.equal(parsed.varianceAmount, -100);
  });
});
