import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  runLoyaltyExpirySweep,
  openLoyaltyFraudReviewCase,
  claimLoyaltyFraudReviewCase,
  decideLoyaltyFraudReviewCase,
  suppressLoyaltyFraudReview,
  revokeLoyaltyFraudReviewSuppression,
  LoyaltyExpiryFraudMutationError,
  type LoyaltyExpiryFraudMutationRpcClient,
} from "./customer-portal-loyalty-expiry-fraud.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const CASE_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "523e4567-e89b-12d3-a456-426614174000";
const SUPPRESSION_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyExpiryFraudMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyExpiryFraudMutationRpcClient;
  return { client, calls };
}

const RUN_ROW = {
  job_id: JOB_ID,
  status: "completed",
  run_label: "2026-08-18",
  as_of: "2026-08-18T00:00:00.000Z",
  lots_expired_count: 1,
  entitlements_expired_count: 0,
  error: null,
  created_at: "2026-08-18T00:00:00.000Z",
  completed_at: "2026-08-18T00:00:01.000Z",
  updated_at: "2026-08-18T00:00:01.000Z",
};

const CASE_ROW = {
  id: CASE_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  risk_signal_type: "manual_flag",
  risk_signal_detail: "reported by support",
  status: "open",
  opened_by: "manager1",
  reviewed_by: null,
  review_reason: null,
  decided_at: null,
  idempotency_key: "idem-1",
  record_version: 1,
  created_at: "2026-08-18T00:00:00.000Z",
  updated_at: "2026-08-18T00:00:00.000Z",
};

const SUPPRESSION_ROW = {
  id: SUPPRESSION_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  reason: "verified false positive",
  expires_at: "2026-08-25T00:00:00.000Z",
  suppressed_by_auth_user_id: ACTOR_ID,
  suppressed_by: "manager1",
  revoked_at: null,
  revoked_by: null,
  revoked_reason: null,
  record_version: 1,
  created_at: "2026-08-18T00:00:00.000Z",
};

describe("runLoyaltyExpirySweep", () => {
  test("passes the exact param names, runLabel/asOf default to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [RUN_ROW], error: null });
    const result = await runLoyaltyExpirySweep(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.status, "completed");
    assert.deepEqual(calls[0], {
      fn: "run_loyalty_expiry_sweep",
      args: { p_tenant_id: TENANT_ID, p_as_of: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1", p_run_label: null },
    });
  });

  test("propagates insufficient_authority with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: x" } });
    await assert.rejects(
      () => runLoyaltyExpirySweep(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
      (err: unknown) => err instanceof LoyaltyExpiryFraudMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("openLoyaltyFraudReviewCase", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [CASE_ROW], error: null });
    const result = await openLoyaltyFraudReviewCase(client, {
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      riskSignalType: "manual_flag",
      riskSignalDetail: "reported by support",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.status, "open");
    assert.deepEqual(calls[0], {
      fn: "open_loyalty_fraud_review_case",
      args: {
        p_tenant_id: TENANT_ID,
        p_loyalty_account_id: ACCOUNT_ID,
        p_risk_signal_type: "manual_flag",
        p_risk_signal_detail: "reported by support",
        p_idempotency_key: "idem-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "manager1",
      },
    });
  });

  test("propagates fraud_review_suppressed with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "fraud_review_suppressed: x" } });
    await assert.rejects(
      () =>
        openLoyaltyFraudReviewCase(client, {
          tenantId: TENANT_ID,
          loyaltyAccountId: ACCOUNT_ID,
          riskSignalType: "manual_flag",
          riskSignalDetail: "x",
          idempotencyKey: "idem-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "manager1",
        }),
      (err: unknown) => err instanceof LoyaltyExpiryFraudMutationError && err.code === "fraud_review_suppressed",
    );
  });

  test("rejects zod-invalid input (empty riskSignalDetail) before ever calling rpc", async () => {
    const { client, calls } = fakeRpcClient({ data: [CASE_ROW], error: null });
    await assert.rejects(() =>
      openLoyaltyFraudReviewCase(client, {
        tenantId: TENANT_ID,
        loyaltyAccountId: ACCOUNT_ID,
        riskSignalType: "manual_flag",
        riskSignalDetail: "",
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager1",
      }),
    );
    assert.equal(calls.length, 0);
  });
});

describe("claimLoyaltyFraudReviewCase", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...CASE_ROW, status: "under_review" }], error: null });
    const result = await claimLoyaltyFraudReviewCase(client, { tenantId: TENANT_ID, caseId: CASE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.status, "under_review");
    assert.deepEqual(calls[0], {
      fn: "claim_loyalty_fraud_review_case",
      args: { p_tenant_id: TENANT_ID, p_case_id: CASE_ID, p_expected_version: 1, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });
});

describe("decideLoyaltyFraudReviewCase", () => {
  test("passes the exact param names for a clear decision", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...CASE_ROW, status: "cleared", reviewed_by: "manager2", review_reason: "false positive" }], error: null });
    const result = await decideLoyaltyFraudReviewCase(client, {
      tenantId: TENANT_ID,
      caseId: CASE_ID,
      expectedVersion: 1,
      decision: "clear",
      reviewReason: "false positive",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager2",
    });
    assert.equal(result.status, "cleared");
    assert.deepEqual(calls[0], {
      fn: "decide_loyalty_fraud_review_case",
      args: { p_tenant_id: TENANT_ID, p_case_id: CASE_ID, p_expected_version: 1, p_decision: "clear", p_review_reason: "false positive", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager2" },
    });
  });

  test("propagates stale_version with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: x" } });
    await assert.rejects(
      () =>
        decideLoyaltyFraudReviewCase(client, {
          tenantId: TENANT_ID,
          caseId: CASE_ID,
          expectedVersion: 1,
          decision: "confirm",
          reviewReason: "confirmed",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "manager1",
        }),
      (err: unknown) => err instanceof LoyaltyExpiryFraudMutationError && err.code === "stale_version",
    );
  });
});

describe("suppressLoyaltyFraudReview / revokeLoyaltyFraudReviewSuppression", () => {
  test("suppressLoyaltyFraudReview passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [SUPPRESSION_ROW], error: null });
    const result = await suppressLoyaltyFraudReview(client, {
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      reason: "verified false positive",
      expiresAt: "2026-08-25T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.revokedAt, null);
    assert.deepEqual(calls[0], {
      fn: "suppress_loyalty_fraud_review",
      args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_reason: "verified false positive", p_expires_at: "2026-08-25T00:00:00.000Z", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });

  test("revokeLoyaltyFraudReviewSuppression passes the exact param names, reason defaults to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SUPPRESSION_ROW, revoked_at: "2026-08-18T01:00:00.000Z", revoked_by: "manager1", revoked_reason: "revoked by staff" }], error: null });
    const result = await revokeLoyaltyFraudReviewSuppression(client, { tenantId: TENANT_ID, suppressionId: SUPPRESSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.ok(result.revokedAt);
    assert.deepEqual(calls[0], {
      fn: "revoke_loyalty_fraud_review_suppression",
      args: { p_tenant_id: TENANT_ID, p_suppression_id: SUPPRESSION_ID, p_expected_version: 1, p_reason: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });
});
