import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { SupportAccessQueryError, currentSupportSession, hasActiveSupportGrant, type SupportAccessRpcClient } from "./support-access.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const GRANT_ID = "323e4567-e89b-12d3-a456-426614174000";

const SESSION_ROW = {
  id: "423e4567-e89b-12d3-a456-426614174000",
  grant_id: GRANT_ID,
  tenant_id: TENANT_ID,
  grantee_auth_user_id: AUTH_USER_ID,
  reauth_confirmed_at: "2026-07-16T00:05:00.000Z",
  started_at: "2026-07-16T00:05:00.000Z",
  ended_at: null,
  ended_reason: null,
  created_at: "2026-07-16T00:05:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): SupportAccessRpcClient & {
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

describe("hasActiveSupportGrant", () => {
  test("passes through a true decision", async () => {
    const client = fakeClient({ data: true, error: null });
    const result = await hasActiveSupportGrant(client, { tenantId: TENANT_ID, authUserId: AUTH_USER_ID });
    assert.equal(result, true);
    assert.equal(client.calls[0]?.fn, "has_active_support_grant");
    assert.equal(client.calls[0]?.args.p_tenant_id, TENANT_ID);
  });

  test("passes through a false decision", async () => {
    const client = fakeClient({ data: false, error: null });
    const result = await hasActiveSupportGrant(client, { tenantId: TENANT_ID, authUserId: AUTH_USER_ID });
    assert.equal(result, false);
  });

  test("throws SupportAccessQueryError on an RPC error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => hasActiveSupportGrant(client, { tenantId: TENANT_ID, authUserId: AUTH_USER_ID }),
      (err: unknown) => {
        assert.ok(err instanceof SupportAccessQueryError);
        return true;
      },
    );
  });

  test("throws SupportAccessQueryError on a non-boolean result", async () => {
    const client = fakeClient({ data: "not-a-boolean", error: null });
    await assert.rejects(() => hasActiveSupportGrant(client, { tenantId: TENANT_ID, authUserId: AUTH_USER_ID }));
  });
});

describe("currentSupportSession", () => {
  test("returns the parsed session when one is open", async () => {
    const client = fakeClient({ data: SESSION_ROW, error: null });
    const session = await currentSupportSession(client, { tenantId: TENANT_ID, authUserId: AUTH_USER_ID });
    assert.ok(session);
    assert.equal(session?.grantId, GRANT_ID);
    assert.equal(session?.endedAt, null);
  });

  test("returns null (not an error) when no session is open -- the normal, majority-case state", async () => {
    const client = fakeClient({ data: null, error: null });
    const session = await currentSupportSession(client, { tenantId: TENANT_ID, authUserId: AUTH_USER_ID });
    assert.equal(session, null);
  });

  test("returns null when the RPC returns an all-null composite row (no matching session)", async () => {
    const client = fakeClient({
      data: { id: null, grant_id: null, tenant_id: null, grantee_auth_user_id: null, reauth_confirmed_at: null, started_at: null, ended_at: null, ended_reason: null, created_at: null },
      error: null,
    });
    const session = await currentSupportSession(client, { tenantId: TENANT_ID, authUserId: AUTH_USER_ID });
    assert.equal(session, null);
  });

  test("throws SupportAccessQueryError on an RPC error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => currentSupportSession(client, { tenantId: TENANT_ID, authUserId: AUTH_USER_ID }),
      (err: unknown) => {
        assert.ok(err instanceof SupportAccessQueryError);
        return true;
      },
    );
  });
});
