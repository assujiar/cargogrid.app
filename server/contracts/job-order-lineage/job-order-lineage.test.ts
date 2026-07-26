import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseJobOrderHandoff, PrepareJobOrderHandoffInputSchema } from "./job-order-lineage.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "323e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "723e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "823e4567-e89b-12d3-a456-426614174000";
const CONVERSION_ID = "923e4567-e89b-12d3-a456-426614174000";

const VALID_PAYLOAD = {
  schemaVersion: 1,
  source: {
    quotationId: QUOTATION_ID,
    quoteNumber: "QTN-2026-000001",
    versionNumber: 1,
    opportunityId: OPPORTUNITY_ID,
    prospectId: PROSPECT_ID,
    accountConversionId: CONVERSION_ID,
  },
  customer: {
    accountId: ACCOUNT_ID,
    customerSnapshot: { legal_name: "Lineage Co" },
    contactId: null,
    contactName: null,
    contactEmail: null,
    contactPhone: null,
  },
  cargoService: { service_type: "ocean_freight" },
  pricing: {
    currency: "IDR",
    subtotalAmount: 15000000,
    discountAmount: 0,
    taxAmount: 0,
    totalAmount: 15000000,
    lines: [{ lineNo: 1, description: "Ocean freight" }],
  },
  contract: null,
  credit: null,
  acceptance: { decidedByName: "Lineage Contact", decidedAt: "2026-07-26T00:00:00.000Z", decision: "accepted" },
};

describe("parseJobOrderHandoff", () => {
  test("maps an unmasked row", () => {
    const handoff = parseJobOrderHandoff({
      id: HANDOFF_ID,
      tenant_id: TENANT_ID,
      quotation_id: QUOTATION_ID,
      account_id: ACCOUNT_ID,
      purpose: "job_order_draft",
      schema_version: 1,
      status: "prepared",
      payload: VALID_PAYLOAD,
      payload_hash: "abc123",
      payload_masked: false,
      downstream_reference: null,
      delivered_at: null,
      prepared_by_auth_user_id: ACTOR_ID,
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      created_by: "tester",
      created_at: "2026-07-26T00:00:00.000Z",
    });
    assert.equal(handoff.payloadMasked, false);
    assert.equal(handoff.payload?.pricing.totalAmount, 15000000);
  });

  test("maps a masked row without coercing a null payload into an empty object", () => {
    const handoff = parseJobOrderHandoff({
      id: HANDOFF_ID,
      tenant_id: TENANT_ID,
      quotation_id: QUOTATION_ID,
      account_id: ACCOUNT_ID,
      purpose: "job_order_draft",
      schema_version: 1,
      status: "prepared",
      payload: null,
      payload_hash: null,
      payload_masked: true,
      downstream_reference: null,
      delivered_at: null,
      prepared_by_auth_user_id: ACTOR_ID,
      owner_user_id: null,
      org_unit_id: null,
      created_by: "tester",
      created_at: "2026-07-26T00:00:00.000Z",
    });
    assert.equal(handoff.payload, null);
    assert.equal(handoff.payloadHash, null);
    assert.equal(handoff.payloadMasked, true);
  });
});

describe("PrepareJobOrderHandoffInputSchema", () => {
  test("requires a non-empty actorLabel", () => {
    assert.throws(() =>
      PrepareJobOrderHandoffInputSchema.parse({ quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "" }),
    );
  });
});
