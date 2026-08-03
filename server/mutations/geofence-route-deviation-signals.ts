/**
 * Geofence, route deviation, milestone candidate, and exception signal review/promotion
 * RPCs (ATW-226G). app.confirm_milestone_candidate/app.confirm_exception_signal are the
 * sole paths a derived signal ever becomes a real app.milestone_events/app.operational_
 * exceptions row -- app.dismiss_milestone_candidate/app.dismiss_exception_signal close a
 * signal out without ever creating one (supabase/migrations/20260730090000_create_
 * advanced_tms_geofence_route_deviation_signals.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseShipmentMilestoneCandidate,
  parseShipmentExceptionSignal,
  ConfirmMilestoneCandidateInputSchema,
  DismissMilestoneCandidateInputSchema,
  ConfirmExceptionSignalInputSchema,
  DismissExceptionSignalInputSchema,
  type ShipmentMilestoneCandidate,
  type ShipmentExceptionSignal,
  type ConfirmMilestoneCandidateInput,
  type DismissMilestoneCandidateInput,
  type ConfirmExceptionSignalInput,
  type DismissExceptionSignalInput,
} from "../contracts/geofence-route-deviation-signals/geofence-route-deviation-signals.ts";
import { MilestoneEventSchema, parseMilestoneEvent, type MilestoneEvent } from "../contracts/milestone-management/milestone-management.ts";
import { OperationalExceptionSchema, parseOperationalException, type OperationalException } from "../contracts/exception-escalation/exception-escalation.ts";

export type GeofenceSignalsMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const GEOFENCE_SIGNALS_KNOWN_MUTATION_ERROR_CODES = [
  "milestone_candidate_not_found",
  "milestone_candidate_not_pending",
  "milestone_candidate_conflicts_confirmed_event",
  "exception_signal_not_found",
  "exception_signal_not_pending",
  "shipment_order_not_found",
  "insufficient_authority",
] as const;
type KnownGeofenceSignalsMutationErrorCode = (typeof GEOFENCE_SIGNALS_KNOWN_MUTATION_ERROR_CODES)[number];
export type GeofenceSignalsMutationErrorCode = KnownGeofenceSignalsMutationErrorCode | "mutation_failed" | "invalid_response";

export class GeofenceSignalsMutationError extends Error {
  readonly code: GeofenceSignalsMutationErrorCode;

  constructor(code: GeofenceSignalsMutationErrorCode, message: string) {
    super(message);
    this.name = "GeofenceSignalsMutationError";
    this.code = code;
  }
}

function classifyError(message: string): GeofenceSignalsMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (GEOFENCE_SIGNALS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownGeofenceSignalsMutationErrorCode)
    : "mutation_failed";
}

function parseRpcMilestoneEvent(data: unknown, rpcName: string): MilestoneEvent {
  if (!data || typeof data !== "object") {
    throw new GeofenceSignalsMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseMilestoneEvent(data as Record<string, unknown>);
}

function parseRpcOperationalException(data: unknown, rpcName: string): OperationalException {
  if (!data || typeof data !== "object") {
    throw new GeofenceSignalsMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseOperationalException(data as Record<string, unknown>);
}

function parseRpcMilestoneCandidate(data: unknown, rpcName: string): ShipmentMilestoneCandidate {
  if (!data || typeof data !== "object") {
    throw new GeofenceSignalsMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseShipmentMilestoneCandidate(data as Record<string, unknown>);
}

function parseRpcExceptionSignal(data: unknown, rpcName: string): ShipmentExceptionSignal {
  if (!data || typeof data !== "object") {
    throw new GeofenceSignalsMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseShipmentExceptionSignal(data as Record<string, unknown>);
}

/**
 * The sole path from a staged candidate to a real app.milestone_events row -- always
 * uses the confirming actor's own real, RBAC-checked identity, never a system bypass.
 * A candidate dated after an already-confirmed terminal milestone on the same shipment
 * order is rejected unless overrideConflict is set.
 */
export async function confirmMilestoneCandidate(
  client: GeofenceSignalsMutationRpcClient,
  input: ConfirmMilestoneCandidateInput,
): Promise<MilestoneEvent> {
  const parsedInput = ConfirmMilestoneCandidateInputSchema.parse(input);
  const { data, error } = await client.rpc("confirm_milestone_candidate", {
    p_candidate_id: parsedInput.candidateId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_override_event_time: parsedInput.overrideEventTime,
    p_override_conflict: parsedInput.overrideConflict,
  });
  if (error) {
    throw new GeofenceSignalsMutationError(classifyError(error.message), error.message);
  }
  return parseRpcMilestoneEvent(data, "confirm_milestone_candidate");
}

/** Closes a candidate out without ever creating a real milestone event. */
export async function dismissMilestoneCandidate(
  client: GeofenceSignalsMutationRpcClient,
  input: DismissMilestoneCandidateInput,
): Promise<ShipmentMilestoneCandidate> {
  const parsedInput = DismissMilestoneCandidateInputSchema.parse(input);
  const { data, error } = await client.rpc("dismiss_milestone_candidate", {
    p_candidate_id: parsedInput.candidateId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_review_note: parsedInput.reviewNote,
  });
  if (error) {
    throw new GeofenceSignalsMutationError(classifyError(error.message), error.message);
  }
  return parseRpcMilestoneCandidate(data, "dismiss_milestone_candidate");
}

/**
 * The sole path from a staged signal to a real app.operational_exceptions row --
 * reuses OPS-174's own (tenant, shipmentOrderId, correlationKey) idempotent dedup, so a
 * retried confirm producing the identical correlation key returns the same exception.
 */
export async function confirmExceptionSignal(
  client: GeofenceSignalsMutationRpcClient,
  input: ConfirmExceptionSignalInput,
): Promise<OperationalException> {
  const parsedInput = ConfirmExceptionSignalInputSchema.parse(input);
  const { data, error } = await client.rpc("confirm_exception_signal", {
    p_signal_id: parsedInput.signalId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new GeofenceSignalsMutationError(classifyError(error.message), error.message);
  }
  return parseRpcOperationalException(data, "confirm_exception_signal");
}

/** Closes a signal out without ever creating a real operational exception. */
export async function dismissExceptionSignal(
  client: GeofenceSignalsMutationRpcClient,
  input: DismissExceptionSignalInput,
): Promise<ShipmentExceptionSignal> {
  const parsedInput = DismissExceptionSignalInputSchema.parse(input);
  const { data, error } = await client.rpc("dismiss_exception_signal", {
    p_signal_id: parsedInput.signalId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_review_note: parsedInput.reviewNote,
  });
  if (error) {
    throw new GeofenceSignalsMutationError(classifyError(error.message), error.message);
  }
  return parseRpcExceptionSignal(data, "dismiss_exception_signal");
}

// Re-exported so a caller mapping ATW-226G RPC outcomes has both schemas available
// without a second import from unrelated capability modules.
export { MilestoneEventSchema, OperationalExceptionSchema };
