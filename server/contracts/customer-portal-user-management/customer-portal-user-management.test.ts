import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerPortalAccessReview,
  parseCustomerPortalAccessReviewMembershipRow,
  CustomerPortalAccessReviewCursorSchema,
  CustomerPortalAccessReviewMembershipCursorSchema,
  UpdateCustomerPortalAccountMembershipRoleInputSchema,
  RecordCustomerPortalAccountMembershipAccessReviewInputSchema,
} from "./customer-portal-user-management.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "323e4567-e89b-12d3-a456-426614174000";
const MEMBERSHIP_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const REVIEW_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseCustomerPortalAccessReview", () => {
  test("maps a full review row", () => {
    const row = parseCustomerPortalAccessReview({
      id: REVIEW_ID,
      tenant_id: TENANT_ID,
      account_id: ACCOUNT_ID,
      membership_id: MEMBERSHIP_ID,
      reviewed_by_actor_auth_user_id: ACTOR_ID,
      reviewed_by_label: "account-admin@acme.test",
      review_outcome: "confirmed_appropriate",
      note: "Still needed for invoicing.",
      idempotency_key: "review-2026-08-17-1",
      reviewed_at: "2026-08-17T00:00:00.000Z",
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(row.reviewOutcome, "confirmed_appropriate");
    assert.equal(row.note, "Still needed for invoicing.");
  });

  test("maps a null note/label", () => {
    const row = parseCustomerPortalAccessReview({
      id: REVIEW_ID,
      tenant_id: TENANT_ID,
      account_id: ACCOUNT_ID,
      membership_id: MEMBERSHIP_ID,
      reviewed_by_actor_auth_user_id: ACTOR_ID,
      reviewed_by_label: null,
      review_outcome: "flagged_for_follow_up",
      note: null,
      idempotency_key: "review-2026-08-17-2",
      reviewed_at: "2026-08-17T00:00:00.000Z",
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(row.reviewedByLabel, null);
    assert.equal(row.note, null);
    assert.equal(row.reviewOutcome, "flagged_for_follow_up");
  });

  test("rejects an unrecognized review outcome", () => {
    assert.throws(() =>
      parseCustomerPortalAccessReview({
        id: REVIEW_ID,
        tenant_id: TENANT_ID,
        account_id: ACCOUNT_ID,
        membership_id: MEMBERSHIP_ID,
        reviewed_by_actor_auth_user_id: ACTOR_ID,
        review_outcome: "escalated",
        idempotency_key: "review-2026-08-17-3",
        reviewed_at: "2026-08-17T00:00:00.000Z",
        created_at: "2026-08-17T00:00:00.000Z",
      }),
    );
  });
});

describe("parseCustomerPortalAccessReviewMembershipRow", () => {
  test("maps a row with a prior review", () => {
    const row = parseCustomerPortalAccessReviewMembershipRow({
      membership_id: MEMBERSHIP_ID,
      auth_user_id: AUTH_USER_ID,
      role: "member",
      status: "active",
      granted_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-10T00:00:00.000Z",
      record_version: 3,
      last_reviewed_at: "2026-08-15T00:00:00.000Z",
      last_reviewed_by_label: "account-admin@acme.test",
      last_review_outcome: "confirmed_appropriate",
      last_review_note: "Looks fine.",
    });
    assert.equal(row.role, "member");
    assert.equal(row.lastReviewOutcome, "confirmed_appropriate");
  });

  test("maps a row that has never been reviewed", () => {
    const row = parseCustomerPortalAccessReviewMembershipRow({
      membership_id: MEMBERSHIP_ID,
      auth_user_id: AUTH_USER_ID,
      role: "account_admin",
      status: "active",
      granted_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
      record_version: 1,
      last_reviewed_at: null,
      last_reviewed_by_label: null,
      last_review_outcome: null,
      last_review_note: null,
    });
    assert.equal(row.lastReviewedAt, null);
    assert.equal(row.lastReviewOutcome, null);
  });
});

describe("CustomerPortalAccessReviewCursorSchema", () => {
  test("accepts both fields omitted", () => {
    assert.doesNotThrow(() => CustomerPortalAccessReviewCursorSchema.parse({}));
  });

  test("rejects cursorId without cursorReviewedAt", () => {
    assert.throws(() => CustomerPortalAccessReviewCursorSchema.parse({ cursorId: REVIEW_ID }));
  });
});

describe("CustomerPortalAccessReviewMembershipCursorSchema", () => {
  test("accepts both fields supplied together", () => {
    assert.doesNotThrow(() => CustomerPortalAccessReviewMembershipCursorSchema.parse({ cursorUpdatedAt: "2026-08-17T00:00:00.000Z", cursorId: MEMBERSHIP_ID }));
  });

  test("rejects cursorId without cursorUpdatedAt", () => {
    assert.throws(() => CustomerPortalAccessReviewMembershipCursorSchema.parse({ cursorId: MEMBERSHIP_ID }));
  });
});

describe("UpdateCustomerPortalAccountMembershipRoleInputSchema", () => {
  test("accepts a valid role-update input", () => {
    const parsed = UpdateCustomerPortalAccountMembershipRoleInputSchema.parse({
      membershipId: MEMBERSHIP_ID,
      expectedVersion: 2,
      newRole: "account_admin",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "account-admin@acme.test",
    });
    assert.equal(parsed.newRole, "account_admin");
  });

  test("rejects an unrecognized role", () => {
    assert.throws(() =>
      UpdateCustomerPortalAccountMembershipRoleInputSchema.parse({
        membershipId: MEMBERSHIP_ID,
        expectedVersion: 2,
        newRole: "owner",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "account-admin@acme.test",
      }),
    );
  });

  test("rejects a non-positive expectedVersion", () => {
    assert.throws(() =>
      UpdateCustomerPortalAccountMembershipRoleInputSchema.parse({
        membershipId: MEMBERSHIP_ID,
        expectedVersion: 0,
        newRole: "member",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "account-admin@acme.test",
      }),
    );
  });
});

describe("RecordCustomerPortalAccountMembershipAccessReviewInputSchema", () => {
  test("accepts a valid review input with a note", () => {
    const parsed = RecordCustomerPortalAccountMembershipAccessReviewInputSchema.parse({
      membershipId: MEMBERSHIP_ID,
      reviewOutcome: "flagged_for_follow_up",
      note: "Role seems too broad for their actual usage.",
      idempotencyKey: "review-2026-08-17-4",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "account-admin@acme.test",
    });
    assert.equal(parsed.reviewOutcome, "flagged_for_follow_up");
  });

  test("accepts note omitted", () => {
    const parsed = RecordCustomerPortalAccountMembershipAccessReviewInputSchema.parse({
      membershipId: MEMBERSHIP_ID,
      reviewOutcome: "confirmed_appropriate",
      idempotencyKey: "review-2026-08-17-5",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "account-admin@acme.test",
    });
    assert.equal(parsed.note, undefined);
  });

  test("rejects an empty idempotencyKey", () => {
    assert.throws(() =>
      RecordCustomerPortalAccountMembershipAccessReviewInputSchema.parse({
        membershipId: MEMBERSHIP_ID,
        reviewOutcome: "confirmed_appropriate",
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "account-admin@acme.test",
      }),
    );
  });

  test("rejects an unrecognized reviewOutcome", () => {
    assert.throws(() =>
      RecordCustomerPortalAccountMembershipAccessReviewInputSchema.parse({
        membershipId: MEMBERSHIP_ID,
        reviewOutcome: "escalated",
        idempotencyKey: "review-2026-08-17-6",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "account-admin@acme.test",
      }),
    );
  });
});
