import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  prepareRoutePlanningScenario,
  validateRoutePlanningScenario,
  selectRoutePlanningPlan,
  overrideRoutePlanningSelection,
  replanRoutePlanningScenario,
  runNextRoutePlanningJob,
  RouteLoadPlanningMutationError,
  type RouteLoadPlanningMutationRpcClient,
} from "./route-load-planning.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SCENARIO_ID = "423e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: RouteLoadPlanningMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as RouteLoadPlanningMutationRpcClient;
  return { client, calls };
}

const SCENARIO_ROW = {
  id: SCENARIO_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  idempotency_key: "idem-scenario-1",
  status: "draft",
  requested_weight_kg: 800,
  requested_volume_cbm: 10,
  job_id: null,
  canonical_position_snapshot: null,
  canonical_position_captured_at: null,
  owner_user_id: ACTOR_ID,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

describe("prepareRoutePlanningScenario", () => {
  test("calls prepare_route_planning_scenario with snake_case args and parses the result", async () => {
    const { client, calls } = fakeRpcClient({ data: SCENARIO_ROW, error: null });
    const scenario = await prepareRoutePlanningScenario(client, {
      shipmentOrderId: SHIPMENT_ID,
      idempotencyKey: "idem-scenario-1",
      requestedWeightKg: 800,
      requestedVolumeCbm: 10,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(scenario.status, "draft");
    assert.equal(calls[0]?.fn, "prepare_route_planning_scenario");
    assert.equal(calls[0]?.args.p_shipment_order_id, SHIPMENT_ID);
  });

  test("classifies a shipment_order_not_found error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "shipment_order_not_found: no such shipment" } });
    await assert.rejects(
      () =>
        prepareRoutePlanningScenario(client, {
          shipmentOrderId: SHIPMENT_ID,
          idempotencyKey: "idem-scenario-2",
          requestedWeightKg: null,
          requestedVolumeCbm: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof RouteLoadPlanningMutationError && error.code === "shipment_order_not_found",
    );
  });

  test("classifies an unrecognized error message as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_postgres_error" } });
    await assert.rejects(
      () =>
        prepareRoutePlanningScenario(client, {
          shipmentOrderId: SHIPMENT_ID,
          idempotencyKey: "idem-scenario-3",
          requestedWeightKg: null,
          requestedVolumeCbm: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof RouteLoadPlanningMutationError && error.code === "mutation_failed",
    );
  });
});

describe("validateRoutePlanningScenario", () => {
  test("classifies a stop_sequence_gap error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stop_sequence_gap: stops must form a contiguous sequence" } });
    await assert.rejects(
      () => validateRoutePlanningScenario(client, { scenarioId: SCENARIO_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof RouteLoadPlanningMutationError && error.code === "stop_sequence_gap",
    );
  });
});

describe("selectRoutePlanningPlan", () => {
  test("classifies a candidate_infeasible error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "candidate_infeasible: candidate requires override" } });
    await assert.rejects(
      () => selectRoutePlanningPlan(client, { scenarioId: SCENARIO_ID, candidatePlanId: CANDIDATE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof RouteLoadPlanningMutationError && error.code === "candidate_infeasible",
    );
  });
});

describe("overrideRoutePlanningSelection", () => {
  test("classifies an insufficient_authority error for a Create/Edit-only actor", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:Override" } });
    await assert.rejects(
      () =>
        overrideRoutePlanningSelection(client, {
          scenarioId: SCENARIO_ID,
          candidatePlanId: CANDIDATE_ID,
          overrideReason: "manual override: use rented truck",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof RouteLoadPlanningMutationError && error.code === "insufficient_authority",
    );
  });
});

describe("replanRoutePlanningScenario", () => {
  test("classifies a nothing_to_replan error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "nothing_to_replan: every leg has already left planned" } });
    await assert.rejects(
      () =>
        replanRoutePlanningScenario(client, {
          scenarioId: SCENARIO_ID,
          reason: "approved tracking-derived exception",
          idempotencyKey: "idem-replan-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof RouteLoadPlanningMutationError && error.code === "nothing_to_replan",
    );
  });
});

describe("runNextRoutePlanningJob", () => {
  test("returns null when no job is due, without throwing", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await runNextRoutePlanningJob(client, { workerId: "worker-1" });
    assert.equal(result, null);
  });

  test("parses the scenario returned once a job runs", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...SCENARIO_ROW, status: "ready" }, error: null });
    const result = await runNextRoutePlanningJob(client, { workerId: "worker-1" });
    assert.equal(result?.status, "ready");
    assert.equal(calls[0]?.fn, "run_next_route_planning_job");
    assert.equal(calls[0]?.args.p_worker_id, "worker-1");
  });
});
