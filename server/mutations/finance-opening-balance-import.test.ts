import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  validateFinanceOpeningBalanceImportRow,
  commitFinanceOpeningBalanceImportJob,
  FinanceOpeningBalanceImportMutationError,
  type FinanceOpeningBalanceImportMutationRpcClient,
} from "./finance-opening-balance-import.ts";

const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): FinanceOpeningBalanceImportMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("validateFinanceOpeningBalanceImportRow", () => {
  test("calls validate_finance_opening_balance_import_row with the exact snake_case params", async () => {
    const client = fakeClient({
      data: {
        id: ROW_ID,
        tenant_id: TENANT_ID,
        job_id: JOB_ID,
        row_number: 1,
        raw_payload: { open_item_type: "ar" },
        validation_status: "invalid",
        error: "currency: (missing) is not a registered, active currency",
        created_at: "2026-08-30T00:00:00.000Z",
      },
      error: null,
    });
    const row = await validateFinanceOpeningBalanceImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera" });

    assert.deepEqual(client.calls[0]?.args, { p_staging_row_id: ROW_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "financemanagera" });
    assert.equal(row.validationStatus, "invalid");
    assert.match(row.error ?? "", /currency/);
  });

  test("wraps a database error into a typed FinanceOpeningBalanceImportMutationError", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_staging_row_not_found: no staging row" } });
    await assert.rejects(
      () => validateFinanceOpeningBalanceImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera" }),
      FinanceOpeningBalanceImportMutationError,
    );
  });
});

describe("commitFinanceOpeningBalanceImportJob", () => {
  test("calls commit_finance_opening_balance_import_job with the exact snake_case params, including client IP", async () => {
    const client = fakeClient({
      data: {
        job_id: JOB_ID,
        tenant_id: TENANT_ID,
        job_type: "import",
        status: "completed",
        priority: 0,
        payload: {},
        attempts: 0,
        max_attempts: 3,
        locked_by: null,
        locked_until: null,
        error: null,
        result_url: null,
        created_by: "financemanagera",
        created_at: "2026-08-30T00:00:00.000Z",
        completed_at: "2026-08-30T00:05:00.000Z",
        requested_by_auth_user_id: ACTOR_ID,
        idempotency_key: "idem-fin-ob-job",
        import_export_schema_code: "finance_opening_balance_import",
        source_file_id: "723e4567-e89b-12d3-a456-426614174000",
        result_file_id: null,
        total_rows: 1,
        processed_rows: 1,
        valid_row_count: 1,
        invalid_row_count: 0,
        cancel_reason: null,
        updated_at: "2026-08-30T00:05:00.000Z",
      },
      error: null,
    });
    const job = await commitFinanceOpeningBalanceImportJob(client, { jobId: JOB_ID, allowPartial: true, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera", clientIp: "203.0.113.5" });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_allow_partial: true, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "financemanagera", p_client_ip: "203.0.113.5" });
    assert.equal(job.status, "completed");
  });

  test("classifies mfa_step_up_required as its own error code", async () => {
    const client = fakeClient({ data: null, error: { message: "mfa_step_up_required: FIN:Import requires a current MFA step-up verification" } });
    await assert.rejects(
      () => commitFinanceOpeningBalanceImportJob(client, { jobId: JOB_ID, allowPartial: false, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera", clientIp: null }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceOpeningBalanceImportMutationError);
        assert.equal(err.code, "mfa_step_up_required");
        return true;
      },
    );
  });

  test("classifies ip_not_allowed as its own error code", async () => {
    const client = fakeClient({ data: null, error: { message: "ip_not_allowed: malformed IP address denied for scope" } });
    await assert.rejects(
      () => commitFinanceOpeningBalanceImportJob(client, { jobId: JOB_ID, allowPartial: false, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera", clientIp: "bad-ip" }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceOpeningBalanceImportMutationError);
        assert.equal(err.code, "ip_not_allowed");
        return true;
      },
    );
  });

  test("classifies import_export_job_has_invalid_rows (a code inherited from the generic framework) correctly", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_job_has_invalid_rows: job has 2 invalid row(s)" } });
    await assert.rejects(
      () => commitFinanceOpeningBalanceImportJob(client, { jobId: JOB_ID, allowPartial: false, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera", clientIp: null }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceOpeningBalanceImportMutationError);
        assert.equal(err.code, "import_export_job_has_invalid_rows");
        return true;
      },
    );
  });

  test("classifies import_export_wrong_schema (CG-AUDIT-2026-09-02 A4, found while scoping vendor_import)", async () => {
    const client = fakeClient({ data: null, error: { message: "import_export_wrong_schema: job x is not a finance_opening_balance_import job" } });
    await assert.rejects(
      () => commitFinanceOpeningBalanceImportJob(client, { jobId: JOB_ID, allowPartial: false, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera", clientIp: null }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceOpeningBalanceImportMutationError);
        assert.equal(err.code, "import_export_wrong_schema");
        return true;
      },
    );
  });
});
