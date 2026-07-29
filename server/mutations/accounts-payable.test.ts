import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  postFinanceApOpenItem,
  placeFinanceApHold,
  releaseFinanceApHold,
  applyFinanceApSettlement,
  reverseFinanceApSettlement,
  AccountsPayableMutationError,
  type AccountsPayableMutationRpcClient,
} from "./accounts-payable.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const ITEM_ROW = {
  id: ITEM_ID, tenant_id: TENANT_ID, company_id: null, vendor_master_id: VENDOR_ID,
  source_document_type: "vendor_bill", source_document_id: SOURCE_ID, currency: "USD",
  original_amount: "1000.00", settled_amount: "0.00", open_amount: "1000.00",
  status: "open", is_held: false, hold_reason: null, held_by: null, held_at: null, released_by: null, released_at: null,
  bill_date: "2026-03-10", due_date: "2026-04-09", posting_period_id: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): AccountsPayableMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AccountsPayableMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("postFinanceApOpenItem", () => {
  test("calls post_finance_ap_open_item with the exact snake_case params", async () => {
    const client = fakeClient({ data: ITEM_ROW, error: null });
    await postFinanceApOpenItem(client, {
      tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, sourceDocumentType: "vendor_bill", sourceDocumentId: SOURCE_ID,
      currency: "USD", originalAmount: 1000, billDate: "2026-03-10", dueDate: "2026-04-09", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "post_finance_ap_open_item");
    assert.equal(client.calls[0]?.args.p_original_amount, 1000);
  });

  test("wraps a finance_ap_period_not_open error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_ap_period_not_open: fiscal period 2026-03 is not open" } });
    await assert.rejects(
      () =>
        postFinanceApOpenItem(client, {
          tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, sourceDocumentType: "vendor_bill", sourceDocumentId: SOURCE_ID,
          currency: "USD", originalAmount: 1000, billDate: "2026-03-10", dueDate: "2026-04-09", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
        }),
      (error: unknown) => error instanceof AccountsPayableMutationError && error.code === "finance_ap_period_not_open",
    );
  });
});

describe("placeFinanceApHold / releaseFinanceApHold", () => {
  test("placeFinanceApHold calls place_finance_ap_hold", async () => {
    const client = fakeClient({ data: { ...ITEM_ROW, is_held: true }, error: null });
    const item = await placeFinanceApHold(client, { openItemId: ITEM_ID, expectedVersion: 1, reason: "disputed", actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(item.isHeld, true);
  });

  test("releaseFinanceApHold wraps a finance_ap_not_held error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_ap_not_held: open item is not currently held" } });
    await assert.rejects(
      () => releaseFinanceApHold(client, { openItemId: ITEM_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof AccountsPayableMutationError && error.code === "finance_ap_not_held",
    );
  });
});

describe("applyFinanceApSettlement / reverseFinanceApSettlement", () => {
  test("applyFinanceApSettlement wraps a finance_ap_over_settlement error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_ap_over_settlement: settlement exceeds open amount" } });
    await assert.rejects(
      () => applyFinanceApSettlement(client, { openItemId: ITEM_ID, amount: 2000, sourceType: "payment", sourceId: SOURCE_ID, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof AccountsPayableMutationError && error.code === "finance_ap_over_settlement",
    );
  });

  test("reverseFinanceApSettlement calls reverse_finance_ap_settlement with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...ITEM_ROW, settled_amount: "300.00", status: "partial" }, error: null });
    const item = await reverseFinanceApSettlement(client, { openItemId: ITEM_ID, amount: 200, reason: "payment reversed", sourceType: "payment", sourceId: SOURCE_ID, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(item.status, "partial");
    assert.equal(client.calls[0]?.args.p_reason, "payment reversed");
  });
});
