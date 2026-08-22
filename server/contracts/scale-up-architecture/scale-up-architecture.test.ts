import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWorkloadCapacityProfile,
  parseWorkloadBackpressureEvent,
  parseScalingRecommendation,
  SetWorkloadCapacityProfileInputSchema,
  GenerateScalingRecommendationInputSchema,
  WorkloadTypeSchema,
} from "./scale-up-architecture.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseWorkloadCapacityProfile", () => {
  test("round-trips a tenant-scoped profile", () => {
    const profile = parseWorkloadCapacityProfile({
      id: ROW_ID, tenant_id: TENANT_ID, workload_type: "analytics", budget_value: 150, evaluation_window_minutes: 60,
      created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
    });
    assert.equal(profile.budgetValue, 150);
  });

  test("rejects an unrecognized workload_type", () => {
    assert.throws(() =>
      parseWorkloadCapacityProfile({
        id: ROW_ID, tenant_id: TENANT_ID, workload_type: "not-a-real-workload", budget_value: 100, evaluation_window_minutes: 60,
        created_by: null, created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
      }),
    );
  });
});

describe("parseWorkloadBackpressureEvent", () => {
  test("round-trips a backpressure_applied event", () => {
    const event = parseWorkloadBackpressureEvent({
      id: ROW_ID, tenant_id: TENANT_ID, workload_type: "analytics", observed_value: 200, budget_value: 150,
      action_taken: "backpressure_applied", alert_incident_id: ROW_ID, occurred_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(event.actionTaken, "backpressure_applied");
    assert.equal(event.alertIncidentId, ROW_ID);
  });
});

describe("parseScalingRecommendation", () => {
  test("round-trips an open recommendation", () => {
    const rec = parseScalingRecommendation({
      id: ROW_ID, tenant_id: TENANT_ID, workload_type: "analytics", recommendation_type: "read_model",
      rationale: "repeated backpressure", status: "open", acknowledged_by_auth_user_id: null, acknowledged_by: null,
      acknowledged_at: null, dismissed_reason: null, created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z",
      updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
    });
    assert.equal(rec.status, "open");
  });
});

describe("WorkloadTypeSchema", () => {
  test("accepts every known workload type", () => {
    for (const t of ["oltp", "analytics", "reports", "ai", "webhooks", "import_export", "notifications"]) {
      assert.equal(WorkloadTypeSchema.parse(t), t);
    }
  });

  test("rejects anything else", () => {
    assert.throws(() => WorkloadTypeSchema.parse("not-a-real-workload"));
  });
});

describe("input schemas", () => {
  test("SetWorkloadCapacityProfileInputSchema rejects a non-positive budgetValue", () => {
    assert.throws(() =>
      SetWorkloadCapacityProfileInputSchema.parse({
        tenantId: TENANT_ID, workloadType: "analytics", budgetValue: 0, evaluationWindowMinutes: 60, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("GenerateScalingRecommendationInputSchema rejects an empty rationale", () => {
    assert.throws(() =>
      GenerateScalingRecommendationInputSchema.parse({
        tenantId: TENANT_ID, workloadType: "analytics", recommendationType: "read_model", rationale: "", actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });
});
