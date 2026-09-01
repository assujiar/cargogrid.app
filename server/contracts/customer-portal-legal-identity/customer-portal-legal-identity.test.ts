import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerLegalIdentityChangeRequest,
  readCustomerLegalIdentityProposedValue,
  CustomerLegalIdentityChangeRequestCursorSchema,
  SubmitCustomerLegalIdentityChangeRequestInputSchema,
  DecideCustomerLegalIdentityChangeRequestInputSchema,
  CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELDS,
} from "./customer-portal-legal-identity.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";

const LEGAL_NAME_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_actor_auth_user_id: AUTH_USER_ID,
  field_name: "legal_name",
  proposed_value: "Alpha Logistics Renamed Pte Ltd",
  status: "pending",
  reviewed_by: null,
  reviewed_at: null,
  review_reason: null,
  idempotency_key: "submit-1",
  record_version: 1,
  created_at: "2026-09-01T00:00:00.000Z",
  updated_at: "2026-09-01T00:00:00.000Z",
};

describe("CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELDS", () => {
  test("is exactly {legal_name, tax_id} -- the SAME two fields the sibling low-authority table's own registry deliberately rejects", () => {
    assert.deepEqual([...CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELDS].sort(), ["legal_name", "tax_id"]);
  });
});

describe("parseCustomerLegalIdentityChangeRequest", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerLegalIdentityChangeRequest(LEGAL_NAME_ROW);
    assert.equal(parsed.id, REQUEST_ID);
    assert.equal(parsed.accountId, ACCOUNT_ID);
    assert.equal(parsed.fieldName, "legal_name");
    assert.equal(parsed.status, "pending");
    assert.equal(parsed.proposedValue, "Alpha Logistics Renamed Pte Ltd");
  });

  test("rejects an out-of-registry field_name -- never trade_name/billing_address (the sibling low-authority table's own writable fields)", () => {
    assert.throws(() => parseCustomerLegalIdentityChangeRequest({ ...LEGAL_NAME_ROW, field_name: "trade_name" }));
  });

  test("defaults reviewedBy/reviewedAt/reviewReason/idempotencyKey to null when absent", () => {
    const parsed = parseCustomerLegalIdentityChangeRequest({ ...LEGAL_NAME_ROW, reviewed_by: undefined, reviewed_at: undefined, review_reason: undefined, idempotency_key: undefined });
    assert.equal(parsed.reviewedBy, null);
    assert.equal(parsed.reviewedAt, null);
    assert.equal(parsed.reviewReason, null);
    assert.equal(parsed.idempotencyKey, null);
  });
});

describe("readCustomerLegalIdentityProposedValue", () => {
  test("reads a legal_name request's own proposedValue as the plain string", () => {
    const parsed = parseCustomerLegalIdentityChangeRequest(LEGAL_NAME_ROW);
    assert.equal(readCustomerLegalIdentityProposedValue(parsed), "Alpha Logistics Renamed Pte Ltd");
  });

  test("reads a tax_id request's own proposedValue as the plain string", () => {
    const parsed = parseCustomerLegalIdentityChangeRequest({ ...LEGAL_NAME_ROW, field_name: "tax_id", proposed_value: "02.111.222.3-000.000" });
    assert.equal(readCustomerLegalIdentityProposedValue(parsed), "02.111.222.3-000.000");
  });
});

describe("CustomerLegalIdentityChangeRequestCursorSchema", () => {
  test("rejects a cursorId without a matching cursorUpdatedAt", () => {
    const result = CustomerLegalIdentityChangeRequestCursorSchema.safeParse({ cursorId: REQUEST_ID });
    assert.equal(result.success, false);
  });

  test("accepts both omitted (first page)", () => {
    const result = CustomerLegalIdentityChangeRequestCursorSchema.safeParse({});
    assert.equal(result.success, true);
  });
});

describe("SubmitCustomerLegalIdentityChangeRequestInputSchema", () => {
  test("accepts a legal_name proposedValue", () => {
    const result = SubmitCustomerLegalIdentityChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      fieldName: "legal_name",
      proposedValue: "Alpha Logistics Renamed Pte Ltd",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, true);
  });

  test("accepts a tax_id proposedValue", () => {
    const result = SubmitCustomerLegalIdentityChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      fieldName: "tax_id",
      proposedValue: "02.111.222.3-000.000",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, true);
  });

  test("rejects a forbidden field name -- trade_name/billing_address stay the sibling low-authority table's own fields, never this one's", () => {
    const result = SubmitCustomerLegalIdentityChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      fieldName: "trade_name",
      proposedValue: "Forged Trade Name",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, false);
  });

  test("rejects an empty proposedValue", () => {
    const result = SubmitCustomerLegalIdentityChangeRequestInputSchema.safeParse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      fieldName: "legal_name",
      proposedValue: "",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.success, false);
  });
});

describe("DecideCustomerLegalIdentityChangeRequestInputSchema", () => {
  test("requires a non-empty reviewReason", () => {
    const result = DecideCustomerLegalIdentityChangeRequestInputSchema.safeParse({
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
    const result = DecideCustomerLegalIdentityChangeRequestInputSchema.safeParse({
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
