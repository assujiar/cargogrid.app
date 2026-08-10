import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseShiftTemplateRow,
  parseShiftTemplateVersionDetail,
  parseRosterCycleRow,
  parseRosterCycleDetail,
  parseRosterHolidayRow,
  parseCoverageRequirementRow,
  parseCoveragePreviewRow,
  parseMyScheduleRow,
  parseScheduleAssignmentListRow,
  parseScheduleAssignmentDetail,
  parseSwapRequestRow,
  parseMySwapRequestRow,
  parsePublishScheduleAssignmentsResultRow,
  parseGenerateRosterScheduleAssignmentsResult,
  CreateShiftTemplateVersionInputSchema,
  AssignEmployeeScheduleInputSchema,
  RequestScheduleSwapInputSchema,
} from "./shift-roster.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ID_3 = "423e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACTOR = "523e4567-e89b-12d3-a456-426614174000";

describe("parseShiftTemplateRow / parseShiftTemplateVersionDetail", () => {
  test("template row maps snake_case to camelCase, null org_unit_id tenant-wide", () => {
    const r = parseShiftTemplateRow({
      id: ID_1, org_unit_id: null, code: "MORNING", name: "Morning Fixed", status: "published",
      published_version_id: ID_2, published_version_number: 1, record_version: 2,
    });
    assert.equal(r.orgUnitId, null);
    assert.equal(r.publishedVersionNumber, 1);
  });

  test("version detail parses a real cross-midnight segment list", () => {
    const v = parseShiftTemplateVersionDetail({
      id: ID_1, shift_template_id: ID_2, version_number: 1, status: "published", effective_from: "2026-08-10",
      timezone: "Asia/Jakarta", day_boundary_local_time: "04:00:00", shift_type: "fixed",
      grace_late_minutes: 10, grace_early_minutes: 10, crosses_midnight: true,
      total_work_minutes: 480, total_break_minutes: 60, record_version: 1,
      segments: [
        { sequence_number: 0, segment_type: "work", start_time: "22:00:00", end_time: "02:00:00", crosses_midnight: false, duration_minutes: 240 },
      ],
    });
    assert.equal(v.crossesMidnight, true);
    assert.equal(v.segments.length, 1);
    assert.equal(v.segments[0]?.segmentType, "work");
  });

  test("version detail defaults segments to empty array when absent", () => {
    const v = parseShiftTemplateVersionDetail({
      id: ID_1, shift_template_id: ID_2, version_number: 1, status: "draft", effective_from: "2026-08-10",
      timezone: "Asia/Jakarta", day_boundary_local_time: "00:00:00", shift_type: "flexible",
      grace_late_minutes: null, grace_early_minutes: null, crosses_midnight: false,
      total_work_minutes: 480, total_break_minutes: 0, record_version: 1,
    });
    assert.deepEqual(v.segments, []);
  });
});

describe("parseRosterCycleRow / parseRosterCycleDetail", () => {
  test("cycle row carries slot_count", () => {
    const c = parseRosterCycleRow({ id: ID_1, org_unit_id: ID_2, name: "4-on 2-off", cycle_length_days: 6, status: "published", slot_count: 6, record_version: 1 });
    assert.equal(c.slotCount, 6);
  });

  test("cycle detail maps slots, including a day-off null shift_template_id", () => {
    const d = parseRosterCycleDetail({
      id: ID_1, org_unit_id: null, name: "Weekly", cycle_length_days: 2, status: "draft", record_version: 1,
      slots: [
        { day_offset: 0, shift_template_id: ID_2 },
        { day_offset: 1, shift_template_id: null },
      ],
    });
    assert.equal(d.slots.length, 2);
    assert.equal(d.slots[1]?.shiftTemplateId, null);
  });
});

describe("parseRosterHolidayRow / parseCoverageRequirementRow / parseCoveragePreviewRow", () => {
  test("holiday row maps is_working_day override", () => {
    const h = parseRosterHolidayRow({ id: ID_1, org_unit_id: null, holiday_date: "2026-12-25", name: "Christmas", is_working_day: false, record_version: 1 });
    assert.equal(h.isWorkingDay, false);
  });

  test("coverage requirement row includes the joined shift template name", () => {
    const r = parseCoverageRequirementRow({ id: ID_1, org_unit_id: ID_2, shift_template_id: ID_3, shift_template_name: "Morning", day_of_week: 1, min_headcount: 3, record_version: 1 });
    assert.equal(r.shiftTemplateName, "Morning");
  });

  test("coverage preview row reports below_minimum when scheduled_count < min_headcount", () => {
    const p = parseCoveragePreviewRow({ work_date: "2026-08-10", shift_template_id: ID_1, shift_template_name: "Morning", scheduled_count: 1, min_headcount: 3, coverage_status: "below_minimum" });
    assert.equal(p.coverageStatus, "below_minimum");
  });
});

