import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLoyaltyLiabilityReconciliationRun,
  parseLoyaltyLiabilityReconciliationException,
  parseLoyaltyEngagementMetrics,
  parseCustomerPortalLoyaltySummary,
  describeLoyaltyLiabilityReconciliationRunStatus,
  ExecuteLoyaltyLiabilityReconciliationRunInputSchema,
  ResolveLoyaltyLiabilityReconciliationExceptionInputSchema,
  CertifyLoyaltyLiabilityReconciliationRunInputSchema,
  GetLoyaltyEngagementMetricsInputSchema,
  LoyaltyLiabilityUpdatedAtCursorSchema,
} from "./customer-portal-loyalty-liability.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "223e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseLoyaltyLiabilityReconciliationRun", () => {
  test("maps a certified run, points total kept as a raw units number never blended with currency lines", () => {
    const run = parseLoyaltyLiabilityReconciliationRun({
      id: RUN_ID,
      tenant_id: TENANT_ID,
      as_of: "2026-08-18T00:00:00.000Z",
      currency: "USD",
      status: "certified",
      points_liability_total: 600,
      cashback_liability_total: 30,
      discount_liability_total: 15,
      voucher_liability_total: 40,
      reward_fulfillment_liability_total: 75,
      computed_at: "2026-08-18T00:00:00.000Z",
      config_version: 1,
      idempotency_key: "lra-mismatch-run",
      executed_by: "manager1",
      certified_by: "manager1",
      certified_at: "2026-08-18T00:05:00.000Z",
      record_version: 4,
      created_at: "2026-08-18T00:00:00.000Z",
      updated_at: "2026-08-18T00:05:00.000Z",
    });
    assert.equal(run.status, "certified");
    assert.equal(run.pointsLiabilityTotal, 600);
    assert.equal(run.cashbackLiabilityTotal, 30);
    assert.equal(run.certifiedBy, "manager1");
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseLoyaltyLiabilityReconciliationRun({
        id: RUN_ID,
        tenant_id: TENANT_ID,
        as_of: "2026-08-18T00:00:00.000Z",
        currency: "USD",
        status: "made_up_status",
        points_liability_total: 0,
        cashback_liability_total: 0,
        discount_liability_total: 0,
        voucher_liability_total: 0,
        reward_fulfillment_liability_total: 0,
        computed_at: "2026-08-18T00:00:00.000Z",
        config_version: 1,
        idempotency_key: "x",
        executed_by: null,
        certified_by: null,
        certified_at: null,
        record_version: 1,
        created_at: "2026-08-18T00:00:00.000Z",
        updated_at: "2026-08-18T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLoyaltyLiabilityReconciliationException", () => {
  test("maps an open point-balance mismatch, detail carries expected/actual", () => {
    const exception = parseLoyaltyLiabilityReconciliationException({
      id: EXCEPTION_ID,
      tenant_id: TENANT_ID,
      run_id: RUN_ID,
      exception_type: "point_balance_derivation_mismatch",
      detail: { loyaltyAccountId: ACCOUNT_ID, expectedAvailable: 200, actualAvailable: 700 },
      status: "open",
      resolved_by: null,
      resolution_reason: null,
      resolved_at: null,
      record_version: 1,
      created_at: "2026-08-18T00:00:00.000Z",
      updated_at: "2026-08-18T00:00:00.000Z",
    });
    assert.equal(exception.exceptionType, "point_balance_derivation_mismatch");
    assert.equal(exception.detail.expectedAvailable, 200);
    assert.equal(exception.detail.actualAvailable, 700);
  });

  // Tier C review fix (Batch 5 close): redemption_liability_status_mismatch
  // -- the reward-fulfillment liability line's own status re-derivation.
  test("maps an open redemption-liability-status mismatch, detail carries expected/actual/latestEventType", () => {
    const exception = parseLoyaltyLiabilityReconciliationException({
      id: EXCEPTION_ID,
      tenant_id: TENANT_ID,
      run_id: RUN_ID,
      exception_type: "redemption_liability_status_mismatch",
      detail: { redemptionId: ACCOUNT_ID, expectedStatus: "fulfilling", actualStatus: "fulfilled", latestEventType: "approved" },
      status: "open",
      resolved_by: null,
      resolution_reason: null,
      resolved_at: null,
      record_version: 1,
      created_at: "2026-08-18T00:00:00.000Z",
      updated_at: "2026-08-18T00:00:00.000Z",
    });
    assert.equal(exception.exceptionType, "redemption_liability_status_mismatch");
    assert.equal(exception.detail.expectedStatus, "fulfilling");
    assert.equal(exception.detail.actualStatus, "fulfilled");
  });

  test("rejects an unrecognized exception_type", () => {
    assert.throws(() =>
      parseLoyaltyLiabilityReconciliationException({
        id: EXCEPTION_ID,
        tenant_id: TENANT_ID,
        run_id: RUN_ID,
        exception_type: "made_up_type",
        detail: {},
        status: "open",
        resolved_by: null,
        resolution_reason: null,
        resolved_at: null,
        record_version: 1,
        created_at: "2026-08-18T00:00:00.000Z",
        updated_at: "2026-08-18T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLoyaltyEngagementMetrics", () => {
  test("maps an aggregate metrics row, structurally no per-customer/internal-cost field to even attempt parsing", () => {
    const metrics = parseLoyaltyEngagementMetrics({
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
    });
    assert.equal(metrics.activeLoyaltyAccountsCount, 4);
    assert.equal(metrics.redemptionRate, 0.25);
    assert.deepEqual(Object.keys(metrics).some((k) => /customer|internalCost|vendorRef/i.test(k)), false);
  });
});

describe("parseCustomerPortalLoyaltySummary", () => {
  test("maps a consolidated summary row, entitlements grouped by (benefitType, currency) never blended", () => {
    const summary = parseCustomerPortalLoyaltySummary({
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
    });
    assert.equal(summary.pointsAvailable, 150);
    assert.equal(summary.activeEntitlementsSummary.length, 1);
    assert.equal(summary.activeEntitlementsSummary[0]?.benefitType, "voucher");
    assert.equal(summary.recentRedemptions.length, 0);
  });
});

describe("input schemas", () => {
  test("ExecuteLoyaltyLiabilityReconciliationRunInputSchema requires tenantId/currency/actor, defaults the rest", () => {
    const parsed = ExecuteLoyaltyLiabilityReconciliationRunInputSchema.parse({
      tenantId: TENANT_ID,
      currency: "USD",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager1",
    });
    assert.equal(parsed.asOf, null);
    assert.equal(parsed.idempotencyKey, null);
    assert.equal(parsed.configVersion, null);
  });

  test("ResolveLoyaltyLiabilityReconciliationExceptionInputSchema rejects an empty resolutionReason", () => {
    assert.throws(() =>
      ResolveLoyaltyLiabilityReconciliationExceptionInputSchema.parse({
        tenantId: TENANT_ID,
        exceptionId: EXCEPTION_ID,
        expectedVersion: 1,
        resolutionReason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager1",
      }),
    );
  });

  test("CertifyLoyaltyLiabilityReconciliationRunInputSchema requires a positive expectedVersion", () => {
    assert.throws(() =>
      CertifyLoyaltyLiabilityReconciliationRunInputSchema.parse({
        tenantId: TENANT_ID,
        runId: RUN_ID,
        expectedVersion: 0,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager1",
      }),
    );
  });

  test("GetLoyaltyEngagementMetricsInputSchema requires a non-empty periodStart, periodEnd defaults null", () => {
    const parsed = GetLoyaltyEngagementMetricsInputSchema.parse({
      tenantId: TENANT_ID,
      periodStart: "2026-01-01T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
    });
    assert.equal(parsed.periodEnd, null);
  });

  test("LoyaltyLiabilityUpdatedAtCursorSchema rejects a cursorId without cursorUpdatedAt", () => {
    assert.throws(() => LoyaltyLiabilityUpdatedAtCursorSchema.parse({ cursorId: RUN_ID }));
  });
});

describe("describeLoyaltyLiabilityReconciliationRunStatus", () => {
  test("renders customer-safe, plain-language labels for every status", () => {
    assert.equal(describeLoyaltyLiabilityReconciliationRunStatus("open"), "Ready to certify");
    assert.equal(describeLoyaltyLiabilityReconciliationRunStatus("exceptions_pending"), "Exceptions pending");
    assert.equal(describeLoyaltyLiabilityReconciliationRunStatus("certified"), "Certified");
  });
});
