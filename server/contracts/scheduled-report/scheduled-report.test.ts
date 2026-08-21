import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseScheduledReport,
  parseScheduledReportRecipient,
  parseScheduledReportRun,
  CreateScheduledReportInputSchema,
  ScheduledReportFiltersSchema,
} from "./scheduled-report.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const SCHEDULE_ID = "423e4567-e89b-12d3-a456-426614174000";
const RECIPIENT_ROW_ID = "523e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "623e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseScheduledReport", () => {
  test("maps a daily schedule (both dom/dow null)", () => {
    const schedule = parseScheduledReport({
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
    });
    assert.equal(schedule.cronDayOfMonth, null);
    assert.equal(schedule.timezone, "Asia/Jakarta");
  });
});

describe("parseScheduledReportRecipient", () => {
  test("maps snake_case fields", () => {
    const recipient = parseScheduledReportRecipient({
      id: RECIPIENT_ROW_ID,
      scheduled_report_id: SCHEDULE_ID,
      recipient_auth_user_id: ACTOR_ID,
      added_by_auth_user_id: ACTOR_ID,
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(recipient.recipientAuthUserId, ACTOR_ID);
  });
});

describe("parseScheduledReportRun", () => {
  test("maps a real run with reauthorization counts", () => {
    const run = parseScheduledReportRun({
      id: RUN_ID,
      scheduled_report_id: SCHEDULE_ID,
      job_id: JOB_ID,
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
    });
    assert.equal(run.recipientsReauthorized, 1);
    assert.equal(run.recipientsDenied, 1);
    assert.equal(run.jobId, JOB_ID);
  });
});

describe("CreateScheduledReportInputSchema", () => {
  test("defaults cronDayOfMonth/cronDayOfWeek to null and filters to empty", () => {
    const parsed = CreateScheduledReportInputSchema.parse({
      tenantId: TENANT_ID,
      reportTypeCode: "finance_billing_summary",
      name: "Daily Billing Summary",
      cronMinute: 30,
      cronHour: 9,
      timezone: "Asia/Jakarta",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.cronDayOfMonth, null);
    assert.equal(parsed.cronDayOfWeek, null);
    assert.deepEqual(parsed.filters, {});
  });

  test("rejects an out-of-range cronHour", () => {
    assert.throws(() =>
      CreateScheduledReportInputSchema.parse({
        tenantId: TENANT_ID,
        reportTypeCode: "finance_billing_summary",
        name: "x",
        cronMinute: 0,
        cronHour: 24,
        timezone: "Asia/Jakarta",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("ScheduledReportFiltersSchema", () => {
  test("accepts a flat bag of strings/numbers/booleans/nulls", () => {
    const parsed = ScheduledReportFiltersSchema.parse({ currency: "IDR", limit: 10 });
    assert.equal(parsed.currency, "IDR");
  });

  test("rejects a nested object value -- filters stay flat", () => {
    assert.throws(() => ScheduledReportFiltersSchema.parse({ nested: { a: 1 } }));
  });
});
