import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  recordReportRun,
  enqueueReportExport,
  cancelReportRun,
  publishReportTypeVersion,
  ReportMutationError,
  type ReportMutationRpcClient,
} from "./report.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_PREVIEW_RUN_ROW = {
  id: RUN_ID,
  tenant_id: TENANT_ID,
  report_type_code: "lead_aging",
  run_type: "preview",
  status: "completed",
  parameters: {},
  row_count: 4,
  masked_columns: [],
  job_id: null,
  file_id: null,
  error_reason: null,
  requested_by_auth_user_id: ACTOR_ID,
  created_by: "tester",
  requested_at: "2026-07-26T00:00:00.000Z",
  completed_at: "2026-07-26T00:00:01.000Z",
};

const VALID_EXPORT_RUN_ROW = {
  ...VALID_PREVIEW_RUN_ROW,
  run_type: "export",
  status: "queued",
  job_id: JOB_ID,
  row_count: null,
  completed_at: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ReportMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ReportMutationRpcClient;
  return { client, calls };
}

describe("recordReportRun", () => {
  test("calls record_report_run with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_PREVIEW_RUN_ROW, error: null });
    const run = await recordReportRun(client, {
      tenantId: TENANT_ID,
      reportTypeCode: "lead_aging",
      rowCount: 4,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "record_report_run");
    assert.equal(calls[0]?.args.p_report_type_code, "lead_aging");
    assert.equal(calls[0]?.args.p_row_count, 4);
    assert.deepEqual(calls[0]?.args.p_masked_columns, []);
    assert.equal(run.status, "completed");
  });

  test("classifies a known error code from the RPC's own message prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "report_type_retired: lead_aging is retired" } });
    await assert.rejects(
      () => recordReportRun(client, { tenantId: TENANT_ID, reportTypeCode: "lead_aging", rowCount: 0, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ReportMutationError);
        assert.equal(err.code, "report_type_retired");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () => recordReportRun(client, { tenantId: TENANT_ID, reportTypeCode: "lead_aging", rowCount: 0, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ReportMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("enqueueReportExport", () => {
  test("calls enqueue_report_export and returns the queued run with its job id", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_EXPORT_RUN_ROW, error: null });
    const run = await enqueueReportExport(client, {
      tenantId: TENANT_ID,
      reportTypeCode: "pipeline_summary",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "enqueue_report_export");
    assert.equal(run.runType, "export");
    assert.equal(run.status, "queued");
    assert.equal(run.jobId, JOB_ID);
  });

  test("classifies insufficient_authority (missing COM:Export)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks COM:Export" } });
    await assert.rejects(
      () => enqueueReportExport(client, { tenantId: TENANT_ID, reportTypeCode: "pipeline_summary", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ReportMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("cancelReportRun", () => {
  test("calls cancel_report_run with the exact snake_case params and returns the cancelled run", async () => {
    const { client, calls } = fakeRpcClient({
      data: { ...VALID_EXPORT_RUN_ROW, status: "failed", error_reason: "cancelled_by_requester", completed_at: "2026-07-26T00:00:02.000Z" },
      error: null,
    });
    const run = await cancelReportRun(client, { runId: RUN_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "cancel_report_run");
    assert.equal(calls[0]?.args.p_run_id, RUN_ID);
    assert.equal(run.status, "failed");
    assert.equal(run.errorReason, "cancelled_by_requester");
  });

  test("classifies report_run_not_cancellable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "report_run_not_cancellable: status is completed" } });
    await assert.rejects(
      () => cancelReportRun(client, { runId: RUN_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ReportMutationError);
        assert.equal(err.code, "report_run_not_cancellable");
        return true;
      },
    );
  });
});

describe("publishReportTypeVersion", () => {
  test("calls publish_report_type_version with the exact snake_case params and returns the new version", async () => {
    const versionRow = {
      id: "623e4567-e89b-12d3-a456-426614174000",
      report_type_code: "lead_aging",
      version_number: 2,
      source_function: "get_dashboard_lead_aging",
      parameter_schema: { currency: { type: "string", required: true } },
      description: "v2",
      published_by_auth_user_id: ACTOR_ID,
      published_by: "tester",
      published_at: "2026-08-21T00:00:00.000Z",
    };
    const { client, calls } = fakeRpcClient({ data: versionRow, error: null });
    const version = await publishReportTypeVersion(client, {
      code: "lead_aging",
      sourceFunction: "get_dashboard_lead_aging",
      parameterSchema: { currency: { type: "string", required: true } },
      description: "v2",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "publish_report_type_version");
    assert.equal(calls[0]?.args.p_code, "lead_aging");
    assert.equal(version.versionNumber, 2);
  });

  test("classifies insufficient_authority (not Supreme Admin)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may publish a report type version" } });
    await assert.rejects(
      () =>
        publishReportTypeVersion(client, {
          code: "lead_aging",
          sourceFunction: "get_dashboard_lead_aging",
          parameterSchema: {},
          description: "v2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ReportMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});
