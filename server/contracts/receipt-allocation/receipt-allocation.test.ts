import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceReceiptStatusSchema,
  CaptureFinanceReceiptInputSchema,
  AllocateFinanceReceiptInputSchema,
  RequestFinanceReceiptDeallocationInputSchema,
  parseFinanceReceipt,
  parseFinanceReceiptAllocation,
} from "./receipt-allocation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ID = "323e4567-e89b-12d3-a456-426614174000";
const RECEIPT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const BATCH_ID = "723e4567-e89b-12d3-a456-426614174000";
const ALLOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("FinanceReceiptStatusSchema", () => {
  test("accepts the two canonical states", () => {
    assert.doesNotThrow(() => FinanceReceiptStatusSchema.parse("captured"));
    assert.doesNotThrow(() => FinanceReceiptStatusSchema.parse("void"));
    assert.throws(() => FinanceReceiptStatusSchema.parse("pending"));
  });
});

describe("CaptureFinanceReceiptInputSchema", () => {
  test("rejects a non-positive amount", () => {
    assert.throws(() =>
      CaptureFinanceReceiptInputSchema.parse({
        tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, receiptDate: "2026-03-10", currency: "IDR", amount: 0,
        idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
    );
  });
});

describe("AllocateFinanceReceiptInputSchema", () => {
  test("requires at least one allocation line, each with a positive amount", () => {
    assert.throws(() => AllocateFinanceReceiptInputSchema.parse({ receiptId: RECEIPT_ID, idempotencyKey: "k1", allocations: [], actorAuthUserId: ACTOR_ID, actorLabel: "fm" }));
    assert.throws(() =>
      AllocateFinanceReceiptInputSchema.parse({ receiptId: RECEIPT_ID, idempotencyKey: "k1", allocations: [{ arOpenItemId: ITEM_ID, amount: -1 }], actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
    );
    assert.doesNotThrow(() =>
      AllocateFinanceReceiptInputSchema.parse({ receiptId: RECEIPT_ID, idempotencyKey: "k1", allocations: [{ arOpenItemId: ITEM_ID, amount: 100 }], actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
    );
  });
});

describe("RequestFinanceReceiptDeallocationInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() => RequestFinanceReceiptDeallocationInputSchema.parse({ allocationId: ALLOCATION_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }));
  });
});

describe("parseFinanceReceipt", () => {
  test("maps a raw snake_case row, coercing string amounts", () => {
    const parsed = parseFinanceReceipt({
      id: RECEIPT_ID, tenant_id: TENANT_ID, company_id: null, customer_account_id: CUSTOMER_ID,
      receipt_reference: "BANKREF-001", receipt_date: "2026-03-10", payer_name: "Jane Payer", bank_account_label: "BCA ****1234",
      currency: "IDR", amount: "1300000.00", allocated_amount: "1000000.00", unapplied_amount: "300000.00",
      status: "captured", idempotency_key: "capture-1", posting_period_id: null,
      record_version: 2, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 1300000);
    assert.equal(parsed.unappliedAmount, 300000);
  });
});

describe("parseFinanceReceiptAllocation", () => {
  test("maps a raw snake_case allocation row", () => {
    const parsed = parseFinanceReceiptAllocation({
      id: ALLOCATION_ID, tenant_id: TENANT_ID, receipt_id: RECEIPT_ID, batch_id: BATCH_ID, ar_open_item_id: ITEM_ID,
      amount: "1000000.00", status: "applied", reason: null, reversed_by: null, reversed_at: null,
      created_by: "fm", created_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 1000000);
    assert.equal(parsed.status, "applied");
  });
});
