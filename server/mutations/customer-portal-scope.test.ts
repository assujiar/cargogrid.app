import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  inviteCustomerPortalUser,
  acceptCustomerPortalInvite,
  setCustomerPortalAccountMembershipStatus,
  grantInitialCustomerPortalAccountAdmin,
  CustomerPortalScopeMutationError,
  type CustomerPortalScopeMutationRpcClient,
} from "./customer-portal-scope.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const MEMBERSHIP_ID = "623e4567-e89b-12d3-a456-426614174000";

const MEMBERSHIP_ROW = {
  id: MEMBERSHIP_ID,
  tenant_id: TENANT_ID,
  auth_user_id: AUTH_USER_ID,
  account_id: ACCOUNT_ID,
  role: "member",
  status: "invited",
  invited_by: "account-admin@acme.test",
  invited_at: "2026-08-01T00:00:00.000Z",
  accepted_at: null,
  granted_by: "account-admin@acme.test",
  granted_at: "2026-08-01T00:00:00.000Z",
  suspended_by: null,
  suspended_at: null,
  suspended_reason: null,
  revoked_by: null,
  revoked_at: null,
  revoked_reason: null,
  record_version: 1,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalScopeMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalScopeMutationRpcClient;
  return { client, calls };
}

describe("inviteCustomerPortalUser", () => {
  test("maps the returned row and passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [MEMBERSHIP_ROW], error: null });
    const result = await inviteCustomerPortalUser(client, {
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      authUserId: AUTH_USER_ID,
      role: "member",
      actorAuthUserId: ACTOR_ID,
      invitedBy: "account-admin@acme.test",
    });
    assert.equal(result.status, "invited");
    assert.deepEqual(calls[0], {
      fn: "invite_customer_portal_user",
      args: {
        p_tenant_id: TENANT_ID,
        p_account_id: ACCOUNT_ID,
        p_auth_user_id: AUTH_USER_ID,
        p_role: "member",
        p_actor_auth_user_id: ACTOR_ID,
        p_invited_by: "account-admin@acme.test",
      },
    });
  });

  test("classifies insufficient_authority (wrong-account/member-role actor rejected)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x is not an active account_admin on account y" } });
    await assert.rejects(
      () => inviteCustomerPortalUser(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, authUserId: AUTH_USER_ID, role: "member", actorAuthUserId: ACTOR_ID, invitedBy: "someone" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalScopeMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => inviteCustomerPortalUser(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, authUserId: AUTH_USER_ID, role: "member", actorAuthUserId: ACTOR_ID, invitedBy: "someone" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalScopeMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("acceptCustomerPortalInvite", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...MEMBERSHIP_ROW, status: "active", accepted_at: "2026-08-01T00:05:00.000Z" }], error: null });
    const result = await acceptCustomerPortalInvite(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 1, authUserId: AUTH_USER_ID });
    assert.equal(result.status, "active");
    assert.deepEqual(calls[0], {
      fn: "accept_customer_portal_invite",
      args: { p_membership_id: MEMBERSHIP_ID, p_expected_version: 1, p_auth_user_id: AUTH_USER_ID },
    });
  });

  test("classifies insufficient_authority for a forged/copied auth_user_id", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: only the invited identity may accept customer portal membership x" } });
    await assert.rejects(
      () => acceptCustomerPortalInvite(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 1, authUserId: AUTH_USER_ID }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalScopeMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: customer portal membership x expected version 1 but found 2" } });
    await assert.rejects(
      () => acceptCustomerPortalInvite(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 1, authUserId: AUTH_USER_ID }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalScopeMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("setCustomerPortalAccountMembershipStatus", () => {
  test("passes the exact param names, defaulting reason to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...MEMBERSHIP_ROW, status: "active" }], error: null });
    await setCustomerPortalAccountMembershipStatus(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 2, toStatus: "active", actorAuthUserId: ACTOR_ID, actorLabel: "account-admin@acme.test" });
    assert.deepEqual(calls[0], {
      fn: "set_customer_portal_account_membership_status",
      args: { p_membership_id: MEMBERSHIP_ID, p_expected_version: 2, p_to_status: "active", p_reason: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "account-admin@acme.test" },
    });
  });

  test("classifies reason_required for a suspend/revoke with no reason", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reason_required: a non-empty reason is required to suspended a customer portal membership" } });
    await assert.rejects(
      () => setCustomerPortalAccountMembershipStatus(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 2, toStatus: "suspended", actorAuthUserId: ACTOR_ID, actorLabel: "account-admin@acme.test" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalScopeMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });

  test("classifies accept_required when an admin tries to force invited -> active", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "accept_required: an invited membership may only be activated by the invited identity itself, via app.accept_customer_portal_invite" } });
    await assert.rejects(
      () =>
        setCustomerPortalAccountMembershipStatus(client, {
          membershipId: MEMBERSHIP_ID,
          expectedVersion: 1,
          toStatus: "active",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "account-admin@acme.test",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalScopeMutationError);
        assert.equal(err.code, "accept_required");
        return true;
      },
    );
  });
});

describe("grantInitialCustomerPortalAccountAdmin", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...MEMBERSHIP_ROW, role: "account_admin", status: "active" }], error: null });
    const result = await grantInitialCustomerPortalAccountAdmin(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, authUserId: AUTH_USER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant-admin@acme.test" });
    assert.equal(result.role, "account_admin");
    assert.deepEqual(calls[0], {
      fn: "grant_initial_customer_portal_account_admin",
      args: { p_tenant_id: TENANT_ID, p_account_id: ACCOUNT_ID, p_auth_user_id: AUTH_USER_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tenant-admin@acme.test" },
    });
  });

  test("classifies insufficient_authority for a staff actor lacking CPT:Create", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks CPT:Create (no_granting_role) for tenant y" } });
    await assert.rejects(
      () => grantInitialCustomerPortalAccountAdmin(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, authUserId: AUTH_USER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "no-authority-staff" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalScopeMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies account_not_found for a cross-tenant account id", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "account_not_found: no account x in tenant y" } });
    await assert.rejects(
      () => grantInitialCustomerPortalAccountAdmin(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, authUserId: AUTH_USER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant-admin@acme.test" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalScopeMutationError);
        assert.equal(err.code, "account_not_found");
        return true;
      },
    );
  });
});
