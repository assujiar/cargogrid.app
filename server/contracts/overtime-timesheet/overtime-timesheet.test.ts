import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseOvertimeRequestRow,
  parseOvertimeRequestAdminRow,
  parseOvertimeRequestDetail,
  parseTimesheetEntryRow,
  parseTimesheetEntryAdminRow,
  parseTimesheetEntryDetail,
  parseTimesheetPeriodRow,
  parseTimesheetPeriodSummaryRow,
  parseTimesheetPeriodSummaryDetail,
  parseOvertimePolicyRow,
  parseOvertimePolicyVersion,
  parsePayrollTimeInputRow,
  parsePayrollTimeInputDetail,
  CreateOvertimeRequestInputSchema,
  DecideOvertimeRequestInputSchema,
  CreateTimesheetEntryInputSchema,
  CreateOvertimePolicyVersionInputSchema,
} from "./overtime-timesheet.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACTOR = "323e4567-e89b-12d3-a456-426614174000";

describe("parseOvertimeRequestRow / parseOvertimeRequestAdminRow / parseOvertimeRequestDetail", () => {
  test("self row maps requested/eligible/approved as distinct fields (never collapsed)", () => {
    const r = parseOvertimeRequestRow({
      id: ID_1, work_date: "2026-08-10", request_type: "planned", requested_start_at: "2026-08-10T17:00:00Z",
      requested_end_at: "2026-08-10T19:00:00Z", requested_minutes: 120, unpaid_break_minutes: 0, status: "approved",
      reconciliation_status: "matched", eligible_minutes: 120, eligible_classification: "weekday", approved_minutes: 90,
      payroll_input_status: "pending", record_version: 3,
    });
    assert.equal(r.requestedMinutes, 120);
    assert.equal(r.eligibleMinutes, 120);
    assert.equal(r.approvedMinutes, 90);
    assert.notEqual(r.approvedMinutes, r.eligibleMinutes);
  });

  test("admin row maps employee identity columns", () => {
    const r = parseOvertimeRequestAdminRow({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe",
      work_date: "2026-08-10", request_type: "emergency_after_the_fact", status: "pending_approval",
      requested_minutes: 60, reconciliation_status: "not_reconciled", eligible_minutes: null, eligible_classification: null,
      approved_minutes: null, payroll_input_status: "pending", record_version: 1,
    });
    assert.equal(r.employeeNumber, "EMP-2026-000001");
    assert.equal(r.eligibleMinutes, null);
  });

  test("detail row masks nothing itself -- the RPC already decided what to project, reason may be null", () => {
    const d = parseOvertimeRequestDetail({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe", work_date: "2026-08-10",
      request_type: "planned", requested_start_at: "2026-08-10T17:00:00Z", requested_end_at: "2026-08-10T19:00:00Z",
      requested_minutes: 120, unpaid_break_minutes: 0, reason: null, schedule_assignment_id: null, job_order_id: null,
      job_number: null, shipment_order_id: null, shipment_number: null, status: "approved", reconciliation_status: "matched",
      reconciled_actual_minutes: 120, eligible_minutes: 120, eligible_classification: "weekday", approved_minutes: 120,
      decided_reason: null, cancel_reason: null, payroll_input_status: "approved", record_version: 4,
    });
    assert.equal(d.reason, null);
    assert.equal(d.payrollInputStatus, "approved");
  });
});

