import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getMyAttendanceStatus, listAttendanceSessions, getAttendanceSessionDetail, listAttendanceExceptions, AttendanceQueryError, type AttendanceQueryClient } from "./attendance.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: AttendanceQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AttendanceQueryClient;
  return { client, calls };
}

describe("getMyAttendanceStatus", () => {
  test("passes tenant/actor through and parses rows", async () => {
    const { client, calls } = fakeClient({
      data: [{ session_id: ID_1, work_date: "2026-08-10", status: "open", effective_clock_in_at: "2026-08-10T01:00:00Z", effective_clock_out_at: null, open_exception_count: 0, payroll_input_status: "pending" }],
      error: null,
    });
    const rows = await getMyAttendanceStatus(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(rows[0]?.status, "open");
  });

  test("throws AttendanceQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => getMyAttendanceStatus(client, TENANT_ID, ACTOR_ID), AttendanceQueryError);
  });
});

describe("listAttendanceSessions", () => {
  test("defaults limit to 50 and applies filters", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listAttendanceSessions(client, TENANT_ID, ACTOR_ID, { employeeId: ID_1, status: "closed" });
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_employee_id, ID_1);
    assert.equal(calls[0]?.args.p_status, "closed");
  });
});

describe("getAttendanceSessionDetail", () => {
  test("returns null when the RPC yields no row (folded not-found/no-access)", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const detail = await getAttendanceSessionDetail(client, ID_1, ACTOR_ID);
    assert.equal(detail, null);
  });
});

describe("listAttendanceExceptions", () => {
  test("maps status filter through", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listAttendanceExceptions(client, TENANT_ID, ACTOR_ID, { status: "open" });
    assert.equal(calls[0]?.args.p_status, "open");
  });
});
