import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  inviteUser,
  resendInvitation,
  transitionUserStatus,
  reassignUserOrgUnit,
  UserLifecycleMutationError,
  type UserLifecycleRpcClient,
} from "./user-lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const USER_ID = "323e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: USER_ID,
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

function fakeClient(response: { data: unknown; error: { message: string } | null }): UserLifecycleRpcClient & {
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

describe("inviteUser", () => {
  test("calls invite_user with the exact snake_case params, defaulting orgUnitId to null", async () => {
    const client = fakeClient({ data: ROW, error: null });
    await inviteUser(client, {
      tenantId: TENANT_ID,
      authUserId: AUTH_USER_ID,
      email: "admin@example.test",
      displayName: "Admin One",
      invitedBy: "tester",
      inviteExpiresAt: "2026-07-23T00:00:00.000Z",
    });

    assert.equal(client.calls[0]?.fn, "invite_user");
    assert.equal(client.calls[0]?.args.p_org_unit_id, null);
  });
});

describe("resendInvitation", () => {
  test("classifies an invalid_resend rejection into its typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_resend: user is active, only a pending invitation can be resent" } });
    await assert.rejects(
      () => resendInvitation(client, { id: USER_ID, newExpiresAt: "2026-08-01T00:00:00.000Z", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof UserLifecycleMutationError);
        assert.equal(err.code, "invalid_resend");
        return true;
      },
    );
  });
});

describe("transitionUserStatus", () => {
  test("calls transition_user_status with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...ROW, status: "active" }, error: null });
    await transitionUserStatus(client, { id: USER_ID, newStatus: "active", reason: "onboarded", requestedBy: "tester" });

    assert.equal(client.calls[0]?.fn, "transition_user_status");
    assert.equal(client.calls[0]?.args.p_new_status, "active");
  });

  test("classifies a last_critical_admin rejection distinctly from a generic failure", async () => {
    const client = fakeClient({ data: null, error: { message: "last_critical_admin: cannot suspended the tenant's only active tenant admin" } });
    await assert.rejects(
      () => transitionUserStatus(client, { id: USER_ID, newStatus: "suspended", reason: "x", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof UserLifecycleMutationError);
        assert.equal(err.code, "last_critical_admin");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized database error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset by peer" } });
    await assert.rejects(
      () => transitionUserStatus(client, { id: USER_ID, newStatus: "revoked", reason: "x", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof UserLifecycleMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("reassignUserOrgUnit", () => {
  test("calls reassign_user_org_unit with the exact snake_case params", async () => {
    const client = fakeClient({ data: ROW, error: null });
    await reassignUserOrgUnit(client, { id: USER_ID, newOrgUnitId: TENANT_ID, expectedVersion: 1, requestedBy: "tester" });

    assert.equal(client.calls[0]?.fn, "reassign_user_org_unit");
    assert.equal(client.calls[0]?.args.p_expected_version, 1);
  });

  test("classifies a cross_tenant_org_unit rejection into its typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "cross_tenant_org_unit: org unit does not belong to tenant" } });
    await assert.rejects(
      () => reassignUserOrgUnit(client, { id: USER_ID, newOrgUnitId: TENANT_ID, expectedVersion: 1, requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof UserLifecycleMutationError);
        assert.equal(err.code, "cross_tenant_org_unit");
        return true;
      },
    );
  });
});
