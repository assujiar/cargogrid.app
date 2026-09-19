import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listVehicleOperationalProfiles,
  listDriverOperationalProfiles,
  listGpsDevices,
  listSimCards,
  listDeviceVehicleAssignmentHistory,
  listProviderVehicleMappings,
  listVehicleTrackingSourcePriorities,
  FleetDriverDeviceQueryError,
  type FleetDriverDeviceQueryTableClient,
} from "./fleet-driver-device.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VEHICLE_MASTER_ID = "323e4567-e89b-12d3-a456-426614174000";
const DRIVER_MASTER_ID = "423e4567-e89b-12d3-a456-426614174000";
const DEVICE_ID = "723e4567-e89b-12d3-a456-426614174000";
const VEHICLE_PROFILE_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(
  response: { data: unknown; error: { message: string } | null },
  capture?: (fn: string, args: Record<string, unknown>) => void,
): FleetDriverDeviceQueryTableClient {
  return {
    rpc: (fn: string, args: Record<string, unknown>) => {
      capture?.(fn, args);
      return Promise.resolve(response);
    },
  } as unknown as FleetDriverDeviceQueryTableClient;
}

describe("listVehicleOperationalProfiles", () => {
  test("maps rows for one tenant", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient(
      {
        data: [
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
        ],
        error: null,
      },
      (fn, args) => {
        capturedFn = fn;
        capturedArgs = args;
      },
    );
    const profiles = await listVehicleOperationalProfiles(client, TENANT_ID);
    assert.equal(capturedFn, "list_vehicle_operational_profiles");
    assert.equal(capturedArgs?.p_tenant_id, TENANT_ID);
    assert.equal(profiles.length, 1);
    assert.equal(profiles[0]?.ownershipType, "owned");
  });

  test("surfaces a real query error as FleetDriverDeviceQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listVehicleOperationalProfiles(client, TENANT_ID), FleetDriverDeviceQueryError);
  });
});

describe("listDriverOperationalProfiles", () => {
  test("maps rows for one tenant", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient(
      {
        data: [
          {
            id: DRIVER_MASTER_ID,
            tenant_id: TENANT_ID,
            driver_master_id: DRIVER_MASTER_ID,
            license_class: "B2",
            license_expiry_date: "2027-01-01",
            mobile_tracking_consent: true,
            mobile_tracking_consent_at: "2026-07-29T00:00:00.000Z",
            status: "active",
            record_version: 1,
            created_by: "admin",
            created_at: "2026-07-29T00:00:00.000Z",
            updated_at: "2026-07-29T00:00:00.000Z",
          },
        ],
        error: null,
      },
      (fn, args) => {
        capturedFn = fn;
        capturedArgs = args;
      },
    );
    const profiles = await listDriverOperationalProfiles(client, TENANT_ID);
    assert.equal(capturedFn, "list_driver_operational_profiles");
    assert.equal(capturedArgs?.p_tenant_id, TENANT_ID);
    assert.equal(profiles.length, 1);
    assert.equal(profiles[0]?.mobileTrackingConsent, true);
  });
});

describe("listGpsDevices", () => {
  test("maps device rows", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient(
      {
        data: [
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
        ],
        error: null,
      },
      (fn, args) => {
        capturedFn = fn;
        capturedArgs = args;
      },
    );
    const devices = await listGpsDevices(client, TENANT_ID);
    assert.equal(capturedFn, "list_gps_devices");
    assert.equal(capturedArgs?.p_tenant_id, TENANT_ID);
    assert.equal(devices.length, 1);
    assert.equal(devices[0]?.status, "stock");
  });
});

