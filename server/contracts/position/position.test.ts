import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parsePositionGrade,
  parsePosition,
  parsePositionListRow,
  parsePositionDetail,
  parsePositionExportRow,
  parseEmployeePositionAssignment,
  parseAssignmentImpactPreview,
  parseManagerChainRow,
  parseOrgPositionTreeRow,
  CreatePositionGradeInputSchema,
  ProposeEmployeePositionAssignmentInputSchema,
} from "./position.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ID_3 = "423e4567-e89b-12d3-a456-426614174000";

describe("parsePositionGrade", () => {
  test("maps snake_case row to camelCase", () => {
    const grade = parsePositionGrade({
      id: ID_1,
      tenant_id: TENANT_ID,
      code: "GR-1",
      name: "Staff Grade",
      rank: 1,
      status: "active",
      description: null,
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(grade.code, "GR-1");
    assert.equal(grade.rank, 1);
    assert.equal(grade.status, "active");
  });
});

describe("parsePosition / parsePositionListRow / parsePositionDetail", () => {
  const base = {
    id: ID_1,
    tenant_id: TENANT_ID,
    code: "POS-1",
    title: "Warehouse Supervisor",
    org_unit_id: ID_2,
    grade_id: ID_3,
    capacity: 2,
    status: "active",
    description: null,
    record_version: 1,
    created_at: "2026-08-09T00:00:00.000Z",
    updated_at: "2026-08-09T00:00:00.000Z",
  };

  test("parsePosition maps the full row", () => {
    const position = parsePosition(base);
    assert.equal(position.title, "Warehouse Supervisor");
    assert.equal(position.capacity, 2);
  });

  test("parsePositionListRow includes computed current_headcount", () => {
    const row = parsePositionListRow({ ...base, current_headcount: 1 });
    assert.equal(row.currentHeadcount, 1);
  });

  test("parsePositionDetail includes computed capacity_remaining", () => {
    const row = parsePositionDetail({ ...base, current_headcount: 1, capacity_remaining: 1 });
    assert.equal(row.capacityRemaining, 1);
  });
});

describe("parsePositionExportRow", () => {
  test("carries no compensation column at all", () => {
    const row = parsePositionExportRow({ code: "POS-1", title: "Warehouse Supervisor", org_unit_id: ID_2, grade_code: "GR-1", capacity: 2, status: "active" });
    assert.equal(Object.keys(row).includes("salary" as never), false);
    assert.equal(row.gradeCode, "GR-1");
  });
});

describe("parseEmployeePositionAssignment", () => {
  test("maps effective-dated assignment fields", () => {
    const assignment = parseEmployeePositionAssignment({
      id: ID_1,
      tenant_id: TENANT_ID,
      master_record_id: ID_2,
      position_id: ID_3,
      grade_id: null,
      manager_employee_id: null,
      assignment_type: "primary",
      allocation_pct: "100.00",
      effective_start_date: "2026-08-09",
      effective_end_date: null,
      status: "active",
      change_reason: "hire",
      reason_note: null,
      previous_assignment_id: null,
      decided_by: "approver",
      decided_at: "2026-08-09T00:00:00.000Z",
      decided_reason: "approved",
      record_version: 1,
      created_at: "2026-08-09T00:00:00.000Z",
      updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(assignment.assignmentType, "primary");
    assert.equal(assignment.allocationPct, 100);
    assert.equal(assignment.effectiveEndDate, null);
  });
});

describe("parseAssignmentImpactPreview", () => {
  test("always carries a non-empty downstreamDisclosure and real signal fields", () => {
    const preview = parseAssignmentImpactPreview({
      current_position_id: null,
      current_position_title: null,
      current_manager_employee_id: null,
      proposed_position_title: "Warehouse Supervisor",
      proposed_grade_id: null,
      proposed_company_org_unit_id: null,
      proposed_branch_org_unit_id: null,
      proposed_department_org_unit_id: ID_2,
      position_capacity: 2,
      position_current_headcount: 1,
      position_capacity_remaining: 1,
      would_create_manager_cycle: false,
      target_org_unit_active: true,
      direct_report_count: 0,
      pending_change_request_count: 0,
      pending_duplicate_candidate_count: 0,
      downstream_disclosure: "Approval-queue org-scope, Payroll input recalculation, and Ticketing queue routing are not yet integrated.",
    });
    assert.equal(preview.wouldCreateManagerCycle, false);
    assert.ok(preview.downstreamDisclosure.length > 0);
  });
});

describe("parseManagerChainRow / parseOrgPositionTreeRow", () => {
  test("parseManagerChainRow maps depth-ordered chain rows", () => {
    const row = parseManagerChainRow({ depth: 1, master_record_id: ID_1, employee_number: "EMP-2026-000001", full_name: "Manager Person", position_title: "Manager" });
    assert.equal(row.depth, 1);
  });

  test("parseOrgPositionTreeRow tolerates a null position (LEFT JOIN, no position defined yet)", () => {
    const row = parseOrgPositionTreeRow({
      org_unit_id: ID_1,
      org_unit_code: "DEPT-1",
      org_unit_name: "Ops Dept",
      unit_type: "department",
      depth: 2,
      position_id: null,
      position_code: null,
      position_title: null,
      capacity: null,
      current_headcount: null,
    });
    assert.equal(row.positionId, null);
    assert.equal(row.unitType, "department");
  });
});

describe("input schemas", () => {
  test("CreatePositionGradeInputSchema requires a non-empty code/name", () => {
    assert.throws(() => CreatePositionGradeInputSchema.parse({ tenantId: TENANT_ID, code: "", name: "Grade", rank: null, description: null, actorAuthUserId: ID_1, actorLabel: "staff" }));
  });

  test("ProposeEmployeePositionAssignmentInputSchema requires a legal assignment_type/change_reason enum value", () => {
    assert.throws(() =>
      ProposeEmployeePositionAssignmentInputSchema.parse({
        masterRecordId: ID_1,
        expectedVersion: 1,
        positionId: ID_2,
        gradeId: null,
        managerEmployeeId: null,
        assignmentType: "not-a-real-type",
        allocationPct: 100,
        effectiveStartDate: "2026-08-09",
        effectiveEndDate: null,
        changeReason: "hire",
        reasonNote: null,
        actorAuthUserId: ID_1,
        actorLabel: "staff",
      }),
    );
  });

  test("ProposeEmployeePositionAssignmentInputSchema accepts a legal payload", () => {
    const parsed = ProposeEmployeePositionAssignmentInputSchema.parse({
      masterRecordId: ID_1,
      expectedVersion: 1,
      positionId: ID_2,
      gradeId: null,
      managerEmployeeId: null,
      assignmentType: "primary",
      allocationPct: 100,
      effectiveStartDate: "2026-08-09",
      effectiveEndDate: null,
      changeReason: "hire",
      reasonNote: null,
      actorAuthUserId: ID_1,
      actorLabel: "staff",
    });
    assert.equal(parsed.assignmentType, "primary");
  });
});
