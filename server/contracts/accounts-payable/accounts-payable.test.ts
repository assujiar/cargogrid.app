import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceApOpenItemStatusSchema,
  FinanceApSourceDocumentTypeSchema,
  PostFinanceApOpenItemInputSchema,
  PlaceFinanceApHoldInputSchema,
  ApplyFinanceApSettlementInputSchema,
  ReverseFinanceApSettlementInputSchema,
  parseFinanceApOpenItem,
  parseFinanceApOpenItemEvent,
  parseFinanceApExposureSummary,
} from "./accounts-payable.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("FinanceApOpenItemStatusSchema / FinanceApSourceDocumentTypeSchema", () => {
  test("accepts the three canonical balance-derived statuses", () => {
    for (const status of ["open", "partial", "settled"]) {
      assert.doesNotThrow(() => FinanceApOpenItemStatusSchema.parse(status));
    }
  });

  test("accepts only vendor_bill/opening_balance as source document types", () => {
    assert.doesNotThrow(() => FinanceApSourceDocumentTypeSchema.parse("vendor_bill"));
    assert.doesNotThrow(() => FinanceApSourceDocumentTypeSchema.parse("opening_balance"));
    assert.throws(() => FinanceApSourceDocumentTypeSchema.parse("purchase_order"));
  });
});

describe("PostFinanceApOpenItemInputSchema", () => {
  test("rejects a non-positive original amount", () => {
    assert.throws(() =>
      PostFinanceApOpenItemInputSchema.parse({
        tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, sourceDocumentType: "vendor_bill", sourceDocumentId: SOURCE_ID,
        currency: "USD", originalAmount: 0, billDate: "2026-03-10", dueDate: "2026-04-09", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
    );
  });
});

describe("PlaceFinanceApHoldInputSchema / ApplyFinanceApSettlementInputSchema / ReverseFinanceApSettlementInputSchema", () => {
  test("PlaceFinanceApHoldInputSchema requires a non-empty reason", () => {
    assert.throws(() => PlaceFinanceApHoldInputSchema.parse({ openItemId: ITEM_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "fe" }));
    assert.doesNotThrow(() => PlaceFinanceApHoldInputSchema.parse({ openItemId: ITEM_ID, expectedVersion: 1, reason: "disputed", actorAuthUserId: ACTOR_ID, actorLabel: "fe" }));
  });

  test("ApplyFinanceApSettlementInputSchema rejects a non-positive amount", () => {
    assert.throws(() =>
      ApplyFinanceApSettlementInputSchema.parse({ openItemId: ITEM_ID, amount: -1, sourceType: "payment", sourceId: SOURCE_ID, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
    );
  });

  test("ReverseFinanceApSettlementInputSchema requires a non-empty reason", () => {
    assert.throws(() =>
      ReverseFinanceApSettlementInputSchema.parse({ openItemId: ITEM_ID, amount: 100, reason: "", sourceType: "payment", sourceId: SOURCE_ID, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
    );
  });
});

describe("parseFinanceApOpenItem", () => {
  test("maps a raw snake_case row, coercing string amounts", () => {
    const parsed = parseFinanceApOpenItem({
      id: ITEM_ID, tenant_id: TENANT_ID, company_id: null, vendor_master_id: VENDOR_ID,
      source_document_type: "vendor_bill", source_document_id: SOURCE_ID, currency: "USD",
      original_amount: "1000.00", settled_amount: "400.00", open_amount: "600.00",
      status: "partial", is_held: false, hold_reason: null, held_by: null, held_at: null, released_by: null, released_at: null,
      bill_date: "2026-03-10", due_date: "2026-04-09", posting_period_id: null,
      record_version: 2, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.originalAmount, 1000);
    assert.equal(parsed.openAmount, 600);
    assert.equal(parsed.status, "partial");
  });
});

describe("parseFinanceApOpenItemEvent", () => {
  test("maps a raw snake_case event row", () => {
    const parsed = parseFinanceApOpenItemEvent({
      id: ITEM_ID, tenant_id: TENANT_ID, open_item_id: ITEM_ID, event_type: "settled", amount_delta: "400.00",
      reason: null, source_type: "payment", source_id: SOURCE_ID, actor_label: "fm", created_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.eventType, "settled");
    assert.equal(parsed.amountDelta, 400);
  });
});

describe("parseFinanceApExposureSummary", () => {
  test("maps one raw per-currency row, coercing string numbers (CG-AUDIT-2026-09-02 B4)", () => {
    const parsed = parseFinanceApExposureSummary({
      currency: "USD",
      total_open: "600.00",
      open_count: 3,
      overdue_open: "0",
      overdue_count: 0,
      base_currency: "IDR",
      base_total_open: "9450000.00",
      base_overdue_open: "0",
      fx_status: "converted",
    });
    assert.equal(parsed.currency, "USD");
    assert.equal(parsed.totalOpen, 600);
    assert.equal(parsed.openCount, 3);
    assert.equal(parsed.baseCurrency, "IDR");
    assert.equal(parsed.baseTotalOpen, 9450000);
    assert.equal(parsed.fxStatus, "converted");
  });

  test("maps a rate_unavailable row with null base figures, never a fabricated conversion", () => {
    const parsed = parseFinanceApExposureSummary({
      currency: "EUR",
      total_open: "100.00",
      open_count: 1,
      overdue_open: "0",
      overdue_count: 0,
      base_currency: "IDR",
      base_total_open: null,
      base_overdue_open: null,
      fx_status: "rate_unavailable",
    });
    assert.equal(parsed.baseTotalOpen, null);
    assert.equal(parsed.baseOverdueOpen, null);
    assert.equal(parsed.fxStatus, "rate_unavailable");
  });
});
