import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseRfq,
  parseRfqInvitation,
  parseRfqResponse,
  parseRfqClarification,
  ReviseRfqInputSchema,
  SubmitRfqResponseInputSchema,
} from "./rfq.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RFQ_ID = "323e4567-e89b-12d3-a456-426614174000";
const SOURCING_REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const INVITATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "623e4567-e89b-12d3-a456-426614174000";
const VENDOR_MASTER_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";
const RESPONSE_ID = "923e4567-e89b-12d3-a456-426614174000";

const BASE_RFQ_ROW = {
  id: RFQ_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  sourcing_request_id: SOURCING_REQUEST_ID,
  rfq_number: "RFQ-2026-000001",
  version: 1,
  revised_from_id: null,
  requirements_snapshot: { service_type: "ocean_freight" },
  service_type: "ocean_freight",
  mode: "FCL",
  origin_lane: "Jakarta",
  destination_lane: "Surabaya",
  cargo_weight_min: null,
  cargo_weight_max: 5000,
  cargo_volume_min: null,
  cargo_volume_max: null,
  currency: "IDR",
  status: "draft",
  issued_at: null,
  response_deadline_at: null,
  closed_at: null,
  closed_reason: null,
  owner_user_id: ACTOR_ID,
  idempotency_key: "idem-1",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

describe("parseRfq", () => {
  test("maps every snake_case column to camelCase", () => {
    const parsed = parseRfq(BASE_RFQ_ROW);
    assert.equal(parsed.id, RFQ_ID);
    assert.equal(parsed.rfqNumber, "RFQ-2026-000001");
    assert.equal(parsed.sourcingRequestId, SOURCING_REQUEST_ID);
    assert.equal(parsed.status, "draft");
  });

  test("never carries budget_amount inside requirements_snapshot (design note 3)", () => {
    const parsed = parseRfq(BASE_RFQ_ROW);
    assert.equal("budget_amount" in parsed.requirementsSnapshot, false);
  });

  test("round-trips every status enum value", () => {
    for (const status of ["draft", "issued", "closed", "cancelled", "superseded"] as const) {
      const parsed = parseRfq({ ...BASE_RFQ_ROW, status });
      assert.equal(parsed.status, status);
    }
  });
});

describe("parseRfqInvitation", () => {
  test("maps every snake_case column to camelCase", () => {
    const parsed = parseRfqInvitation({
      id: INVITATION_ID,
      tenant_id: TENANT_ID,
      rfq_id: RFQ_ID,
      sourcing_candidate_id: CANDIDATE_ID,
      vendor_master_id: VENDOR_MASTER_ID,
      status: "invited",
      invited_at: "2026-08-01T00:00:00.000Z",
      invited_by: "staff",
      decline_reason: null,
      declined_at: null,
      record_version: 1,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(parsed.status, "invited");
    assert.equal(parsed.vendorMasterId, VENDOR_MASTER_ID);
  });
});

describe("parseRfqClarification", () => {
  test("vendorMasterId null means a broadcast clarification", () => {
    const parsed = parseRfqClarification({
      id: "a23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      rfq_id: RFQ_ID,
      vendor_master_id: null,
      question: "is DG handling required?",
      asked_by: "staff",
      asked_at: "2026-08-01T00:00:00.000Z",
      answer: null,
      answered_by: null,
      answered_at: null,
      record_version: 1,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(parsed.vendorMasterId, null);
    assert.equal(parsed.answer, null);
  });
});

describe("parseRfqResponse", () => {
  const BASE_RESPONSE_ROW = {
    id: RESPONSE_ID,
    tenant_id: TENANT_ID,
    rfq_id: RFQ_ID,
    rfq_invitation_id: INVITATION_ID,
    vendor_master_id: VENDOR_MASTER_ID,
    version: 1,
    previous_version_id: null,
    status: "submitted",
    currency: "IDR",
    total_amount: 12000000,
    validity_until: "2026-09-01T00:00:00.000Z",
    lead_time_days: 7,
    commercial_terms: { incoterm: "FOB" },
    capture_mode: "offline",
    source_message_ref: "email thread #1",
    received_at: "2026-08-05T00:00:00.000Z",
    vendor_confirmed: true,
    late_capture: false,
    late_reason: null,
    comparison_eligible: true,
    idempotency_key: "idem-resp-1",
    actor_auth_user_id: ACTOR_ID,
    actor_label: "staff",
    record_version: 1,
    created_at: "2026-08-05T00:00:00.000Z",
    updated_at: "2026-08-05T00:00:00.000Z",
  };

  test("parses a masked read-RPC row (cost_masked present)", () => {
    const parsed = parseRfqResponse({ ...BASE_RESPONSE_ROW, currency: null, total_amount: null, validity_until: null, commercial_terms: {}, cost_masked: true });
    assert.equal(parsed.costMasked, true);
    assert.equal(parsed.totalAmount, null);
  });

  test("defaults costMasked to false when absent", () => {
    const parsed = parseRfqResponse(BASE_RESPONSE_ROW);
    assert.equal(parsed.costMasked, false);
    assert.equal(parsed.totalAmount, 12000000);
  });

  test("late capture is never comparison eligible", () => {
    const parsed = parseRfqResponse({ ...BASE_RESPONSE_ROW, late_capture: true, late_reason: "delayed vendor reply", comparison_eligible: false });
    assert.equal(parsed.lateCapture, true);
    assert.equal(parsed.comparisonEligible, false);
  });
});

describe("ReviseRfqInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      ReviseRfqInputSchema.parse({
        rfqId: RFQ_ID,
        reason: "",
        idempotencyKey: "idem-revise-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("defaults every optional override field to null", () => {
    const parsed = ReviseRfqInputSchema.parse({
      rfqId: RFQ_ID,
      reason: "requirements changed",
      idempotencyKey: "idem-revise-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.cargoWeightMax, null);
    assert.equal(parsed.destinationLane, null);
  });
});

describe("SubmitRfqResponseInputSchema", () => {
  test("requires a non-negative totalAmount", () => {
    assert.throws(() =>
      SubmitRfqResponseInputSchema.parse({
        rfqInvitationId: INVITATION_ID,
        currency: "IDR",
        totalAmount: -1,
        receivedAt: "2026-08-05T00:00:00.000Z",
        idempotencyKey: "idem-resp-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("defaults captureMode to offline and vendorConfirmed to false", () => {
    const parsed = SubmitRfqResponseInputSchema.parse({
      rfqInvitationId: INVITATION_ID,
      currency: "IDR",
      totalAmount: 12000000,
      receivedAt: "2026-08-05T00:00:00.000Z",
      idempotencyKey: "idem-resp-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.captureMode, "offline");
    assert.equal(parsed.vendorConfirmed, false);
    assert.equal(parsed.fileIds, null);
  });
});
