import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listPermissionsForModule, listTenantRoles, RolePermissionLookupError, type RolePermissionLookupClient } from "./role-permission.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

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

function fakeClient(response: { data: unknown[] | null; error: { message: string } | null }): RolePermissionLookupClient {
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

describe("listPermissionsForModule", () => {
  test("maps every permission row", async () => {
    const client = fakeClient({ data: [PERMISSION_ROW], error: null });
    const permissions = await listPermissionsForModule(client, "FIN");
    assert.equal(permissions.length, 1);
    assert.equal(permissions[0]?.resourceModuleCode, "FIN");
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listPermissionsForModule(client, "FIN"), RolePermissionLookupError);
  });
});

describe("listTenantRoles", () => {
  test("maps every role row", async () => {
    const client = fakeClient({ data: [ROLE_ROW], error: null });
    const roles = await listTenantRoles(client, TENANT_ID);
    assert.equal(roles.length, 1);
    assert.equal(roles[0]?.name, "Finance Approver");
  });

  test("returns an empty array rather than throwing when a tenant has no roles", async () => {
    const client = fakeClient({ data: [], error: null });
    const roles = await listTenantRoles(client, TENANT_ID);
    assert.deepEqual(roles, []);
  });
});
