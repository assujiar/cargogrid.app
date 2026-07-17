import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { CreateRoleInputSchema, parsePermission, parseRole, parseRoleVersion, parseRoleAssignment } from "./role-permission.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

describe("parsePermission", () => {
  test("maps a snake_case row to the camelCase contract shape", () => {
    const permission = parsePermission({
      id: "323e4567-e89b-12d3-a456-426614174000",
      action: "View cost",
      resource_module_code: "FIN",
      category: "sensitive",
      protected: true,
      code: "FIN:View cost",
      created_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(permission.category, "sensitive");
    assert.equal(permission.protected, true);
  });

  test("rejects an unknown action -- the 19 canonical actions are closed", () => {
    assert.throws(() =>
      parsePermission({
        id: "323e4567-e89b-12d3-a456-426614174000",
        action: "Delete Everything",
        resource_module_code: "FIN",
        category: "standard",
        protected: false,
        code: "FIN:Delete Everything",
        created_at: "2026-07-16T00:00:00.000Z",
      }),
    );
  });
});

describe("parseRole / parseRoleVersion / parseRoleAssignment", () => {
  test("maps every row shape to its camelCase contract", () => {
    const role = parseRole({
      id: "423e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      name: "Finance Approver",
      description: null,
      status: "active",
      created_by: "tester",
      record_version: 1,
      created_at: "2026-07-16T00:00:00.000Z",
      updated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(role.name, "Finance Approver");

    const version = parseRoleVersion({
      id: "523e4567-e89b-12d3-a456-426614174000",
      role_id: role.id,
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
    });
    assert.equal(version.status, "draft");

    const assignment = parseRoleAssignment({
      id: "623e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      role_version_id: version.id,
      auth_user_id: "723e4567-e89b-12d3-a456-426614174000",
      status: "active",
      granted_by: "tester",
      granted_at: "2026-07-16T00:00:00.000Z",
      revoked_at: null,
      revoked_reason: null,
      record_version: 1,
      created_at: "2026-07-16T00:00:00.000Z",
      updated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(assignment.status, "active");
  });
});

describe("CreateRoleInputSchema", () => {
  test("defaults description to null when omitted", () => {
    const parsed = CreateRoleInputSchema.parse({ tenantId: TENANT_ID, name: "Finance Approver", createdBy: "tester" });
    assert.equal(parsed.description, null);
  });
});
