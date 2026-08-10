import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createShiftTemplate,
  createShiftTemplateVersion,
  publishShiftTemplateVersion,
  createRosterCycle,
  setRosterCycleSlot,
  publishRosterCycle,
  assignEmployeeSchedule,
  cancelScheduleAssignment,
  publishScheduleAssignments,
  generateRosterScheduleAssignments,
  requestScheduleSwap,
  decideScheduleSwapRequest,
  ShiftRosterMutationError,
  type ShiftRosterMutationRpcClient,
} from "./shift-roster.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ID_3 = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: ShiftRosterMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ShiftRosterMutationRpcClient;
  return { client, calls };
}

describe("createShiftTemplate / createShiftTemplateVersion / publishShiftTemplateVersion", () => {
  test("createShiftTemplate maps input to snake_case RPC args", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, code: "MORNING" }], error: null });
    await createShiftTemplate(client, { tenantId: TENANT_ID, orgUnitId: null, code: "MORNING", name: "Morning", actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.fn, "create_shift_template");
    assert.equal(calls[0]?.args.p_code, "MORNING");
  });

  test("createShiftTemplateVersion serializes the segment list to snake_case", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1 }], error: null });
    await createShiftTemplateVersion(client, {
      shiftTemplateId: ID_1, timezone: "Asia/Jakarta", dayBoundaryLocalTime: null, shiftType: "fixed",
      graceLateMinutes: 10, graceEarlyMinutes: 10, effectiveFrom: "2026-08-10",
      segments: [{ segmentType: "work", startTime: "08:00:00", endTime: "17:00:00" }],
      actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    const segs = calls[0]?.args.p_segments as Record<string, unknown>[];
    assert.equal(segs[0]?.segment_type, "work");
    assert.equal(segs[0]?.start_time, "08:00:00");
  });

  test("publishShiftTemplateVersion classifies stale_version", async () => {
    const { client } = fakeClient({ data: null, error: { message: "stale_version: expected 1 but found 2" } });
    await assert.rejects(
      () => publishShiftTemplateVersion(client, { versionId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof ShiftRosterMutationError && err.code === "stale_version",
    );
  });
});

describe("createRosterCycle / setRosterCycleSlot / publishRosterCycle", () => {
  test("setRosterCycleSlot allows a null shift_template_id (day off)", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, day_offset: 3, shift_template_id: null }], error: null });
    await setRosterCycleSlot(client, { rosterCycleId: ID_1, dayOffset: 3, shiftTemplateId: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_shift_template_id, null);
  });

  test("publishRosterCycle classifies incomplete_roster_cycle", async () => {
    const { client } = fakeClient({ data: null, error: { message: "incomplete_roster_cycle: cycle has 3 of 6 day-offsets filled" } });
    await assert.rejects(
      () => publishRosterCycle(client, { rosterCycleId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof ShiftRosterMutationError && err.code === "incomplete_roster_cycle",
    );
  });

  test("createRosterCycle passes cycle_length_days through", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1 }], error: null });
    await createRosterCycle(client, { tenantId: TENANT_ID, orgUnitId: null, name: "4-on 2-off", cycleLengthDays: 6, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_cycle_length_days, 6);
  });
});

describe("assignEmployeeSchedule / cancelScheduleAssignment / publishScheduleAssignments", () => {
  test("assignEmployeeSchedule classifies employee_not_active", async () => {
    const { client } = fakeClient({ data: null, error: { message: "employee_not_active: employee is terminated" } });
    await assert.rejects(
      () => assignEmployeeSchedule(client, { tenantId: TENANT_ID, employeeId: ID_1, shiftTemplateVersionId: ID_2, workDate: "2026-08-10", source: "manual", idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof ShiftRosterMutationError && err.code === "employee_not_active",
    );
  });

  test("cancelScheduleAssignment requires a non-empty reason at the schema layer", async () => {
    // Zod parse happens inside the (async) wrapper before any RPC call, so the
    // rejection surfaces as a rejected Promise, never a synchronous throw.
    const { client } = fakeClient({ data: [{}], error: null });
    await assert.rejects(() => cancelScheduleAssignment(client, { assignmentId: ID_1, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "hr" }));
  });

  test("publishScheduleAssignments returns the per-row result array unparsed-error", async () => {
    const { client } = fakeClient({ data: [{ assignment_id: ID_1, published: true, skip_reason: null }, { assignment_id: ID_2, published: false, skip_reason: "employee_not_active" }], error: null });
    const rows = await publishScheduleAssignments(client, { tenantId: TENANT_ID, fromDate: "2026-08-01", toDate: "2026-08-31", orgUnitId: null, employeeId: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(rows.length, 2);
    assert.equal(rows[1]?.skipReason, "employee_not_active");
  });
});

describe("generateRosterScheduleAssignments", () => {
  test("passes the employee_ids array through and parses the summary result", async () => {
    const { client, calls } = fakeClient({ data: [{ created_count: 4, superseded_count: 0, skipped_count: 1, job_id: ID_1 }], error: null });
    const result = await generateRosterScheduleAssignments(client, {
      tenantId: TENANT_ID, rosterCycleId: ID_1, employeeIds: [ID_2, ID_3], fromDate: "2026-08-01", toDate: "2026-08-31", actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    assert.deepEqual(calls[0]?.args.p_employee_ids, [ID_2, ID_3]);
    assert.equal(result.createdCount, 4);
    assert.equal(result.jobId, ID_1);
  });

  test("requires at least one employee_id at the schema layer", async () => {
    const { client } = fakeClient({ data: [{}], error: null });
    await assert.rejects(() =>
      generateRosterScheduleAssignments(client, { tenantId: TENANT_ID, rosterCycleId: ID_1, employeeIds: [], fromDate: "2026-08-01", toDate: "2026-08-31", actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
    );
  });
});

describe("requestScheduleSwap / decideScheduleSwapRequest", () => {
  test("requestScheduleSwap classifies invalid_swap_target", async () => {
    const { client } = fakeClient({ data: null, error: { message: "invalid_swap_target: an employee may not swap a shift with themself" } });
    await assert.rejects(
      () => requestScheduleSwap(client, { assignmentId: ID_1, targetEmployeeId: ID_2, targetAssignmentId: ID_3, reason: "cover for me", idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp" }),
      (err: unknown) => err instanceof ShiftRosterMutationError && err.code === "invalid_swap_target",
    );
  });

  test("decideScheduleSwapRequest classifies self_approval_not_permitted", async () => {
    const { client } = fakeClient({ data: null, error: { message: "self_approval_not_permitted: an actor may not decide a swap request they are a party to" } });
    await assert.rejects(
      () => decideScheduleSwapRequest(client, { requestId: ID_1, expectedVersion: 1, decision: "approve", decidedReason: "ok", actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof ShiftRosterMutationError && err.code === "self_approval_not_permitted",
    );
  });
});
