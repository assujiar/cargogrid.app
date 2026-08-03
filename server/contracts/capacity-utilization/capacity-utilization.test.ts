import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseVehicleCapacityReservation,
  parseTenantTrackingCoverageRow,
  parseTenantTrackingUtilizationSummary,
  ReserveVehicleCapacityInputSchema,
} from "./capacity-utilization.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const VEHICLE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseVehicleCapacityReservation", () => {
  test("maps a held reservation row", () => {
    const reservation = parseVehicleCapacityReservation({
      id: "823e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      vehicle_master_id: VEHICLE_ID,
      idempotency_key: "leg-1-reserve",
      requested_weight_kg: "1200.5",
      requested_volume_cbm: "8.25",
      window_start: "2026-08-03T00:00:00.000Z",
      window_end: "2026-08-04T00:00:00.000Z",
      status: "held",
      released_reason: null,
      record_version: 1,
      created_by: "dispatcher",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(reservation.status, "held");
    assert.equal(reservation.requestedWeightKg, 1200.5);
    assert.equal(reservation.releasedReason, null);
  });

  test("maps a released reservation with a reason", () => {
    const reservation = parseVehicleCapacityReservation({
      id: "823e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      vehicle_master_id: VEHICLE_ID,
      idempotency_key: "leg-1-reserve",
      requested_weight_kg: null,
      requested_volume_cbm: null,
      window_start: "2026-08-03T00:00:00.000Z",
      window_end: "2026-08-04T00:00:00.000Z",
      status: "released",
      released_reason: "leg_completed",
      record_version: 2,
      created_by: "dispatcher",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T01:00:00.000Z",
    });
    assert.equal(reservation.status, "released");
    assert.equal(reservation.releasedReason, "leg_completed");
  });
});

describe("parseTenantTrackingCoverageRow", () => {
  test("maps a hybrid, currently-tracked vehicle with reserved capacity", () => {
    const row = parseTenantTrackingCoverageRow({
      vehicle_master_id: VEHICLE_ID,
      vehicle_code: "VEH-001",
      vehicle_name: "Box Truck 001",
      source_class: "hybrid",
      coverage_status: "tracked",
      authoritative_source_type: "direct_device",
      last_position_at: "2026-08-03T00:05:00.000Z",
      has_active_provider_mapping: true,
      capacity_weight_kg: "5000",
      capacity_volume_cbm: "30",
      reserved_weight_kg: "1200.5",
      reserved_volume_cbm: "8.25",
    });
    assert.equal(row.sourceClass, "hybrid");
    assert.equal(row.coverageStatus, "tracked");
    assert.equal(row.reservedWeightKg, 1200.5);
  });

  test("maps a never-tracked vehicle honestly (not_tracked, no source, no last position)", () => {
    const row = parseTenantTrackingCoverageRow({
      vehicle_master_id: VEHICLE_ID,
      vehicle_code: "VEH-002",
      vehicle_name: "Box Truck 002",
      source_class: "none",
      coverage_status: "not_tracked",
      authoritative_source_type: null,
      last_position_at: null,
      has_active_provider_mapping: false,
      capacity_weight_kg: null,
      capacity_volume_cbm: null,
      reserved_weight_kg: 0,
      reserved_volume_cbm: 0,
    });
    assert.equal(row.coverageStatus, "not_tracked");
    assert.equal(row.authoritativeSourceType, null);
    assert.equal(row.capacityWeightKg, null);
  });
});

describe("parseTenantTrackingUtilizationSummary", () => {
  test("maps a tenant-wide summary and discloses a null limit when no cap is set", () => {
    const summary = parseTenantTrackingUtilizationSummary({
      tracking_enabled: true,
      package_code: "standard",
      max_tracked_vehicles: null,
      max_mobile_sessions: 20,
      total_active_vehicle_count: 10,
      tracked_vehicle_count: 6,
      stale_vehicle_count: 1,
      offline_vehicle_count: 2,
      not_tracked_vehicle_count: 2,
      tracked_vehicle_limit_remaining: null,
      device_total_count: 8,
      device_active_count: 6,
      mobile_session_active_count: 3,
      untracked_required_leg_count: 1,
    });
    assert.equal(summary.trackedVehicleCount, 6);
    assert.equal(summary.trackedVehicleLimitRemaining, null);
    assert.equal(summary.untrackedRequiredLegCount, 1);
  });

  test("maps a computed remaining-limit value when a cap is set", () => {
    const summary = parseTenantTrackingUtilizationSummary({
      tracking_enabled: true,
      package_code: "standard",
      max_tracked_vehicles: 50,
      max_mobile_sessions: 20,
      total_active_vehicle_count: 10,
      tracked_vehicle_count: 6,
      stale_vehicle_count: 0,
      offline_vehicle_count: 2,
      not_tracked_vehicle_count: 2,
      tracked_vehicle_limit_remaining: 44,
      device_total_count: 8,
      device_active_count: 6,
      mobile_session_active_count: 3,
      untracked_required_leg_count: 0,
    });
    assert.equal(summary.trackedVehicleLimitRemaining, 44);
  });
});

describe("ReserveVehicleCapacityInputSchema", () => {
  test("accepts a valid input with both capacity dimensions", () => {
    const parsed = ReserveVehicleCapacityInputSchema.parse({
      shipmentLegId: LEG_ID,
      requestedWeightKg: 1200.5,
      requestedVolumeCbm: 8.25,
      idempotencyKey: "leg-1-reserve",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "dispatcher",
    });
    assert.equal(parsed.requestedWeightKg, 1200.5);
  });

  test("accepts null capacity dimensions (unbounded/unknown)", () => {
    const parsed = ReserveVehicleCapacityInputSchema.parse({
      shipmentLegId: LEG_ID,
      requestedWeightKg: null,
      requestedVolumeCbm: null,
      idempotencyKey: "leg-1-reserve",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "dispatcher",
    });
    assert.equal(parsed.requestedWeightKg, null);
  });

  test("rejects a negative requested weight", () => {
    assert.throws(() =>
      ReserveVehicleCapacityInputSchema.parse({
        shipmentLegId: LEG_ID,
        requestedWeightKg: -1,
        requestedVolumeCbm: null,
        idempotencyKey: "leg-1-reserve",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "dispatcher",
      }),
    );
  });

  test("rejects an empty idempotency key", () => {
    assert.throws(() =>
      ReserveVehicleCapacityInputSchema.parse({
        shipmentLegId: LEG_ID,
        requestedWeightKg: null,
        requestedVolumeCbm: null,
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "dispatcher",
      }),
    );
  });
});
