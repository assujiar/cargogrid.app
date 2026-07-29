import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { FinancePeriodLockScopeSchema, LockFinancePeriodInputSchema, ApproveFinancePeriodReopenInputSchema, parseFinancePeriodLock } from "./period-lock.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LOCK_ID = "323e4567-e89b-12d3-a456-426614174001";
const PERIOD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("FinancePeriodLockScopeSchema", () => {
  test("accepts all/gl/ar/ap/tax", () => {
    for (const scope of ["all", "gl", "ar", "ap", "tax"]) {
      assert.doesNotThrow(() => FinancePeriodLockScopeSchema.parse(scope));
    }
  });

  test("rejects an unrecognized scope", () => {
    assert.throws(() => FinancePeriodLockScopeSchema.parse("bank"));
  });
});

describe("LockFinancePeriodInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() => LockFinancePeriodInputSchema.parse({
      tenantId: TENANT_ID, periodId: PERIOD_ID, lockScope: "ar", reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });

  test("accepts a well-formed lock request", () => {
    const parsed = LockFinancePeriodInputSchema.parse({
      tenantId: TENANT_ID, periodId: PERIOD_ID, lockScope: "ar", reason: "AR close complete", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(parsed.lockScope, "ar");
    assert.equal(parsed.companyId, null);
  });
});

describe("ApproveFinancePeriodReopenInputSchema", () => {
  test("rejects a reopen window over 720 hours", () => {
    assert.throws(() => ApproveFinancePeriodReopenInputSchema.parse({
      lockId: LOCK_ID, expectedVersion: 2, windowHours: 1000, actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });

  test("accepts a bounded window", () => {
    const parsed = ApproveFinancePeriodReopenInputSchema.parse({
      lockId: LOCK_ID, expectedVersion: 2, windowHours: 48, actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(parsed.windowHours, 48);
  });
});

describe("parseFinancePeriodLock", () => {
  test("maps a raw snake_case row to camelCase", () => {
    const parsed = parseFinancePeriodLock({
      id: LOCK_ID, tenant_id: TENANT_ID, company_id: null, period_id: PERIOD_ID, lock_scope: "ar", status: "locked",
      lock_reason: "AR close complete", evidence_ref: null, locked_by: "fm", locked_at: "2026-05-01T00:00:00.000Z",
      reopen_reason: null, reopen_requested_by: null, reopen_requested_at: null, reopen_approved_by: null,
      reopen_window_expires_at: null, reopened_at: null, relocked_by: null, relocked_at: null,
      record_version: 1, created_by: "fm", created_at: "2026-05-01T00:00:00.000Z", updated_at: "2026-05-01T00:00:00.000Z",
    });
    assert.equal(parsed.lockScope, "ar");
    assert.equal(parsed.status, "locked");
  });
});
