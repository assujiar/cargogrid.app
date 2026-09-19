import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveImportExportSchemaColumns, previewImportJob, listImportStagingRows, getImportExportJob, sanitizeFormulaInjection, ImportExportQueryError, type ImportExportQueryRpcClient } from "./import-export.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): ImportExportQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("resolveImportExportSchemaColumns", () => {
  test("calls resolve_import_export_schema_columns with the exact snake_case params", async () => {
    const client = fakeClient({
      data: [{ config_version_id: VERSION_ID, columns: [{ key: "ref", label: "Reference", required: true, data_type: "text" }] }],
      error: null,
    });
    const resolved = await resolveImportExportSchemaColumns(client, { tenantId: TENANT_ID, schemaCode: "shipment_rows" });

    assert.deepEqual(client.calls[0]?.args, { p_tenant_id: TENANT_ID, p_schema_code: "shipment_rows" });
    assert.equal(resolved.configVersionId, VERSION_ID);
    assert.equal(resolved.columns.length, 1);
  });

  test("propagates import_export_schema_not_configured as a query error", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_schema_not_configured: tenant has not published a definition" } });
    await assert.rejects(
      () => resolveImportExportSchemaColumns(client, { tenantId: TENANT_ID, schemaCode: "never_published" }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportQueryError);
        assert.match(err.message, /import_export_schema_not_configured/);
        return true;
      },
    );
  });
});

describe("previewImportJob", () => {
  test("calls preview_import_job with the exact snake_case params and returns the aggregated counts", async () => {
    const client = fakeClient({ data: [{ total_rows: 4, valid_rows: 3, invalid_rows: 1, pending_rows: 0 }], error: null });
    const preview = await previewImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(preview.totalRows, 4);
    assert.equal(preview.validRows, 3);
    assert.equal(preview.invalidRows, 1);
    assert.equal(preview.pendingRows, 0);
  });

  test("propagates job_actor_unauthorized as a query error", async () => {
    const client = fakeClient({ data: null, error: { message: "job_actor_unauthorized: identity may not preview job" } });
    await assert.rejects(
      () => previewImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportQueryError);
        return true;
      },
    );
  });
});

describe("listImportStagingRows", () => {
  test("calls list_import_staging_rows with the exact snake_case params and maps every row", async () => {
    const client = fakeClient({
      data: [
        {
          id: "623e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          job_id: JOB_ID,
          row_number: 1,
          raw_payload: { open_item_type: "ar" },
          validation_status: "invalid",
          error: "currency: missing",
          created_at: "2026-08-30T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listImportStagingRows(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.validationStatus, "invalid");
    assert.equal(rows[0]?.error, "currency: missing");
  });

  test("returns an empty array when the job has no staged rows yet", async () => {
    const client = fakeClient({ data: [], error: null });
    const rows = await listImportStagingRows(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 0);
  });

  test("propagates job_actor_unauthorized as a query error", async () => {
    const client = fakeClient({ data: null, error: { message: "job_actor_unauthorized: identity may not list job rows" } });
    await assert.rejects(
      () => listImportStagingRows(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportQueryError);
        return true;
      },
    );
  });
});

describe("getImportExportJob", () => {
  test("calls get_import_export_job with the exact snake_case params and maps the full row", async () => {
    const client = fakeClient({
      data: {
        job_id: JOB_ID,
        tenant_id: TENANT_ID,
        job_type: "import",
        status: "in_progress",
        priority: 0,
        payload: { source_storage_path: "acme/opening-balances.csv" },
        attempts: 0,
        max_attempts: 3,
        locked_by: null,
        locked_until: null,
        error: null,
        result_url: null,
        created_by: "financemanagera",
        created_at: "2026-08-30T00:00:00.000Z",
        completed_at: null,
        requested_by_auth_user_id: ACTOR_ID,
        idempotency_key: null,
        import_export_schema_code: "finance_opening_balance_import",
        source_file_id: "723e4567-e89b-12d3-a456-426614174000",
        result_file_id: null,
        total_rows: null,
        processed_rows: 0,
        valid_row_count: 0,
        invalid_row_count: 0,
        cancel_reason: null,
        updated_at: "2026-08-30T00:00:00.000Z",
      },
      error: null,
    });
    const job = await getImportExportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(job.status, "in_progress");
    assert.equal(job.payload.source_storage_path, "acme/opening-balances.csv");
    assert.equal(job.totalRows, null);
  });

  test("propagates import_export_job_not_found as a query error", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_job_not_found: no job" } });
    await assert.rejects(
      () => getImportExportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ImportExportQueryError);
        return true;
      },
    );
  });
});

describe("sanitizeFormulaInjection", () => {
  test("calls sanitize_formula_injection with the exact snake_case params", async () => {
    const client = fakeClient({ data: "'=SUM(A1:A9)", error: null });
    const sanitized = await sanitizeFormulaInjection(client, "=SUM(A1:A9)");

    assert.deepEqual(client.calls[0]?.args, { p_value: "=SUM(A1:A9)" });
    assert.equal(sanitized, "'=SUM(A1:A9)");
  });

  test("passes ordinary text through untouched", async () => {
    const client = fakeClient({ data: "REF-001", error: null });
    const sanitized = await sanitizeFormulaInjection(client, "REF-001");
    assert.equal(sanitized, "REF-001");
  });
});