describe("listSimCards", () => {
  test("maps SIM card rows", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient(
      {
        data: [
          {
            id: "923e4567-e89b-12d3-a456-426614174000",
            tenant_id: TENANT_ID,
            iccid: "8901260000000000001",
            msisdn: null,
            carrier: "Telkomsel",
            status: "stock",
            current_device_id: null,
            record_version: 1,
            created_by: "rep",
            created_at: "2026-07-29T00:00:00.000Z",
            updated_at: "2026-07-29T00:00:00.000Z",
          },
        ],
        error: null,
      },
      (fn, args) => {
        capturedFn = fn;
        capturedArgs = args;
      },
    );
    const simCards = await listSimCards(client, TENANT_ID);
    assert.equal(capturedFn, "list_sim_cards");
    assert.equal(capturedArgs?.p_tenant_id, TENANT_ID);
    assert.equal(simCards.length, 1);
    assert.equal(simCards[0]?.carrier, "Telkomsel");
  });
});

describe("listDeviceVehicleAssignmentHistory", () => {
  test("maps assignment history rows for one device", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient(
      {
        data: [
          {
            id: "a23e4567-e89b-12d3-a456-426614174000",
            tenant_id: TENANT_ID,
            device_id: DEVICE_ID,
            vehicle_operational_profile_id: VEHICLE_PROFILE_ID,
            is_current: true,
            effective_from: "2026-07-29T00:00:00.000Z",
            effective_to: null,
            reason: null,
            superseded_by_id: null,
            created_by: "rep",
            created_at: "2026-07-29T00:00:00.000Z",
          },
        ],
        error: null,
      },
      (fn, args) => {
        capturedFn = fn;
        capturedArgs = args;
      },
    );
    const history = await listDeviceVehicleAssignmentHistory(client, DEVICE_ID);
    assert.equal(capturedFn, "list_device_vehicle_assignment_history");
    assert.equal(capturedArgs?.p_device_id, DEVICE_ID);
    assert.equal(history.length, 1);
    assert.equal(history[0]?.isCurrent, true);
  });
});

describe("listProviderVehicleMappings", () => {
  test("maps provider mapping rows for one vehicle master record", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient(
      {
        data: [
          {
            id: "b23e4567-e89b-12d3-a456-426614174000",
            tenant_id: TENANT_ID,
            vehicle_master_id: VEHICLE_MASTER_ID,
            provider_code: "geotab",
            external_vehicle_id: "GT-001",
            status: "active",
            record_version: 1,
            created_by: "rep",
            created_at: "2026-07-29T00:00:00.000Z",
            updated_at: "2026-07-29T00:00:00.000Z",
          },
        ],
        error: null,
      },
      (fn, args) => {
        capturedFn = fn;
        capturedArgs = args;
      },
    );
    const mappings = await listProviderVehicleMappings(client, VEHICLE_MASTER_ID);
    assert.equal(capturedFn, "list_provider_vehicle_mappings");
    assert.equal(capturedArgs?.p_vehicle_master_id, VEHICLE_MASTER_ID);
    assert.equal(mappings.length, 1);
    assert.equal(mappings[0]?.providerCode, "geotab");
  });
});

describe("listVehicleTrackingSourcePriorities", () => {
  test("maps source-priority rows for one vehicle master record, ranked ascending", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient(
      {
        data: [
          {
            id: "c23e4567-e89b-12d3-a456-426614174000",
            tenant_id: TENANT_ID,
            vehicle_master_id: VEHICLE_MASTER_ID,
            source_type: "direct_device",
            priority_rank: 1,
            is_enabled: true,
            record_version: 1,
            created_by: "rep",
            created_at: "2026-07-29T00:00:00.000Z",
            updated_at: "2026-07-29T00:00:00.000Z",
          },
        ],
        error: null,
      },
      (fn, args) => {
        capturedFn = fn;
        capturedArgs = args;
      },
    );
    const priorities = await listVehicleTrackingSourcePriorities(client, VEHICLE_MASTER_ID);
    assert.equal(capturedFn, "list_vehicle_tracking_source_priorities");
    assert.equal(capturedArgs?.p_vehicle_master_id, VEHICLE_MASTER_ID);
    assert.equal(priorities.length, 1);
    assert.equal(priorities[0]?.sourceType, "direct_device");
  });
});
