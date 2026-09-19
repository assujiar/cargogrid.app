import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listPortalUsers, PortalUsersQueryError } from "./portal-users.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACTOR_AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";

function rowsWithTotal(rows: { id: string; display_name: string; status: string; email: string; email_masked: boolean }[], totalCount: number) {
  return rows.map((row) => ({ ...row, total_count: totalCount }));
}

const ROWS = rowsWithTotal(
  [
    { id: "223e4567-e89b-12d3-a456-426614174000", display_name: "Ada Lovelace", status: "active", email: "a***@example.test", email_masked: true },
    { id: "323e4567-e89b-12d3-a456-426614174000", display_name: "Bob Marley", status: "invited", email: "b***@example.test", email_masked: true },
  ],
  2,
);

interface FakeQueryState {
  readonly calls: { fn: string; args: Record<string, unknown> }[];
}

function fakeClient(response: { data: unknown[] | null; error: { message: string } | null }, state: FakeQueryState) {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      state.calls.push({ fn, args });
      return response;
    },
  };
}

describe("listPortalUsers", () => {
  test("returns typed users and total count on success", async () => {
    const state: FakeQueryState = { calls: [] };
    const client = fakeClient({ data: ROWS, error: null }, state);
    const result = await listPortalUsers(client as never, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_AUTH_USER_ID, page: 1, pageSize: 20 });

    assert.equal(result.users.length, 2);
    assert.equal(result.users[0]?.displayName, "Ada Lovelace");
    assert.equal(result.totalCount, 2);
  });

  test("calls list_portal_users with the given tenant_id and actor id (never merges another tenant's users)", async () => {
    const state: FakeQueryState = { calls: [] };
    const client = fakeClient({ data: ROWS, error: null }, state);
    await listPortalUsers(client as never, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_AUTH_USER_ID, page: 1, pageSize: 20 });

    assert.equal(state.calls[0]?.fn, "list_portal_users");
    assert.equal(state.calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(state.calls[0]?.args.p_actor_auth_user_id, ACTOR_AUTH_USER_ID);
  });

  test("clamps an over-limit pageSize to the governed maximum of 100", async () => {
    const state: FakeQueryState = { calls: [] };
    const client = fakeClient({ data: [], error: null }, state);
    const result = await listPortalUsers(client as never, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_AUTH_USER_ID, page: 1, pageSize: 5000 });

    assert.equal(result.pageSize, 100);
    assert.equal(state.calls[0]?.args.p_page_size, 100);
  });

  test("clamps a zero/negative pageSize up to 1", async () => {
    const state: FakeQueryState = { calls: [] };
    const client = fakeClient({ data: [], error: null }, state);
    const result = await listPortalUsers(client as never, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_AUTH_USER_ID, page: 1, pageSize: 0 });

    assert.equal(result.pageSize, 1);
  });

  test("passes the requested page through to the RPC", async () => {
    const state: FakeQueryState = { calls: [] };
    const client = fakeClient({ data: [], error: null }, state);
    await listPortalUsers(client as never, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_AUTH_USER_ID, page: 2, pageSize: 20 });

    assert.equal(state.calls[0]?.args.p_page, 2);
    assert.equal(state.calls[0]?.args.p_page_size, 20);
  });

  test("wraps a database error into PortalUsersQueryError", async () => {
    const state: FakeQueryState = { calls: [] };
    const client = fakeClient({ data: null, error: { message: "connection reset" } }, state);
    await assert.rejects(
      () => listPortalUsers(client as never, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_AUTH_USER_ID, page: 1, pageSize: 20 }),
      PortalUsersQueryError,
    );
  });

  test("returns an empty list and zero total, not an error, for a tenant with zero users", async () => {
    const state: FakeQueryState = { calls: [] };
    const client = fakeClient({ data: [], error: null }, state);
    const result = await listPortalUsers(client as never, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_AUTH_USER_ID, page: 1, pageSize: 20 });

    assert.deepEqual(result.users, []);
    assert.equal(result.totalCount, 0);
  });
});
