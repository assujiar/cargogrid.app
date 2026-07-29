import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createFinanceJournalDraft,
  submitFinanceJournalForApproval,
  discardFinanceJournalDraft,
  approveFinanceJournal,
  postFinanceJournal,
  JournalMutationError,
  type JournalMutationRpcClient,
} from "./journal.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOURNAL_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const JOURNAL_ROW = {
  id: JOURNAL_ID, tenant_id: TENANT_ID, company_id: null, journal_number: null,
  source_type: "manual", source_id: null, idempotency_key: "jrnl-1", currency: "USD",
  total_amount: "500.00", journal_date: "2026-03-05", status: "draft", posting_period_id: null,
  submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
  posted_by: null, posted_at: null, void_reason: null, voided_by: null, voided_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-05T00:00:00.000Z", updated_at: "2026-03-05T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): JournalMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as JournalMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("createFinanceJournalDraft", () => {
  test("calls create_finance_journal_draft with exact snake_case params, mapping lines", async () => {
    const client = fakeClient({ data: JOURNAL_ROW, error: null });
    await createFinanceJournalDraft(client, {
      tenantId: TENANT_ID, journalDate: "2026-03-05", currency: "USD",
      lines: [
        { accountId: ACCOUNT_ID, direction: "debit", amount: 500 },
        { accountId: ACCOUNT_ID, direction: "credit", amount: 500 },
      ],
      idempotencyKey: "jrnl-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "create_finance_journal_draft");
    assert.deepEqual(client.calls[0]?.args.p_lines, [
      { accountId: ACCOUNT_ID, direction: "debit", amount: 500, description: null, dimension: null },
      { accountId: ACCOUNT_ID, direction: "credit", amount: 500, description: null, dimension: null },
    ]);
  });

  test("wraps a finance_journal_unbalanced error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_journal_unbalanced: debit total 500 does not equal credit total 400" } });
    await assert.rejects(
      () => createFinanceJournalDraft(client, {
        tenantId: TENANT_ID, journalDate: "2026-03-05", currency: "USD",
        lines: [
          { accountId: ACCOUNT_ID, direction: "debit", amount: 500 },
          { accountId: ACCOUNT_ID, direction: "credit", amount: 400 },
        ],
        idempotencyKey: "jrnl-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
      (error: unknown) => error instanceof JournalMutationError && error.code === "finance_journal_unbalanced",
    );
  });
});

describe("submitFinanceJournalForApproval / discardFinanceJournalDraft / approveFinanceJournal", () => {
  test("submitFinanceJournalForApproval calls submit_finance_journal_for_approval", async () => {
    const client = fakeClient({ data: { ...JOURNAL_ROW, status: "submitted" }, error: null });
    const journal = await submitFinanceJournalForApproval(client, { journalId: JOURNAL_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(journal.status, "submitted");
  });

  test("discardFinanceJournalDraft wraps a finance_journal_not_cancellable error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_journal_not_cancellable: journal is approved, only a draft or submitted journal may be discarded" } });
    await assert.rejects(
      () => discardFinanceJournalDraft(client, { journalId: JOURNAL_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof JournalMutationError && error.code === "finance_journal_not_cancellable",
    );
  });

  test("approveFinanceJournal wraps a finance_journal_not_submitted error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_journal_not_submitted: journal is draft not submitted" } });
    await assert.rejects(
      () => approveFinanceJournal(client, { journalId: JOURNAL_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof JournalMutationError && error.code === "finance_journal_not_submitted",
    );
  });
});

describe("postFinanceJournal", () => {
  test("calls post_finance_journal and returns a journal_number", async () => {
    const client = fakeClient({ data: { ...JOURNAL_ROW, status: "posted", journal_number: "JRNL-2026-000001" }, error: null });
    const journal = await postFinanceJournal(client, { journalId: JOURNAL_ID, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(journal.status, "posted");
    assert.equal(journal.journalNumber, "JRNL-2026-000001");
  });

  test("wraps a finance_journal_not_approved error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_journal_not_approved: journal is submitted not approved" } });
    await assert.rejects(
      () => postFinanceJournal(client, { journalId: JOURNAL_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof JournalMutationError && error.code === "finance_journal_not_approved",
    );
  });
});
