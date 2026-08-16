import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerPortalAccountMembership,
  parseCustomerPortalScopeContextRow,
  CustomerPortalMembershipCursorSchema,
  InviteCustomerPortalUserInputSchema,
  AcceptCustomerPortalInviteInputSchema,
  SetCustomerPortalAccountMembershipStatusInputSchema,
  GrantInitialCustomerPortalAccountAdminInputSchema,
} from "./customer-portal-scope.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "323e4567-e89b-12d3-a456-426614174000";
const MEMBERSHIP_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseCustomerPortalAccountMembership", () => {
  test("maps a full active membership row", () => {
    const row = parseCustomerPortalAccountMembership({
      id: MEMBERSHIP_ID,
      tenant_id: TENANT_ID,
      auth_user_id: AUTH_USER_ID,
      account_id: ACCOUNT_ID,
      role: "account_admin",
      status: "active",
      invited_by: "some-admin",
      invited_at: "2026-08-01T00:00:00.000Z",
      accepted_at: "2026-08-01T00:05:00.000Z",
      granted_by: "some-admin",
      granted_at: "2026-08-01T00:00:00.000Z",
      suspended_by: null,
      suspended_at: null,
      suspended_reason: null,
      revoked_by: null,
      revoked_at: null,
      revoked_reason: null,
      record_version: 2,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:05:00.000Z",
    });
    assert.equal(row.role, "account_admin");
    assert.equal(row.status, "active");
    assert.equal(row.recordVersion, 2);
    assert.equal(row.suspendedReason, null);
  });

  test("maps a suspended row with its own reason/actor recorded", () => {
    const row = parseCustomerPortalAccountMembership({
      id: MEMBERSHIP_ID,
      tenant_id: TENANT_ID,
      auth_user_id: AUTH_USER_ID,
      account_id: ACCOUNT_ID,
      role: "member",
      status: "suspended",
      invited_by: "admin",
      invited_at: "2026-08-01T00:00:00.000Z",
      accepted_at: "2026-08-01T00:05:00.000Z",
      granted_by: "admin",
      granted_at: "2026-08-01T00:00:00.000Z",
      suspended_by: "admin",
      suspended_at: "2026-08-02T00:00:00.000Z",
      suspended_reason: "temporary hold",
      revoked_by: null,
      revoked_at: null,
      revoked_reason: null,
      record_version: 3,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-02T00:00:00.000Z",
    });
    assert.equal(row.status, "suspended");
    assert.equal(row.suspendedReason, "temporary hold");
    assert.equal(row.suspendedBy, "admin");
  });

  test("rejects a row with an unrecognized role", () => {
    assert.throws(() =>
      parseCustomerPortalAccountMembership({
        id: MEMBERSHIP_ID,
        tenant_id: TENANT_ID,
        auth_user_id: AUTH_USER_ID,
        account_id: ACCOUNT_ID,
        role: "owner",
        status: "active",
        granted_at: "2026-08-01T00:00:00.000Z",
        record_version: 1,
        created_at: "2026-08-01T00:00:00.000Z",
        updated_at: "2026-08-01T00:00:00.000Z",
      }),
    );
  });
});

describe("parseCustomerPortalScopeContextRow", () => {
  test("maps a primary account_admin row", () => {
    const row = parseCustomerPortalScopeContextRow({
      account_id: ACCOUNT_ID,
      account_name: "Acme Logistics",
      role: "account_admin",
      is_primary: true,
    });
    assert.equal(row.accountName, "Acme Logistics");
    assert.equal(row.isPrimary, true);
  });

  test("maps a legacy-only row with a null role", () => {
    const row = parseCustomerPortalScopeContextRow({
      account_id: ACCOUNT_ID,
      account_name: "Acme Logistics",
      role: null,
      is_primary: true,
    });
    assert.equal(row.role, null);
  });

  test("never carries an internal-only app.accounts field even if present on the raw row", () => {
    const row = parseCustomerPortalScopeContextRow({
      account_id: ACCOUNT_ID,
      account_name: "Acme Logistics",
      role: "member",
      is_primary: false,
      normalized_legal_name: "should-be-ignored",
      duplicate_fingerprint: "should-be-ignored",
      owner_user_id: "should-be-ignored",
    });
    assert.equal((row as Record<string, unknown>).normalized_legal_name, undefined);
    assert.equal((row as Record<string, unknown>).duplicate_fingerprint, undefined);
    assert.equal((row as Record<string, unknown>).owner_user_id, undefined);
  });
});

