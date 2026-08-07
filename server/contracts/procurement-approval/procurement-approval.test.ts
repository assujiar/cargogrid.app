import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseProcurementApprovalPolicyVersion,
  parseProcurementApprovalRequirement,
  parseProcurementApprovalContextSnapshot,
  parseProcurementExceptionRequest,
  parseVendorActivationApprovalSyncResult,
  parseRateVersionApprovalSyncResult,
  parseVendorSelectionApprovalSyncResult,
  CreateProcurementApprovalPolicyVersionInputSchema,
  PublishProcurementApprovalPolicyVersionInputSchema,
  DecideProcurementApprovalStepInputSchema,
  CreateProcurementExceptionRequestInputSchema,
} from "./procurement-approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "723e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "823e4567-e89b-12d3-a456-426614174000";
const ENTITY_ID = "923e4567-e89b-12d3-a456-426614174000";
const SNAPSHOT_ID = "a23e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "b23e4567-e89b-12d3-a456-426614174000";

describe("parseProcurementApprovalPolicyVersion", () => {
  test("maps an alwaysRequired-only policy, leaving minValueAmount null", () => {
    const policy = parseProcurementApprovalPolicyVersion({
      id: POLICY_ID,
      tenant_id: TENANT_ID,
      entity_type: "vendor_activation",
      min_value_amount: null,
      always_required: true,
      status: "published",
      supersedes_version_id: null,
      record_version: 2,
      created_by: "tester",
      created_at: "2026-08-07T00:00:00.000Z",
      updated_at: "2026-08-07T00:00:00.000Z",
    });
    assert.equal(policy.entityType, "vendor_activation");
    assert.equal(policy.minValueAmount, null);
    assert.equal(policy.alwaysRequired, true);
  });
});

describe("parseProcurementApprovalRequirement", () => {
  test("maps a required=true row with reason codes", () => {
    const requirement = parseProcurementApprovalRequirement({ required: true, reasons: ["value_meets_threshold"], policy_version_id: POLICY_ID });
    assert.equal(requirement.required, true);
    assert.deepEqual(requirement.reasons, ["value_meets_threshold"]);
    assert.equal(requirement.policyVersionId, POLICY_ID);
  });

  test("maps a required=false row with no published policy (policyVersionId null)", () => {
    const requirement = parseProcurementApprovalRequirement({ required: false, reasons: [], policy_version_id: null });
    assert.equal(requirement.required, false);
    assert.equal(requirement.policyVersionId, null);
  });
});

describe("parseProcurementApprovalContextSnapshot", () => {
  test("maps a masked row (costMasked=true, valueAmount/currency null)", () => {
    const snapshot = parseProcurementApprovalContextSnapshot({
      id: SNAPSHOT_ID,
      approval_request_id: REQUEST_ID,
      tenant_id: TENANT_ID,
      entity_type: "rate_version",
      entity_id: ENTITY_ID,
      value_amount: null,
      currency: null,
      cost_masked: true,
      reasons: ["value_meets_threshold"],
      policy_version_id: POLICY_ID,
      context: { service_type: "ocean_freight" },
      source_record_version: 1,
      created_by: "tester",
      created_at: "2026-08-07T00:00:00.000Z",
    });
    assert.equal(snapshot.costMasked, true);
    assert.equal(snapshot.valueAmount, null);
    assert.deepEqual(snapshot.context, { service_type: "ocean_freight" });
  });

  test("maps an unmasked row with the real amount/currency", () => {
    const snapshot = parseProcurementApprovalContextSnapshot({
      id: SNAPSHOT_ID,
      approval_request_id: REQUEST_ID,
      tenant_id: TENANT_ID,
      entity_type: "rate_version",
      entity_id: ENTITY_ID,
      value_amount: "10000000",
      currency: "IDR",
      cost_masked: false,
      reasons: [],
      policy_version_id: POLICY_ID,
      context: {},
      source_record_version: 1,
      created_by: "tester",
      created_at: "2026-08-07T00:00:00.000Z",
    });
    assert.equal(snapshot.costMasked, false);
    assert.equal(snapshot.valueAmount, 10000000);
    assert.equal(snapshot.currency, "IDR");
  });
});

describe("parseProcurementExceptionRequest", () => {
  test("maps a routed, pending exception request", () => {
    const req = parseProcurementExceptionRequest({
      id: EXCEPTION_ID,
      tenant_id: TENANT_ID,
      related_entity_type: "purchase_order",
      related_entity_id: null,
      exception_type: "po_threshold_bypass",
      reason: "emergency spare parts order",
      requested_outcome: null,
      status: "submitted",
      approval_status: "pending",
      approval_request_id: REQUEST_ID,
      idempotency_key: "idem-1",
      record_version: 1,
      created_by: "tester",
      created_at: "2026-08-07T00:00:00.000Z",
      updated_at: "2026-08-07T00:00:00.000Z",
    });
    assert.equal(req.status, "submitted");
    assert.equal(req.approvalStatus, "pending");
    assert.equal(req.approvalRequestId, REQUEST_ID);
  });
});

