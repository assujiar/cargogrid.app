import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseVendorApiKey,
  parseCreatedVendorApiKey,
  parseRfqForVendorApi,
  parseRfqResponse,
  parseVendorAssignmentInvitation,
  CreateVendorApiKeyInputSchema,
  SubmitRfqResponseViaVendorApiInputSchema,
} from "./vendor-api.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const KEY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const RFQ_ID = "623e4567-e89b-12d3-a456-426614174000";
const RFQ_INVITATION_ID = "723e4567-e89b-12d3-a456-426614174000";

const KEY_ROW = {
  id: KEY_ID,
  tenant_id: TENANT_ID,
  name: "Ops Integration",
  key_prefix: "cgk_abcd1234",
  scopes: ["PRC:VendorPortal"],
  status: "active",
  rate_limit_per_minute: 60,
  expires_at: null,
  last_used_at: null,
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
  vendor_master_record_id: VENDOR_ID,
  vendor_legal_name: "Acme Freight Co",
};

describe("parseVendorApiKey", () => {
  test("maps snake_case columns to camelCase, including the vendor binding", () => {
    const key = parseVendorApiKey(KEY_ROW);
    assert.equal(key.id, KEY_ID);
    assert.equal(key.vendorMasterRecordId, VENDOR_ID);
    assert.equal(key.vendorLegalName, "Acme Freight Co");
    assert.deepEqual(key.scopes, ["PRC:VendorPortal"]);
  });

  test("rejects a row missing the vendor binding -- a tenant-staff/customer key is never a VendorApiKey", () => {
    const { vendor_master_record_id, ...staffRow } = KEY_ROW;
    assert.throws(() => parseVendorApiKey(staffRow as Record<string, unknown>));
  });
});

describe("parseCreatedVendorApiKey", () => {
  test("carries the one-time raw_key alongside the mapped row", () => {
    const created = parseCreatedVendorApiKey({ ...KEY_ROW, raw_key: "cgk_abcd1234deadbeef" });
    assert.equal(created.rawKey, "cgk_abcd1234deadbeef");
    assert.equal(created.vendorMasterRecordId, VENDOR_ID);
  });
});

describe("CreateVendorApiKeyInputSchema", () => {
  test("defaults expiresAt and rateLimitPerMinute to null", () => {
    const parsed = CreateVendorApiKeyInputSchema.parse({
      tenantId: TENANT_ID,
      vendorMasterRecordId: VENDOR_ID,
      name: "Ops Integration",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant admin",
    });
    assert.equal(parsed.expiresAt, null);
    assert.equal(parsed.rateLimitPerMinute, null);
  });

  test("rejects an empty name", () => {
    assert.throws(() =>
      CreateVendorApiKeyInputSchema.parse({
        tenantId: TENANT_ID,
        vendorMasterRecordId: VENDOR_ID,
        name: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
      }),
    );
  });
});

describe("parseRfqForVendorApi", () => {
  test("maps snake_case columns to camelCase", () => {
    const rfq = parseRfqForVendorApi({
      rfq_invitation_id: RFQ_INVITATION_ID,
      rfq_id: RFQ_ID,
      invitation_status: "invited",
      response_deadline_at: "2026-09-01T00:00:00.000Z",
      rfq_number: "RFQ-0001",
      rfq_status: "issued",
    });
    assert.equal(rfq.rfqInvitationId, RFQ_INVITATION_ID);
    assert.equal(rfq.invitationStatus, "invited");
  });
});

describe("SubmitRfqResponseViaVendorApiInputSchema", () => {
  test("defaults vendorConfirmed to true and commercialTerms to an empty object", () => {
    const parsed = SubmitRfqResponseViaVendorApiInputSchema.parse({
      tenantId: TENANT_ID,
      vendorMasterRecordId: VENDOR_ID,
      rfqInvitationId: RFQ_INVITATION_ID,
      currency: "USD",
      totalAmount: 1000,
      idempotencyKey: "resp-001",
    });
    assert.equal(parsed.vendorConfirmed, true);
    assert.deepEqual(parsed.commercialTerms, {});
  });

  test("rejects a negative totalAmount", () => {
    assert.throws(() =>
      SubmitRfqResponseViaVendorApiInputSchema.parse({
        tenantId: TENANT_ID,
        vendorMasterRecordId: VENDOR_ID,
        rfqInvitationId: RFQ_INVITATION_ID,
        currency: "USD",
        totalAmount: -1,
        idempotencyKey: "resp-001",
      }),
    );
  });
});

describe("parseRfqResponse", () => {
  test("maps snake_case columns to camelCase and coerces numeric total_amount", () => {
    const response = parseRfqResponse({
      id: RFQ_INVITATION_ID,
      tenant_id: TENANT_ID,
      rfq_id: RFQ_ID,
      rfq_invitation_id: RFQ_INVITATION_ID,
      version: 1,
      status: "submitted",
      currency: "USD",
      total_amount: "1000.00",
      validity_until: null,
      lead_time_days: 14,
      capture_mode: "vendor_api",
      late_capture: false,
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(response.totalAmount, 1000);
    assert.equal(response.captureMode, "vendor_api");
  });
});

describe("parseVendorAssignmentInvitation", () => {
  test("maps snake_case columns to camelCase", () => {
    const invitation = parseVendorAssignmentInvitation({
      id: RFQ_INVITATION_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: RFQ_ID,
      vendor_master_id: VENDOR_ID,
      status: "accepted",
      decline_reason: null,
      record_version: 2,
    });
    assert.equal(invitation.status, "accepted");
    assert.equal(invitation.recordVersion, 2);
  });
});
