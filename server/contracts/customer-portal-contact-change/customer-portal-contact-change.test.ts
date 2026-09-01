import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerContactChangeRequest,
  CustomerContactChangeRequestCursorSchema,
  SubmitCustomerContactChangeRequestInputSchema,
  DecideCustomerContactChangeRequestInputSchema,
  CUSTOMER_CONTACT_CHANGE_KINDS,
} from "./customer-portal-contact-change.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONTACT_ID = "623e4567-e89b-12d3-a456-426614174000";

const ADD_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_actor_auth_user_id: AUTH_USER_ID,
  change_kind: "add",
  target_contact_id: null,
  full_name: "Jane Doe",
  title: "Ops Manager",
  email: "jane@test.com",
  phone: null,
  role: "primary",
  is_primary: true,
  status: "pending",
  reviewed_by: null,
  reviewed_at: null,
  review_reason: null,
  idempotency_key: "submit-1",
  record_version: 1,
  created_at: "2026-09-01T00:00:00.000Z",
  updated_at: "2026-09-01T00:00:00.000Z",
};

describe("CUSTOMER_CONTACT_CHANGE_KINDS", () => {
  test("is exactly {add, update, remove}", () => {
    assert.deepEqual([...CUSTOMER_CONTACT_CHANGE_KINDS].sort(), ["add", "remove", "update"]);
  });
});

describe("parseCustomerContactChangeRequest", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerContactChangeRequest(ADD_ROW);
    assert.equal(parsed.id, REQUEST_ID);
    assert.equal(parsed.changeKind, "add");
    assert.equal(parsed.targetContactId, null);
    assert.equal(parsed.fullName, "Jane Doe");
    assert.equal(parsed.isPrimary, true);
  });

  test("maps an update row's targetContactId", () => {
    const parsed = parseCustomerContactChangeRequest({ ...ADD_ROW, change_kind: "update", target_contact_id: CONTACT_ID, full_name: null, title: "Senior Ops", email: null, is_primary: null });
    assert.equal(parsed.changeKind, "update");
    assert.equal(parsed.targetContactId, CONTACT_ID);
    assert.equal(parsed.title, "Senior Ops");
    assert.equal(parsed.fullName, null);
  });

  test("rejects an out-of-registry change_kind", () => {
    assert.throws(() => parseCustomerContactChangeRequest({ ...ADD_ROW, change_kind: "delete" }));
  });
});

describe("CustomerContactChangeRequestCursorSchema", () => {
  test("rejects a cursorId without a matching cursorUpdatedAt", () => {
    const result = CustomerContactChangeRequestCursorSchema.safeParse({ cursorId: REQUEST_ID });
    assert.equal(result.success, false);
  });
});

describe("SubmitCustomerContactChangeRequestInputSchema", () => {
  test("accepts a genuine add request with no targetContactId", () => {
    const result = SubmitCustomerContactChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      changeKind: "add",
      fullName: "Jane Doe",
      email: "jane@test.com",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, true);
  });

  test("rejects an add request that supplies a targetContactId", () => {
    const result = SubmitCustomerContactChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      changeKind: "add",
      targetContactId: CONTACT_ID,
      fullName: "Jane Doe",
      email: "jane@test.com",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, false);
  });

  test("rejects an update request with no targetContactId", () => {
    const result = SubmitCustomerContactChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      changeKind: "update",
      title: "Senior Ops",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, false);
  });

  test("accepts a genuine remove request with a targetContactId", () => {
    const result = SubmitCustomerContactChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      changeKind: "remove",
      targetContactId: CONTACT_ID,
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, true);
  });

  test("rejects an invalid role", () => {
    const result = SubmitCustomerContactChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      changeKind: "add",
      fullName: "Jane Doe",
      email: "jane@test.com",
      role: "not-a-role",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, false);
  });
});

describe("DecideCustomerContactChangeRequestInputSchema", () => {
  test("requires a non-empty reviewReason", () => {
    const result = DecideCustomerContactChangeRequestInputSchema.safeParse({
      requestId: REQUEST_ID,
      expectedVersion: 1,
      decision: "approve",
      reviewReason: "",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "staff",
    });
    assert.equal(result.success, false);
  });

  test("accepts a genuine approve decision with a real reason", () => {
    const result = DecideCustomerContactChangeRequestInputSchema.safeParse({
      requestId: REQUEST_ID,
      expectedVersion: 1,
      decision: "approve",
      reviewReason: "verified new contact",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "staff",
    });
    assert.equal(result.success, true);
  });
});
