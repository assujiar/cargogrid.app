import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseImportExportSchema,
  parseImportExportSchemaVersion,
  parseResolvedImportExportSchemaColumns,
  parseImportExportJob,
  parseImportStagingRow,
  parseImportJobPreview,
  CreateImportExportJobInputSchema,
  StageImportRowsInputSchema,
} from "./import-export.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "523e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "623e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "723e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("parseImportExportSchema", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const schema = parseImportExportSchema({
      code: "shipment_rows",
      name: "Shipment Rows",
      owner_primitive_code: "SHP",
      registered_by: "supreme admin",
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(schema.ownerPrimitiveCode, "SHP");
  });
});

describe("parseImportExportSchemaVersion", () => {
  test("maps app.config_versions' own shape (reused directly, not forked)", () => {
    const version = parseImportExportSchemaVersion({
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
      record_version: 1,
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(version.status, "published");
  });
});

describe("parseResolvedImportExportSchemaColumns", () => {
  test("maps a raw row's columns array", () => {
    const resolved = parseResolvedImportExportSchemaColumns({
      config_version_id: VERSION_ID,
      columns: [{ key: "ref", label: "Reference", required: true, data_type: "text" }],
    });
    assert.equal(resolved.columns.length, 1);
    assert.equal(resolved.columns[0]?.data_type, "text");
  });
});

describe("parseImportExportJob", () => {
  test("maps a raw snake_case app.jobs row to the camelCase contract shape", () => {
    const job = parseImportExportJob({
      job_id: JOB_ID,
      tenant_id: TENANT_ID,
      job_type: "import",
      status: "pending",
      priority: 0,
      payload: {},
      attempts: 0,
      max_attempts: 3,
      locked_by: null,
      locked_until: null,
      error: null,
      result_url: null,
      created_by: "requester",
      created_at: "2026-07-19T00:00:00.000Z",
      completed_at: null,
      requested_by_auth_user_id: AUTH_USER_ID,
      idempotency_key: "idem-1",
      import_export_schema_code: "shipment_rows",
      source_file_id: FILE_ID,
      result_file_id: null,
      total_rows: null,
      processed_rows: 0,
      valid_row_count: 0,
      invalid_row_count: 0,
      cancel_reason: null,
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(job.jobType, "import");
    assert.equal(job.sourceFileId, FILE_ID);
  });
});

describe("parseImportStagingRow", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const row = parseImportStagingRow({
      id: ROW_ID,
      tenant_id: TENANT_ID,
      job_id: JOB_ID,
      row_number: 1,
      raw_payload: { ref: "REF-001" },
      validation_status: "valid",
      error: null,
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(row.validationStatus, "valid");
    assert.deepEqual(row.rawPayload, { ref: "REF-001" });
  });
});

describe("parseImportJobPreview", () => {
  test("maps a raw snake_case preview row to the camelCase contract shape", () => {
    const preview = parseImportJobPreview({
      total_rows: 4,
      valid_rows: 3,
      invalid_rows: 1,
      pending_rows: 0,
    });
    assert.equal(preview.totalRows, 4);
    assert.equal(preview.validRows, 3);
  });
});

describe("CreateImportExportJobInputSchema", () => {
  test("defaults filters to {} and sourceFileId/idempotencyKey to null", () => {
    const parsed = CreateImportExportJobInputSchema.parse({
      tenantId: TENANT_ID,
      jobType: "export",
      schemaCode: "shipment_rows",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "requester",
    });
    assert.deepEqual(parsed.filters, {});
    assert.equal(parsed.sourceFileId, null);
    assert.equal(parsed.idempotencyKey, null);
  });

  test("rejects an unknown jobType", () => {
    assert.throws(() =>
      CreateImportExportJobInputSchema.parse({
        tenantId: TENANT_ID,
        jobType: "sync",
        schemaCode: "shipment_rows",
        actorAuthUserId: AUTH_USER_ID,
        actorLabel: "requester",
      }),
    );
  });
});

describe("StageImportRowsInputSchema", () => {
  test("requires at least one row", () => {
    assert.throws(() =>
      StageImportRowsInputSchema.parse({
        jobId: JOB_ID,
        rows: [],
        actorAuthUserId: AUTH_USER_ID,
        actorLabel: "requester",
      }),
    );
  });

  test("accepts a non-empty rows array", () => {
    const parsed = StageImportRowsInputSchema.parse({
      jobId: JOB_ID,
      rows: [{ ref: "REF-001" }],
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "requester",
    });
    assert.equal(parsed.rows.length, 1);
  });
});
