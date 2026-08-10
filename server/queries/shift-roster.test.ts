import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getMySchedule,
  listScheduleAssignments,
  getScheduleAssignmentDetail,
  listShiftTemplates,
  getShiftTemplateVersionDetail,
  listRosterCycles,
  getRosterCycleDetail,
  listRosterHolidays,
  listScheduleCoverageRequirements,
  getScheduleCoveragePreview,
  listScheduleSwapRequests,
  listMyScheduleSwapRequests,
  ShiftRosterQueryError,
  type ShiftRosterQueryClient,
} from "./shift-roster.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: ShiftRosterQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ShiftRosterQueryClient;
  return { client, calls };
}

describe("getMySchedule", () => {
  test("passes tenant/actor/date-range through and parses rows", async () => {
    const { client, calls } = fakeClient({
      data: [{ assignment_id: ID_1, work_date: "2026-08-10", shift_template_id: ID_1, shift_template_name: "Morning", shift_type: "fixed", crosses_midnight: false, status: "published" }],
      error: null,
    });
    const rows = await getMySchedule(client, TENANT_ID, ACTOR_ID, { fromDate: "2026-08-01", toDate: "2026-08-31" });
    assert.equal(calls[0]?.fn, "get_my_schedule");
    assert.equal(rows[0]?.status, "published");
  });

  test("throws ShiftRosterQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => getMySchedule(client, TENANT_ID, ACTOR_ID), ShiftRosterQueryError);
  });
});

describe("listScheduleAssignments", () => {
  test("defaults limit to 50 and applies filters", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listScheduleAssignments(client, TENANT_ID, ACTOR_ID, { employeeId: ID_1, status: "scheduled" });
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_employee_id, ID_1);
  });
});

describe("getScheduleAssignmentDetail", () => {
  test("returns null when the RPC returns no row", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const detail = await getScheduleAssignmentDetail(client, ID_1, ACTOR_ID);
    assert.equal(detail, null);
  });
});

describe("listShiftTemplates / getShiftTemplateVersionDetail", () => {
  test("template list parses published_version fields", async () => {
    const { client } = fakeClient({ data: [{ id: ID_1, org_unit_id: null, code: "MORNING", name: "Morning", status: "published", published_version_id: ID_1, published_version_number: 1, record_version: 1 }], error: null });
    const rows = await listShiftTemplates(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.code, "MORNING");
  });

  test("version detail parses segments jsonb array", async () => {
    const { client } = fakeClient({
      data: [{
        id: ID_1, shift_template_id: ID_1, version_number: 1, status: "published", effective_from: "2026-08-10",
        timezone: "Asia/Jakarta", day_boundary_local_time: "00:00:00", shift_type: "fixed", grace_late_minutes: null,
        grace_early_minutes: null, crosses_midnight: false, total_work_minutes: 480, total_break_minutes: 60, record_version: 1,
        segments: [{ sequence_number: 0, segment_type: "work", start_time: "08:00:00", end_time: "17:00:00", crosses_midnight: false, duration_minutes: 540 }],
      }],
      error: null,
    });
    const detail = await getShiftTemplateVersionDetail(client, ID_1, ACTOR_ID);
    assert.equal(detail?.segments.length, 1);
  });
});

describe("listRosterCycles / getRosterCycleDetail", () => {
  test("cycle detail parses slots including a day-off null shift", async () => {
    const { client } = fakeClient({
      data: [{ id: ID_1, org_unit_id: null, name: "Weekly", cycle_length_days: 2, status: "draft", record_version: 1, slots: [{ day_offset: 0, shift_template_id: null }] }],
      error: null,
    });
    const detail = await getRosterCycleDetail(client, ID_1, ACTOR_ID);
    assert.equal(detail?.slots[0]?.shiftTemplateId, null);
  });

  test("listRosterCycles returns an empty array on empty data", async () => {
    const { client } = fakeClient({ data: null, error: null });
    const rows = await listRosterCycles(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("listRosterHolidays / listScheduleCoverageRequirements / getScheduleCoveragePreview", () => {
  test("holiday list passes org_unit_id through, null by default", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listRosterHolidays(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_org_unit_id, null);
  });

  test("coverage preview requires an explicit date range", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await getScheduleCoveragePreview(client, TENANT_ID, ACTOR_ID, null, "2026-08-01", "2026-08-31");
    assert.equal(calls[0]?.args.p_from_date, "2026-08-01");
  });

  test("coverage requirements list parses the joined shift template name", async () => {
    const { client } = fakeClient({ data: [{ id: ID_1, org_unit_id: ID_1, shift_template_id: ID_1, shift_template_name: "Morning", day_of_week: 1, min_headcount: 2, record_version: 1 }], error: null });
    const rows = await listScheduleCoverageRequirements(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.shiftTemplateName, "Morning");
  });
});

describe("listScheduleSwapRequests / listMyScheduleSwapRequests", () => {
  test("admin swap list defaults limit to 50", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listScheduleSwapRequests(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("my swap requests parses requester/target role", async () => {
    const { client } = fakeClient({ data: [{ id: ID_1, role: "requester", assignment_id: ID_1, target_assignment_id: ID_1, status: "pending_approval", created_at: "2026-08-10T01:00:00Z", record_version: 1 }], error: null });
    const rows = await listMyScheduleSwapRequests(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.role, "requester");
  });
});
