import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinancePeriodLocks, getFinancePeriodLockEvents, PeriodLockQueryError, type PeriodLockQueryRpcClient } from "./period-lock.ts";

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

function fakeClient(response: { data: unknown; error: { message: string } | null }): PeriodLockQueryRpcClient {
  return { async rpc() { return response; } } as unknown as PeriodLockQueryRpcClient;
}

describe("listFinancePeriodLocks", () => {
  test("maps rows to camelCase", async () => {
    const client = fakeClient({ data: [LOCK_ROW], error: null });
    const rows = await listFinancePeriodLocks(client, { tenantId: TENANT_ID, companyId: null, periodId: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.lockScope, "ar");
  });

  test("throws on rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: lacks FIN:View" } });
    await assert.rejects(() => listFinancePeriodLocks(client, { tenantId: TENANT_ID, companyId: null, periodId: null, actorAuthUserId: ACTOR_ID }), PeriodLockQueryError);
  });
});

describe("getFinancePeriodLockEvents", () => {
  test("maps event rows to camelCase", async () => {
    const client = fakeClient({
      data: [{ id: "623e4567-e89b-12d3-a456-426614174002", lock_id: LOCK_ID, tenant_id: TENANT_ID, action: "locked", reason: "AR close complete", actor_label: "fm", created_at: "2026-05-01T00:00:00.000Z" }],
      error: null,
    });
    const rows = await getFinancePeriodLockEvents(client, { lockId: LOCK_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.action, "locked");
  });
});
