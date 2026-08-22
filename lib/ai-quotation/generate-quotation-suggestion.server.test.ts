import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { generateAiQuotationSuggestion, GenerateAiQuotationSuggestionError, type GenerateAiQuotationSuggestionClient } from "./generate-quotation-suggestion.server.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "723e4567-e89b-12d3-a456-426614174000";
const COSTING_REQUEST_ID = "823e4567-e89b-12d3-a456-426614174000";
const RATE_SELECTION_ID = "923e4567-e89b-12d3-a456-426614174000";
const MARGIN_CALCULATION_ID = "a23e4567-e89b-12d3-a456-426614174000";
const RULE_VERSION_ID = "b23e4567-e89b-12d3-a456-426614174000";
const SUGGESTION_ID = "c23e4567-e89b-12d3-a456-426614174000";

const PROMPT_CONTEXT_ROW = {
  opportunity_name: "Contoso freight lane",
  opportunity_stage: "ready_for_costing",
  opportunity_value_amount: 5000,
  opportunity_value_currency: "USD",
  opportunity_requirements: { origin: "JKT", destination: "SIN" },
  costing_request_id: COSTING_REQUEST_ID,
  margin_calculation_id: MARGIN_CALCULATION_ID,
  rate_selection_id: RATE_SELECTION_ID,
  rule_version_id: RULE_VERSION_ID,
  sell_amount: 500,
  sell_currency: "USD",
  margin_pct: 20,
};

const PROMPT_CONTEXT_NO_MARGIN_ROW = {
  opportunity_name: "Contoso freight lane",
  opportunity_stage: "ready_for_costing",
  opportunity_value_amount: 5000,
  opportunity_value_currency: "USD",
  opportunity_requirements: { origin: "JKT", destination: "SIN" },
  costing_request_id: null,
  margin_calculation_id: null,
  rate_selection_id: null,
  rule_version_id: null,
  sell_amount: null,
  sell_currency: null,
  margin_pct: null,
};

interface RecordedCalls {
  rpc: { fn: string; args: Record<string, unknown> }[];
}

