import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createLeaveRequest,
  submitLeaveRequest,
  decideLeaveRequest,
  cancelLeaveRequest,
  adjustLeaveBalance,
  validateLeaveOpeningBalanceImportRow,
  commitLeaveOpeningBalanceImportJob,
  LeaveMutationError,
  type LeaveMutationRpcClient,
} from "./leave.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "423e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: LeaveMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LeaveMutationRpcClient;
  return { client, calls };
}

describe("createLeaveRequest", () => {
  test("maps input to snake_case RPC args", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "draft" }], error: null });
    await createLeaveRequest(client, {
      tenantId: TENANT_ID, leaveTypeId: ID_1, dateFrom: "2026-08-10", dateTo: "2026-08-10", dayPortion: "full_day",
      reason: "family event", destination: null, evidenceFileId: null, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "emp",
    });
    assert.equal(calls[0]?.fn, "create_leave_request");
    assert.equal(calls[0]?.args.p_day_portion, "full_day");
  });

  test("classifies a known error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "leave_request_overlap: employee already has an overlapping request" } });
    await assert.rejects(
      () => createLeaveRequest(client, {
        tenantId: TENANT_ID, leaveTypeId: ID_1, dateFrom: "2026-08-10", dateTo: "2026-08-10", dayPortion: "full_day",
        reason: "family event", destination: null, evidenceFileId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "leave_request_overlap",
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "totally_unexpected_thing: oops" } });
    await assert.rejects(
      () => createLeaveRequest(client, {
        tenantId: TENANT_ID, leaveTypeId: ID_1, dateFrom: "2026-08-10", dateTo: "2026-08-10", dayPortion: "full_day",
        reason: "family event", destination: null, evidenceFileId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "mutation_failed",
    );
  });
});

describe("submitLeaveRequest", () => {
  test("passes expectedVersion through", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "pending_approval" }], error: null });
    await submitLeaveRequest(client, { requestId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "emp" });
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });
});

describe("decideLeaveRequest", () => {
  test("passes overrideCoverage through", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "approved" }], error: null });
    await decideLeaveRequest(client, { requestStepId: ID_1, decision: "approved", reason: "ok", overrideCoverage: true, actorAuthUserId: ACTOR_ID, actorLabel: "mgr" });
    assert.equal(calls[0]?.args.p_override_coverage, true);
    assert.equal(calls[0]?.args.p_decision, "approved");
  });

  test("classifies coverage_below_minimum", async () => {
    const { client } = fakeClient({ data: null, error: { message: "coverage_below_minimum: approving this leave would drop coverage below minimum" } });
    await assert.rejects(
      () => decideLeaveRequest(client, { requestStepId: ID_1, decision: "approved", reason: "ok", overrideCoverage: false, actorAuthUserId: ACTOR_ID, actorLabel: "mgr" }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "coverage_below_minimum",
    );
  });
});

describe("cancelLeaveRequest", () => {
  test("classifies stale_version", async () => {
    const { client } = fakeClient({ data: null, error: { message: "stale_version: leave request target row was concurrently modified" } });
    await assert.rejects(
      () => cancelLeaveRequest(client, { requestId: ID_1, expectedVersion: 1, reason: "changed plans", actorAuthUserId: ACTOR_ID, actorLabel: "emp" }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "stale_version",
    );
  });
});

describe("adjustLeaveBalance", () => {
  test("maps a negative correction", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, units: -1 }], error: null });
    await adjustLeaveBalance(client, {
      tenantId: TENANT_ID, employeeId: ID_1, leaveTypeId: ID_1, units: -1, effectiveDate: "2026-08-10",
      reason: "correction of prior over-credit", idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    assert.equal(calls[0]?.args.p_units, -1);
  });
});

describe("validateLeaveOpeningBalanceImportRow (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls validate_leave_opening_balance_import_row with the exact snake_case params", async () => {
    const { client, calls } = fakeClient({
      data: {
        id: ROW_ID,
        tenant_id: TENANT_ID,
        job_id: JOB_ID,
        row_number: 1,
        raw_payload: { employee_number: "EMP-1", leave_type_code: "ANNUAL", units: "12", as_of_date: "2026-01-01" },
        validation_status: "valid",
        error: null,
        created_at: "2026-09-17T00:00:00.000Z",
      },
      error: null,
    });
    const row = await validateLeaveOpeningBalanceImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(calls[0]?.args, { p_staging_row_id: ROW_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester" });
    assert.equal(row.validationStatus, "valid");
  });

  test("wraps a database error into a typed LeaveMutationError", async () => {
    const { client } = fakeClient({ data: null, error: { message: "import_export_staging_row_not_found: no staging row" } });
    await assert.rejects(() => validateLeaveOpeningBalanceImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }), LeaveMutationError);
  });
});

describe("commitLeaveOpeningBalanceImportJob (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls commit_leave_opening_balance_import_job with the exact snake_case params, including client IP, defaulting allowPartial to false", async () => {
    const { client, calls } = fakeClient({
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
        created_by: "tester",
        created_at: "2026-09-17T00:00:00.000Z",
        completed_at: "2026-09-17T00:05:00.000Z",
        requested_by_auth_user_id: ACTOR_ID,
        idempotency_key: "idem-leave-opening-balance-import-job",
        import_export_schema_code: "leave_opening_balance_import",
        source_file_id: "623e4567-e89b-12d3-a456-426614174000",
        result_file_id: null,
        total_rows: 1,
        processed_rows: 1,
        valid_row_count: 1,
        invalid_row_count: 0,
        cancel_reason: null,
        updated_at: "2026-09-17T00:05:00.000Z",
      },
      error: null,
    });
    const job = await commitLeaveOpeningBalanceImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "203.0.113.5" });

    assert.deepEqual(calls[0]?.args, { p_job_id: JOB_ID, p_allow_partial: false, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester", p_client_ip: "203.0.113.5" });
    assert.equal(job.status, "completed");
  });

  test("classifies job_actor_unauthorized, mfa_step_up_required, and ip_not_allowed", async () => {
    const membershipClient = fakeClient({ data: null, error: { message: "job_actor_unauthorized: identity x lacks active membership in tenant y" } }).client;
    await assert.rejects(
      () => commitLeaveOpeningBalanceImportJob(membershipClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof LeaveMutationError);
        assert.equal(err.code, "job_actor_unauthorized");
        return true;
      },
    );
    const mfaClient = fakeClient({ data: null, error: { message: "mfa_step_up_required: HRS:Import requires a current MFA step-up verification" } }).client;
    await assert.rejects(
      () => commitLeaveOpeningBalanceImportJob(mfaClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof LeaveMutationError);
        assert.equal(err.code, "mfa_step_up_required");
        return true;
      },
    );
    const ipClient = fakeClient({ data: null, error: { message: "ip_not_allowed: malformed IP address denied for scope" } }).client;
    await assert.rejects(
      () => commitLeaveOpeningBalanceImportJob(ipClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "bad-ip" }),
      (err: unknown) => {
        assert.ok(err instanceof LeaveMutationError);
        assert.equal(err.code, "ip_not_allowed");
        return true;
      },
    );
  });

  test("classifies insufficient_authority when the actor holds HRS:Import but lacks is_support_grant_authority", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: actor lacks Supreme Admin or tenant_admin grant" } });
    await assert.rejects(
      () => commitLeaveOpeningBalanceImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "insufficient_authority",
    );
  });
});
