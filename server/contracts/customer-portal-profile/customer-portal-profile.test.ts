import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerProfileChangeRequest,
  parseCustomerPortalAccountProfile,
  parseCustomerPortalAccountContact,
  readCustomerProfileProposedValue,
  CustomerProfileChangeRequestCursorSchema,
  SubmitCustomerProfileChangeRequestInputSchema,
  DecideCustomerProfileChangeRequestInputSchema,
  CUSTOMER_PROFILE_WRITABLE_FIELDS,
} from "./customer-portal-profile.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONTACT_ID = "623e4567-e89b-12d3-a456-426614174000";

const TRADE_NAME_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_actor_auth_user_id: AUTH_USER_ID,
  field_name: "trade_name",
  proposed_value: "Alpha Logistics Group",
  status: "pending",
  reviewed_by: null,
  reviewed_at: null,
  review_reason: null,
  idempotency_key: "submit-1",
  record_version: 1,
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("CUSTOMER_PROFILE_WRITABLE_FIELDS", () => {
  test("is exactly {trade_name, billing_address} -- never legal_name/tax_id/credit-adjacent/structural fields", () => {
    assert.deepEqual([...CUSTOMER_PROFILE_WRITABLE_FIELDS].sort(), ["billing_address", "trade_name"]);
  });
});

describe("parseCustomerProfileChangeRequest", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerProfileChangeRequest(TRADE_NAME_ROW);
    assert.equal(parsed.id, REQUEST_ID);
    assert.equal(parsed.accountId, ACCOUNT_ID);
    assert.equal(parsed.fieldName, "trade_name");
    assert.equal(parsed.status, "pending");
    assert.equal(parsed.proposedValue, "Alpha Logistics Group");
  });

  test("rejects an out-of-registry field_name -- the writable set is a closed union, never an open string", () => {
    assert.throws(() => parseCustomerProfileChangeRequest({ ...TRADE_NAME_ROW, field_name: "legal_name" }));
  });

  test("defaults reviewedBy/reviewedAt/reviewReason/idempotencyKey to null when absent", () => {
    const parsed = parseCustomerProfileChangeRequest({ ...TRADE_NAME_ROW, reviewed_by: undefined, reviewed_at: undefined, review_reason: undefined, idempotency_key: undefined });
    assert.equal(parsed.reviewedBy, null);
    assert.equal(parsed.reviewedAt, null);
    assert.equal(parsed.reviewReason, null);
    assert.equal(parsed.idempotencyKey, null);
  });
});

describe("readCustomerProfileProposedValue", () => {
  test("reads a trade_name request's own proposedValue as the plain string", () => {
    const parsed = parseCustomerProfileChangeRequest(TRADE_NAME_ROW);
    assert.equal(readCustomerProfileProposedValue(parsed), "Alpha Logistics Group");
  });

  test("reads a billing_address request's own proposedValue as the address object", () => {
    const parsed = parseCustomerProfileChangeRequest({ ...TRADE_NAME_ROW, field_name: "billing_address", proposed_value: { line1: "Jl. Alpha 2", city: "Jakarta", country: "ID" } });
    assert.deepEqual(readCustomerProfileProposedValue(parsed), { line1: "Jl. Alpha 2", city: "Jakarta", country: "ID" });
  });
});

describe("parseCustomerPortalAccountProfile", () => {
  test("maps legal_name/tax_id as read-only fields alongside the writable trade_name/billing_address, plus the pending-change summary", () => {
    const parsed = parseCustomerPortalAccountProfile({
      account_id: ACCOUNT_ID,
      legal_name: "Cpp1 Account Alpha Pte Ltd",
      trade_name: "Alpha Logistics",
      tax_id: "01.111.222.3-000.000",
      billing_address: { line1: "Jl. Alpha 1", city: "Jakarta", country: "ID" },
      customer_status: "active",
      record_version: 3,
      updated_at: "2026-08-17T00:00:00.000Z",
      pending_change_request_count: 1,
      latest_pending_change_request_id: REQUEST_ID,
      latest_pending_change_request_field: "trade_name",
      latest_pending_change_request_submitted_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(parsed.legalName, "Cpp1 Account Alpha Pte Ltd");
    assert.equal(parsed.taxId, "01.111.222.3-000.000");
    assert.equal(parsed.pendingChangeRequestCount, 1);
    assert.equal(parsed.latestPendingChangeRequestField, "trade_name");
  });

  test("defaults pending-change summary to zero/null when no row supplies one", () => {
    const parsed = parseCustomerPortalAccountProfile({
      account_id: ACCOUNT_ID,
      legal_name: "Cpp1 Account Alpha Pte Ltd",
      trade_name: null,
      tax_id: null,
      billing_address: {},
      customer_status: "active",
      record_version: 1,
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(parsed.pendingChangeRequestCount, 0);
    assert.equal(parsed.latestPendingChangeRequestId, null);
  });
});

describe("parseCustomerPortalAccountContact", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerPortalAccountContact({ contact_id: CONTACT_ID, full_name: "Jane Requester", title: "Ops Manager", email: "jane@test.com", phone: "0811", role: "primary", is_primary: true });
    assert.equal(parsed.contactId, CONTACT_ID);
    assert.equal(parsed.fullName, "Jane Requester");
    assert.equal(parsed.isPrimary, true);
  });
});

describe("CustomerProfileChangeRequestCursorSchema", () => {
  test("rejects a cursorId without a matching cursorUpdatedAt", () => {
    const result = CustomerProfileChangeRequestCursorSchema.safeParse({ cursorId: REQUEST_ID });
    assert.equal(result.success, false);
  });

  test("accepts both omitted (first page)", () => {
    const result = CustomerProfileChangeRequestCursorSchema.safeParse({});
    assert.equal(result.success, true);
  });
});

describe("SubmitCustomerProfileChangeRequestInputSchema", () => {
  test("accepts a trade_name string proposedValue", () => {
    const result = SubmitCustomerProfileChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      fieldName: "trade_name",
      proposedValue: "Alpha Logistics Group",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, true);
  });

  test("accepts a billing_address object proposedValue", () => {
    const result = SubmitCustomerProfileChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      fieldName: "billing_address",
      proposedValue: { line1: "Jl. Alpha 2", city: "Jakarta" },
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, true);
  });

  test("rejects a forbidden field name -- never an open text column naming an arbitrary field", () => {
    const result = SubmitCustomerProfileChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      fieldName: "legal_name",
      proposedValue: "Forged Legal Name",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, false);
  });
});

describe("DecideCustomerProfileChangeRequestInputSchema", () => {
  test("requires a non-empty reviewReason", () => {
    const result = DecideCustomerProfileChangeRequestInputSchema.safeParse({
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
    const result = DecideCustomerProfileChangeRequestInputSchema.safeParse({
      requestId: REQUEST_ID,
      expectedVersion: 1,
      decision: "approve",
      reviewReason: "verified via phone call with customer",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "staff",
    });
    assert.equal(result.success, true);
  });
});
