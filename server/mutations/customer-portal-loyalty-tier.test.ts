import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createLoyaltyTierDefinition,
  updateLoyaltyTierDefinitionDraft,
  publishLoyaltyTierDefinition,
  recalculateCustomerLoyaltyTier,
  holdLoyaltyAccountTierBenefits,
  releaseLoyaltyAccountTierBenefits,
  LoyaltyTierMutationError,
  type LoyaltyTierMutationRpcClient,
} from "./customer-portal-loyalty-tier.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const TIER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "623e4567-e89b-12d3-a456-426614174000";
const HOLD_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyTierMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyTierMutationRpcClient;
  return { client, calls };
}

const TIER_ROW = {
  id: TIER_ID,
  tenant_id: TENANT_ID,
  program_id: PROGRAM_ID,
  tier_name: "Gold",
  tier_rank: 3,
  threshold_dimension: "earning_amount_ytd",
  threshold_value: 1000,
  benefits: {},
  review_period_days: 30,
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

const MOVEMENT_ROW = {
  id: MOVEMENT_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  from_tier_id: null,
  to_tier_id: TIER_ID,
  movement_type: "initial",
  tier_definition_version_id: TIER_ID,
  evaluation_snapshot: { computed_amount: 1200 },
  reason: "Initial tier assignment.",
  next_review_at: "2026-09-16T00:00:00.000Z",
  created_by: "staff-1",
  created_at: "2026-08-17T00:00:00.000Z",
};

const HOLD_ROW = {
  id: HOLD_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  is_held: true,
  hold_reason: "Suspected fraud",
  held_by: "staff-1",
  held_at: "2026-08-17T00:00:00.000Z",
  released_by: null,
  released_at: null,
  record_version: 1,
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("createLoyaltyTierDefinition", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [TIER_ROW], error: null });
    const result = await createLoyaltyTierDefinition(client, {
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      tierName: "Gold",
      tierRank: 3,
      thresholdDimension: "earning_amount_ytd",
      thresholdValue: 1000,
      benefits: {},
      reviewPeriodDays: 30,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff-1",
    });
    assert.equal(result.tierName, "Gold");
    assert.deepEqual(calls[0], {
      fn: "create_loyalty_tier_definition",
      args: {
        p_tenant_id: TENANT_ID,
        p_program_id: PROGRAM_ID,
        p_tier_name: "Gold",
        p_tier_rank: 3,
        p_threshold_dimension: "earning_amount_ytd",
        p_threshold_value: 1000,
        p_benefits: {},
        p_review_period_days: 30,
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "staff-1",
      },
    });
  });

  test("propagates draft_already_exists with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "draft_already_exists: x" } });
    await assert.rejects(
      () =>
        createLoyaltyTierDefinition(client, {
          tenantId: TENANT_ID,
          programId: PROGRAM_ID,
          tierName: "Gold",
          tierRank: 3,
          thresholdDimension: "earning_amount_ytd",
          thresholdValue: 1000,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff-1",
        }),
      (err: unknown) => err instanceof LoyaltyTierMutationError && err.code === "draft_already_exists",
    );
  });

  test("an unrecognized RPC error message classifies as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unrelated_db_error: x" } });
    await assert.rejects(
      () =>
        createLoyaltyTierDefinition(client, {
          tenantId: TENANT_ID,
          programId: PROGRAM_ID,
          tierName: "Gold",
          tierRank: 3,
          thresholdDimension: "earning_amount_ytd",
          thresholdValue: 1000,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff-1",
        }),
      (err: unknown) => err instanceof LoyaltyTierMutationError && err.code === "mutation_failed",
    );
  });
});

