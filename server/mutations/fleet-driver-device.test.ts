import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerVehicleOperationalProfile,
  registerGpsDevice,
  transitionGpsDeviceStatus,
  assignDeviceToVehicle,
  assignSimToDevice,
  FleetDriverDeviceMutationError,
  type FleetDriverDeviceMutationRpcClient,
} from "./fleet-driver-device.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VEHICLE_MASTER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const DEVICE_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: FleetDriverDeviceMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as FleetDriverDeviceMutationRpcClient;
  return { client, calls };
}

const VEHICLE_ROW = {
  id: VEHICLE_MASTER_ID,
  tenant_id: TENANT_ID,
  vehicle_master_id: VEHICLE_MASTER_ID,
  ownership_type: "owned",
  capacity_weight_kg: 5000,
  capacity_volume_cbm: 20,
  mobile_tracking_eligible: false,
  direct_device_tracking_eligible: false,
  third_party_tracking_eligible: false,
  status: "active",
  record_version: 1,
  created_by: "admin",
  created_at: "2026-07-29T00:00:00.000Z",
  updated_at: "2026-07-29T00:00:00.000Z",
};

describe("registerVehicleOperationalProfile", () => {
  test("calls register_vehicle_operational_profile with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: VEHICLE_ROW, error: null });
    const profile = await registerVehicleOperationalProfile(client, {
      tenantId: TENANT_ID,
      code: "VEH-001",
      name: "Truck 001",
      ownershipType: "owned",
      capacityWeightKg: 5000,
      capacityVolumeCbm: 20,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "admin",
    });
    assert.equal(profile.ownershipType, "owned");
    assert.equal(calls[0]?.fn, "register_vehicle_operational_profile");
    assert.equal(calls[0]?.args.p_code, "VEH-001");
  });

  test("classifies an insufficient_authority error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:Create" } });
    await assert.rejects(
      () =>
        registerVehicleOperationalProfile(client, {
          tenantId: TENANT_ID,
          code: "VEH-001",
          name: "Truck 001",
          ownershipType: "owned",
          capacityWeightKg: null,
          capacityVolumeCbm: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "viewer",
        }),
      (error: unknown) => error instanceof FleetDriverDeviceMutationError && error.code === "insufficient_authority",
    );
  });
});

describe("registerGpsDevice / transitionGpsDeviceStatus", () => {
  test("classifies invalid_device_status_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_device_status_transition: device cannot move from stock to active" } });
    await assert.rejects(
      () => transitionGpsDeviceStatus(client, { deviceId: DEVICE_ID, toStatus: "active", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof FleetDriverDeviceMutationError && error.code === "invalid_device_status_transition",
    );
  });

  test("classifies device_retired", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "device_retired: device is retired and cannot be assigned" } });
    await assert.rejects(
      () => assignDeviceToVehicle(client, { deviceId: DEVICE_ID, vehicleProfileId: VEHICLE_MASTER_ID, reason: "install", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof FleetDriverDeviceMutationError && error.code === "device_retired",
    );
  });
});

describe("assignSimToDevice", () => {
  test("classifies device_already_has_sim", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "device_already_has_sim: device already has a different SIM assigned" } });
    await assert.rejects(
      () => assignSimToDevice(client, { simId: DEVICE_ID, deviceId: DEVICE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof FleetDriverDeviceMutationError && error.code === "device_already_has_sim",
    );
  });
});
