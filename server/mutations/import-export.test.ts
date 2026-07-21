import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerImportExportSchema,
  publishImportExportSchema,
  createImportExportJob,
  stageImportRows,
  validateStagingRow,
  commitImportJob,
  cancelImportExportJob,
  acknowledgeJobCancellation,
  completeExportJob,
  recordJobFailure,
  requeueDeadLetterJob,
  ImportExportMutationError,
  type ImportExportMutationRpcClient,
} from "./import-export.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "523e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "823e4567-e89b-12d3-a456-426614174000";

const VALID_JOB_ROW = {
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
  requested_by_auth_user_id: ACTOR_ID,
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
};

const VALID_STAGING_ROW = {
  id: ROW_ID,
  tenant_id: TENANT_ID,
  job_id: JOB_ID,
  row_number: 1,
  raw_payload: { ref: "REF-001" },
  validation_status: "valid",
  error: null,
  created_at: "2026-07-19T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): ImportExportMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("registerImportExportSchema", () => {
  test("calls register_import_export_schema with the exact snake_case params", async () => {
    const client = fakeClient({
      data: { code: "shipment_rows", name: "Shipment Rows", owner_primitive_code: "SHP", registered_by: "supreme admin", created_at: "2026-07-19T00:00:00.000Z" },
      error: null,
    });
    const schema = await registerImportExportSchema(client, { code: "shipment_rows", name: "Shipment Rows", ownerPrimitiveCode: "SHP", actorAuthUserId: ACTOR_ID, registeredBy: "supreme admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_code: "shipment_rows",
      p_name: "Shipment Rows",
      p_owner_primitive_code: "SHP",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "supreme admin",
    });
    assert.equal(schema.code, "shipment_rows");
  });

  test("classifies insufficient_authority into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register an import/export schema" } });
    await assert.rejects(
      () => registerImportExportSchema(client, { code: "x", name: "X", ownerPrimitiveCode: "X", actorAuthUserId: ACTOR_ID, registeredBy: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishImportExportSchema", () => {
  test("calls publish_import_export_schema with the exact snake_case params", async () => {
    const client = fakeClient({
      data: {
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
      },
      error: null,
    });
    const version = await publishImportExportSchema(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, effectiveFrom: "2026-07-19T00:00:00.000Z", actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_effective_from: "2026-07-19T00:00:00.000Z",
      p_actor_label: "tenant admin",
    });
    assert.equal(version.status, "published");
  });

  test("classifies import_export_missing_columns into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_missing_columns: version has no 'columns' item" } });
    await assert.rejects(
      () => publishImportExportSchema(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, effectiveFrom: "2026-07-19T00:00:00.000Z", actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "import_export_missing_columns");
        return true;
      },
    );
  });
});

describe("createImportExportJob", () => {
  test("calls create_import_export_job with the exact snake_case params, defaulting filters/sourceFileId/idempotencyKey", async () => {
    const client = fakeClient({ data: VALID_JOB_ROW, error: null });
    const job = await createImportExportJob(client, {
      tenantId: TENANT_ID,
      jobType: "import",
      schemaCode: "shipment_rows",
      sourceFileId: FILE_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "requester",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_job_type: "import",
      p_schema_code: "shipment_rows",
      p_source_file_id: FILE_ID,
      p_filters: {},
      p_idempotency_key: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "requester",
    });
    assert.equal(job.jobId, JOB_ID);
  });

  test("classifies import_missing_source_file into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "import_missing_source_file: an import job requires a source_file_id" } });
    await assert.rejects(
      () => createImportExportJob(client, { tenantId: TENANT_ID, jobType: "import", schemaCode: "shipment_rows", actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "import_missing_source_file");
        return true;
      },
    );
  });
});

