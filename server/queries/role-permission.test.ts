import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listPermissionsForModule, listTenantRoles, RolePermissionLookupError, type RolePermissionLookupClient } from "./role-permission.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";

const PERMISSION_ROW = {
  id: "323e4567-e89b-12d3-a456-426614174000",
  action: "View",
  resource_module_code: "FIN",
  category: "standard",
  protected: false,
  code: "FIN:View",
  created_at: "2026-07-16T00:00:00.000Z",
};

const ROLE_ROW = {
  id: "423e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  name: "Finance Approver",
  description: null,
  status: "active",
  created_by: "tester",
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown[] | null; error: { message: string } | null },
  capture?: { calls: { fn: string; args: Record<string, unknown> }[] },
): RolePermissionLookupClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture?.calls.push({ fn, args });
      return response;
    },
  } as RolePermissionLookupClient;
}

describe("listPermissionsForModule", () => {
  test("calls list_permissions_for_module with the module code and actor id, maps every row", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeClient({ data: [PERMISSION_ROW], error: null }, capture);
    const permissions = await listPermissionsForModule(client, "FIN", ACTOR_AUTH_USER_ID);
    assert.equal(capture.calls[0]?.fn, "list_permissions_for_module");
    assert.deepEqual(capture.calls[0]?.args, { p_resource_module_code: "FIN", p_actor_auth_user_id: ACTOR_AUTH_USER_ID });
    assert.equal(permissions.length, 1);
    assert.equal(permissions[0]?.resourceModuleCode, "FIN");
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listPermissionsForModule(client, "FIN", ACTOR_AUTH_USER_ID), RolePermissionLookupError);
  });
});

describe("listTenantRoles", () => {
  test("calls list_tenant_roles with the tenant and actor id, maps every role row", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeClient({ data: [ROLE_ROW], error: null }, capture);
    const roles = await listTenantRoles(client, TENANT_ID, ACTOR_AUTH_USER_ID);
    assert.equal(capture.calls[0]?.fn, "list_tenant_roles");
    assert.deepEqual(capture.calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_AUTH_USER_ID });
    assert.equal(roles.length, 1);
    assert.equal(roles[0]?.name, "Finance Approver");
  });

  test("returns an empty array rather than throwing when a tenant has no roles", async () => {
    const client = fakeClient({ data: [], error: null });
    const roles = await listTenantRoles(client, TENANT_ID, ACTOR_AUTH_USER_ID);
    assert.deepEqual(roles, []);
  });
});
