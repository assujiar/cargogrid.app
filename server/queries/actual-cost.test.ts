import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getShipmentActualCost, listActualCostComponents, evaluateActualCostVariance, ActualCostQueryError, type ActualCostQueryClient } from "./actual-cost.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const COST_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const DIRECTORY_ROW = {
  id: COST_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  version_number: 1,
  is_current: true,
  supersedes_version_id: null,
  status: "draft",
  currency: "IDR",
  estimated_amount: null,
  total_amount: 0,
  cost_masked: false,
  approved_by_auth_user_id: null,
  approved_at: null,
  rejection_reason: null,
  adjustment_reason: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("getShipmentActualCost", () => {
  test("filters by shipment_order_id and is_current, returns the parsed row", async () => {
    const calls: { table: string; filters: [string, unknown][] }[] = [];
    const client = {
      from(table: string) {
        const filters: [string, unknown][] = [];
        const builder = {
          select() {
            return builder;
          },
          eq(column: string, value: unknown) {
            filters.push([column, value]);
            return builder;
          },
          maybeSingle() {
            calls.push({ table, filters });
            return Promise.resolve({ data: DIRECTORY_ROW, error: null });
          },
        };
        return builder;
      },
    } as unknown as ActualCostQueryClient;

    const row = await getShipmentActualCost(client, SHIPMENT_ID);
    assert.equal(calls[0]?.table, "shipment_actual_costs_directory");
    assert.deepEqual(calls[0]?.filters, [
      ["shipment_order_id", SHIPMENT_ID],
      ["is_current", true],
    ]);
    assert.equal(row?.id, COST_ID);
  });

  test("returns null when no current version exists", async () => {
    const client = {
      from() {
        const builder = {
          select() {
            return builder;
          },
          eq() {
            return builder;
          },
          maybeSingle() {
            return Promise.resolve({ data: null, error: null });
          },
        };
        return builder;
      },
    } as unknown as ActualCostQueryClient;

    const row = await getShipmentActualCost(client, SHIPMENT_ID);
    assert.equal(row, null);
  });
});

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ActualCostQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ActualCostQueryClient;
  return { client, calls };
}

describe("listActualCostComponents", () => {
  test("calls list_actual_cost_components with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listActualCostComponents(client, { actualCostId: COST_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(calls[0]?.fn, "list_actual_cost_components");
    assert.deepEqual(calls[0]?.args, { p_actual_cost_id: COST_ID, p_actor_auth_user_id: ACTOR_ID });
  });

  test("wraps insufficient_authority (no OPS:View cost) as an error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View cost" } });
    await assert.rejects(
      () => listActualCostComponents(client, { actualCostId: COST_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ActualCostQueryError);
        return true;
      },
    );
  });
});

describe("evaluateActualCostVariance", () => {
  test("calls evaluate_actual_cost_variance and maps the single-row result", async () => {
    const { client, calls } = fakeRpcClient({ data: { total_amount: 10250000, estimated_amount: 12000000, variance_amount: -1750000, variance_available: true }, error: null });
    const variance = await evaluateActualCostVariance(client, { actualCostId: COST_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(calls[0]?.fn, "evaluate_actual_cost_variance");
    assert.equal(variance.varianceAvailable, true);
  });
});
