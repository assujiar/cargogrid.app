import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceCurrencySchema,
  FinanceExchangeRateStatusSchema,
  CreateFinanceExchangeRateDraftInputSchema,
  DiscardFinanceExchangeRateDraftInputSchema,
  ApproveFinanceExchangeRateInputSchema,
  ConvertFinanceAmountInputSchema,
  parseFinanceCurrency,
  parseFinanceExchangeRate,
  parseFinanceConvertedAmount,
} from "./currency-exchange-rate.ts";

describe("FinanceCurrencySchema", () => {
  test("accepts a well-formed ISO 4217 currency row", () => {
    assert.doesNotThrow(() =>
      FinanceCurrencySchema.parse({ code: "USD", name: "United States Dollar", minorUnitPrecision: 2, isActive: true }),
    );
  });

  test("rejects a lowercase or non-3-letter code", () => {
    assert.throws(() =>
      FinanceCurrencySchema.parse({ code: "usd", name: "United States Dollar", minorUnitPrecision: 2, isActive: true }),
    );
    assert.throws(() =>
      FinanceCurrencySchema.parse({ code: "US", name: "United States Dollar", minorUnitPrecision: 2, isActive: true }),
    );
  });

  test("rejects a minor unit precision outside 0-6", () => {
    assert.throws(() =>
      FinanceCurrencySchema.parse({ code: "USD", name: "United States Dollar", minorUnitPrecision: 7, isActive: true }),
    );
  });
});

describe("FinanceExchangeRateStatusSchema", () => {
  test("accepts the three canonical lifecycle states", () => {
    for (const status of ["draft", "approved", "archived"]) {
      assert.doesNotThrow(() => FinanceExchangeRateStatusSchema.parse(status));
    }
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => FinanceExchangeRateStatusSchema.parse("published"));
  });
});

describe("CreateFinanceExchangeRateDraftInputSchema", () => {
  test("parses a well-formed draft request and defaults rateType/source", () => {
    const parsed = CreateFinanceExchangeRateDraftInputSchema.parse({
      tenantId: "123e4567-e89b-12d3-a456-426614174000",
      sourceCurrency: "USD",
      targetCurrency: "IDR",
      rate: 15750.5,
      effectiveFrom: "2026-07-28T00:00:00.000Z",
      actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
      createdBy: "finance-manager",
    });
    assert.equal(parsed.rateType, "spot");
    assert.equal(parsed.source, "manual");
    assert.equal(parsed.effectiveTo, null);
  });

  test("rejects a non-positive rate", () => {
    assert.throws(() =>
      CreateFinanceExchangeRateDraftInputSchema.parse({
        tenantId: "123e4567-e89b-12d3-a456-426614174000",
        sourceCurrency: "USD",
        targetCurrency: "IDR",
        rate: 0,
        effectiveFrom: "2026-07-28T00:00:00.000Z",
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
        createdBy: "finance-manager",
      }),
    );
  });

  test("rejects a currency code that is not 3 uppercase letters", () => {
    assert.throws(() =>
      CreateFinanceExchangeRateDraftInputSchema.parse({
        tenantId: "123e4567-e89b-12d3-a456-426614174000",
        sourceCurrency: "us",
        targetCurrency: "IDR",
        rate: 1,
        effectiveFrom: "2026-07-28T00:00:00.000Z",
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
        createdBy: "finance-manager",
      }),
    );
  });
});

describe("DiscardFinanceExchangeRateDraftInputSchema", () => {
  test("defaults reason to null", () => {
    const parsed = DiscardFinanceExchangeRateDraftInputSchema.parse({
      rateId: "323e4567-e89b-12d3-a456-426614174000",
      expectedVersion: 1,
      actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
      actorLabel: "finance-manager",
    });
    assert.equal(parsed.reason, null);
  });

  test("rejects a non-positive expectedVersion", () => {
    assert.throws(() =>
      DiscardFinanceExchangeRateDraftInputSchema.parse({
        rateId: "323e4567-e89b-12d3-a456-426614174000",
        expectedVersion: 0,
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
        actorLabel: "finance-manager",
      }),
    );
  });
});

describe("ApproveFinanceExchangeRateInputSchema", () => {
  test("requires a non-empty actorLabel", () => {
    assert.throws(() =>
      ApproveFinanceExchangeRateInputSchema.parse({
        rateId: "323e4567-e89b-12d3-a456-426614174000",
        expectedVersion: 1,
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
        actorLabel: "",
      }),
    );
  });
});

describe("ConvertFinanceAmountInputSchema", () => {
  test("parses a well-formed conversion request and defaults rateType/asOf", () => {
    const parsed = ConvertFinanceAmountInputSchema.parse({
      tenantId: "123e4567-e89b-12d3-a456-426614174000",
      amount: 100,
      sourceCurrency: "USD",
      targetCurrency: "IDR",
      actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
    });
    assert.equal(parsed.rateType, "spot");
    assert.equal(parsed.asOf, null);
  });

  test("accepts a null tenantId (platform-wide conversion)", () => {
    assert.doesNotThrow(() =>
      ConvertFinanceAmountInputSchema.parse({
        tenantId: null,
        amount: 100,
        sourceCurrency: "USD",
        targetCurrency: "IDR",
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
      }),
    );
  });
});

describe("parseFinanceCurrency", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const parsed = parseFinanceCurrency({ code: "JPY", name: "Japanese Yen", minor_unit_precision: 0, is_active: true });
    assert.equal(parsed.minorUnitPrecision, 0);
    assert.equal(parsed.isActive, true);
  });
});

describe("parseFinanceExchangeRate", () => {
  test("maps a raw snake_case row and coerces a string rate to a number", () => {
    const parsed = parseFinanceExchangeRate({
      id: "323e4567-e89b-12d3-a456-426614174000",
      tenant_id: "123e4567-e89b-12d3-a456-426614174000",
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
    });
    assert.equal(parsed.rate, 15750.5);
    assert.equal(typeof parsed.rate, "number");
    assert.equal(parsed.status, "draft");
  });
});

describe("parseFinanceConvertedAmount", () => {
  test("maps a raw jsonb result and coerces a string rate to a number", () => {
    const parsed = parseFinanceConvertedAmount({
      amount: 100,
      sourceCurrency: "USD",
      targetCurrency: "IDR",
      rate: "15750.5000000000",
      rateId: "323e4567-e89b-12d3-a456-426614174000",
      convertedAmount: 1575050,
      roundingMode: "round_half_up",
      roundingOrder: "convert_then_round",
    });
    assert.equal(parsed.rate, 15750.5);
    assert.equal(parsed.convertedAmount, 1575050);
  });

  test("defaults rateId and roundingOrder to null when absent", () => {
    const parsed = parseFinanceConvertedAmount({
      amount: 100,
      sourceCurrency: "USD",
      targetCurrency: "USD",
      rate: 1,
      convertedAmount: 100,
      roundingMode: "identity",
    });
    assert.equal(parsed.rateId, null);
    assert.equal(parsed.roundingOrder, null);
  });
});
