import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceSettlements, getFinanceSettlementAllocations, searchFinanceApCandidatesForSettlement, SettlementQueryError, type SettlementQueryRpcClient } from "./settlement.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const SETTLEMENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const AP_ITEM_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): SettlementQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as SettlementQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

const SETTLEMENT_ROW = {
  id: SETTLEMENT_ID, tenant_id: TENANT_ID, company_id: null, settlement_number: null,
  vendor_master_id: VENDOR_ID, payment_reference: "PMT-1", bank_account_label: "Bank ***1234",
  currency: "USD", status: "draft", allocated_amount: "400.00", fee_amount: "0.00", total_amount: "400.00",
  settlement_date: "2026-03-15", idempotency_key: "prep-1", posting_period_id: null, execution_reference: null,
  submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
  executed_by: null, executed_at: null, posted_by: null, posted_at: null,
  void_reason: null, voided_by: null, voided_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-15T00:00:00.000Z", updated_at: "2026-03-15T00:00:00.000Z",
};

describe("listFinanceSettlements", () => {
  test("maps every returned row", async () => {
    const client = fakeRpcClient({ data: [SETTLEMENT_ROW], error: null });
    const settlements = await listFinanceSettlements(client, { tenantId: TENANT_ID, companyId: null, vendorMasterId: null, status: null, actorAuthUserId: ACTOR_ID });
    assert.equal(settlements.length, 1);
    assert.equal(settlements[0]?.status, "draft");
  });

  test("wraps a database error into a typed SettlementQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => listFinanceSettlements(client, { tenantId: TENANT_ID, companyId: null, vendorMasterId: null, status: null, actorAuthUserId: ACTOR_ID }),
      SettlementQueryError,
    );
  });
});

describe("getFinanceSettlementAllocations", () => {
  test("maps every returned allocation row", async () => {
    const client = fakeRpcClient({
      data: [{ id: AP_ITEM_ID, tenant_id: TENANT_ID, settlement_id: SETTLEMENT_ID, ap_open_item_id: AP_ITEM_ID, amount: "400.00", status: "applied", reason: null, reversed_by: null, reversed_at: null, created_at: "2026-03-15T00:00:00.000Z" }],
      error: null,
    });
    const allocations = await getFinanceSettlementAllocations(client, { settlementId: SETTLEMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(allocations.length, 1);
    assert.equal(allocations[0]?.amount, 400);
  });
});

describe("searchFinanceApCandidatesForSettlement", () => {
  test("maps every returned AP open-item candidate row", async () => {
    const client = fakeRpcClient({
      data: [{
        id: AP_ITEM_ID, tenant_id: TENANT_ID, company_id: null, vendor_master_id: VENDOR_ID,
        source_document_type: "vendor_bill", source_document_id: AP_ITEM_ID, currency: "USD",
        original_amount: "1000.00", settled_amount: "0.00", open_amount: "1000.00", status: "open",
        is_held: false, hold_reason: null, held_by: null, held_at: null, released_by: null, released_at: null,
        bill_date: "2026-03-10", due_date: "2026-04-09", posting_period_id: null,
        record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
      }],
      error: null,
    });
    const candidates = await searchFinanceApCandidatesForSettlement(client, { tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, currency: "USD", actorAuthUserId: ACTOR_ID });
    assert.equal(candidates.length, 1);
    assert.equal(candidates[0]?.openAmount, 1000);
  });
});
