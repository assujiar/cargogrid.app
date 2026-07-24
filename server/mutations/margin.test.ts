import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createMarginRuleVersion,
  publishMarginRuleVersion,
  calculateMargin,
  overrideMarginThreshold,
  MarginMutationError,
  type MarginMutationRpcClient,
} from "./margin.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const RATE_SELECTION_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const CALC_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_RULE_ROW = {
  id: RULE_ID,
  tenant_id: TENANT_ID,
  minimum_margin_pct: 20,
  rounding_mode: "half_up",
  status: "draft",
  supersedes_version_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

const VALID_CALC_ROW = {
  id: CALC_ID,
  tenant_id: TENANT_ID,
  costing_request_id: REQUEST_ID,
  rate_selection_id: RATE_SELECTION_ID,
  cost_amount: 10000000,
  cost_currency: "IDR",
  sell_amount: 15000000,
  sell_currency: "IDR",
  discount_pct: 0,
  discount_amount: 0,
  net_sell_amount: 15000000,
  margin_amount: 5000000,
  margin_pct: 33.33,
  markup_pct: 50,
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
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): MarginMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as MarginMutationRpcClient;
}

describe("createMarginRuleVersion", () => {
  test("calls create_margin_rule_version with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_RULE_ROW, error: null }, calls);
    const rule = await createMarginRuleVersion(client, { tenantId: TENANT_ID, minimumMarginPct: 20, actorAuthUserId: ACTOR_ID, createdBy: "tester" });
    assert.equal(calls[0]?.fn, "create_margin_rule_version");
    assert.equal(calls[0]?.args.p_minimum_margin_pct, 20);
    assert.equal(rule.status, "draft");
  });

  test("classifies insufficient_authority", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks COM:Create (missing) for tenant y" } }, []);
    await assert.rejects(
      () => createMarginRuleVersion(client, { tenantId: TENANT_ID, minimumMarginPct: 20, actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof MarginMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishMarginRuleVersion", () => {
  test("calls publish_margin_rule_version with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RULE_ROW, status: "published" }, error: null }, calls);
    const rule = await publishMarginRuleVersion(client, { ruleVersionId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "publish_margin_rule_version");
    assert.equal(calls[0]?.args.p_supersedes_version_id, null);
    assert.equal(rule.status, "published");
  });

  test("classifies active_rule_exists", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "active_rule_exists: tenant x already has a published margin rule" } }, []);
    await assert.rejects(
      () => publishMarginRuleVersion(client, { ruleVersionId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof MarginMutationError);
        assert.equal(err.code, "active_rule_exists");
        return true;
      },
    );
  });
});

describe("calculateMargin", () => {
  test("calls calculate_margin with the exact snake_case params, unmasked (caller already holds View cost)", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_CALC_ROW, error: null }, calls);
    const calc = await calculateMargin(client, { rateSelectionId: RATE_SELECTION_ID, sellAmount: 15000000, sellCurrency: "IDR", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "calculate_margin");
    assert.equal(calls[0]?.args.p_discount_pct, 0);
    assert.equal(calc.costMasked, false);
    assert.equal(calc.marginPct, 33.33);
  });

  test("classifies mixed_currency", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "mixed_currency: sell currency USD does not match the pinned cost snapshot's currency IDR" } }, []);
    await assert.rejects(
      () => calculateMargin(client, { rateSelectionId: RATE_SELECTION_ID, sellAmount: 1, sellCurrency: "USD", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof MarginMutationError);
        assert.equal(err.code, "mixed_currency");
        return true;
      },
    );
  });

  test("classifies no_active_margin_rule", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "no_active_margin_rule: tenant x has no published margin rule" } }, []);
    await assert.rejects(
      () => calculateMargin(client, { rateSelectionId: RATE_SELECTION_ID, sellAmount: 1, sellCurrency: "IDR", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof MarginMutationError);
        assert.equal(err.code, "no_active_margin_rule");
        return true;
      },
    );
  });
});

describe("overrideMarginThreshold", () => {
  test("calls override_margin_threshold with the mandatory reason", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_CALC_ROW, is_overridden: true, override_reason: "Strategic account" }, error: null }, calls);
    const calc = await overrideMarginThreshold(client, { marginCalculationId: CALC_ID, expectedVersion: 1, reason: "Strategic account", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.args.p_reason, "Strategic account");
    assert.equal(calc.isOverridden, true);
  });

  test("classifies reason_required", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "reason_required: overriding a margin threshold requires a non-empty reason" } }, []);
    await assert.rejects(
      () => overrideMarginThreshold(client, { marginCalculationId: CALC_ID, expectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof MarginMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });
});
