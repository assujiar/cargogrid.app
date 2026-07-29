import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceJournalCorrections, getFinanceCorrectionChain, JournalCorrectionQueryError, type JournalCorrectionQueryRpcClient } from "./journal-correction.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CORRECTION_ID = "323e4567-e89b-12d3-a456-426614174001";
const JOURNAL_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const CORRECTION_ROW = {
  id: CORRECTION_ID, tenant_id: TENANT_ID, company_id: null, original_journal_id: JOURNAL_ID,
  correction_type: "reversal", correction_date: "2026-04-01", reason: "duplicate posting",
  evidence_ref: null, adjustment_lines: null, status: "draft", idempotency_key: "rev-1",
  correction_journal_id: null, submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
  posted_by: null, posted_at: null, discard_reason: null, discarded_by: null, discarded_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-04-01T00:00:00.000Z", updated_at: "2026-04-01T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): JournalCorrectionQueryRpcClient {
  return { async rpc() { return response; } } as unknown as JournalCorrectionQueryRpcClient;
}

describe("listFinanceJournalCorrections", () => {
  test("maps rows to camelCase", async () => {
    const client = fakeClient({ data: [CORRECTION_ROW], error: null });
    const rows = await listFinanceJournalCorrections(client, { tenantId: TENANT_ID, companyId: null, correctionType: null, status: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.correctionType, "reversal");
  });

  test("throws on rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: lacks FIN:View" } });
    await assert.rejects(() => listFinanceJournalCorrections(client, { tenantId: TENANT_ID, companyId: null, correctionType: null, status: null, actorAuthUserId: ACTOR_ID }), JournalCorrectionQueryError);
  });
});

describe("getFinanceCorrectionChain", () => {
  test("returns the correction, original journal and null correction journal when not yet posted", async () => {
    const client = fakeClient({ data: { correction: CORRECTION_ROW, originalJournal: { id: JOURNAL_ID, status: "posted" }, correctionJournal: null }, error: null });
    const chain = await getFinanceCorrectionChain(client, { correctionId: CORRECTION_ID, actorAuthUserId: ACTOR_ID });
    assert.equal((chain.originalJournal as { id: string }).id, JOURNAL_ID);
    assert.equal(chain.correctionJournal, null);
  });
});
