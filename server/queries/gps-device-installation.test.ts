import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listGpsDeviceInstallations, getGpsDeviceInstallationForAssignment, GpsDeviceInstallationQueryError, type GpsDeviceInstallationQueryClient } from "./gps-device-installation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ASSIGNMENT_ID = "423e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: "723e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  device_id: "323e4567-e89b-12d3-a456-426614174000",
  device_vehicle_assignment_id: ASSIGNMENT_ID,
  evidence_file_id: "523e4567-e89b-12d3-a456-426614174000",
  technician_label: "Budi Teknisi",
  installation_notes: null,
  installed_at: "2026-08-03T00:00:00.000Z",
  verified_by_auth_user_id: null,
  verified_at: null,
  record_version: 1,
  created_by: "admin",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

function fakeTableClient(response: { data: unknown; error: { message: string } | null }, expectMaybeSingle: boolean): GpsDeviceInstallationQueryClient {
  return {
    from(table: string) {
      assert.equal(table, "gps_device_installations");
      const chain = {
        select() {
          return chain;
        },
        eq() {
          return chain;
        },
        order() {
          return response;
        },
        async maybeSingle() {
          return response;
        },
      };
      return expectMaybeSingle ? chain : chain;
    },
  } as unknown as GpsDeviceInstallationQueryClient;
}

describe("listGpsDeviceInstallations", () => {
  test("maps rows for a tenant", async () => {
    const client = fakeTableClient({ data: [ROW], error: null }, false);
    const rows = await listGpsDeviceInstallations(client, TENANT_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.technicianLabel, "Budi Teknisi");
  });

  test("throws on a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } }, false);
    await assert.rejects(() => listGpsDeviceInstallations(client, TENANT_ID), GpsDeviceInstallationQueryError);
  });
});

describe("getGpsDeviceInstallationForAssignment", () => {
  test("returns null when none was ever recorded", async () => {
    const client = fakeTableClient({ data: null, error: null }, true);
    const installation = await getGpsDeviceInstallationForAssignment(client, ASSIGNMENT_ID);
    assert.equal(installation, null);
  });

  test("parses a real row", async () => {
    const client = fakeTableClient({ data: ROW, error: null }, true);
    const installation = await getGpsDeviceInstallationForAssignment(client, ASSIGNMENT_ID);
    assert.ok(installation);
    assert.equal(installation?.deviceVehicleAssignmentId, ASSIGNMENT_ID);
  });
});
