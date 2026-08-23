import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  setWorkloadCapacityProfile,
  generateScalingRecommendation,
  setScalingRecommendationStatus,
  ScaleUpArchitectureMutationError,
  type ScaleUpArchitectureMutationRpcClient,
} from "./scale-up-architecture.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_PROFILE_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, workload_type: "analytics", budget_value: 150, evaluation_window_minutes: 60,
  created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
};

const VALID_RECOMMENDATION_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, workload_type: "analytics", recommendation_type: "read_model",
  rationale: "repeated backpressure", status: "open", acknowledged_by_auth_user_id: null, acknowledged_by: null,
  acknowledged_at: null, dismissed_reason: null, created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z",
  updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ScaleUpArchitectureMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ScaleUpArchitectureMutationRpcClient;
  return { client, calls };
}

describe("setWorkloadCapacityProfile", () => {
  test("calls set_workload_capacity_profile with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_PROFILE_ROW, error: null });
    const profile = await setWorkloadCapacityProfile(client, { tenantId: TENANT_ID, workloadType: "analytics", budgetValue: 150, evaluationWindowMinutes: 60, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(profile.budgetValue, 150);
    assert.equal(calls[0]?.args.p_workload_type, "analytics");
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks authority to configure this capacity profile" } });
    await assert.rejects(
      setWorkloadCapacityProfile(client, { tenantId: TENANT_ID, workloadType: "analytics", budgetValue: 150, evaluationWindowMinutes: 60, actorAuthUserId: ACTOR_ID, actorLabel: "viewer1" }),
      (err: unknown) => err instanceof ScaleUpArchitectureMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("generateScalingRecommendation", () => {
  test("returns an open recommendation", async () => {
    const { client } = fakeRpcClient({ data: VALID_RECOMMENDATION_ROW, error: null });
    const rec = await generateScalingRecommendation(client, { tenantId: TENANT_ID, workloadType: "analytics", recommendationType: "read_model", rationale: "repeated backpressure", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(rec.status, "open");
  });

  test("classifies scaling_recommendation_already_dedicated", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "scaling_recommendation_already_dedicated: tenant already has an active dedicated deployment" } });
    await assert.rejects(
      generateScalingRecommendation(client, { tenantId: TENANT_ID, workloadType: "analytics", recommendationType: "dedicated_deployment", rationale: "x", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof ScaleUpArchitectureMutationError && err.code === "scaling_recommendation_already_dedicated",
    );
  });
});

describe("setScalingRecommendationStatus", () => {
  test("calls set_scaling_recommendation_status with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_RECOMMENDATION_ROW, status: "acknowledged", acknowledged_by: "admin1" }, error: null });
    const rec = await setScalingRecommendationStatus(client, { recommendationId: ROW_ID, newStatus: "acknowledged", dismissedReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(rec.status, "acknowledged");
    assert.equal(calls[0]?.args.p_new_status, "acknowledged");
  });

  test("classifies scaling_recommendation_invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "scaling_recommendation_invalid_transition: open -> implemented is not a valid transition" } });
    await assert.rejects(
      setScalingRecommendationStatus(client, { recommendationId: ROW_ID, newStatus: "implemented", dismissedReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof ScaleUpArchitectureMutationError && err.code === "scaling_recommendation_invalid_transition",
    );
  });

  test("classifies scaling_recommendation_dismissed_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "scaling_recommendation_dismissed_reason_required: a real dismissal reason must be stated" } });
    await assert.rejects(
      setScalingRecommendationStatus(client, { recommendationId: ROW_ID, newStatus: "dismissed", dismissedReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof ScaleUpArchitectureMutationError && err.code === "scaling_recommendation_dismissed_reason_required",
    );
  });
});
