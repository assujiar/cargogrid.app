import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listTenantUsers, UserLookupError, type UserLookupClient } from "./user-lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const USER_ID = "323e4567-e89b-12d3-a456-426614174000";

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

/** Records which columns each table was asked for, so the grant contract can be asserted. */
function fakeClient(
  responses: { users: Response; users_directory: Response },
  requested?: Record<string, string>,
): UserLookupClient {
  return {
    from(table) {
      return {
        select(columns) {
          if (requested) requested[table] = columns;
          return {
            async eq() {
              return responses[table];
            },
          };
        },
      };
    },
  };
}

describe("listTenantUsers", () => {
  test("merges the granted app.users columns with the app.users_directory email", async () => {
    const client = fakeClient({
      users: { data: [ROW], error: null },
      users_directory: { data: [DIRECTORY_ROW], error: null },
    });
    const users = await listTenantUsers(client, TENANT_ID);
    assert.equal(users.length, 1);
    assert.equal(users[0]?.status, "active");
    assert.equal(users[0]?.email, "admin@example.test");
    assert.equal(users[0]?.emailMasked, false);
  });

  test("accepts the masked projection, which is not a syntactically valid address", async () => {
    const client = fakeClient({
      users: { data: [ROW], error: null },
      users_directory: { data: [MASKED_DIRECTORY_ROW], error: null },
    });
    const users = await listTenantUsers(client, TENANT_ID);
    assert.equal(users[0]?.email, "a***@example.test");
    assert.equal(users[0]?.emailMasked, true);
  });

  test("never asks app.users for `*` -- authenticated has no grant on the email column", async () => {
    const requested: Record<string, string> = {};
    const client = fakeClient(
      { users: { data: [], error: null }, users_directory: { data: [], error: null } },
      requested,
    );
    await listTenantUsers(client, TENANT_ID);
    assert.equal(requested.users?.includes("*"), false);
    assert.equal(requested.users?.includes("email"), false);
    // Exactly the 17 columns 20260716110430_create_field_record_access.sql re-grants.
    assert.equal(requested.users?.split(",").length, 17);
  });

  test("returns an empty array rather than throwing when a tenant has no users", async () => {
    const client = fakeClient({
      users: { data: [], error: null },
      users_directory: { data: [], error: null },
    });
    assert.deepEqual(await listTenantUsers(client, TENANT_ID), []);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({
      users: { data: null, error: { message: "connection reset" } },
      users_directory: { data: [], error: null },
    });
    await assert.rejects(() => listTenantUsers(client, TENANT_ID), UserLookupError);
  });

  test("wraps a directory-side database error too", async () => {
    const client = fakeClient({
      users: { data: [ROW], error: null },
      users_directory: { data: null, error: { message: "permission denied" } },
    });
    await assert.rejects(() => listTenantUsers(client, TENANT_ID), UserLookupError);
  });

  test("fails loudly rather than inventing an address when the two reads disagree", async () => {
    const client = fakeClient({
      users: { data: [ROW], error: null },
      users_directory: { data: [], error: null },
    });
    await assert.rejects(() => listTenantUsers(client, TENANT_ID), UserLookupError);
  });
});
