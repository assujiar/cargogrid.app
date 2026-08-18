import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  submitLoyaltyRedemption,
  decideLoyaltyRedemption,
  cancelLoyaltyRedemption,
  markLoyaltyRedemptionFulfilled,
  markLoyaltyRedemptionFulfillmentFailed,
  LoyaltyRedemptionMutationError,
  type LoyaltyRedemptionMutationRpcClient,
} from "./customer-portal-loyalty-redemptions.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REWARD_ID = "323e4567-e89b-12d3-a456-426614174000";
const REDEMPTION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyRedemptionMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyRedemptionMutationRpcClient;
  return { client, calls };
}

const REDEMPTION_ROW = {
  id: REDEMPTION_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  reward_id: REWARD_ID,
  reward_version_number: 1,
  reward_name: "Physical Reward",
  reward_type: "physical_item",
  points_consumed: "50",
  stock_reservation_id: null,
  benefit_entitlement_id: null,
  status: "pending_approval",
  fulfillment_status: "pending",
  decision_reason: null,
  decided_by: null,
  decided_at: null,
  idempotency_key: "idem-1",
  record_version: 1,
  created_by: "customer-1",
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("submitLoyaltyRedemption", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [REDEMPTION_ROW], error: null });
    const result = await submitLoyaltyRedemption(client, {
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      rewardId: REWARD_ID,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "customer-1",
    });
    assert.equal(result.status, "pending_approval");
    assert.deepEqual(calls[0], {
      fn: "submit_loyalty_redemption",
      args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_reward_id: REWARD_ID, p_idempotency_key: "idem-1", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "customer-1" },
    });
  });

  test("propagates account_on_hold with .code set, message never rewritten", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "account_on_hold: this account cannot redeem rewards at this time. Contact your account administrator or support for details." } });
    await assert.rejects(
      () => submitLoyaltyRedemption(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, rewardId: REWARD_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "customer-1" }),
      (err: unknown) => err instanceof LoyaltyRedemptionMutationError && err.code === "account_on_hold",
    );
  });

  test("rejects an empty idempotency key before ever calling rpc", async () => {
    const { client, calls } = fakeRpcClient({ data: [REDEMPTION_ROW], error: null });
    await assert.rejects(() => submitLoyaltyRedemption(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, rewardId: REWARD_ID, idempotencyKey: "", actorAuthUserId: ACTOR_ID, actorLabel: "customer-1" }));
    assert.equal(calls.length, 0);
  });
});

describe("decideLoyaltyRedemption", () => {
  test("passes the exact param names for an approve decision", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REDEMPTION_ROW, status: "fulfilling" }], error: null });
    await decideLoyaltyRedemption(client, { tenantId: TENANT_ID, redemptionId: REDEMPTION_ID, expectedVersion: 1, decision: "approve", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.deepEqual(calls[0], {
      fn: "decide_loyalty_redemption",
      args: { p_tenant_id: TENANT_ID, p_redemption_id: REDEMPTION_ID, p_expected_version: 1, p_decision: "approve", p_decision_reason: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });

  test("rejects a reject decision with no reason before ever calling rpc", async () => {
    const { client, calls } = fakeRpcClient({ data: [REDEMPTION_ROW], error: null });
    await assert.rejects(() => decideLoyaltyRedemption(client, { tenantId: TENANT_ID, redemptionId: REDEMPTION_ID, expectedVersion: 1, decision: "reject", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }));
    assert.equal(calls.length, 0);
  });

  test("propagates insufficient_authority for a customer_user actor (self-approval structurally impossible)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks LYL:Configure" } });
    await assert.rejects(
      () => decideLoyaltyRedemption(client, { tenantId: TENANT_ID, redemptionId: REDEMPTION_ID, expectedVersion: 1, decision: "approve", actorAuthUserId: ACTOR_ID, actorLabel: "customer-1" }),
      (err: unknown) => err instanceof LoyaltyRedemptionMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("cancelLoyaltyRedemption", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REDEMPTION_ROW, status: "cancelled" }], error: null });
    const result = await cancelLoyaltyRedemption(client, { tenantId: TENANT_ID, redemptionId: REDEMPTION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "customer-1" });
    assert.equal(result.status, "cancelled");
    assert.deepEqual(calls[0], {
      fn: "cancel_loyalty_redemption",
      args: { p_tenant_id: TENANT_ID, p_redemption_id: REDEMPTION_ID, p_expected_version: 1, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "customer-1" },
    });
  });
});

describe("markLoyaltyRedemptionFulfilled / markLoyaltyRedemptionFulfillmentFailed", () => {
  test("markLoyaltyRedemptionFulfilled passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REDEMPTION_ROW, status: "fulfilled", fulfillment_status: "fulfilled" }], error: null });
    await markLoyaltyRedemptionFulfilled(client, { tenantId: TENANT_ID, redemptionId: REDEMPTION_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.deepEqual(calls[0], {
      fn: "mark_loyalty_redemption_fulfilled",
      args: { p_tenant_id: TENANT_ID, p_redemption_id: REDEMPTION_ID, p_expected_version: 2, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });

  test("markLoyaltyRedemptionFulfillmentFailed requires a non-empty reason before ever calling rpc", async () => {
    const { client, calls } = fakeRpcClient({ data: [REDEMPTION_ROW], error: null });
    await assert.rejects(() => markLoyaltyRedemptionFulfillmentFailed(client, { tenantId: TENANT_ID, redemptionId: REDEMPTION_ID, expectedVersion: 2, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }));
    assert.equal(calls.length, 0);
  });

  test("markLoyaltyRedemptionFulfillmentFailed passes the exact param names with a real reason", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REDEMPTION_ROW, status: "failed", fulfillment_status: "failed" }], error: null });
    await markLoyaltyRedemptionFulfillmentFailed(client, { tenantId: TENANT_ID, redemptionId: REDEMPTION_ID, expectedVersion: 2, reason: "item damaged", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.deepEqual(calls[0], {
      fn: "mark_loyalty_redemption_fulfillment_failed",
      args: { p_tenant_id: TENANT_ID, p_redemption_id: REDEMPTION_ID, p_expected_version: 2, p_reason: "item damaged", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });
});
