import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseShipmentModeProfile, SetShipmentModeProfileInputSchema, ChangeShipmentModeInputSchema } from "./shipment-mode-baseline.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const PROFILE_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const BASE_ROW = {
  id: PROFILE_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("parseShipmentModeProfile", () => {
  test("maps a land profile", () => {
    const profile = parseShipmentModeProfile({
      ...BASE_ROW,
      mode: "land",
      land_vehicle_ref: "TRK-001",
      land_vendor_ref: "VENDOR-TRK-1",
      land_pickup_address: "Jl. Gudang 1",
      land_delivery_address: "Jl. Pasar 1",
      air_awb_number: null,
      air_flight_number: null,
      air_origin_airport: null,
      air_destination_airport: null,
      sea_bl_number: null,
      sea_booking_number: null,
      sea_vessel_name: null,
      sea_origin_port: null,
      sea_destination_port: null,
      sea_container_number: null,
      sea_container_type: null,
    });
    assert.equal(profile.mode, "land");
    if (profile.mode === "land") {
      assert.equal(profile.vehicleRef, "TRK-001");
    }
  });

  test("maps an air profile", () => {
    const profile = parseShipmentModeProfile({
      ...BASE_ROW,
      mode: "air",
      land_vehicle_ref: null,
      land_vendor_ref: null,
      land_pickup_address: null,
      land_delivery_address: null,
      air_awb_number: "AWB-12345678",
      air_flight_number: "GA-402",
      air_origin_airport: "CGK",
      air_destination_airport: "DPS",
      sea_bl_number: null,
      sea_booking_number: null,
      sea_vessel_name: null,
      sea_origin_port: null,
      sea_destination_port: null,
      sea_container_number: null,
      sea_container_type: null,
    });
    assert.equal(profile.mode, "air");
    if (profile.mode === "air") {
      assert.equal(profile.awbNumber, "AWB-12345678");
    }
  });

  test("maps a sea profile with no container reference (LCL, optional)", () => {
    const profile = parseShipmentModeProfile({
      ...BASE_ROW,
      mode: "sea",
      land_vehicle_ref: null,
      land_vendor_ref: null,
      land_pickup_address: null,
      land_delivery_address: null,
      air_awb_number: null,
      air_flight_number: null,
      air_origin_airport: null,
      air_destination_airport: null,
      sea_bl_number: "BL-2026-0001",
      sea_booking_number: "BOOK-2026-0001",
      sea_vessel_name: "MV Contoso Star",
      sea_origin_port: "IDJKT",
      sea_destination_port: "SGSIN",
      sea_container_number: null,
      sea_container_type: null,
    });
    assert.equal(profile.mode, "sea");
    if (profile.mode === "sea") {
      assert.equal(profile.containerNumber, null);
    }
  });
});

describe("SetShipmentModeProfileInputSchema", () => {
  test("requires every land field to be non-empty", () => {
    assert.throws(() =>
      SetShipmentModeProfileInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        mode: "land",
        vehicleRef: "TRK-001",
        vendorRef: "",
        pickupAddress: "Jl. A",
        deliveryAddress: "Jl. B",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("defaults sea containerNumber/containerType to null", () => {
    const parsed = SetShipmentModeProfileInputSchema.parse({
      shipmentOrderId: SHIPMENT_ID,
      mode: "sea",
      blNumber: "BL-1",
      bookingNumber: "BOOK-1",
      vesselName: "MV Test",
      originPort: "IDJKT",
      destinationPort: "SGSIN",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    if (parsed.mode === "sea") {
      assert.equal(parsed.containerNumber, null);
    }
  });
});

describe("ChangeShipmentModeInputSchema", () => {
  test("rejects an unsupported mode", () => {
    assert.throws(() =>
      ChangeShipmentModeInputSchema.parse({ shipmentOrderId: SHIPMENT_ID, newMode: "rail", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });

  test("requires a positive expectedVersion", () => {
    assert.throws(() =>
      ChangeShipmentModeInputSchema.parse({ shipmentOrderId: SHIPMENT_ID, newMode: "air", expectedVersion: 0, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });
});
