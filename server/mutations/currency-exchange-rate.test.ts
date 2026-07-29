import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createFinanceExchangeRateDraft,
  discardFinanceExchangeRateDraft,
  approveFinanceExchangeRate,
  stageFinanceExchangeRateImport,
  CurrencyExchangeRateMutationError,
  type CurrencyExchangeRateMutationRpcClient,
} from "./currency-exchange-rate.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RATE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const RATE_ROW = {
  id: RATE_ID,
  tenant_id: TENANT_ID,
  rate_type: "spot",
  source_currency: "USD",
  target_currency: "IDR",
  rate: "15750.5000000000",
  source: "manual",
  effective_from: "2026-07-28T00:00:00.000Z",
  effective_to: null,
  status: "draft",
  approved_by: null,
  approved_at: null,
  import_batch_id: null,
  record_version: 1,
  created_by: "finance-manager",
  created_at: "2026-07-28T00:00:00.000Z",
  updated_at: "2026-07-28T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): CurrencyExchangeRateMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CurrencyExchangeRateMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("createFinanceExchangeRateDraft", () => {
  test("calls create_finance_exchange_rate_draft with the exact snake_case params", async () => {
    const client = fakeClient({ data: RATE_ROW, error: null });
    await createFinanceExchangeRateDraft(client, {
      tenantId: TENANT_ID,
      sourceCurrency: "USD",
      targetCurrency: "IDR",
      rate: 15750.5,
      effectiveFrom: "2026-07-28T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
      createdBy: "finance-manager",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_rate_type: "spot",
      p_source_currency: "USD",
      p_target_currency: "IDR",
      p_rate: 15750.5,
      p_source: "manual",
      p_effective_from: "2026-07-28T00:00:00.000Z",
      p_effective_to: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "finance-manager",
    });
  });

  test("wraps a finance_exchange_rate_unsupported_currency error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_exchange_rate_unsupported_currency: GBP is not a registered, active currency" } });
    await assert.rejects(
      () =>
        createFinanceExchangeRateDraft(client, {
          tenantId: TENANT_ID,
          sourceCurrency: "GBP",
          targetCurrency: "IDR",
          rate: 1,
          effectiveFrom: "2026-07-28T00:00:00.000Z",
          actorAuthUserId: ACTOR_ID,
          createdBy: "finance-manager",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CurrencyExchangeRateMutationError);
        assert.equal(err.code, "finance_exchange_rate_unsupported_currency");
        return true;
      },
    );
  });
});

describe("discardFinanceExchangeRateDraft", () => {
  test("calls discard_finance_exchange_rate_draft and returns the archived row", async () => {
    const client = fakeClient({ data: { ...RATE_ROW, status: "archived" }, error: null });
    const rate = await discardFinanceExchangeRateDraft(client, { rateId: RATE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "finance-manager" });
    assert.equal(rate.status, "archived");
  });

  test("wraps a finance_exchange_rate_not_draft error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_exchange_rate_not_draft: rate is approved, only a draft may be discarded" } });
    await assert.rejects(
      () => discardFinanceExchangeRateDraft(client, { rateId: RATE_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "finance-manager" }),
      (err: unknown) => {
        assert.ok(err instanceof CurrencyExchangeRateMutationError);
        assert.equal(err.code, "finance_exchange_rate_not_draft");
        return true;
      },
    );
  });
});

describe("approveFinanceExchangeRate", () => {
  test("calls approve_finance_exchange_rate and returns the approved row", async () => {
    const client = fakeClient({ data: { ...RATE_ROW, status: "approved", approved_by: "finance-approver", approved_at: "2026-07-28T00:00:00.000Z" }, error: null });
    const rate = await approveFinanceExchangeRate(client, { rateId: RATE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "finance-approver" });
    assert.equal(rate.status, "approved");
  });

  test("wraps a finance_exchange_rate_overlap error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_exchange_rate_overlap: an approved rate already covers an overlapping window for this scope/type/pair" } });
    await assert.rejects(
      () => approveFinanceExchangeRate(client, { rateId: RATE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "finance-approver" }),
      (err: unknown) => {
        assert.ok(err instanceof CurrencyExchangeRateMutationError);
        assert.equal(err.code, "finance_exchange_rate_overlap");
        return true;
      },
    );
  });
});

describe("stageFinanceExchangeRateImport", () => {
  test("maps camelCase import rows to the exact snake_case jsonb shape", async () => {
    const client = fakeClient({
      data: { id: "523e4567-e89b-12d3-a456-426614174000", tenant_id: TENANT_ID, idempotency_key: "batch-1", row_count: 1, created_by: "finance-manager", created_at: "2026-07-28T00:00:00.000Z" },
      error: null,
    });
    await stageFinanceExchangeRateImport(client, {
      tenantId: TENANT_ID,
      idempotencyKey: "batch-1",
      rows: [{ sourceCurrency: "USD", targetCurrency: "IDR", rate: 15750.5, effectiveFrom: "2026-07-28T00:00:00.000Z" }],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "finance-manager",
    });

    assert.deepEqual(client.calls[0]?.args.p_rows, [
      { rate_type: "spot", source_currency: "USD", target_currency: "IDR", rate: 15750.5, source: "import", effective_from: "2026-07-28T00:00:00.000Z", effective_to: null },
    ]);
  });

  test("returns the original batch's row count on a retried call (idempotent)", async () => {
    const client = fakeClient({
      data: { id: "523e4567-e89b-12d3-a456-426614174000", tenant_id: TENANT_ID, idempotency_key: "batch-1", row_count: 1, created_by: "finance-manager", created_at: "2026-07-28T00:00:00.000Z" },
      error: null,
    });
    const result = await stageFinanceExchangeRateImport(client, {
      tenantId: TENANT_ID,
      idempotencyKey: "batch-1",
      rows: [],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "finance-manager",
    });
    assert.equal(result.rowCount, 1);
    assert.equal(result.idempotencyKey, "batch-1");
  });
});
