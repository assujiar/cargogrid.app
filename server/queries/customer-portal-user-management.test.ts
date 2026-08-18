import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listCustomerPortalAccountMembershipAccessReviews,
  listCustomerPortalAccountMembershipsForAccessReview,
  CustomerPortalUserManagementQueryError,
  type CustomerPortalUserManagementQueryClient,
} from "./customer-portal-user-management.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const MEMBERSHIP_ID = "623e4567-e89b-12d3-a456-426614174000";
const REVIEW_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalUserManagementQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalUserManagementQueryClient;
  return { client, calls };
}

describe("listCustomerPortalAccountMembershipAccessReviews", () => {
  test("maps rows and passes exact param names, defaulting cursor/limit", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: REVIEW_ID,
          tenant_id: TENANT_ID,
          account_id: ACCOUNT_ID,
          membership_id: MEMBERSHIP_ID,
          reviewed_by_actor_auth_user_id: ACTOR_ID,
          reviewed_by_label: "account-admin@acme.test",
          review_outcome: "confirmed_appropriate",
          note: null,
          idempotency_key: "review-1",
          reviewed_at: "2026-08-17T00:00:00.000Z",
          created_at: "2026-08-17T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listCustomerPortalAccountMembershipAccessReviews(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]!.reviewOutcome, "confirmed_appropriate");
    assert.deepEqual(calls[0], {
      fn: "list_customer_portal_account_membership_access_reviews",
      args: { p_tenant_id: TENANT_ID, p_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID, p_membership_id: null, p_cursor_reviewed_at: null, p_cursor_id: null, p_limit: 50 },
    });
  });

  test("passes membershipId/cursor/limit through when supplied", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalAccountMembershipAccessReviews(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID, {
      membershipId: MEMBERSHIP_ID,
      cursorReviewedAt: "2026-08-16T00:00:00.000Z",
      cursorId: REVIEW_ID,
      limit: 10,
    });
    assert.deepEqual(calls[0]!.args, {
      p_tenant_id: TENANT_ID,
      p_account_id: ACCOUNT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_membership_id: MEMBERSHIP_ID,
      p_cursor_reviewed_at: "2026-08-16T00:00:00.000Z",
      p_cursor_id: REVIEW_ID,
      p_limit: 10,
    });
  });

  test("returns an empty array (never throws) for a non-admin/deny-by-default result", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const rows = await listCustomerPortalAccountMembershipAccessReviews(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });

  test("throws CustomerPortalUserManagementQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_cursor: p_cursor_reviewed_at is required when p_cursor_id is supplied" } });
    await assert.rejects(
      () => listCustomerPortalAccountMembershipAccessReviews(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID),
      (err: unknown) => err instanceof CustomerPortalUserManagementQueryError,
    );
  });
});

describe("listCustomerPortalAccountMembershipsForAccessReview", () => {
  test("maps a row with no prior review and passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          membership_id: MEMBERSHIP_ID,
          auth_user_id: ACTOR_ID,
          role: "member",
          status: "active",
          granted_at: "2026-08-01T00:00:00.000Z",
          updated_at: "2026-08-01T00:00:00.000Z",
          record_version: 1,
          last_reviewed_at: null,
          last_reviewed_by_label: null,
          last_review_outcome: null,
          last_review_note: null,
        },
      ],
      error: null,
    });
    const rows = await listCustomerPortalAccountMembershipsForAccessReview(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]!.lastReviewedAt, null);
    assert.deepEqual(calls[0], {
      fn: "list_customer_portal_account_memberships_for_access_review",
      args: { p_tenant_id: TENANT_ID, p_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 },
    });
  });

  test("returns an empty array (never throws) for a deny-by-default result", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const rows = await listCustomerPortalAccountMembershipsForAccessReview(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });

  test("throws CustomerPortalUserManagementQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actor_identity_mismatch: the authenticated session is x but this call claims to act as y" } });
    await assert.rejects(
      () => listCustomerPortalAccountMembershipsForAccessReview(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID),
      (err: unknown) => err instanceof CustomerPortalUserManagementQueryError,
    );
  });
});
