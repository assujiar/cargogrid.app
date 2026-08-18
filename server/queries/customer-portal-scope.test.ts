import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  resolveCustomerAccountScope,
  getCustomerPortalScopeContext,
  listCustomerPortalAccountMemberships,
  CustomerPortalScopeQueryError,
  type CustomerPortalScopeQueryClient,
} from "./customer-portal-scope.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const MEMBERSHIP_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalScopeQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalScopeQueryClient;
  return { client, calls };
}

describe("resolveCustomerAccountScope", () => {
  test("returns the RPC's own array and passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [ACCOUNT_ID], error: null });
    const result = await resolveCustomerAccountScope(client, AUTH_USER_ID, TENANT_ID);
    assert.deepEqual(result, [ACCOUNT_ID]);
    assert.deepEqual(calls[0], {
      fn: "resolve_customer_account_scope",
      args: { p_auth_user_id: AUTH_USER_ID, p_tenant_id: TENANT_ID },
    });
  });

  test("returns an empty array when the RPC returns null (never throws for an empty scope)", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await resolveCustomerAccountScope(client, AUTH_USER_ID, TENANT_ID);
    assert.deepEqual(result, []);
  });

  test("throws on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "unexpected: boom" } });
    await assert.rejects(() => resolveCustomerAccountScope(client, AUTH_USER_ID, TENANT_ID), CustomerPortalScopeQueryError);
  });
});

describe("getCustomerPortalScopeContext", () => {
  test("maps every returned row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ account_id: ACCOUNT_ID, account_name: "Acme Logistics", role: "account_admin", is_primary: true }],
      error: null,
    });
    const result = await getCustomerPortalScopeContext(client, AUTH_USER_ID, TENANT_ID);
    assert.equal(result.length, 1);
    assert.equal(result[0]?.accountName, "Acme Logistics");
    assert.deepEqual(calls[0]?.args, { p_auth_user_id: AUTH_USER_ID, p_tenant_id: TENANT_ID });
  });

  test("returns an empty array (never throws) when the RPC returns zero rows -- deny-by-default for a non-customer_user actor", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await getCustomerPortalScopeContext(client, AUTH_USER_ID, TENANT_ID);
    assert.deepEqual(result, []);
  });
});

describe("listCustomerPortalAccountMemberships", () => {
  const MEMBERSHIP_ROW = {
    id: MEMBERSHIP_ID,
    tenant_id: TENANT_ID,
    auth_user_id: AUTH_USER_ID,
    account_id: ACCOUNT_ID,
    role: "member",
    status: "active",
    invited_by: "admin",
    invited_at: "2026-08-01T00:00:00.000Z",
    accepted_at: "2026-08-01T00:05:00.000Z",
    granted_by: "admin",
    granted_at: "2026-08-01T00:00:00.000Z",
    suspended_by: null,
    suspended_at: null,
    suspended_reason: null,
    revoked_by: null,
    revoked_at: null,
    revoked_reason: null,
    record_version: 1,
    created_at: "2026-08-01T00:00:00.000Z",
    updated_at: "2026-08-01T00:05:00.000Z",
  };

  test("defaults cursor to null and limit to 50, forwards the actor id", async () => {
    const { client, calls } = fakeRpcClient({ data: [MEMBERSHIP_ROW], error: null });
    const result = await listCustomerPortalAccountMemberships(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_account_id: ACCOUNT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("forwards cursor/limit overrides", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalAccountMemberships(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID, { cursorUpdatedAt: "2026-08-01T00:00:00.000Z", cursorId: MEMBERSHIP_ID, limit: 10 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_account_id: ACCOUNT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_cursor_updated_at: "2026-08-01T00:00:00.000Z",
      p_cursor_id: MEMBERSHIP_ID,
      p_limit: 10,
    });
  });

  test("returns an empty array (never throws) for a non-admin caller", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerPortalAccountMemberships(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});
