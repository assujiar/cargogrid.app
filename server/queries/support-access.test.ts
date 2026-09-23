import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { SupportAccessQueryError, currentSupportSession, hasActiveSupportGrant, listSupportAccessGrantsForAdmin, type SupportAccessRpcClient } from "./support-access.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const GRANT_ID = "323e4567-e89b-12d3-a456-426614174000";

const GRANT_ROW = {
  id: GRANT_ID,
  tenant_id: TENANT_ID,
  grantee_auth_user_id: AUTH_USER_ID,
  reason: "customer cannot see invoices",
  case_id: "CASE-100",
  scope: "read_only",
  emergency: false,
  status: "pending_approval",
  requested_by: "tester",
  requested_at: "2026-07-16T00:00:00.000Z",
  authorized_by_auth_user_id: null,
  approved_by: null,
  granted_at: null,
  denied_by: null,
  denied_at: null,
  denial_reason: null,
  expires_at: "2026-07-17T00:00:00.000Z",
  revoked_at: null,
  revoked_by: null,
  revoked_reason: null,
  post_review_completed_at: null,
  post_review_by: null,
  post_review_note: null,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
  total_count: 2,
};

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

describe("listSupportAccessGrantsForAdmin", () => {
  test("parses the row set and reads total_count from the first row", async () => {
    const client = fakeClient({ data: [GRANT_ROW], error: null });
    const result = await listSupportAccessGrantsForAdmin(client, { page: 1, pageSize: 20 });
    assert.equal(result.grants.length, 1);
    assert.equal(result.grants[0]?.id, GRANT_ID);
    assert.equal(result.totalCount, 2);
    assert.equal(result.page, 1);
    assert.equal(result.pageSize, 20);
    assert.equal(client.calls[0]?.fn, "list_support_access_grants_for_admin");
    assert.equal(client.calls[0]?.args.p_page, 1);
    assert.equal(client.calls[0]?.args.p_page_size, 20);
  });

  test("returns an empty result (totalCount 0) for zero rows, not an error", async () => {
    const client = fakeClient({ data: [], error: null });
    const result = await listSupportAccessGrantsForAdmin(client, { page: 1, pageSize: 20 });
    assert.deepEqual(result.grants, []);
    assert.equal(result.totalCount, 0);
  });

  test("clamps pageSize to [1, 100] and page to >= 1", async () => {
    const client = fakeClient({ data: [], error: null });
    await listSupportAccessGrantsForAdmin(client, { page: 0, pageSize: 500 });
    assert.equal(client.calls[0]?.args.p_page, 1);
    assert.equal(client.calls[0]?.args.p_page_size, 100);
  });

  test("throws SupportAccessQueryError on an RPC error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => listSupportAccessGrantsForAdmin(client, { page: 1, pageSize: 20 }),
      (err: unknown) => {
        assert.ok(err instanceof SupportAccessQueryError);
        return true;
      },
    );
  });
});
