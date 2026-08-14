import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createOvertimeRequest,
  submitOvertimeRequest,
  decideOvertimeRequest,
  cancelOvertimeRequest,
  createTimesheetEntry,
  decideTimesheetEntry,
  createTimesheetPeriod,
  lockTimesheetPeriod,
  reopenTimesheetPeriod,
  generatePayrollTimeInput,
  generatePayrollTimeInputsForPeriod,
  OvertimeTimesheetMutationError,
  type OvertimeTimesheetMutationRpcClient,
} from "./overtime-timesheet.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: OvertimeTimesheetMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as OvertimeTimesheetMutationRpcClient;
  return { client, calls };
}

describe("createOvertimeRequest / submitOvertimeRequest / decideOvertimeRequest / cancelOvertimeRequest", () => {
  test("createOvertimeRequest maps input to snake_case RPC args -- no employee-id field exists (self-only, structural anti-spoofing)", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "draft" }], error: null });
    await createOvertimeRequest(client, {
      tenantId: TENANT_ID, requestType: "planned", requestedStartAt: "2026-08-10T17:00:00Z", requestedEndAt: "2026-08-10T19:00:00Z",
      unpaidBreakMinutes: 0, reason: "deadline", scheduleAssignmentId: null, jobOrderId: null, shipmentOrderId: null,
      idempotencyKey: "ot-1", actorAuthUserId: ACTOR_ID, actorLabel: "emp1",
    });
    assert.equal(calls[0]?.fn, "create_overtime_request");
    assert.equal("p_employee_id" in (calls[0]?.args ?? {}), false);
  });

  test("submitOvertimeRequest passes expected_version through for the optimistic-lock guard", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "pending_approval" }], error: null });
    await submitOvertimeRequest(client, { requestId: ID_1, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "emp1" });
    assert.equal(calls[0]?.args.p_expected_version, 3);
  });

  test("decideOvertimeRequest classifies a known error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "self_approval_not_permitted: an actor may not decide their own overtime request" } });
    await assert.rejects(
      () => decideOvertimeRequest(client, { requestId: ID_1, expectedVersion: 1, decision: "approve", decidedReason: "x", approvedMinutesOverride: null, actorAuthUserId: ACTOR_ID, actorLabel: "a" }),
      (err: unknown) => err instanceof OvertimeTimesheetMutationError && err.code === "self_approval_not_permitted",
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "totally_unexpected_thing: oops" } });
    await assert.rejects(
      () => cancelOvertimeRequest(client, { requestId: ID_1, expectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "a" }),
      (err: unknown) => err instanceof OvertimeTimesheetMutationError && err.code === "mutation_failed",
    );
  });

  test("throws mutation_failed when the RPC returns no row", async () => {
    const { client } = fakeClient({ data: [], error: null });
    await assert.rejects(
      () => cancelOvertimeRequest(client, { requestId: ID_1, expectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "a" }),
      (err: unknown) => err instanceof OvertimeTimesheetMutationError && err.code === "mutation_failed",
    );
  });
});

describe("createTimesheetEntry / decideTimesheetEntry", () => {
  test("createTimesheetEntry forwards job/shipment reference ids for independent authorization", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1 }], error: null });
    await createTimesheetEntry(client, {
      tenantId: TENANT_ID, workDate: "2026-08-10", entryMinutes: 480, unpaidBreakMinutes: 30, jobOrderId: ID_1,
      shipmentOrderId: null, scheduleAssignmentId: null, notes: null, idempotencyKey: "ts-1", actorAuthUserId: ACTOR_ID, actorLabel: "emp1",
    });
    assert.equal(calls[0]?.args.p_job_order_id, ID_1);
  });

  test("decideTimesheetEntry allows a null approvedMinutesOverride", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "approved" }], error: null });
    await decideTimesheetEntry(client, { entryId: ID_1, expectedVersion: 2, decision: "approve", decidedReason: "ok", approvedMinutesOverride: null, actorAuthUserId: ACTOR_ID, actorLabel: "a" });
    assert.equal(calls[0]?.args.p_approved_minutes_override, null);
  });
});

describe("createTimesheetPeriod / lockTimesheetPeriod / reopenTimesheetPeriod", () => {
  test("createTimesheetPeriod classifies an overlap conflict", async () => {
    const { client } = fakeClient({ data: null, error: { message: "timesheet_period_overlap: a period of the same scope already covers part of the range" } });
    await assert.rejects(
      () => createTimesheetPeriod(client, { tenantId: TENANT_ID, orgUnitId: null, code: "P-1", periodStart: "2026-08-01", periodEnd: "2026-08-31", actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof OvertimeTimesheetMutationError && err.code === "timesheet_period_overlap",
    );
  });

  test("lockTimesheetPeriod classifies the unapproved-summaries block", async () => {
    const { client } = fakeClient({ data: null, error: { message: "period_has_unapproved_summaries: 2 employee summary(ies) are not yet approved" } });
    await assert.rejects(
      () => lockTimesheetPeriod(client, { periodId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof OvertimeTimesheetMutationError && err.code === "period_has_unapproved_summaries",
    );
  });

  test("reopenTimesheetPeriod passes the mandatory reason through", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "open" }], error: null });
    await reopenTimesheetPeriod(client, { periodId: ID_1, expectedVersion: 2, reason: "late correction", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.args.p_reason, "late correction");
  });
});

describe("generatePayrollTimeInput / generatePayrollTimeInputsForPeriod", () => {
  test("generatePayrollTimeInput returns the versioned handoff row", async () => {
    const { client } = fakeClient({ data: [{ id: ID_1, version_number: 1, status: "active" }], error: null });
    const row = await generatePayrollTimeInput(client, { periodId: ID_1, employeeId: ID_1, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(row.version_number, 1);
  });

  test("generatePayrollTimeInputsForPeriod returns the per-employee bulk result array", async () => {
    const { client } = fakeClient({ data: [{ employee_id: ID_1, payroll_time_input_id: ID_1, generated: true, skip_reason: null }], error: null });
    const rows = await generatePayrollTimeInputsForPeriod(client, { periodId: ID_1, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.generated, true);
  });
});
