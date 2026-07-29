import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceSubledgerSourceTypeSchema,
  FinanceSubledgerBatchStatusSchema,
  parseFinanceSubledgerBatch,
  parseFinanceSubledgerLine,
  parseFinanceSubledgerReconciliationSummary,
} from "./subledger.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const BATCH_ID = "323e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const AR_ITEM_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("FinanceSubledgerSourceTypeSchema / FinanceSubledgerBatchStatusSchema", () => {
  test("accepts the four canonical source types", () => {
    for (const sourceType of ["invoice", "receipt_allocation", "vendor_bill", "settlement"]) {
      assert.doesNotThrow(() => FinanceSubledgerSourceTypeSchema.parse(sourceType));
    }
  });

  test("rejects an unknown source type", () => {
    assert.throws(() => FinanceSubledgerSourceTypeSchema.parse("adjustment"));
  });

  test("accepts posted/reversed statuses", () => {
    assert.doesNotThrow(() => FinanceSubledgerBatchStatusSchema.parse("posted"));
    assert.doesNotThrow(() => FinanceSubledgerBatchStatusSchema.parse("reversed"));
  });
});

describe("parseFinanceSubledgerBatch", () => {
  test("maps a raw snake_case row, coercing string amounts", () => {
    const parsed = parseFinanceSubledgerBatch({
      id: BATCH_ID, tenant_id: TENANT_ID, company_id: null, source_type: "invoice", source_id: SOURCE_ID,
      currency: "USD", total_amount: "1000.00", status: "posted", posting_period_id: null, gl_journal_id: null,
      posted_by: "fm", posted_at: "2026-03-10T00:00:00.000Z", created_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.totalAmount, 1000);
    assert.equal(parsed.status, "posted");
    assert.equal(parsed.glJournalId, null);
  });
});

describe("parseFinanceSubledgerLine", () => {
  test("maps a raw snake_case line row with open-item lineage", () => {
    const parsed = parseFinanceSubledgerLine({
      id: BATCH_ID, batch_id: BATCH_ID, tenant_id: TENANT_ID, line_number: 1, account_id: ACCOUNT_ID,
      posting_map_key: "ar_control", direction: "debit", amount: "1000.00",
      open_item_type: "ar_open_item", open_item_id: AR_ITEM_ID, created_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 1000);
    assert.equal(parsed.direction, "debit");
    assert.equal(parsed.openItemType, "ar_open_item");
  });

  test("maps a line resolved via a direct accountId reference (null posting_map_key)", () => {
    const parsed = parseFinanceSubledgerLine({
      id: BATCH_ID, batch_id: BATCH_ID, tenant_id: TENANT_ID, line_number: 2, account_id: ACCOUNT_ID,
      posting_map_key: null, direction: "credit", amount: "110.00",
      open_item_type: null, open_item_id: null, created_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.postingMapKey, null);
    assert.equal(parsed.openItemType, null);
  });
});

describe("parseFinanceSubledgerReconciliationSummary", () => {
  test("maps the raw jsonb reconciliation summary, coercing string amounts", () => {
    const parsed = parseFinanceSubledgerReconciliationSummary({
      arControlAccountCode: "AR-CTRL", arControlSubledgerBalance: "500.00", arOpenItemTotal: "500.00", arReconciled: true,
      apControlAccountCode: "AP-CTRL", apControlSubledgerBalance: "300.00", apOpenItemTotal: "300.00", apReconciled: true,
    });
    assert.equal(parsed.arReconciled, true);
    assert.equal(parsed.arControlSubledgerBalance, 500);
    assert.equal(parsed.apReconciled, true);
  });

  test("preserves a false reconciliation flag", () => {
    const parsed = parseFinanceSubledgerReconciliationSummary({
      arControlAccountCode: "AR-CTRL", arControlSubledgerBalance: 1575, arOpenItemTotal: 500, arReconciled: false,
      apControlAccountCode: "AP-CTRL", apControlSubledgerBalance: 300, apOpenItemTotal: 300, apReconciled: true,
    });
    assert.equal(parsed.arReconciled, false);
  });
});
