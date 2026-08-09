import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listPositionGrades,
  listPositions,
  getPosition,
  exportPositions,
  previewEmployeePositionAssignmentImpact,
  getEmployeePositionAssignmentHistory,
  getMyEmployeePositionAssignmentHistory,
  getEmployeeCurrentAssignment,
  getEmployeeManagerChain,
  getOrgPositionTree,
  PositionQueryError,
  type PositionQueryClient,
} from "./position.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: PositionQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PositionQueryClient;
  return { client, calls };
}

describe("listPositionGrades / listPositions", () => {
  test("listPositionGrades maps default args", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPositionGrades(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_status_filter: null });
  });

  test("listPositions threads through filter/search/pagination and never fetches an unbounded page", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPositions(client, TENANT_ID, ACTOR_ID, { orgUnitId: ID_1, statusFilter: "active", search: "supervisor", limit: 10, afterCode: "POS-001" });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_org_unit_id: ID_1,
      p_status_filter: "active",
      p_search: "supervisor",
      p_limit: 10,
      p_after_code: "POS-001",
    });
  });

  test("throws PositionQueryError on an RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: nope" } });
    await assert.rejects(() => listPositions(client, TENANT_ID, ACTOR_ID), PositionQueryError);
  });
});

describe("getPosition / exportPositions", () => {
  test("getPosition parses the first row and throws when the RPC returns nothing", async () => {
    const { client } = fakeClient({ data: [], error: null });
    await assert.rejects(() => getPosition(client, ID_1, ACTOR_ID), PositionQueryError);
  });

  test("exportPositions returns the scoped projection rows", async () => {
    const { client } = fakeClient({ data: [{ code: "POS-1", title: "Supervisor", org_unit_id: ID_1, grade_code: null, capacity: 1, status: "active" }], error: null });
    const result = await exportPositions(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.code, "POS-1");
  });
});

describe("previewEmployeePositionAssignmentImpact", () => {
  test("maps input and parses the impact preview row", async () => {
    const { client, calls } = fakeClient({
      data: [
        {
          current_position_id: null,
          current_position_title: null,
          current_manager_employee_id: null,
          proposed_position_title: "Supervisor",
          proposed_grade_id: null,
          proposed_company_org_unit_id: null,
          proposed_branch_org_unit_id: null,
          proposed_department_org_unit_id: null,
          position_capacity: 1,
          position_current_headcount: 0,
          position_capacity_remaining: 1,
          would_create_manager_cycle: false,
          target_org_unit_active: true,
          direct_report_count: 0,
          pending_change_request_count: 0,
          pending_duplicate_candidate_count: 0,
          downstream_disclosure: "not yet integrated",
        },
      ],
      error: null,
    });
    const result = await previewEmployeePositionAssignmentImpact(client, { masterRecordId: ID_1, positionId: ID_1, managerEmployeeId: null, effectiveStartDate: "2026-08-09", actorAuthUserId: ACTOR_ID, actorLabel: ACTOR_ID });
    assert.equal(calls[0]?.fn, "preview_employee_position_assignment_impact");
    assert.equal(result.proposedPositionTitle, "Supervisor");
  });
});

describe("history/current-assignment/hierarchy reads", () => {
  test("getEmployeePositionAssignmentHistory maps args", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await getEmployeePositionAssignmentHistory(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_employee_position_assignment_history");
  });

  test("getMyEmployeePositionAssignmentHistory returns an empty array (never throws) with zero rows", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getMyEmployeePositionAssignmentHistory(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });

  test("getEmployeeCurrentAssignment defaults p_as_of to null (server-side current_date)", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await getEmployeeCurrentAssignment(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.args.p_as_of, null);
  });

  test("getEmployeeManagerChain parses depth-ordered rows", async () => {
    const { client } = fakeClient({ data: [{ depth: 1, master_record_id: ID_1, employee_number: "EMP-2026-000001", full_name: "Manager", position_title: null }], error: null });
    const result = await getEmployeeManagerChain(client, ID_1, ACTOR_ID);
    assert.equal(result[0]?.depth, 1);
  });

  test("getOrgPositionTree threads through an optional root scope", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await getOrgPositionTree(client, TENANT_ID, ACTOR_ID, ID_1);
    assert.equal(calls[0]?.args.p_root_org_unit_id, ID_1);
  });
});