describe("parseMyScheduleRow / parseScheduleAssignmentListRow / parseScheduleAssignmentDetail", () => {
  test("my schedule row", () => {
    const r = parseMyScheduleRow({ assignment_id: ID_1, work_date: "2026-08-10", shift_template_id: ID_2, shift_template_name: "Morning", shift_type: "fixed", crosses_midnight: false, status: "published" });
    assert.equal(r.status, "published");
  });

  test("assignment list row maps employee identity fields", () => {
    const r = parseScheduleAssignmentListRow({
      id: ID_1, employee_id: ID_2, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe",
      work_date: "2026-08-10", shift_template_name: "Morning", status: "scheduled", record_version: 1,
    });
    assert.equal(r.employeeNumber, "EMP-2026-000001");
  });

  test("assignment detail carries source", () => {
    const d = parseScheduleAssignmentDetail({
      id: ID_1, employee_id: ID_2, work_date: "2026-08-10", shift_template_version_id: ID_3,
      shift_template_name: "Morning", status: "published", source: "bulk_generated", record_version: 1,
    });
    assert.equal(d.source, "bulk_generated");
  });
});

describe("parseSwapRequestRow / parseMySwapRequestRow", () => {
  test("admin swap row includes both employee identities", () => {
    const r = parseSwapRequestRow({
      id: ID_1, requesting_employee_id: ID_2, requesting_employee_number: "EMP-2026-000001",
      target_employee_id: ID_3, target_employee_number: "EMP-2026-000002",
      assignment_id: ID_1, target_assignment_id: ID_2, status: "pending_approval", created_at: "2026-08-10T01:00:00Z", record_version: 1,
    });
    assert.equal(r.status, "pending_approval");
  });

  test("my swap row reports role as target for the non-initiating employee", () => {
    const r = parseMySwapRequestRow({ id: ID_1, role: "target", assignment_id: ID_2, target_assignment_id: ID_3, status: "pending_approval", created_at: "2026-08-10T01:00:00Z", record_version: 1 });
    assert.equal(r.role, "target");
  });
});

describe("parsePublishScheduleAssignmentsResultRow / parseGenerateRosterScheduleAssignmentsResult", () => {
  test("publish result row reports a skip_reason for a not-yet-active employee", () => {
    const r = parsePublishScheduleAssignmentsResultRow({ assignment_id: ID_1, published: false, skip_reason: "employee_not_active" });
    assert.equal(r.published, false);
    assert.equal(r.skipReason, "employee_not_active");
  });

  test("generation result maps counts and the tracking job_id", () => {
    const r = parseGenerateRosterScheduleAssignmentsResult({ created_count: 5, superseded_count: 1, skipped_count: 2, job_id: ID_1 });
    assert.equal(r.createdCount, 5);
    assert.equal(r.jobId, ID_1);
  });
});

describe("mutation input schemas", () => {
  test("CreateShiftTemplateVersionInputSchema requires at least one segment", () => {
    assert.throws(() =>
      CreateShiftTemplateVersionInputSchema.parse({
        shiftTemplateId: ID_1, timezone: "Asia/Jakarta", dayBoundaryLocalTime: null, shiftType: "fixed",
        graceLateMinutes: null, graceEarlyMinutes: null, effectiveFrom: "2026-08-10", segments: [],
        actorAuthUserId: ACTOR, actorLabel: "tester",
      }),
    );
  });

  test("CreateShiftTemplateVersionInputSchema accepts a real split-shift segment pair", () => {
    const parsed = CreateShiftTemplateVersionInputSchema.parse({
      shiftTemplateId: ID_1, timezone: "Asia/Jakarta", dayBoundaryLocalTime: "00:00:00", shiftType: "split",
      graceLateMinutes: 10, graceEarlyMinutes: 10, effectiveFrom: "2026-08-10",
      segments: [
        { segmentType: "work", startTime: "08:00:00", endTime: "12:00:00" },
        { segmentType: "break", startTime: "12:00:00", endTime: "13:00:00" },
        { segmentType: "work", startTime: "13:00:00", endTime: "17:00:00" },
      ],
      actorAuthUserId: ACTOR, actorLabel: "tester",
    });
    assert.equal(parsed.segments.length, 3);
  });

  test("AssignEmployeeScheduleInputSchema rejects a non-uuid employeeId", () => {
    assert.throws(() =>
      AssignEmployeeScheduleInputSchema.parse({
        tenantId: TENANT_ID, employeeId: "not-a-uuid", shiftTemplateVersionId: ID_1, workDate: "2026-08-10",
        source: "manual", idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "tester",
      }),
    );
  });

  test("RequestScheduleSwapInputSchema requires a non-empty reason", () => {
    assert.throws(() =>
      RequestScheduleSwapInputSchema.parse({
        assignmentId: ID_1, targetEmployeeId: ID_2, targetAssignmentId: ID_3, reason: "",
        idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "tester",
      }),
    );
  });
});
