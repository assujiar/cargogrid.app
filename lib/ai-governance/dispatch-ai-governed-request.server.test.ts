import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { dispatchAiGovernedRequest, type DispatchAiGovernedRequestRpcClient } from "./dispatch-ai-governed-request.server.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";

interface RecordedCalls {
  requested: Record<string, unknown>[];
  outcomes: Record<string, unknown>[];
}

function mockClient(apiUrl: string | null, dispatchOverrides: Record<string, unknown> = {}, recorded: RecordedCalls = { requested: [], outcomes: [] }, credential: string | null = "test-credential-value"): DispatchAiGovernedRequestRpcClient {
  return {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      if (fn === "get_ai_governed_dispatch_info") {
        return { data: { connection_id: CONNECTION_ID, connection_status: "active", connection_config: apiUrl ? { apiUrl } : {}, ...dispatchOverrides }, error: null };
      }
      if (fn === "get_ai_governed_credential") {
        return { data: credential, error: null };
      }
      if (fn === "request_ai_governed_action") {
        recorded.requested.push(args);
        return {
          data: {
            id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: args.p_connection_id, feature_code: args.p_feature_code,
            correlation_record_type: args.p_correlation_record_type ?? null, correlation_record_id: args.p_correlation_record_id ?? null,
            prompt_payload: args.p_prompt_payload, status: "pending", output_payload: null, confidence_label: null,
            model_version: null, provider_unit_cost_amount: null, currency: null, billed_amount: null, error_message: null,
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-21T00:00:00.000Z", completed_at: null,
          },
          error: null,
        };
      }
      if (fn === "record_ai_governed_request_outcome") {
        recorded.outcomes.push(args);
        return {
          data: {
            id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, feature_code: "quotation_draft",
            correlation_record_type: null, correlation_record_id: null, prompt_payload: {}, status: args.p_status,
            output_payload: args.p_output_payload ?? null, confidence_label: args.p_confidence_label ?? null,
            model_version: args.p_model_version ?? null, provider_unit_cost_amount: args.p_provider_unit_cost_amount ?? null,
            currency: args.p_currency ?? null, billed_amount: null, error_message: args.p_error_message ?? null,
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-21T00:00:00.000Z",
            completed_at: "2026-08-21T00:01:00.000Z",
          },
          error: null,
        };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as DispatchAiGovernedRequestRpcClient;
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/infer` };
}

describe("dispatchAiGovernedRequest", () => {
  test("a real 2xx provider response with a valid output object succeeds and records a real cost", async () => {
    const received: { headers: Record<string, string | string[] | undefined>; body: string }[] = [];
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        received.push({ headers: req.headers, body });
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ output: { draftLines: [{ description: "Freight" }] }, confidenceLabel: "high" }));
      });
    });
    try {
      const recorded: RecordedCalls = { requested: [], outcomes: [] };
      const client = mockClient(url, {}, recorded);
      const result = await dispatchAiGovernedRequest(
        client,
        { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", featureCode: "quotation_draft", correlationRecordType: null, correlationRecordId: null, promptPayload: { origin: "JKT" } },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, true);
      assert.equal(result.requestId, REQUEST_ID);
      assert.deepEqual(result.outputPayload, { draftLines: [{ description: "Freight" }] });
      assert.equal(result.confidenceLabel, "high");
      assert.equal(recorded.requested.length, 1);
      assert.equal(recorded.outcomes.length, 1);
      assert.equal(recorded.outcomes[0]?.p_status, "succeeded");
      assert.ok((recorded.outcomes[0]?.p_provider_unit_cost_amount as number) > 0);
      assert.equal(received[0]?.headers["authorization"], "Bearer test-credential-value");
      assert.deepEqual(JSON.parse(received[0]!.body), { origin: "JKT" });
    } finally {
      server.close();
    }
  });

  test("a real non-2xx provider response fails cleanly and still records the outcome", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { requested: [], outcomes: [] };
      const client = mockClient(url, {}, recorded);
      const result = await dispatchAiGovernedRequest(
        client,
        { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", featureCode: "quotation_draft", correlationRecordType: null, correlationRecordId: null, promptPayload: {} },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /HTTP 503/);
      assert.equal(recorded.outcomes[0]?.p_status, "failed");
    } finally {
      server.close();
    }
  });

  test("a real network-level failure is classified as a failure, not an uncaught throw", async () => {
    const recorded: RecordedCalls = { requested: [], outcomes: [] };
    const client = mockClient("http://127.0.0.1:1/unreachable", {}, recorded);
    const result = await dispatchAiGovernedRequest(
      client,
      { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", featureCode: "quotation_draft", correlationRecordType: null, correlationRecordId: null, promptPayload: {} },
      ALLOW_ALL_URLS,
    );

    assert.equal(result.success, false);
    assert.ok(result.errorMessage);
    assert.equal(recorded.outcomes[0]?.p_status, "failed");
  });

  test("no active connection throws instead of recording a request with nothing to dispatch through", async () => {
    let called = false;
    const { server, url } = await startServer((_req, res) => {
      called = true;
      res.writeHead(200);
      res.end();
    });
    try {
      const recorded: RecordedCalls = { requested: [], outcomes: [] };
      const client = mockClient(url, { connection_status: "disabled" }, recorded);
      await assert.rejects(
        () =>
          dispatchAiGovernedRequest(
            client,
            { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", featureCode: "quotation_draft", correlationRecordType: null, correlationRecordId: null, promptPayload: {} },
            ALLOW_ALL_URLS,
          ),
        /no active openai_multimodal connection/,
      );
      assert.equal(called, false);
      assert.equal(recorded.requested.length, 0);
    } finally {
      server.close();
    }
  });

  test("a malformed provider response (missing output) fails cleanly", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ confidenceLabel: "low" }));
    });
    try {
      const recorded: RecordedCalls = { requested: [], outcomes: [] };
      const client = mockClient(url, {}, recorded);
      const result = await dispatchAiGovernedRequest(
        client,
        { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", featureCode: "quotation_draft", correlationRecordType: null, correlationRecordId: null, promptPayload: {} },
        ALLOW_ALL_URLS,
      );

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /missing an output object/);
    } finally {
      server.close();
    }
  });

  test("the REAL (non-injected) SSRF guard refuses a literal private-IP provider apiUrl without attempting a live HTTP call", async () => {
    const recorded: RecordedCalls = { requested: [], outcomes: [] };
    const client = mockClient("https://169.254.169.254/latest/meta-data/", {}, recorded);
    const result = await dispatchAiGovernedRequest(client, {
      tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", featureCode: "quotation_draft", correlationRecordType: null, correlationRecordId: null, promptPayload: {},
    });

    assert.equal(result.success, false);
    assert.match(result.errorMessage ?? "", /refusing to dispatch/);
  });
});
