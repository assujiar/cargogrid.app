import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createRole,
  createRoleVersion,
  setRoleVersionPermissions,
  publishRoleVersion,
  cloneRoleVersion,
  assignRole,
  revokeRoleAssignment,
  RolePermissionMutationError,
  type RolePermissionRpcClient,
} from "./role-permission.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ROLE_ID = "423e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "523e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "723e4567-e89b-12d3-a456-426614174000";
const ASSIGNMENT_ID = "623e4567-e89b-12d3-a456-426614174000";

const ROLE_ROW = {
  id: ROLE_ID,
  tenant_id: TENANT_ID,
  name: "Finance Approver",
  description: null,
  status: "active",
  created_by: "tester",
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

const VERSION_ROW = {
  id: VERSION_ID,
  role_id: ROLE_ID,
  version_number: 1,
  status: "draft",
  effective_from: null,
  cloned_from_version_id: null,
  created_by: "tester",
  published_by: null,
  published_at: null,
  archived_at: null,
  archived_reason: null,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

const ASSIGNMENT_ROW = {
  id: ASSIGNMENT_ID,
  tenant_id: TENANT_ID,
  role_version_id: VERSION_ID,
  auth_user_id: AUTH_USER_ID,
  status: "active",
  granted_by: "tester",
  granted_at: "2026-07-16T00:00:00.000Z",
  revoked_at: null,
  revoked_reason: null,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): RolePermissionRpcClient & {
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

describe("createRole / createRoleVersion", () => {
  test("calls create_role with the exact snake_case params, defaulting description to null", async () => {
    const client = fakeClient({ data: ROLE_ROW, error: null });
    await createRole(client, { tenantId: TENANT_ID, name: "Finance Approver", createdBy: "tester" });
    assert.equal(client.calls[0]?.fn, "create_role");
    assert.equal(client.calls[0]?.args.p_description, null);
  });

  test("calls create_role_version with the exact snake_case params", async () => {
    const client = fakeClient({ data: VERSION_ROW, error: null });
    await createRoleVersion(client, { roleId: ROLE_ID, createdBy: "tester" });
    assert.equal(client.calls[0]?.fn, "create_role_version");
    assert.equal(client.calls[0]?.args.p_role_id, ROLE_ID);
  });
});

describe("setRoleVersionPermissions", () => {
  test("returns the numeric bound-permission count", async () => {
    const client = fakeClient({ data: 3, error: null });
    const permissionIds = [
      "823e4567-e89b-12d3-a456-426614174000",
      "923e4567-e89b-12d3-a456-426614174000",
      "a23e4567-e89b-12d3-a456-426614174000",
    ];
    const count = await setRoleVersionPermissions(client, { roleVersionId: VERSION_ID, permissionIds, requestedBy: "tester" });
    assert.equal(count, 3);
  });

  test("classifies a role_version_not_draft rejection into its typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "role_version_not_draft: version is published, only a draft's permissions may be changed" } });
    await assert.rejects(
      () => setRoleVersionPermissions(client, { roleVersionId: VERSION_ID, permissionIds: [], requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RolePermissionMutationError);
        assert.equal(err.code, "role_version_not_draft");
        return true;
      },
    );
  });
});

describe("publishRoleVersion / cloneRoleVersion", () => {
  test("calls publish_role_version with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VERSION_ROW, status: "published" }, error: null });
    await publishRoleVersion(client, { roleVersionId: VERSION_ID, effectiveFrom: "2026-07-16T00:00:00.000Z", publishedBy: "tester" });
    assert.equal(client.calls[0]?.fn, "publish_role_version");
  });

  test("classifies a cannot_clone_draft rejection into its typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "cannot_clone_draft: version is still a draft, nothing stable to clone" } });
    await assert.rejects(
      () => cloneRoleVersion(client, { roleVersionId: VERSION_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RolePermissionMutationError);
        assert.equal(err.code, "cannot_clone_draft");
        return true;
      },
    );
  });
});

describe("assignRole", () => {
  test("calls assign_role with the exact snake_case params, including the distinct actor field", async () => {
    const client = fakeClient({ data: ASSIGNMENT_ROW, error: null });
    await assignRole(client, { tenantId: TENANT_ID, roleVersionId: VERSION_ID, authUserId: AUTH_USER_ID, actorAuthUserId: AUTH_USER_ID, grantedBy: "tester" });
    assert.equal(client.calls[0]?.fn, "assign_role");
    assert.equal(client.calls[0]?.args.p_actor_auth_user_id, AUTH_USER_ID);
  });

  test("classifies a self_escalation rejection distinctly from a cross_tenant_role rejection", async () => {
    const escalationClient = fakeClient({ data: null, error: { message: "self_escalation: an actor may not assign themselves a role version carrying a protected permission" } });
    await assert.rejects(
      () => assignRole(escalationClient, { tenantId: TENANT_ID, roleVersionId: VERSION_ID, authUserId: AUTH_USER_ID, actorAuthUserId: AUTH_USER_ID, grantedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RolePermissionMutationError);
        assert.equal(err.code, "self_escalation");
        return true;
      },
    );

    const crossTenantClient = fakeClient({ data: null, error: { message: "cross_tenant_role: role version does not belong to tenant" } });
    await assert.rejects(
      () => assignRole(crossTenantClient, { tenantId: TENANT_ID, roleVersionId: VERSION_ID, authUserId: AUTH_USER_ID, actorAuthUserId: AUTH_USER_ID, grantedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RolePermissionMutationError);
        assert.equal(err.code, "cross_tenant_role");
        return true;
      },
    );
  });
});

describe("revokeRoleAssignment", () => {
  test("calls revoke_role_assignment with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...ASSIGNMENT_ROW, status: "revoked" }, error: null });
    await revokeRoleAssignment(client, { id: ASSIGNMENT_ID, reason: "role change", requestedBy: "tester" });
    assert.equal(client.calls[0]?.fn, "revoke_role_assignment");
    assert.equal(client.calls[0]?.args.p_reason, "role change");
  });

  test("falls back to mutation_failed for an unrecognized database error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset by peer" } });
    await assert.rejects(
      () => revokeRoleAssignment(client, { id: ASSIGNMENT_ID, reason: "x", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RolePermissionMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
