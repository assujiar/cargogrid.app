import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listCostingRequestsForOpportunity,
  getCostingRequestById,
  listCostingRequestComponents,
  listCostingResponsesForRequest,
  listCostingResponseComponents,
  CostingQueryError,
  type CostingQueryTableClient,
} from "./costing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "323e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "423e4567-e89b-12d3-a456-426614174000";
const COMPONENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESPONSE_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  opportunity_id: OPPORTUNITY_ID,
  source_opportunity_version: 1,
  requirements_snapshot: {},
  status: "pending",
  due_at: null,
  assignee_user_id: null,
  cancel_reason: null,
  revised_from_id: null,
  owner_user_id: null,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

const VALID_COMPONENT_ROW = {
  id: COMPONENT_ID,
  tenant_id: TENANT_ID,
  costing_request_id: REQUEST_ID,
  component_code: "ocean_freight",
  description: null,
  quantity: null,
  unit: null,
  created_at: "2026-07-24T00:00:00.000Z",
};

const VALID_RESPONSE_ROW = {
  id: RESPONSE_ID,
  tenant_id: TENANT_ID,
  costing_request_id: REQUEST_ID,
  source_type: "internal",
  vendor_ref: null,
  currency: "IDR",
  total_amount: 17500000,
  cost_masked: false,
  effective_at: "2026-07-24T00:00:00.000Z",
  expiry_at: null,
  is_expired: false,
  submitted_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
};

const VALID_RESPONSE_COMPONENT_ROW = {
  id: "723e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  costing_response_id: RESPONSE_ID,
  costing_request_component_id: COMPONENT_ID,
  amount: 15000000,
  created_at: "2026-07-24T00:00:00.000Z",
};

const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeTableClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): CostingQueryTableClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.rpcFn = fn;
      capture.calls.rpcArgs = args;
      return response;
    },
  };
  return fake as unknown as CostingQueryTableClient;
}

describe("listCostingRequestsForOpportunity", () => {
  test("calls list_costing_requests_for_opportunity with opportunity/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_REQUEST_ROW], error: null }, capture);
    const requests = await listCostingRequestsForOpportunity(client, OPPORTUNITY_ID, ACTOR_ID);
    assert.equal(capture.calls.rpcFn, "list_costing_requests_for_opportunity");
    assert.deepEqual(capture.calls.rpcArgs, { p_opportunity_id: OPPORTUNITY_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(requests.length, 1);
  });
});

describe("getCostingRequestById", () => {
  test("returns null (never an error) when denied/no-match yields zero rows", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    const request = await getCostingRequestById(client, REQUEST_ID, ACTOR_ID);
    assert.equal(request, null);
  });

  test("wraps a query error", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: null, error: { message: "boom" } }, capture);
    await assert.rejects(
      () => getCostingRequestById(client, REQUEST_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CostingQueryError);
        return true;
      },
    );
  });
});

describe("listCostingRequestComponents", () => {
  test("maps rows to the contract shape", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_COMPONENT_ROW], error: null }, capture);
    const components = await listCostingRequestComponents(client, REQUEST_ID, ACTOR_ID);
    assert.equal(capture.calls.rpcFn, "list_costing_request_components");
    assert.deepEqual(capture.calls.rpcArgs, { p_request_id: REQUEST_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(components.length, 1);
  });
});

describe("listCostingResponsesForRequest", () => {
  test("calls list_costing_responses_for_request with request/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_RESPONSE_ROW], error: null }, capture);
    const responses = await listCostingResponsesForRequest(client, REQUEST_ID, ACTOR_ID);
    assert.equal(capture.calls.rpcFn, "list_costing_responses_for_request");
    assert.deepEqual(capture.calls.rpcArgs, { p_request_id: REQUEST_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(responses[0]?.totalAmount, 17500000);
  });
});

describe("listCostingResponseComponents", () => {
  test("calls list_costing_response_components with response/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_RESPONSE_COMPONENT_ROW], error: null }, capture);
    const components = await listCostingResponseComponents(client, RESPONSE_ID, ACTOR_ID);
    assert.equal(capture.calls.rpcFn, "list_costing_response_components");
    assert.deepEqual(capture.calls.rpcArgs, { p_response_id: RESPONSE_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(components.length, 1);
    assert.equal(components[0]?.amount, 15000000);
  });
});
