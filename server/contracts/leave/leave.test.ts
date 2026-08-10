import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLeaveTypeRow,
  parseLeaveTypePolicyVersion,
  parseEmployeeLeaveBalanceRow,
  parseLeaveRequestListRow,
  parseLeaveRequestDetail,
  parseLeaveBalanceLedgerRow,
  parseLeaveCalendarRow,
  CreateLeaveRequestInputSchema,
  DecideLeaveRequestInputSchema,
  AdjustLeaveBalanceInputSchema,
} from "./leave.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";

describe("parseLeaveTypeRow / parseLeaveTypePolicyVersion", () => {
  test("maps a published leave type", () => {
    const t = parseLeaveTypeRow({
      id: ID_1, code: "annual", name: "Annual Leave", category: "leave", requires_balance: true,
      requires_evidence: false, evidence_classification: "none", status: "published", record_version: 2,
    });
    assert.equal(t.category, "leave");
    assert.equal(t.requiresBalance, true);
  });

  test("maps a policy version, nulls carried through", () => {
    const v = parseLeaveTypePolicyVersion({
      id: ID_1, leave_type_id: ID_1, org_unit_id: null, version_number: 1, status: "published",
      effective_from: "2026-01-01", accrual_frequency: "monthly", accrual_amount_per_period: "1.5",
      accrual_max_balance: null, carry_forward_max_units: "6", min_notice_days: 3, max_consecutive_units: null,
      eligibility_min_tenure_days: 90, negative_balance_allowed: false, record_version: 1,
    });
    assert.equal(v.accrualAmountPerPeriod, 1.5);
    assert.equal(v.accrualMaxBalance, null);
    assert.equal(v.carryForwardMaxUnits, 6);
  });
});

describe("parseEmployeeLeaveBalanceRow / parseLeaveRequestListRow / parseLeaveRequestDetail", () => {
  test("balance row coerces numeric strings", () => {
    const b = parseEmployeeLeaveBalanceRow({
      leave_type_id: ID_1, code: "annual", name: "Annual Leave", category: "leave", requires_balance: true,
      balance: "8.5", pending_units: "1",
    });
    assert.equal(b.balance, 8.5);
    assert.equal(b.pendingUnits, 1);
  });

  test("list row masks reason when reason_visible is false", () => {
    const r = parseLeaveRequestListRow({
      id: ID_1, employee_id: ID_1, employee_name: "Jane Doe", leave_type_id: ID_1, leave_type_code: "annual",
      category: "leave", status: "pending_approval", date_from: "2026-08-10", date_to: "2026-08-12",
      day_portion: "full_day", total_units: "3", payroll_input_status: "pending", record_version: 1,
      reason_visible: false, reason: null,
    });
    assert.equal(r.reasonVisible, false);
    assert.equal(r.reason, null);
  });

  test("detail row preserves schedule_snapshot array", () => {
    const d = parseLeaveRequestDetail({
      id: ID_1, employee_id: ID_1, leave_type_id: ID_1, status: "approved", date_from: "2026-08-10",
      date_to: "2026-08-10", day_portion: "full_day", total_units: "1", reason: "medical", destination: null,
      evidence_file_id: null, schedule_snapshot: [{ work_date: "2026-08-10", schedule_assignment_id: ID_1 }],
      payroll_input_status: "pending", decided_reason: "approved by manager", cancel_reason: null, record_version: 2,
    });
    assert.equal(d.scheduleSnapshot.length, 1);
    assert.equal(d.status, "approved");
  });
});

describe("parseLeaveBalanceLedgerRow / parseLeaveCalendarRow", () => {
  test("ledger row keeps a signed debit", () => {
    const l = parseLeaveBalanceLedgerRow({
      id: ID_1, employee_id: ID_1, leave_type_id: ID_1, event_type: "request_debit", units: "-2",
      effective_date: "2026-08-10", source_request_id: ID_1, created_at: "2026-08-10T01:00:00Z",
    });
    assert.equal(l.units, -2);
    assert.equal(l.eventType, "request_debit");
  });

  test("calendar row never carries a reason field at all (minimized by construction)", () => {
    const c = parseLeaveCalendarRow({
      employee_id: ID_1, employee_name: "Jane Doe", leave_type_id: ID_1, category: "leave",
      date_from: "2026-08-10", date_to: "2026-08-11", day_portion: "full_day",
    });
    assert.equal((c as Record<string, unknown>).reason, undefined);
  });
});

describe("mutation input schemas", () => {
  test("CreateLeaveRequestInputSchema accepts a business_trip-shaped payload", () => {
    const parsed = CreateLeaveRequestInputSchema.parse({
      tenantId: TENANT_ID, leaveTypeId: ID_1, dateFrom: "2026-09-01", dateTo: "2026-09-03", dayPortion: "full_day",
      reason: "Client site visit", destination: "Surabaya", evidenceFileId: null, idempotencyKey: null,
      actorAuthUserId: ACTOR, actorLabel: "emp",
    });
    assert.equal(parsed.destination, "Surabaya");
  });

  test("DecideLeaveRequestInputSchema rejects an unknown decision value", () => {
    assert.throws(() =>
      DecideLeaveRequestInputSchema.parse({
        requestStepId: ID_1, decision: "approve", reason: "ok", overrideCoverage: false, actorAuthUserId: ACTOR, actorLabel: "mgr",
      }),
    );
  });

  test("AdjustLeaveBalanceInputSchema rejects a zero-unit adjustment", () => {
    assert.throws(() =>
      AdjustLeaveBalanceInputSchema.parse({
        tenantId: TENANT_ID, employeeId: ID_1, leaveTypeId: ID_1, units: 0, effectiveDate: "2026-08-10",
        reason: "correction", idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "hr",
      }),
    );
  });
});
