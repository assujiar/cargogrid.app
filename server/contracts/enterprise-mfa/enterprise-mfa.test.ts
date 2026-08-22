import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseMfaTenantPolicy,
  parseMfaStepUpChallenge,
  parseUserSession,
  parseMfaException,
  SetMfaTenantPolicyInputSchema,
  RequestMfaStepUpChallengeInputSchema,
} from "./enterprise-mfa.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const CHALLENGE_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseMfaTenantPolicy", () => {
  test("round-trips a default policy row", () => {
    const policy = parseMfaTenantPolicy({
      tenant_id: TENANT_ID, tenant_wide_required: false, required_layers: ["supreme_admin", "tenant_admin"],
      step_up_max_age_minutes: 15, additional_high_risk_actions: [], updated_by: null, updated_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(policy.stepUpMaxAgeMinutes, 15);
    assert.equal(policy.tenantWideRequired, false);
  });
});

describe("parseMfaStepUpChallenge", () => {
  test("round-trips a pending challenge", () => {
    const challenge = parseMfaStepUpChallenge({
      id: CHALLENGE_ID, tenant_id: TENANT_ID, auth_user_id: ACTOR_ID, module_code: "FIN", action: "Approve",
      status: "pending", challenge_issued_at: "2026-08-22T00:00:00.000Z", challenge_expires_at: "2026-08-22T00:10:00.000Z", verified_at: null,
    });
    assert.equal(challenge.status, "pending");
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseMfaStepUpChallenge({
        id: CHALLENGE_ID, tenant_id: TENANT_ID, auth_user_id: ACTOR_ID, module_code: "FIN", action: "Approve",
        status: "not-a-real-status", challenge_issued_at: "2026-08-22T00:00:00.000Z", challenge_expires_at: "2026-08-22T00:10:00.000Z", verified_at: null,
      }),
    );
  });
});

describe("parseUserSession", () => {
  test("round-trips an active session", () => {
    const session = parseUserSession({
      id: CHALLENGE_ID, tenant_id: TENANT_ID, auth_user_id: ACTOR_ID, device_label: "laptop", ip_address: "203.0.113.1",
      status: "active", created_at: "2026-08-22T00:00:00.000Z", last_seen_at: "2026-08-22T00:00:00.000Z",
      revoked_at: null, revoked_reason: null, revoked_by: null,
    });
    assert.equal(session.status, "active");
  });
});

describe("parseMfaException", () => {
  test("round-trips a pending exception", () => {
    const exception = parseMfaException({
      id: CHALLENGE_ID, tenant_id: TENANT_ID, target_auth_user_id: ACTOR_ID, reason: "lost phone",
      requested_by_auth_user_id: ACTOR_ID, requested_by: "admin1", approved_by_auth_user_id: null, approved_by: null,
      status: "pending", requested_at: "2026-08-22T00:00:00.000Z", decided_at: null,
      expires_at: "2026-08-23T00:00:00.000Z", used_at: null,
    });
    assert.equal(exception.status, "pending");
  });
});

describe("input schemas", () => {
  test("SetMfaTenantPolicyInputSchema rejects an out-of-range stepUpMaxAgeMinutes", () => {
    assert.throws(() =>
      SetMfaTenantPolicyInputSchema.parse({
        tenantId: TENANT_ID, tenantWideRequired: true, requiredLayers: ["supreme_admin"], stepUpMaxAgeMinutes: 9999,
        additionalHighRiskActions: [], actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("RequestMfaStepUpChallengeInputSchema rejects an empty action", () => {
    assert.throws(() =>
      RequestMfaStepUpChallengeInputSchema.parse({ tenantId: TENANT_ID, moduleCode: "FIN", action: "", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
    );
  });
});
