import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  assertHrisExportAuthority,
  exportAttendanceSessions,
  exportLeaveRequests,
  exportScheduleAssignments,
  exportTimesheetEntries,
  HrisExportQueryError,
  type HrisExportQueryClient,
} from "./hris-export.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const RANGE = { fromDate: "2026-08-01", toDate: "2026-08-31" };

/** Answers evaluate_permission from `allowed`, every other RPC from `rows`. */
function fakeClient(options: { allowed?: boolean; rows?: unknown; error?: { message: string } | null }): {
  client: HrisExportQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      if (fn === "evaluate_permission") {
        return {
          data: {
            allowed: options.allowed ?? true,
            reason: options.allowed === false ? "no_role_grants_permission" : "granted",
            permission_id: null,
            role_id: null,
            role_version_id: null,
            evaluated_at: "2026-08-31T00:00:00.000Z",
          },
          error: null,
        };
      }
      return { data: options.rows ?? [], error: options.error ?? null };
    },
  } as unknown as HrisExportQueryClient;
  return { client, calls };
}

describe("assertHrisExportAuthority", () => {
  test("passes silently when HRS:Export is granted, and asks for exactly that permission", async () => {
    const { client, calls } = fakeClient({ allowed: true });
    await assertHrisExportAuthority(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "evaluate_permission");
    assert.equal(calls[0]?.args["p_resource_module_code"], "HRS");
    assert.equal(calls[0]?.args["p_action"], "Export");
  });

  test("throws insufficient_authority when it is not, carrying the decision's own reason", async () => {
    const { client } = fakeClient({ allowed: false });
    await assert.rejects(
      () => assertHrisExportAuthority(client, TENANT_ID, ACTOR_ID),
      (error: unknown) => error instanceof HrisExportQueryError && error.code === "insufficient_authority" && /no_role_grants_permission/.test(error.message),
    );
  });
});

describe("export date-range validation", () => {
  test("a range longer than 366 days is refused before any RPC call", async () => {
    const { client, calls } = fakeClient({ allowed: true });
    await assert.rejects(
      () => exportAttendanceSessions(client, TENANT_ID, ACTOR_ID, { fromDate: "2025-01-01", toDate: "2026-06-01" }),
      (error: unknown) => error instanceof HrisExportQueryError && error.code === "invalid_date_range",
    );
    assert.equal(calls.length, 0);
  });

  test("exactly 366 days is allowed -- the cap is inclusive, matching the RPCs' own `> 366` test", async () => {
    const { client } = fakeClient({ allowed: true, rows: [] });
    assert.deepEqual(await exportAttendanceSessions(client, TENANT_ID, ACTOR_ID, { fromDate: "2026-01-01", toDate: "2027-01-02" }), []);
  });

  test("a reversed range is refused rather than silently returning nothing", async () => {
    const { client } = fakeClient({ allowed: true });
    await assert.rejects(
      () => exportLeaveRequests(client, TENANT_ID, ACTOR_ID, { fromDate: "2026-08-31", toDate: "2026-08-01" }),
      (error: unknown) => error instanceof HrisExportQueryError && error.code === "invalid_date_range",
    );
  });
});

describe("the four export wrappers", () => {
  test("an unauthorised caller is refused BEFORE the export RPC runs -- the whole point of the wrapper", async () => {
    const { client, calls } = fakeClient({ allowed: false, rows: [] });
    await assert.rejects(
      () => exportTimesheetEntries(client, TENANT_ID, ACTOR_ID, RANGE),
      (error: unknown) => error instanceof HrisExportQueryError && error.code === "insufficient_authority",
    );
    // Without this, the RPC's own `return;` on denial would have produced an empty
    // export indistinguishable from an empty date range.
    assert.deepEqual(
      calls.map((c) => c.fn),
      ["evaluate_permission"],
    );
  });

  test("exportAttendanceSessions maps its row shape and passes the exact param names", async () => {
    const { client, calls } = fakeClient({
      allowed: true,
      rows: [
        {
          employee_number: "EMP-001",
          employee_full_name: "Ada Lovelace",
          work_date: "2026-08-03",
          status: "present",
          effective_clock_in_at: "2026-08-03T01:00:00.000Z",
          effective_clock_out_at: null,
          payroll_input_status: "pending",
          exception_types: "late_in",
        },
      ],
    });
    const rows = await exportAttendanceSessions(client, TENANT_ID, ACTOR_ID, RANGE);
    assert.equal(rows[0]?.employeeNumber, "EMP-001");
    assert.equal(rows[0]?.effectiveClockOutAt, null);
    assert.deepEqual(calls[1], {
      fn: "export_attendance_sessions",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_from_date: "2026-08-01", p_to_date: "2026-08-31" },
    });
  });

  test("exportScheduleAssignments maps its row shape", async () => {
    const { client, calls } = fakeClient({
      allowed: true,
      rows: [{ employee_number: "EMP-002", employee_full_name: "Grace Hopper", work_date: "2026-08-04", shift_template_name: "Day", status: "published" }],
    });
    const rows = await exportScheduleAssignments(client, TENANT_ID, ACTOR_ID, RANGE);
    assert.equal(rows[0]?.shiftTemplateName, "Day");
    assert.equal(calls[1]?.fn, "export_schedule_assignments");
  });

  test("exportLeaveRequests normalises the RPC's own employee_code/employee_name column names", async () => {
    const { client } = fakeClient({
      allowed: true,
      rows: [
        {
          employee_code: "EMP-003",
          employee_name: "Katherine Johnson",
          leave_type_code: "ANNUAL",
          category: "leave",
          date_from: "2026-08-10",
          date_to: "2026-08-12",
          total_units: "3.0",
          status: "approved",
        },
      ],
    });
    const rows = await exportLeaveRequests(client, TENANT_ID, ACTOR_ID, RANGE);
    // The other three RPCs call these columns employee_number/employee_full_name; the
    // difference is absorbed here so it never reaches a call site or a CSV header.
    assert.equal(rows[0]?.employeeNumber, "EMP-003");
    assert.equal(rows[0]?.employeeFullName, "Katherine Johnson");
    assert.equal(rows[0]?.totalUnits, 3);
  });

  test("exportTimesheetEntries maps its row shape, nullable job/shipment included", async () => {
    const { client } = fakeClient({
      allowed: true,
      rows: [
        {
          employee_number: "EMP-004",
          employee_full_name: "Margaret Hamilton",
          work_date: "2026-08-05",
          job_number: null,
          shipment_number: null,
          entry_minutes: 480,
          eligible_minutes: 60,
          approved_minutes: null,
          status: "submitted",
        },
      ],
    });
    const rows = await exportTimesheetEntries(client, TENANT_ID, ACTOR_ID, RANGE);
    assert.equal(rows[0]?.jobNumber, null);
    assert.equal(rows[0]?.approvedMinutes, null);
    assert.equal(rows[0]?.entryMinutes, 480);
  });

  test("a null result is an empty list, never a throw", async () => {
    const { client } = fakeClient({ allowed: true, rows: null });
    assert.deepEqual(await exportScheduleAssignments(client, TENANT_ID, ACTOR_ID, RANGE), []);
  });

  test("an RPC error is wrapped, with a recognised prefix mapped to a code", async () => {
    const { client } = fakeClient({ allowed: true, rows: null, error: { message: "invalid_date_range: export date range must be non-empty and at most 366 days" } });
    await assert.rejects(
      () => exportTimesheetEntries(client, TENANT_ID, ACTOR_ID, RANGE),
      (error: unknown) => error instanceof HrisExportQueryError && error.code === "invalid_date_range",
    );
  });
});
