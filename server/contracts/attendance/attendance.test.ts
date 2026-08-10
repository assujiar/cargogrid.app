import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseMyAttendanceStatus,
  parseSessionListRow,
  parseSessionDetail,
  parseAttendanceExceptionRow,
  parseCorrectionRequestRow,
  parseAttendancePolicyRow,
  parseAttendancePolicyVersion,
  RecordAttendanceClockEventInputSchema,
  RequestAttendanceCorrectionInputSchema,
  GeoJsonPointSchema,
} from "./attendance.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR = "323e4567-e89b-12d3-a456-426614174000";

describe("parseMyAttendanceStatus / parseSessionListRow / parseSessionDetail", () => {
  test("maps a real open session row", () => {
    const s = parseMyAttendanceStatus({
      session_id: ID_1, work_date: "2026-08-10", status: "open", effective_clock_in_at: "2026-08-10T01:00:00Z",
      effective_clock_out_at: null, open_exception_count: 1, payroll_input_status: "pending",
    });
    assert.equal(s.status, "open");
    assert.equal(s.effectiveClockOutAt, null);
  });

  test("session list row maps snake_case to camelCase", () => {
    const r = parseSessionListRow({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe",
      work_date: "2026-08-10", status: "closed", effective_clock_in_at: "2026-08-10T01:00:00Z",
      effective_clock_out_at: "2026-08-10T09:00:00Z", payroll_input_status: "approved", open_exception_count: 0, record_version: 2,
    });
    assert.equal(r.employeeNumber, "EMP-2026-000001");
    assert.equal(r.payrollInputStatus, "approved");
  });

  test("session detail preserves raw vs effective distinction (never overwrites raw)", () => {
    const d = parseSessionDetail({
      id: ID_1, employee_id: ID_1, work_date: "2026-08-10", status: "closed", timezone: "Asia/Jakarta",
      effective_clock_in_at: "2026-08-10T01:00:00Z", effective_clock_out_at: "2026-08-10T10:00:00Z",
      raw_clock_in_at: "2026-08-10T01:00:00Z", raw_clock_out_at: "2026-08-10T09:00:00Z",
      payroll_input_status: "pending", record_version: 3,
    });
    assert.notEqual(d.rawClockOutAt, d.effectiveClockOutAt);
  });
});

describe("parseAttendanceExceptionRow / parseCorrectionRequestRow", () => {
  test("exception row carries detail jsonb", () => {
    const e = parseAttendanceExceptionRow({
      id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", session_id: ID_1, work_date: "2026-08-10",
      exception_type: "late", severity: "medium", status: "open", detail: { minutes_late: 8 }, detected_at: "2026-08-10T01:00:00Z", record_version: 1,
    });
    assert.equal(e.exceptionType, "late");
    assert.equal(e.detail.minutes_late, 8);
  });

  test("correction request row maps request_type/status", () => {
    const c = parseCorrectionRequestRow({
      id: ID_1, session_id: ID_1, work_date: "2026-08-10", request_type: "adjust_clock_out", status: "pending_approval",
      created_at: "2026-08-10T01:00:00Z", record_version: 1,
    });
    assert.equal(c.status, "pending_approval");
  });
});

describe("parseAttendancePolicyRow / parseAttendancePolicyVersion", () => {
  test("policy row maps published version pointer", () => {
    const p = parseAttendancePolicyRow({
      id: ID_1, org_unit_id: null, name: "Tenant-Wide", status: "published", published_version_id: ID_1, published_version_number: 1, record_version: 1,
    });
    assert.equal(p.orgUnitId, null);
    assert.equal(p.publishedVersionNumber, 1);
  });

  test("policy version row maps geofence/channel/grace fields", () => {
    const v = parseAttendancePolicyVersion({
      id: ID_1, policy_id: ID_1, tenant_id: TENANT_ID, version_number: 1, status: "published", effective_from: "2024-01-01",
      timezone: "Asia/Jakarta", workday_start_time: "08:00:00", workday_end_time: "17:00:00", day_boundary_local_time: "04:00:00",
      grace_late_minutes: 15, grace_early_minutes: 15, allowed_channels: ["mobile_web", "kiosk"], location_enforcement_mode: "none",
      geofence_radius_meters: null, max_session_hours: 16, record_version: 1,
    });
    assert.deepEqual(v.allowedChannels, ["mobile_web", "kiosk"]);
    assert.equal(v.locationEnforcementMode, "none");
  });
});

describe("input schemas", () => {
  test("RecordAttendanceClockEventInputSchema rejects a non-self-service channel", () => {
    assert.throws(() =>
      RecordAttendanceClockEventInputSchema.parse({
        tenantId: TENANT_ID, eventType: "clock_in", sourceChannel: "device_import", clientReportedAt: null,
        locationGeojson: null, deviceLabel: null, idempotencyKey: "k1", actorAuthUserId: ACTOR, actorLabel: "emp",
      }),
    );
  });

  test("RecordAttendanceClockEventInputSchema has NO employee-id-shaped field to spoof (decision 10)", () => {
    const parsed = RecordAttendanceClockEventInputSchema.parse({
      tenantId: TENANT_ID, eventType: "clock_in", sourceChannel: "mobile_web", clientReportedAt: null,
      locationGeojson: null, deviceLabel: null, idempotencyKey: "k1", actorAuthUserId: ACTOR, actorLabel: "emp",
    });
    assert.equal("employeeId" in parsed, false);
  });

  test("RequestAttendanceCorrectionInputSchema requires a non-empty reason", () => {
    assert.throws(() =>
      RequestAttendanceCorrectionInputSchema.parse({
        sessionId: ID_1, requestType: "adjust_clock_out", proposedClockInAt: null, proposedClockOutAt: "2026-08-10T10:00:00Z",
        reason: "", evidenceFileId: null, idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "emp",
      }),
    );
  });

  test("GeoJsonPointSchema enforces RFC 7946 [longitude, latitude] range", () => {
    assert.throws(() => GeoJsonPointSchema.parse({ type: "Point", coordinates: [200, 10] }));
    assert.doesNotThrow(() => GeoJsonPointSchema.parse({ type: "Point", coordinates: [106.8456, -6.2088] }));
  });
});
