/**
 * Rebaseline mutation primitive (ATW-228, CG-S10-ATW-009). Thin, typed wrapper around
 * app.rebaseline_shipment_leg_schedule
 * (supabase/migrations/20260730130000_create_advanced_tms_milestone_exception_telemetry.sql).
 *
 * Every other ATW-228 mutation path (milestone/exception provenance, tracking-health
 * signal confirm/dismiss) widens an already-existing RPC in place -- see
 * server/mutations/{milestone-management,exception-escalation,geofence-route-
 * deviation-signals}.ts, unchanged by this module.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { RebaselineShipmentLegScheduleInputSchema, type RebaselineShipmentLegScheduleInput } from "../contracts/milestone-exception-telemetry/milestone-exception-telemetry.ts";
import { parseShipmentLeg, type ShipmentLeg } from "../contracts/multi-leg-shipment/multi-leg-shipment.ts";

export type MilestoneExceptionTelemetryMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const MILESTONE_EXCEPTION_TELEMETRY_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "reason_required",
  "invalid_schedule",
  "leg_not_found",
  "stale_version",
  "leg_not_unstarted",
] as const;
type KnownMilestoneExceptionTelemetryMutationErrorCode = (typeof MILESTONE_EXCEPTION_TELEMETRY_KNOWN_MUTATION_ERROR_CODES)[number];
export type MilestoneExceptionTelemetryMutationErrorCode = KnownMilestoneExceptionTelemetryMutationErrorCode | "mutation_failed" | "invalid_response";

export class MilestoneExceptionTelemetryMutationError extends Error {
  readonly code: MilestoneExceptionTelemetryMutationErrorCode;

  constructor(code: MilestoneExceptionTelemetryMutationErrorCode, message: string) {
    super(message);
    this.name = "MilestoneExceptionTelemetryMutationError";
    this.code = code;
  }
}

function classifyError(message: string): MilestoneExceptionTelemetryMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (MILESTONE_EXCEPTION_TELEMETRY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownMilestoneExceptionTelemetryMutationErrorCode)
    : "mutation_failed";
}

export async function rebaselineShipmentLegSchedule(
  client: MilestoneExceptionTelemetryMutationRpcClient,
  input: RebaselineShipmentLegScheduleInput,
): Promise<ShipmentLeg> {
  const parsedInput = RebaselineShipmentLegScheduleInputSchema.parse(input);
  const { data, error } = await client.rpc("rebaseline_shipment_leg_schedule", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_new_planned_departure_at: parsedInput.newPlannedDepartureAt,
    p_new_planned_arrival_at: parsedInput.newPlannedArrivalAt,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MilestoneExceptionTelemetryMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MilestoneExceptionTelemetryMutationError("invalid_response", "rebaseline_shipment_leg_schedule returned no row");
  }
  return parseShipmentLeg(data as Record<string, unknown>);
}
