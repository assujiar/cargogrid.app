import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseGpsDeviceInstallation, RecordGpsDeviceInstallationInputSchema, VerifyGpsDeviceInstallationInputSchema } from "./gps-device-installation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const DEVICE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ASSIGNMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseGpsDeviceInstallation", () => {
  test("maps an unverified installation row", () => {
    const installation = parseGpsDeviceInstallation({
      id: "723e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      device_id: DEVICE_ID,
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
    });
    assert.equal(installation.technicianLabel, "Budi Teknisi");
    assert.equal(installation.verifiedByAuthUserId, null);
  });

  test("maps a verified installation row", () => {
    const installation = parseGpsDeviceInstallation({
      id: "723e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      device_id: DEVICE_ID,
      device_vehicle_assignment_id: ASSIGNMENT_ID,
      evidence_file_id: FILE_ID,
      technician_label: "Budi Teknisi",
      installation_notes: "installed under dashboard",
      installed_at: "2026-08-03T00:00:00.000Z",
      verified_by_auth_user_id: ACTOR_ID,
      verified_at: "2026-08-03T01:00:00.000Z",
      record_version: 2,
      created_by: "admin",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T01:00:00.000Z",
    });
    assert.equal(installation.verifiedByAuthUserId, ACTOR_ID);
    assert.equal(installation.installationNotes, "installed under dashboard");
  });
});

describe("RecordGpsDeviceInstallationInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = RecordGpsDeviceInstallationInputSchema.parse({
      deviceVehicleAssignmentId: ASSIGNMENT_ID,
      evidenceFileId: FILE_ID,
      technicianLabel: "Budi Teknisi",
      expectedDeviceVersion: 2,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "admin",
    });
    assert.equal(parsed.installationNotes, null);
  });

  test("rejects an empty technicianLabel", () => {
    assert.throws(() =>
      RecordGpsDeviceInstallationInputSchema.parse({
        deviceVehicleAssignmentId: ASSIGNMENT_ID,
        evidenceFileId: FILE_ID,
        technicianLabel: "",
        expectedDeviceVersion: 2,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "admin",
      }),
    );
  });
});

describe("VerifyGpsDeviceInstallationInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = VerifyGpsDeviceInstallationInputSchema.parse({
      installationId: "723e4567-e89b-12d3-a456-426614174000",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "admin",
    });
    assert.equal(parsed.actorLabel, "admin");
  });
});
