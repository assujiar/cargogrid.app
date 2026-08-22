import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  requestEnterpriseSsoDomainClaim,
  verifyEnterpriseSsoDomainClaim,
  activateEnterpriseSsoDomainClaim,
  disableEnterpriseSsoDomainClaim,
  resolveEnterpriseSsoClaims,
  activateEnterpriseIdpConnection,
  provisionScimIdentity,
  EnterpriseIamMutationError,
  type EnterpriseIamMutationRpcClient,
} from "./enterprise-iam.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "423e4567-e89b-12d3-a456-426614174000";
const CLAIM_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_CLAIM_ROW = {
  id: CLAIM_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, email_domain: "acme.test",
  status: "pending_verification", verification_method: "dns_txt", verification_token: "abc123",
  verification_challenge_host: "_cargogrid-verify.acme.test", requested_by: "admin1",
  verified_at: null, verified_by: null, activated_at: null, activated_by: null,
  disabled_at: null, disabled_by: null, disabled_reason: null,
  rejected_at: null, rejected_by: null, rejected_reason: null,
  expires_at: "2026-08-29T00:00:00.000Z", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z",
};

const VALID_ATTEMPT_ROW = {
  id: CLAIM_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, domain_claim_id: CLAIM_ID,
  subject_claim: "okta|subject-1", email_claim: "person@acme.test", resolved_auth_user_id: ACTOR_ID,
  outcome: "matched", resolved_by_auth_user_id: ACTOR_ID, occurred_at: "2026-08-22T00:00:00.000Z",
};

const VALID_CONNECTION_ROW = {
  id: CONNECTION_ID, tenant_id: TENANT_ID, adapter_code: "enterprise_sso_oidc", name: "Okta OIDC",
  environment: "production", status: "active", owner_team: null, owner_email: null, runbook_url: null,
  config: {}, consecutive_failure_count: 0, last_health_check_at: null, last_health_status: null,
  auto_disabled_at: null, disabled_reason: null, record_version: 1,
  created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z",
};

const VALID_SCIM_EVENT_ROW = {
  id: CLAIM_ID, tenant_id: TENANT_ID, scim_link_id: CLAIM_ID, api_key_id: null,
  operation: "create", is_dry_run: false, outcome: "applied", outcome_reason: null,
  occurred_at: "2026-08-22T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: EnterpriseIamMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as EnterpriseIamMutationRpcClient;
  return { client, calls };
}

describe("requestEnterpriseSsoDomainClaim", () => {
  test("calls request_enterprise_sso_domain_claim with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_CLAIM_ROW, error: null });
    const claim = await requestEnterpriseSsoDomainClaim(client, {
      tenantId: TENANT_ID, connectionId: CONNECTION_ID, emailDomain: "acme.test", actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(claim.status, "pending_verification");
    assert.equal(calls[0]?.fn, "request_enterprise_sso_domain_claim");
    assert.equal(calls[0]?.args.p_email_domain, "acme.test");
  });

  test("classifies a known error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "email_domain_already_claimed: acme.test is already claimed" } });
    await assert.rejects(
      requestEnterpriseSsoDomainClaim(client, { tenantId: TENANT_ID, connectionId: CONNECTION_ID, emailDomain: "acme.test", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseIamMutationError && err.code === "email_domain_already_claimed",
    );
  });

  test("classifies an unrecognized error as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_never_before_seen_error: oops" } });
    await assert.rejects(
      requestEnterpriseSsoDomainClaim(client, { tenantId: TENANT_ID, connectionId: CONNECTION_ID, emailDomain: "acme.test", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseIamMutationError && err.code === "mutation_failed",
    );
  });
});

describe("verifyEnterpriseSsoDomainClaim", () => {
  test("calls verify_enterprise_sso_domain_claim with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_CLAIM_ROW, status: "verified" }, error: null });
    const claim = await verifyEnterpriseSsoDomainClaim(client, { claimId: CLAIM_ID, observedTxtValue: "abc123", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(claim.status, "verified");
    assert.equal(calls[0]?.args.p_observed_txt_value, "abc123");
  });
});

describe("activateEnterpriseSsoDomainClaim / disableEnterpriseSsoDomainClaim", () => {
  test("activate returns the active row", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_CLAIM_ROW, status: "active" }, error: null });
    const claim = await activateEnterpriseSsoDomainClaim(client, { claimId: CLAIM_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(claim.status, "active");
  });

  test("disable classifies iam_domain_claim_not_disableable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "iam_domain_claim_not_disableable: already disabled" } });
    await assert.rejects(
      disableEnterpriseSsoDomainClaim(client, { claimId: CLAIM_ID, reason: "test", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseIamMutationError && err.code === "iam_domain_claim_not_disableable",
    );
  });
});

describe("resolveEnterpriseSsoClaims", () => {
  test("passes a null rawEmailClaim through unchanged (defensive extraction happens server-side, never at this layer)", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_ATTEMPT_ROW, outcome: "invalid_email_claim", resolved_auth_user_id: null }, error: null });
    const attempt = await resolveEnterpriseSsoClaims(client, { connectionId: CONNECTION_ID, subjectClaim: "okta|subject-1", rawEmailClaim: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(attempt.outcome, "invalid_email_claim");
    assert.equal(calls[0]?.args.p_raw_email_claim, null);
  });

  test("returns a matched outcome with the resolved auth user id", async () => {
    const { client } = fakeRpcClient({ data: VALID_ATTEMPT_ROW, error: null });
    const attempt = await resolveEnterpriseSsoClaims(client, { connectionId: CONNECTION_ID, subjectClaim: "okta|subject-1", rawEmailClaim: "person@acme.test", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(attempt.outcome, "matched");
    assert.equal(attempt.resolvedAuthUserId, ACTOR_ID);
  });
});

describe("activateEnterpriseIdpConnection", () => {
  test("returns the active connection", async () => {
    const { client } = fakeRpcClient({ data: VALID_CONNECTION_ROW, error: null });
    const connection = await activateEnterpriseIdpConnection(client, { connectionId: CONNECTION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(connection.status, "active");
  });

  test("classifies the lockout guard's own named error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "enterprise_idp_no_verified_test_login: connection has no recorded successful test-login resolution" } });
    await assert.rejects(
      activateEnterpriseIdpConnection(client, { connectionId: CONNECTION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof EnterpriseIamMutationError && err.code === "enterprise_idp_no_verified_test_login",
    );
  });
});

describe("provisionScimIdentity", () => {
  test("calls provision_scim_identity with the exact snake_case params, including isDryRun", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_SCIM_EVENT_ROW, outcome: "dry_run_preview" }, error: null });
    const event = await provisionScimIdentity(client, {
      tenantId: TENANT_ID, apiKeyId: null, externalId: "ext-1", rawEmail: "person@acme.test", displayName: "Person",
      operation: "create", isDryRun: true, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(event.outcome, "dry_run_preview");
    assert.equal(calls[0]?.args.p_is_dry_run, true);
  });

  test("a rejected outcome is still a normal return value, not a thrown error -- rejection is a real, documented business outcome", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_SCIM_EVENT_ROW, outcome: "rejected", outcome_reason: "no_matching_platform_identity" }, error: null });
    const event = await provisionScimIdentity(client, {
      tenantId: TENANT_ID, apiKeyId: null, externalId: "ext-2", rawEmail: "brand.new@acme.test", displayName: "Brand New",
      operation: "create", isDryRun: false, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(event.outcome, "rejected");
    assert.equal(event.outcomeReason, "no_matching_platform_identity");
  });
});