function fakeClient(options: {
  contextRows?: Record<string, unknown>[];
  apiUrl?: string | null;
  connectionStatus?: string;
  recorded?: RecordedCalls;
}): GenerateAiQuotationSuggestionClient {
  const recorded = options.recorded ?? { rpc: [] };
  const contextRows = options.contextRows ?? [PROMPT_CONTEXT_ROW];
  const connectionStatus = options.connectionStatus ?? "active";

  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      recorded.rpc.push({ fn, args });
      if (fn === "get_ai_quotation_prompt_context") {
        return { data: contextRows, error: null };
      }
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
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-21T00:00:00.000Z", completed_at: null,
          },
          error: null,
        };
      }
      if (fn === "record_ai_governed_request_outcome") {
        return {
          data: {
            id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, feature_code: "ai_assisted_quotation",
            correlation_record_type: "opportunity", correlation_record_id: OPPORTUNITY_ID, prompt_payload: {}, status: args.p_status,
            output_payload: args.p_output_payload ?? null, confidence_label: args.p_confidence_label ?? null,
            model_version: args.p_model_version ?? null, provider_unit_cost_amount: args.p_provider_unit_cost_amount ?? null,
            currency: args.p_currency ?? null, billed_amount: 0.02, error_message: args.p_error_message ?? null,
            approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-21T00:00:00.000Z",
            completed_at: "2026-08-21T00:01:00.000Z",
          },
          error: null,
        };
      }
      if (fn === "record_ai_quotation_suggestion") {
        return {
          data: {
            id: SUGGESTION_ID, tenant_id: TENANT_ID, opportunity_id: OPPORTUNITY_ID, ai_governed_request_id: args.p_ai_governed_request_id,
            status: "pending", accepted_quotation_id: null, dismiss_reason: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test",
            reviewed_by_auth_user_id: null, reviewed_by: null, reviewed_at: null, created_at: "2026-08-21T00:00:00.000Z",
          },
          error: null,
        };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as GenerateAiQuotationSuggestionClient;
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/infer` };
}

describe("generateAiQuotationSuggestion", () => {
  test("a real succeeded dispatch tracks a pending suggestion and cites the real margin source returned by get_ai_quotation_prompt_context", async () => {
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const parsed = JSON.parse(body);
        assert.deepEqual(parsed.opportunity.id, OPPORTUNITY_ID);
        assert.equal(parsed.opportunity.name, "Contoso freight lane");
        assert.deepEqual(parsed.costingRequestId, COSTING_REQUEST_ID);
        assert.equal(parsed.marginCalculations.length, 1);
        assert.equal(parsed.marginCalculations[0].marginCalculationId, MARGIN_CALCULATION_ID);
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ output: { draftLines: [{ description: "Ocean freight JKT-SIN" }] }, confidenceLabel: "high" }));
      });
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, recorded });
      const result = await generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS);

      assert.equal(result.success, true);
      assert.equal(result.requestId, REQUEST_ID);
      assert.equal(result.suggestion?.status, "pending");
      assert.equal(result.suggestion?.aiGovernedRequestId, REQUEST_ID);
      assert.ok(recorded.rpc.some((call) => call.fn === "get_ai_quotation_prompt_context" && call.args.p_actor_auth_user_id === ACTOR_ID));
      assert.ok(recorded.rpc.some((call) => call.fn === "record_ai_quotation_suggestion"));
    } finally {
      server.close();
    }
  });

  test("no current costing/margin evidence yet -- dispatches with an empty marginCalculations array rather than fabricating a source", async () => {
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const parsed = JSON.parse(body);
        assert.equal(parsed.costingRequestId, null);
        assert.deepEqual(parsed.marginCalculations, []);
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ output: { draftLines: [] }, confidenceLabel: "low" }));
      });
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, contextRows: [PROMPT_CONTEXT_NO_MARGIN_ROW], recorded });
      const result = await generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS);
      assert.equal(result.success, true);
      assert.equal(result.suggestion?.status, "pending");
    } finally {
      server.close();
    }
  });

  test("multiple margin sources returned by get_ai_quotation_prompt_context are all cited", async () => {
    const secondRow = { ...PROMPT_CONTEXT_ROW, margin_calculation_id: "d23e4567-e89b-12d3-a456-426614174000", rate_selection_id: "e23e4567-e89b-12d3-a456-426614174000" };
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const parsed = JSON.parse(body);
        assert.equal(parsed.marginCalculations.length, 2);
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ output: { draftLines: [] }, confidenceLabel: "medium" }));
      });
    });
    try {
      const client = fakeClient({ apiUrl: url, contextRows: [PROMPT_CONTEXT_ROW, secondRow] });
      const result = await generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS);
      assert.equal(result.success, true);
    } finally {
      server.close();
    }
  });

  test("a real dispatch failure returns success:false and never calls record_ai_quotation_suggestion", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { rpc: [] };
      const client = fakeClient({ apiUrl: url, recorded });
      const result = await generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS);

      assert.equal(result.success, false);
      assert.equal(result.suggestion, null);
      assert.match(result.errorMessage ?? "", /HTTP 503/);
      assert.ok(!recorded.rpc.some((call) => call.fn === "record_ai_quotation_suggestion"));
    } finally {
      server.close();
    }
  });

  test("a non-existent (or record-inaccessible/unauthorized) opportunity -- get_ai_quotation_prompt_context returns zero rows -- throws before any dispatch is attempted", async () => {
    const recorded: RecordedCalls = { rpc: [] };
    const client = fakeClient({ contextRows: [], recorded });
    await assert.rejects(() => generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS), GenerateAiQuotationSuggestionError);
    assert.ok(!recorded.rpc.some((call) => call.fn === "get_ai_governed_dispatch_info" || call.fn === "request_ai_governed_action"));
  });
});
