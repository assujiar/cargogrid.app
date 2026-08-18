import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerQuoteRequest,
  parseCustomerQuoteRequestFile,
  CustomerQuoteRequestCursorSchema,
  CreateCustomerQuoteRequestDraftInputSchema,
  SubmitCustomerQuoteRequestInputSchema,
  QUOTE_REQUEST_STATUSES,
} from "./customer-quote-request.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_auth_user_id: AUTH_USER_ID,
  status: "draft",
  cargo_description: "General cargo",
  origin: { label: "Jakarta" },
  destination: { label: "Surabaya" },
  service_type: "ocean_freight",
  requested_pickup_date: "2026-09-01",
  requested_delivery_date: "2026-09-10",
  notes: "Fragile",
  idempotency_key: "create-1",
  submitted_idempotency_key: null,
  linked_quotation_id: null,
  record_version: 1,
  created_by: AUTH_USER_ID,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  submitted_at: null,
  cancelled_at: null,
  cancelled_reason: null,
};

describe("parseCustomerQuoteRequest", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerQuoteRequest(ROW);
    assert.equal(parsed.id, REQUEST_ID);
    assert.equal(parsed.accountId, ACCOUNT_ID);
    assert.equal(parsed.status, "draft");
    assert.deepEqual(parsed.origin, { label: "Jakarta" });
    assert.equal(parsed.serviceType, "ocean_freight");
    assert.equal(parsed.linkedQuotationId, null);
  });

  test("defaults missing origin/destination to an empty object, nullable fields to null", () => {
    const parsed = parseCustomerQuoteRequest({ ...ROW, origin: undefined, destination: undefined, cargo_description: undefined, notes: undefined });
    assert.deepEqual(parsed.origin, {});
    assert.deepEqual(parsed.destination, {});
    assert.equal(parsed.cargoDescription, null);
    assert.equal(parsed.notes, null);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => parseCustomerQuoteRequest({ ...ROW, status: "not_a_real_status" }));
  });

  test("every real status is exactly the migration's 4-value set", () => {
    assert.deepEqual([...QUOTE_REQUEST_STATUSES], ["draft", "submitted", "cancelled", "converted"]);
  });
});

describe("parseCustomerQuoteRequestFile", () => {
  test("maps a real attachment row", () => {
    const parsed = parseCustomerQuoteRequestFile({
      id: REQUEST_ID,
      original_filename: "cargo.jpg",
      mime_type: "image/jpeg",
      size_bytes: 2048,
      malware_scan_status: "pending",
      uploaded_by_auth_user_id: AUTH_USER_ID,
      created_at: "2026-08-16T00:00:00.000Z",
    });
    assert.equal(parsed.originalFilename, "cargo.jpg");
    assert.equal(parsed.malwareScanStatus, "pending");
  });
});

describe("CustomerQuoteRequestCursorSchema", () => {
  test("accepts an empty cursor (first page)", () => {
    assert.doesNotThrow(() => CustomerQuoteRequestCursorSchema.parse({}));
  });

  test("rejects a cursorId supplied without cursorUpdatedAt", () => {
    assert.throws(() => CustomerQuoteRequestCursorSchema.parse({ cursorId: REQUEST_ID }));
  });
});

describe("CreateCustomerQuoteRequestDraftInputSchema", () => {
  test("accepts a minimal input with every optional field omitted", () => {
    const parsed = CreateCustomerQuoteRequestDraftInputSchema.parse({ tenantId: TENANT_ID, accountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" });
    assert.equal(parsed.tenantId, TENANT_ID);
  });

  test("rejects a non-uuid accountId", () => {
    assert.throws(() => CreateCustomerQuoteRequestDraftInputSchema.parse({ tenantId: TENANT_ID, accountId: "not-a-uuid", actorAuthUserId: ACTOR_ID, actorLabel: "x" }));
  });
});

describe("SubmitCustomerQuoteRequestInputSchema", () => {
  test("requires a non-empty idempotencyKey", () => {
    assert.throws(() => SubmitCustomerQuoteRequestInputSchema.parse({ requestId: REQUEST_ID, expectedVersion: 1, idempotencyKey: "", actorAuthUserId: ACTOR_ID, actorLabel: "x" }));
  });

  test("accepts a real submit input", () => {
    const parsed = SubmitCustomerQuoteRequestInputSchema.parse({ requestId: REQUEST_ID, expectedVersion: 1, idempotencyKey: "submit-1", actorAuthUserId: ACTOR_ID, actorLabel: "x" });
    assert.equal(parsed.idempotencyKey, "submit-1");
  });
});
