import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseSourcingRequest,
  parseSourcingRequestEvent,
  parseSourcingCandidate,
  CreateProactiveSourcingRequestInputSchema,
  OverrideSourcingRequestConstraintsInputSchema,
  ShortlistSourcingCandidateInputSchema,
} from "./sourcing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "323e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "423e4567-e89b-12d3-a456-426614174000";
const VENDOR_MASTER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const BASE_SOURCING_REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  source_type: "proactive",
  source_costing_request_id: null,
  source_shipment_order_id: null,
  demand_snapshot: { service_type: "ocean_freight" },
  service_type: "ocean_freight",
  mode: "FCL",
  origin_lane: "Jakarta",
  destination_lane: "Surabaya",
  cargo_weight_min: null,
  cargo_weight_max: null,
  cargo_volume_min: null,
  cargo_volume_max: null,
  requested_pickup_at: null,
  requested_delivery_at: null,
  currency: "IDR",
  budget_amount: 50000000,
  status: "open",
  owner_user_id: ACTOR_ID,
  sla_due_at: null,
  closed_reason: null,
  shortlist_locked_at: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

describe("parseSourcingRequest", () => {
  test("parses a masked directory-view row (cost_masked present)", () => {
    const row = { ...BASE_SOURCING_REQUEST_ROW, budget_amount: null, cost_masked: true };
    const parsed = parseSourcingRequest(row);
    assert.equal(parsed.id, REQUEST_ID);
    assert.equal(parsed.costMasked, true);
    assert.equal(parsed.budgetAmount, null);
  });

  test("parses a base-table write-RPC row (no cost_masked column) defaulting costMasked to false", () => {
    const row = { ...BASE_SOURCING_REQUEST_ROW };
    const parsed = parseSourcingRequest(row);
    assert.equal(parsed.costMasked, false);
    assert.equal(parsed.budgetAmount, 50000000);
  });

  test("round-trips every source_type/status enum value", () => {
    for (const sourceType of ["costing_request", "operational_demand", "proactive"] as const) {
      const parsed = parseSourcingRequest({ ...BASE_SOURCING_REQUEST_ROW, source_type: sourceType });
      assert.equal(parsed.sourceType, sourceType);
    }
    for (const status of ["draft", "open", "shortlisted", "closed_no_source", "cancelled"] as const) {
      const parsed = parseSourcingRequest({ ...BASE_SOURCING_REQUEST_ROW, status });
      assert.equal(parsed.status, status);
    }
  });
});

describe("parseSourcingRequestEvent", () => {
  test("maps every snake_case column to camelCase, including the design-note-10 evidence_ref column", () => {
    const parsed = parseSourcingRequestEvent({
      id: "723e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      sourcing_request_id: REQUEST_ID,
      from_status: "open",
      to_status: "open",
      reason: "need more capacity",
      evidence_ref: "override_expires_at=2026-09-01T00:00:00.000Z",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "staff",
      occurred_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(parsed.fromStatus, "open");
    assert.equal(parsed.toStatus, "open");
    assert.equal(parsed.evidenceRef, "override_expires_at=2026-09-01T00:00:00.000Z");
  });
});

describe("parseSourcingCandidate", () => {
  test("defaults exclusionReasons/evaluationSnapshot when absent", () => {
    const parsed = parseSourcingCandidate({
      id: CANDIDATE_ID,
      tenant_id: TENANT_ID,
      sourcing_request_id: REQUEST_ID,
      vendor_master_id: VENDOR_MASTER_ID,
      eligible: true,
      exclusion_reasons: null,
      evaluation_snapshot: null,
      shortlisted: false,
      shortlist_reason: null,
      shortlisted_by: null,
      shortlisted_at: null,
      record_version: 1,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.deepEqual(parsed.exclusionReasons, []);
    assert.deepEqual(parsed.evaluationSnapshot, {});
  });

  test("carries a real exclusion_reasons array and evaluation_snapshot through unchanged", () => {
    const parsed = parseSourcingCandidate({
      id: CANDIDATE_ID,
      tenant_id: TENANT_ID,
      sourcing_request_id: REQUEST_ID,
      vendor_master_id: VENDOR_MASTER_ID,
      eligible: false,
      exclusion_reasons: ["service_mismatch", "coverage_mismatch"],
      evaluation_snapshot: { has_active_rate: false },
      shortlisted: false,
      shortlist_reason: null,
      shortlisted_by: null,
      shortlisted_at: null,
      record_version: 1,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.deepEqual(parsed.exclusionReasons, ["service_mismatch", "coverage_mismatch"]);
    assert.equal(parsed.evaluationSnapshot.has_active_rate, false);
  });
});

describe("CreateProactiveSourcingRequestInputSchema", () => {
  test("requires non-empty serviceType/originLane/destinationLane", () => {
    assert.throws(() =>
      CreateProactiveSourcingRequestInputSchema.parse({
        tenantId: TENANT_ID,
        serviceType: "",
        originLane: "Jakarta",
        destinationLane: "Surabaya",
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("defaults every optional constraint field to null", () => {
    const parsed = CreateProactiveSourcingRequestInputSchema.parse({
      tenantId: TENANT_ID,
      serviceType: "ocean_freight",
      originLane: "Jakarta",
      destinationLane: "Surabaya",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.mode, null);
    assert.equal(parsed.cargoWeightMax, null);
    assert.equal(parsed.budgetAmount, null);
    assert.equal(parsed.ownerUserId, null);
  });
});

describe("OverrideSourcingRequestConstraintsInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      OverrideSourcingRequestConstraintsInputSchema.parse({
        sourcingRequestId: REQUEST_ID,
        reason: "",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("ShortlistSourcingCandidateInputSchema", () => {
  test("reason defaults to null (enforced server-side, not client-side, when shortlisted=true)", () => {
    const parsed = ShortlistSourcingCandidateInputSchema.parse({
      candidateId: CANDIDATE_ID,
      shortlisted: false,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.reason, null);
  });
});
