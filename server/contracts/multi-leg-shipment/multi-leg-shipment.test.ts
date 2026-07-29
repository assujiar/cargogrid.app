import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseShipmentLeg,
  parseShipmentLegStop,
  parseShipmentLegCargoAllocation,
  parseShipmentLegCustodyEvent,
  AddShipmentLegInputSchema,
  AddShipmentLegStopInputSchema,
} from "./multi-leg-shipment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "423e4567-e89b-12d3-a456-426614174000";
const CARRIER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseShipmentLeg", () => {
  test("maps a planned leg with a carrier reference", () => {
    const leg = parseShipmentLeg({
      id: LEG_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      sequence_no: 1,
      idempotency_key: "idem-leg-1",
      mode: "land",
      leg_status: "planned",
      is_legacy_compat: false,
      carrier_master_id: CARRIER_ID,
      planned_departure_at: null,
      planned_arrival_at: null,
      actual_departure_at: null,
      actual_arrival_at: null,
      owner_user_id: ACTOR_ID,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(leg.sequenceNo, 1);
    assert.equal(leg.carrierMasterId, CARRIER_ID);
    assert.equal(leg.isLegacyCompat, false);
  });

  test("maps a legacy-compat leg with no carrier", () => {
    const leg = parseShipmentLeg({
      id: LEG_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      sequence_no: 1,
      idempotency_key: "legacy-compat:x",
      mode: "sea",
      leg_status: "completed",
      is_legacy_compat: true,
      carrier_master_id: null,
      planned_departure_at: null,
      planned_arrival_at: null,
      actual_departure_at: null,
      actual_arrival_at: null,
      owner_user_id: null,
      record_version: 1,
      created_by: null,
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(leg.isLegacyCompat, true);
    assert.equal(leg.carrierMasterId, null);
  });
});

describe("parseShipmentLegStop", () => {
  test("extracts longitude/latitude from a GeoJSON Point", () => {
    const stop = parseShipmentLegStop({
      id: LEG_ID,
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      stop_sequence: 1,
      stop_type: "pickup",
      location_name: "Jakarta Warehouse",
      address: null,
      location_geojson: { type: "Point", coordinates: [106.8456, -6.2088] },
      planned_at: null,
      actual_at: null,
      stop_status: "pending",
      record_version: 1,
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(stop.longitude, 106.8456);
    assert.equal(stop.latitude, -6.2088);
  });

  test("nulls longitude/latitude when no geography was recorded", () => {
    const stop = parseShipmentLegStop({
      id: LEG_ID,
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      stop_sequence: 2,
      stop_type: "delivery",
      location_name: "Surabaya Warehouse",
      address: null,
      location_geojson: null,
      planned_at: null,
      actual_at: null,
      stop_status: "pending",
      record_version: 1,
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(stop.longitude, null);
    assert.equal(stop.latitude, null);
  });
});

describe("parseShipmentLegCargoAllocation", () => {
  test("maps a cargo allocation row", () => {
    const allocation = parseShipmentLegCargoAllocation({
      id: LEG_ID,
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      allocated_quantity: 60,
      allocated_weight_kg: 3000,
      allocated_volume_cbm: 24,
      record_version: 1,
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(allocation.allocatedQuantity, 60);
  });
});

describe("parseShipmentLegCustodyEvent", () => {
  test("maps a custody event with a null from-party (initial custody)", () => {
    const event = parseShipmentLegCustodyEvent({
      id: LEG_ID,
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      sequence_no: 1,
      event_type: "custody_transfer",
      from_party_snapshot: null,
      to_party_snapshot: { party: "Driver A" },
      occurred_at: "2026-07-29T00:00:00.000Z",
      evidence: null,
      recorded_by: "tester",
      created_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(event.fromPartySnapshot, null);
    assert.deepEqual(event.toPartySnapshot, { party: "Driver A" });
  });
});

describe("AddShipmentLegInputSchema", () => {
  test("rejects a non-positive sequenceNo", () => {
    assert.throws(() =>
      AddShipmentLegInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        idempotencyKey: "idem-1",
        sequenceNo: 0,
        mode: "land",
        carrierMasterId: null,
        plannedDepartureAt: null,
        plannedArrivalAt: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("accepts a valid input", () => {
    const parsed = AddShipmentLegInputSchema.parse({
      shipmentOrderId: SHIPMENT_ID,
      idempotencyKey: "idem-1",
      sequenceNo: 1,
      mode: "sea",
      carrierMasterId: CARRIER_ID,
      plannedDepartureAt: null,
      plannedArrivalAt: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.mode, "sea");
  });
});

describe("AddShipmentLegStopInputSchema", () => {
  test("rejects an out-of-range latitude", () => {
    assert.throws(() =>
      AddShipmentLegStopInputSchema.parse({
        shipmentLegId: LEG_ID,
        stopSequence: 1,
        stopType: "pickup",
        locationName: "Jakarta Warehouse",
        address: null,
        longitude: 106.8456,
        latitude: 91,
        plannedAt: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("accepts null coordinates", () => {
    const parsed = AddShipmentLegStopInputSchema.parse({
      shipmentLegId: LEG_ID,
      stopSequence: 1,
      stopType: "transfer",
      locationName: "Surabaya Transfer Yard",
      address: null,
      longitude: null,
      latitude: null,
      plannedAt: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.longitude, null);
  });
});
