import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  upsertShipmentLegTrackingPolicy,
  startLegTrackingSession,
  handoffLegTrackingSession,
  endLegTrackingSession,
  evaluateLegNoSignalEscalation,
  MileOrchestrationMutationError,
  type MileOrchestrationMutationRpcClient,
} from "./mile-orchestration.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "423e4567-e89b-12d3-a456-426614174000";
const RESOURCE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: MileOrchestrationMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as MileOrchestrationMutationRpcClient;
  return { client, calls };
}

const POLICY_ROW = {
  id: POLICY_ID,
  tenant_id: TENANT_ID,
  shipment_leg_id: LEG_ID,
  tracking_required: true,
  allowed_sources: ["driver_mobile"],
  preferred_source: "driver_mobile",
  fallback_order: ["driver_mobile"],
  freshness_tolerance_seconds: null,
  accuracy_tolerance_meters: null,
  ping_interval_seconds: null,
  start_trigger: "leg_dispatch",
  end_trigger: "leg_complete",
  geofence_policy: null,
  customer_visible: false,
  no_signal_escalation_seconds: null,
  policy_version: 1,
  status: "active",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-02T00:00:00.000Z",
  updated_at: "2026-08-02T00:00:00.000Z",
};

const SESSION_ROW = {
  id: RESOURCE_ID,
  tenant_id: TENANT_ID,
  shipment_leg_id: LEG_ID,
  policy_id: POLICY_ID,
  source_type: "driver_mobile",
  resource_kind: "driver",
  resource_master_id: RESOURCE_ID,
  device_id: null,
  tracking_entitled_at_start: false,
  status: "active",
  started_at: "2026-08-02T00:00:00.000Z",
  ended_at: null,
  end_reason: null,
  is_current: true,
  superseded_by_id: null,
  created_by: "rep",
  created_at: "2026-08-02T00:00:00.000Z",
};

describe("upsertShipmentLegTrackingPolicy", () => {
  test("calls upsert_shipment_leg_tracking_policy with snake_case args and parses the result", async () => {
    const { client, calls } = fakeRpcClient({ data: POLICY_ROW, error: null });
    const policy = await upsertShipmentLegTrackingPolicy(client, {
      shipmentLegId: LEG_ID,
      trackingRequired: true,
      allowedSources: ["driver_mobile"],
      preferredSource: "driver_mobile",
      fallbackOrder: ["driver_mobile"],
      freshnessToleranceSeconds: null,
      accuracyToleranceMeters: null,
      pingIntervalSeconds: null,
      startTrigger: "leg_dispatch",
      endTrigger: "leg_complete",
      geofencePolicy: null,
      customerVisible: false,
      noSignalEscalationSeconds: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(policy.trackingRequired, true);
    assert.equal(calls[0]?.fn, "upsert_shipment_leg_tracking_policy");
    assert.equal(calls[0]?.args.p_shipment_leg_id, LEG_ID);
  });

  test("classifies an unrecognized error message as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_postgres_error" } });
    await assert.rejects(
      () =>
        upsertShipmentLegTrackingPolicy(client, {
          shipmentLegId: LEG_ID,
          trackingRequired: false,
          allowedSources: [],
          preferredSource: null,
          fallbackOrder: [],
          freshnessToleranceSeconds: null,
          accuracyToleranceMeters: null,
          pingIntervalSeconds: null,
          startTrigger: "leg_dispatch",
          endTrigger: "leg_complete",
          geofencePolicy: null,
          customerVisible: false,
          noSignalEscalationSeconds: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof MileOrchestrationMutationError && error.code === "mutation_failed",
    );
  });
});

describe("startLegTrackingSession", () => {
  test("classifies a session_already_active error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "session_already_active: leg already has an active session" } });
    await assert.rejects(
      () =>
        startLegTrackingSession(client, {
          shipmentLegId: LEG_ID,
          sourceType: "driver_mobile",
          resourceKind: "driver",
          resourceMasterId: RESOURCE_ID,
          deviceId: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof MileOrchestrationMutationError && error.code === "session_already_active",
    );
  });

  test("parses a real started session", async () => {
    const { client } = fakeRpcClient({ data: SESSION_ROW, error: null });
    const session = await startLegTrackingSession(client, {
      shipmentLegId: LEG_ID,
      sourceType: "driver_mobile",
      resourceKind: "driver",
      resourceMasterId: RESOURCE_ID,
      deviceId: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(session.status, "active");
  });
});

describe("handoffLegTrackingSession", () => {
  test("rejects an empty handoffReason client-side before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "handoff_reason_required: a non-empty reason is required" } });
    await assert.rejects(() =>
      handoffLegTrackingSession(client, {
        shipmentLegId: LEG_ID,
        sourceType: "direct_device",
        resourceKind: "vehicle",
        resourceMasterId: RESOURCE_ID,
        deviceId: RESOURCE_ID,
        handoffReason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies a source_not_eligible error from the RPC", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "source_not_eligible: driver_mobile is not currently eligible" } });
    await assert.rejects(
      () =>
        handoffLegTrackingSession(client, {
          shipmentLegId: LEG_ID,
          sourceType: "driver_mobile",
          resourceKind: "driver",
          resourceMasterId: RESOURCE_ID,
          deviceId: null,
          handoffReason: "driver swap",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof MileOrchestrationMutationError && error.code === "source_not_eligible",
    );
  });
});

describe("endLegTrackingSession", () => {
  test("classifies an override_reason_required error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "override_reason_required: a non-empty reason is required" } });
    await assert.rejects(
      () =>
        endLegTrackingSession(client, {
          shipmentLegId: LEG_ID,
          endReason: "unauthorized_override",
          reasonNote: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "manager",
        }),
      (error: unknown) => error instanceof MileOrchestrationMutationError && error.code === "override_reason_required",
    );
  });
});

describe("evaluateLegNoSignalEscalation", () => {
  test("returns null when no current session exists, without throwing", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await evaluateLegNoSignalEscalation(client, { shipmentLegId: LEG_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(result, null);
  });

  test("parses the session returned once staleness is evaluated", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...SESSION_ROW, status: "ended", end_reason: "stale_source", is_current: false }, error: null });
    const result = await evaluateLegNoSignalEscalation(client, { shipmentLegId: LEG_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(result?.endReason, "stale_source");
    assert.equal(calls[0]?.fn, "evaluate_leg_no_signal_escalation");
  });
});
