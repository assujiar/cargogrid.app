import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseIamDomainClaim,
  parseIamSsoLoginAttempt,
  parseIamScimProvisioningEvent,
  parseEnterpriseIdpByEmailDomain,
  RequestEnterpriseSsoDomainClaimInputSchema,
  ResolveEnterpriseSsoClaimsInputSchema,
  ProvisionScimIdentityInputSchema,
} from "./enterprise-iam.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const CLAIM_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseIamDomainClaim", () => {
  test("round-trips a pending_verification row", () => {
    const claim = parseIamDomainClaim({
      id: CLAIM_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, email_domain: "acme.test",
      status: "pending_verification", verification_method: "dns_txt", verification_token: "abc123",
      verification_challenge_host: "_cargogrid-verify.acme.test", requested_by: "admin1",
      verified_at: null, verified_by: null, activated_at: null, activated_by: null,
      disabled_at: null, disabled_by: null, disabled_reason: null,
      rejected_at: null, rejected_by: null, rejected_reason: null,
      expires_at: "2026-08-29T00:00:00.000Z", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(claim.status, "pending_verification");
    assert.equal(claim.emailDomain, "acme.test");
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseIamDomainClaim({
        id: CLAIM_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, email_domain: "acme.test",
        status: "not-a-real-status", verification_method: "dns_txt", verification_token: "abc123",
        verification_challenge_host: "_cargogrid-verify.acme.test", requested_by: null,
        verified_at: null, verified_by: null, activated_at: null, activated_by: null,
        disabled_at: null, disabled_by: null, disabled_reason: null,
        rejected_at: null, rejected_by: null, rejected_reason: null,
        expires_at: "2026-08-29T00:00:00.000Z", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z",
      }),
    );
  });
});

describe("parseIamSsoLoginAttempt", () => {
  test("round-trips a matched attempt", () => {
    const attempt = parseIamSsoLoginAttempt({
      id: CLAIM_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, domain_claim_id: CLAIM_ID,
      subject_claim: "okta|subject-1", email_claim: "person@acme.test", resolved_auth_user_id: ACTOR_ID,
      outcome: "matched", resolved_by_auth_user_id: ACTOR_ID, occurred_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(attempt.outcome, "matched");
    assert.equal(attempt.resolvedAuthUserId, ACTOR_ID);
  });

  test("rejects an unrecognized outcome", () => {
    assert.throws(() =>
      parseIamSsoLoginAttempt({
        id: CLAIM_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, domain_claim_id: null,
        subject_claim: "okta|subject-1", email_claim: null, resolved_auth_user_id: null,
        outcome: "not-a-real-outcome", resolved_by_auth_user_id: ACTOR_ID, occurred_at: "2026-08-22T00:00:00.000Z",
      }),
    );
  });
});

describe("parseIamScimProvisioningEvent", () => {
  test("round-trips an applied create event", () => {
    const event = parseIamScimProvisioningEvent({
      id: CLAIM_ID, tenant_id: TENANT_ID, scim_link_id: CLAIM_ID, api_key_id: null,
      operation: "create", is_dry_run: false, outcome: "applied", outcome_reason: null,
      occurred_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(event.outcome, "applied");
    assert.equal(event.isDryRun, false);
  });

  test("rejects an unrecognized operation", () => {
    assert.throws(() =>
      parseIamScimProvisioningEvent({
        id: CLAIM_ID, tenant_id: TENANT_ID, scim_link_id: CLAIM_ID, api_key_id: null,
        operation: "delete-everything", is_dry_run: false, outcome: "applied", outcome_reason: null,
        occurred_at: "2026-08-22T00:00:00.000Z",
      }),
    );
  });
});

describe("parseEnterpriseIdpByEmailDomain", () => {
  test("round-trips a public resolver row", () => {
    const row = parseEnterpriseIdpByEmailDomain({ connection_id: CONNECTION_ID, protocol: "enterprise_sso_oidc", display_name: "Okta OIDC" });
    assert.equal(row.protocol, "enterprise_sso_oidc");
  });
});

describe("input schemas", () => {
  test("RequestEnterpriseSsoDomainClaimInputSchema rejects an empty email domain", () => {
    assert.throws(() =>
      RequestEnterpriseSsoDomainClaimInputSchema.parse({ tenantId: TENANT_ID, connectionId: CONNECTION_ID, emailDomain: "", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
    );
  });

  test("ResolveEnterpriseSsoClaimsInputSchema accepts a null rawEmailClaim (a malformed/absent IdP claim, never rejected at the contract layer)", () => {
    const parsed = ResolveEnterpriseSsoClaimsInputSchema.parse({
      connectionId: CONNECTION_ID, subjectClaim: "okta|subject-1", rawEmailClaim: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(parsed.rawEmailClaim, null);
  });

  test("ProvisionScimIdentityInputSchema rejects an empty externalId", () => {
    assert.throws(() =>
      ProvisionScimIdentityInputSchema.parse({
        tenantId: TENANT_ID, apiKeyId: null, externalId: "", rawEmail: "a@b.test", displayName: "A", operation: "create",
        isDryRun: false, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("ProvisionScimIdentityInputSchema rejects an unrecognized operation", () => {
    assert.throws(() =>
      ProvisionScimIdentityInputSchema.parse({
        tenantId: TENANT_ID, apiKeyId: null, externalId: "ext-1", rawEmail: "a@b.test", displayName: "A", operation: "delete-everything",
        isDryRun: false, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });
});
