/**
 * Multi-Leg and Multimodal Shipment mutation primitives (ATW-221, CG-S10-ATW-002).
 * Thin, typed wrappers around the RPCs in
 * supabase/migrations/20260729290000_create_advanced_tms_multi_leg_shipment.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  AddShipmentLegInputSchema,
  CancelShipmentLegInputSchema,
  AddShipmentLegStopInputSchema,
  AllocateShipmentLegCargoInputSchema,
  ConfirmShipmentLegNetworkInputSchema,
  TransitionShipmentLegInputSchema,
  RecordShipmentLegCustodyEventInputSchema,
  MigrateLegacyShipmentToLegNetworkInputSchema,
  parseShipmentLeg,
  parseShipmentLegStop,
  parseShipmentLegCargoAllocation,
  parseShipmentLegCustodyEvent,
  type AddShipmentLegInput,
  type CancelShipmentLegInput,
  type AddShipmentLegStopInput,
  type AllocateShipmentLegCargoInput,
  type ConfirmShipmentLegNetworkInput,
  type TransitionShipmentLegInput,
  type RecordShipmentLegCustodyEventInput,
  type MigrateLegacyShipmentToLegNetworkInput,
  type ShipmentLeg,
  type ShipmentLegStop,
  type ShipmentLegCargoAllocation,
  type ShipmentLegCustodyEvent,
} from "../contracts/multi-leg-shipment/multi-leg-shipment.ts";
import { parseShipmentOrder, type ShipmentOrder } from "../contracts/shipment-order/shipment-order.ts";

export type MultiLegShipmentMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const MULTI_LEG_SHIPMENT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_mode",
  "idempotency_key_required",
  "invalid_sequence",
  "shipment_order_not_found",
  "leg_sequence_duplicate",
  "carrier_not_found",
  "leg_not_found",
  "leg_not_mutable",
  "stale_version",
  "cancel_reason_required",
  "invalid_stop_type",
  "location_name_required",
  "cargo_over_allocated",
  "network_empty",
  "network_sequence_gap",
  "network_cargo_incomplete",
  "invalid_leg_status_transition",
  "network_not_confirmed",
  "invalid_event_type",
  "to_party_required",
] as const;
type KnownMultiLegShipmentMutationErrorCode = (typeof MULTI_LEG_SHIPMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type MultiLegShipmentMutationErrorCode = KnownMultiLegShipmentMutationErrorCode | "mutation_failed" | "invalid_response";

export class MultiLegShipmentMutationError extends Error {
  readonly code: MultiLegShipmentMutationErrorCode;

  constructor(code: MultiLegShipmentMutationErrorCode, message: string) {
    super(message);
    this.name = "MultiLegShipmentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): MultiLegShipmentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (MULTI_LEG_SHIPMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownMultiLegShipmentMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: MultiLegShipmentMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new MultiLegShipmentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MultiLegShipmentMutationError("invalid_response", `${fn} returned no row`);
  }
  return data as Record<string, unknown>;
}

export async function addShipmentLeg(client: MultiLegShipmentMutationRpcClient, input: AddShipmentLegInput): Promise<ShipmentLeg> {
  const parsedInput = AddShipmentLegInputSchema.parse(input);
  const row = await callRpc(client, "add_shipment_leg", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_sequence_no: parsedInput.sequenceNo,
    p_mode: parsedInput.mode,
    p_carrier_master_id: parsedInput.carrierMasterId,
    p_planned_departure_at: parsedInput.plannedDepartureAt,
    p_planned_arrival_at: parsedInput.plannedArrivalAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLeg(row);
}

/** Planned-only cancellation (never a hard delete). */
export async function cancelShipmentLeg(client: MultiLegShipmentMutationRpcClient, input: CancelShipmentLegInput): Promise<ShipmentLeg> {
  const parsedInput = CancelShipmentLegInputSchema.parse(input);
  const row = await callRpc(client, "cancel_shipment_leg", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLeg(row);
}

/** Only while the owning leg is planned. */
export async function addShipmentLegStop(client: MultiLegShipmentMutationRpcClient, input: AddShipmentLegStopInput): Promise<ShipmentLegStop> {
  const parsedInput = AddShipmentLegStopInputSchema.parse(input);
  const row = await callRpc(client, "add_shipment_leg_stop", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_stop_sequence: parsedInput.stopSequence,
    p_stop_type: parsedInput.stopType,
    p_location_name: parsedInput.locationName,
    p_address: parsedInput.address,
    p_longitude: parsedInput.longitude,
    p_latitude: parsedInput.latitude,
    p_planned_at: parsedInput.plannedAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  // The mutation RPC returns the raw geography-bearing row shape (not the GeoJSON
  // projection app.get_shipment_leg_stops provides) -- location is not surfaced
  // back on the mutation response; callers re-read via listShipmentLegStops.
  return parseShipmentLegStop({ ...row, location_geojson: null });
}

export async function allocateShipmentLegCargo(client: MultiLegShipmentMutationRpcClient, input: AllocateShipmentLegCargoInput): Promise<ShipmentLegCargoAllocation> {
  const parsedInput = AllocateShipmentLegCargoInputSchema.parse(input);
  const row = await callRpc(client, "allocate_shipment_leg_cargo", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_allocated_quantity: parsedInput.allocatedQuantity,
    p_allocated_weight_kg: parsedInput.allocatedWeightKg,
    p_allocated_volume_cbm: parsedInput.allocatedVolumeCbm,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLegCargoAllocation(row);
}

/** Validates leg-sequence contiguity and full cargo allocation, then sets leg_network_status = confirmed. */
export async function confirmShipmentLegNetwork(client: MultiLegShipmentMutationRpcClient, input: ConfirmShipmentLegNetworkInput): Promise<ShipmentOrder> {
  const parsedInput = ConfirmShipmentLegNetworkInputSchema.parse(input);
  const row = await callRpc(client, "confirm_shipment_leg_network", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentOrder(row);
}

/** Hardcoded edges planned->dispatched->in_transit->arrived->completed, plus any non-terminal state->cancelled. */
export async function transitionShipmentLeg(client: MultiLegShipmentMutationRpcClient, input: TransitionShipmentLegInput): Promise<ShipmentLeg> {
  const parsedInput = TransitionShipmentLegInputSchema.parse(input);
  const row = await callRpc(client, "transition_shipment_leg", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_to_status: parsedInput.toStatus,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLeg(row);
}

/** Append-only, server-assigned sequence_no. */
export async function recordShipmentLegCustodyEvent(client: MultiLegShipmentMutationRpcClient, input: RecordShipmentLegCustodyEventInput): Promise<ShipmentLegCustodyEvent> {
  const parsedInput = RecordShipmentLegCustodyEventInputSchema.parse(input);
  const row = await callRpc(client, "record_shipment_leg_custody_event", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_event_type: parsedInput.eventType,
    p_from_party_snapshot: parsedInput.fromPartySnapshot,
    p_to_party_snapshot: parsedInput.toPartySnapshot,
    p_occurred_at: parsedInput.occurredAt,
    p_evidence: parsedInput.evidence,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLegCustodyEvent(row);
}

/** Idempotent expand-only backfill for a pre-existing single-leg Shipment Order. */
export async function migrateLegacyShipmentToLegNetwork(client: MultiLegShipmentMutationRpcClient, input: MigrateLegacyShipmentToLegNetworkInput): Promise<ShipmentLeg> {
  const parsedInput = MigrateLegacyShipmentToLegNetworkInputSchema.parse(input);
  const row = await callRpc(client, "migrate_legacy_shipment_to_leg_network", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseShipmentLeg(row);
}
