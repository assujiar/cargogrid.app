import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getPublishedMarginRule,
  listMarginRuleVersions,
  listMarginCalculationsForRequest,
  MarginQueryError,
  type MarginQueryTableClient,
} from "./margin.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const RATE_SELECTION_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const CALC_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_RULE_ROW = {
  id: RULE_ID,
  tenant_id: TENANT_ID,
  minimum_margin_pct: 20,
  rounding_mode: "half_up",
  status: "published",
  supersedes_version_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

const VALID_CALC_ROW = {
  id: CALC_ID,
  tenant_id: TENANT_ID,
  costing_request_id: REQUEST_ID,
  rate_selection_id: RATE_SELECTION_ID,
  cost_amount: 10000000,
  cost_currency: "IDR",
  sell_amount: 15000000,
  sell_currency: "IDR",
  discount_pct: 0,
  discount_amount: 0,
  net_sell_amount: 15000000,
  margin_amount: 5000000,
  margin_pct: 33.33,
  markup_pct: 50,
  cost_masked: false,
  sell_masked: false,
  rule_version_id: RULE_ID,
  minimum_margin_pct_snapshot: 20,
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
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeTableClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): MarginQueryTableClient {
  function chain(): Record<string, unknown> {
    return {
      eq(column: string, value: unknown) {
        const eqCalls = (capture.calls.eqCalls ?? []) as { column: string; value: unknown }[];
        eqCalls.push({ column, value });
        capture.calls.eqCalls = eqCalls;
        return chain();
      },
      order(column: string, opts: { ascending: boolean }) {
        capture.calls.orderColumn = column;
        capture.calls.ascending = opts.ascending;
        return response;
      },
      async maybeSingle() {
        const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
        return { data: row, error: response.error };
      },
    };
  }

  const fake = {
    from(table: string) {
      capture.calls.table = table;
      return { select: () => chain() };
    },
  };
  return fake as unknown as MarginQueryTableClient;
}

describe("getPublishedMarginRule", () => {
  test("filters by tenant_id and status=published, returns null when none exists", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    const rule = await getPublishedMarginRule(client, TENANT_ID);
    const eqCalls = capture.calls.eqCalls as { column: string; value: unknown }[];
    assert.deepEqual(eqCalls, [
      { column: "tenant_id", value: TENANT_ID },
      { column: "status", value: "published" },
    ]);
    assert.equal(rule, null);
  });

  test("wraps a query error", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: null, error: { message: "boom" } }, capture);
    await assert.rejects(
      () => getPublishedMarginRule(client, TENANT_ID),
      (err: unknown) => {
        assert.ok(err instanceof MarginQueryError);
        return true;
      },
    );
  });
});

describe("listMarginRuleVersions", () => {
  test("maps rows to the contract shape, newest first", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_RULE_ROW], error: null }, capture);
    const rules = await listMarginRuleVersions(client, TENANT_ID);
    assert.equal(capture.calls.ascending, false);
    assert.equal(rules.length, 1);
  });
});

describe("listMarginCalculationsForRequest", () => {
  test("queries the field-masked margin_calculations_directory view", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_CALC_ROW], error: null }, capture);
    const calcs = await listMarginCalculationsForRequest(client, REQUEST_ID);
    assert.equal(capture.calls.table, "margin_calculations_directory");
    assert.equal(calcs[0]?.marginPct, 33.33);
  });
});
