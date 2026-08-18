import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLoyaltyReward,
  parseLoyaltyRewardStockReservation,
  parseCustomerPortalLoyaltyReward,
  parseCustomerPortalLoyaltyRewardDetail,
  describeLoyaltyRewardEligibility,
  LoyaltyRewardUpdatedAtCursorSchema,
  CreateLoyaltyRewardDraftInputSchema,
} from "./customer-portal-loyalty-rewards.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const REWARD_ID = "323e4567-e89b-12d3-a456-426614174000";
const TIER_ID = "423e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseLoyaltyReward", () => {
  test("maps a published reward including internal_cost/vendor_ref", () => {
    const reward = parseLoyaltyReward({
      id: REWARD_ID,
      tenant_id: TENANT_ID,
      program_id: PROGRAM_ID,
      reward_name: "Free Shipping Pass",
      reward_type: "discount_voucher",
      description: "A free shipping voucher.",
      terms_text: "One use only.",
      min_tier_id: TIER_ID,
      min_points_required: "200",
      total_stock: 10,
      internal_cost: "5.25",
      vendor_ref: "Acme Fulfillment Co",
      file_id: FILE_ID,
      version_number: 1,
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
    assert.equal(reward.status, "published");
    assert.equal(reward.minPointsRequired, 200);
    assert.equal(reward.internalCost, 5.25);
    assert.equal(reward.vendorRef, "Acme Fulfillment Co");
  });

  test("maps a draft with all publish fields null and no eligibility gates", () => {
    const reward = parseLoyaltyReward({
      id: REWARD_ID,
      tenant_id: TENANT_ID,
      program_id: PROGRAM_ID,
      reward_name: "Welcome Gift",
      reward_type: "physical_item",
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
    });
    assert.equal(reward.status, "draft");
    assert.equal(reward.minTierId, null);
    assert.equal(reward.totalStock, null);
  });

  test("rejects an unrecognized reward_type", () => {
    assert.throws(() =>
      parseLoyaltyReward({
        id: REWARD_ID,
        tenant_id: TENANT_ID,
        program_id: PROGRAM_ID,
        reward_name: "x",
        reward_type: "store_credit",
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
        created_by: null,
        created_at: "2026-08-17T00:00:00.000Z",
        updated_at: "2026-08-17T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLoyaltyRewardStockReservation", () => {
  test("maps a reservation row", () => {
    const reservation = parseLoyaltyRewardStockReservation({
      id: RESERVATION_ID,
      tenant_id: TENANT_ID,
      reward_id: REWARD_ID,
      quantity: 1,
      reason: null,
      created_by: "staff-1",
      idempotency_key: "reserve-1",
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(reservation.quantity, 1);
    assert.equal(reservation.rewardId, REWARD_ID);
  });
});

describe("customer-facing catalogue projection", () => {
  test("parseCustomerPortalLoyaltyReward maps an eligible row, never exposing internal_cost/vendor_ref", () => {
    const reward = parseCustomerPortalLoyaltyReward({
      reward_id: REWARD_ID,
      program_id: PROGRAM_ID,
      program_name: "Freight Rewards",
      reward_name: "Free Shipping Pass",
      reward_type: "discount_voucher",
      description: "A free shipping voucher.",
      display_state: "eligible",
      min_tier_name: "Silver",
      min_points_required: "200",
      customer_current_points: "500",
      total_stock: 10,
      stock_available: 9,
      effective_from: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(reward.displayState, "eligible");
    assert.equal(reward.stockAvailable, 9);
    assert.ok(!("internal_cost" in reward));
    assert.ok(!("internalCost" in reward));
    assert.ok(!("vendor_ref" in reward));
    assert.ok(!("vendorRef" in reward));
  });

  test("a locked reward still carries its own eligibility requirements", () => {
    const reward = parseCustomerPortalLoyaltyReward({
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
    });
    assert.equal(reward.displayState, "locked");
    assert.equal(reward.minTierName, "Gold");
  });

  test("parseCustomerPortalLoyaltyRewardDetail maps a clean-file detail row", () => {
    const detail = parseCustomerPortalLoyaltyRewardDetail({
      reward_id: REWARD_ID,
      program_id: PROGRAM_ID,
      program_name: "Freight Rewards",
      reward_name: "Free Shipping Pass",
      reward_type: "discount_voucher",
      description: "A free shipping voucher.",
      terms_text: "One use only.",
      display_state: "eligible",
      min_tier_name: null,
      min_points_required: null,
      customer_current_points: 0,
      total_stock: null,
      stock_available: null,
      effective_from: "2026-08-01T00:00:00.000Z",
      has_terms_file: true,
      terms_file_scan_status: "clean",
      terms_file_name: "terms.pdf",
      terms_file_mime_type: "application/pdf",
      terms_file_size_bytes: 20480,
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(detail.hasTermsFile, true);
    assert.equal(detail.termsFileScanStatus, "clean");
    assert.equal(detail.termsFileName, "terms.pdf");
  });

  test("parseCustomerPortalLoyaltyRewardDetail maps a still-pending file with no metadata", () => {
    const detail = parseCustomerPortalLoyaltyRewardDetail({
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
      has_terms_file: true,
      terms_file_scan_status: "pending",
      terms_file_name: null,
      terms_file_mime_type: null,
      terms_file_size_bytes: null,
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(detail.termsFileScanStatus, "pending");
    assert.equal(detail.termsFileName, null);
  });
});

describe("describeLoyaltyRewardEligibility", () => {
  test("renders an eligible message", () => {
    const text = describeLoyaltyRewardEligibility({ displayState: "eligible", minTierName: null, minPointsRequired: null, customerCurrentPoints: 0 });
    assert.match(text, /can redeem/);
  });

  test("renders a locked message naming both gates", () => {
    const text = describeLoyaltyRewardEligibility({ displayState: "locked", minTierName: "Gold", minPointsRequired: 200, customerCurrentPoints: 50 });
    assert.match(text, /Gold/);
    assert.match(text, /200/);
    assert.match(text, /50/);
  });

  test("renders an out_of_stock message", () => {
    const text = describeLoyaltyRewardEligibility({ displayState: "out_of_stock", minTierName: null, minPointsRequired: null, customerCurrentPoints: 0 });
    assert.match(text, /out of stock/);
  });

  test("renders an unavailable message for a paused reward", () => {
    const text = describeLoyaltyRewardEligibility({ displayState: "unavailable", minTierName: null, minPointsRequired: null, customerCurrentPoints: 0 });
    assert.match(text, /temporarily unavailable/);
  });
});

describe("cursor schema", () => {
  test("LoyaltyRewardUpdatedAtCursorSchema rejects a half-supplied cursor", () => {
    const result = LoyaltyRewardUpdatedAtCursorSchema.safeParse({ cursorId: REWARD_ID });
    assert.equal(result.success, false);
  });

  test("LoyaltyRewardUpdatedAtCursorSchema accepts a fully-supplied cursor", () => {
    const result = LoyaltyRewardUpdatedAtCursorSchema.safeParse({ cursorUpdatedAt: "2026-08-17T00:00:00.000Z", cursorId: REWARD_ID });
    assert.equal(result.success, true);
  });
});

describe("CreateLoyaltyRewardDraftInputSchema", () => {
  test("rejects an empty reward name", () => {
    const result = CreateLoyaltyRewardDraftInputSchema.safeParse({
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      rewardName: "",
      rewardType: "discount_voucher",
      actorAuthUserId: TENANT_ID,
      actorLabel: "staff-1",
    });
    assert.equal(result.success, false);
  });

  test("rejects a negative min_points_required", () => {
    const result = CreateLoyaltyRewardDraftInputSchema.safeParse({
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      rewardName: "x",
      rewardType: "discount_voucher",
      minPointsRequired: -1,
      actorAuthUserId: TENANT_ID,
      actorLabel: "staff-1",
    });
    assert.equal(result.success, false);
  });

  test("defaults optional fields to null", () => {
    const result = CreateLoyaltyRewardDraftInputSchema.parse({
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      rewardName: "x",
      rewardType: "discount_voucher",
      actorAuthUserId: TENANT_ID,
      actorLabel: "staff-1",
    });
    assert.equal(result.minTierId, null);
    assert.equal(result.totalStock, null);
    assert.equal(result.internalCost, null);
  });
});
