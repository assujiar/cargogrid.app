/**
 * First-, Middle-, and Last-Mile Orchestration mutation primitives (ATW-225,
 * CG-S10-ATW-006). Thin, typed wrappers around the RPCs in
 * supabase/migrations/20260729330000_create_advanced_tms_mile_orchestration.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  UpsertShipmentLegTrackingPolicyInputSchema,
  StartLegTrackingSessionInputSchema,
  HandoffLegTrackingSessionInputSchema,
  EndLegTrackingSessionInputSchema,
  EvaluateLegNoSignalEscalationInputSchema,
  parseShipmentLegTrackingPolicy,
  parseShipmentLegTrackingSession,
  type UpsertShipmentLegTrackingPolicyInput,
  type StartLegTrackingSessionInput,
  type HandoffLegTrackingSessionInput,
  type EndLegTrackingSessionInput,
  type EvaluateLegNoSignalEscalationInput,
  type ShipmentLegTrackingPolicy,
  type ShipmentLegTrackingSession,
} from "../contracts/mile-orchestration/mile-orchestration.ts";

export type MileOrchestrationMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const MILE_ORCHESTRATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_start_trigger",
  "invalid_end_trigger",
  "leg_not_found",
  "invalid_source_type",
  "invalid_resource_kind",
  "policy_not_defined",
  "tracking_not_required",
  "source_not_allowed",
  "session_already_active",
  "source_not_eligible",
  "handoff_reason_required",
  "no_active_session",
  "invalid_end_reason",
  "end_reason_required",
  "override_reason_required",
] as const;
type KnownMileOrchestrationMutationErrorCode = (typeof MILE_ORCHESTRATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type MileOrchestrationMutationErrorCode = KnownMileOrchestrationMutationErrorCode | "mutation_failed" | "invalid_response";

export class MileOrchestrationMutationError extends Error {
  readonly code: MileOrchestrationMutationErrorCode;

  constructor(code: MileOrchestrationMutationErrorCode, message: string) {
    super(message);
    this.name = "MileOrchestrationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): MileOrchestrationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (MILE_ORCHESTRATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownMileOrchestrationMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: MileOrchestrationMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new MileOrchestrationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MileOrchestrationMutationError("invalid_response", `${fn} returned no row`);
  }
  return data as Record<string, unknown>;
}

/** One policy per leg (upsert), policy_version incremented on every real update. */
export async function upsertShipmentLegTrackingPolicy(client: MileOrchestrationMutationRpcClient, input: UpsertShipmentLegTrackingPolicyInput): Promise<ShipmentLegTrackingPolicy> {
  const parsedInput = UpsertShipmentLegTrackingPolicyInputSchema.parse(input);
  const row = await callRpc(client, "upsert_shipment_leg_tracking_policy", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_tracking_required: parsedInput.trackingRequired,
    p_allowed_sources: parsedInput.allowedSources,
    p_preferred_source: parsedInput.preferredSource,
    p_fallback_order: parsedInput.fallbackOrder,
    p_freshness_tolerance_seconds: parsedInput.freshnessToleranceSeconds,
    p_accuracy_tolerance_meters: parsedInput.accuracyToleranceMeters,
    p_ping_interval_seconds: parsedInput.pingIntervalSeconds,
    p_start_trigger: parsedInput.startTrigger,
    p_end_trigger: parsedInput.endTrigger,
    p_geofence_policy: parsedInput.geofencePolicy,
    p_customer_visible: parsedInput.customerVisible,
    p_no_signal_escalation_seconds: parsedInput.noSignalEscalationSeconds,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLegTrackingPolicy(row);
}

/** Requires a defined, tracking_required policy naming this source among allowed_sources, no already-active session, and real ATW-223 eligibility. */
export async function startLegTrackingSession(client: MileOrchestrationMutationRpcClient, input: StartLegTrackingSessionInput): Promise<ShipmentLegTrackingSession> {
  const parsedInput = StartLegTrackingSessionInputSchema.parse(input);
  const row = await callRpc(client, "start_leg_tracking_session", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_source_type: parsedInput.sourceType,
    p_resource_kind: parsedInput.resourceKind,
    p_resource_master_id: parsedInput.resourceMasterId,
    p_device_id: parsedInput.deviceId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLegTrackingSession(row);
}

/** Supersedes the current session (end_reason=handoff); history preserved via is_current/superseded_by_id. */
export async function handoffLegTrackingSession(client: MileOrchestrationMutationRpcClient, input: HandoffLegTrackingSessionInput): Promise<ShipmentLegTrackingSession> {
  const parsedInput = HandoffLegTrackingSessionInputSchema.parse(input);
  const row = await callRpc(client, "handoff_leg_tracking_session", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_source_type: parsedInput.sourceType,
    p_resource_kind: parsedInput.resourceKind,
    p_resource_master_id: parsedInput.resourceMasterId,
    p_device_id: parsedInput.deviceId,
    p_handoff_reason: parsedInput.handoffReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLegTrackingSession(row);
}

/** leg_completed/manual_stop require OPS:Edit; unauthorized_override requires OPS:Override plus a mandatory reasonNote. */
export async function endLegTrackingSession(client: MileOrchestrationMutationRpcClient, input: EndLegTrackingSessionInput): Promise<ShipmentLegTrackingSession> {
  const parsedInput = EndLegTrackingSessionInputSchema.parse(input);
  const row = await callRpc(client, "end_leg_tracking_session", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_end_reason: parsedInput.endReason,
    p_reason_note: parsedInput.reasonNote,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLegTrackingSession(row);
}

/** Orchestration-level staleness check -- ends a session left active past its own no_signal_escalation_seconds and raises a real app.operational_exceptions row. Returns null when no current session exists. */
export async function evaluateLegNoSignalEscalation(client: MileOrchestrationMutationRpcClient, input: EvaluateLegNoSignalEscalationInput): Promise<ShipmentLegTrackingSession | null> {
  const parsedInput = EvaluateLegNoSignalEscalationInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_leg_no_signal_escalation", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MileOrchestrationMutationError(classifyError(error.message), error.message);
  }
  if (data === null) {
    return null;
  }
  if (typeof data !== "object") {
    throw new MileOrchestrationMutationError("invalid_response", "evaluate_leg_no_signal_escalation returned a non-object, non-null result");
  }
  return parseShipmentLegTrackingSession(data as Record<string, unknown>);
}
