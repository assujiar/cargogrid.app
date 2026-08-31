import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listMyOvertimeRequests,
  listOvertimeRequests,
  getOvertimeRequestDetail,
  listMyTimesheetEntries,
  listTimesheetEntries,
  getTimesheetEntryDetail,
  listTimesheetPeriods,
  listTimesheetPeriodSummaries,
  getTimesheetPeriodSummary,
  listOvertimePolicies,
  getOvertimePolicyVersion,
  listPayrollTimeInputs,
  getPayrollTimeInput,
  OvertimeTimesheetQueryError,
  type OvertimeTimesheetQueryClient,
} from "./overtime-timesheet.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: OvertimeTimesheetQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as OvertimeTimesheetQueryClient;
  return { client, calls };
}

const OVERTIME_ROW = {
  id: ID_1, work_date: "2026-08-10", request_type: "planned", requested_start_at: "2026-08-10T17:00:00Z",
  requested_end_at: "2026-08-10T19:00:00Z", requested_minutes: 120, unpaid_break_minutes: 0, status: "approved",
  reconciliation_status: "matched", eligible_minutes: 120, eligible_classification: "weekday", approved_minutes: 120,
  payroll_input_status: "pending", record_version: 2,
};

describe("listMyOvertimeRequests / listOvertimeRequests / getOvertimeRequestDetail", () => {
  test("listMyOvertimeRequests defaults limit and parses rows", async () => {
    const { client, calls } = fakeClient({ data: [OVERTIME_ROW], error: null });
    const rows = await listMyOvertimeRequests(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(rows[0]?.eligibleMinutes, 120);
  });

  test("listOvertimeRequests passes through employee/status filters", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listOvertimeRequests(client, TENANT_ID, ACTOR_ID, { employeeId: ID_1, status: "pending_approval" });
    assert.equal(calls[0]?.args.p_employee_id, ID_1);
    assert.equal(calls[0]?.args.p_status, "pending_approval");
  });

  test("getOvertimeRequestDetail returns null on the folded not-found/no-access empty result", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const detail = await getOvertimeRequestDetail(client, ID_1, ACTOR_ID);
    assert.equal(detail, null);
  });

  test("throws OvertimeTimesheetQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listMyOvertimeRequests(client, TENANT_ID, ACTOR_ID), OvertimeTimesheetQueryError);
  });
});

/**
 * `ISS-2026-315`: this fixture is the exact column set `app.list_my_timesheet_entries` and
 * `app.list_timesheet_entries` declare in their `RETURNS TABLE`, after
 * `20260831160000_expose_timesheet_entry_break_and_notes_in_list.sql`.
 *
 * It has to be. Its previous version carried an `unpaid_break_minutes` that the HR listing had
 * **never** returned, so this suite went green while the real admin workspace would have thrown a
 * `ZodError` on its first row. A fake more generous than the thing it stands in for proves
 * nothing about the thing — which is why the pin below asserts the failure direction directly,
 * rather than trusting a future editor to keep this object honest.
 */
const ENTRY_ROW = {
  id: ID_1, work_date: "2026-08-10", entry_minutes: 480, unpaid_break_minutes: 30, job_order_id: null, job_number: null,
  shipment_order_id: null, shipment_number: null, notes: "reworked the manifest", status: "approved", reconciliation_status: "matched",
  eligible_minutes: 450, approved_minutes: 450, payroll_input_status: "pending", record_version: 2,
};

