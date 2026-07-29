import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceReceipts, getFinanceReceiptAllocations, searchFinanceArCandidatesForReceipt, ReceiptAllocationQueryError, type ReceiptAllocationQueryRpcClient } from "./receipt-allocation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ID = "323e4567-e89b-12d3-a456-426614174000";
const RECEIPT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const BATCH_ID = "723e4567-e89b-12d3-a456-426614174000";
const ALLOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): ReceiptAllocationQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ReceiptAllocationQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

const RECEIPT_ROW = {
  id: RECEIPT_ID, tenant_id: TENANT_ID, company_id: null, customer_account_id: CUSTOMER_ID,
  receipt_reference: "BANKREF-001", receipt_date: "2026-03-10", payer_name: "Jane Payer", bank_account_label: "BCA ****1234",
  currency: "IDR", amount: "1300000.00", allocated_amount: "0.00", unapplied_amount: "1300000.00",
  status: "captured", idempotency_key: "capture-1", posting_period_id: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

describe("listFinanceReceipts", () => {
  test("maps every returned row", async () => {
    const client = fakeRpcClient({ data: [RECEIPT_ROW], error: null });
    const receipts = await listFinanceReceipts(client, { tenantId: TENANT_ID, companyId: null, customerAccountId: null, status: null, actorAuthUserId: ACTOR_ID });
    assert.equal(receipts.length, 1);
    assert.equal(receipts[0]?.unappliedAmount, 1300000);
  });

  test("wraps a database error into a typed ReceiptAllocationQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => listFinanceReceipts(client, { tenantId: TENANT_ID, companyId: null, customerAccountId: null, status: null, actorAuthUserId: ACTOR_ID }),
      ReceiptAllocationQueryError,
    );
  });
});

describe("getFinanceReceiptAllocations", () => {
  test("maps every returned allocation row", async () => {
    const client = fakeRpcClient({
      data: [{ id: ALLOCATION_ID, tenant_id: TENANT_ID, receipt_id: RECEIPT_ID, batch_id: BATCH_ID, ar_open_item_id: ITEM_ID, amount: "1000000.00", status: "applied", reason: null, reversed_by: null, reversed_at: null, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z" }],
      error: null,
    });
    const allocations = await getFinanceReceiptAllocations(client, { receiptId: RECEIPT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(allocations.length, 1);
    assert.equal(allocations[0]?.amount, 1000000);
  });
});

describe("searchFinanceArCandidatesForReceipt", () => {
  test("maps every returned candidate open item", async () => {
    const client = fakeRpcClient({
      data: [
        {
          id: ITEM_ID, tenant_id: TENANT_ID, company_id: null, customer_account_id: CUSTOMER_ID, source_document_type: "invoice", source_document_id: ITEM_ID,
          currency: "IDR", original_amount: "1000000.00", allocated_amount: "0.00", open_amount: "1000000.00", status: "open", is_held: false,
          hold_reason: null, held_by: null, held_at: null, released_by: null, released_at: null, invoice_date: "2026-03-01", due_date: "2026-03-31",
          posting_period_id: null, record_version: 1, created_by: "fm", created_at: "2026-03-01T00:00:00.000Z", updated_at: "2026-03-01T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const candidates = await searchFinanceArCandidatesForReceipt(client, { receiptId: RECEIPT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(candidates.length, 1);
    assert.equal(candidates[0]?.openAmount, 1000000);
  });
});
