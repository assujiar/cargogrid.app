import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listTenantUsers, UserLookupError, type UserLookupClient } from "./user-lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: "323e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  auth_user_id: "123e4567-e89b-12d3-a456-426614174000",
  email: "admin@example.test",
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

function fakeClient(response: { data: unknown[] | null; error: { message: string } | null }): UserLookupClient {
  return {
    from() {
      return {
        select() {
          return {
            async eq() {
              return response;
            },
          };
        },
      };
    },
  };
}

describe("listTenantUsers", () => {
  test("maps every row in the response", async () => {
    const client = fakeClient({ data: [ROW], error: null });
    const users = await listTenantUsers(client, TENANT_ID);
    assert.equal(users.length, 1);
    assert.equal(users[0]?.status, "active");
  });

  test("returns an empty array rather than throwing when a tenant has no users", async () => {
    const client = fakeClient({ data: [], error: null });
    const users = await listTenantUsers(client, TENANT_ID);
    assert.deepEqual(users, []);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listTenantUsers(client, TENANT_ID), UserLookupError);
  });
});
