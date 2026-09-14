import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listPermissionsForModule,
  listTenantRoles,
  listRoleVersions,
  listRoleVersionPermissions,
  listRoleAssignmentsForRole,
  listActiveTenantUsersForRoleAssignment,
  RolePermissionLookupError,
  type RolePermissionLookupClient,
} from "./role-permission.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ROLE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ROLE_VERSION_ID = "623e4567-e89b-12d3-a456-426614174000";

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

const ROLE_VERSION_ROW = {
  id: ROLE_VERSION_ID,
  role_id: ROLE_ID,
  version_number: 2,
  status: "published",
  effective_from: "2026-09-14T00:00:00.000Z",
  cloned_from_version_id: null,
  created_by: "tester",
  published_by: "tester",
  published_at: "2026-09-14T00:00:00.000Z",
  archived_at: null,
  archived_reason: null,
  record_version: 1,
  created_at: "2026-09-14T00:00:00.000Z",
  updated_at: "2026-09-14T00:00:00.000Z",
};

const ROLE_ASSIGNMENT_ROW = {
  id: "723e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  role_version_id: ROLE_VERSION_ID,
  auth_user_id: ACTOR_AUTH_USER_ID,
  status: "active",
  granted_by: "tester",
  granted_at: "2026-09-14T00:00:00.000Z",
  revoked_at: null,
  revoked_reason: null,
  record_version: 1,
  created_at: "2026-09-14T00:00:00.000Z",
  updated_at: "2026-09-14T00:00:00.000Z",
};

describe("listRoleVersions", () => {
  test("calls list_role_versions with only the role id (no actor param -- relies on live RLS)", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeClient({ data: [ROLE_VERSION_ROW], error: null }, capture);
    const versions = await listRoleVersions(client, ROLE_ID);
    assert.equal(capture.calls[0]?.fn, "list_role_versions");
    assert.deepEqual(capture.calls[0]?.args, { p_role_id: ROLE_ID });
    assert.equal(versions[0]?.versionNumber, 2);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listRoleVersions(client, ROLE_ID), RolePermissionLookupError);
  });
});

describe("listRoleVersionPermissions", () => {
  test("calls list_role_version_permissions with the version and actor id", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeClient({ data: [PERMISSION_ROW], error: null }, capture);
    const permissions = await listRoleVersionPermissions(client, ROLE_VERSION_ID, ACTOR_AUTH_USER_ID);
    assert.equal(capture.calls[0]?.fn, "list_role_version_permissions");
    assert.deepEqual(capture.calls[0]?.args, { p_role_version_id: ROLE_VERSION_ID, p_actor_auth_user_id: ACTOR_AUTH_USER_ID });
    assert.equal(permissions[0]?.code, "FIN:View");
  });
});

describe("listRoleAssignmentsForRole", () => {
  test("calls list_role_assignments_for_role with only the role id (no actor param -- relies on live RLS)", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeClient({ data: [ROLE_ASSIGNMENT_ROW], error: null }, capture);
    const assignments = await listRoleAssignmentsForRole(client, ROLE_ID);
    assert.equal(capture.calls[0]?.fn, "list_role_assignments_for_role");
    assert.deepEqual(capture.calls[0]?.args, { p_role_id: ROLE_ID });
    assert.equal(assignments[0]?.status, "active");
  });
});

describe("listActiveTenantUsersForRoleAssignment", () => {
  test("calls list_active_tenant_users_for_role_assignment with the tenant and actor id, maps auth_user_id/display_name", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeClient({ data: [{ auth_user_id: ACTOR_AUTH_USER_ID, display_name: "Ada Lovelace" }], error: null }, capture);
    const candidates = await listActiveTenantUsersForRoleAssignment(client, TENANT_ID, ACTOR_AUTH_USER_ID);
    assert.equal(capture.calls[0]?.fn, "list_active_tenant_users_for_role_assignment");
    assert.deepEqual(capture.calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_AUTH_USER_ID });
    assert.deepEqual(candidates, [{ authUserId: ACTOR_AUTH_USER_ID, displayName: "Ada Lovelace" }]);
  });
});
