import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { linkAuthIdentity, revokeAuthIdentity, IdentityMutationError, type IdentityRpcClient } from "./auth-identity.ts";

const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: "323e4567-e89b-12d3-a456-426614174000",
  auth_user_id: AUTH_USER_ID,
  tenant_id: TENANT_ID,
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
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): IdentityRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("linkAuthIdentity", () => {
  test("calls link_auth_identity with the exact snake_case params the SQL function expects", async () => {
    const client = fakeClient({ data: ROW, error: null });
    await linkAuthIdentity(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, invitedBy: "supreme-admin-1" });

    assert.equal(client.calls[0]?.fn, "link_auth_identity");
    assert.equal(client.calls[0]?.args.p_auth_user_id, AUTH_USER_ID);
    assert.equal(client.calls[0]?.args.p_status, "invited");
  });

  test("wraps a database error into a typed IdentityMutationError", async () => {
    const client = fakeClient({ data: null, error: { message: "foreign key violation" } });
    await assert.rejects(
      () => linkAuthIdentity(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, invitedBy: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof IdentityMutationError);
        assert.equal(err.code, "link_failed");
        return true;
      },
    );
  });
});

describe("revokeAuthIdentity", () => {
  test("calls revoke_auth_identity with the exact snake_case params the SQL function expects", async () => {
    const client = fakeClient({ data: { ...ROW, status: "revoked" }, error: null });
    await revokeAuthIdentity(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, reason: "offboarded", requestedBy: "supreme-admin-1" });

    assert.equal(client.calls[0]?.fn, "revoke_auth_identity");
    assert.equal(client.calls[0]?.args.p_reason, "offboarded");
  });

  test("wraps a database error (e.g. a non-existent linkage) into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "identity_link_not_found" } });
    await assert.rejects(
      () => revokeAuthIdentity(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, reason: "x", requestedBy: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof IdentityMutationError);
        assert.equal(err.code, "revoke_failed");
        return true;
      },
    );
  });
});
