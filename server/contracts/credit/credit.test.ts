import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCreditProfile,
  parseCreditProfileOverride,
  parseCreditCheckResult,
  RequestCustomerCreditProfileInputSchema,
  DecideCreditProfileApprovalStepInputSchema,
  CreateCreditOverrideInputSchema,
  CheckCustomerCreditInputSchema,
} from "./credit.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROFILE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "623e4567-e89b-12d3-a456-426614174000";

const PROFILE_ROW = {
  id: PROFILE_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  currency: "IDR",
  requested_limit_amount: 50000000,
  approved_limit_amount: 50000000,
  amount_masked: false,
  status: "active",
  effective_from: "2026-07-24T00:00:00.000Z",
  effective_to: null,
  hold_reason: null,
  rejected_reason: null,
  approval_request_id: "723e4567-e89b-12d3-a456-426614174000",
  supersedes_profile_id: null,
  approved_by: "approver",
  approved_at: "2026-07-24T00:00:00.000Z",
  record_version: 2,
  created_by: "rep",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

describe("parseCreditProfile", () => {
  test("maps an unmasked active profile", () => {
    const profile = parseCreditProfile(PROFILE_ROW);
    assert.equal(profile.status, "active");
    assert.equal(profile.approvedLimitAmount, 50000000);
    assert.equal(profile.amountMasked, false);
  });

  test("maps a masked profile with null amounts", () => {
    const profile = parseCreditProfile({ ...PROFILE_ROW, currency: null, requested_limit_amount: null, approved_limit_amount: null, amount_masked: true });
    assert.equal(profile.amountMasked, true);
    assert.equal(profile.approvedLimitAmount, null);
  });
});

describe("parseCreditProfileOverride", () => {
  test("maps an unmasked override", () => {
    const override = parseCreditProfileOverride({
      id: "823e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      credit_profile_id: PROFILE_ID,
      amount: 80000000,
      amount_masked: false,
      reason: "One-time large shipment",
      expires_at: "2026-08-01T00:00:00.000Z",
      approved_by: "approver",
      created_by: "approver",
      created_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(override.amount, 80000000);
    assert.equal(override.reason, "One-time large shipment");
  });
});

describe("parseCreditCheckResult", () => {
  test("maps an allow outcome", () => {
    const result = parseCreditCheckResult({
      id: "923e4567-e89b-12d3-a456-426614174000",
      credit_profile_id: PROFILE_ID,
      profile_status_at_check: "active",
      currency: "IDR",
      requested_amount: 30000000,
      effective_limit_amount: 50000000,
      amount_masked: false,
      outcome: "allow",
      checked_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(result.outcome, "allow");
    assert.equal(result.effectiveLimitAmount, 50000000);
  });

  test("maps a blocked_no_profile outcome with null profile fields", () => {
    const result = parseCreditCheckResult({
      id: "923e4567-e89b-12d3-a456-426614174000",
      credit_profile_id: null,
      profile_status_at_check: null,
      currency: "IDR",
      requested_amount: 100,
      effective_limit_amount: null,
      amount_masked: false,
      outcome: "blocked_no_profile",
      checked_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(result.outcome, "blocked_no_profile");
    assert.equal(result.creditProfileId, null);
  });
});

describe("RequestCustomerCreditProfileInputSchema", () => {
  test("rejects a malformed currency code", () => {
    assert.throws(() =>
      RequestCustomerCreditProfileInputSchema.parse({ tenantId: TENANT_ID, accountId: ACCOUNT_ID, currency: "idr", requestedLimitAmount: 100, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });

  test("rejects a negative requestedLimitAmount", () => {
    assert.throws(() =>
      RequestCustomerCreditProfileInputSchema.parse({ tenantId: TENANT_ID, accountId: ACCOUNT_ID, currency: "IDR", requestedLimitAmount: -1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });
});

describe("DecideCreditProfileApprovalStepInputSchema", () => {
  test("defaults reason to null and requires reauthConfirmedAt", () => {
    const parsed = DecideCreditProfileApprovalStepInputSchema.parse({ requestStepId: STEP_ID, decision: "approved", reauthConfirmedAt: "2026-07-24T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(parsed.reason, null);
  });

  test("rejects a missing reauthConfirmedAt", () => {
    assert.throws(() => DecideCreditProfileApprovalStepInputSchema.parse({ requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "approver" }));
  });
});

describe("CreateCreditOverrideInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      CreateCreditOverrideInputSchema.parse({ profileId: PROFILE_ID, amount: 100, reason: "", expiresAt: "2026-08-01T00:00:00.000Z", reauthConfirmedAt: "2026-07-24T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "approver" }),
    );
  });
});

describe("CheckCustomerCreditInputSchema", () => {
  test("defaults contextType/contextId to null", () => {
    const parsed = CheckCustomerCreditInputSchema.parse({ tenantId: TENANT_ID, accountId: ACCOUNT_ID, currency: "IDR", requestedAmount: 100, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(parsed.contextType, null);
    assert.equal(parsed.contextId, null);
  });
});
