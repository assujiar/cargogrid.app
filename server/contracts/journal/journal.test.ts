import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceJournalStatusSchema,
  CreateFinanceJournalDraftInputSchema,
  parseFinanceJournal,
  parseFinanceJournalLine,
} from "./journal.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOURNAL_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("FinanceJournalStatusSchema", () => {
  test("accepts the five canonical lifecycle states", () => {
    for (const status of ["draft", "submitted", "approved", "posted", "void"]) {
      assert.doesNotThrow(() => FinanceJournalStatusSchema.parse(status));
    }
  });
});

describe("CreateFinanceJournalDraftInputSchema", () => {
  test("requires at least two lines", () => {
    assert.throws(() => CreateFinanceJournalDraftInputSchema.parse({
      tenantId: TENANT_ID, journalDate: "2026-03-05", currency: "USD",
      lines: [{ accountId: ACCOUNT_ID, direction: "debit", amount: 100 }],
      idempotencyKey: "jrnl-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });

  test("defaults companyId to null and each line's description/dimension to null", () => {
    const parsed = CreateFinanceJournalDraftInputSchema.parse({
      tenantId: TENANT_ID, journalDate: "2026-03-05", currency: "USD",
      lines: [
        { accountId: ACCOUNT_ID, direction: "debit", amount: 100 },
        { accountId: ACCOUNT_ID, direction: "credit", amount: 100 },
      ],
      idempotencyKey: "jrnl-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(parsed.companyId, null);
    assert.equal(parsed.lines[0]?.description, null);
    assert.equal(parsed.lines[0]?.dimension, null);
  });

  test("rejects a non-positive line amount", () => {
    assert.throws(() => CreateFinanceJournalDraftInputSchema.parse({
      tenantId: TENANT_ID, journalDate: "2026-03-05", currency: "USD",
      lines: [
        { accountId: ACCOUNT_ID, direction: "debit", amount: 0 },
        { accountId: ACCOUNT_ID, direction: "credit", amount: 100 },
      ],
      idempotencyKey: "jrnl-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });
});

describe("parseFinanceJournal", () => {
  test("maps a raw snake_case row, coercing string amounts", () => {
    const parsed = parseFinanceJournal({
      id: JOURNAL_ID, tenant_id: TENANT_ID, company_id: null, journal_number: "JRNL-2026-000001",
      source_type: "manual", source_id: null, idempotency_key: "jrnl-1", currency: "USD",
      total_amount: "500.00", journal_date: "2026-03-05", status: "posted", posting_period_id: null,
      submitted_by: "fe", submitted_at: "2026-03-05T00:00:00.000Z", approved_by: "fm", approved_at: "2026-03-05T00:00:00.000Z",
      posted_by: "fm", posted_at: "2026-03-05T00:00:00.000Z", void_reason: null, voided_by: null, voided_at: null,
      record_version: 4, created_by: "fm", created_at: "2026-03-05T00:00:00.000Z", updated_at: "2026-03-05T00:00:00.000Z",
    });
    assert.equal(parsed.totalAmount, 500);
    assert.equal(parsed.journalNumber, "JRNL-2026-000001");
    assert.equal(parsed.sourceId, null);
  });

  test("maps a system journal with a non-null sourceId", () => {
    const parsed = parseFinanceJournal({
      id: JOURNAL_ID, tenant_id: TENANT_ID, company_id: null, journal_number: "JRNL-2026-000002",
      source_type: "subledger", source_id: ACCOUNT_ID, idempotency_key: "subledger:x", currency: "USD",
      total_amount: "1200.00", journal_date: "2026-03-08", status: "posted", posting_period_id: null,
      submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
      posted_by: "fm", posted_at: "2026-03-08T00:00:00.000Z", void_reason: null, voided_by: null, voided_at: null,
      record_version: 1, created_by: "fm", created_at: "2026-03-08T00:00:00.000Z", updated_at: "2026-03-08T00:00:00.000Z",
    });
    assert.equal(parsed.sourceType, "subledger");
    assert.equal(parsed.sourceId, ACCOUNT_ID);
  });
});

describe("parseFinanceJournalLine", () => {
  test("maps a raw snake_case line row", () => {
    const parsed = parseFinanceJournalLine({
      id: JOURNAL_ID, journal_id: JOURNAL_ID, tenant_id: TENANT_ID, line_number: 1, account_id: ACCOUNT_ID,
      dimension: null, direction: "debit", amount: "500.00", description: "opening cash", created_at: "2026-03-05T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 500);
    assert.equal(parsed.direction, "debit");
  });
});
