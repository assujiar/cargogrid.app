import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  CreateMarginRuleVersionInputSchema,
  CalculateMarginInputSchema,
  OverrideMarginThresholdInputSchema,
  parseMarginRuleVersion,
  parseMarginCalculation,
} from "./margin.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const RATE_SELECTION_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const CALC_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("CreateMarginRuleVersionInputSchema", () => {
  test("defaults roundingMode to half_up", () => {
    const parsed = CreateMarginRuleVersionInputSchema.parse({
      tenantId: TENANT_ID,
      minimumMarginPct: 20,
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(parsed.roundingMode, "half_up");
  });

  test("rejects a minimumMarginPct above 100", () => {
    assert.throws(() =>
      CreateMarginRuleVersionInputSchema.parse({
        tenantId: TENANT_ID,
        minimumMarginPct: 150,
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });
});

describe("CalculateMarginInputSchema", () => {
  test("defaults discountPct to 0", () => {
    const parsed = CalculateMarginInputSchema.parse({
      rateSelectionId: RATE_SELECTION_ID,
      sellAmount: 12000000,
      sellCurrency: "IDR",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.discountPct, 0);
  });

  test("rejects a malformed sell currency", () => {
    assert.throws(() =>
      CalculateMarginInputSchema.parse({
        rateSelectionId: RATE_SELECTION_ID,
        sellAmount: 12000000,
        sellCurrency: "idr",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("rejects a negative sell amount", () => {
    assert.throws(() =>
      CalculateMarginInputSchema.parse({
        rateSelectionId: RATE_SELECTION_ID,
        sellAmount: -1,
        sellCurrency: "IDR",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("OverrideMarginThresholdInputSchema", () => {
  test("rejects an empty reason", () => {
    assert.throws(() =>
      OverrideMarginThresholdInputSchema.parse({
        marginCalculationId: CALC_ID,
        expectedVersion: 1,
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("parseMarginRuleVersion", () => {
  test("maps a raw app.margin_rule_versions row to the camelCase contract shape", () => {
    const rule = parseMarginRuleVersion({
      id: RULE_ID,
      tenant_id: TENANT_ID,
      minimum_margin_pct: 20,
      rounding_mode: "half_up",
      status: "published",
      supersedes_version_id: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
      updated_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(rule.minimumMarginPct, 20);
    assert.equal(rule.status, "published");
  });
});

describe("parseMarginCalculation", () => {
  test("maps a raw app.margin_calculations_directory row to the camelCase contract shape", () => {
    const calc = parseMarginCalculation({
      id: CALC_ID,
      tenant_id: TENANT_ID,
      costing_request_id: REQUEST_ID,
      rate_selection_id: RATE_SELECTION_ID,
      cost_amount: null,
      cost_currency: "IDR",
      sell_amount: 15000000,
      sell_currency: "IDR",
      discount_pct: 0,
      discount_amount: null,
      net_sell_amount: 15000000,
      margin_amount: null,
      margin_pct: null,
      markup_pct: null,
      cost_masked: true,
      sell_masked: false,
      rule_version_id: RULE_ID,
      minimum_margin_pct_snapshot: 20,
      rounding_mode_snapshot: "half_up",
      threshold_outcome: "pass",
      is_overridden: false,
      override_reason: null,
      override_by: null,
      override_at: null,
      is_current: true,
      superseded_by_id: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
      updated_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(calc.costMasked, true);
    assert.equal(calc.marginAmount, null);
    assert.equal(calc.sellAmount, 15000000);
  });
});
