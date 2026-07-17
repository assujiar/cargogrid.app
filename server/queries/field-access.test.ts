import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  canAccessRecord,
  listUserDirectory,
  RecordAccessCheckError,
  UserDirectoryLookupError,
  type FieldAccessRpcClient,
  type UserDirectoryLookupClient,
} from "./field-access.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): FieldAccessRpcClient & {
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

describe("canAccessRecord", () => {
  test("calls can_access_record with the exact snake_case params, defaulting the optional fields", async () => {
    const client = fakeRpcClient({ data: true, error: null });
    const allowed = await canAccessRecord(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, ownerUserId: OWNER_ID });

    assert.equal(client.calls[0]?.fn, "can_access_record");
    assert.deepEqual(client.calls[0]?.args.p_shared_org_unit_ids, []);
    assert.equal(client.calls[0]?.args.p_customer_account_ref, null);
    assert.equal(allowed, true);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => canAccessRecord(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, ownerUserId: OWNER_ID }), RecordAccessCheckError);
  });

  test("rejects a non-boolean success response rather than fabricating a decision", async () => {
    const client = fakeRpcClient({ data: "true", error: null });
    await assert.rejects(() => canAccessRecord(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, ownerUserId: OWNER_ID }), RecordAccessCheckError);
  });
});

function fakeDirectoryClient(response: { data: unknown[] | null; error: { message: string } | null }): UserDirectoryLookupClient {
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

describe("listUserDirectory", () => {
  test("maps every row, including the emailMasked flag", async () => {
    const client = fakeDirectoryClient({
      data: [
        {
          id: "423e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          auth_user_id: AUTH_USER_ID,
          display_name: "Jane Doe",
          status: "active",
          org_unit_id: null,
          email: "j***@example.test",
          email_masked: true,
          created_at: "2026-07-16T00:00:00.000Z",
          updated_at: "2026-07-16T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const entries = await listUserDirectory(client, TENANT_ID);
    assert.equal(entries.length, 1);
    assert.equal(entries[0]?.emailMasked, true);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeDirectoryClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listUserDirectory(client, TENANT_ID), UserDirectoryLookupError);
  });
});
