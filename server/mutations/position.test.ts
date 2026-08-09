import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createPositionGrade,
  updatePositionGrade,
  setPositionGradeStatus,
  createPosition,
  updatePosition,
  setPositionStatus,
  proposeEmployeePositionAssignment,
  decideEmployeePositionAssignment,
  cancelEmployeePositionAssignment,
  activateDueEmployeePositionAssignments,
  PositionMutationError,
  type PositionMutationRpcClient,
} from "./position.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): { client: PositionMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PositionMutationRpcClient;
  return { client, calls };
}

const GRADE_ROW = { id: ID_1, tenant_id: TENANT_ID, code: "GR-1", name: "Staff Grade", rank: 1, status: "active", description: null, record_version: 1, created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z" };
const POSITION_ROW = { id: ID_1, tenant_id: TENANT_ID, code: "POS-1", title: "Supervisor", org_unit_id: ID_2, grade_id: null, capacity: 1, status: "active", description: null, record_version: 1, created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z" };
const ASSIGNMENT_ROW = {
  id: ID_1,
  tenant_id: TENANT_ID,
  master_record_id: ID_2,
  position_id: ID_1,
  grade_id: null,
  manager_employee_id: null,
  assignment_type: "primary",
  allocation_pct: "100.00",
  effective_start_date: "2026-08-09",
  effective_end_date: null,
  status: "pending_approval",
  change_reason: "hire",
  reason_note: null,
  previous_assignment_id: null,
  decided_by: null,
  decided_at: null,
  decided_reason: null,
  record_version: 1,
  created_at: "2026-08-09T00:00:00.000Z",
  updated_at: "2026-08-09T00:00:00.000Z",
};

describe("position grade CRUD", () => {
  test("createPositionGrade maps mapped snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: [GRADE_ROW], error: null });
    await createPositionGrade(client, { tenantId: TENANT_ID, code: "GR-1", name: "Staff Grade", rank: 1, description: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.fn, "create_position_grade");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_code: "GR-1", p_name: "Staff Grade", p_rank: 1, p_description: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff" });
  });

  test("updatePositionGrade / setPositionGradeStatus round-trip", async () => {
    const { client } = fakeRpcClient({ data: [GRADE_ROW], error: null });
    const updated = await updatePositionGrade(client, { id: ID_1, expectedVersion: 1, name: "Staff Grade v2", rank: 2, description: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(updated.code, "GR-1");
    const statused = await setPositionGradeStatus(client, { id: ID_1, expectedVersion: 1, newStatus: "inactive", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(statused.status, "active"); // response is the fixed fake row, not re-derived
  });

  test("classifies a known error code from the RPC error message prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "position_grade_code_conflict: code GR-1 already exists" } });
    await assert.rejects(
      () => createPositionGrade(client, { tenantId: TENANT_ID, code: "GR-1", name: "Staff Grade", rank: null, description: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof PositionMutationError && error.code === "position_grade_code_conflict",
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unmapped_db_error: oops" } });
    await assert.rejects(
      () => createPositionGrade(client, { tenantId: TENANT_ID, code: "GR-1", name: "Staff Grade", rank: null, description: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof PositionMutationError && error.code === "mutation_failed",
    );
  });
});

describe("position CRUD", () => {
  test("createPosition maps mapped snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: [POSITION_ROW], error: null });
    await createPosition(client, { tenantId: TENANT_ID, code: "POS-1", title: "Supervisor", orgUnitId: ID_2, gradeId: null, capacity: 1, description: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.fn, "create_position");
    assert.equal(calls[0]?.args.p_capacity, 1);
  });

  test("updatePosition / setPositionStatus round-trip", async () => {
    const { client } = fakeRpcClient({ data: [POSITION_ROW], error: null });
    const updated = await updatePosition(client, { id: ID_1, expectedVersion: 1, title: "Supervisor v2", orgUnitId: ID_2, gradeId: null, capacity: 2, description: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(updated.code, "POS-1");
    const statused = await setPositionStatus(client, { id: ID_1, expectedVersion: 1, newStatus: "inactive", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(statused.id, ID_1);
  });

  test("throws invalid_response when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () => createPosition(client, { tenantId: TENANT_ID, code: "POS-1", title: "Supervisor", orgUnitId: ID_2, gradeId: null, capacity: 1, description: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof PositionMutationError && error.code === "invalid_response",
    );
  });
});

describe("employee <-> position/grade/manager assignment workflow", () => {
  test("proposeEmployeePositionAssignment maps every field, including nullable manager/grade", async () => {
    const { client, calls } = fakeRpcClient({ data: [ASSIGNMENT_ROW], error: null });
    await proposeEmployeePositionAssignment(client, {
      masterRecordId: ID_2,
      expectedVersion: 1,
      positionId: ID_1,
      gradeId: null,
      managerEmployeeId: null,
      assignmentType: "primary",
      allocationPct: 100,
      effectiveStartDate: "2026-08-09",
      effectiveEndDate: null,
      changeReason: "hire",
      reasonNote: "initial hire",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "propose_employee_position_assignment");
    assert.equal(calls[0]?.args.p_change_reason, "hire");
    assert.equal(calls[0]?.args.p_reason_note, "initial hire");
  });

  test("decideEmployeePositionAssignment requires a non-empty reason at the schema layer", async () => {
    await assert.rejects(() =>
      decideEmployeePositionAssignment(fakeRpcClient({ data: [ASSIGNMENT_ROW], error: null }).client, {
        assignmentId: ID_1,
        expectedVersion: 1,
        decision: "approve",
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "approver",
      }),
    );
  });

  test("decideEmployeePositionAssignment maps a real approval", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ASSIGNMENT_ROW, status: "active" }], error: null });
    const result = await decideEmployeePositionAssignment(client, { assignmentId: ID_1, expectedVersion: 1, decision: "approve", reason: "approved by HR", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.fn, "decide_employee_position_assignment");
    assert.equal(result.status, "active");
  });

  test("cancelEmployeePositionAssignment maps args and classifies assignment_not_cancellable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "assignment_not_cancellable: assignment is already in effect" } });
    await assert.rejects(
      () => cancelEmployeePositionAssignment(client, { assignmentId: ID_1, expectedVersion: 1, reason: "changed my mind", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof PositionMutationError && error.code === "assignment_not_cancellable",
    );
  });

  test("activateDueEmployeePositionAssignments returns the swept count as a number", async () => {
    const { client, calls } = fakeRpcClient({ data: 3, error: null });
    const result = await activateDueEmployeePositionAssignments(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.fn, "activate_due_employee_position_assignments");
    assert.equal(result, 3);
  });

  test("activateDueEmployeePositionAssignments rejects a non-numeric RPC response", async () => {
    const { client } = fakeRpcClient({ data: "not-a-number", error: null });
    await assert.rejects(
      () => activateDueEmployeePositionAssignments(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "approver" }),
      (error: unknown) => error instanceof PositionMutationError && error.code === "invalid_response",
    );
  });
});
