import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getEssHomeSummary, getMssTeamWorkspace, SelfServiceQueryError, type SelfServiceQueryClient } from "./self-service.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const TEAM_MEMBER_1 = "523e4567-e89b-12d3-a456-426614174001";
const TEAM_MEMBER_2 = "523e4567-e89b-12d3-a456-426614174002";
const OUTSIDER = "923e4567-e89b-12d3-a456-426614174009";
const LEAVE_REQUEST_ID = "623e4567-e89b-12d3-a456-426614174001";
const LEAVE_STEP_ID = "723e4567-e89b-12d3-a456-426614174001";

type RpcResponse = { data: unknown; error: { message: string } | null };

function fakeClient(rpcResponses: Record<string, RpcResponse>, approvalRequestRows: Record<string, unknown>[] = []): SelfServiceQueryClient {
  return {
    async rpc(fn: string) {
      return rpcResponses[fn] ?? { data: [], error: null };
    },
    from() {
      return {
        select() {
          return { in: async () => ({ data: approvalRequestRows, error: null }) };
        },
      };
    },
  } as unknown as SelfServiceQueryClient;
}

describe("getEssHomeSummary", () => {
  test("returns a zeroed, safe summary when the caller has no employee profile", async () => {
    const client = fakeClient({ get_my_employee_profile: { data: [], error: null } });
    const summary = await getEssHomeSummary(client, TENANT_ID, ACTOR_ID);
    assert.equal(summary.hasEmployeeProfile, false);
    assert.equal(summary.upcomingScheduleCount, 0);
    assert.equal(summary.latestPayslip, null);
    assert.equal(summary.pendingOvertimeRequestCount, 0);
  });

  test("counts pending overtime/timesheet items and reports the latest payslip", async () => {
    const client = fakeClient({
      get_my_employee_profile: {
        data: [
          {
            master_record_id: TEAM_MEMBER_1, employee_number: "E1", tenant_id: TENANT_ID, user_id: ACTOR_ID, full_name: "A",
            employment_type: "full_time", lifecycle_status: "active", intake_source: "hr_created", work_email: null, work_phone: null,
            personal_email: null, personal_phone: null, national_id_number: null, date_of_birth: null, gender: null,
            personal_address_street: null, personal_address_city: null, personal_address_province: null, personal_address_postal_code: null,
            personal_address_country: null, hire_date: null, probation_end_date: null, employment_end_date: null,
            company_org_unit_id: null, branch_org_unit_id: null, department_org_unit_id: null, position_title: null,
            manager_employee_id: null, record_version: 1, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z",
          },
        ],
        error: null,
      },
      list_my_overtime_requests: {
        data: [
          { id: "a23e4567-e89b-12d3-a456-426614174000", work_date: "2026-08-01", request_type: "planned", requested_start_at: "2026-08-01T10:00:00Z", requested_end_at: "2026-08-01T12:00:00Z", requested_minutes: 120, unpaid_break_minutes: 0, status: "pending_approval", reconciliation_status: "not_reconciled", eligible_minutes: null, eligible_classification: null, approved_minutes: null, payroll_input_status: "pending", record_version: 1 },
          { id: "a23e4567-e89b-12d3-a456-426614174001", work_date: "2026-08-02", request_type: "planned", requested_start_at: "2026-08-02T10:00:00Z", requested_end_at: "2026-08-02T12:00:00Z", requested_minutes: 60, unpaid_break_minutes: 0, status: "approved", reconciliation_status: "not_reconciled", eligible_minutes: null, eligible_classification: null, approved_minutes: 60, payroll_input_status: "approved", record_version: 1 },
        ],
        error: null,
      },
      list_my_payslips: {
        data: [
          { id: "b23e4567-e89b-12d3-a456-426614174000", payroll_run_id: TEAM_MEMBER_1, payroll_period_id: TEAM_MEMBER_1, employee_id: TEAM_MEMBER_1, currency: "IDR", gross_earnings: "1000", total_deductions: "0", total_tax: "0", total_benefit_employer_cost: "0", total_reimbursement: "0", total_loan_repayment: "0", net_pay: "1000", line_items: [], generated_at: "2026-08-01T00:00:00Z" },
        ],
        error: null,
      },
    });
    const summary = await getEssHomeSummary(client, TENANT_ID, ACTOR_ID);
    assert.equal(summary.hasEmployeeProfile, true);
    assert.equal(summary.pendingOvertimeRequestCount, 1);
    assert.deepEqual(summary.latestPayslip, { payslipId: "b23e4567-e89b-12d3-a456-426614174000", currency: "IDR", netPay: "1000" });
  });

  test("wraps an underlying capability's own query error into one SelfServiceQueryError type", async () => {
    const client = fakeClient({ get_my_employee_profile: { data: null, error: { message: "insufficient_authority: x" } } });
    await assert.rejects(() => getEssHomeSummary(client, TENANT_ID, ACTOR_ID), SelfServiceQueryError);
  });

  // Batch 283-285 Tier C fix (spec-compliance lens finding 4): this used to
  // be a hardcoded `0` regardless of the caller's real pending leave
  // requests -- now computed via `list_leave_requests` scoped to the
  // caller's OWN server-resolved employee id (never a client-supplied one).
  test("pendingLeaveRequestCount reflects the caller's own pending leave requests, self-scoped by the server-resolved employee id", async () => {
    const client = fakeClient({
      get_my_employee_profile: {
        data: [
          {
            master_record_id: TEAM_MEMBER_1, employee_number: "E1", tenant_id: TENANT_ID, user_id: ACTOR_ID, full_name: "A",
            employment_type: "full_time", lifecycle_status: "active", intake_source: "hr_created", work_email: null, work_phone: null,
            personal_email: null, personal_phone: null, national_id_number: null, date_of_birth: null, gender: null,
            personal_address_street: null, personal_address_city: null, personal_address_province: null, personal_address_postal_code: null,
            personal_address_country: null, hire_date: null, probation_end_date: null, employment_end_date: null,
            company_org_unit_id: null, branch_org_unit_id: null, department_org_unit_id: null, position_title: null,
            manager_employee_id: null, record_version: 1, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z",
          },
        ],
        error: null,
      },
      list_leave_requests: {
        data: [
          {
            id: LEAVE_REQUEST_ID, employee_id: TEAM_MEMBER_1, employee_name: "A", leave_type_id: TEAM_MEMBER_1, leave_type_code: "AL", category: "leave",
            status: "pending_approval", date_from: "2026-08-10", date_to: "2026-08-10", day_portion: "full_day", total_units: 1,
            payroll_input_status: "pending", record_version: 1, reason_visible: true, reason: null,
          },
        ],
        error: null,
      },
    });
    const summary = await getEssHomeSummary(client, TENANT_ID, ACTOR_ID);
    assert.equal(summary.pendingLeaveRequestCount, 1);
  });
});

