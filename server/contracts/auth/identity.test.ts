import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { LinkAuthIdentityInputSchema, RevokeAuthIdentityInputSchema, parseTenantUserIdentity } from "./identity.ts";

describe("LinkAuthIdentityInputSchema", () => {
  test("accepts a well-formed invite and defaults status to invited", () => {
    const parsed = LinkAuthIdentityInputSchema.parse({
      authUserId: "123e4567-e89b-12d3-a456-426614174000",
      tenantId: "223e4567-e89b-12d3-a456-426614174000",
      invitedBy: "supreme-admin-1",
    });
    assert.equal(parsed.status, "invited");
  });

  test("rejects a status other than invited/active (a fresh link can never start revoked)", () => {
    assert.throws(() =>
      LinkAuthIdentityInputSchema.parse({
        authUserId: "123e4567-e89b-12d3-a456-426614174000",
        tenantId: "223e4567-e89b-12d3-a456-426614174000",
        invitedBy: "x",
        status: "revoked",
      }),
    );
  });

  test("rejects a non-UUID authUserId", () => {
    assert.throws(() => LinkAuthIdentityInputSchema.parse({ authUserId: "not-a-uuid", tenantId: "223e4567-e89b-12d3-a456-426614174000", invitedBy: "x" }));
  });
});

describe("RevokeAuthIdentityInputSchema", () => {
  test("requires a non-empty reason (Prompt 107 §22/§24: revocation must be reasoned and audited)", () => {
    assert.throws(() =>
      RevokeAuthIdentityInputSchema.parse({ authUserId: "123e4567-e89b-12d3-a456-426614174000", tenantId: "223e4567-e89b-12d3-a456-426614174000", reason: "", requestedBy: "x" }),
    );
  });
});

describe("parseTenantUserIdentity", () => {
  test("maps a real snake_case Postgres row to the camelCase contract shape", () => {
    const identity = parseTenantUserIdentity({
      id: "323e4567-e89b-12d3-a456-426614174000",
      auth_user_id: "123e4567-e89b-12d3-a456-426614174000",
      tenant_id: "223e4567-e89b-12d3-a456-426614174000",
      status: "invited",
      invited_by: "supreme-admin-1",
      invited_at: "2026-07-16T00:00:00.000Z",
      activated_at: null,
      revoked_at: null,
      revoked_reason: null,
      mfa_enrolled: false,
      record_version: 1,
      created_at: "2026-07-16T00:00:00.000Z",
      updated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(identity.status, "invited");
    assert.equal(identity.mfaEnrolled, false);
  });
});
