import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { grantPrincipalMembership, revokePrincipalMembership, PrincipalMembershipMutationError, type PrincipalMembershipRpcClient } from "./access-context.ts";

const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const MEMBERSHIP_ID = "323e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: MEMBERSHIP_ID,
  auth_user_id: AUTH_USER_ID,
  layer: "org_user",
  tenant_id: TENANT_ID,
  customer_account_ref: null,
  status: "active",
  granted_by: "tester",
  granted_at: "2026-07-16T00:00:00.000Z",
  revoked_at: null,
  revoked_reason: null,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): PrincipalMembershipRpcClient & {
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("grantPrincipalMembership", () => {
  test("calls grant_principal_membership with the exact snake_case params the SQL function expects", async () => {
    const client = fakeClient({ data: ROW, error: null });
    await grantPrincipalMembership(client, { authUserId: AUTH_USER_ID, layer: "org_user", tenantId: TENANT_ID, grantedBy: "tester" });

    assert.equal(client.calls[0]?.fn, "grant_principal_membership");
    assert.equal(client.calls[0]?.args.p_layer, "org_user");
    assert.equal(client.calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(client.calls[0]?.args.p_customer_account_ref, null);
  });

  test("wraps a database error (e.g. the layer/scope shape check) into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "new row for relation \"principal_memberships\" violates check constraint \"principal_memberships_layer_scope_shape\"" } });
    await assert.rejects(
      () => grantPrincipalMembership(client, { authUserId: AUTH_USER_ID, layer: "supreme_admin", tenantId: TENANT_ID, grantedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof PrincipalMembershipMutationError);
        assert.equal(err.code, "grant_failed");
        return true;
      },
    );
  });
});

describe("revokePrincipalMembership", () => {
  test("calls revoke_principal_membership with the exact snake_case params the SQL function expects", async () => {
    const client = fakeClient({ data: { ...ROW, status: "revoked" }, error: null });
    await revokePrincipalMembership(client, { membershipId: MEMBERSHIP_ID, reason: "role change", requestedBy: "tester" });

    assert.equal(client.calls[0]?.fn, "revoke_principal_membership");
    assert.equal(client.calls[0]?.args.p_membership_id, MEMBERSHIP_ID);
    assert.equal(client.calls[0]?.args.p_reason, "role change");
  });

  test("wraps a database error (e.g. a non-existent membership) into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "principal_membership_not_found" } });
    await assert.rejects(
      () => revokePrincipalMembership(client, { membershipId: MEMBERSHIP_ID, reason: "x", requestedBy: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof PrincipalMembershipMutationError);
        assert.equal(err.code, "revoke_failed");
        return true;
      },
    );
  });
});
