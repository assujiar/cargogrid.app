import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createScheduledReport,
  setScheduledReportStatus,
  addScheduledReportRecipient,
  removeScheduledReportRecipient,
  runScheduledReport,
  ScheduledReportMutationError,
  type ScheduledReportMutationRpcClient,
} from "./scheduled-report.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const SCHEDULE_ID = "423e4567-e89b-12d3-a456-426614174000";
const RECIPIENT_ROW_ID = "523e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "623e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "723e4567-e89b-12d3-a456-426614174000";

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
  id: RECIPIENT_ROW_ID,
  scheduled_report_id: SCHEDULE_ID,
  recipient_auth_user_id: ACTOR_ID,
  added_by_auth_user_id: ACTOR_ID,
  created_at: "2026-08-21T00:00:00.000Z",
};

const VALID_RUN_ROW = {
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
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ScheduledReportMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ScheduledReportMutationRpcClient;
  return { client, calls };
}

describe("createScheduledReport", () => {
  test("calls create_scheduled_report with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_SCHEDULE_ROW, error: null });
    const schedule = await createScheduledReport(client, {
      tenantId: TENANT_ID,
      reportTypeCode: "finance_billing_summary",
      name: "Daily Billing Summary",
      cronMinute: 30,
      cronHour: 9,
      timezone: "Asia/Jakarta",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "create_scheduled_report");
    assert.equal(calls[0]?.args.p_timezone, "Asia/Jakarta");
    assert.equal(schedule.status, "active");
  });

  test("classifies scheduled_report_invalid_cron", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "scheduled_report_invalid_cron: day_of_month and day_of_week may not both be set" } });
    await assert.rejects(
      () =>
        createScheduledReport(client, {
          tenantId: TENANT_ID,
          reportTypeCode: "finance_billing_summary",
          name: "x",
          cronMinute: 0,
          cronHour: 9,
          cronDayOfMonth: 15,
          cronDayOfWeek: 1,
          timezone: "Asia/Jakarta",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ScheduledReportMutationError);
        assert.equal(err.code, "scheduled_report_invalid_cron");
        return true;
      },
    );
  });
});

describe("setScheduledReportStatus", () => {
  test("calls set_scheduled_report_status with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_SCHEDULE_ROW, status: "paused" }, error: null });
    const schedule = await setScheduledReportStatus(client, { scheduledReportId: SCHEDULE_ID, status: "paused", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "set_scheduled_report_status");
    assert.equal(calls[0]?.args.p_status, "paused");
    assert.equal(schedule.status, "paused");
  });
});

describe("addScheduledReportRecipient", () => {
  test("calls add_scheduled_report_recipient and returns the new recipient row", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_RECIPIENT_ROW, error: null });
    const recipient = await addScheduledReportRecipient(client, { scheduledReportId: SCHEDULE_ID, recipientAuthUserId: ACTOR_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "add_scheduled_report_recipient");
    assert.equal(recipient.recipientAuthUserId, ACTOR_ID);
  });

  test("classifies scheduled_report_recipient_not_member", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "scheduled_report_recipient_not_member: no active membership" } });
    await assert.rejects(
      () => addScheduledReportRecipient(client, { scheduledReportId: SCHEDULE_ID, recipientAuthUserId: ACTOR_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ScheduledReportMutationError);
        assert.equal(err.code, "scheduled_report_recipient_not_member");
        return true;
      },
    );
  });
});

describe("removeScheduledReportRecipient", () => {
  test("calls remove_scheduled_report_recipient with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await removeScheduledReportRecipient(client, { recipientRowId: RECIPIENT_ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "remove_scheduled_report_recipient");
    assert.equal(calls[0]?.args.p_recipient_row_id, RECIPIENT_ROW_ID);
  });
});

describe("runScheduledReport", () => {
  test("calls run_scheduled_report and returns real reauthorization counts", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_RUN_ROW, error: null });
    const run = await runScheduledReport(client, { scheduledReportId: SCHEDULE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "run_scheduled_report");
    assert.equal(run.recipientsReauthorized, 1);
    assert.equal(run.recipientsDenied, 1);
  });

  test("classifies scheduled_report_not_active", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "scheduled_report_not_active: schedule is paused" } });
    await assert.rejects(
      () => runScheduledReport(client, { scheduledReportId: SCHEDULE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ScheduledReportMutationError);
        assert.equal(err.code, "scheduled_report_not_active");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () => runScheduledReport(client, { scheduledReportId: SCHEDULE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ScheduledReportMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
