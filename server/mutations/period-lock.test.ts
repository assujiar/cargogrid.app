import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  lockFinancePeriod,
  requestFinancePeriodReopen,
  approveFinancePeriodReopen,
  relockFinancePeriod,
  PeriodLockMutationError,
  type PeriodLockMutationRpcClient,
} from "./period-lock.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LOCK_ID = "323e4567-e89b-12d3-a456-426614174001";
const PERIOD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const LOCK_ROW = {
  id: LOCK_ID, tenant_id: TENANT_ID, company_id: null, period_id: PERIOD_ID, lock_scope: "ar", status: "locked",
  lock_reason: "AR close complete", evidence_ref: null, locked_by: "fm", locked_at: "2026-05-01T00:00:00.000Z",
  reopen_reason: null, reopen_requested_by: null, reopen_requested_at: null, reopen_approved_by: null,
  reopen_window_expires_at: null, reopened_at: null, relocked_by: null, relocked_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-05-01T00:00:00.000Z", updated_at: "2026-05-01T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): PeriodLockMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PeriodLockMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("lockFinancePeriod", () => {
  test("calls lock_finance_period with exact snake_case params", async () => {
    const client = fakeClient({ data: LOCK_ROW, error: null });
    await lockFinancePeriod(client, { tenantId: TENANT_ID, periodId: PERIOD_ID, lockScope: "ar", reason: "AR close complete", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(client.calls[0]?.fn, "lock_finance_period");
    assert.equal(client.calls[0]?.args.p_lock_scope, "ar");
  });

  test("wraps a finance_period_lock_invalid_scope error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_period_lock_invalid_scope: bank is not a supported lock scope" } });
    await assert.rejects(
      () => lockFinancePeriod(client, { tenantId: TENANT_ID, periodId: PERIOD_ID, lockScope: "ar", reason: "AR close complete", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof PeriodLockMutationError && error.code === "finance_period_lock_invalid_scope",
    );
  });
});

describe("requestFinancePeriodReopen / approveFinancePeriodReopen / relockFinancePeriod", () => {
  test("requestFinancePeriodReopen calls request_finance_period_reopen", async () => {
    const client = fakeClient({ data: { ...LOCK_ROW, status: "reopen_requested" }, error: null });
    const lock = await requestFinancePeriodReopen(client, { lockId: LOCK_ID, expectedVersion: 1, reason: "correction needed", actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(lock.status, "reopen_requested");
  });

  test("approveFinancePeriodReopen wraps a finance_period_lock_not_reopen_requested error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_period_lock_not_reopen_requested: lock is locked not reopen_requested" } });
    await assert.rejects(
      () => approveFinancePeriodReopen(client, { lockId: LOCK_ID, expectedVersion: 1, windowHours: 24, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof PeriodLockMutationError && error.code === "finance_period_lock_not_reopen_requested",
    );
  });

  test("relockFinancePeriod calls relock_finance_period and returns locked", async () => {
    const client = fakeClient({ data: { ...LOCK_ROW, status: "locked" }, error: null });
    const lock = await relockFinancePeriod(client, { lockId: LOCK_ID, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(lock.status, "locked");
  });
});
