import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  captureFinanceReceipt,
  allocateFinanceReceipt,
  requestFinanceReceiptDeallocation,
  ReceiptAllocationMutationError,
  type ReceiptAllocationMutationRpcClient,
} from "./receipt-allocation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ID = "323e4567-e89b-12d3-a456-426614174000";
const RECEIPT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ALLOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";

const RECEIPT_ROW = {
  id: RECEIPT_ID, tenant_id: TENANT_ID, company_id: null, customer_account_id: CUSTOMER_ID,
  receipt_reference: "BANKREF-001", receipt_date: "2026-03-10", payer_name: "Jane Payer", bank_account_label: "BCA ****1234",
  currency: "IDR", amount: "1300000.00", allocated_amount: "0.00", unapplied_amount: "1300000.00",
  status: "captured", idempotency_key: "capture-1", posting_period_id: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): ReceiptAllocationMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ReceiptAllocationMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("captureFinanceReceipt", () => {
  test("calls capture_finance_receipt with the exact snake_case params", async () => {
    const client = fakeClient({ data: RECEIPT_ROW, error: null });
    await captureFinanceReceipt(client, {
      tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, receiptReference: "BANKREF-001", receiptDate: "2026-03-10",
      currency: "IDR", amount: 1300000, idempotencyKey: "capture-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "capture_finance_receipt");
    assert.equal(client.calls[0]?.args.p_amount, 1300000);
  });

  test("wraps a finance_receipt_duplicate_reference error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_receipt_duplicate_reference: bank reference already exists" } });
    await assert.rejects(
      () =>
        captureFinanceReceipt(client, {
          tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, receiptReference: "BANKREF-001", receiptDate: "2026-03-10",
          currency: "IDR", amount: 1300000, idempotencyKey: "capture-2", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
        }),
      (error: unknown) => error instanceof ReceiptAllocationMutationError && error.code === "finance_receipt_duplicate_reference",
    );
  });
});

describe("allocateFinanceReceipt", () => {
  test("maps allocation lines to the exact snake_case shape the RPC expects", async () => {
    const client = fakeClient({ data: { ...RECEIPT_ROW, allocated_amount: "1000000.00", unapplied_amount: "300000.00" }, error: null });
    await allocateFinanceReceipt(client, { receiptId: RECEIPT_ID, idempotencyKey: "alloc-1", allocations: [{ arOpenItemId: ITEM_ID, amount: 1000000 }], actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    const args = client.calls[0]?.args as { p_allocations: Array<{ arOpenItemId: string; amount: number }> };
    assert.equal(args.p_allocations[0]?.amount, 1000000);
  });

  test("wraps a finance_receipt_over_allocation error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_receipt_over_allocation: total allocation exceeds unapplied amount" } });
    await assert.rejects(
      () => allocateFinanceReceipt(client, { receiptId: RECEIPT_ID, idempotencyKey: "alloc-1", allocations: [{ arOpenItemId: ITEM_ID, amount: 2000000 }], actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof ReceiptAllocationMutationError && error.code === "finance_receipt_over_allocation",
    );
  });
});

describe("requestFinanceReceiptDeallocation", () => {
  test("calls request_finance_receipt_deallocation with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...RECEIPT_ROW, allocated_amount: "0.00", unapplied_amount: "1300000.00" }, error: null });
    const receipt = await requestFinanceReceiptDeallocation(client, { allocationId: ALLOCATION_ID, reason: "receipt bounced", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(receipt.unappliedAmount, 1300000);
    assert.equal(client.calls[0]?.args.p_reason, "receipt bounced");
  });

  test("wraps a finance_receipt_allocation_not_applied error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_receipt_allocation_not_applied: allocation is reversed not applied" } });
    await assert.rejects(
      () => requestFinanceReceiptDeallocation(client, { allocationId: ALLOCATION_ID, reason: "again", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof ReceiptAllocationMutationError && error.code === "finance_receipt_allocation_not_applied",
    );
  });
});