describe("listMyTimesheetEntries / listTimesheetEntries / getTimesheetEntryDetail", () => {
  test("listMyTimesheetEntries applies date range filters", async () => {
    const { client, calls } = fakeClient({ data: [ENTRY_ROW], error: null });
    await listMyTimesheetEntries(client, TENANT_ID, ACTOR_ID, { fromDate: "2026-08-01", toDate: "2026-08-31" });
    assert.equal(calls[0]?.args.p_from_date, "2026-08-01");
    assert.equal(calls[0]?.args.p_to_date, "2026-08-31");
  });

  test("listTimesheetEntries admin variant parses employee identity columns", async () => {
    const { client } = fakeClient({ data: [{ ...ENTRY_ROW, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe" }], error: null });
    const rows = await listTimesheetEntries(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.employeeNumber, "EMP-2026-000001");
  });

  test("getTimesheetEntryDetail returns null on empty result", async () => {
    const { client } = fakeClient({ data: [], error: null });
    assert.equal(await getTimesheetEntryDetail(client, ID_1, ACTOR_ID), null);
  });

  /**
   * `ISS-2026-315` regression, stated as the failure it actually was. `unpaidBreakMinutes` is
   * required and NOT defaulted, so a listing that stops returning the column breaks loudly here
   * instead of breaking quietly in the browser — where it surfaced as an uncaught `ZodError`
   * rather than the `OvertimeTimesheetQueryError` the page knows how to render.
   */
  test("a listing row missing unpaid_break_minutes is rejected, not silently coerced", async () => {
    const { unpaid_break_minutes: _dropped, ...withoutBreak } = ENTRY_ROW;
    const { client } = fakeClient({ data: [{ ...withoutBreak, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe" }], error: null });
    await assert.rejects(() => listTimesheetEntries(client, TENANT_ID, ACTOR_ID));
  });

  /** `notes`, by contrast, degrades to null — a missing note must never break a listing. */
  test("a listing row missing notes degrades to null rather than throwing", async () => {
    const { notes: _dropped, ...withoutNotes } = ENTRY_ROW;
    const { client } = fakeClient({ data: [{ ...withoutNotes, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe" }], error: null });
    const rows = await listTimesheetEntries(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.notes, null);
  });

  test("notes reaches the parsed row when the RPC returns it", async () => {
    const { client } = fakeClient({ data: [{ ...ENTRY_ROW, employee_id: ID_1, employee_number: "EMP-2026-000001", employee_full_name: "Jane Doe" }], error: null });
    const rows = await listTimesheetEntries(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.notes, "reworked the manifest");
    assert.equal(rows[0]?.unpaidBreakMinutes, 30);
  });
});

describe("listTimesheetPeriods / listTimesheetPeriodSummaries / getTimesheetPeriodSummary", () => {
  test("listTimesheetPeriods parses lock status", async () => {
    const { client } = fakeClient({ data: [{ id: ID_1, org_unit_id: null, code: "P-1", period_start: "2026-08-01", period_end: "2026-08-31", status: "locked", record_version: 1 }], error: null });
    const rows = await listTimesheetPeriods(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.status, "locked");
  });

  test("listTimesheetPeriodSummaries passes period/status filters", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTimesheetPeriodSummaries(client, TENANT_ID, ACTOR_ID, { periodId: ID_1, status: "submitted" });
    assert.equal(calls[0]?.args.p_period_id, ID_1);
    assert.equal(calls[0]?.args.p_status, "submitted");
  });

  test("getTimesheetPeriodSummary returns null on empty result", async () => {
    const { client } = fakeClient({ data: [], error: null });
    assert.equal(await getTimesheetPeriodSummary(client, ID_1, ACTOR_ID), null);
  });
});

describe("listOvertimePolicies / getOvertimePolicyVersion", () => {
  test("listOvertimePolicies parses published-version pointer", async () => {
    const { client } = fakeClient({ data: [{ id: ID_1, org_unit_id: null, name: "Tenant-Wide", status: "published", published_version_id: ID_1, published_version_number: 1, record_version: 1 }], error: null });
    const rows = await listOvertimePolicies(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.publishedVersionNumber, 1);
  });

  test("getOvertimePolicyVersion returns null when the RPC returns null (no permission)", async () => {
    const { client } = fakeClient({ data: null, error: null });
    assert.equal(await getOvertimePolicyVersion(client, ID_1, ACTOR_ID), null);
  });
});

describe("listPayrollTimeInputs / getPayrollTimeInput", () => {
  test("listPayrollTimeInputs parses classification-split minutes, no money field", async () => {
    const { client } = fakeClient({
      data: [{ id: ID_1, employee_id: ID_1, employee_number: "EMP-2026-000001", timesheet_period_id: ID_1, version_number: 1, status: "active", regular_minutes: 9600, overtime_weekday_minutes: 120, overtime_weekend_minutes: 0, overtime_holiday_minutes: 0, created_at: "2026-08-10T01:00:00Z" }],
      error: null,
    });
    const rows = await listPayrollTimeInputs(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.overtimeWeekdayMinutes, 120);
  });

  test("getPayrollTimeInput returns null on empty result (self-or-View-payroll denial)", async () => {
    const { client } = fakeClient({ data: [], error: null });
    assert.equal(await getPayrollTimeInput(client, ID_1, ACTOR_ID), null);
  });
});