describe("parseTimesheetEntryRow / parseTimesheetEntryAdminRow / parseTimesheetEntryDetail", () => {
  test("self row maps job/shipment reference metadata only, never a full Operations row", () => {
    const r = parseTimesheetEntryRow({
      id: ID_1, work_date: "2026-08-10", entry_minutes: 480, unpaid_break_minutes: 30, job_order_id: ID_1,
      job_number: "JO-2026-0001", shipment_order_id: null, shipment_number: null, status: "approved",
      reconciliation_status: "matched", eligible_minutes: 450, approved_minutes: 450, payroll_input_status: "pending",
      record_version: 2,
    });
    assert.equal(r.jobNumber, "JO-2026-0001");
    assert.equal(r.eligibleMinutes, 450);
  });

  test("admin row extends the self row with employee identity", () => {
    const r = parseTimesheetEntryAdminRow({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe",
      work_date: "2026-08-10", entry_minutes: 300, unpaid_break_minutes: 15, job_order_id: null, job_number: null,
      shipment_order_id: null, shipment_number: null, status: "draft", reconciliation_status: "not_reconciled",
      eligible_minutes: null, approved_minutes: null, payroll_input_status: "pending", record_version: 1,
    });
    assert.equal(r.employeeFullName, "Jane Doe");
  });

  test("detail row carries multi-job allocation reference fields distinctly", () => {
    const d = parseTimesheetEntryDetail({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe", work_date: "2026-08-10",
      entry_minutes: 180, unpaid_break_minutes: 15, job_order_id: ID_1, job_number: "JO-1", shipment_order_id: null,
      shipment_number: null, notes: "afternoon job", status: "approved", source: "manual", reconciliation_status: "mismatch",
      reconciled_day_actual_minutes: 500, eligible_minutes: 165, approved_minutes: 165, decided_reason: "ok",
      cancel_reason: null, payroll_input_status: "pending", record_version: 3,
    });
    assert.equal(d.source, "manual");
    assert.equal(d.reconciliationStatus, "mismatch");
  });
});

describe("parseTimesheetPeriodRow / parseTimesheetPeriodSummaryRow / parseTimesheetPeriodSummaryDetail", () => {
  test("period row maps lock status", () => {
    const p = parseTimesheetPeriodRow({ id: ID_1, org_unit_id: null, code: "P-2026-08", period_start: "2026-08-01", period_end: "2026-08-31", status: "locked", record_version: 2 });
    assert.equal(p.status, "locked");
  });

  test("summary row splits overtime by classification, never one combined figure", () => {
    const s = parseTimesheetPeriodSummaryRow({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe",
      timesheet_period_id: ID_1, status: "approved", total_regular_minutes: 9600, total_overtime_weekday_minutes: 120,
      total_overtime_weekend_minutes: 60, total_overtime_holiday_minutes: 0, record_version: 2,
    });
    assert.equal(s.totalOvertimeWeekdayMinutes, 120);
    assert.equal(s.totalOvertimeWeekendMinutes, 60);
  });

  test("summary detail extends the row with reopen lineage", () => {
    const d = parseTimesheetPeriodSummaryDetail({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe",
      timesheet_period_id: ID_1, status: "pending", total_regular_minutes: 0, total_overtime_weekday_minutes: 0,
      total_overtime_weekend_minutes: 0, total_overtime_holiday_minutes: 0, record_version: 3, entry_count: 5,
      overtime_request_count: 1, computed_at: "2026-08-10T01:00:00Z", decided_reason: null, reopen_count: 1,
      last_reopen_reason: "correction needed",
    });
    assert.equal(d.reopenCount, 1);
    assert.equal(d.lastReopenReason, "correction needed");
  });
});

describe("parseOvertimePolicyRow / parseOvertimePolicyVersion", () => {
  test("policy version row maps every server-authoritative rounding/cap field", () => {
    const v = parseOvertimePolicyVersion({
      id: ID_1, policy_id: ID_1, tenant_id: TENANT_ID, version_number: 1, status: "published", effective_from: "2024-01-01",
      rounding_increment_minutes: 15, rounding_mode: "nearest", min_overtime_minutes: 30, daily_overtime_cap_minutes: 180,
      weekly_overtime_cap_minutes: 600, standard_workday_minutes: 480, default_break_deduction_minutes: 0,
      requires_pre_approval: true, record_version: 1,
    });
    assert.equal(v.roundingIncrementMinutes, 15);
    assert.equal(v.dailyOvertimeCapMinutes, 180);
  });

  test("policy row maps published-version pointer", () => {
    const p = parseOvertimePolicyRow({ id: ID_1, org_unit_id: null, name: "Tenant-Wide", status: "published", published_version_id: ID_1, published_version_number: 1, record_version: 1 });
    assert.equal(p.publishedVersionNumber, 1);
  });
});

