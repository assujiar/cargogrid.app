import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseVehicleOperationalProfile,
  parseDriverOperationalProfile,
  parseGpsDevice,
  parseSimCard,
  parseDeviceVehicleAssignment,
  RegisterVehicleOperationalProfileInputSchema,
} from "./fleet-driver-device.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VEHICLE_MASTER_ID = "323e4567-e89b-12d3-a456-426614174000";
const DRIVER_MASTER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const DEVICE_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseVehicleOperationalProfile", () => {
  test("maps a profile with tracking-mode eligibility flags", () => {
    const profile = parseVehicleOperationalProfile({
      id: VEHICLE_MASTER_ID,
      tenant_id: TENANT_ID,
      vehicle_master_id: VEHICLE_MASTER_ID,
      ownership_type: "owned",
      capacity_weight_kg: 5000,
      capacity_volume_cbm: 20,
      mobile_tracking_eligible: true,
      direct_device_tracking_eligible: false,
      third_party_tracking_eligible: false,
      status: "active",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(profile.ownershipType, "owned");
    assert.equal(profile.mobileTrackingEligible, true);
  });
});

describe("parseDriverOperationalProfile", () => {
  test("maps a profile with consent not yet granted", () => {
    const profile = parseDriverOperationalProfile({
      id: DRIVER_MASTER_ID,
      tenant_id: TENANT_ID,
      driver_master_id: DRIVER_MASTER_ID,
      license_class: "B2",
      license_expiry_date: "2028-01-01",
      mobile_tracking_consent: false,
      mobile_tracking_consent_at: null,
      status: "active",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(profile.mobileTrackingConsent, false);
    assert.equal(profile.mobileTrackingConsentAt, null);
  });
});

describe("parseGpsDevice", () => {
  test("maps a device in stock status", () => {
    const device = parseGpsDevice({
      id: DEVICE_ID,
      tenant_id: TENANT_ID,
      imei: "868712345678901",
      device_model: "Teltonika FMB920",
      ownership_type: "cargogrid",
      status: "stock",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(device.status, "stock");
  });
});

describe("parseSimCard", () => {
  test("maps a SIM with no device assigned", () => {
    const sim = parseSimCard({
      id: DEVICE_ID,
      tenant_id: TENANT_ID,
      iccid: "8901260123456789012",
      msisdn: "628111111111",
      carrier: "Telkomsel",
      status: "stock",
      current_device_id: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-07-29T00:00:00.000Z",
      updated_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(sim.currentDeviceId, null);
  });
});

describe("parseDeviceVehicleAssignment", () => {
  test("maps a superseded (non-current) historical assignment", () => {
    const assignment = parseDeviceVehicleAssignment({
      id: DEVICE_ID,
      tenant_id: TENANT_ID,
      device_id: DEVICE_ID,
      vehicle_operational_profile_id: VEHICLE_MASTER_ID,
      is_current: false,
      effective_from: "2026-07-29T00:00:00.000Z",
      effective_to: "2026-07-29T01:00:00.000Z",
      reason: "reassigned",
      superseded_by_id: ACTOR_ID,
      created_by: "rep",
      created_at: "2026-07-29T00:00:00.000Z",
    });
    assert.equal(assignment.isCurrent, false);
    assert.equal(assignment.supersededById, ACTOR_ID);
  });
});

describe("RegisterVehicleOperationalProfileInputSchema", () => {
  test("rejects an unknown ownership type", () => {
    assert.throws(() =>
      RegisterVehicleOperationalProfileInputSchema.parse({
        tenantId: TENANT_ID,
        code: "VEH-001",
        name: "Truck 001",
        ownershipType: "franchise",
        capacityWeightKg: null,
        capacityVolumeCbm: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "admin",
      }),
    );
  });
});
