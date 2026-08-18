import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createLoyaltyRewardDraft,
  updateLoyaltyRewardDraft,
  publishLoyaltyReward,
  pauseLoyaltyReward,
  resumeLoyaltyReward,
  archiveLoyaltyReward,
  reserveLoyaltyRewardStockUnit,
  LoyaltyRewardMutationError,
  type LoyaltyRewardMutationRpcClient,
} from "./customer-portal-loyalty-rewards.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const REWARD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyRewardMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyRewardMutationRpcClient;
  return { client, calls };
}

const REWARD_ROW = {
  id: REWARD_ID,
  tenant_id: TENANT_ID,
  program_id: PROGRAM_ID,
  reward_name: "Free Shipping Pass",
  reward_type: "discount_voucher",
  description: null,
  terms_text: null,
  min_tier_id: null,
  min_points_required: null,
  total_stock: null,
  internal_cost: null,
  vendor_ref: null,
  file_id: null,
  version_number: 1,
  status: "draft",
  effective_from: null,
  effective_to: null,
  published_by: null,
  published_at: null,
  record_version: 1,
  created_by: "staff-1",
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("createLoyaltyRewardDraft / updateLoyaltyRewardDraft", () => {
  test("createLoyaltyRewardDraft passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [REWARD_ROW], error: null });
    const result = await createLoyaltyRewardDraft(client, { tenantId: TENANT_ID, programId: PROGRAM_ID, rewardName: "Free Shipping Pass", rewardType: "discount_voucher", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.status, "draft");
    assert.deepEqual(calls[0], {
      fn: "create_loyalty_reward_draft",
      args: {
        p_tenant_id: TENANT_ID,
        p_program_id: PROGRAM_ID,
        p_reward_name: "Free Shipping Pass",
        p_reward_type: "discount_voucher",
        p_description: null,
        p_terms_text: null,
        p_min_tier_id: null,
        p_min_points_required: null,
        p_total_stock: null,
        p_internal_cost: null,
        p_vendor_ref: null,
        p_file_id: null,
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "staff-1",
      },
    });
  });

  test("createLoyaltyRewardDraft classifies draft_already_exists", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "draft_already_exists: program x reward y already has an open draft version" } });
    await assert.rejects(
      () => createLoyaltyRewardDraft(client, { tenantId: TENANT_ID, programId: PROGRAM_ID, rewardName: "x", rewardType: "discount_voucher", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (err: unknown) => err instanceof LoyaltyRewardMutationError && err.code === "draft_already_exists",
    );
  });

  test("updateLoyaltyRewardDraft passes the expected version", async () => {
    const { client, calls } = fakeRpcClient({ data: [REWARD_ROW], error: null });
    await updateLoyaltyRewardDraft(client, { tenantId: TENANT_ID, rewardId: REWARD_ID, expectedVersion: 1, rewardName: "x", rewardType: "discount_voucher", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });
});

describe("publishLoyaltyReward / pauseLoyaltyReward / resumeLoyaltyReward / archiveLoyaltyReward", () => {
  test("publishLoyaltyReward passes p_effective_from defaulted to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REWARD_ROW, status: "published" }], error: null });
    await publishLoyaltyReward(client, { tenantId: TENANT_ID, rewardId: REWARD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.deepEqual(calls[0], {
      fn: "publish_loyalty_reward",
      args: { p_tenant_id: TENANT_ID, p_reward_id: REWARD_ID, p_expected_version: 1, p_effective_from: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("pauseLoyaltyReward classifies invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: reward x is draft -- only a published reward may be paused" } });
    await assert.rejects(
      () => pauseLoyaltyReward(client, { tenantId: TENANT_ID, rewardId: REWARD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (err: unknown) => err instanceof LoyaltyRewardMutationError && err.code === "invalid_transition",
    );
  });

  test("resumeLoyaltyReward passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REWARD_ROW, status: "published" }], error: null });
    await resumeLoyaltyReward(client, { tenantId: TENANT_ID, rewardId: REWARD_ID, expectedVersion: 4, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.deepEqual(calls[0], {
      fn: "resume_loyalty_reward",
      args: { p_tenant_id: TENANT_ID, p_reward_id: REWARD_ID, p_expected_version: 4, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("archiveLoyaltyReward classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: reward x expected version 1 but found 2" } });
    await assert.rejects(
      () => archiveLoyaltyReward(client, { tenantId: TENANT_ID, rewardId: REWARD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (err: unknown) => err instanceof LoyaltyRewardMutationError && err.code === "stale_version",
    );
  });

  test("an unrecognized error message classifies as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "something_unexpected: x" } });
    await assert.rejects(
      () => publishLoyaltyReward(client, { tenantId: TENANT_ID, rewardId: REWARD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (err: unknown) => err instanceof LoyaltyRewardMutationError && err.code === "mutation_failed",
    );
  });
});

describe("reserveLoyaltyRewardStockUnit", () => {
  test("passes the exact param names, including a null reason default", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ id: RESERVATION_ID, tenant_id: TENANT_ID, reward_id: REWARD_ID, quantity: 1, reason: null, created_by: "staff-1", idempotency_key: "seed-1", created_at: "2026-08-17T00:00:00.000Z" }],
      error: null,
    });
    const result = await reserveLoyaltyRewardStockUnit(client, { tenantId: TENANT_ID, rewardId: REWARD_ID, quantity: 1, idempotencyKey: "seed-1", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.quantity, 1);
    assert.deepEqual(calls[0], {
      fn: "reserve_loyalty_reward_stock_unit",
      args: { p_tenant_id: TENANT_ID, p_reward_id: REWARD_ID, p_quantity: 1, p_idempotency_key: "seed-1", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1", p_reason: null },
    });
  });

  test("classifies insufficient_reward_stock", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_reward_stock: reward x has 1 of 1 units already reserved, cannot reserve 1 more" } });
    await assert.rejects(
      () => reserveLoyaltyRewardStockUnit(client, { tenantId: TENANT_ID, rewardId: REWARD_ID, quantity: 1, idempotencyKey: "seed-2", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (err: unknown) => err instanceof LoyaltyRewardMutationError && err.code === "insufficient_reward_stock",
    );
  });

  test("rejects a non-positive quantity at the schema layer", async () => {
    await assert.rejects(() =>
      reserveLoyaltyRewardStockUnit({ rpc: async () => ({ data: null, error: null }) } as unknown as LoyaltyRewardMutationRpcClient, {
        tenantId: TENANT_ID,
        rewardId: REWARD_ID,
        quantity: 0,
        idempotencyKey: "x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff-1",
      }),
    );
  });
});
