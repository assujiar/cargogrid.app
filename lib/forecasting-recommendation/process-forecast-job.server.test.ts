import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { processForecastJob, type ProcessForecastJobClient } from "./process-forecast-job.server.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "723e4567-e89b-12d3-a456-426614174000";

interface RecordedCalls {
  rpc: { fn: string; args: Record<string, unknown> }[];
}

function fakeClient(options: { apiUrl?: string | null; connectionStatus?: string; jobStatus?: string; recorded?: RecordedCalls }): ProcessForecastJobClient {
  const recorded = options.recorded ?? { rpc: [] };
  const connectionStatus = options.connectionStatus ?? "active";

  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      recorded.rpc.push({ fn, args });
      if (fn === "get_ai_governed_dispatch_info") {
        return { data: { connection_id: CONNECTION_ID, connection_status: connectionStatus, connection_config: options.apiUrl ? { apiUrl: options.apiUrl } : {} }, error: null };
      }
      if (fn === "get_ai_governed_credential") {
        return { data: "test-credential", error: null };
      }
      if (fn === "request_ai_governed_action") {
        return {
          data: {
            id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: args.p_connection_id, feature_code: args.p_feature_code,
            correlation_record_type: args.p_correlation_record_type ?? null, correlation_record_id: args.p_correlation_record_id ?? null,
            prompt_payload: args.p_prompt_payload, status: "pending", output_payload: null, confidence_label: null,
            model_version: null, provider_unit_cost_amount: null, currency: null, billed_amount: null, error_message: null,
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-22T00:00:00.000Z", completed_at: null,
          },
          error: null,
        };
      }
      if (fn === "record_ai_governed_request_outcome") {
        return {
          data: {
            id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, feature_code: "forecasting_recommendation",
            correlation_record_type: "forecast_job", correlation_record_id: JOB_ID, prompt_payload: {}, status: args.p_status,
            output_payload: args.p_output_payload ?? null, confidence_label: args.p_confidence_label ?? null,
            model_version: args.p_model_version ?? null, provider_unit_cost_amount: args.p_provider_unit_cost_amount ?? null,
            currency: args.p_currency ?? null, billed_amount: 0.02, error_message: args.p_error_message ?? null,
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-22T00:00:00.000Z",
            completed_at: "2026-08-22T00:01:00.000Z",
          },
          error: null,
        };
      }
      if (fn === "record_forecast_job_outcome") {
        return {
          data: {
            id: JOB_ID, tenant_id: TENANT_ID, forecast_type: "demand", scenario_label: "baseline",
            scope_snapshot: { segment: "jkt-fcl" }, feature_snapshot: { history_weeks: 26 }, horizon_days: 90,
            ai_governed_request_id: args.p_ai_governed_request_id, status: options.jobStatus ?? "succeeded",
            predicted_value: options.jobStatus === "failed" ? null : "48000", cohort_size: options.jobStatus === "failed" ? null : 250,
            is_small_cohort_suppressed: false, data_quality_note: null, requested_by: "test",
            created_at: "2026-08-22T00:00:00.000Z", completed_at: "2026-08-22T00:01:00.000Z",
          },
          error: null,
        };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as ProcessForecastJobClient;
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/infer` };
}

describe("processForecastJob", () => {
  test("a real succeeded dispatch syncs the job to succeeded with a real predicted_value", async () => {
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const parsed = JSON.parse(body);
        assert.equal(parsed.horizonDays, 90);
        assert.deepEqual(parsed.scopeSnapshot, { segment: "jkt-fcl" });
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ output: { predictedValue: 48000, cohortSize: 250 }, confidenceLabel: "high" }));
      });
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, jobStatus: "succeeded", recorded });
      const result = await processForecastJob(
        client,
        { tenantId: TENANT_ID, jobId: JOB_ID, scopeSnapshot: { segment: "jkt-fcl" }, featureSnapshot: { history_weeks: 26 }, horizonDays: 90, actorAuthUserId: ACTOR_ID, actorLabel: "rep" },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, true);
      assert.equal(result.requestId, REQUEST_ID);
      assert.equal(result.job.status, "succeeded");
      assert.equal(result.job.predictedValue, 48000);
      assert.ok(recorded.rpc.some((call) => call.fn === "record_forecast_job_outcome" && call.args.p_job_id === JOB_ID));
    } finally {
      server.close();
    }
  });

  test("a real dispatch failure still syncs the job -- to failed, never left pending", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, jobStatus: "failed", recorded });
      const result = await processForecastJob(
        client,
        { tenantId: TENANT_ID, jobId: JOB_ID, scopeSnapshot: {}, featureSnapshot: {}, horizonDays: 30, actorAuthUserId: ACTOR_ID, actorLabel: "rep" },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /HTTP 503/);
      assert.equal(result.job.status, "failed");
      assert.equal(result.job.predictedValue, null);
    } finally {
      server.close();
    }
  });

  test("no active connection configured -- throws before any job sync is attempted", async () => {
    const recorded: RecordedCalls = { rpc: [] };
    const client = fakeClient({ connectionStatus: "inactive", recorded });
    await assert.rejects(() =>
      processForecastJob(client, { tenantId: TENANT_ID, jobId: JOB_ID, scopeSnapshot: {}, featureSnapshot: {}, horizonDays: 30, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }, ALLOW_ALL_URLS),
    );
    assert.ok(!recorded.rpc.some((call) => call.fn === "record_forecast_job_outcome"));
  });
});
