import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { recordGpsDeviceInstallation, verifyGpsDeviceInstallation, GpsDeviceInstallationMutationError, type GpsDeviceInstallationMutationRpcClient } from "./gps-device-installation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ASSIGNMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const INSTALLATION_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: GpsDeviceInstallationMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as GpsDeviceInstallationMutationRpcClient;
  return { client, calls };
}

const INSTALLATION_ROW = {
  id: INSTALLATION_ID,
  tenant_id: TENANT_ID,
  device_id: "323e4567-e89b-12d3-a456-426614174000",
  device_vehicle_assignment_id: ASSIGNMENT_ID,
  evidence_file_id: FILE_ID,
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

describe("recordGpsDeviceInstallation", () => {
  test("calls record_gps_device_installation with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: INSTALLATION_ROW, error: null });
    const installation = await recordGpsDeviceInstallation(client, {
      deviceVehicleAssignmentId: ASSIGNMENT_ID,
      evidenceFileId: FILE_ID,
      technicianLabel: "Budi Teknisi",
      expectedDeviceVersion: 2,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "admin",
    });
    assert.equal(installation.technicianLabel, "Budi Teknisi");
    assert.equal(calls[0]?.fn, "record_gps_device_installation");
    assert.equal(calls[0]?.args.p_expected_device_version, 2);
  });

  test("classifies an installation_unsafe_evidence error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "installation_unsafe_evidence: evidence file has scan status pending" } });
    await assert.rejects(
      () =>
        recordGpsDeviceInstallation(client, {
          deviceVehicleAssignmentId: ASSIGNMENT_ID,
          evidenceFileId: FILE_ID,
          technicianLabel: "Budi Teknisi",
          expectedDeviceVersion: 2,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "admin",
        }),
      (error: unknown) => error instanceof GpsDeviceInstallationMutationError && error.code === "installation_unsafe_evidence",
    );
  });
});

describe("verifyGpsDeviceInstallation", () => {
  test("calls verify_gps_device_installation with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...INSTALLATION_ROW, verified_by_auth_user_id: ACTOR_ID, verified_at: "2026-08-03T01:00:00.000Z" }, error: null });
    const installation = await verifyGpsDeviceInstallation(client, {
      installationId: INSTALLATION_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "admin",
    });
    assert.equal(installation.verifiedByAuthUserId, ACTOR_ID);
    assert.equal(calls[0]?.fn, "verify_gps_device_installation");
    assert.equal(calls[0]?.args.p_installation_id, INSTALLATION_ID);
  });

  test("classifies an insufficient_authority error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:Edit" } });
    await assert.rejects(
      () => verifyGpsDeviceInstallation(client, { installationId: INSTALLATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "viewer" }),
      (error: unknown) => error instanceof GpsDeviceInstallationMutationError && error.code === "insufficient_authority",
    );
  });
});
