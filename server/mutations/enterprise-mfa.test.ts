import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  setMfaTenantPolicy,
  requestMfaStepUpChallenge,
  verifyMfaStepUpChallenge,
  registerUserSession,
  revokeUserSession,
  revokeAllActorSessions,
  requestMfaException,
  approveMfaException,
  consumeMfaException,
  assertCurrentStepUpAuthorization,
  EnterpriseMfaMutationError,
  type EnterpriseMfaMutationRpcClient,
} from "./enterprise-mfa.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const CHALLENGE_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_POLICY_ROW = {
  tenant_id: TENANT_ID, tenant_wide_required: true, required_layers: ["supreme_admin"],
  step_up_max_age_minutes: 20, additional_high_risk_actions: [], updated_by: "admin1", updated_at: "2026-08-22T00:00:00.000Z",
};

const VALID_CHALLENGE_ROW = {
  id: CHALLENGE_ID, tenant_id: TENANT_ID, auth_user_id: ACTOR_ID, module_code: "FIN", action: "Approve",
  status: "pending", challenge_issued_at: "2026-08-22T00:00:00.000Z", challenge_expires_at: "2026-08-22T00:10:00.000Z", verified_at: null,
};

const VALID_SESSION_ROW = {
  id: CHALLENGE_ID, tenant_id: TENANT_ID, auth_user_id: ACTOR_ID, device_label: "laptop", ip_address: "203.0.113.1",
  status: "active", created_at: "2026-08-22T00:00:00.000Z", last_seen_at: "2026-08-22T00:00:00.000Z",
  revoked_at: null, revoked_reason: null, revoked_by: null,
};

const VALID_EXCEPTION_ROW = {
  id: CHALLENGE_ID, tenant_id: TENANT_ID, target_auth_user_id: ACTOR_ID, reason: "lost phone",
  requested_by_auth_user_id: ACTOR_ID, requested_by: "admin1", approved_by_auth_user_id: null, approved_by: null,
  status: "pending", requested_at: "2026-08-22T00:00:00.000Z", decided_at: null,
  expires_at: "2026-08-23T00:00:00.000Z", used_at: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: EnterpriseMfaMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as EnterpriseMfaMutationRpcClient;
  return { client, calls };
}

describe("setMfaTenantPolicy", () => {
  test("calls set_mfa_tenant_policy with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_POLICY_ROW, error: null });
    const policy = await setMfaTenantPolicy(client, {
      tenantId: TENANT_ID, tenantWideRequired: true, requiredLayers: ["supreme_admin"], stepUpMaxAgeMinutes: 20,
      additionalHighRiskActions: [], actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(policy.stepUpMaxAgeMinutes, 20);
    assert.equal(calls[0]?.args.p_step_up_max_age_minutes, 20);
  });

  test("classifies a known error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "mfa_invalid_step_up_max_age: 9999 must be between 1 and 1440 minutes" } });
    await assert.rejects(
      setMfaTenantPolicy(client, { tenantId: TENANT_ID, tenantWideRequired: true, requiredLayers: [], stepUpMaxAgeMinutes: 30, additionalHighRiskActions: [], actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseMfaMutationError && err.code === "mfa_invalid_step_up_max_age",
    );
  });
});

describe("requestMfaStepUpChallenge / verifyMfaStepUpChallenge", () => {
  test("request returns a pending challenge", async () => {
    const { client } = fakeRpcClient({ data: VALID_CHALLENGE_ROW, error: null });
    const challenge = await requestMfaStepUpChallenge(client, { tenantId: TENANT_ID, moduleCode: "FIN", action: "Approve", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(challenge.status, "pending");
  });

  test("request classifies mfa_step_up_not_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "mfa_step_up_not_required: OPS:View is not classified as a high-risk action" } });
    await assert.rejects(
      requestMfaStepUpChallenge(client, { tenantId: TENANT_ID, moduleCode: "OPS", action: "View", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseMfaMutationError && err.code === "mfa_step_up_not_required",
    );
  });

  test("verify returns a verified challenge", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_CHALLENGE_ROW, status: "verified", verified_at: "2026-08-22T00:01:00.000Z" }, error: null });
    const challenge = await verifyMfaStepUpChallenge(client, { challengeId: CHALLENGE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(challenge.status, "verified");
  });

  test("verify classifies mfa_step_up_challenge_expired", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "mfa_step_up_challenge_expired: challenge expired" } });
    await assert.rejects(
      verifyMfaStepUpChallenge(client, { challengeId: CHALLENGE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseMfaMutationError && err.code === "mfa_step_up_challenge_expired",
    );
  });
});

describe("assertCurrentStepUpAuthorization", () => {
  test("resolves (no throw) when the RPC reports no error", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assertCurrentStepUpAuthorization(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, moduleCode: "OPS", action: "View" });
    assert.equal(calls[0]?.fn, "assert_current_step_up_authorization");
  });

  test("throws mfa_step_up_required when the RPC reports that error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "mfa_step_up_required: FIN:Approve requires a current MFA step-up verification" } });
    await assert.rejects(
      assertCurrentStepUpAuthorization(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, moduleCode: "FIN", action: "Approve" }),
      (err: unknown) => err instanceof EnterpriseMfaMutationError && err.code === "mfa_step_up_required",
    );
  });
});

