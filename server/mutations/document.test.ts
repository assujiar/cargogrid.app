import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerDocumentType,
  publishDocumentTypeDefinition,
  initiateFileUpload,
  recordFileScanResult,
  authorizeFileAccess,
  createFileVersion,
  requestFileDeletion,
  setFileLegalHold,
  DocumentMutationError,
  type DocumentMutationRpcClient,
} from "./document.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "523e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "623e4567-e89b-12d3-a456-426614174000";
const VERSION_GROUP_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";
const LOG_ID = "923e4567-e89b-12d3-a456-426614174000";

const VALID_TYPE_ROW = {
  code: "contract",
  name: "Contract",
  owner_primitive_code: "DOC",
  registered_by: "platform-core-foundation",
  created_at: "2026-07-19T00:00:00.000Z",
};

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: OBJECT_ID,
  version_number: 1,
  status: "published",
  effective_from: "2026-07-19T00:00:00.000Z",
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "tenant admin",
  published_by: "tenant admin",
  published_at: "2026-07-19T00:00:00.000Z",
  archived_at: null,
  archived_reason: null,
  record_version: 2,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_FILE_ROW = {
  id: FILE_ID,
  tenant_id: TENANT_ID,
  document_type_code: "contract",
  config_version_id: VERSION_ID,
  record_type: "shipment",
  record_id: RECORD_ID,
  classification: "confidential",
  original_filename: "msa.pdf",
  mime_type: "application/pdf",
  size_bytes: 204800,
  storage_path: `tenant/${TENANT_ID}/contract/${FILE_ID}`,
  malware_scan_status: "pending",
  malware_scan_completed_at: null,
  malware_scan_provider_ref: null,
  version_group_id: VERSION_GROUP_ID,
  version_number: 1,
  is_latest_version: true,
  lifecycle_status: "active",
  legal_hold: false,
  legal_hold_reason: null,
  deleted_at: null,
  uploaded_by_auth_user_id: ACTOR_ID,
  shared_org_unit_ids: [],
  customer_account_ref: null,
  idempotency_key: "idem-msa-upload-1",
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_LOG_ROW = {
  id: LOG_ID,
  tenant_id: TENANT_ID,
  file_id: FILE_ID,
  accessed_by_auth_user_id: ACTOR_ID,
  access_type: "download",
  result: "granted",
  reason: null,
  correlation_id: null,
  accessed_at: "2026-07-19T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): DocumentMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("registerDocumentType", () => {
  test("calls register_document_type with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_TYPE_ROW, error: null });
    await registerDocumentType(client, { code: "contract", name: "Contract", ownerPrimitiveCode: "DOC", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_code: "contract",
      p_name: "Contract",
      p_owner_primitive_code: "DOC",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a document type" } });
    await assert.rejects(
      () => registerDocumentType(client, { code: "x", name: "X", ownerPrimitiveCode: "DOC", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishDocumentTypeDefinition", () => {
  test("calls publish_document_type_definition and returns the published version row", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    const version = await publishDocumentTypeDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
  });

  test("wraps a document_invalid_mime_type error", async () => {
    const client = fakeClient({ data: null, error: { message: "document_invalid_mime_type: application/x-msdownload is not in the platform allowlist" } });
    await assert.rejects(
      () => publishDocumentTypeDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "document_invalid_mime_type");
        return true;
      },
    );
  });
});

describe("initiateFileUpload", () => {
  test("calls initiate_file_upload with the exact snake_case params, defaulting the optional fields", async () => {
    const client = fakeClient({ data: VALID_FILE_ROW, error: null });
    await initiateFileUpload(client, {
      tenantId: TENANT_ID,
      documentTypeCode: "contract",
      recordType: "shipment",
      recordId: RECORD_ID,
      originalFilename: "msa.pdf",
      mimeType: "application/pdf",
      sizeBytes: 204800,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "uploader",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_document_type_code: "contract",
      p_record_type: "shipment",
      p_record_id: RECORD_ID,
      p_original_filename: "msa.pdf",
      p_mime_type: "application/pdf",
      p_size_bytes: 204800,
      p_classification: null,
      p_legal_hold: false,
      p_legal_hold_reason: null,
      p_shared_org_unit_ids: [],
      p_customer_account_ref: null,
      p_idempotency_key: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "uploader",
    });
  });

  test("wraps a document_unsafe_filename error", async () => {
    const client = fakeClient({ data: null, error: { message: "document_unsafe_filename: filename is missing, empty, too long, or contains a path separator/traversal sequence" } });
    await assert.rejects(
      () =>
        initiateFileUpload(client, {
          tenantId: TENANT_ID,
          documentTypeCode: "contract",
          recordType: "shipment",
          recordId: RECORD_ID,
          originalFilename: "../../etc/passwd",
          mimeType: "application/pdf",
          sizeBytes: 1000,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "uploader",
        }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "document_unsafe_filename");
        return true;
      },
    );
  });

  test("wraps a document_file_too_large error", async () => {
    const client = fakeClient({ data: null, error: { message: "document_file_too_large: 999999999 bytes exceeds the 10485760 byte limit for document type contract (or is not positive)" } });
    await assert.rejects(
      () =>
        initiateFileUpload(client, {
          tenantId: TENANT_ID,
          documentTypeCode: "contract",
          recordType: "shipment",
          recordId: RECORD_ID,
          originalFilename: "big.pdf",
          mimeType: "application/pdf",
          sizeBytes: 999999999,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "uploader",
        }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "document_file_too_large");
        return true;
      },
    );
  });
});

describe("recordFileScanResult", () => {
  test("calls record_file_scan_result with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_FILE_ROW, malware_scan_status: "clean", malware_scan_completed_at: "2026-07-19T00:00:00.000Z" }, error: null });
    const file = await recordFileScanResult(client, { fileId: FILE_ID, status: "clean", actorAuthUserId: ACTOR_ID, actorLabel: "scan-provider" });

    assert.deepEqual(client.calls[0]?.args, {
      p_file_id: FILE_ID,
      p_status: "clean",
      p_provider_ref: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "scan-provider",
    });
    assert.equal(file.malwareScanStatus, "clean");
  });

  test("wraps a document_scan_already_resolved error", async () => {
    const client = fakeClient({ data: null, error: { message: "document_scan_already_resolved: file already resolved to scan status clean, cannot re-resolve to infected" } });
    await assert.rejects(
      () => recordFileScanResult(client, { fileId: FILE_ID, status: "infected", actorAuthUserId: ACTOR_ID, actorLabel: "scan-provider" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "document_scan_already_resolved");
        return true;
      },
    );
  });
});

