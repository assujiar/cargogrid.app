/**
 * Land, Air and Sea Baseline contract (OPS-171, CG-S8-OPS-005). Mirrors
 * supabase/migrations/20260727120000_create_operations_mode_baseline.sql's
 * app.shipment_mode_profiles shape and its RPCs.
 *
 * One bounded, single-mode/single-leg mode profile per Shipment Order (OPS-169).
 * Vehicle/vendor/carrier references are deliberately plain text -- binding these to
 * real canonical vendor/fleet/vehicle/driver references is OPS-172's (Resource
 * Assignment) own explicit scope, not anticipated here. Modeled here as a real
 * TypeScript discriminated union even though the database stores every mode's own
 * columns on one shared table (structurally mutually exclusive, enforced by
 * shipment_mode_profiles_mode_fields_check, never merely a convention).
 */

import { z } from "zod";

export const SHIPMENT_MODE_PROFILE_MODES = ["land", "air", "sea"] as const;
export const ShipmentModeProfileModeSchema = z.enum(SHIPMENT_MODE_PROFILE_MODES);
export type ShipmentModeProfileMode = z.infer<typeof ShipmentModeProfileModeSchema>;

const BaseFieldsSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});

export const LandModeProfileSchema = BaseFieldsSchema.extend({
  mode: z.literal("land"),
  vehicleRef: z.string(),
  vendorRef: z.string(),
  pickupAddress: z.string(),
  deliveryAddress: z.string(),
});
export type LandModeProfile = z.infer<typeof LandModeProfileSchema>;

export const AirModeProfileSchema = BaseFieldsSchema.extend({
  mode: z.literal("air"),
  awbNumber: z.string(),
  flightNumber: z.string(),
  originAirport: z.string(),
  destinationAirport: z.string(),
});
export type AirModeProfile = z.infer<typeof AirModeProfileSchema>;

export const SeaModeProfileSchema = BaseFieldsSchema.extend({
  mode: z.literal("sea"),
  blNumber: z.string(),
  bookingNumber: z.string(),
  vesselName: z.string(),
  originPort: z.string(),
  destinationPort: z.string(),
  containerNumber: z.string().nullable(),
  containerType: z.string().nullable(),
});
export type SeaModeProfile = z.infer<typeof SeaModeProfileSchema>;

export const ShipmentModeProfileSchema = z.discriminatedUnion("mode", [LandModeProfileSchema, AirModeProfileSchema, SeaModeProfileSchema]);
export type ShipmentModeProfile = z.infer<typeof ShipmentModeProfileSchema>;

/** Maps a raw app.shipment_mode_profiles row (snake_case, every mode's own columns present but only the matching mode's own subset non-null) into the discriminated union. */
export function parseShipmentModeProfile(row: Record<string, unknown>): ShipmentModeProfile {
  const base = {
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
  if (row.mode === "land") {
    return LandModeProfileSchema.parse({
      ...base,
      mode: "land",
      vehicleRef: row.land_vehicle_ref,
      vendorRef: row.land_vendor_ref,
      pickupAddress: row.land_pickup_address,
      deliveryAddress: row.land_delivery_address,
    });
  }
  if (row.mode === "air") {
    return AirModeProfileSchema.parse({
      ...base,
      mode: "air",
      awbNumber: row.air_awb_number,
      flightNumber: row.air_flight_number,
      originAirport: row.air_origin_airport,
      destinationAirport: row.air_destination_airport,
    });
  }
  return SeaModeProfileSchema.parse({
    ...base,
    mode: "sea",
    blNumber: row.sea_bl_number,
    bookingNumber: row.sea_booking_number,
    vesselName: row.sea_vessel_name,
    originPort: row.sea_origin_port,
    destinationPort: row.sea_destination_port,
    containerNumber: row.sea_container_number ?? null,
    containerType: row.sea_container_type ?? null,
  });
}

export const SetShipmentModeProfileInputSchema = z.discriminatedUnion("mode", [
  z.object({
    shipmentOrderId: z.string().uuid(),
    mode: z.literal("land"),
    vehicleRef: z.string().min(1),
    vendorRef: z.string().min(1),
    pickupAddress: z.string().min(1),
    deliveryAddress: z.string().min(1),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string().min(1),
  }),
  z.object({
    shipmentOrderId: z.string().uuid(),
    mode: z.literal("air"),
    awbNumber: z.string().min(1),
    flightNumber: z.string().min(1),
    originAirport: z.string().min(1),
    destinationAirport: z.string().min(1),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string().min(1),
  }),
  z.object({
    shipmentOrderId: z.string().uuid(),
    mode: z.literal("sea"),
    blNumber: z.string().min(1),
    bookingNumber: z.string().min(1),
    vesselName: z.string().min(1),
    originPort: z.string().min(1),
    destinationPort: z.string().min(1),
    containerNumber: z.string().nullable().default(null),
    containerType: z.string().nullable().default(null),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string().min(1),
  }),
]);
export type SetShipmentModeProfileInput = z.input<typeof SetShipmentModeProfileInputSchema>;

export const ChangeShipmentModeInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  newMode: ShipmentModeProfileModeSchema,
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ChangeShipmentModeInput = z.input<typeof ChangeShipmentModeInputSchema>;
