import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseCustomerShipmentTracking, VEHICLE_POSITION_STATUSES, ETA_STATUSES, POSITION_UNAVAILABLE_REASONS } from "./customer-shipment-tracking.ts";

const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";

const NOT_ENTITLED_ROW = {
  shipment_order_id: SHIPMENT_ID,
  milestones: [{ code: "pickup_arrival", name: "Pickup Arrival", category: "pickup", eventTime: "2026-08-16T00:00:00.000Z" }],
  tracking_entitled: false,
  position_unavailable_reason: "tracking_not_entitled",
  vehicle_position_geojson: null,
  vehicle_position_updated_at: null,
  vehicle_position_status: null,
  eta_status: null,
  eta_at: null,
};

const LIVE_ROW = {
  shipment_order_id: SHIPMENT_ID,
  milestones: [],
  tracking_entitled: true,
  position_unavailable_reason: null,
  vehicle_position_geojson: { type: "Point", coordinates: [106.845599, -6.208763] },
  vehicle_position_updated_at: "2026-08-16T00:05:00.000Z",
  vehicle_position_status: "live",
  eta_status: "on_time",
  eta_at: "2026-08-16T01:00:00.000Z",
};

describe("parseCustomerShipmentTracking", () => {
  test("maps a not-entitled response, milestones camelCased already", () => {
    const parsed = parseCustomerShipmentTracking(NOT_ENTITLED_ROW);
    assert.equal(parsed.shipmentOrderId, SHIPMENT_ID);
    assert.equal(parsed.trackingEntitled, false);
    assert.equal(parsed.positionUnavailableReason, "tracking_not_entitled");
    assert.equal(parsed.vehiclePositionGeojson, null);
    assert.deepEqual(parsed.milestones, [{ code: "pickup_arrival", name: "Pickup Arrival", category: "pickup", eventTime: "2026-08-16T00:00:00.000Z" }]);
  });

  test("maps a live position/ETA response", () => {
    const parsed = parseCustomerShipmentTracking(LIVE_ROW);
    assert.equal(parsed.trackingEntitled, true);
    assert.equal(parsed.positionUnavailableReason, null);
    assert.deepEqual(parsed.vehiclePositionGeojson, { type: "Point", coordinates: [106.845599, -6.208763] });
    assert.equal(parsed.vehiclePositionStatus, "live");
    assert.equal(parsed.etaStatus, "on_time");
  });

  test("defaults a missing milestones array to empty, never throws", () => {
    const parsed = parseCustomerShipmentTracking({ ...NOT_ENTITLED_ROW, milestones: undefined });
    assert.deepEqual(parsed.milestones, []);
  });

  test("rejects an unrecognized vehiclePositionStatus", () => {
    assert.throws(() => parseCustomerShipmentTracking({ ...LIVE_ROW, vehicle_position_status: "not_a_real_status" }));
  });

  test("rejects an unrecognized positionUnavailableReason", () => {
    assert.throws(() => parseCustomerShipmentTracking({ ...NOT_ENTITLED_ROW, position_unavailable_reason: "not_a_real_reason" }));
  });

  test("every real vehicle position status is exactly the migration's 3-value set", () => {
    assert.deepEqual([...VEHICLE_POSITION_STATUSES], ["live", "delayed", "unavailable"]);
  });

  test("every real eta status is exactly the migration's 3-value set", () => {
    assert.deepEqual([...ETA_STATUSES], ["on_time", "delayed", "unavailable"]);
  });

  test("every real position-unavailable reason is exactly the migration's 5-value set", () => {
    assert.deepEqual([...POSITION_UNAVAILABLE_REASONS], ["tracking_not_entitled", "no_active_leg", "no_vehicle_assigned", "not_customer_visible", "no_live_position"]);
  });
});
