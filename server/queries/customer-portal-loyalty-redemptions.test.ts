import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getLoyaltyRedemption, listLoyaltyRedemptions, listCustomerPortalLoyaltyRedemptions, getCustomerPortalLoyaltyRedemption, LoyaltyRedemptionQueryError, type LoyaltyRedemptionQueryClient } from "./customer-portal-loyalty-redemptions.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REWARD_ID = "323e4567-e89b-12d3-a456-426614174000";
const REDEMPTION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyRedemptionQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyRedemptionQueryClient;
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

describe("getLoyaltyRedemption / listLoyaltyRedemptions", () => {
  test("getLoyaltyRedemption passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [REDEMPTION_ROW], error: null });
    const result = await getLoyaltyRedemption(client, TENANT_ID, REDEMPTION_ID, ACTOR_ID);
    assert.equal(result.rewardName, "Physical Reward");
    assert.deepEqual(calls[0], { fn: "get_loyalty_redemption", args: { p_tenant_id: TENANT_ID, p_redemption_id: REDEMPTION_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("getLoyaltyRedemption propagates loyalty_redemption_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_redemption_not_found: x" } });
    await assert.rejects(
      () => getLoyaltyRedemption(client, TENANT_ID, REDEMPTION_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyRedemptionQueryError && err.code === "loyalty_redemption_not_found",
    );
  });

  test("listLoyaltyRedemptions defaults filters to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [REDEMPTION_ROW], error: null });
    await listLoyaltyRedemptions(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_status: null,
      p_loyalty_account_id: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("listLoyaltyRedemptions returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listLoyaltyRedemptions(client, TENANT_ID, ACTOR_ID, { status: "pending_approval" });
    assert.deepEqual(result, []);
  });
});

describe("listCustomerPortalLoyaltyRedemptions", () => {
  test("p_loyalty_account_id is optional (whole-scope shape, unlike the reward catalogue list)", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalLoyaltyRedemptions(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0], {
      fn: "list_customer_portal_loyalty_redemptions",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_loyalty_account_id: null, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 },
    });
  });

  test("returns an empty array (deny-by-default) when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalLoyaltyRedemptions(client, TENANT_ID, ACTOR_ID, { loyaltyAccountId: ACCOUNT_ID });
    assert.deepEqual(result, []);
  });

  test("maps a fulfilled row, never exposing idempotency_key/created_by/stock_reservation_id", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          redemption_id: REDEMPTION_ID,
          loyalty_account_id: ACCOUNT_ID,
          reward_id: REWARD_ID,
          reward_name: "Voucher Reward",
          reward_type: "discount_voucher",
          points_consumed: "100",
          benefit_entitlement_id: "623e4567-e89b-12d3-a456-426614174000",
          status: "fulfilled",
          fulfillment_status: "not_applicable",
          decision_reason: "auto-approved",
          decided_at: "2026-08-17T00:05:00.000Z",
          record_version: 2,
          created_at: "2026-08-17T00:00:00.000Z",
          updated_at: "2026-08-17T00:05:00.000Z",
        },
      ],
      error: null,
    });
    const result = await listCustomerPortalLoyaltyRedemptions(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.status, "fulfilled");
    assert.ok(!("idempotency_key" in (result[0] as object)));
    assert.ok(!("stock_reservation_id" in (result[0] as object)));
  });
});

describe("getCustomerPortalLoyaltyRedemption", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          redemption_id: REDEMPTION_ID,
          loyalty_account_id: ACCOUNT_ID,
          reward_id: REWARD_ID,
          reward_name: "Physical Reward",
          reward_type: "physical_item",
          points_consumed: "50",
          benefit_entitlement_id: null,
          status: "pending_approval",
          fulfillment_status: "pending",
          decision_reason: null,
          decided_at: null,
          record_version: 1,
          created_at: "2026-08-17T00:00:00.000Z",
          updated_at: "2026-08-17T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await getCustomerPortalLoyaltyRedemption(client, TENANT_ID, REDEMPTION_ID, ACTOR_ID);
    assert.equal(result.status, "pending_approval");
    assert.deepEqual(calls[0], {
      fn: "get_customer_portal_loyalty_redemption",
      args: { p_tenant_id: TENANT_ID, p_redemption_id: REDEMPTION_ID, p_actor_auth_user_id: ACTOR_ID },
    });
  });

  test("propagates loyalty_redemption_not_found with .code set (anti-enumeration)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_redemption_not_found: x" } });
    await assert.rejects(
      () => getCustomerPortalLoyaltyRedemption(client, TENANT_ID, REDEMPTION_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyRedemptionQueryError && err.code === "loyalty_redemption_not_found",
    );
  });
});
