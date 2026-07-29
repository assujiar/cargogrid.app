import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { FinanceAgingEntityTypeSchema, FinanceAgingBucketSchema, parseFinanceAgingReportRow, parseFinanceAgingSummaryRow, parseFinanceAgingBucketConfig } from "./aging.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONFIG_ID = "323e4567-e89b-12d3-a456-426614174001";
const ITEM_ID = "323e4567-e89b-12d3-a456-426614174000";
const PARTY_ID = "423e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "523e4567-e89b-12d3-a456-426614174001";

describe("FinanceAgingEntityTypeSchema", () => {
  test("accepts ar/ap", () => {
    for (const entityType of ["ar", "ap"]) {
      assert.doesNotThrow(() => FinanceAgingEntityTypeSchema.parse(entityType));
    }
  });

  test("rejects an unrecognized entity type", () => {
    assert.throws(() => FinanceAgingEntityTypeSchema.parse("gl"));
  });
});

describe("FinanceAgingBucketSchema", () => {
  test("accepts a bucket with a null (open-ended) maxDays", () => {
    const parsed = FinanceAgingBucketSchema.parse({ label: "90+", minDays: 91, maxDays: null });
    assert.equal(parsed.maxDays, null);
  });

  test("requires a non-empty label", () => {
    assert.throws(() => FinanceAgingBucketSchema.parse({ label: "", minDays: 0, maxDays: 30 }));
  });
});

describe("parseFinanceAgingReportRow", () => {
  test("maps a raw snake_case row to camelCase, coercing numeric strings", () => {
    const parsed = parseFinanceAgingReportRow({
      open_item_id: ITEM_ID, party_id: PARTY_ID, currency: "USD", original_amount: "1000.00", open_amount: "400.00",
      document_date: "2026-05-01", due_date: "2026-05-31", days_overdue: 45, bucket_label: "31-60", is_held: false,
      source_document_type: "invoice", source_document_id: SOURCE_ID,
    });
    assert.equal(parsed.openAmount, 400);
    assert.equal(parsed.bucketLabel, "31-60");
  });
});

describe("parseFinanceAgingSummaryRow", () => {
  test("maps a raw snake_case row to camelCase, coercing counts", () => {
    const parsed = parseFinanceAgingSummaryRow({ bucket_label: "31-60", currency: "USD", open_amount: "400.00", item_count: "2" });
    assert.equal(parsed.itemCount, 2);
    assert.equal(parsed.openAmount, 400);
  });
});

describe("parseFinanceAgingBucketConfig", () => {
  test("maps a raw snake_case row to camelCase", () => {
    const parsed = parseFinanceAgingBucketConfig({
      id: CONFIG_ID, tenant_id: TENANT_ID, entity_type: "ar", version: 1,
      buckets: [{ label: "Current", minDays: -999999, maxDays: 0 }, { label: "1-30", minDays: 1, maxDays: null }],
      is_active: true, created_by: "fm", created_at: "2026-07-01T00:00:00.000Z",
    });
    assert.equal(parsed.entityType, "ar");
    assert.equal(parsed.buckets.length, 2);
  });
});
