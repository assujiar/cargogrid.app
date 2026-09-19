import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  recordGpsDeviceInstallation,
  verifyGpsDeviceInstallation,
  uploadGpsDeviceInstallationEvidenceFile,
  GpsDeviceInstallationMutationError,
  type GpsDeviceInstallationMutationRpcClient,
} from "./gps-device-installation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ASSIGNMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const INSTALLATION_ID = "723e4567-e89b-12d3-a456-426614174000";
const DEVICE_ID = "323e4567-e89b-12d3-a456-426614174000";

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

describe("uploadGpsDeviceInstallationEvidenceFile", () => {
  const FILE_ROW = {
    id: FILE_ID,
    tenant_id: TENANT_ID,
    document_type_code: "gps_device_installation",
    config_version_id: "823e4567-e89b-12d3-a456-426614174000",
    record_type: "gps_device",
    record_id: DEVICE_ID,
    classification: "internal",
    original_filename: "install-photo.jpg",
    mime_type: "image/jpeg",
    size_bytes: 40960,
    storage_path: `tenant/${TENANT_ID}/gps_device_installation/${FILE_ID}`,
    malware_scan_status: "pending",
    malware_scan_completed_at: null,
    malware_scan_provider_ref: null,
    version_group_id: FILE_ID,
    version_number: 1,
    is_latest_version: true,
    lifecycle_status: "active",
    legal_hold: false,
    legal_hold_reason: null,
    deleted_at: null,
    uploaded_by_auth_user_id: ACTOR_ID,
    shared_org_unit_ids: [],
    customer_account_ref: null,
    idempotency_key: "idem-gps-install-1",
    created_at: "2026-09-14T09:00:00.000Z",
    updated_at: "2026-09-14T09:00:00.000Z",
  };

  test("calls initiate_file_upload with record_type always gps_device and document_type_code always gps_device_installation", async () => {
    const { client, calls } = fakeRpcClient({ data: FILE_ROW, error: null });
    const file = await uploadGpsDeviceInstallationEvidenceFile(client, {
      tenantId: TENANT_ID,
      deviceId: DEVICE_ID,
      originalFilename: "install-photo.jpg",
      mimeType: "image/jpeg",
      sizeBytes: 40960,
      idempotencyKey: "idem-gps-install-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "admin",
    });
    assert.equal(calls[0]?.fn, "initiate_file_upload");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_document_type_code: "gps_device_installation",
      p_record_type: "gps_device",
      p_record_id: DEVICE_ID,
      p_original_filename: "install-photo.jpg",
      p_mime_type: "image/jpeg",
      p_size_bytes: 40960,
      p_classification: null,
      p_legal_hold: false,
      p_legal_hold_reason: null,
      p_shared_org_unit_ids: [],
      p_customer_account_ref: null,
      p_idempotency_key: "idem-gps-install-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "admin",
    });
    assert.equal(file.storagePath, `tenant/${TENANT_ID}/gps_device_installation/${FILE_ID}`);
    assert.equal(file.malwareScanStatus, "pending");
  });

  test("classifies a document_type_not_configured error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "document_type_not_configured: tenant has not published a definition for document type gps_device_installation" } });
    await assert.rejects(
      () =>
        uploadGpsDeviceInstallationEvidenceFile(client, {
          tenantId: TENANT_ID,
          deviceId: DEVICE_ID,
          originalFilename: "install-photo.jpg",
          mimeType: "image/jpeg",
          sizeBytes: 40960,
          idempotencyKey: "idem-gps-install-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "admin",
        }),
      (error: unknown) => error instanceof GpsDeviceInstallationMutationError && error.code === "document_type_not_configured",
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
