import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseBillingReadinessEvaluation, parseBillingReadinessHandoff } from "./billing-readiness.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const EVAL_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "623e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseBillingReadinessEvaluation", () => {
  test("maps a not_ready row with per-shipment blockers and evidence", () => {
    const evaluation = parseBillingReadinessEvaluation({
      id: EVAL_ID,
      tenant_id: TENANT_ID,
      job_order_id: JOB_ORDER_ID,
      version_number: 2,
      is_current: true,
      evaluated_status: "not_ready",
      effective_status: "not_ready",
      blockers: [{ code: "shipment_not_delivered", shipmentOrderId: SHIPMENT_ID, status: "in_transit" }],
      evidence: { shipmentOrderIds: [SHIPMENT_ID], actualCostIds: [], epodCaptureIds: [], creditOutcome: "allow", jobOrderStatus: "confirmed" },
      rule_version: 1,
      is_overridden: false,
      override_reason: null,
      overridden_by: null,
      overridden_at: null,
      override_revoked_reason: null,
      override_revoked_by: null,
      override_revoked_at: null,
      reevaluation_reason: "shipments now exist",
      supersedes_evaluation_id: null,
      evaluated_by_auth_user_id: ACTOR_ID,
      evaluated_by: "rep",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-28T09:00:00.000Z",
      updated_at: "2026-07-28T09:00:00.000Z",
    });
    assert.equal(evaluation.evaluatedStatus, "not_ready");
    assert.equal(evaluation.effectiveStatus, "not_ready");
    assert.equal(evaluation.blockers.length, 1);
    assert.equal(evaluation.blockers[0]?.code, "shipment_not_delivered");
    assert.equal(evaluation.evidence.creditOutcome, "allow");
  });

  test("maps an overridden ready row -- effective_status ready while evaluated_status remains not_ready", () => {
    const evaluation = parseBillingReadinessEvaluation({
      id: EVAL_ID,
      tenant_id: TENANT_ID,
      job_order_id: JOB_ORDER_ID,
      version_number: 3,
      is_current: true,
      evaluated_status: "not_ready",
      effective_status: "ready",
      blockers: [{ code: "active_exception", shipmentOrderId: SHIPMENT_ID, activeExceptionCount: 1 }],
      evidence: { shipmentOrderIds: [SHIPMENT_ID], actualCostIds: [SHIPMENT_ID], epodCaptureIds: [SHIPMENT_ID], creditOutcome: "allow", jobOrderStatus: "confirmed" },
      rule_version: 1,
      is_overridden: true,
      override_reason: "documentation-only delay",
      overridden_by: "rep",
      overridden_at: "2026-07-28T10:00:00.000Z",
      override_revoked_reason: null,
      override_revoked_by: null,
      override_revoked_at: null,
      reevaluation_reason: null,
      supersedes_evaluation_id: null,
      evaluated_by_auth_user_id: ACTOR_ID,
      evaluated_by: "rep",
      record_version: 2,
      created_by: "rep",
      created_at: "2026-07-28T09:00:00.000Z",
      updated_at: "2026-07-28T10:00:00.000Z",
    });
    assert.equal(evaluation.effectiveStatus, "ready");
    assert.equal(evaluation.evaluatedStatus, "not_ready");
    assert.equal(evaluation.isOverridden, true);
    assert.equal(evaluation.overrideReason, "documentation-only delay");
  });
});

describe("parseBillingReadinessHandoff", () => {
  test("maps a handoff row", () => {
    const handoff = parseBillingReadinessHandoff({
      id: HANDOFF_ID,
      tenant_id: TENANT_ID,
      job_order_id: JOB_ORDER_ID,
      evaluation_id: EVAL_ID,
      idempotency_key: "idem-handoff-1",
      handed_off_by_auth_user_id: ACTOR_ID,
      handed_off_by: "rep",
      handed_off_at: "2026-07-28T11:00:00.000Z",
      created_at: "2026-07-28T11:00:00.000Z",
    });
    assert.equal(handoff.idempotencyKey, "idem-handoff-1");
    assert.equal(handoff.evaluationId, EVAL_ID);
  });
});
