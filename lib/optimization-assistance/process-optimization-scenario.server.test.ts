import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { processOptimizationScenario, type ProcessOptimizationScenarioClient } from "./process-optimization-scenario.server.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SCENARIO_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "723e4567-e89b-12d3-a456-426614174000";

interface RecordedCalls {
  rpc: { fn: string; args: Record<string, unknown> }[];
}

function fakeClient(options: { apiUrl?: string | null; connectionStatus?: string; scenarioStatus?: string; recorded?: RecordedCalls }): ProcessOptimizationScenarioClient {
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
            id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, feature_code: "optimization_assistance",
            correlation_record_type: "optimization_scenario", correlation_record_id: SCENARIO_ID, prompt_payload: {}, status: args.p_status,
            output_payload: args.p_output_payload ?? null, confidence_label: args.p_confidence_label ?? null,
            model_version: args.p_model_version ?? null, provider_unit_cost_amount: args.p_provider_unit_cost_amount ?? null,
            currency: args.p_currency ?? null, billed_amount: 0.02, error_message: args.p_error_message ?? null,
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-22T00:00:00.000Z",
            completed_at: "2026-08-22T00:01:00.000Z",
          },
          error: null,
        };
      }
      if (fn === "record_optimization_scenario_outcome") {
        return {
          data: {
            id: SCENARIO_ID, tenant_id: TENANT_ID, scope_type: "route", input_snapshot: { stops: 5 }, constraint_set: { max_hours: 8 },
            ai_governed_request_id: args.p_ai_governed_request_id, status: options.scenarioStatus ?? "succeeded", is_stale: false,
            stale_reason: null, requested_by: "test", created_at: "2026-08-22T00:00:00.000Z", completed_at: "2026-08-22T00:01:00.000Z",
          },
          error: null,
        };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as ProcessOptimizationScenarioClient;
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/infer` };
}

describe("processOptimizationScenario", () => {
  test("a real succeeded dispatch syncs the scenario to succeeded", async () => {
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const parsed = JSON.parse(body);
        assert.deepEqual(parsed.inputSnapshot, { stops: 5 });
        assert.deepEqual(parsed.constraintSet, { max_hours: 8 });
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ output: { recommendations: [{ label: "Reorder stops 2/3" }] }, confidenceLabel: "high" }));
      });
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, scenarioStatus: "succeeded", recorded });
      const result = await processOptimizationScenario(
        client,
        { tenantId: TENANT_ID, scenarioId: SCENARIO_ID, inputSnapshot: { stops: 5 }, constraintSet: { max_hours: 8 }, actorAuthUserId: ACTOR_ID, actorLabel: "rep" },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, true);
      assert.equal(result.requestId, REQUEST_ID);
      assert.equal(result.scenario.status, "succeeded");
      assert.ok(recorded.rpc.some((call) => call.fn === "record_optimization_scenario_outcome" && call.args.p_scenario_id === SCENARIO_ID));
    } finally {
      server.close();
    }
  });

  test("a real dispatch failure still syncs the scenario -- to failed, never left pending", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, scenarioStatus: "failed", recorded });
      const result = await processOptimizationScenario(
        client,
        { tenantId: TENANT_ID, scenarioId: SCENARIO_ID, inputSnapshot: { stops: 5 }, constraintSet: { max_hours: 8 }, actorAuthUserId: ACTOR_ID, actorLabel: "rep" },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /HTTP 503/);
      assert.equal(result.scenario.status, "failed");
    } finally {
      server.close();
    }
  });

  test("no active connection configured -- throws before any scenario sync is attempted", async () => {
    const recorded: RecordedCalls = { rpc: [] };
    const client = fakeClient({ connectionStatus: "inactive", recorded });
    await assert.rejects(() =>
      processOptimizationScenario(client, { tenantId: TENANT_ID, scenarioId: SCENARIO_ID, inputSnapshot: { stops: 5 }, constraintSet: {}, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }, ALLOW_ALL_URLS),
    );
    assert.ok(!recorded.rpc.some((call) => call.fn === "record_optimization_scenario_outcome"));
  });
});
