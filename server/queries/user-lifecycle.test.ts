import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listTenantUsers, UserLookupError, type UserLookupClient } from "./user-lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const USER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: USER_ID,
  tenant_id: TENANT_ID,
  auth_user_id: "123e4567-e89b-12d3-a456-426614174000",
  display_name: "Admin One",
  status: "active",
  org_unit_id: null,
  invited_by: "tester",
  invited_at: "2026-07-16T00:00:00.000Z",
  invite_expires_at: "2026-07-23T00:00:00.000Z",
  activated_at: "2026-07-16T00:00:00.000Z",
  suspended_at: null,
  suspended_reason: null,
  revoked_at: null,
  revoked_reason: null,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

const DIRECTORY_ROW = { id: USER_ID, email: "admin@example.test", email_masked: false };
const MASKED_DIRECTORY_ROW = { id: USER_ID, email: "a***@example.test", email_masked: true };

type Response = { data: unknown[] | null; error: { message: string } | null };

/** Records the args each RPC was called with, so the tenant/actor scoping can be asserted. */
function fakeClient(
  responses: { users: Response; directory: Response },
  captured?: Record<string, Record<string, unknown>>,
): UserLookupClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      if (captured) captured[fn] = args;
      if (fn === "list_tenant_users") return responses.users;
      return responses.directory;
    },
  } as UserLookupClient;
}

describe("listTenantUsers", () => {
  test("merges the app.list_tenant_users columns with the directory-projection email", async () => {
    const client = fakeClient({
      users: { data: [ROW], error: null },
      directory: { data: [DIRECTORY_ROW], error: null },
    });
    const users = await listTenantUsers(client, TENANT_ID, ACTOR_AUTH_USER_ID);
    assert.equal(users.length, 1);
    assert.equal(users[0]?.status, "active");
    assert.equal(users[0]?.email, "admin@example.test");
    assert.equal(users[0]?.emailMasked, false);
  });

  test("accepts the masked projection, which is not a syntactically valid address", async () => {
    const client = fakeClient({
      users: { data: [ROW], error: null },
      directory: { data: [MASKED_DIRECTORY_ROW], error: null },
    });
    const users = await listTenantUsers(client, TENANT_ID, ACTOR_AUTH_USER_ID);
    assert.equal(users[0]?.email, "a***@example.test");
    assert.equal(users[0]?.emailMasked, true);
  });

  test("calls both RPCs with the tenant id and the actor's own id", async () => {
    const captured: Record<string, Record<string, unknown>> = {};
    const client = fakeClient(
      { users: { data: [], error: null }, directory: { data: [], error: null } },
      captured,
    );
    await listTenantUsers(client, TENANT_ID, ACTOR_AUTH_USER_ID);
    assert.deepEqual(captured.list_tenant_users, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_AUTH_USER_ID });
    assert.deepEqual(captured.list_user_directory_email_projections, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_AUTH_USER_ID });
  });

  test("returns an empty array rather than throwing when a tenant has no users", async () => {
    const client = fakeClient({
      users: { data: [], error: null },
      directory: { data: [], error: null },
    });
    assert.deepEqual(await listTenantUsers(client, TENANT_ID, ACTOR_AUTH_USER_ID), []);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({
      users: { data: null, error: { message: "connection reset" } },
      directory: { data: [], error: null },
    });
    await assert.rejects(() => listTenantUsers(client, TENANT_ID, ACTOR_AUTH_USER_ID), UserLookupError);
  });

  test("wraps a directory-side database error too", async () => {
    const client = fakeClient({
      users: { data: [ROW], error: null },
      directory: { data: null, error: { message: "permission denied" } },
    });
    await assert.rejects(() => listTenantUsers(client, TENANT_ID, ACTOR_AUTH_USER_ID), UserLookupError);
  });

  test("fails loudly rather than inventing an address when the two reads disagree", async () => {
    const client = fakeClient({
      users: { data: [ROW], error: null },
      directory: { data: [], error: null },
    });
    await assert.rejects(() => listTenantUsers(client, TENANT_ID, ACTOR_AUTH_USER_ID), UserLookupError);
  });
});
