import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listScheduledReports,
  getScheduledReportById,
  listScheduledReportRecipients,
  listScheduledReportRuns,
  ScheduledReportQueryError,
  type ScheduledReportQueryClient,
} from "./scheduled-report.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const SCHEDULE_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_SCHEDULE_ROW = {
  id: SCHEDULE_ID,
  tenant_id: TENANT_ID,
  report_type_code: "finance_billing_summary",
  owner_auth_user_id: ACTOR_ID,
  name: "Daily Billing Summary",
  description: "",
  cron_minute: 30,
  cron_hour: 9,
  cron_day_of_month: null,
  cron_day_of_week: null,
  timezone: "Asia/Jakarta",
  filters: {},
  status: "active",
  next_run_at: "2026-08-22T02:30:00.000Z",
  last_run_at: null,
  record_version: 1,
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
};

const VALID_RECIPIENT_ROW = {
  id: "523e4567-e89b-12d3-a456-426614174000",
  scheduled_report_id: SCHEDULE_ID,
  recipient_auth_user_id: ACTOR_ID,
  added_by_auth_user_id: ACTOR_ID,
  created_at: "2026-08-21T00:00:00.000Z",
};

const VALID_RUN_ROW = {
  id: "623e4567-e89b-12d3-a456-426614174000",
  scheduled_report_id: SCHEDULE_ID,
  job_id: "723e4567-e89b-12d3-a456-426614174000",
  status: "queued",
  recipients_total: 2,
  recipients_reauthorized: 1,
  recipients_denied: 1,
  artifact_file_id: null,
  artifact_expires_at: "2026-08-28T00:00:00.000Z",
  error_reason: null,
  triggered_by_auth_user_id: ACTOR_ID,
  triggered_by_label: "tester",
  started_at: "2026-08-21T00:00:00.000Z",
  completed_at: null,
};

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): ScheduledReportQueryClient {
  function chainNode(): unknown {
    return {
      select: () => chainNode(),
      eq: () => chainNode(),
      order: () => chainNode(),
      limit: () => Promise.resolve(response),
      maybeSingle: () => {
        const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
        return Promise.resolve({ data: row, error: response.error });
      },
      then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) => Promise.resolve(response).then(resolve, reject),
    };
  }
  return { from: () => chainNode() } as unknown as ScheduledReportQueryClient;
}

describe("listScheduledReports", () => {
  test("maps schedule rows", async () => {
    const client = fakeTableClient({ data: [VALID_SCHEDULE_ROW], error: null });
    const schedules = await listScheduledReports(client, TENANT_ID);
    assert.equal(schedules.length, 1);
    assert.equal(schedules[0]?.name, "Daily Billing Summary");
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listScheduledReports(client, TENANT_ID),
      (err: unknown) => err instanceof ScheduledReportQueryError,
    );
  });
});

describe("getScheduledReportById", () => {
  test("returns null (never an error) when not found", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const schedule = await getScheduledReportById(client, SCHEDULE_ID);
    assert.equal(schedule, null);
  });

  test("parses a matched row", async () => {
    const client = fakeTableClient({ data: VALID_SCHEDULE_ROW, error: null });
    const schedule = await getScheduledReportById(client, SCHEDULE_ID);
    assert.equal(schedule?.id, SCHEDULE_ID);
  });
});

describe("listScheduledReportRecipients", () => {
  test("maps recipient rows", async () => {
    const client = fakeTableClient({ data: [VALID_RECIPIENT_ROW], error: null });
    const recipients = await listScheduledReportRecipients(client, SCHEDULE_ID);
    assert.equal(recipients.length, 1);
    assert.equal(recipients[0]?.recipientAuthUserId, ACTOR_ID);
  });
});

describe("listScheduledReportRuns", () => {
  test("maps run rows, newest first", async () => {
    const client = fakeTableClient({ data: [VALID_RUN_ROW], error: null });
    const runs = await listScheduledReportRuns(client, SCHEDULE_ID);
    assert.equal(runs.length, 1);
    assert.equal(runs[0]?.recipientsReauthorized, 1);
  });
});
