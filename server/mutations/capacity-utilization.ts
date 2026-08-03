/**
 * Capacity reservation mutation primitives (ATW-227, CG-S10-ATW-008). Thin, typed
 * wrappers around app.reserve_vehicle_capacity/app.consume_vehicle_capacity_
 * reservation/app.release_vehicle_capacity_reservation
 * (supabase/migrations/20260730120000_create_advanced_tms_capacity_utilization.sql).
 *
 * Tracking coverage/utilization is read-only (server/queries/capacity-utilization.ts)
 * -- no mutation wrapper exists for it, matching the migration's own §14 boundary
 * ("analytics APIs do not alter entitlements or source mappings").
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ReserveVehicleCapacityInputSchema,
  ConsumeVehicleCapacityReservationInputSchema,
  ReleaseVehicleCapacityReservationInputSchema,
  parseVehicleCapacityReservation,
  type ReserveVehicleCapacityInput,
  type ConsumeVehicleCapacityReservationInput,
  type ReleaseVehicleCapacityReservationInput,
  type VehicleCapacityReservation,
} from "../contracts/capacity-utilization/capacity-utilization.ts";

export type CapacityUtilizationMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CAPACITY_UTILIZATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "idempotency_key_required",
  "invalid_requested_weight",
  "invalid_requested_volume",
  "leg_not_found",
  "leg_schedule_required",
  "vehicle_not_assigned",
  "vehicle_not_active",
  "reservation_already_active",
  "capacity_exceeded",
  "reservation_not_found",
  "stale_version",
  "invalid_transition",
  "reason_required",
] as const;
type KnownCapacityUtilizationMutationErrorCode = (typeof CAPACITY_UTILIZATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type CapacityUtilizationMutationErrorCode = KnownCapacityUtilizationMutationErrorCode | "mutation_failed" | "invalid_response";

export class CapacityUtilizationMutationError extends Error {
  readonly code: CapacityUtilizationMutationErrorCode;

  constructor(code: CapacityUtilizationMutationErrorCode, message: string) {
    super(message);
    this.name = "CapacityUtilizationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CapacityUtilizationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CAPACITY_UTILIZATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownCapacityUtilizationMutationErrorCode)
    : "mutation_failed";
}

function parseReservationResponse(data: unknown, rpcName: string): VehicleCapacityReservation {
  if (!data || typeof data !== "object") {
    throw new CapacityUtilizationMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseVehicleCapacityReservation(data as Record<string, unknown>);
}

export async function reserveVehicleCapacity(client: CapacityUtilizationMutationRpcClient, input: ReserveVehicleCapacityInput): Promise<VehicleCapacityReservation> {
  const parsedInput = ReserveVehicleCapacityInputSchema.parse(input);
  const { data, error } = await client.rpc("reserve_vehicle_capacity", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_requested_weight_kg: parsedInput.requestedWeightKg,
    p_requested_volume_cbm: parsedInput.requestedVolumeCbm,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CapacityUtilizationMutationError(classifyError(error.message), error.message);
  }
  return parseReservationResponse(data, "reserve_vehicle_capacity");
}

export async function consumeVehicleCapacityReservation(
  client: CapacityUtilizationMutationRpcClient,
  input: ConsumeVehicleCapacityReservationInput,
): Promise<VehicleCapacityReservation> {
  const parsedInput = ConsumeVehicleCapacityReservationInputSchema.parse(input);
  const { data, error } = await client.rpc("consume_vehicle_capacity_reservation", {
    p_reservation_id: parsedInput.reservationId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CapacityUtilizationMutationError(classifyError(error.message), error.message);
  }
  return parseReservationResponse(data, "consume_vehicle_capacity_reservation");
}

export async function releaseVehicleCapacityReservation(
  client: CapacityUtilizationMutationRpcClient,
  input: ReleaseVehicleCapacityReservationInput,
): Promise<VehicleCapacityReservation> {
  const parsedInput = ReleaseVehicleCapacityReservationInputSchema.parse(input);
  const { data, error } = await client.rpc("release_vehicle_capacity_reservation", {
    p_reservation_id: parsedInput.reservationId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CapacityUtilizationMutationError(classifyError(error.message), error.message);
  }
  return parseReservationResponse(data, "release_vehicle_capacity_reservation");
}
