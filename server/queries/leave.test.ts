import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listLeaveTypes,
  listEmployeeLeaveBalances,
  listLeaveRequests,
  getLeaveRequestDetail,
  getLeaveCalendar,
  LeaveQueryError,
  type LeaveQueryClient,
} from "./leave.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: LeaveQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LeaveQueryClient;
  return { client, calls };
}

describe("listLeaveTypes", () => {
  test("passes tenant/actor through and parses rows", async () => {
    const { client, calls } = fakeClient({
      data: [{ id: ID_1, code: "annual", name: "Annual Leave", category: "leave", requires_balance: true, requires_evidence: false, evidence_classification: "none", status: "published", record_version: 1 }],
      error: null,
    });
    const rows = await listLeaveTypes(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(rows[0]?.code, "annual");
  });

  test("throws LeaveQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listLeaveTypes(client, TENANT_ID, ACTOR_ID), LeaveQueryError);
  });
});

describe("listEmployeeLeaveBalances", () => {
  test("defaults employeeId/asOfDate to null", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listEmployeeLeaveBalances(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_employee_id, null);
    assert.equal(calls[0]?.args.p_as_of_date, null);
  });
});

describe("listLeaveRequests", () => {
  test("defaults limit to 50 and applies filters", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listLeaveRequests(client, TENANT_ID, ACTOR_ID, { employeeId: ID_1, status: "approved" });
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_employee_id, ID_1);
    assert.equal(calls[0]?.args.p_status, "approved");
  });
});

describe("getLeaveRequestDetail", () => {
  test("returns null when the RPC yields no row", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const detail = await getLeaveRequestDetail(client, ID_1, ACTOR_ID);
    assert.equal(detail, null);
  });

  test("throws LeaveQueryError when the RPC raises (folded not-found/no-access)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "leave_request_not_found: no row" } });
    await assert.rejects(() => getLeaveRequestDetail(client, ID_1, ACTOR_ID), LeaveQueryError);
  });

  test("parses the single returned row", async () => {
    const { client } = fakeClient({
      data: [{
        id: ID_1, employee_id: ID_1, leave_type_id: ID_1, status: "approved", date_from: "2026-08-10",
        date_to: "2026-08-10", day_portion: "full_day", total_units: "1", reason: "medical", destination: null,
        evidence_file_id: null, schedule_snapshot: [], payroll_input_status: "pending", decided_reason: "ok",
        cancel_reason: null, record_version: 2,
      }],
      error: null,
    });
    const detail = await getLeaveRequestDetail(client, ID_1, ACTOR_ID);
    assert.equal(detail?.status, "approved");
  });
});

describe("getLeaveCalendar", () => {
  test("passes date range and org_unit filter through", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await getLeaveCalendar(client, TENANT_ID, ACTOR_ID, null, "2026-08-01", "2026-08-31");
    assert.equal(calls[0]?.args.p_from_date, "2026-08-01");
    assert.equal(calls[0]?.args.p_org_unit_id, null);
  });
});
