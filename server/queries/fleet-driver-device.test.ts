import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listVehicleOperationalProfiles, listGpsDevices, FleetDriverDeviceQueryError, type FleetDriverDeviceQueryTableClient } from "./fleet-driver-device.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VEHICLE_MASTER_ID = "323e4567-e89b-12d3-a456-426614174000";
const DEVICE_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeFromClient(rows: Record<string, unknown>[]): FleetDriverDeviceQueryTableClient {
  return {
    from() {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        order() {
          return Promise.resolve({ data: rows, error: null });
        },
      };
    },
  } as unknown as FleetDriverDeviceQueryTableClient;
}

describe("listVehicleOperationalProfiles", () => {
  test("maps rows for one tenant", async () => {
    const client = fakeFromClient([
      {
        id: VEHICLE_MASTER_ID,
        tenant_id: TENANT_ID,
        vehicle_master_id: VEHICLE_MASTER_ID,
        ownership_type: "owned",
        capacity_weight_kg: null,
        capacity_volume_cbm: null,
        mobile_tracking_eligible: false,
        direct_device_tracking_eligible: false,
        third_party_tracking_eligible: false,
        status: "active",
        record_version: 1,
        created_by: "admin",
        created_at: "2026-07-29T00:00:00.000Z",
        updated_at: "2026-07-29T00:00:00.000Z",
      },
    ]);
    const profiles = await listVehicleOperationalProfiles(client, TENANT_ID);
    assert.equal(profiles.length, 1);
    assert.equal(profiles[0]?.ownershipType, "owned");
  });

  test("surfaces a real query error as FleetDriverDeviceQueryError", async () => {
    const client = {
      from() {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          order() {
            return Promise.resolve({ data: null, error: { message: "connection reset" } });
          },
        };
      },
    } as unknown as FleetDriverDeviceQueryTableClient;
    await assert.rejects(() => listVehicleOperationalProfiles(client, TENANT_ID), FleetDriverDeviceQueryError);
  });
});

describe("listGpsDevices", () => {
  test("maps device rows", async () => {
    const client = fakeFromClient([
      {
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
      },
    ]);
    const devices = await listGpsDevices(client, TENANT_ID);
    assert.equal(devices.length, 1);
    assert.equal(devices[0]?.status, "stock");
  });
});
