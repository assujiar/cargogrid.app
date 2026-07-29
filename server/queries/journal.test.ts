import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceJournals, getFinanceJournalLines, JournalQueryError, type JournalQueryRpcClient } from "./journal.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOURNAL_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): JournalQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as JournalQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

const JOURNAL_ROW = {
  id: JOURNAL_ID, tenant_id: TENANT_ID, company_id: null, journal_number: null,
  source_type: "manual", source_id: null, idempotency_key: "jrnl-1", currency: "USD",
  total_amount: "500.00", journal_date: "2026-03-05", status: "draft", posting_period_id: null,
  submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
  posted_by: null, posted_at: null, void_reason: null, voided_by: null, voided_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-05T00:00:00.000Z", updated_at: "2026-03-05T00:00:00.000Z",
};

describe("listFinanceJournals", () => {
  test("maps every returned row", async () => {
    const client = fakeRpcClient({ data: [JOURNAL_ROW], error: null });
    const journals = await listFinanceJournals(client, { tenantId: TENANT_ID, companyId: null, sourceType: null, status: null, actorAuthUserId: ACTOR_ID });
    assert.equal(journals.length, 1);
    assert.equal(journals[0]?.status, "draft");
  });

  test("wraps a database error into a typed JournalQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => listFinanceJournals(client, { tenantId: TENANT_ID, companyId: null, sourceType: null, status: null, actorAuthUserId: ACTOR_ID }),
      JournalQueryError,
    );
  });
});

describe("getFinanceJournalLines", () => {
  test("maps every returned line row", async () => {
    const client = fakeRpcClient({
      data: [{ id: JOURNAL_ID, journal_id: JOURNAL_ID, tenant_id: TENANT_ID, line_number: 1, account_id: ACCOUNT_ID, dimension: null, direction: "debit", amount: "500.00", description: null, created_at: "2026-03-05T00:00:00.000Z" }],
      error: null,
    });
    const lines = await getFinanceJournalLines(client, { journalId: JOURNAL_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(lines.length, 1);
    assert.equal(lines[0]?.amount, 500);
  });
});
