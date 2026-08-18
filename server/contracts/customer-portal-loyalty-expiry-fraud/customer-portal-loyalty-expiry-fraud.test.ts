import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLoyaltyExpiryRun,
  parseLoyaltyFraudReviewCase,
  parseLoyaltyFraudReviewSuppression,
  parseCustomerPortalLoyaltyAccountHoldStatus,
  describeLoyaltyFraudReviewCaseStatus,
  LoyaltyExpiryFraudUpdatedAtCursorSchema,
  LoyaltyExpiryFraudCreatedAtCursorSchema,
  OpenLoyaltyFraudReviewCaseInputSchema,
  DecideLoyaltyFraudReviewCaseInputSchema,
  SuppressLoyaltyFraudReviewInputSchema,
} from "./customer-portal-loyalty-expiry-fraud.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const CASE_ID = "423e4567-e89b-12d3-a456-426614174000";
const SUPPRESSION_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseLoyaltyExpiryRun", () => {
  test("maps a completed run with real counts", () => {
    const run = parseLoyaltyExpiryRun({
      job_id: JOB_ID,
      status: "completed",
      run_label: "2026-08-18",
      as_of: "2026-08-18T00:00:00.000Z",
      lots_expired_count: 3,
      entitlements_expired_count: 1,
      error: null,
      created_at: "2026-08-18T00:00:00.000Z",
      completed_at: "2026-08-18T00:00:01.000Z",
      updated_at: "2026-08-18T00:00:01.000Z",
    });
    assert.equal(run.status, "completed");
    assert.equal(run.lotsExpiredCount, 3);
    assert.equal(run.entitlementsExpiredCount, 1);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseLoyaltyExpiryRun({
        job_id: JOB_ID,
        status: "made_up_status",
        run_label: "2026-08-18",
        as_of: null,
        lots_expired_count: 0,
        entitlements_expired_count: 0,
        error: null,
        created_at: "2026-08-18T00:00:00.000Z",
        completed_at: null,
        updated_at: "2026-08-18T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLoyaltyFraudReviewCase", () => {
  test("maps an open case, internal risk_signal fields present (staff-only projection)", () => {
    const fraudCase = parseLoyaltyFraudReviewCase({
      id: CASE_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      risk_signal_type: "velocity_anomaly",
      risk_signal_detail: "12 redemptions in 5 minutes",
      status: "open",
      opened_by: "manager1",
      reviewed_by: null,
      review_reason: null,
      decided_at: null,
      idempotency_key: "idem-1",
      record_version: 1,
      created_at: "2026-08-18T00:00:00.000Z",
      updated_at: "2026-08-18T00:00:00.000Z",
    });
    assert.equal(fraudCase.status, "open");
    assert.equal(fraudCase.riskSignalType, "velocity_anomaly");
    assert.equal(fraudCase.riskSignalDetail, "12 redemptions in 5 minutes");
  });

  test("rejects an unrecognized risk_signal_type", () => {
    assert.throws(() =>
      parseLoyaltyFraudReviewCase({
        id: CASE_ID,
        tenant_id: TENANT_ID,
        loyalty_account_id: ACCOUNT_ID,
        risk_signal_type: "made_up_signal",
        risk_signal_detail: "x",
        status: "open",
        opened_by: "manager1",
        reviewed_by: null,
        review_reason: null,
        decided_at: null,
        idempotency_key: "idem-2",
        record_version: 1,
        created_at: "2026-08-18T00:00:00.000Z",
        updated_at: "2026-08-18T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLoyaltyFraudReviewSuppression", () => {
  test("maps an active (non-revoked) suppression", () => {
    const suppression = parseLoyaltyFraudReviewSuppression({
      id: SUPPRESSION_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      reason: "verified false positive, cooldown 7 days",
      expires_at: "2026-08-25T00:00:00.000Z",
      suppressed_by_auth_user_id: ACCOUNT_ID,
      suppressed_by: "manager1",
      revoked_at: null,
      revoked_by: null,
      revoked_reason: null,
      record_version: 1,
      created_at: "2026-08-18T00:00:00.000Z",
    });
    assert.equal(suppression.revokedAt, null);
    assert.equal(suppression.reason, "verified false positive, cooldown 7 days");
  });
});

describe("customer-facing hold status projection", () => {
  test("parseCustomerPortalLoyaltyAccountHoldStatus maps a held account, never exposes internal fields", () => {
    const status = parseCustomerPortalLoyaltyAccountHoldStatus({
      loyalty_account_id: ACCOUNT_ID,
      program_name: "Test Program",
      is_on_hold: true,
      hold_notice: "Your loyalty account is temporarily on hold. Contact your account administrator or support for details.",
    });
    assert.equal(status.isOnHold, true);
    assert.ok(!("risk_signal_type" in status));
    assert.ok(!("riskSignalType" in status));
    assert.ok(!("review_reason" in status));
    assert.ok(!("reviewReason" in status));
  });

  test("maps a non-held account with a null hold_notice", () => {
    const status = parseCustomerPortalLoyaltyAccountHoldStatus({
      loyalty_account_id: ACCOUNT_ID,
      program_name: "Test Program",
      is_on_hold: false,
      hold_notice: null,
    });
    assert.equal(status.isOnHold, false);
    assert.equal(status.holdNotice, null);
  });
});

describe("describeLoyaltyFraudReviewCaseStatus", () => {
  test("renders customer-safe-shaped labels, never the raw enum value verbatim", () => {
    assert.equal(describeLoyaltyFraudReviewCaseStatus("open"), "Open");
    assert.equal(describeLoyaltyFraudReviewCaseStatus("under_review"), "Under review");
    const confirmed = describeLoyaltyFraudReviewCaseStatus("confirmed");
    assert.equal(confirmed, "Confirmed");
    assert.notEqual(confirmed, "confirmed");
  });
});

describe("cursor schemas", () => {
  test("LoyaltyExpiryFraudUpdatedAtCursorSchema rejects a half-supplied cursor", () => {
    assert.equal(LoyaltyExpiryFraudUpdatedAtCursorSchema.safeParse({ cursorId: CASE_ID }).success, false);
  });
  test("LoyaltyExpiryFraudUpdatedAtCursorSchema accepts a fully-supplied cursor", () => {
    assert.equal(LoyaltyExpiryFraudUpdatedAtCursorSchema.safeParse({ cursorUpdatedAt: "2026-08-18T00:00:00.000Z", cursorId: CASE_ID }).success, true);
  });
  test("LoyaltyExpiryFraudCreatedAtCursorSchema rejects a half-supplied cursor", () => {
    assert.equal(LoyaltyExpiryFraudCreatedAtCursorSchema.safeParse({ cursorId: SUPPRESSION_ID }).success, false);
  });
  test("LoyaltyExpiryFraudCreatedAtCursorSchema accepts a fully-supplied cursor", () => {
    assert.equal(LoyaltyExpiryFraudCreatedAtCursorSchema.safeParse({ cursorCreatedAt: "2026-08-18T00:00:00.000Z", cursorId: SUPPRESSION_ID }).success, true);
  });
});

describe("OpenLoyaltyFraudReviewCaseInputSchema", () => {
  test("rejects an empty risk_signal_detail", () => {
    const result = OpenLoyaltyFraudReviewCaseInputSchema.safeParse({
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      riskSignalType: "manual_flag",
      riskSignalDetail: "",
      idempotencyKey: "idem-1",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, false);
  });

  test("rejects an unrecognized risk_signal_type", () => {
    const result = OpenLoyaltyFraudReviewCaseInputSchema.safeParse({
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      riskSignalType: "made_up",
      riskSignalDetail: "x",
      idempotencyKey: "idem-1",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, false);
  });

  test("accepts a real case", () => {
    const result = OpenLoyaltyFraudReviewCaseInputSchema.safeParse({
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      riskSignalType: "duplicate_device",
      riskSignalDetail: "same device fingerprint across 3 accounts",
      idempotencyKey: "idem-1",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, true);
  });
});

describe("DecideLoyaltyFraudReviewCaseInputSchema", () => {
  test("rejects an empty reviewReason", () => {
    const result = DecideLoyaltyFraudReviewCaseInputSchema.safeParse({
      tenantId: TENANT_ID,
      caseId: CASE_ID,
      expectedVersion: 1,
      decision: "clear",
      reviewReason: "",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, false);
  });

  test("rejects an unrecognized decision", () => {
    const result = DecideLoyaltyFraudReviewCaseInputSchema.safeParse({
      tenantId: TENANT_ID,
      caseId: CASE_ID,
      expectedVersion: 1,
      decision: "approve",
      reviewReason: "looks fine",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, false);
  });

  test("accepts a confirm decision with a real reason", () => {
    const result = DecideLoyaltyFraudReviewCaseInputSchema.safeParse({
      tenantId: TENANT_ID,
      caseId: CASE_ID,
      expectedVersion: 1,
      decision: "confirm",
      reviewReason: "confirmed velocity anomaly after manual review",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, true);
  });
});

describe("SuppressLoyaltyFraudReviewInputSchema", () => {
  test("rejects an empty reason", () => {
    const result = SuppressLoyaltyFraudReviewInputSchema.safeParse({
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      reason: "",
      expiresAt: "2026-08-25T00:00:00.000Z",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, false);
  });

  test("accepts a real suppression request", () => {
    const result = SuppressLoyaltyFraudReviewInputSchema.safeParse({
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      reason: "verified false positive",
      expiresAt: "2026-08-25T00:00:00.000Z",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, true);
  });
});
