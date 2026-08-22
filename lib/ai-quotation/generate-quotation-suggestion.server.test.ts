import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { generateAiQuotationSuggestion, GenerateAiQuotationSuggestionError, type GenerateAiQuotationSuggestionClient } from "./generate-quotation-suggestion.server.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "723e4567-e89b-12d3-a456-426614174000";
const COSTING_REQUEST_ID = "823e4567-e89b-12d3-a456-426614174000";
const RATE_SELECTION_ID = "923e4567-e89b-12d3-a456-426614174000";
const MARGIN_CALCULATION_ID = "a23e4567-e89b-12d3-a456-426614174000";
const RULE_VERSION_ID = "b23e4567-e89b-12d3-a456-426614174000";
const SUGGESTION_ID = "c23e4567-e89b-12d3-a456-426614174000";

const OPPORTUNITY_ROW = {
  id: OPPORTUNITY_ID,
  tenant_id: TENANT_ID,
  prospect_id: PROSPECT_ID,
  account_ref: null,
  name: "Contoso freight lane",
  stage: "ready_for_costing",
  probability: 60,
  value_amount: 5000,
  value_currency: "USD",
  value_masked: false,
  requirements: { origin: "JKT", destination: "SIN" },
  next_action: null,
  next_action_due_at: null,
  close_reason: null,
  cloned_from_id: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

const COSTING_REQUEST_ROW = {
  id: COSTING_REQUEST_ID,
  tenant_id: TENANT_ID,
  opportunity_id: OPPORTUNITY_ID,
  source_opportunity_version: 1,
  requirements_snapshot: {},
  status: "responded",
  due_at: null,
  assignee_user_id: null,
  cancel_reason: null,
  revised_from_id: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-02T00:00:00.000Z",
  updated_at: "2026-08-02T00:00:00.000Z",
};

const MARGIN_CALCULATION_ROW = {
  id: MARGIN_CALCULATION_ID,
  tenant_id: TENANT_ID,
  costing_request_id: COSTING_REQUEST_ID,
  rate_selection_id: RATE_SELECTION_ID,
  cost_amount: 400,
  cost_currency: "USD",
  sell_amount: 500,
  sell_currency: "USD",
  discount_pct: 0,
  discount_amount: 0,
  net_sell_amount: 500,
  margin_amount: 100,
  margin_pct: 20,
  markup_pct: 25,
  cost_masked: false,
  sell_masked: false,
  rule_version_id: RULE_VERSION_ID,
  minimum_margin_pct_snapshot: 10,
  rounding_mode_snapshot: "half_up",
  threshold_outcome: "pass",
  is_overridden: false,
  override_reason: null,
  override_by: null,
  override_at: null,
  is_current: true,
  superseded_by_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

interface RecordedCalls {
  rpc: { fn: string; args: Record<string, unknown> }[];
}

function eqNode(response: { data: unknown; error: { message: string } | null }) {
  return {
    order() {
      return response;
    },
    async maybeSingle() {
      const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
      return { data: row, error: response.error };
    },
  };
}

function fakeClient(options: {
  opportunity?: { data: unknown; error: { message: string } | null };
  costingRequests?: { data: unknown; error: { message: string } | null };
  marginCalculations?: { data: unknown; error: { message: string } | null };
  apiUrl?: string | null;
  connectionStatus?: string;
  recorded?: RecordedCalls;
}): GenerateAiQuotationSuggestionClient {
  const recorded = options.recorded ?? { rpc: [] };
  const opportunity = options.opportunity ?? { data: OPPORTUNITY_ROW, error: null };
  const costingRequests = options.costingRequests ?? { data: [COSTING_REQUEST_ROW], error: null };
  const marginCalculations = options.marginCalculations ?? { data: [MARGIN_CALCULATION_ROW], error: null };
  const connectionStatus = options.connectionStatus ?? "active";

  return {
    from(table: string) {
      if (table === "opportunities_directory") {
        return { select: () => ({ eq: () => eqNode(opportunity) }) };
      }
      if (table === "costing_requests") {
        return { select: () => ({ eq: () => eqNode(costingRequests) }) };
      }
      if (table === "margin_calculations_directory") {
        return { select: () => ({ eq: () => eqNode(marginCalculations) }) };
      }
      throw new Error(`unexpected table: ${table}`);
    },
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
  test("a real succeeded dispatch tracks a pending suggestion and cites the real, current margin calculation as a source", async () => {
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const parsed = JSON.parse(body);
        assert.deepEqual(parsed.opportunity.id, OPPORTUNITY_ID);
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
      assert.ok(recorded.rpc.some((call) => call.fn === "record_ai_quotation_suggestion"));
    } finally {
      server.close();
    }
  });

  test("no current costing evidence yet -- dispatches with an empty marginCalculations array rather than fabricating a source", async () => {
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
      const client = fakeClient({ apiUrl: url, costingRequests: { data: [], error: null }, recorded });
      const result = await generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS);
      assert.equal(result.success, true);
      assert.equal(result.suggestion?.status, "pending");
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

  test("an opportunity that does not belong to the tenant throws before any dispatch is attempted", async () => {
    const recorded: RecordedCalls = { rpc: [] };
    const client = fakeClient({ opportunity: { data: { ...OPPORTUNITY_ROW, tenant_id: "d23e4567-e89b-12d3-a456-426614174000" }, error: null }, recorded });
    await assert.rejects(() => generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS), GenerateAiQuotationSuggestionError);
    assert.equal(recorded.rpc.length, 0);
  });

  test("a non-existent opportunity throws", async () => {
    const client = fakeClient({ opportunity: { data: null, error: null } });
    await assert.rejects(() => generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS), GenerateAiQuotationSuggestionError);
  });

  test("only CURRENT margin calculations are cited -- a superseded one is excluded from the prompt", async () => {
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const parsed = JSON.parse(body);
        assert.deepEqual(parsed.marginCalculations, []);
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ output: { draftLines: [] }, confidenceLabel: "low" }));
      });
    });
    try {
      const client = fakeClient({ apiUrl: url, marginCalculations: { data: [{ ...MARGIN_CALCULATION_ROW, is_current: false }], error: null } });
      const result = await generateAiQuotationSuggestion(client, { tenantId: TENANT_ID, opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "sales rep" }, ALLOW_ALL_URLS);
      assert.equal(result.success, true);
    } finally {
      server.close();
    }
  });
});
