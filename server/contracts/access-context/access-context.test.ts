import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  GrantPrincipalMembershipInputSchema,
  ResolveAccessContextInputSchema,
  parseAccessContext,
  parsePrincipalMembership,
} from "./access-context.ts";

describe("parsePrincipalMembership", () => {
  test("maps a snake_case row to the camelCase contract shape", () => {
    const membership = parsePrincipalMembership({
      id: "323e4567-e89b-12d3-a456-426614174000",
      auth_user_id: "123e4567-e89b-12d3-a456-426614174000",
      layer: "tenant_admin",
      tenant_id: "223e4567-e89b-12d3-a456-426614174000",
      customer_account_ref: null,
      status: "active",
      granted_by: "tester",
      granted_at: "2026-07-16T00:00:00.000Z",
      revoked_at: null,
      revoked_reason: null,
      record_version: 1,
      created_at: "2026-07-16T00:00:00.000Z",
      updated_at: "2026-07-16T00:00:00.000Z",
    });

    assert.equal(membership.authUserId, "123e4567-e89b-12d3-a456-426614174000");
    assert.equal(membership.layer, "tenant_admin");
    assert.equal(membership.customerAccountRef, null);
  });

  test("rejects an unknown layer -- the four layers are closed, not open-ended", () => {
    assert.throws(() =>
      parsePrincipalMembership({
        id: "323e4567-e89b-12d3-a456-426614174000",
        auth_user_id: "123e4567-e89b-12d3-a456-426614174000",
        layer: "billing_admin",
        tenant_id: null,
        customer_account_ref: null,
        status: "active",
        granted_by: "tester",
        granted_at: "2026-07-16T00:00:00.000Z",
        revoked_at: null,
        revoked_reason: null,
        record_version: 1,
        created_at: "2026-07-16T00:00:00.000Z",
        updated_at: "2026-07-16T00:00:00.000Z",
      }),
    );
  });
});

describe("parseAccessContext", () => {
  test("maps a resolved app.access_context composite (snake_case) to the camelCase contract shape", () => {
    const ctx = parseAccessContext({
      membership_id: "323e4567-e89b-12d3-a456-426614174000",
      auth_user_id: "123e4567-e89b-12d3-a456-426614174000",
      layer: "supreme_admin",
      tenant_id: null,
      customer_account_ref: null,
      resolved_at: "2026-07-16T00:00:00.000Z",
    });

    assert.equal(ctx.layer, "supreme_admin");
    assert.equal(ctx.tenantId, null);
  });
});

describe("ResolveAccessContextInputSchema", () => {
  test("defaults tenantId and customerAccountRef to null when omitted", () => {
    const parsed = ResolveAccessContextInputSchema.parse({ authUserId: "123e4567-e89b-12d3-a456-426614174000" });
    assert.equal(parsed.tenantId, null);
    assert.equal(parsed.customerAccountRef, null);
  });
});

describe("GrantPrincipalMembershipInputSchema", () => {
  test("accepts a global supreme_admin grant with no tenant/customer scope", () => {
    const parsed = GrantPrincipalMembershipInputSchema.parse({
      authUserId: "123e4567-e89b-12d3-a456-426614174000",
      layer: "supreme_admin",
      grantedBy: "tester",
    });
    assert.equal(parsed.layer, "supreme_admin");
    assert.equal(parsed.tenantId, null);
  });

  test("rejects an unknown layer at the contract boundary, before any RPC call", () => {
    assert.throws(() =>
      GrantPrincipalMembershipInputSchema.parse({
        authUserId: "123e4567-e89b-12d3-a456-426614174000",
        layer: "billing_admin",
        grantedBy: "tester",
      }),
    );
  });
});
