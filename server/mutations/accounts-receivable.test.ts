import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  postFinanceArOpenItem,
  placeFinanceArHold,
  releaseFinanceArHold,
  applyFinanceArAllocation,
  reverseFinanceArAllocation,
  AccountsReceivableMutationError,
  type AccountsReceivableMutationRpcClient,
} from "./accounts-receivable.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ID = "323e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const ITEM_ROW = {
  id: ITEM_ID, tenant_id: TENANT_ID, company_id: null, customer_account_id: CUSTOMER_ID,
  source_document_type: "invoice", source_document_id: SOURCE_ID, currency: "USD",
  original_amount: "1000.00", allocated_amount: "0.00", open_amount: "1000.00",
  status: "open", is_held: false, hold_reason: null, held_by: null, held_at: null, released_by: null, released_at: null,
  invoice_date: "2026-03-10", due_date: "2026-04-09", posting_period_id: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): AccountsReceivableMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AccountsReceivableMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("postFinanceArOpenItem", () => {
  test("calls post_finance_ar_open_item with the exact snake_case params", async () => {
    const client = fakeClient({ data: ITEM_ROW, error: null });
    await postFinanceArOpenItem(client, {
      tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, sourceDocumentType: "invoice", sourceDocumentId: SOURCE_ID,
      currency: "USD", originalAmount: 1000, invoiceDate: "2026-03-10", dueDate: "2026-04-09", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "post_finance_ar_open_item");
    assert.equal(client.calls[0]?.args.p_original_amount, 1000);
  });

  test("wraps a finance_ar_period_not_open error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_ar_period_not_open: fiscal period 2026-03 is not open" } });
    await assert.rejects(
      () =>
        postFinanceArOpenItem(client, {
          tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, sourceDocumentType: "invoice", sourceDocumentId: SOURCE_ID,
          currency: "USD", originalAmount: 1000, invoiceDate: "2026-03-10", dueDate: "2026-04-09", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
        }),
      (error: unknown) => error instanceof AccountsReceivableMutationError && error.code === "finance_ar_period_not_open",
    );
  });
});

describe("placeFinanceArHold / releaseFinanceArHold", () => {
  test("placeFinanceArHold calls place_finance_ar_hold", async () => {
    const client = fakeClient({ data: { ...ITEM_ROW, is_held: true }, error: null });
    const item = await placeFinanceArHold(client, { openItemId: ITEM_ID, expectedVersion: 1, reason: "disputed", actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(item.isHeld, true);
  });

  test("releaseFinanceArHold wraps a finance_ar_not_held error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_ar_not_held: open item is not currently held" } });
    await assert.rejects(
      () => releaseFinanceArHold(client, { openItemId: ITEM_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof AccountsReceivableMutationError && error.code === "finance_ar_not_held",
    );
  });
});

describe("applyFinanceArAllocation / reverseFinanceArAllocation", () => {
  test("applyFinanceArAllocation wraps a finance_ar_over_allocation error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_ar_over_allocation: allocation exceeds open amount" } });
    await assert.rejects(
      () => applyFinanceArAllocation(client, { openItemId: ITEM_ID, amount: 2000, sourceType: "receipt", sourceId: SOURCE_ID, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof AccountsReceivableMutationError && error.code === "finance_ar_over_allocation",
    );
  });

  test("reverseFinanceArAllocation calls reverse_finance_ar_allocation with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...ITEM_ROW, allocated_amount: "300.00", status: "partial" }, error: null });
    const item = await reverseFinanceArAllocation(client, { openItemId: ITEM_ID, amount: 200, reason: "receipt bounced", sourceType: "receipt", sourceId: SOURCE_ID, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(item.status, "partial");
    assert.equal(client.calls[0]?.args.p_reason, "receipt bounced");
  });
});
