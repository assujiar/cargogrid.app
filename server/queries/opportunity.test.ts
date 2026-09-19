import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listOpportunities,
  getOpportunityById,
  listOpportunityStageHistory,
  getOpportunityCostingReadiness,
  OpportunityQueryError,
  type OpportunityQueryRpcClient,
} from "./opportunity.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_OPPORTUNITY_ROW = {
  id: OPPORTUNITY_ID,
  tenant_id: TENANT_ID,
  prospect_id: PROSPECT_ID,
  account_ref: null,
  name: "Contoso freight lane",
  stage: "qualifying",
  probability: 10,
  value_amount: null,
  value_currency: null,
  value_masked: true,
  requirements: {},
  next_action: null,
  next_action_due_at: null,
  close_reason: null,
  cloned_from_id: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

const VALID_HISTORY_ROW = {
  id: "623e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  opportunity_id: OPPORTUNITY_ID,
  from_stage: null,
  to_stage: "qualifying",
  probability: 10,
  reason: null,
  changed_by: "tester",
  changed_at: "2026-07-23T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: { fn: string; args: Record<string, unknown> }[] }): OpportunityQueryRpcClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.push({ fn, args });
      return response;
    },
  };
  return fake as unknown as OpportunityQueryRpcClient;
}

describe("listOpportunities", () => {
  test("calls list_opportunities with tenant/actor/page/pageSize, maps total_count", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ data: [{ ...VALID_OPPORTUNITY_ROW, total_count: 1 }], error: null }, capture);

    const result = await listOpportunities(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 });
    assert.equal(capture.calls[0]?.fn, "list_opportunities");
    assert.deepEqual(capture.calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_page: 1, p_page_size: 50 });
    assert.equal(result.opportunities.length, 1);
    assert.equal(result.totalCount, 1);
    assert.equal(result.opportunities[0]?.valueMasked, true);
  });
});

describe("getOpportunityById", () => {
  test("returns null (never an error) when denied/no-match yields zero rows", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ data: [], error: null }, capture);
    const opportunity = await getOpportunityById(client, OPPORTUNITY_ID, ACTOR_ID);
    assert.equal(opportunity, null);
  });

  test("wraps a query error", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ data: null, error: { message: "boom" } }, capture);
    await assert.rejects(
      () => getOpportunityById(client, OPPORTUNITY_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof OpportunityQueryError);
        return true;
      },
    );
  });
});

describe("listOpportunityStageHistory", () => {
  test("calls list_opportunity_stage_history with opportunity/actor", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ data: [VALID_HISTORY_ROW], error: null }, capture);
    const history = await listOpportunityStageHistory(client, OPPORTUNITY_ID, ACTOR_ID);
    assert.equal(capture.calls[0]?.fn, "list_opportunity_stage_history");
    assert.deepEqual(capture.calls[0]?.args, { p_opportunity_id: OPPORTUNITY_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(history.length, 1);
  });
});

describe("getOpportunityCostingReadiness", () => {
  test("calls get_opportunity_costing_readiness with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: [{ ready: true, missing: [] }], error: null };
      },
    } as unknown as OpportunityQueryRpcClient;

    const readiness = await getOpportunityCostingReadiness(client, OPPORTUNITY_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_opportunity_id: OPPORTUNITY_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(readiness.ready, true);
  });
});
