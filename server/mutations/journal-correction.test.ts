import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  prepareFinanceJournalReversal,
  prepareFinanceJournalAdjustment,
  submitFinanceCorrectionForApproval,
  discardFinanceCorrectionDraft,
  approveFinanceCorrection,
  postFinanceCorrection,
  JournalCorrectionMutationError,
  type JournalCorrectionMutationRpcClient,
} from "./journal-correction.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CORRECTION_ID = "323e4567-e89b-12d3-a456-426614174001";
const JOURNAL_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const CORRECTION_ROW = {
  id: CORRECTION_ID, tenant_id: TENANT_ID, company_id: null, original_journal_id: JOURNAL_ID,
  correction_type: "reversal", correction_date: "2026-04-01", reason: "duplicate posting",
  evidence_ref: null, adjustment_lines: null, status: "draft", idempotency_key: "rev-1",
  correction_journal_id: null, submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
  posted_by: null, posted_at: null, discard_reason: null, discarded_by: null, discarded_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-04-01T00:00:00.000Z", updated_at: "2026-04-01T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): JournalCorrectionMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as JournalCorrectionMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("prepareFinanceJournalReversal", () => {
  test("calls prepare_finance_journal_reversal with exact snake_case params", async () => {
    const client = fakeClient({ data: CORRECTION_ROW, error: null });
    await prepareFinanceJournalReversal(client, {
      tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
      reason: "duplicate posting", idempotencyKey: "rev-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "prepare_finance_journal_reversal");
    assert.equal(client.calls[0]?.args.p_original_journal_id, JOURNAL_ID);
  });

  test("wraps a finance_correction_duplicate_reversal error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_correction_duplicate_reversal: journal already has an active reversal request" } });
    await assert.rejects(
      () => prepareFinanceJournalReversal(client, {
        tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
        reason: "duplicate posting", idempotencyKey: "rev-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
      (error: unknown) => error instanceof JournalCorrectionMutationError && error.code === "finance_correction_duplicate_reversal",
    );
  });

  test("wraps a finance_correction_original_not_posted error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_correction_original_not_posted: journal is draft not posted" } });
    await assert.rejects(
      () => prepareFinanceJournalReversal(client, {
        tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
        reason: "duplicate posting", idempotencyKey: "rev-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
      (error: unknown) => error instanceof JournalCorrectionMutationError && error.code === "finance_correction_original_not_posted",
    );
  });
});

describe("prepareFinanceJournalAdjustment", () => {
  test("calls prepare_finance_journal_adjustment mapping adjustmentLines", async () => {
    const client = fakeClient({ data: { ...CORRECTION_ROW, correction_type: "adjustment" }, error: null });
    await prepareFinanceJournalAdjustment(client, {
      tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
      reason: "reclass", idempotencyKey: "adj-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      adjustmentLines: [
        { accountId: ACCOUNT_ID, direction: "debit", amount: 100 },
        { accountId: ACCOUNT_ID, direction: "credit", amount: 100 },
      ],
    });
    assert.equal(client.calls[0]?.fn, "prepare_finance_journal_adjustment");
    assert.equal((client.calls[0]?.args.p_adjustment_lines as unknown[]).length, 2);
  });

  test("wraps a finance_journal_unbalanced error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_journal_unbalanced: debit total 100 does not equal credit total 50" } });
    await assert.rejects(
      () => prepareFinanceJournalAdjustment(client, {
        tenantId: TENANT_ID, originalJournalId: JOURNAL_ID, correctionDate: "2026-04-01",
        reason: "reclass", idempotencyKey: "adj-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
        adjustmentLines: [
          { accountId: ACCOUNT_ID, direction: "debit", amount: 100 },
          { accountId: ACCOUNT_ID, direction: "credit", amount: 50 },
        ],
      }),
      (error: unknown) => error instanceof JournalCorrectionMutationError && error.code === "finance_journal_unbalanced",
    );
  });
});

describe("submitFinanceCorrectionForApproval / discardFinanceCorrectionDraft / approveFinanceCorrection", () => {
  test("submitFinanceCorrectionForApproval calls submit_finance_correction_for_approval", async () => {
    const client = fakeClient({ data: { ...CORRECTION_ROW, status: "submitted" }, error: null });
    const correction = await submitFinanceCorrectionForApproval(client, { correctionId: CORRECTION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(correction.status, "submitted");
  });

  test("discardFinanceCorrectionDraft wraps a finance_correction_not_cancellable error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_correction_not_cancellable: correction is approved, only a draft or submitted correction may be discarded" } });
    await assert.rejects(
      () => discardFinanceCorrectionDraft(client, { correctionId: CORRECTION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof JournalCorrectionMutationError && error.code === "finance_correction_not_cancellable",
    );
  });

  test("approveFinanceCorrection wraps a finance_correction_not_submitted error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_correction_not_submitted: correction is draft not submitted" } });
    await assert.rejects(
      () => approveFinanceCorrection(client, { correctionId: CORRECTION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof JournalCorrectionMutationError && error.code === "finance_correction_not_submitted",
    );
  });
});

describe("postFinanceCorrection", () => {
  test("calls post_finance_correction and returns a correctionJournalId", async () => {
    const client = fakeClient({ data: { ...CORRECTION_ROW, status: "posted", correction_journal_id: JOURNAL_ID }, error: null });
    const correction = await postFinanceCorrection(client, { correctionId: CORRECTION_ID, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(correction.status, "posted");
    assert.equal(correction.correctionJournalId, JOURNAL_ID);
  });

  test("wraps a finance_correction_not_approved error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_correction_not_approved: correction is submitted not approved" } });
    await assert.rejects(
      () => postFinanceCorrection(client, { correctionId: CORRECTION_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof JournalCorrectionMutationError && error.code === "finance_correction_not_approved",
    );
  });
});