describe("stageImportRows", () => {
  test("calls stage_import_rows with the exact snake_case params and returns the staged count", async () => {
    const client = fakeClient({ data: 2, error: null });
    const count = await stageImportRows(client, { jobId: JOB_ID, rows: [{ ref: "A" }, { ref: "B" }], actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_job_id: JOB_ID,
      p_rows: [{ ref: "A" }, { ref: "B" }],
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "requester",
    });
    assert.equal(count, 2);
  });

  test("classifies import_source_file_infected into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "import_source_file_infected: file is quarantined, cannot stage rows from it" } });
    await assert.rejects(
      () => stageImportRows(client, { jobId: JOB_ID, rows: [{ ref: "A" }], actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "import_source_file_infected");
        return true;
      },
    );
  });
});

describe("validateStagingRow", () => {
  test("calls validate_staging_row with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_STAGING_ROW, error: null });
    const row = await validateStagingRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, { p_staging_row_id: ROW_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "requester" });
    assert.equal(row.validationStatus, "valid");
  });
});

describe("commitImportJob", () => {
  test("calls commit_import_job with the exact snake_case params, defaulting allowPartial to false", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, status: "completed" }, error: null });
    const job = await commitImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_allow_partial: false, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "requester" });
    assert.equal(job.status, "completed");
  });

  test("classifies import_export_job_has_invalid_rows into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_job_has_invalid_rows: job has 1 invalid row(s)" } });
    await assert.rejects(
      () => commitImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "import_export_job_has_invalid_rows");
        return true;
      },
    );
  });
});

describe("cancelImportExportJob", () => {
  test("calls cancel_import_export_job with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, status: "cancelled" }, error: null });
    const job = await cancelImportExportJob(client, { jobId: JOB_ID, reason: "no longer needed", actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_reason: "no longer needed", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "requester" });
    assert.equal(job.status, "cancelled");
  });
});

describe("acknowledgeJobCancellation", () => {
  test("calls acknowledge_job_cancellation with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, status: "cancelled" }, error: null });
    const job = await acknowledgeJobCancellation(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "requester" });
    assert.equal(job.status, "cancelled");
  });

  test("classifies import_export_job_not_cancelling into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_job_not_cancelling: job is pending" } });
    await assert.rejects(
      () => acknowledgeJobCancellation(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "import_export_job_not_cancelling");
        return true;
      },
    );
  });
});

describe("completeExportJob", () => {
  test("calls complete_export_job with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, job_type: "export", status: "completed", result_file_id: FILE_ID, source_file_id: null }, error: null });
    const job = await completeExportJob(client, { jobId: JOB_ID, resultFileId: FILE_ID, rowCount: 5, actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_result_file_id: FILE_ID, p_row_count: 5, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "requester" });
    assert.equal(job.resultFileId, FILE_ID);
  });

  test("classifies export_result_file_not_found into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "export_result_file_not_found: no file in tenant" } });
    await assert.rejects(
      () => completeExportJob(client, { jobId: JOB_ID, resultFileId: FILE_ID, rowCount: 5, actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "export_result_file_not_found");
        return true;
      },
    );
  });
});

describe("recordJobFailure", () => {
  test("calls record_job_failure with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, attempts: 1, error: "transient error" }, error: null });
    const job = await recordJobFailure(client, { jobId: JOB_ID, errorMessage: "transient error", actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_error_message: "transient error", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "requester" });
    assert.equal(job.attempts, 1);
  });

  test("classifies import_export_job_already_terminal into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_job_already_terminal: job is already completed" } });
    await assert.rejects(
      () => recordJobFailure(client, { jobId: JOB_ID, errorMessage: "x", actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "import_export_job_already_terminal");
        return true;
      },
    );
  });
});

describe("requeueDeadLetterJob", () => {
  test("calls requeue_dead_letter_job with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, attempts: 0, status: "pending" }, error: null });
    const job = await requeueDeadLetterJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tenant admin" });
    assert.equal(job.attempts, 0);
  });

  test("classifies job_requeue_unauthorized into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "job_requeue_unauthorized: identity lacks support/supreme authority" } });
    await assert.rejects(
      () => requeueDeadLetterJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportMutationError);
        assert.equal(err.code, "job_requeue_unauthorized");
        return true;
      },
    );
  });
});
