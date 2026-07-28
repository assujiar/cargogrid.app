import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listFinanceCurrencies,
  listFinanceExchangeRates,
  resolveFinanceExchangeRate,
  convertFinanceAmount,
  CurrencyExchangeRateQueryError,
  type CurrencyExchangeRateQueryRpcClient,
  type FinanceCurrencyTableClient,
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
  status: "approved",
  approved_by: "finance-approver",
  approved_at: "2026-07-28T00:00:00.000Z",
  import_batch_id: null,
  record_version: 2,
  created_by: "finance-manager",
  created_at: "2026-07-28T00:00:00.000Z",
  updated_at: "2026-07-28T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): CurrencyExchangeRateQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CurrencyExchangeRateQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("listFinanceCurrencies", () => {
  function fakeTableClient(rows: unknown[]): FinanceCurrencyTableClient {
    const chain = {
      select: () => chain,
      order: async () => ({ data: rows, error: null }),
    };
    return { from: () => chain } as unknown as FinanceCurrencyTableClient;
  }

  test("maps every currency row", async () => {
    const client = fakeTableClient([{ code: "USD", name: "United States Dollar", minor_unit_precision: 2, is_active: true }]);
    const currencies = await listFinanceCurrencies(client);
    assert.equal(currencies.length, 1);
    assert.equal(currencies[0]?.code, "USD");
  });
});

describe("listFinanceExchangeRates", () => {
  test("maps every returned row to the FinanceExchangeRate contract shape", async () => {
    const client = fakeRpcClient({ data: [RATE_ROW], error: null });
    const rates = await listFinanceExchangeRates(client, { tenantId: TENANT_ID, rateType: null, sourceCurrency: null, targetCurrency: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rates.length, 1);
    assert.equal(rates[0]?.rate, 15750.5);
  });

  test("wraps a database error into a typed CurrencyExchangeRateQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => listFinanceExchangeRates(client, { tenantId: TENANT_ID, rateType: null, sourceCurrency: null, targetCurrency: null, actorAuthUserId: ACTOR_ID }),
      CurrencyExchangeRateQueryError,
    );
  });
});

describe("resolveFinanceExchangeRate", () => {
  test("returns the resolved rate when one covers the requested instant", async () => {
    const client = fakeRpcClient({ data: [RATE_ROW], error: null });
    const rate = await resolveFinanceExchangeRate(client, { tenantId: TENANT_ID, rateType: "spot", sourceCurrency: "USD", targetCurrency: "IDR", asOf: "2026-07-28T00:00:00.000Z" });
    assert.equal(rate?.status, "approved");
  });

  test("returns null when no approved rate covers the requested instant", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const rate = await resolveFinanceExchangeRate(client, { tenantId: TENANT_ID, rateType: "spot", sourceCurrency: "USD", targetCurrency: "IDR", asOf: null });
    assert.equal(rate, null);
  });
});

describe("convertFinanceAmount", () => {
  test("parses a conversion result, coercing a string rate", async () => {
    const client = fakeRpcClient({
      data: { amount: 100, sourceCurrency: "USD", targetCurrency: "IDR", rate: "15750.5000000000", rateId: RATE_ID, convertedAmount: 1575050, roundingMode: "round_half_up", roundingOrder: "convert_then_round" },
      error: null,
    });
    const converted = await convertFinanceAmount(client, { tenantId: TENANT_ID, amount: 100, sourceCurrency: "USD", targetCurrency: "IDR", rateType: "spot", asOf: null, actorAuthUserId: ACTOR_ID });
    assert.equal(converted.rate, 15750.5);
    assert.equal(converted.convertedAmount, 1575050);
  });

  test("wraps a finance_exchange_rate_missing error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "finance_exchange_rate_missing: no approved spot rate from USD to IDR covers 2026-07-28" } });
    await assert.rejects(
      () => convertFinanceAmount(client, { tenantId: TENANT_ID, amount: 100, sourceCurrency: "USD", targetCurrency: "IDR", rateType: "spot", asOf: null, actorAuthUserId: ACTOR_ID }),
      CurrencyExchangeRateQueryError,
    );
  });

  test("short-circuits identically for a same-currency conversion", async () => {
    const client = fakeRpcClient({
      data: { amount: 100, sourceCurrency: "USD", targetCurrency: "USD", rate: 1, rateId: null, convertedAmount: 100, roundingMode: "identity" },
      error: null,
    });
    const converted = await convertFinanceAmount(client, { tenantId: TENANT_ID, amount: 100, sourceCurrency: "USD", targetCurrency: "USD", rateType: "spot", asOf: null, actorAuthUserId: ACTOR_ID });
    assert.equal(converted.roundingMode, "identity");
    assert.equal(converted.rateId, null);
  });
});
