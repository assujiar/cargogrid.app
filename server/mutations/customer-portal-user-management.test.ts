import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  updateCustomerPortalAccountMembershipRole,
  recordCustomerPortalAccountMembershipAccessReview,
  CustomerPortalUserManagementMutationError,
  type CustomerPortalUserManagementMutationRpcClient,
} from "./customer-portal-user-management.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const MEMBERSHIP_ID = "623e4567-e89b-12d3-a456-426614174000";
const REVIEW_ID = "723e4567-e89b-12d3-a456-426614174000";

const MEMBERSHIP_ROW = {
  id: MEMBERSHIP_ID,
  tenant_id: TENANT_ID,
  auth_user_id: AUTH_USER_ID,
  account_id: ACCOUNT_ID,
  role: "account_admin",
  status: "active",
  invited_by: "account-admin@acme.test",
  invited_at: "2026-08-01T00:00:00.000Z",
  accepted_at: "2026-08-01T00:05:00.000Z",
  granted_by: "account-admin@acme.test",
  granted_at: "2026-08-01T00:00:00.000Z",
  suspended_by: null,
  suspended_at: null,
  suspended_reason: null,
  revoked_by: null,
  revoked_at: null,
  revoked_reason: null,
  record_version: 2,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-10T00:00:00.000Z",
};

const REVIEW_ROW = {
  id: REVIEW_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  membership_id: MEMBERSHIP_ID,
  reviewed_by_actor_auth_user_id: ACTOR_ID,
  reviewed_by_label: "account-admin@acme.test",
  review_outcome: "confirmed_appropriate",
  note: null,
  idempotency_key: "review-2026-08-17-1",
  reviewed_at: "2026-08-17T00:00:00.000Z",
  created_at: "2026-08-17T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalUserManagementMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalUserManagementMutationRpcClient;
  return { client, calls };
}

describe("updateCustomerPortalAccountMembershipRole", () => {
  test("maps the returned row and passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...MEMBERSHIP_ROW, role: "member" }], error: null });
    const result = await updateCustomerPortalAccountMembershipRole(client, {
      membershipId: MEMBERSHIP_ID,
      expectedVersion: 2,
      newRole: "member",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "account-admin@acme.test",
    });
    assert.equal(result.role, "member");
    assert.deepEqual(calls[0], {
      fn: "update_customer_portal_account_membership_role",
      args: { p_membership_id: MEMBERSHIP_ID, p_expected_version: 2, p_new_role: "member", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "account-admin@acme.test" },
    });
  });

  test("classifies last_account_admin for a demotion that would leave zero active admins", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "last_account_admin: account x must retain at least one active account_admin" } });
    await assert.rejects(
      () => updateCustomerPortalAccountMembershipRole(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 2, newRole: "member", actorAuthUserId: ACTOR_ID, actorLabel: "solo-admin" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalUserManagementMutationError);
        assert.equal(err.code, "last_account_admin");
        return true;
      },
    );
  });

  test("classifies insufficient_authority for a wrong-account actor", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x is not an active account_admin on account y" } });
    await assert.rejects(
      () => updateCustomerPortalAccountMembershipRole(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 2, newRole: "member", actorAuthUserId: ACTOR_ID, actorLabel: "beta-admin" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalUserManagementMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: customer portal membership x expected version 2 but found 3" } });
    await assert.rejects(
      () => updateCustomerPortalAccountMembershipRole(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 2, newRole: "member", actorAuthUserId: ACTOR_ID, actorLabel: "account-admin@acme.test" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalUserManagementMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => updateCustomerPortalAccountMembershipRole(client, { membershipId: MEMBERSHIP_ID, expectedVersion: 2, newRole: "member", actorAuthUserId: ACTOR_ID, actorLabel: "account-admin@acme.test" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalUserManagementMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("recordCustomerPortalAccountMembershipAccessReview", () => {
  test("maps the returned row and passes exact param names, defaulting note to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [REVIEW_ROW], error: null });
    const result = await recordCustomerPortalAccountMembershipAccessReview(client, {
      membershipId: MEMBERSHIP_ID,
      reviewOutcome: "confirmed_appropriate",
      idempotencyKey: "review-2026-08-17-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "account-admin@acme.test",
    });
    assert.equal(result.reviewOutcome, "confirmed_appropriate");
    assert.deepEqual(calls[0], {
      fn: "record_customer_portal_account_membership_access_review",
      args: {
        p_membership_id: MEMBERSHIP_ID,
        p_review_outcome: "confirmed_appropriate",
        p_note: null,
        p_idempotency_key: "review-2026-08-17-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "account-admin@acme.test",
      },
    });
  });

  test("classifies invalid_review_target for a non-active membership", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_review_target: customer portal membership x is suspended, only an active membership may be access-reviewed" } });
    await assert.rejects(
      () =>
        recordCustomerPortalAccountMembershipAccessReview(client, {
          membershipId: MEMBERSHIP_ID,
          reviewOutcome: "confirmed_appropriate",
          idempotencyKey: "review-2026-08-17-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "account-admin@acme.test",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalUserManagementMutationError);
        assert.equal(err.code, "invalid_review_target");
        return true;
      },
    );
  });

  test("classifies idempotency_key_conflict for a key reused against a different membership", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "idempotency_key_conflict: key x was already used for a different membership's access review y" } });
    await assert.rejects(
      () =>
        recordCustomerPortalAccountMembershipAccessReview(client, {
          membershipId: MEMBERSHIP_ID,
          reviewOutcome: "confirmed_appropriate",
          idempotencyKey: "review-2026-08-17-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "account-admin@acme.test",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalUserManagementMutationError);
        assert.equal(err.code, "idempotency_key_conflict");
        return true;
      },
    );
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x is not an active account_admin on account y" } });
    await assert.rejects(
      () =>
        recordCustomerPortalAccountMembershipAccessReview(client, {
          membershipId: MEMBERSHIP_ID,
          reviewOutcome: "confirmed_appropriate",
          idempotencyKey: "review-2026-08-17-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "beta-admin",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalUserManagementMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});
