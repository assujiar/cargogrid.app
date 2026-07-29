import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceReconciliationRuns, listFinanceReconciliationExceptions, ReconciliationQueryError, type ReconciliationQueryRpcClient } from "./reconciliation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "323e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const RUN_ROW = {
  id: RUN_ID, tenant_id: TENANT_ID, company_id: null, scope: "ar", as_of_date: "2026-06-30",
  tolerance_amount: "0.00", control_total: "1000.00", source_total: "1000.00", variance_amount: "0.00",
  is_within_tolerance: true, status: "completed", certify_reason: null, certified_by: null, certified_at: null,
  prepared_by: "fm", record_version: 1, created_at: "2026-06-30T00:00:00.000Z", updated_at: "2026-06-30T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): ReconciliationQueryRpcClient {
  return { async rpc() { return response; } } as unknown as ReconciliationQueryRpcClient;
}

describe("listFinanceReconciliationRuns", () => {
  test("maps rows to camelCase", async () => {
    const client = fakeClient({ data: [RUN_ROW], error: null });
    const rows = await listFinanceReconciliationRuns(client, { tenantId: TENANT_ID, companyId: null, scope: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.scope, "ar");
  });

  test("throws on rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: lacks FIN:View" } });
    await assert.rejects(() => listFinanceReconciliationRuns(client, { tenantId: TENANT_ID, companyId: null, scope: null, actorAuthUserId: ACTOR_ID }), ReconciliationQueryError);
  });
});

describe("listFinanceReconciliationExceptions", () => {
  test("maps exception rows to camelCase", async () => {
    const client = fakeClient({
      data: [{
        id: "323e4567-e89b-12d3-a456-426614174002", run_id: RUN_ID, tenant_id: TENANT_ID, item_type: "control_account_variance",
        description: "variance", expected_amount: "1000.00", actual_amount: "900.00", variance_amount: "-100.00", status: "open",
        owner: null, resolution_reason: null, resolved_by: null, resolved_at: null,
        record_version: 1, created_at: "2026-06-30T00:00:00.000Z", updated_at: "2026-06-30T00:00:00.000Z",
      }],
      error: null,
    });
    const rows = await listFinanceReconciliationExceptions(client, { runId: RUN_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.status, "open");
  });
});
