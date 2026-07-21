import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseDocumentType, parseFile, parseFileAccessLog, InitiateFileUploadInputSchema, RegisterDocumentTypeInputSchema } from "./document.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "523e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "623e4567-e89b-12d3-a456-426614174000";
const VERSION_GROUP_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";
const LOG_ID = "923e4567-e89b-12d3-a456-426614174000";

describe("parseDocumentType", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const type = parseDocumentType({
      code: "contract",
      name: "Contract",
      owner_primitive_code: "DOC",
      registered_by: "platform-core-foundation",
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(type.ownerPrimitiveCode, "DOC");
  });
});

describe("parseFile", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const file = parseFile({
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
    });
    assert.equal(file.malwareScanStatus, "pending");
    assert.equal(file.isLatestVersion, true);
    assert.deepEqual(file.sharedOrgUnitIds, []);
  });
});

describe("parseFileAccessLog", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const log = parseFileAccessLog({
      id: LOG_ID,
      tenant_id: TENANT_ID,
      file_id: FILE_ID,
      accessed_by_auth_user_id: ACTOR_ID,
      access_type: "download",
      result: "denied",
      reason: "document_not_yet_scanned",
      correlation_id: null,
      accessed_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(log.result, "denied");
    assert.equal(log.reason, "document_not_yet_scanned");
  });
});

describe("InitiateFileUploadInputSchema", () => {
  test("defaults classification/legalHold/sharedOrgUnitIds/customerAccountRef/idempotencyKey", () => {
    const parsed = InitiateFileUploadInputSchema.parse({
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
    assert.equal(parsed.classification, null);
    assert.equal(parsed.legalHold, false);
    assert.deepEqual(parsed.sharedOrgUnitIds, []);
    assert.equal(parsed.customerAccountRef, null);
    assert.equal(parsed.idempotencyKey, null);
  });

  test("rejects an unrecognized classification", () => {
    assert.throws(() =>
      InitiateFileUploadInputSchema.parse({
        tenantId: TENANT_ID,
        documentTypeCode: "contract",
        recordType: "shipment",
        recordId: RECORD_ID,
        originalFilename: "msa.pdf",
        mimeType: "application/pdf",
        sizeBytes: 204800,
        classification: "top_secret",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "uploader",
      }),
    );
  });

  test("rejects a non-positive size", () => {
    assert.throws(() =>
      InitiateFileUploadInputSchema.parse({
        tenantId: TENANT_ID,
        documentTypeCode: "contract",
        recordType: "shipment",
        recordId: RECORD_ID,
        originalFilename: "msa.pdf",
        mimeType: "application/pdf",
        sizeBytes: 0,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "uploader",
      }),
    );
  });
});

describe("RegisterDocumentTypeInputSchema", () => {
  test("parses a well-formed input", () => {
    const parsed = RegisterDocumentTypeInputSchema.parse({
      code: "contract",
      name: "Contract",
      ownerPrimitiveCode: "DOC",
      actorAuthUserId: ACTOR_ID,
      registeredBy: "tester",
    });
    assert.equal(parsed.code, "contract");
  });
});
