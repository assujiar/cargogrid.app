import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLoyaltyTierDefinition,
  parseLoyaltyAccountTierMovement,
  parseLoyaltyAccountTierHold,
  parseLoyaltyAccountTierState,
  parseLoyaltyProgramTierReadiness,
  parseCustomerPortalLoyaltyTierCard,
  describeLoyaltyTierProgress,
  LoyaltyTierUpdatedAtCursorSchema,
  LoyaltyTierCreatedAtCursorSchema,
  CreateLoyaltyTierDefinitionInputSchema,
} from "./customer-portal-loyalty-tier.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const TIER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "623e4567-e89b-12d3-a456-426614174000";
const NEXT_TIER_ID = "723e4567-e89b-12d3-a456-426614174000";
const HOLD_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("parseLoyaltyTierDefinition", () => {
  test("maps a published tier definition", () => {
    const tier = parseLoyaltyTierDefinition({
      id: TIER_ID,
      tenant_id: TENANT_ID,
      program_id: PROGRAM_ID,
      tier_name: "Gold",
      tier_rank: 3,
      threshold_dimension: "earning_amount_ytd",
      threshold_value: "1000",
      benefits: { free_shipping: true },
      review_period_days: 30,
      version_number: 2,
      status: "published",
      effective_from: "2026-08-01T00:00:00.000Z",
      effective_to: null,
      published_by: "staff-1",
      published_at: "2026-08-01T00:00:00.000Z",
      record_version: 2,
      created_by: "staff-1",
      created_at: "2026-07-30T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(tier.thresholdValue, 1000);
    assert.equal(tier.status, "published");
    assert.deepEqual(tier.benefits, { free_shipping: true });
  });

  test("maps a draft with all publish fields null", () => {
    const tier = parseLoyaltyTierDefinition({
      id: TIER_ID,
      tenant_id: TENANT_ID,
      program_id: PROGRAM_ID,
      tier_name: "Gold",
      tier_rank: 3,
      threshold_dimension: "earning_amount_ytd",
      threshold_value: 1000,
      benefits: {},
      review_period_days: 0,
      version_number: 3,
      status: "draft",
      effective_from: null,
      effective_to: null,
      published_by: null,
      published_at: null,
      record_version: 1,
      created_by: "staff-1",
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(tier.status, "draft");
    assert.equal(tier.publishedBy, null);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseLoyaltyTierDefinition({
        id: TIER_ID,
        tenant_id: TENANT_ID,
        program_id: PROGRAM_ID,
        tier_name: "Gold",
        tier_rank: 3,
        threshold_dimension: "earning_amount_ytd",
        threshold_value: 1000,
        benefits: {},
        review_period_days: 0,
        version_number: 1,
        status: "archived",
        effective_from: null,
        effective_to: null,
        published_by: null,
        published_at: null,
        record_version: 1,
        created_by: null,
        created_at: "2026-08-17T00:00:00.000Z",
        updated_at: "2026-08-17T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLoyaltyAccountTierMovement", () => {
  test("maps an upgrade movement", () => {
    const movement = parseLoyaltyAccountTierMovement({
      id: MOVEMENT_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      from_tier_id: TIER_ID,
      to_tier_id: NEXT_TIER_ID,
      movement_type: "upgrade",
      tier_definition_version_id: NEXT_TIER_ID,
      evaluation_snapshot: { computed_amount: 1200 },
      reason: "Recalculated: earning newly qualifies for a higher tier.",
      next_review_at: "2026-09-01T00:00:00.000Z",
      created_by: "staff-1",
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(movement.movementType, "upgrade");
    assert.equal(movement.toTierId, movement.tierDefinitionVersionId);
  });

  test("maps an initial movement with from_tier_id null", () => {
    const movement = parseLoyaltyAccountTierMovement({
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
    });
    assert.equal(movement.fromTierId, null);
    assert.equal(movement.movementType, "initial");
  });
});

describe("parseLoyaltyAccountTierHold", () => {
  test("maps a held row", () => {
    const hold = parseLoyaltyAccountTierHold({
      id: HOLD_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      is_held: true,
      hold_reason: "Suspected fraud on recent transactions",
      held_by: "staff-1",
      held_at: "2026-08-17T00:00:00.000Z",
      released_by: null,
      released_at: null,
      record_version: 1,
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(hold.isHeld, true);
    assert.equal(hold.releasedAt, null);
  });

  test("maps a released row", () => {
    const hold = parseLoyaltyAccountTierHold({
      id: HOLD_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      is_held: false,
      hold_reason: "Suspected fraud on recent transactions",
      held_by: "staff-1",
      held_at: "2026-08-17T00:00:00.000Z",
      released_by: "staff-2",
      released_at: "2026-08-18T00:00:00.000Z",
      record_version: 2,
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-18T00:00:00.000Z",
    });
    assert.equal(hold.isHeld, false);
    assert.equal(hold.releasedBy, "staff-2");
  });
});

describe("parseLoyaltyAccountTierState", () => {
  test("maps a state row with no movement yet (all-null current tier)", () => {
    const state = parseLoyaltyAccountTierState({
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
    });
    assert.equal(state.currentTierId, null);
    assert.equal(state.isHeld, false);
  });
});

describe("parseLoyaltyProgramTierReadiness", () => {
  test("maps a ready programme (base tier, no unsupported dimensions, no untiered accounts)", () => {
    const readiness = parseLoyaltyProgramTierReadiness({
      program_id: PROGRAM_ID,
      published_tier_count: 3,
      has_base_tier: true,
      base_tier_id: TIER_ID,
      unsupported_dimension_tier_count: 0,
      active_account_count: 2,
      untiered_active_account_count: 0,
      ready: true,
    });
    assert.equal(readiness.ready, true);
    assert.equal(readiness.baseTierId, TIER_ID);
  });

  test("maps a not-ready programme with no published base tier (base_tier_id null)", () => {
    const readiness = parseLoyaltyProgramTierReadiness({
      program_id: PROGRAM_ID,
      published_tier_count: 1,
      has_base_tier: false,
      base_tier_id: null,
      unsupported_dimension_tier_count: 0,
      active_account_count: 1,
      untiered_active_account_count: 1,
      ready: false,
    });
    assert.equal(readiness.ready, false);
    assert.equal(readiness.hasBaseTier, false);
    assert.equal(readiness.baseTierId, null);
    assert.equal(readiness.untieredActiveAccountCount, 1);
  });

  test("maps a not-ready programme that HAS a base tier but a published unsupported-dimension tier", () => {
    const readiness = parseLoyaltyProgramTierReadiness({
      program_id: PROGRAM_ID,
      published_tier_count: 1,
      has_base_tier: true,
      base_tier_id: TIER_ID,
      unsupported_dimension_tier_count: 1,
      active_account_count: 1,
      untiered_active_account_count: 1,
      ready: false,
    });
    assert.equal(readiness.hasBaseTier, true);
    assert.equal(readiness.unsupportedDimensionTierCount, 1);
    assert.equal(readiness.ready, false);
  });
});

describe("customer-facing tier card projection", () => {
  test("parseCustomerPortalLoyaltyTierCard maps a full row, never exposing internal linkage", () => {
    const card = parseCustomerPortalLoyaltyTierCard({
      loyalty_account_id: ACCOUNT_ID,
      customer_account_id: CUSTOMER_ACCOUNT_ID,
      program_id: PROGRAM_ID,
      program_name: "Freight Rewards",
      current_tier_id: TIER_ID,
      current_tier_name: "Silver",
      current_tier_rank: 2,
      benefits: { free_shipping: true },
      is_benefits_suspended: false,
      benefits_suspended_reason: null,
      computed_amount: "750.5",
      next_tier_id: NEXT_TIER_ID,
      next_tier_name: "Gold",
      next_tier_threshold: "1000",
      amount_to_next_tier: "249.5",
      next_review_at: "2026-09-01T00:00:00.000Z",
      tier_since: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(card.currentTierName, "Silver");
    assert.equal(card.amountToNextTier, 249.5);
    assert.ok(!("ruleVersionId" in card));
  });

  test("a suspended card has empty benefits and a generic customer-safe reason", () => {
    const card = parseCustomerPortalLoyaltyTierCard({
      loyalty_account_id: ACCOUNT_ID,
      customer_account_id: CUSTOMER_ACCOUNT_ID,
      program_id: PROGRAM_ID,
      program_name: "Freight Rewards",
      current_tier_id: TIER_ID,
      current_tier_name: "Silver",
      current_tier_rank: 2,
      benefits: {},
      is_benefits_suspended: true,
      benefits_suspended_reason: "Your loyalty tier benefits are temporarily on hold. Contact your account administrator or support for details.",
      computed_amount: 750,
      next_tier_id: null,
      next_tier_name: null,
      next_tier_threshold: null,
      amount_to_next_tier: null,
      next_review_at: null,
      tier_since: "2026-08-01T00:00:00.000Z",
    });
    assert.deepEqual(card.benefits, {});
    assert.match(card.benefitsSuspendedReason ?? "", /on hold/);
  });
});

describe("describeLoyaltyTierProgress", () => {
  test("renders a not-yet-evaluated message when currentTierId is null", () => {
    const text = describeLoyaltyTierProgress({
      loyaltyAccountId: ACCOUNT_ID,
      customerAccountId: CUSTOMER_ACCOUNT_ID,
      programId: PROGRAM_ID,
      programName: "Freight Rewards",
      currentTierId: null,
      currentTierName: null,
      currentTierRank: null,
      benefits: {},
      isBenefitsSuspended: false,
      benefitsSuspendedReason: null,
      computedAmount: 0,
      nextTierId: null,
      nextTierName: null,
      nextTierThreshold: null,
      amountToNextTier: null,
      nextReviewAt: null,
      tierSince: null,
    });
    assert.match(text, /not been evaluated/);
  });

  test("renders a top-tier message when nextTierId is null but currentTierId is set", () => {
    const text = describeLoyaltyTierProgress({
      loyaltyAccountId: ACCOUNT_ID,
      customerAccountId: CUSTOMER_ACCOUNT_ID,
      programId: PROGRAM_ID,
      programName: "Freight Rewards",
      currentTierId: TIER_ID,
      currentTierName: "Gold",
      currentTierRank: 3,
      benefits: {},
      isBenefitsSuspended: false,
      benefitsSuspendedReason: null,
      computedAmount: 5000,
      nextTierId: null,
      nextTierName: null,
      nextTierThreshold: null,
      amountToNextTier: null,
      nextReviewAt: null,
      tierSince: "2026-08-01T00:00:00.000Z",
    });
    assert.match(text, /Gold/);
    assert.match(text, /highest/);
  });

  test("renders a progress-toward-next-tier message", () => {
    const text = describeLoyaltyTierProgress({
      loyaltyAccountId: ACCOUNT_ID,
      customerAccountId: CUSTOMER_ACCOUNT_ID,
      programId: PROGRAM_ID,
      programName: "Freight Rewards",
      currentTierId: TIER_ID,
      currentTierName: "Silver",
      currentTierRank: 2,
      benefits: {},
      isBenefitsSuspended: false,
      benefitsSuspendedReason: null,
      computedAmount: 750,
      nextTierId: NEXT_TIER_ID,
      nextTierName: "Gold",
      nextTierThreshold: 1000,
      amountToNextTier: 250,
      nextReviewAt: null,
      tierSince: "2026-08-01T00:00:00.000Z",
    });
    assert.match(text, /250\.00/);
    assert.match(text, /Gold/);
  });
});

describe("cursor schemas", () => {
  test("LoyaltyTierUpdatedAtCursorSchema rejects a half-supplied cursor", () => {
    const result = LoyaltyTierUpdatedAtCursorSchema.safeParse({ cursorId: TIER_ID });
    assert.equal(result.success, false);
  });

  test("LoyaltyTierCreatedAtCursorSchema accepts a fully-supplied cursor", () => {
    const result = LoyaltyTierCreatedAtCursorSchema.safeParse({ cursorCreatedAt: "2026-08-17T00:00:00.000Z", cursorId: MOVEMENT_ID });
    assert.equal(result.success, true);
  });
});

describe("CreateLoyaltyTierDefinitionInputSchema", () => {
  test("rejects a non-positive tier rank", () => {
    const result = CreateLoyaltyTierDefinitionInputSchema.safeParse({
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      tierName: "Bronze",
      tierRank: 0,
      thresholdDimension: "earning_amount_ytd",
      thresholdValue: 0,
      actorAuthUserId: TENANT_ID,
      actorLabel: "staff-1",
    });
    assert.equal(result.success, false);
  });

  test("defaults benefits to {} and reviewPeriodDays to 0", () => {
    const result = CreateLoyaltyTierDefinitionInputSchema.parse({
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      tierName: "Bronze",
      tierRank: 1,
      thresholdDimension: "earning_amount_ytd",
      thresholdValue: 0,
      actorAuthUserId: TENANT_ID,
      actorLabel: "staff-1",
    });
    assert.deepEqual(result.benefits, {});
    assert.equal(result.reviewPeriodDays, 0);
  });

  test("rejects a negative threshold value", () => {
    const result = CreateLoyaltyTierDefinitionInputSchema.safeParse({
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      tierName: "Bronze",
      tierRank: 1,
      thresholdDimension: "earning_amount_ytd",
      thresholdValue: -1,
      actorAuthUserId: TENANT_ID,
      actorLabel: "staff-1",
    });
    assert.equal(result.success, false);
  });
});