describe("domain sync wrapper result parsers", () => {
  test("parseVendorActivationApprovalSyncResult maps masterRecordId/approvalStatus", () => {
    const result = parseVendorActivationApprovalSyncResult({ master_record_id: ENTITY_ID, approval_status: "approved" });
    assert.equal(result.masterRecordId, ENTITY_ID);
    assert.equal(result.approvalStatus, "approved");
  });

  test("parseRateVersionApprovalSyncResult maps id/governanceApprovalStatus", () => {
    const result = parseRateVersionApprovalSyncResult({ id: ENTITY_ID, governance_approval_status: "rejected" });
    assert.equal(result.id, ENTITY_ID);
    assert.equal(result.governanceApprovalStatus, "rejected");
  });

  test("parseVendorSelectionApprovalSyncResult maps id/approvalStatus", () => {
    const result = parseVendorSelectionApprovalSyncResult({ id: ENTITY_ID, approval_status: "pending" });
    assert.equal(result.id, ENTITY_ID);
    assert.equal(result.approvalStatus, "pending");
  });
});

describe("CreateProcurementApprovalPolicyVersionInputSchema", () => {
  test("accepts an alwaysRequired-only policy for vendor_activation", () => {
    const parsed = CreateProcurementApprovalPolicyVersionInputSchema.parse({
      tenantId: TENANT_ID,
      entityType: "vendor_activation",
      alwaysRequired: true,
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(parsed.alwaysRequired, true);
    assert.equal(parsed.minValueAmount, null);
  });

  test("rejects a policy with neither minValueAmount nor alwaysRequired set", () => {
    assert.throws(() =>
      CreateProcurementApprovalPolicyVersionInputSchema.parse({
        tenantId: TENANT_ID,
        entityType: "rate_version",
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });

  test("rejects an invalid entityType", () => {
    assert.throws(() =>
      CreateProcurementApprovalPolicyVersionInputSchema.parse({
        tenantId: TENANT_ID,
        entityType: "not_a_real_type",
        alwaysRequired: true,
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });
});

describe("PublishProcurementApprovalPolicyVersionInputSchema", () => {
  test("defaults supersedesVersionId to null", () => {
    const parsed = PublishProcurementApprovalPolicyVersionInputSchema.parse({
      policyVersionId: POLICY_ID,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.supersedesVersionId, null);
  });
});

describe("DecideProcurementApprovalStepInputSchema", () => {
  test("accepts an approve decision with no reason", () => {
    const parsed = DecideProcurementApprovalStepInputSchema.parse({
      requestStepId: STEP_ID,
      decision: "approved",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager",
      reauthConfirmedAt: new Date().toISOString(),
    });
    assert.equal(parsed.decision, "approved");
    assert.equal(parsed.reason, null);
  });

  test("rejects a decision value outside approved/rejected", () => {
    assert.throws(() =>
      DecideProcurementApprovalStepInputSchema.parse({
        requestStepId: STEP_ID,
        decision: "revise",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager",
        reauthConfirmedAt: new Date().toISOString(),
      }),
    );
  });

  // Batch 257-259 review (C-18, HIGH): reauthConfirmedAt is now a required MFA
  // freshness attestation (Prompt 259 §16), mirroring DecideCreditProfileApprovalStepInputSchema (COM-157).
  test("requires reauthConfirmedAt", () => {
    assert.throws(() =>
      DecideProcurementApprovalStepInputSchema.parse({
        requestStepId: STEP_ID,
        decision: "approved",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager",
      }),
    );
  });
});

describe("CreateProcurementExceptionRequestInputSchema", () => {
  test("requires a non-empty reason and exceptionType", () => {
    assert.throws(() =>
      CreateProcurementExceptionRequestInputSchema.parse({
        tenantId: TENANT_ID,
        exceptionType: "",
        reason: "",
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });

  test("accepts a minimal valid request, defaulting relatedEntityType/relatedEntityId/requestedOutcome to null", () => {
    const parsed = CreateProcurementExceptionRequestInputSchema.parse({
      tenantId: TENANT_ID,
      exceptionType: "expedited_activation",
      reason: "urgent shipment",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(parsed.relatedEntityType, null);
    assert.equal(parsed.relatedEntityId, null);
    assert.equal(parsed.requestedOutcome, null);
  });
});
