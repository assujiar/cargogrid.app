import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { EvaluatePermissionInputSchema, parseRbacDecision } from "./rbac.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";

describe("parseRbacDecision", () => {
  test("maps an allowed decision (snake_case) to the camelCase contract shape", () => {
    const decision = parseRbacDecision({
      allowed: true,
      reason: "role_grant",
      permission_id: "323e4567-e89b-12d3-a456-426614174000",
      role_id: "423e4567-e89b-12d3-a456-426614174000",
      role_version_id: "523e4567-e89b-12d3-a456-426614174000",
      evaluated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(decision.allowed, true);
    assert.equal(decision.reason, "role_grant");
  });

  test("maps a denied decision with null role/version references", () => {
    const decision = parseRbacDecision({
      allowed: false,
      reason: "no_active_assignment",
      permission_id: "323e4567-e89b-12d3-a456-426614174000",
      role_id: null,
      role_version_id: null,
      evaluated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(decision.allowed, false);
    assert.equal(decision.roleId, null);
  });
});

describe("EvaluatePermissionInputSchema", () => {
  test("accepts a valid input and leaves asOf optional", () => {
    const parsed = EvaluatePermissionInputSchema.parse({
      authUserId: AUTH_USER_ID,
      tenantId: TENANT_ID,
      resourceModuleCode: "FIN",
      action: "Approve",
    });
    assert.equal(parsed.asOf, undefined);
  });

  test("rejects an empty resourceModuleCode/action at the contract boundary", () => {
    assert.throws(() =>
      EvaluatePermissionInputSchema.parse({
        authUserId: AUTH_USER_ID,
        tenantId: TENANT_ID,
        resourceModuleCode: "",
        action: "",
      }),
    );
  });
});