describe("registerUserSession / revokeUserSession / revokeAllActorSessions", () => {
  test("register returns an active session", async () => {
    const { client } = fakeRpcClient({ data: VALID_SESSION_ROW, error: null });
    const session = await registerUserSession(client, { tenantId: TENANT_ID, deviceLabel: "laptop", ipAddress: "203.0.113.1", actorAuthUserId: ACTOR_ID, actorLabel: "rep1" });
    assert.equal(session.status, "active");
  });

  test("revoke returns a revoked session", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_SESSION_ROW, status: "revoked" }, error: null });
    const session = await revokeUserSession(client, { sessionId: CHALLENGE_ID, reason: "lost device", actorAuthUserId: ACTOR_ID, actorLabel: "rep1" });
    assert.equal(session.status, "revoked");
  });

  test("revokeAllActorSessions returns the numeric session count, not the api-key count", async () => {
    const { client, calls } = fakeRpcClient({ data: 3, error: null });
    const count = await revokeAllActorSessions(client, { tenantId: TENANT_ID, targetAuthUserId: ACTOR_ID, reason: "account compromise", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(count, 3);
    assert.equal(calls[0]?.fn, "revoke_all_actor_sessions");
  });

  test("revokeAllActorSessions rejects a non-numeric response", async () => {
    const { client } = fakeRpcClient({ data: { unexpected: "shape" }, error: null });
    await assert.rejects(
      revokeAllActorSessions(client, { tenantId: TENANT_ID, targetAuthUserId: ACTOR_ID, reason: "test", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseMfaMutationError && err.code === "invalid_response",
    );
  });
});

describe("requestMfaException / approveMfaException / consumeMfaException", () => {
  test("request returns a pending exception", async () => {
    const { client } = fakeRpcClient({ data: VALID_EXCEPTION_ROW, error: null });
    const exception = await requestMfaException(client, { tenantId: TENANT_ID, targetAuthUserId: ACTOR_ID, reason: "lost phone", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(exception.status, "pending");
  });

  test("approve classifies self-approval-forbidden", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "mfa_exception_self_approval_forbidden: identity cannot approve their own request" } });
    await assert.rejects(
      approveMfaException(client, { exceptionId: CHALLENGE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseMfaMutationError && err.code === "mfa_exception_self_approval_forbidden",
    );
  });

  test("consume returns a used exception", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_EXCEPTION_ROW, status: "used", used_at: "2026-08-22T01:00:00.000Z" }, error: null });
    const exception = await consumeMfaException(client, { exceptionId: CHALLENGE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep1" });
    assert.equal(exception.status, "used");
  });
});
