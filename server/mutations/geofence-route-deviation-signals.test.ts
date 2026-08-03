import { test } from "node:test";
import assert from "node:assert/strict";
import {
  confirmMilestoneCandidate,
  dismissMilestoneCandidate,
  confirmExceptionSignal,
  dismissExceptionSignal,
  GeofenceSignalsMutationError,
  type GeofenceSignalsMutationRpcClient,
} from "./geofence-route-deviation-signals.ts";

const TENANT_ID = "523e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "823e4567-e89b-12d3-a456-426614174000";
const SIGNAL_ID = "923e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "a23e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "b23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: GeofenceSignalsMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as GeofenceSignalsMutationRpcClient;
  return { client, calls };
}

const MILESTONE_EVENT_ROW = {
  id: EVENT_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  milestone_code: "pickup_arrival",
  event_time: "2026-08-03T00:02:00Z",
  received_time: "2026-08-03T00:02:00Z",
  location: null,
  source: "system",
  reason: "confirmed_geofence_candidate",
  corrects_event_id: null,
  idempotency_key: `milestone_candidate:${CANDIDATE_ID}`,
  sequence_no: 1,
  created_by: "admin",
  created_at: "2026-08-03T00:02:00Z",
};

const MILESTONE_CANDIDATE_ROW = {
  id: CANDIDATE_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  shipment_leg_id: TENANT_ID,
  shipment_leg_stop_id: TENANT_ID,
  milestone_code: "pickup_departure",
  candidate_event_time: "2026-08-03T00:04:00Z",
  detected_at: "2026-08-03T00:04:00Z",
  source_canonical_event_id: null,
  location_geojson: null,
  status: "dismissed",
  dedup_key: `geofence_departure:${TENANT_ID}`,
  resulting_milestone_event_id: null,
  reviewed_by_user_id: ACTOR_ID,
  reviewed_at: "2026-08-03T00:05:00Z",
  review_note: "false positive",
  created_at: "2026-08-03T00:04:00Z",
};

const OPERATIONAL_EXCEPTION_ROW = {
  id: EXCEPTION_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  milestone_event_id: null,
  type: "delay",
  severity: "medium",
  status: "open",
  owner_user_id: null,
  sla_policy_version_id: null,
  sla_hours: null,
  due_at: null,
  escalation_level: 0,
  source: "system",
  correlation_key: `route_deviation:${TENANT_ID}:20260803000900`,
  description: "Vehicle is off the planned route corridor",
  internal_notes: null,
  damage_loss_details: null,
  claim_amount: null,
  claim_currency: null,
  resolution_evidence: null,
  resolved_at: null,
  reopened_at: null,
  closed_at: null,
  record_version: 1,
  created_by: "admin",
  created_at: "2026-08-03T00:09:00Z",
  updated_at: "2026-08-03T00:09:00Z",
};

const EXCEPTION_SIGNAL_ROW = {
  id: SIGNAL_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  shipment_leg_id: TENANT_ID,
  signal_type: "route_deviation",
  exception_type: "delay",
  severity: "medium",
  detected_at: "2026-08-03T00:09:00Z",
  source_canonical_event_id: null,
  location_geojson: null,
  description: "driver took an approved detour",
  correlation_key: `route_deviation:${TENANT_ID}:20260803000900`,
  status: "dismissed",
  resulting_exception_id: null,
  reviewed_by_user_id: ACTOR_ID,
  reviewed_at: "2026-08-03T00:10:00Z",
  review_note: "approved detour",
  created_at: "2026-08-03T00:09:00Z",
};

test("confirmMilestoneCandidate sends the exact expected RPC args, including default overrideConflict=false", async () => {
  const { client, calls } = fakeRpcClient({ data: MILESTONE_EVENT_ROW, error: null });
  const result = await confirmMilestoneCandidate(client, { candidateId: CANDIDATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
  assert.equal(result.source, "system");
  assert.equal(result.reason, "confirmed_geofence_candidate");
  assert.equal(calls[0]?.fn, "confirm_milestone_candidate");
  assert.deepEqual(calls[0]?.args, {
    p_candidate_id: CANDIDATE_ID,
    p_actor_auth_user_id: ACTOR_ID,
    p_actor_label: "admin",
    p_override_event_time: null,
    p_override_conflict: false,
  });
});

test("confirmMilestoneCandidate classifies a known error code", async () => {
  const { client } = fakeRpcClient({ data: null, error: { message: "milestone_candidate_conflicts_confirmed_event: shipment order X already has a confirmed terminal milestone" } });
  await assert.rejects(
    () => confirmMilestoneCandidate(client, { candidateId: CANDIDATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" }),
    (err: unknown) => err instanceof GeofenceSignalsMutationError && err.code === "milestone_candidate_conflicts_confirmed_event",
  );
});

test("confirmMilestoneCandidate maps an unrecognized error message to mutation_failed", async () => {
  const { client } = fakeRpcClient({ data: null, error: { message: "boom" } });
  await assert.rejects(
    () => confirmMilestoneCandidate(client, { candidateId: CANDIDATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" }),
    (err: unknown) => err instanceof GeofenceSignalsMutationError && err.code === "mutation_failed",
  );
});

test("dismissMilestoneCandidate sends reviewNote through and parses the dismissed candidate row", async () => {
  const { client, calls } = fakeRpcClient({ data: MILESTONE_CANDIDATE_ROW, error: null });
  const result = await dismissMilestoneCandidate(client, { candidateId: CANDIDATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin", reviewNote: "false positive" });
  assert.equal(result.status, "dismissed");
  assert.equal(result.resultingMilestoneEventId, null);
  assert.equal(calls[0]?.args.p_review_note, "false positive");
});

test("confirmExceptionSignal sends the exact expected RPC args and parses the confirmed exception row", async () => {
  const { client, calls } = fakeRpcClient({ data: OPERATIONAL_EXCEPTION_ROW, error: null });
  const result = await confirmExceptionSignal(client, { signalId: SIGNAL_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
  assert.equal(result.source, "system");
  assert.equal(result.correlationKey, `route_deviation:${TENANT_ID}:20260803000900`);
  assert.deepEqual(calls[0]?.args, { p_signal_id: SIGNAL_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "admin" });
});

test("confirmExceptionSignal classifies a not-pending rejection", async () => {
  const { client } = fakeRpcClient({ data: null, error: { message: "exception_signal_not_pending: X is confirmed, not pending" } });
  await assert.rejects(
    () => confirmExceptionSignal(client, { signalId: SIGNAL_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" }),
    (err: unknown) => err instanceof GeofenceSignalsMutationError && err.code === "exception_signal_not_pending",
  );
});

test("dismissExceptionSignal sends reviewNote through and parses the dismissed signal row, never producing a real exception", async () => {
  const { client, calls } = fakeRpcClient({ data: EXCEPTION_SIGNAL_ROW, error: null });
  const result = await dismissExceptionSignal(client, { signalId: SIGNAL_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin", reviewNote: "approved detour" });
  assert.equal(result.status, "dismissed");
  assert.equal(result.resultingExceptionId, null);
  assert.equal(calls[0]?.args.p_review_note, "approved detour");
});

test("dismissExceptionSignal throws invalid_response when the RPC returns no row", async () => {
  const { client } = fakeRpcClient({ data: null, error: null });
  await assert.rejects(
    () => dismissExceptionSignal(client, { signalId: SIGNAL_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin", reviewNote: "x" }),
    (err: unknown) => err instanceof GeofenceSignalsMutationError && err.code === "invalid_response",
  );
});
