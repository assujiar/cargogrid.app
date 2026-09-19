import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  recordAttendanceClockEvent,
  requestAttendanceCorrection,
  decideAttendanceCorrection,
  waiveAttendanceException,
  validateAttendanceDeviceImportRow,
  commitAttendanceDeviceImportJob,
  AttendanceMutationError,
  type AttendanceMutationRpcClient,
} from "./attendance.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "423e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: AttendanceMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AttendanceMutationRpcClient;
  return { client, calls };
}

describe("recordAttendanceClockEvent", () => {
  test("maps input to snake_case RPC args", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, event_type: "clock_in" }], error: null });
    await recordAttendanceClockEvent(client, {
      tenantId: TENANT_ID, eventType: "clock_in", sourceChannel: "mobile_web", clientReportedAt: null,
      locationGeojson: null, deviceLabel: null, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "emp",
    });
    assert.equal(calls[0]?.fn, "record_attendance_clock_event");
    assert.equal(calls[0]?.args.p_source_channel, "mobile_web");
  });

  test("classifies a known error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "duplicate_open_session: employee already has an open session" } });
    await assert.rejects(
      () => recordAttendanceClockEvent(client, {
        tenantId: TENANT_ID, eventType: "clock_in", sourceChannel: "mobile_web", clientReportedAt: null,
        locationGeojson: null, deviceLabel: null, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
      (err: unknown) => err instanceof AttendanceMutationError && err.code === "duplicate_open_session",
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "totally_unexpected_thing: oops" } });
    await assert.rejects(
      () => recordAttendanceClockEvent(client, {
        tenantId: TENANT_ID, eventType: "clock_in", sourceChannel: "mobile_web", clientReportedAt: null,
        locationGeojson: null, deviceLabel: null, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
      (err: unknown) => err instanceof AttendanceMutationError && err.code === "mutation_failed",
    );
  });
});

describe("requestAttendanceCorrection / decideAttendanceCorrection", () => {
  test("requestAttendanceCorrection rejects an empty reason at the schema layer, never reaching the RPC", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1 }], error: null });
    await assert.rejects(() =>
      requestAttendanceCorrection(client, {
        sessionId: ID_1, requestType: "adjust_clock_out", proposedClockInAt: null, proposedClockOutAt: "2026-08-10T10:00:00Z",
        reason: "", evidenceFileId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
    );
    assert.equal(calls.length, 0);
  });

  test("decideAttendanceCorrection surfaces self_approval_not_permitted", async () => {
    const { client } = fakeClient({ data: null, error: { message: "self_approval_not_permitted: an actor may not decide their own attendance correction request" } });
    await assert.rejects(
      () => decideAttendanceCorrection(client, { requestId: ID_1, expectedVersion: 1, decision: "approve", decidedReason: "ok", actorAuthUserId: ACTOR_ID, actorLabel: "emp" }),
      (err: unknown) => err instanceof AttendanceMutationError && err.code === "self_approval_not_permitted",
    );
  });
});

describe("waiveAttendanceException", () => {
  test("requires a non-empty waive reason at the schema layer", async () => {
    await assert.rejects(() =>
      waiveAttendanceException(fakeClient({ data: [], error: null }).client, {
        exceptionId: ID_1, expectedVersion: 1, waiveReason: "", actorAuthUserId: ACTOR_ID, actorLabel: "approver",
      }),
    );
  });
});

describe("validateAttendanceDeviceImportRow (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls validate_attendance_device_import_row with the exact snake_case params", async () => {
    const { client, calls } = fakeClient({
      data: {
        id: ROW_ID,
        tenant_id: TENANT_ID,
        job_id: JOB_ID,
        row_number: 1,
        raw_payload: { employee_number: "EMP-1", event_type: "clock_in" },
        validation_status: "valid",
        error: null,
        created_at: "2026-09-17T00:00:00.000Z",
      },
      error: null,
    });
    const row = await validateAttendanceDeviceImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(calls[0]?.args, { p_staging_row_id: ROW_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester" });
    assert.equal(row.validationStatus, "valid");
  });

  test("wraps a database error into a typed AttendanceMutationError", async () => {
    const { client } = fakeClient({ data: null, error: { message: "import_export_staging_row_not_found: no staging row" } });
    await assert.rejects(() => validateAttendanceDeviceImportRow(client, { stagingRowId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }), AttendanceMutationError);
  });
});

describe("commitAttendanceDeviceImportJob (CG-AUDIT-2026-09-02 A4)", () => {
  test("calls commit_attendance_device_import_job with the exact snake_case params, including client IP, defaulting allowPartial to false", async () => {
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
        idempotency_key: "idem-attendance-import-job",
        import_export_schema_code: "attendance_device_import",
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
    const job = await commitAttendanceDeviceImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "203.0.113.5" });

    assert.deepEqual(calls[0]?.args, { p_job_id: JOB_ID, p_allow_partial: false, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester", p_client_ip: "203.0.113.5" });
    assert.equal(job.status, "completed");
  });

  test("classifies job_actor_unauthorized, mfa_step_up_required, and ip_not_allowed", async () => {
    const membershipClient = fakeClient({ data: null, error: { message: "job_actor_unauthorized: identity x lacks active membership in tenant y" } }).client;
    await assert.rejects(
      () => commitAttendanceDeviceImportJob(membershipClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AttendanceMutationError);
        assert.equal(err.code, "job_actor_unauthorized");
        return true;
      },
    );
    const mfaClient = fakeClient({ data: null, error: { message: "mfa_step_up_required: HRS:Import requires a current MFA step-up verification" } }).client;
    await assert.rejects(
      () => commitAttendanceDeviceImportJob(mfaClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AttendanceMutationError);
        assert.equal(err.code, "mfa_step_up_required");
        return true;
      },
    );
    const ipClient = fakeClient({ data: null, error: { message: "ip_not_allowed: malformed IP address denied for scope" } }).client;
    await assert.rejects(
      () => commitAttendanceDeviceImportJob(ipClient, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", clientIp: "bad-ip" }),
      (err: unknown) => {
        assert.ok(err instanceof AttendanceMutationError);
        assert.equal(err.code, "ip_not_allowed");
        return true;
      },
    );
  });
});