describe("authorizeFileAccess", () => {
  test("calls authorize_file_access and returns the logged decision", async () => {
    const client = fakeClient({ data: VALID_LOG_ROW, error: null });
    const log = await authorizeFileAccess(client, { fileId: FILE_ID, accessType: "download", actorAuthUserId: ACTOR_ID });
    assert.equal(log.result, "granted");
  });

  test("wraps a file_actor_unauthorized error", async () => {
    const client = fakeClient({ data: null, error: { message: "file_actor_unauthorized: identity lacks active membership in tenant" } });
    await assert.rejects(
      () => authorizeFileAccess(client, { fileId: FILE_ID, accessType: "download", actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "file_actor_unauthorized");
        return true;
      },
    );
  });
});

describe("createFileVersion", () => {
  test("calls create_file_version with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_FILE_ROW, version_number: 2 }, error: null });
    const file = await createFileVersion(client, { previousFileId: FILE_ID, originalFilename: "v2.pdf", mimeType: "application/pdf", sizeBytes: 1200, actorAuthUserId: ACTOR_ID, actorLabel: "uploader" });
    assert.equal(file.versionNumber, 2);
  });

  test("wraps a document_version_not_latest error", async () => {
    const client = fakeClient({ data: null, error: { message: "document_version_not_latest: file is not the latest version of its group, versioning must start from the latest" } });
    await assert.rejects(
      () => createFileVersion(client, { previousFileId: FILE_ID, originalFilename: "v2.pdf", mimeType: "application/pdf", sizeBytes: 1200, actorAuthUserId: ACTOR_ID, actorLabel: "uploader" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "document_version_not_latest");
        return true;
      },
    );
  });
});

describe("requestFileDeletion", () => {
  test("calls request_file_deletion with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_FILE_ROW, deleted_at: "2026-07-19T00:00:00.000Z", lifecycle_status: "deleted" }, error: null });
    const file = await requestFileDeletion(client, { fileId: FILE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "uploader" });
    assert.equal(file.lifecycleStatus, "deleted");
  });

  test("wraps a document_legal_hold_blocks_deletion error", async () => {
    const client = fakeClient({ data: null, error: { message: "document_legal_hold_blocks_deletion: file is under legal hold (litigation), it cannot be deleted" } });
    await assert.rejects(
      () => requestFileDeletion(client, { fileId: FILE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "uploader" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "document_legal_hold_blocks_deletion");
        return true;
      },
    );
  });
});

describe("setFileLegalHold", () => {
  test("calls set_file_legal_hold with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_FILE_ROW, legal_hold: true, legal_hold_reason: "litigation hold" }, error: null });
    const file = await setFileLegalHold(client, { fileId: FILE_ID, legalHold: true, legalHoldReason: "litigation hold", actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(file.legalHold, true);
  });

  test("wraps a document_legal_hold_unauthorized error", async () => {
    const client = fakeClient({ data: null, error: { message: "document_legal_hold_unauthorized: identity lacks support/supreme authority over tenant" } });
    await assert.rejects(
      () => setFileLegalHold(client, { fileId: FILE_ID, legalHold: true, legalHoldReason: "litigation hold", actorAuthUserId: ACTOR_ID, actorLabel: "org user" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentMutationError);
        assert.equal(err.code, "document_legal_hold_unauthorized");
        return true;
      },
    );
  });
});
