import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceSettlementStatusSchema,
  PrepareFinanceSettlementInputSchema,
  parseFinanceSettlement,
  parseFinanceSettlementAllocation,
} from "./settlement.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const SETTLEMENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const AP_ITEM_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("FinanceSettlementStatusSchema", () => {
  test("accepts the seven canonical lifecycle states", () => {
    for (const status of ["draft", "submitted", "approved", "executed", "posted", "void", "reversed"]) {
      assert.doesNotThrow(() => FinanceSettlementStatusSchema.parse(status));
    }
  });

  test("rejects an unknown status", () => {
    assert.throws(() => FinanceSettlementStatusSchema.parse("cancelled"));
  });
});

describe("PrepareFinanceSettlementInputSchema", () => {
  test("defaults companyId/paymentReference/bankAccountLabel to null and feeAmount to 0", () => {
    const parsed = PrepareFinanceSettlementInputSchema.parse({
      tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, currency: "USD", settlementDate: "2026-03-15",
      allocations: [{ apOpenItemId: AP_ITEM_ID, amount: 400 }],
      idempotencyKey: "prep-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(parsed.companyId, null);
    assert.equal(parsed.paymentReference, null);
    assert.equal(parsed.bankAccountLabel, null);
    assert.equal(parsed.feeAmount, 0);
  });

  test("requires at least one allocation line", () => {
    assert.throws(() => PrepareFinanceSettlementInputSchema.parse({
      tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, currency: "USD", settlementDate: "2026-03-15",
      allocations: [], idempotencyKey: "prep-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });

  test("rejects a non-positive allocation amount", () => {
    assert.throws(() => PrepareFinanceSettlementInputSchema.parse({
      tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, currency: "USD", settlementDate: "2026-03-15",
      allocations: [{ apOpenItemId: AP_ITEM_ID, amount: 0 }], idempotencyKey: "prep-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });
});

describe("parseFinanceSettlement", () => {
  test("maps a raw snake_case row, coercing string amounts", () => {
    const parsed = parseFinanceSettlement({
      id: SETTLEMENT_ID, tenant_id: TENANT_ID, company_id: null, settlement_number: "SETL-2026-000001",
      vendor_master_id: VENDOR_ID, payment_reference: "PMT-1", bank_account_label: "Bank ***1234",
      currency: "USD", status: "posted", allocated_amount: "900.00", fee_amount: "5.00", total_amount: "905.00",
      settlement_date: "2026-03-20", idempotency_key: "prep-real-1", posting_period_id: null, execution_reference: "TXN-1",
      submitted_by: "fm", submitted_at: "2026-03-19T00:00:00.000Z", approved_by: "fm", approved_at: "2026-03-19T00:00:00.000Z",
      executed_by: "fm", executed_at: "2026-03-19T00:00:00.000Z", posted_by: "fm", posted_at: "2026-03-20T00:00:00.000Z",
      void_reason: null, voided_by: null, voided_at: null,
      record_version: 5, created_by: "fm", created_at: "2026-03-15T00:00:00.000Z", updated_at: "2026-03-20T00:00:00.000Z",
    });
    assert.equal(parsed.totalAmount, 905);
    assert.equal(parsed.status, "posted");
    assert.equal(parsed.settlementNumber, "SETL-2026-000001");
  });

  test("leaves settlementNumber null before posting", () => {
    const parsed = parseFinanceSettlement({
      id: SETTLEMENT_ID, tenant_id: TENANT_ID, company_id: null, settlement_number: null,
      vendor_master_id: VENDOR_ID, payment_reference: null, bank_account_label: null,
      currency: "USD", status: "draft", allocated_amount: "400.00", fee_amount: "0.00", total_amount: "400.00",
      settlement_date: "2026-03-15", idempotency_key: "prep-1", posting_period_id: null, execution_reference: null,
      submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
      executed_by: null, executed_at: null, posted_by: null, posted_at: null,
      void_reason: null, voided_by: null, voided_at: null,
      record_version: 1, created_by: "fm", created_at: "2026-03-15T00:00:00.000Z", updated_at: "2026-03-15T00:00:00.000Z",
    });
    assert.equal(parsed.settlementNumber, null);
    assert.equal(parsed.status, "draft");
  });
});

describe("parseFinanceSettlementAllocation", () => {
  test("maps a raw snake_case allocation row", () => {
    const parsed = parseFinanceSettlementAllocation({
      id: AP_ITEM_ID, tenant_id: TENANT_ID, settlement_id: SETTLEMENT_ID, ap_open_item_id: AP_ITEM_ID,
      amount: "400.00", status: "applied", reason: null, reversed_by: null, reversed_at: null,
      created_at: "2026-03-15T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 400);
    assert.equal(parsed.status, "applied");
  });
});