describe("updateLoyaltyTierDefinitionDraft / publishLoyaltyTierDefinition", () => {
  test("updateLoyaltyTierDefinitionDraft passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [TIER_ROW], error: null });
    await updateLoyaltyTierDefinitionDraft(client, {
      tenantId: TENANT_ID,
      tierDefinitionId: TIER_ID,
      expectedVersion: 1,
      tierName: "Gold",
      tierRank: 3,
      thresholdDimension: "earning_amount_ytd",
      thresholdValue: 1200,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff-1",
    });
    assert.equal(calls[0]?.fn, "update_loyalty_tier_definition_draft");
    assert.equal((calls[0]?.args as Record<string, unknown>).p_threshold_value, 1200);
  });

  test("publishLoyaltyTierDefinition passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TIER_ROW, status: "published", published_by: "staff-1", published_at: "2026-08-17T00:00:00.000Z", effective_from: "2026-08-17T00:00:00.000Z" }], error: null });
    const result = await publishLoyaltyTierDefinition(client, { tenantId: TENANT_ID, tierDefinitionId: TIER_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.status, "published");
    assert.deepEqual(calls[0], {
      fn: "publish_loyalty_tier_definition",
      args: { p_tenant_id: TENANT_ID, p_tier_definition_id: TIER_ID, p_expected_version: 1, p_effective_from: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("publishLoyaltyTierDefinition propagates tier_rank_conflict with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "tier_rank_conflict: x" } });
    await assert.rejects(
      () => publishLoyaltyTierDefinition(client, { tenantId: TENANT_ID, tierDefinitionId: TIER_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (err: unknown) => err instanceof LoyaltyTierMutationError && err.code === "tier_rank_conflict",
    );
  });
});

describe("recalculateCustomerLoyaltyTier", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [MOVEMENT_ROW], error: null });
    const result = await recalculateCustomerLoyaltyTier(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.movementType, "initial");
    assert.deepEqual(calls[0], {
      fn: "recalculate_customer_loyalty_tier",
      args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("propagates no_eligible_tier_definition with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "no_eligible_tier_definition: x" } });
    await assert.rejects(
      () => recalculateCustomerLoyaltyTier(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (err: unknown) => err instanceof LoyaltyTierMutationError && err.code === "no_eligible_tier_definition",
    );
  });

  test("propagates unsupported_threshold_dimension with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "unsupported_threshold_dimension: x" } });
    await assert.rejects(
      () => recalculateCustomerLoyaltyTier(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }),
      (err: unknown) => err instanceof LoyaltyTierMutationError && err.code === "unsupported_threshold_dimension",
    );
  });
});

describe("holdLoyaltyAccountTierBenefits / releaseLoyaltyAccountTierBenefits", () => {
  test("holdLoyaltyAccountTierBenefits passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [HOLD_ROW], error: null });
    const result = await holdLoyaltyAccountTierBenefits(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, reason: "Suspected fraud", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" });
    assert.equal(result.isHeld, true);
    assert.deepEqual(calls[0], {
      fn: "hold_loyalty_account_tier_benefits",
      args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_reason: "Suspected fraud", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-1" },
    });
  });

  test("holdLoyaltyAccountTierBenefits rejects an empty reason before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: [HOLD_ROW], error: null });
    await assert.rejects(() => holdLoyaltyAccountTierBenefits(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "staff-1" }));
    assert.equal(calls.length, 0);
  });

  test("releaseLoyaltyAccountTierBenefits passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...HOLD_ROW, is_held: false, released_by: "staff-2", released_at: "2026-08-18T00:00:00.000Z" }], error: null });
    const result = await releaseLoyaltyAccountTierBenefits(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-2" });
    assert.equal(result.isHeld, false);
    assert.deepEqual(calls[0], {
      fn: "release_loyalty_account_tier_benefits",
      args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff-2" },
    });
  });

  test("releaseLoyaltyAccountTierBenefits propagates loyalty_account_tier_hold_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_account_tier_hold_not_found: x" } });
    await assert.rejects(
      () => releaseLoyaltyAccountTierBenefits(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff-2" }),
      (err: unknown) => err instanceof LoyaltyTierMutationError && err.code === "loyalty_account_tier_hold_not_found",
    );
  });
});