describe("parsePayrollTimeInputRow / parsePayrollTimeInputDetail", () => {
  test("carries only classification-split minute columns -- zero rate/amount fields on the wire shape itself", () => {
    const r = parsePayrollTimeInputRow({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", timesheet_period_id: ID_1, version_number: 1,
      status: "active", regular_minutes: 9600, overtime_weekday_minutes: 120, overtime_weekend_minutes: 0,
      overtime_holiday_minutes: 0, created_at: "2026-08-10T01:00:00Z",
    });
    assert.equal(r.status, "active");
    assert.equal(Object.keys(r).some((k) => /rate|amount|currency/i.test(k)), false);
  });

  test("detail row carries source lineage arrays", () => {
    const d = parsePayrollTimeInputDetail({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", timesheet_period_id: ID_1, version_number: 2,
      status: "active", regular_minutes: 9600, overtime_weekday_minutes: 120, overtime_weekend_minutes: 0,
      overtime_holiday_minutes: 0, created_at: "2026-08-10T01:00:00Z", source_entry_ids: [ID_1], source_overtime_request_ids: [],
    });
    assert.equal(d.sourceEntryIds.length, 1);
  });
});

describe("mutation input schemas", () => {
  test("CreateOvertimeRequestInputSchema requires a non-empty reason and rejects an empty one", () => {
    const base = {
      tenantId: TENANT_ID, requestType: "planned" as const, requestedStartAt: "2026-08-10T17:00:00Z",
      requestedEndAt: "2026-08-10T19:00:00Z", unpaidBreakMinutes: 0, reason: "project deadline", scheduleAssignmentId: null,
      jobOrderId: null, shipmentOrderId: null, idempotencyKey: "ot-1", actorAuthUserId: ACTOR, actorLabel: "emp1",
    };
    assert.doesNotThrow(() => CreateOvertimeRequestInputSchema.parse(base));
    assert.throws(() => CreateOvertimeRequestInputSchema.parse({ ...base, reason: "" }));
  });

  test("DecideOvertimeRequestInputSchema allows a null approvedMinutesOverride (server computes eligible)", () => {
    const parsed = DecideOvertimeRequestInputSchema.parse({
      requestId: ID_1, expectedVersion: 1, decision: "approve", decidedReason: "ok", approvedMinutesOverride: null,
      actorAuthUserId: ACTOR, actorLabel: "approver",
    });
    assert.equal(parsed.approvedMinutesOverride, null);
  });

  test("CreateTimesheetEntryInputSchema rejects zero/negative entry_minutes", () => {
    const base = {
      tenantId: TENANT_ID, workDate: "2026-08-10", entryMinutes: 480, unpaidBreakMinutes: 0, jobOrderId: null,
      shipmentOrderId: null, scheduleAssignmentId: null, notes: null, idempotencyKey: "ts-1", actorAuthUserId: ACTOR, actorLabel: "emp1",
    };
    assert.doesNotThrow(() => CreateTimesheetEntryInputSchema.parse(base));
    assert.throws(() => CreateTimesheetEntryInputSchema.parse({ ...base, entryMinutes: 0 }));
  });

  test("CreateOvertimePolicyVersionInputSchema bounds rounding_increment_minutes to [1,60]", () => {
    const base = {
      policyId: ID_1, roundingIncrementMinutes: 15, roundingMode: "nearest" as const, minOvertimeMinutes: 30,
      dailyOvertimeCapMinutes: 180, weeklyOvertimeCapMinutes: 600, standardWorkdayMinutes: 480,
      defaultBreakDeductionMinutes: 0, requiresPreApproval: true, effectiveFrom: "2024-01-01", actorAuthUserId: ACTOR, actorLabel: "admin",
    };
    assert.doesNotThrow(() => CreateOvertimePolicyVersionInputSchema.parse(base));
    assert.throws(() => CreateOvertimePolicyVersionInputSchema.parse({ ...base, roundingIncrementMinutes: 61 }));
  });
});
