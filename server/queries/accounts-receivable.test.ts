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
  test("parses a real per-currency exposure summary result (CG-AUDIT-2026-09-02 B4, never a blended cross-currency sum)", async () => {
    const client = fakeRpcClient({
      data: [
        { currency: "USD", total_open: 1000, open_count: 1, overdue_open: 0, overdue_count: 0, base_currency: "IDR", base_total_open: 15700000, base_overdue_open: 0, fx_status: "converted" },
        { currency: "EUR", total_open: 200, open_count: 1, overdue_open: 0, overdue_count: 0, base_currency: "IDR", base_total_open: null, base_overdue_open: null, fx_status: "rate_unavailable" },
      ],
      error: null,
    });
    const summary = await getFinanceArExposureSummary(client, { tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(summary.length, 2);
    assert.equal(summary[0]?.currency, "USD");
    assert.equal(summary[0]?.totalOpen, 1000);
    assert.equal(summary[0]?.fxStatus, "converted");
    assert.equal(summary[1]?.currency, "EUR");
    assert.equal(summary[1]?.baseTotalOpen, null);
    assert.equal(summary[1]?.fxStatus, "rate_unavailable");
  });

  test("returns an empty array for a customer with zero open items, never a fabricated zero row", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const summary = await getFinanceArExposureSummary(client, { tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(summary, []);
  });
});
