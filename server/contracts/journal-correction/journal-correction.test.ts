import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceCorrectionStatusSchema,
  PrepareFinanceJournalReversalInputSchema,
  PrepareFinanceJournalAdjustmentInputSchema,
  parseFinanceJournalCorrection,
} from "./journal-correction.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CORRECTION_ID = "323e4567-e89b-12d3-a456-426614174001";
const JOURNAL_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("FinanceCorrectionStatusSchema", () => {
  test("accepts the five canonical lifecycle states", () => {
    for (const status of ["draft", "submitted", "approved", "posted", "discarded"]) {
      assert.doesNotThrow(() => FinanceCorrectionStatusSchema.parse(status));
    }
  });

  test("rejects an unmapped status", () => {
    assert.throws(() => FinanceCorrectionStatusSchema.parse("reversed"));
  });
});

describe("PrepareFinanceJournalReversalInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() => PrepareFinanceJournalReversalInputSchema.parse({
      tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
      reason: "", idempotencyKey: "rev-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });

  test("accepts a well-formed reversal request", () => {
    const parsed = PrepareFinanceJournalReversalInputSchema.parse({
      tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
      reason: "duplicate posting", idempotencyKey: "rev-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(parsed.reason, "duplicate posting");
    assert.equal(parsed.companyId, null);
  });
});

describe("PrepareFinanceJournalAdjustmentInputSchema", () => {
  test("requires at least two adjustment lines", () => {
    assert.throws(() => PrepareFinanceJournalAdjustmentInputSchema.parse({
      tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
      reason: "reclass", idempotencyKey: "adj-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      adjustmentLines: [{ accountId: ACCOUNT_ID, direction: "debit", amount: 100 }],
    }));
  });

  test("accepts a balanced-looking pair of lines (server re-validates the actual balance)", () => {
    const parsed = PrepareFinanceJournalAdjustmentInputSchema.parse({
      tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
      reason: "reclass", idempotencyKey: "adj-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      adjustmentLines: [
        { accountId: ACCOUNT_ID, direction: "debit", amount: 100 },
        { accountId: ACCOUNT_ID, direction: "credit", amount: 100 },
      ],
    });
    assert.equal(parsed.adjustmentLines.length, 2);
  });
});

describe("parseFinanceJournalCorrection", () => {
  test("maps a raw snake_case row to camelCase", () => {
    const parsed = parseFinanceJournalCorrection({
      id: CORRECTION_ID, tenant_id: TENANT_ID, company_id: null, original_journal_id: JOURNAL_ID,
      correction_type: "reversal", correction_date: "2026-04-01", reason: "duplicate posting",
      evidence_ref: null, adjustment_lines: null, status: "draft", idempotency_key: "rev-1",
      correction_journal_id: null, submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
      posted_by: null, posted_at: null, discard_reason: null, discarded_by: null, discarded_at: null,
      record_version: 1, created_by: "fm", created_at: "2026-04-01T00:00:00.000Z", updated_at: "2026-04-01T00:00:00.000Z",
    });
    assert.equal(parsed.correctionType, "reversal");
    assert.equal(parsed.originalJournalId, JOURNAL_ID);
    assert.equal(parsed.correctionJournalId, null);
  });
});
