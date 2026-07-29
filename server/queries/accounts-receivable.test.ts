import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceArOpenItems, getFinanceArOpenItemActivity, getFinanceArExposureSummary, AccountsReceivableQueryError, type AccountsReceivableQueryRpcClient } from "./accounts-receivable.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): AccountsReceivableQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AccountsReceivableQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

const ITEM_ROW = {
  id: ITEM_ID, tenant_id: TENANT_ID, company_id: null, customer_account_id: CUSTOMER_ID,
  source_document_type: "invoice", source_document_id: ITEM_ID, currency: "USD",
  original_amount: "1000.00", allocated_amount: "0.00", open_amount: "1000.00",
  status: "open", is_held: false, hold_reason: null, held_by: null, held_at: null, released_by: null, released_at: null,
  invoice_date: "2026-03-10", due_date: "2026-04-09", posting_period_id: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

describe("listFinanceArOpenItems", () => {
  test("maps every returned row", async () => {
    const client = fakeRpcClient({ data: [ITEM_ROW], error: null });
    const items = await listFinanceArOpenItems(client, { tenantId: TENANT_ID, companyId: null, customerAccountId: null, status: null, overdueOnly: false, actorAuthUserId: ACTOR_ID });
    assert.equal(items.length, 1);
    assert.equal(items[0]?.status, "open");
  });

  test("wraps a database error into a typed AccountsReceivableQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => listFinanceArOpenItems(client, { tenantId: TENANT_ID, companyId: null, customerAccountId: null, status: null, overdueOnly: false, actorAuthUserId: ACTOR_ID }),
      AccountsReceivableQueryError,
    );
  });
});

describe("getFinanceArOpenItemActivity", () => {
  test("maps every returned event row", async () => {
    const client = fakeRpcClient({
      data: [{ id: ITEM_ID, tenant_id: TENANT_ID, open_item_id: ITEM_ID, event_type: "created", amount_delta: "1000.00", reason: null, source_type: "invoice", source_id: ITEM_ID, actor_label: "fm", created_at: "2026-03-10T00:00:00.000Z" }],
      error: null,
    });
    const events = await getFinanceArOpenItemActivity(client, { openItemId: ITEM_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(events.length, 1);
    assert.equal(events[0]?.eventType, "created");
  });
});

describe("getFinanceArExposureSummary", () => {
  test("parses an exposure summary result", async () => {
    const client = fakeRpcClient({ data: { totalOpen: 1000, openCount: 1, overdueOpen: 0, overdueCount: 0 }, error: null });
    const summary = await getFinanceArExposureSummary(client, { tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(summary.totalOpen, 1000);
  });
});
