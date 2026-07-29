import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceArOpenItemStatusSchema,
  FinanceArSourceDocumentTypeSchema,
  PostFinanceArOpenItemInputSchema,
  PlaceFinanceArHoldInputSchema,
  ApplyFinanceArAllocationInputSchema,
  ReverseFinanceArAllocationInputSchema,
  parseFinanceArOpenItem,
  parseFinanceArOpenItemEvent,
  parseFinanceArExposureSummary,
} from "./accounts-receivable.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ID = "323e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("FinanceArOpenItemStatusSchema / FinanceArSourceDocumentTypeSchema", () => {
  test("accepts the three canonical balance-derived statuses", () => {
    for (const status of ["open", "partial", "paid"]) {
      assert.doesNotThrow(() => FinanceArOpenItemStatusSchema.parse(status));
    }
  });

  test("accepts only invoice/opening_balance as source document types", () => {
    assert.doesNotThrow(() => FinanceArSourceDocumentTypeSchema.parse("invoice"));
    assert.doesNotThrow(() => FinanceArSourceDocumentTypeSchema.parse("opening_balance"));
    assert.throws(() => FinanceArSourceDocumentTypeSchema.parse("credit_note"));
  });
});

describe("PostFinanceArOpenItemInputSchema", () => {
  test("rejects a non-positive original amount", () => {
    assert.throws(() =>
      PostFinanceArOpenItemInputSchema.parse({
        tenantId: TENANT_ID, customerAccountId: CUSTOMER_ID, sourceDocumentType: "invoice", sourceDocumentId: SOURCE_ID,
        currency: "USD", originalAmount: 0, invoiceDate: "2026-03-10", dueDate: "2026-04-09", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
    );
  });
});

describe("PlaceFinanceArHoldInputSchema / ApplyFinanceArAllocationInputSchema / ReverseFinanceArAllocationInputSchema", () => {
  test("PlaceFinanceArHoldInputSchema requires a non-empty reason", () => {
    assert.throws(() => PlaceFinanceArHoldInputSchema.parse({ openItemId: ITEM_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "fe" }));
    assert.doesNotThrow(() => PlaceFinanceArHoldInputSchema.parse({ openItemId: ITEM_ID, expectedVersion: 1, reason: "disputed", actorAuthUserId: ACTOR_ID, actorLabel: "fe" }));
  });

  test("ApplyFinanceArAllocationInputSchema rejects a non-positive amount", () => {
    assert.throws(() =>
      ApplyFinanceArAllocationInputSchema.parse({ openItemId: ITEM_ID, amount: -1, sourceType: "receipt", sourceId: SOURCE_ID, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
    );
  });

  test("ReverseFinanceArAllocationInputSchema requires a non-empty reason", () => {
    assert.throws(() =>
      ReverseFinanceArAllocationInputSchema.parse({ openItemId: ITEM_ID, amount: 100, reason: "", sourceType: "receipt", sourceId: SOURCE_ID, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
    );
  });
});

describe("parseFinanceArOpenItem", () => {
  test("maps a raw snake_case row, coercing string amounts", () => {
    const parsed = parseFinanceArOpenItem({
      id: ITEM_ID, tenant_id: TENANT_ID, company_id: null, customer_account_id: CUSTOMER_ID,
      source_document_type: "invoice", source_document_id: SOURCE_ID, currency: "USD",
      original_amount: "1000.00", allocated_amount: "400.00", open_amount: "600.00",
      status: "partial", is_held: false, hold_reason: null, held_by: null, held_at: null, released_by: null, released_at: null,
      invoice_date: "2026-03-10", due_date: "2026-04-09", posting_period_id: null,
      record_version: 2, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.originalAmount, 1000);
    assert.equal(parsed.openAmount, 600);
    assert.equal(parsed.status, "partial");
  });
});

describe("parseFinanceArOpenItemEvent", () => {
  test("maps a raw snake_case event row", () => {
    const parsed = parseFinanceArOpenItemEvent({
      id: ITEM_ID, tenant_id: TENANT_ID, open_item_id: ITEM_ID, event_type: "allocated", amount_delta: "400.00",
      reason: null, source_type: "receipt", source_id: SOURCE_ID, actor_label: "fm", created_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.eventType, "allocated");
    assert.equal(parsed.amountDelta, 400);
  });
});

describe("parseFinanceArExposureSummary", () => {
  test("maps a raw jsonb summary result, coercing string numbers", () => {
    const parsed = parseFinanceArExposureSummary({ totalOpen: "600.00", openCount: 3, overdueOpen: "0", overdueCount: 0 });
    assert.equal(parsed.totalOpen, 600);
    assert.equal(parsed.openCount, 3);
  });
});