describe("getMssTeamWorkspace", () => {
  test("returns the not-a-manager shape when the caller has no direct reports", async () => {
    const client = fakeClient({ list_my_team_employees: { data: [], error: null } });
    const workspace = await getMssTeamWorkspace(client, TENANT_ID, ACTOR_ID);
    assert.equal(workspace.isManager, false);
    assert.deepEqual(workspace.team, []);
    assert.deepEqual(workspace.approvalQueue, []);
  });

  test("defense in depth: excludes a pending item outside the caller's own effective team, even though the underlying RPC returned it", async () => {
    const client = fakeClient({
      list_my_team_employees: {
        data: [{ master_record_id: TEAM_MEMBER_1, employee_number: "E1", full_name: "Team Member", employment_type: "full_time", lifecycle_status: "active", position_title: null, hire_date: null }],
        error: null,
      },
      list_overtime_requests: {
        data: [
          { id: "a23e4567-e89b-12d3-a456-426614174010", employee_id: TEAM_MEMBER_1, employee_number: "E1", employee_full_name: "Team Member", work_date: "2026-08-01", request_type: "planned", status: "pending_approval", requested_minutes: 60, reconciliation_status: "not_reconciled", eligible_minutes: null, eligible_classification: null, approved_minutes: null, payroll_input_status: "pending", record_version: 1 },
          { id: "a23e4567-e89b-12d3-a456-426614174011", employee_id: OUTSIDER, employee_number: "E9", employee_full_name: "Outsider", work_date: "2026-08-01", request_type: "planned", status: "pending_approval", requested_minutes: 60, reconciliation_status: "not_reconciled", eligible_minutes: null, eligible_classification: null, approved_minutes: null, payroll_input_status: "pending", record_version: 1 },
        ],
        error: null,
      },
      list_pending_approval_steps_for_actor: {
        data: [
          {
            id: LEAVE_STEP_ID, request_id: "c23e4567-e89b-12d3-a456-426614174000", step_order: 1, approver_type: "role", role_id: TEAM_MEMBER_1,
            specific_user_id: null, required_approvals: 1, approvals_count: 0, status: "pending", created_at: "2026-08-01T00:00:00Z", updated_at: "2026-08-01T00:00:00Z",
          },
        ],
        error: null,
      },
      get_leave_request_detail: {
        data: [
          {
            id: LEAVE_REQUEST_ID, employee_id: OUTSIDER, leave_type_id: TEAM_MEMBER_1, status: "pending_approval", date_from: "2026-08-01", date_to: "2026-08-01",
            day_portion: "full_day", total_units: 1, reason: null, destination: null, evidence_file_id: null, schedule_snapshot: [], payroll_input_status: "pending",
            decided_reason: null, cancel_reason: null, record_version: 1,
          },
        ],
        error: null,
      },
    }, [{ id: "c23e4567-e89b-12d3-a456-426614174000", entity_type: "leave_request", entity_id: LEAVE_REQUEST_ID }]);

    const workspace = await getMssTeamWorkspace(client, TENANT_ID, ACTOR_ID);
    assert.equal(workspace.isManager, true);
    // the overtime item for OUTSIDER must never appear even though list_overtime_requests returned it
    assert.equal(workspace.approvalQueue.some((i) => i.kind === "overtime" && i.employeeId === OUTSIDER), false);
    assert.equal(workspace.approvalQueue.some((i) => i.kind === "overtime" && i.employeeId === TEAM_MEMBER_1), true);
    // the leave approval-inbox item belongs to OUTSIDER (a delegated-approval case outside the direct team) -- must be excluded too
    assert.equal(workspace.approvalQueue.some((i) => i.kind === "leave"), false);
  });

  test("includes a leave approval-inbox item that genuinely belongs to a direct report", async () => {
    const client = fakeClient({
      list_my_team_employees: {
        data: [{ master_record_id: TEAM_MEMBER_2, employee_number: "E2", full_name: "Direct Report", employment_type: "full_time", lifecycle_status: "active", position_title: null, hire_date: null }],
        error: null,
      },
      list_pending_approval_steps_for_actor: {
        data: [
          {
            id: LEAVE_STEP_ID, request_id: "c23e4567-e89b-12d3-a456-426614174001", step_order: 1, approver_type: "role", role_id: TEAM_MEMBER_2,
            specific_user_id: null, required_approvals: 1, approvals_count: 0, status: "pending", created_at: "2026-08-01T00:00:00Z", updated_at: "2026-08-01T00:00:00Z",
          },
        ],
        error: null,
      },
      get_leave_request_detail: {
        data: [
          {
            id: LEAVE_REQUEST_ID, employee_id: TEAM_MEMBER_2, leave_type_id: TEAM_MEMBER_2, status: "pending_approval", date_from: "2026-08-05", date_to: "2026-08-05",
            day_portion: "full_day", total_units: 1, reason: null, destination: null, evidence_file_id: null, schedule_snapshot: [], payroll_input_status: "pending",
            decided_reason: null, cancel_reason: null, record_version: 4,
          },
        ],
        error: null,
      },
    }, [{ id: "c23e4567-e89b-12d3-a456-426614174001", entity_type: "leave_request", entity_id: LEAVE_REQUEST_ID }]);

    const workspace = await getMssTeamWorkspace(client, TENANT_ID, ACTOR_ID);
    const leaveItem = workspace.approvalQueue.find((i) => i.kind === "leave");
    assert.ok(leaveItem);
    assert.equal(leaveItem?.employeeId, TEAM_MEMBER_2);
    if (leaveItem?.kind === "leave") {
      assert.equal(leaveItem.requestStepId, LEAVE_STEP_ID);
      assert.equal(leaveItem.recordVersion, 4);
    }
    // Batch 283-285 Tier C fix regression coverage: neither bound was hit here.
    assert.equal(workspace.teamTruncated, false);
    assert.equal(workspace.approvalQueueTruncated, false);
  });

  // Batch 283-285 Tier C fix (spec-compliance lens finding 3): a manager with
  // more direct reports than the bounded page size must be told the roster
  // was truncated, not left to discover it silently.
  test("teamTruncated is true when the caller has more direct reports than the bounded page size", async () => {
    const team = Array.from({ length: 51 }, (_, i) => ({
      master_record_id: `623e4567-e89b-12d3-a456-42661417${String(4100 + i)}`,
      employee_number: `E${i}`, full_name: `Member ${i}`, employment_type: "full_time", lifecycle_status: "active", position_title: null, hire_date: null,
    }));
    const client = fakeClient({ list_my_team_employees: { data: team, error: null } });
    const workspace = await getMssTeamWorkspace(client, TENANT_ID, ACTOR_ID);
    assert.equal(workspace.isManager, true);
    assert.equal(workspace.team.length, 50);
    assert.equal(workspace.teamTruncated, true);
  });

  // Batch 283-285 Tier C fix (spec-compliance lens finding 3): more
  // team-scoped pending overtime items than the queue bound must set the
  // truncation flag, even though the rendered queue itself stays bounded.
  test("approvalQueueTruncated is true when a team-scoped queue category exceeds the per-category bound", async () => {
    const overtimeRows = Array.from({ length: 21 }, (_, i) => ({
      id: `a23e4567-e89b-12d3-a456-4266141750${String(i).padStart(2, "0")}`, employee_id: TEAM_MEMBER_1, employee_number: "E1", employee_full_name: "Team Member",
      work_date: "2026-08-01", request_type: "planned", status: "pending_approval", requested_minutes: 60, reconciliation_status: "not_reconciled",
      eligible_minutes: null, eligible_classification: null, approved_minutes: null, payroll_input_status: "pending", record_version: 1,
    }));
    const client = fakeClient({
      list_my_team_employees: {
        data: [{ master_record_id: TEAM_MEMBER_1, employee_number: "E1", full_name: "Team Member", employment_type: "full_time", lifecycle_status: "active", position_title: null, hire_date: null }],
        error: null,
      },
      list_overtime_requests: { data: overtimeRows, error: null },
    });
    const workspace = await getMssTeamWorkspace(client, TENANT_ID, ACTOR_ID);
    assert.equal(workspace.approvalQueue.filter((i) => i.kind === "overtime").length, 20);
    assert.equal(workspace.approvalQueueTruncated, true);
  });
});
