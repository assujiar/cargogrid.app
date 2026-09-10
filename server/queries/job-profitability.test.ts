import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getJobProfitability, type JobProfitabilityQueryClient } from "./job-profitability.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const SNAPSHOT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const DIRECTORY_ROW = {
  id: SNAPSHOT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  version_number: 1,
  is_current: true,
  status: "calculated",
  blocked_reason: null,
  revenue_basis: "quoted",
  revenue_currency: "IDR",
  revenue_amount: 15000000,
  cost_currency: "IDR",
  cost_amount: 8000000,
  margin_amount: 7000000,
  margin_percent: 46.6667,
  source_cost_version_ids: [SNAPSHOT_ID],
  margin_masked: false,
  recalculation_reason: null,
  calculated_by_auth_user_id: ACTOR_ID,
  calculated_at: "2026-07-28T09:00:00.000Z",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("getJobProfitability", () => {
  test("calls get_job_profitability_directory with job_order_id/actor, returns the parsed row", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        capture.calls.fn = fn;
        capture.calls.args = args;
        return { data: [DIRECTORY_ROW], error: null };
      },
    } as unknown as JobProfitabilityQueryClient;

    const row = await getJobProfitability(client, JOB_ORDER_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "get_job_profitability_directory");
    assert.deepEqual(capture.calls.args, { p_job_order_id: JOB_ORDER_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(row?.id, SNAPSHOT_ID);
  });

  test("returns null when no current snapshot exists", async () => {
    const client = {
      async rpc() {
        return { data: [], error: null };
      },
    } as unknown as JobProfitabilityQueryClient;

    const row = await getJobProfitability(client, JOB_ORDER_ID, ACTOR_ID);
    assert.equal(row, null);
  });
});
