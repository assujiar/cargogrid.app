import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceSubledgerBatches, getFinanceSubledgerLines, getFinanceSubledgerReconciliationSummary, SubledgerQueryError, type SubledgerQueryRpcClient } from "./subledger.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const BATCH_ID = "323e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): SubledgerQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as SubledgerQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

const BATCH_ROW = {
  id: BATCH_ID, tenant_id: TENANT_ID, company_id: null, source_type: "invoice", source_id: SOURCE_ID,
  currency: "USD", total_amount: "1000.00", status: "posted", posting_period_id: null, gl_journal_id: null,
  posted_by: "fm", posted_at: "2026-03-10T00:00:00.000Z", created_at: "2026-03-10T00:00:00.000Z",
};

describe("listFinanceSubledgerBatches", () => {
  test("maps every returned row", async () => {
    const client = fakeRpcClient({ data: [BATCH_ROW], error: null });
    const batches = await listFinanceSubledgerBatches(client, { tenantId: TENANT_ID, companyId: null, sourceType: null, actorAuthUserId: ACTOR_ID });
    assert.equal(batches.length, 1);
    assert.equal(batches[0]?.sourceType, "invoice");
  });

  test("wraps a database error into a typed SubledgerQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => listFinanceSubledgerBatches(client, { tenantId: TENANT_ID, companyId: null, sourceType: null, actorAuthUserId: ACTOR_ID }),
      SubledgerQueryError,
    );
  });
});

describe("getFinanceSubledgerLines", () => {
  test("maps every returned line row", async () => {
    const client = fakeRpcClient({
      data: [{ id: BATCH_ID, batch_id: BATCH_ID, tenant_id: TENANT_ID, line_number: 1, account_id: ACCOUNT_ID, posting_map_key: "ar_control", direction: "debit", amount: "1000.00", open_item_type: "ar_open_item", open_item_id: null, created_at: "2026-03-10T00:00:00.000Z" }],
      error: null,
    });
    const lines = await getFinanceSubledgerLines(client, { batchId: BATCH_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(lines.length, 1);
    assert.equal(lines[0]?.amount, 1000);
  });
});

describe("getFinanceSubledgerReconciliationSummary", () => {
  test("maps the raw jsonb result", async () => {
    const client = fakeRpcClient({
      data: {
        arControlAccountCode: "AR-CTRL", arControlSubledgerBalance: "500.00", arOpenItemTotal: "500.00", arReconciled: true,
        apControlAccountCode: "AP-CTRL", apControlSubledgerBalance: "300.00", apOpenItemTotal: "300.00", apReconciled: true,
      },
      error: null,
    });
    const summary = await getFinanceSubledgerReconciliationSummary(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(summary.arReconciled, true);
    assert.equal(summary.arControlSubledgerBalance, 500);
  });

  test("wraps a database error into a typed SubledgerQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "finance_subledger_missing_posting_map: no published finance posting map exists for tenant" } });
    await assert.rejects(
      () => getFinanceSubledgerReconciliationSummary(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }),
      SubledgerQueryError,
    );
  });
});
