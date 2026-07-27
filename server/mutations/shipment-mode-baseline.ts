/**
 * Land, Air and Sea Baseline mutation primitives (OPS-171, CG-S8-OPS-005). Thin,
 * typed wrappers around app.set_shipment_mode_profile / app.change_shipment_mode
 * (supabase/migrations/20260727120000_create_operations_mode_baseline.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SetShipmentModeProfileInputSchema,
  ChangeShipmentModeInputSchema,
  parseShipmentModeProfile,
  type SetShipmentModeProfileInput,
  type ChangeShipmentModeInput,
  type ShipmentModeProfile,
} from "../contracts/shipment-mode-baseline/shipment-mode-baseline.ts";
import { parseShipmentOrder, type ShipmentOrder } from "../contracts/shipment-order/shipment-order.ts";

export type ShipmentModeBaselineMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SHIPMENT_MODE_BASELINE_KNOWN_MUTATION_ERROR_CODES = [
  "shipment_order_not_found",
  "invalid_transition",
  "missing_required_reference",
  "insufficient_authority",
  "invalid_mode",
  "stale_version",
  "confirmed_mode_change_blocked",
] as const;
type KnownShipmentModeBaselineMutationErrorCode = (typeof SHIPMENT_MODE_BASELINE_KNOWN_MUTATION_ERROR_CODES)[number];
export type ShipmentModeBaselineMutationErrorCode = KnownShipmentModeBaselineMutationErrorCode | "mutation_failed" | "invalid_response";

export class ShipmentModeBaselineMutationError extends Error {
  readonly code: ShipmentModeBaselineMutationErrorCode;

  constructor(code: ShipmentModeBaselineMutationErrorCode, message: string) {
    super(message);
    this.name = "ShipmentModeBaselineMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ShipmentModeBaselineMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SHIPMENT_MODE_BASELINE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownShipmentModeBaselineMutationErrorCode)
    : "mutation_failed";
}

/**
 * The one idempotent create-or-update path -- mode is always read from the
 * shipment itself server-side, never re-derived here. Blocked only once the
 * shipment is cancelled.
 */
export async function setShipmentModeProfile(client: ShipmentModeBaselineMutationRpcClient, input: SetShipmentModeProfileInput): Promise<ShipmentModeProfile> {
  const parsedInput = SetShipmentModeProfileInputSchema.parse(input);
  const args =
    parsedInput.mode === "land"
      ? {
          p_land_vehicle_ref: parsedInput.vehicleRef,
          p_land_vendor_ref: parsedInput.vendorRef,
          p_land_pickup_address: parsedInput.pickupAddress,
          p_land_delivery_address: parsedInput.deliveryAddress,
          p_air_awb_number: null,
          p_air_flight_number: null,
          p_air_origin_airport: null,
          p_air_destination_airport: null,
          p_sea_bl_number: null,
          p_sea_booking_number: null,
          p_sea_vessel_name: null,
          p_sea_origin_port: null,
          p_sea_destination_port: null,
          p_sea_container_number: null,
          p_sea_container_type: null,
        }
      : parsedInput.mode === "air"
        ? {
            p_land_vehicle_ref: null,
            p_land_vendor_ref: null,
            p_land_pickup_address: null,
            p_land_delivery_address: null,
            p_air_awb_number: parsedInput.awbNumber,
            p_air_flight_number: parsedInput.flightNumber,
            p_air_origin_airport: parsedInput.originAirport,
            p_air_destination_airport: parsedInput.destinationAirport,
            p_sea_bl_number: null,
            p_sea_booking_number: null,
            p_sea_vessel_name: null,
            p_sea_origin_port: null,
            p_sea_destination_port: null,
            p_sea_container_number: null,
            p_sea_container_type: null,
          }
        : {
            p_land_vehicle_ref: null,
            p_land_vendor_ref: null,
            p_land_pickup_address: null,
            p_land_delivery_address: null,
            p_air_awb_number: null,
            p_air_flight_number: null,
            p_air_origin_airport: null,
            p_air_destination_airport: null,
            p_sea_bl_number: parsedInput.blNumber,
            p_sea_booking_number: parsedInput.bookingNumber,
            p_sea_vessel_name: parsedInput.vesselName,
            p_sea_origin_port: parsedInput.originPort,
            p_sea_destination_port: parsedInput.destinationPort,
            p_sea_container_number: parsedInput.containerNumber,
            p_sea_container_type: parsedInput.containerType,
          };

  const { data, error } = await client.rpc("set_shipment_mode_profile", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    ...args,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ShipmentModeBaselineMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ShipmentModeBaselineMutationError("invalid_response", "set_shipment_mode_profile returned no row");
  }
  return parseShipmentModeProfile(data as Record<string, unknown>);
}

/** The one path that may alter a Shipment Order's own mode -- draft-only, reconciles (deletes) the prior incompatible profile. */
export async function changeShipmentMode(client: ShipmentModeBaselineMutationRpcClient, input: ChangeShipmentModeInput): Promise<ShipmentOrder> {
  const parsedInput = ChangeShipmentModeInputSchema.parse(input);
  const { data, error } = await client.rpc("change_shipment_mode", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_new_mode: parsedInput.newMode,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ShipmentModeBaselineMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ShipmentModeBaselineMutationError("invalid_response", "change_shipment_mode returned no row");
  }
  return parseShipmentOrder(data as Record<string, unknown>);
}
