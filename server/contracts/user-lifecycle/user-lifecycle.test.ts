import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { InviteUserInputSchema, parseUser } from "./user-lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: "323e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  auth_user_id: AUTH_USER_ID,
  email: "admin@example.test",
  display_name: "Admin One",
  status: "invited",
  org_unit_id: null,
  invited_by: "tester",
  invited_at: "2026-07-16T00:00:00.000Z",
  invite_expires_at: "2026-07-23T00:00:00.000Z",
  activated_at: null,
  suspended_at: null,
  suspended_reason: null,
  revoked_at: null,
  revoked_reason: null,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

describe("parseUser", () => {
  test("maps a snake_case row to the camelCase contract shape", () => {
    const user = parseUser(ROW);
    assert.equal(user.authUserId, AUTH_USER_ID);
    assert.equal(user.status, "invited");
    assert.equal(user.orgUnitId, null);
  });

  test("rejects an unknown status -- the four lifecycle states are closed", () => {
    assert.throws(() => parseUser({ ...ROW, status: "archived" }));
  });
});

describe("InviteUserInputSchema", () => {
  test("defaults orgUnitId to null when omitted", () => {
    const parsed = InviteUserInputSchema.parse({
      tenantId: TENANT_ID,
      authUserId: AUTH_USER_ID,
      email: "admin@example.test",
      displayName: "Admin One",
      invitedBy: "tester",
      inviteExpiresAt: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(parsed.orgUnitId, null);
  });

  test("rejects a malformed email at the contract boundary, before any RPC call", () => {
    assert.throws(() =>
      InviteUserInputSchema.parse({
        tenantId: TENANT_ID,
        authUserId: AUTH_USER_ID,
        email: "not-an-email",
        displayName: "Admin One",
        invitedBy: "tester",
        inviteExpiresAt: "2026-07-23T00:00:00.000Z",
      }),
    );
  });
});
