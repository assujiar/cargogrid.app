import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { enqueueOpsReportExport, type OpsReportMutationRpcClient } from "./ops-report.ts";
import { ReportMutationError } from "./report.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_EXPORT_RUN_ROW = {
  id: RUN_ID,
  tenant_id: TENANT_ID,
  report_type_code: "cost_variance_summary",
  run_type: "export",
  status: "queued",
  parameters: {},
  row_count: null,
  masked_columns: [],
  job_id: JOB_ID,
  file_id: null,
  error_reason: null,
  requested_by_auth_user_id: ACTOR_ID,
  created_by: "tester",
  requested_at: "2026-07-28T00:00:00.000Z",
  completed_at: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: OpsReportMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as OpsReportMutationRpcClient;
  return { client, calls };
}

describe("enqueueOpsReportExport", () => {
  test("calls enqueue_ops_report_export with the exact snake_case params and returns the queued run with its job id", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_EXPORT_RUN_ROW, error: null });
    const run = await enqueueOpsReportExport(client, {
      tenantId: TENANT_ID,
      reportTypeCode: "cost_variance_summary",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "enqueue_ops_report_export");
    assert.equal(calls[0]?.args.p_report_type_code, "cost_variance_summary");
    assert.equal(run.runType, "export");
    assert.equal(run.status, "queued");
    assert.equal(run.jobId, JOB_ID);
  });

  test("classifies insufficient_authority (missing OPS:Export)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:Export" } });
    await assert.rejects(
      () => enqueueOpsReportExport(client, { tenantId: TENANT_ID, reportTypeCode: "cost_variance_summary", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ReportMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies report_type_retired", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "report_type_retired: epod_completion_summary is retired and can no longer be exported" } });
    await assert.rejects(
      () => enqueueOpsReportExport(client, { tenantId: TENANT_ID, reportTypeCode: "epod_completion_summary", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
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
      () => enqueueOpsReportExport(client, { tenantId: TENANT_ID, reportTypeCode: "cost_variance_summary", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ReportMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
