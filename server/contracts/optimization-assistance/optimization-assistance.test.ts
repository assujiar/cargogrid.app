import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseOptimizationScenario,
  parseOptimizationScenarioDecision,
  parseOptimizationScenarioDetail,
  RequestOptimizationScenarioInputSchema,
  DecideOptimizationScenarioInputSchema,
  AcknowledgeOptimizationRecommendationAppliedInputSchema,
} from "./optimization-assistance.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SCENARIO_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const DECISION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseOptimizationScenario", () => {
  test("round-trips a pending row", () => {
    const scenario = parseOptimizationScenario({
      id: SCENARIO_ID, tenant_id: TENANT_ID, scope_type: "route", input_snapshot: { stops: 5 },
      constraint_set: { max_hours: 8 }, ai_governed_request_id: null, status: "pending", is_stale: false,
      stale_reason: null, requested_by: "rep", created_at: "2026-08-22T00:00:00.000Z", completed_at: null,
    });
    assert.equal(scenario.status, "pending");
    assert.equal(scenario.isStale, false);
  });

  test("rejects an unrecognized scope_type", () => {
    assert.throws(() =>
      parseOptimizationScenario({
        id: SCENARIO_ID, tenant_id: TENANT_ID, scope_type: "not-a-real-scope", input_snapshot: {}, constraint_set: {},
        ai_governed_request_id: null, status: "pending", is_stale: false, stale_reason: null, requested_by: null,
        created_at: "2026-08-22T00:00:00.000Z", completed_at: null,
      }),
    );
  });
});

describe("parseOptimizationScenarioDecision", () => {
  test("round-trips an accepted decision", () => {
    const decision = parseOptimizationScenarioDecision({
      id: DECISION_ID, tenant_id: TENANT_ID, scenario_id: SCENARIO_ID, decision: "accepted", selected_option_index: 0,
      decision_note: "reorder stops", decided_by: "rep", decided_at: "2026-08-22T00:00:00.000Z", applied_acknowledged: false,
      applied_reference: null, applied_acknowledged_by: null, applied_acknowledged_at: null,
    });
    assert.equal(decision.decision, "accepted");
    assert.equal(decision.selectedOptionIndex, 0);
  });
});

describe("parseOptimizationScenarioDetail", () => {
  test("surfaces masked output_payload when output_payload_masked is true", () => {
    const detail = parseOptimizationScenarioDetail({
      id: SCENARIO_ID, tenant_id: TENANT_ID, scope_type: "route", input_snapshot: { stops: 5 }, constraint_set: {},
      status: "succeeded", is_stale: false, stale_reason: null, requested_by: "rep", created_at: "2026-08-22T00:00:00.000Z",
      completed_at: "2026-08-22T00:01:00.000Z", output_payload: { recommendations: [] }, output_payload_masked: true,
      confidence_label: "high", model_version: "openai-multimodal", request_status: "succeeded", decision: null,
      selected_option_index: null, decision_note: null, decided_by: null, decided_at: null, applied_acknowledged: null,
      applied_reference: null,
    });
    assert.equal(detail.outputPayloadMasked, true);
  });
});

describe("RequestOptimizationScenarioInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = RequestOptimizationScenarioInputSchema.parse({
      tenantId: TENANT_ID, scopeType: "dispatch", inputSnapshot: { x: 1 }, constraintSet: { y: 1 }, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
    });
    assert.equal(parsed.scopeType, "dispatch");
  });

  test("rejects an unrecognized scope type", () => {
    assert.throws(() =>
      RequestOptimizationScenarioInputSchema.parse({
        tenantId: TENANT_ID, scopeType: "not-a-real-scope", inputSnapshot: {}, constraintSet: {}, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
      }),
    );
  });
});

describe("DecideOptimizationScenarioInputSchema", () => {
  test("defaults selectedOptionIndex/decisionNote to null", () => {
    const parsed = DecideOptimizationScenarioInputSchema.parse({
      scenarioId: SCENARIO_ID, tenantId: TENANT_ID, decision: "rejected", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
    });
    assert.equal(parsed.selectedOptionIndex, null);
    assert.equal(parsed.decisionNote, null);
  });

  test("rejects a negative option index", () => {
    assert.throws(() =>
      DecideOptimizationScenarioInputSchema.parse({
        scenarioId: SCENARIO_ID, tenantId: TENANT_ID, decision: "accepted", selectedOptionIndex: -1, actorAuthUserId: ACTOR_ID, actorLabel: "rep",
      }),
    );
  });
});

describe("AcknowledgeOptimizationRecommendationAppliedInputSchema", () => {
  test("rejects an empty applied reference", () => {
    assert.throws(() =>
      AcknowledgeOptimizationRecommendationAppliedInputSchema.parse({ decisionId: DECISION_ID, tenantId: TENANT_ID, appliedReference: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });
});
