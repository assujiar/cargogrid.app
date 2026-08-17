import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getLoyaltyTierDefinition,
  listLoyaltyTierDefinitions,
  getLoyaltyAccountTierState,
  listLoyaltyAccountTierMovements,
  listCustomerPortalLoyaltyTierCards,
  LoyaltyTierQueryError,
  type LoyaltyTierQueryClient,
} from "./customer-portal-loyalty-tier.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const TIER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "623e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyTierQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyTierQueryClient;
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

describe("getLoyaltyTierDefinition / listLoyaltyTierDefinitions", () => {
  test("getLoyaltyTierDefinition passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [TIER_ROW], error: null });
    const result = await getLoyaltyTierDefinition(client, TENANT_ID, TIER_ID, ACTOR_ID);
    assert.equal(result.tierName, "Gold");
    assert.deepEqual(calls[0], { fn: "get_loyalty_tier_definition", args: { p_tenant_id: TENANT_ID, p_tier_definition_id: TIER_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("getLoyaltyTierDefinition propagates loyalty_tier_definition_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_tier_definition_not_found: x" } });
    await assert.rejects(
      () => getLoyaltyTierDefinition(client, TENANT_ID, TIER_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyTierQueryError && err.code === "loyalty_tier_definition_not_found",
    );
  });

  test("listLoyaltyTierDefinitions defaults filters to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [TIER_ROW], error: null });
    await listLoyaltyTierDefinitions(client, TENANT_ID, PROGRAM_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_program_id: PROGRAM_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_status: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("listLoyaltyTierDefinitions returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listLoyaltyTierDefinitions(client, TENANT_ID, PROGRAM_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});

describe("getLoyaltyAccountTierState", () => {
  test("passes the exact param names and parses a no-movement-yet row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          loyalty_account_id: ACCOUNT_ID,
          current_tier_id: null,
          current_tier_name: null,
          current_tier_rank: null,
          movement_type: null,
          next_review_at: null,
          tier_since: null,
          is_held: false,
          hold_reason: null,
          held_by: null,
          held_at: null,
        },
      ],
      error: null,
    });
    const result = await getLoyaltyAccountTierState(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.equal(result.currentTierId, null);
    assert.deepEqual(calls[0], { fn: "get_loyalty_account_tier_state", args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("propagates loyalty_account_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_account_not_found: x" } });
    await assert.rejects(
      () => getLoyaltyAccountTierState(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyTierQueryError && err.code === "loyalty_account_not_found",
    );
  });
});

describe("listLoyaltyAccountTierMovements", () => {
  test("defaults filters to null and limit to 50, keyed on created_at", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listLoyaltyAccountTierMovements(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_loyalty_account_id: null,
      p_cursor_created_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("maps a returned movement row", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          id: MOVEMENT_ID,
          tenant_id: TENANT_ID,
          loyalty_account_id: ACCOUNT_ID,
          from_tier_id: null,
          to_tier_id: TIER_ID,
          movement_type: "initial",
          tier_definition_version_id: TIER_ID,
          evaluation_snapshot: {},
          reason: "Initial tier assignment.",
          next_review_at: "2026-08-17T00:00:00.000Z",
          created_by: "staff-1",
          created_at: "2026-08-17T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await listLoyaltyAccountTierMovements(client, TENANT_ID, ACTOR_ID, { loyaltyAccountId: ACCOUNT_ID });
    assert.equal(result.length, 1);
    assert.equal(result[0]?.movementType, "initial");
  });
});

describe("listCustomerPortalLoyaltyTierCards", () => {
  test("defaults customerAccountId to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalLoyaltyTierCards(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_customer_account_id: null, p_limit: 50 });
  });

  test("returns an empty array (deny-by-default) when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalLoyaltyTierCards(client, TENANT_ID, ACTOR_ID, { customerAccountId: CUSTOMER_ACCOUNT_ID });
    assert.deepEqual(result, []);
  });

  test("maps a full tier card row", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          loyalty_account_id: ACCOUNT_ID,
          customer_account_id: CUSTOMER_ACCOUNT_ID,
          program_id: PROGRAM_ID,
          program_name: "Freight Rewards",
          current_tier_id: TIER_ID,
          current_tier_name: "Gold",
          current_tier_rank: 3,
          benefits: { free_shipping: true },
          is_benefits_suspended: false,
          benefits_suspended_reason: null,
          computed_amount: "1500",
          next_tier_id: null,
          next_tier_name: null,
          next_tier_threshold: null,
          amount_to_next_tier: null,
          next_review_at: "2026-09-17T00:00:00.000Z",
          tier_since: "2026-08-01T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await listCustomerPortalLoyaltyTierCards(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.currentTierName, "Gold");
    assert.equal(result[0]?.computedAmount, 1500);
  });
});
