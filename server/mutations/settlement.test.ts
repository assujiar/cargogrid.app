import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  prepareFinanceSettlement,
  submitFinanceSettlementForApproval,
  discardFinanceSettlementDraft,
  approveFinanceSettlement,
  executeFinanceSettlement,
  postFinanceSettlement,
  requestFinanceSettlementReversal,
  SettlementMutationError,
  type SettlementMutationRpcClient,
} from "./settlement.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const SETTLEMENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const AP_ITEM_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

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

function fakeClient(response: { data: unknown; error: { message: string } | null }): SettlementMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as SettlementMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("prepareFinanceSettlement", () => {
  test("calls prepare_finance_settlement with exact snake_case params, mapping allocations", async () => {
    const client = fakeClient({ data: SETTLEMENT_ROW, error: null });
    await prepareFinanceSettlement(client, {
      tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, paymentReference: "PMT-1", currency: "USD", settlementDate: "2026-03-15",
      allocations: [{ apOpenItemId: AP_ITEM_ID, amount: 400 }], feeAmount: 0,
      idempotencyKey: "prep-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "prepare_finance_settlement");
    assert.deepEqual(client.calls[0]?.args.p_allocations, [{ apOpenItemId: AP_ITEM_ID, amount: 400 }]);
    assert.equal(client.calls[0]?.args.p_payment_reference, "PMT-1");
  });

  test("wraps a finance_settlement_over_allocation error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_settlement_over_allocation: allocation 5000 exceeds open amount 1000" } });
    await assert.rejects(
      () => prepareFinanceSettlement(client, {
        tenantId: TENANT_ID, vendorMasterId: VENDOR_ID, currency: "USD", settlementDate: "2026-03-15",
        allocations: [{ apOpenItemId: AP_ITEM_ID, amount: 5000 }], idempotencyKey: "prep-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
      (error: unknown) => error instanceof SettlementMutationError && error.code === "finance_settlement_over_allocation",
    );
  });
});

describe("submitFinanceSettlementForApproval / discardFinanceSettlementDraft / approveFinanceSettlement", () => {
  test("submitFinanceSettlementForApproval calls submit_finance_settlement_for_approval", async () => {
    const client = fakeClient({ data: { ...SETTLEMENT_ROW, status: "submitted" }, error: null });
    const settlement = await submitFinanceSettlementForApproval(client, { settlementId: SETTLEMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(settlement.status, "submitted");
  });

  test("discardFinanceSettlementDraft wraps a finance_settlement_not_cancellable error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_settlement_not_cancellable: settlement is approved, only a draft or submitted settlement may be discarded" } });
    await assert.rejects(
      () => discardFinanceSettlementDraft(client, { settlementId: SETTLEMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof SettlementMutationError && error.code === "finance_settlement_not_cancellable",
    );
  });

  test("approveFinanceSettlement wraps a finance_settlement_not_submitted error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_settlement_not_submitted: settlement is draft not submitted" } });
    await assert.rejects(
      () => approveFinanceSettlement(client, { settlementId: SETTLEMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof SettlementMutationError && error.code === "finance_settlement_not_submitted",
    );
  });
});

describe("executeFinanceSettlement", () => {
  test("calls execute_finance_settlement with an execution reference", async () => {
    const client = fakeClient({ data: { ...SETTLEMENT_ROW, status: "executed", execution_reference: "TXN-1" }, error: null });
    const settlement = await executeFinanceSettlement(client, { settlementId: SETTLEMENT_ID, expectedVersion: 3, executionReference: "TXN-1", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(settlement.status, "executed");
    assert.equal(settlement.executionReference, "TXN-1");
  });

  test("wraps a finance_settlement_not_approved error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_settlement_not_approved: settlement is submitted not approved" } });
    await assert.rejects(
      () => executeFinanceSettlement(client, { settlementId: SETTLEMENT_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof SettlementMutationError && error.code === "finance_settlement_not_approved",
    );
  });
});

describe("postFinanceSettlement", () => {
  test("calls post_finance_settlement and returns a settlement_number", async () => {
    const client = fakeClient({ data: { ...SETTLEMENT_ROW, status: "posted", settlement_number: "SETL-2026-000001" }, error: null });
    const settlement = await postFinanceSettlement(client, { settlementId: SETTLEMENT_ID, expectedVersion: 4, actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(settlement.status, "posted");
    assert.equal(settlement.settlementNumber, "SETL-2026-000001");
  });

  test("wraps a finance_settlement_not_executed error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_settlement_not_executed: settlement is approved not executed" } });
    await assert.rejects(
      () => postFinanceSettlement(client, { settlementId: SETTLEMENT_ID, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof SettlementMutationError && error.code === "finance_settlement_not_executed",
    );
  });
});

describe("requestFinanceSettlementReversal", () => {
  test("calls request_finance_settlement_reversal with a reason", async () => {
    const client = fakeClient({ data: { ...SETTLEMENT_ROW, status: "reversed" }, error: null });
    const settlement = await requestFinanceSettlementReversal(client, { settlementId: SETTLEMENT_ID, reason: "wrong bank account", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(settlement.status, "reversed");
  });

  test("wraps a finance_settlement_reversal_reason_required error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_settlement_reversal_reason_required: a non-empty reason is required" } });
    await assert.rejects(
      () => requestFinanceSettlementReversal(client, { settlementId: SETTLEMENT_ID, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof SettlementMutationError && error.code === "finance_settlement_reversal_reason_required",
    );
  });
});
