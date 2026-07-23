import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listOpportunities,
  getOpportunityById,
  listOpportunityStageHistory,
  getOpportunityCostingReadiness,
  OpportunityQueryError,
  type OpportunityQueryRpcClient,
  type OpportunityQueryTableClient,
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

function fakeTableClient(response: { data: unknown; error: { message: string } | null; count?: number }, capture: { calls: Record<string, unknown> }): OpportunityQueryTableClient {
  const fake = {
    from(table: string) {
      capture.calls.table = table;
      return {
        select(columns: string, options?: { count?: string }) {
          capture.calls.columns = columns;
          capture.calls.countOption = options?.count;
          return {
            eq(column: string, value: unknown) {
              capture.calls.eqColumn = column;
              capture.calls.eqValue = value;
              return {
                order(column2: string, opts: { ascending: boolean }) {
                  capture.calls.orderColumn = column2;
                  capture.calls.ascending = opts.ascending;
                  return {
                    ...response,
                    async range(from: number, to: number) {
                      capture.calls.from = from;
                      capture.calls.to = to;
                      return response;
                    },
                  };
                },
                async maybeSingle() {
                  const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
                  return { data: row, error: response.error };
                },
              };
            },
          };
        },
      };
    },
  };
  return fake as unknown as OpportunityQueryTableClient;
}

describe("listOpportunities", () => {
  test("queries the field-masked opportunities_directory view, bounded to one 50-row default page", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_OPPORTUNITY_ROW], error: null, count: 1 }, capture);

    const result = await listOpportunities(client, { tenantId: TENANT_ID, page: 1 });
    assert.equal(capture.calls.table, "opportunities_directory");
    assert.equal(capture.calls.from, 0);
    assert.equal(capture.calls.to, 49);
    assert.equal(result.opportunities.length, 1);
    assert.equal(result.opportunities[0]?.valueMasked, true);
  });
});

describe("getOpportunityById", () => {
  test("returns null (never an error) when RLS/no-match yields zero rows", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    const opportunity = await getOpportunityById(client, OPPORTUNITY_ID);
    assert.equal(opportunity, null);
  });

  test("wraps a query error", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: null, error: { message: "boom" } }, capture);
    await assert.rejects(
      () => getOpportunityById(client, OPPORTUNITY_ID),
      (err: unknown) => {
        assert.ok(err instanceof OpportunityQueryError);
        return true;
      },
    );
  });
});

describe("listOpportunityStageHistory", () => {
  test("orders oldest first", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_HISTORY_ROW], error: null }, capture);
    const history = await listOpportunityStageHistory(client, OPPORTUNITY_ID);
    assert.equal(capture.calls.orderColumn, "changed_at");
    assert.equal(capture.calls.ascending, true);
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
