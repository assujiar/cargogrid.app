import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getPipelineSummary,
  getSalesTargetActual,
  listSalesPlans,
  getSalesPlanById,
  listSalesTargetsForPlan,
  listForecastSnapshotsForTarget,
  listPipelineCategories,
  listWinLossReasons,
  PipelineQueryError,
  type PipelineQueryRpcClient,
  type PipelineQueryTableClient,
} from "./pipeline.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const PLAN_ID = "323e4567-e89b-12d3-a456-426614174000";
const TARGET_ID = "423e4567-e89b-12d3-a456-426614174000";
const ORG_UNIT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_PLAN_ROW = {
  id: PLAN_ID,
  tenant_id: TENANT_ID,
  org_unit_id: ORG_UNIT_ID,
  name: "Q3 Plan",
  period_start: "2026-07-01",
  period_end: "2026-09-30",
  status: "draft",
  supersedes_plan_id: null,
  owner_user_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

const VALID_TARGET_ROW = {
  id: TARGET_ID,
  tenant_id: TENANT_ID,
  sales_plan_id: PLAN_ID,
  pipeline_category_id: null,
  metric_type: "leads_captured",
  org_unit_id: ORG_UNIT_ID,
  owner_user_id: null,
  target_value: 10,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

const VALID_SNAPSHOT_ROW = {
  id: "723e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  sales_target_id: TARGET_ID,
  computed_value: 3,
  override_value: null,
  override_reason: null,
  snapshot_at: "2026-07-23T00:00:00.000Z",
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
};

const VALID_CATEGORY_ROW = {
  id: "823e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  code: "TOP_FUNNEL",
  label: "Top of Funnel",
  sort_order: 1,
  is_active: true,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

const VALID_REASON_ROW = {
  id: "923e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  code: "NO_BUDGET",
  label: "No budget",
  outcome: "lost",
  is_active: true,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

describe("getPipelineSummary", () => {
  test("calls get_pipeline_summary with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: [{ stage: "prospect_active", record_count: 2 }], error: null };
      },
    } as unknown as PipelineQueryRpcClient;
    const summary = await getPipelineSummary(client, { tenantId: TENANT_ID, orgUnitId: ORG_UNIT_ID });

    assert.equal(calls[0]?.fn, "get_pipeline_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_org_unit_id: ORG_UNIT_ID });
    assert.equal(summary.length, 1);
    assert.equal(summary[0]?.recordCount, 2);
  });

  test("wraps a query error", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "boom" } };
      },
    } as unknown as PipelineQueryRpcClient;
    await assert.rejects(
      () => getPipelineSummary(client, { tenantId: TENANT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof PipelineQueryError);
        return true;
      },
    );
  });
});

describe("getSalesTargetActual", () => {
  test("returns the reconciled numeric count", async () => {
    const client = {
      async rpc() {
        return { data: 2, error: null };
      },
    } as unknown as PipelineQueryRpcClient;
    const actual = await getSalesTargetActual(client, TARGET_ID, ACTOR_ID);
    assert.equal(actual, 2);
  });
});

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): PipelineQueryTableClient {
  const fake = {
    from(_table: string) {
      return {
        select() {
          return {
            eq() {
              return {
                order() {
                  return response;
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
  return fake as unknown as PipelineQueryTableClient;
}

describe("listSalesPlans", () => {
  test("maps rows to the contract shape", async () => {
    const client = fakeTableClient({ data: [VALID_PLAN_ROW], error: null });
    const plans = await listSalesPlans(client, TENANT_ID);
    assert.equal(plans.length, 1);
    assert.equal(plans[0]?.name, "Q3 Plan");
  });
});

describe("getSalesPlanById", () => {
  test("returns null (never an error) when RLS/no-match yields zero rows", async () => {
    const client = fakeTableClient({ data: [], error: null });
    const plan = await getSalesPlanById(client, PLAN_ID);
    assert.equal(plan, null);
  });
});

describe("listSalesTargetsForPlan", () => {
  test("maps rows to the contract shape", async () => {
    const client = fakeTableClient({ data: [VALID_TARGET_ROW], error: null });
    const targets = await listSalesTargetsForPlan(client, PLAN_ID);
    assert.equal(targets.length, 1);
    assert.equal(targets[0]?.metricType, "leads_captured");
  });
});

describe("listForecastSnapshotsForTarget", () => {
  test("maps rows to the contract shape", async () => {
    const client = fakeTableClient({ data: [VALID_SNAPSHOT_ROW], error: null });
    const snapshots = await listForecastSnapshotsForTarget(client, TARGET_ID);
    assert.equal(snapshots.length, 1);
    assert.equal(snapshots[0]?.computedValue, 3);
  });
});

describe("listPipelineCategories", () => {
  test("maps rows to the contract shape", async () => {
    const client = fakeTableClient({ data: [VALID_CATEGORY_ROW], error: null });
    const categories = await listPipelineCategories(client, TENANT_ID);
    assert.equal(categories.length, 1);
    assert.equal(categories[0]?.code, "TOP_FUNNEL");
  });
});

describe("listWinLossReasons", () => {
  test("maps rows to the contract shape", async () => {
    const client = fakeTableClient({ data: [VALID_REASON_ROW], error: null });
    const reasons = await listWinLossReasons(client, TENANT_ID);
    assert.equal(reasons.length, 1);
    assert.equal(reasons[0]?.outcome, "lost");
  });
});