describe("CustomerPortalMembershipCursorSchema", () => {
  test("accepts both cursor fields omitted (first page)", () => {
    assert.doesNotThrow(() => CustomerPortalMembershipCursorSchema.parse({}));
  });

  test("accepts both cursor fields supplied together", () => {
    assert.doesNotThrow(() => CustomerPortalMembershipCursorSchema.parse({ cursorUpdatedAt: "2026-08-01T00:00:00.000Z", cursorId: MEMBERSHIP_ID }));
  });

  test("rejects cursorId supplied without cursorUpdatedAt", () => {
    assert.throws(() => CustomerPortalMembershipCursorSchema.parse({ cursorId: MEMBERSHIP_ID }));
  });
});

describe("InviteCustomerPortalUserInputSchema", () => {
  test("accepts a valid invite input", () => {
    const parsed = InviteCustomerPortalUserInputSchema.parse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      authUserId: AUTH_USER_ID,
      role: "member",
      actorAuthUserId: ACTOR_ID,
      invitedBy: "account-admin@acme.test",
    });
    assert.equal(parsed.role, "member");
  });

  test("rejects an unrecognized role", () => {
    assert.throws(() =>
      InviteCustomerPortalUserInputSchema.parse({
        tenantId: TENANT_ID,
        accountId: ACCOUNT_ID,
        authUserId: AUTH_USER_ID,
        role: "owner",
        actorAuthUserId: ACTOR_ID,
        invitedBy: "account-admin@acme.test",
      }),
    );
  });

  test("rejects an empty invitedBy label", () => {
    assert.throws(() =>
      InviteCustomerPortalUserInputSchema.parse({
        tenantId: TENANT_ID,
        accountId: ACCOUNT_ID,
        authUserId: AUTH_USER_ID,
        role: "member",
        actorAuthUserId: ACTOR_ID,
        invitedBy: "",
      }),
    );
  });
});

describe("AcceptCustomerPortalInviteInputSchema", () => {
  test("accepts a valid accept input", () => {
    const parsed = AcceptCustomerPortalInviteInputSchema.parse({
      membershipId: MEMBERSHIP_ID,
      expectedVersion: 1,
      authUserId: AUTH_USER_ID,
    });
    assert.equal(parsed.expectedVersion, 1);
  });

  test("rejects a non-positive expectedVersion", () => {
    assert.throws(() => AcceptCustomerPortalInviteInputSchema.parse({ membershipId: MEMBERSHIP_ID, expectedVersion: 0, authUserId: AUTH_USER_ID }));
  });
});

describe("SetCustomerPortalAccountMembershipStatusInputSchema", () => {
  test("accepts a valid suspend input with a reason", () => {
    const parsed = SetCustomerPortalAccountMembershipStatusInputSchema.parse({
      membershipId: MEMBERSHIP_ID,
      expectedVersion: 2,
      toStatus: "suspended",
      reason: "temporary hold",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "account-admin@acme.test",
    });
    assert.equal(parsed.toStatus, "suspended");
  });

  test("accepts reason omitted for an active/reactivate transition", () => {
    const parsed = SetCustomerPortalAccountMembershipStatusInputSchema.parse({
      membershipId: MEMBERSHIP_ID,
      expectedVersion: 2,
      toStatus: "active",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "account-admin@acme.test",
    });
    assert.equal(parsed.reason, undefined);
  });

  test("rejects an unrecognized toStatus (e.g. invited -- that transition is accept-only)", () => {
    assert.throws(() =>
      SetCustomerPortalAccountMembershipStatusInputSchema.parse({
        membershipId: MEMBERSHIP_ID,
        expectedVersion: 2,
        toStatus: "invited",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "account-admin@acme.test",
      }),
    );
  });
});

describe("GrantInitialCustomerPortalAccountAdminInputSchema", () => {
  test("accepts a valid bootstrap input", () => {
    const parsed = GrantInitialCustomerPortalAccountAdminInputSchema.parse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      authUserId: AUTH_USER_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant-admin@acme.test",
    });
    assert.equal(parsed.accountId, ACCOUNT_ID);
  });

  test("rejects a non-uuid accountId", () => {
    assert.throws(() =>
      GrantInitialCustomerPortalAccountAdminInputSchema.parse({
        tenantId: TENANT_ID,
        accountId: "not-a-uuid",
        authUserId: AUTH_USER_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant-admin@acme.test",
      }),
    );
  });
});
