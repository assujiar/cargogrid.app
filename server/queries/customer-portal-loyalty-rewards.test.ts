import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getLoyaltyReward, listLoyaltyRewards, listCustomerPortalLoyaltyRewards, getCustomerPortalLoyaltyReward, LoyaltyRewardQueryError, type LoyaltyRewardQueryClient } from "./customer-portal-loyalty-rewards.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const REWARD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyRewardQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyRewardQueryClient;
  return { client, calls };
}

const REWARD_ROW = {
  id: REWARD_ID,
  tenant_id: TENANT_ID,
  program_id: PROGRAM_ID,
  reward_name: "Free Shipping Pass",
  reward_type: "discount_voucher",
  description: "A free shipping voucher.",
  terms_text: null,
  min_tier_id: null,
  min_points_required: null,
  total_stock: null,
  internal_cost: "5.25",
  vendor_ref: "Acme Fulfillment Co",
  file_id: null,
  version_number: 1,
  status: "published",
  effective_from: "2026-08-01T00:00:00.000Z",
  effective_to: null,
  published_by: "staff-1",
  published_at: "2026-08-01T00:00:00.000Z",
  record_version: 1,
  created_by: "staff-1",
  created_at: "2026-07-30T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

describe("getLoyaltyReward / listLoyaltyRewards", () => {
  test("getLoyaltyReward passes the exact param names and returns internal_cost/vendor_ref", async () => {
    const { client, calls } = fakeRpcClient({ data: [REWARD_ROW], error: null });
    const result = await getLoyaltyReward(client, TENANT_ID, REWARD_ID, ACTOR_ID);
    assert.equal(result.rewardName, "Free Shipping Pass");
    assert.equal(result.internalCost, 5.25);
    assert.deepEqual(calls[0], { fn: "get_loyalty_reward", args: { p_tenant_id: TENANT_ID, p_reward_id: REWARD_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("getLoyaltyReward propagates loyalty_reward_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_reward_not_found: x" } });
    await assert.rejects(
      () => getLoyaltyReward(client, TENANT_ID, REWARD_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyRewardQueryError && err.code === "loyalty_reward_not_found",
    );
  });

  test("listLoyaltyRewards defaults filters to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [REWARD_ROW], error: null });
    await listLoyaltyRewards(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_program_id: null,
      p_status: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("listLoyaltyRewards returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listLoyaltyRewards(client, TENANT_ID, ACTOR_ID, { programId: PROGRAM_ID });
    assert.deepEqual(result, []);
  });
});

describe("listCustomerPortalLoyaltyRewards", () => {
  test("passes p_loyalty_account_id as a required, non-optional argument", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalLoyaltyRewards(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.deepEqual(calls[0], {
      fn: "list_customer_portal_loyalty_rewards",
      args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 },
    });
  });

  test("returns an empty array (deny-by-default) when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalLoyaltyRewards(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });

  test("maps a locked reward row, never exposing internal_cost/vendor_ref", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          reward_id: REWARD_ID,
          program_id: PROGRAM_ID,
          program_name: "Freight Rewards",
          reward_name: "Gold Tier Exclusive",
          reward_type: "physical_item",
          description: "Gold members only.",
          display_state: "locked",
          min_tier_name: "Gold",
          min_points_required: null,
          customer_current_points: 0,
          total_stock: null,
          stock_available: null,
          effective_from: "2026-08-01T00:00:00.000Z",
          updated_at: "2026-08-01T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await listCustomerPortalLoyaltyRewards(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.equal(result[0]?.displayState, "locked");
    assert.ok(!("internal_cost" in (result[0] as object)));
    assert.ok(!("vendor_ref" in (result[0] as object)));
  });
});

describe("getCustomerPortalLoyaltyReward", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          reward_id: REWARD_ID,
          program_id: PROGRAM_ID,
          program_name: "Freight Rewards",
          reward_name: "Free Shipping Pass",
          reward_type: "discount_voucher",
          description: null,
          terms_text: null,
          display_state: "eligible",
          min_tier_name: null,
          min_points_required: null,
          customer_current_points: 0,
          total_stock: null,
          stock_available: null,
          effective_from: "2026-08-01T00:00:00.000Z",
          has_terms_file: false,
          terms_file_scan_status: null,
          terms_file_name: null,
          terms_file_mime_type: null,
          terms_file_size_bytes: null,
          updated_at: "2026-08-01T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await getCustomerPortalLoyaltyReward(client, TENANT_ID, REWARD_ID, ACCOUNT_ID, ACTOR_ID);
    assert.equal(result.hasTermsFile, false);
    assert.deepEqual(calls[0], {
      fn: "get_customer_portal_loyalty_reward",
      args: { p_tenant_id: TENANT_ID, p_reward_id: REWARD_ID, p_loyalty_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID },
    });
  });

  test("propagates loyalty_reward_not_found with .code set (anti-enumeration)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_reward_not_found: x" } });
    await assert.rejects(
      () => getCustomerPortalLoyaltyReward(client, TENANT_ID, REWARD_ID, ACCOUNT_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyRewardQueryError && err.code === "loyalty_reward_not_found",
    );
  });
});
