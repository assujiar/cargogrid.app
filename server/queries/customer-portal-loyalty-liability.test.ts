import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getLoyaltyLiabilityReconciliationRun,
  listLoyaltyLiabilityReconciliationRuns,
  listLoyaltyLiabilityReconciliationExceptions,
  getLoyaltyEngagementMetrics,
  getCustomerPortalLoyaltySummary,
  LoyaltyLiabilityQueryError,
  type LoyaltyLiabilityQueryClient,
} from "./customer-portal-loyalty-liability.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyLiabilityQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyLiabilityQueryClient;
  return { client, calls };
}

const RUN_ROW = {
  id: RUN_ID,
  tenant_id: TENANT_ID,
  as_of: "2026-08-18T00:00:00.000Z",
  currency: "USD",
  status: "open",
  points_liability_total: 400,
  cashback_liability_total: 0,
  discount_liability_total: 0,
  voucher_liability_total: 40,
  reward_fulfillment_liability_total: 75,
  computed_at: "2026-08-18T00:00:00.000Z",
  config_version: 1,
  idempotency_key: "lra-clean-run",
  executed_by: "manager1",
  certified_by: null,
  certified_at: null,
  record_version: 1,
  created_at: "2026-08-18T00:00:00.000Z",
  updated_at: "2026-08-18T00:00:00.000Z",
};

describe("getLoyaltyLiabilityReconciliationRun", () => {
  test("maps the returned row and forwards args", async () => {
    const { client, calls } = fakeRpcClient({ data: [RUN_ROW], error: null });
    const result = await getLoyaltyLiabilityReconciliationRun(client, TENANT_ID, RUN_ID, ACTOR_ID);
    assert.equal(result.pointsLiabilityTotal, 400);
    assert.deepEqual(calls[0], { fn: "get_loyalty_liability_reconciliation_run", args: { p_tenant_id: TENANT_ID, p_run_id: RUN_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("throws LoyaltyLiabilityQueryError with a classified code on RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_liability_reconciliation_run_not_found: nope" } });
    await assert.rejects(() => getLoyaltyLiabilityReconciliationRun(client, TENANT_ID, RUN_ID, ACTOR_ID), (err: unknown) => {
      assert.ok(err instanceof LoyaltyLiabilityQueryError);
      assert.equal(err.code, "loyalty_liability_reconciliation_run_not_found");
      return true;
    });
  });
});

describe("listLoyaltyLiabilityReconciliationRuns", () => {
  test("defaults cursor/limit/currency/status", async () => {
    const { client, calls } = fakeRpcClient({ data: [RUN_ROW], error: null });
    const result = await listLoyaltyLiabilityReconciliationRuns(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0], {
      fn: "list_loyalty_liability_reconciliation_runs",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_currency: null, p_status: null, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 },
    });
  });
});

describe("listLoyaltyLiabilityReconciliationExceptions", () => {
  test("forwards runId and options", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listLoyaltyLiabilityReconciliationExceptions(client, TENANT_ID, RUN_ID, ACTOR_ID, { status: "open", limit: 10 });
    assert.deepEqual(calls[0], {
      fn: "list_loyalty_liability_reconciliation_exceptions",
      args: { p_tenant_id: TENANT_ID, p_run_id: RUN_ID, p_actor_auth_user_id: ACTOR_ID, p_status: "open", p_cursor_updated_at: null, p_cursor_id: null, p_limit: 10 },
    });
  });
});

describe("getLoyaltyEngagementMetrics", () => {
  test("parses via Zod input schema and maps the aggregate row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          period_start: "2026-01-01T00:00:00.000Z",
          period_end: "2026-08-18T00:00:00.000Z",
          active_loyalty_accounts_count: 4,
          points_earned_total: 800,
          points_redeemed_total: 50,
          redemption_count: 1,
          redemption_rate: 0.25,
          published_reward_count: 1,
          rewards_with_redemption_count: 1,
          computed_at: "2026-08-18T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await getLoyaltyEngagementMetrics(client, { tenantId: TENANT_ID, periodStart: "2026-01-01T00:00:00.000Z", actorAuthUserId: ACTOR_ID });
    assert.equal(result.activeLoyaltyAccountsCount, 4);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_period_start: "2026-01-01T00:00:00.000Z", p_period_end: null, p_actor_auth_user_id: ACTOR_ID });
  });

  test("rejects a missing periodStart before ever calling rpc", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getLoyaltyEngagementMetrics(client, { tenantId: TENANT_ID, periodStart: "", actorAuthUserId: ACTOR_ID }));
    assert.equal(calls.length, 0);
  });
});

describe("getCustomerPortalLoyaltySummary", () => {
  test("maps a consolidated summary row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          loyalty_account_id: ACCOUNT_ID,
          customer_account_id: ACCOUNT_ID,
          program_id: TENANT_ID,
          program_name: "Lra Program",
          account_status: "active",
          enrolled_at: "2026-08-01T00:00:00.000Z",
          tier_name: null,
          tier_benefits: {},
          is_tier_benefits_suspended: false,
          points_available: 150,
          active_entitlements_count: 1,
          active_entitlements_summary: [{ benefitType: "voucher", currency: "USD", count: 1, total: 40 }],
          recent_redemptions: [],
          is_on_hold: false,
          hold_notice: null,
          generated_at: "2026-08-18T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await getCustomerPortalLoyaltySummary(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(result.pointsAvailable, 150);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID });
  });

  test("classifies a not-found RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_account_not_found: nope" } });
    await assert.rejects(() => getCustomerPortalLoyaltySummary(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID }), (err: unknown) => {
      assert.ok(err instanceof LoyaltyLiabilityQueryError);
      assert.equal(err.code, "loyalty_account_not_found");
      return true;
    });
  });
});
