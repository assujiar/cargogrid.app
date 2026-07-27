import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getJobOrder,
  getJobOrderForHandoff,
  listJobOrders,
  getJobOrderConversionReadiness,
  JobOrderQueryError,
  type JobOrderQueryTableClient,
} from "./job-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "423e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const MASKED_ROW = {
  id: JOB_ORDER_ID,
  tenant_id: TENANT_ID,
  job_number: "JOB-2026-000001",
  source_handoff_id: HANDOFF_ID,
  quotation_id: QUOTATION_ID,
  account_id: ACCOUNT_ID,
  customer_snapshot: { accountId: ACCOUNT_ID },
  cargo_service_snapshot: { service_type: "ocean_freight" },
  revenue_snapshot: null,
  revenue_masked: true,
  contract_snapshot: null,
  credit_snapshot: null,
  credit_masked: true,
  acceptance_snapshot: { decision: "accepted" },
  status: "draft",
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

function fakeTableClient(
  response: { data: unknown; error: { message: string } | null; count?: number },
  rpcResponse?: { data: unknown; error: { message: string } | null },
  captureRange?: (from: number, to: number) => void,
): JobOrderQueryTableClient {
  function chainNode(): unknown {
    return {
      select: () => chainNode(),
      eq: () => chainNode(),
      order: () => chainNode(),
      limit: () => Promise.resolve(response),
      range: (from: number, to: number) => {
        captureRange?.(from, to);
        return Promise.resolve(response);
      },
      maybeSingle: () => {
        const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
        return Promise.resolve({ data: row, error: response.error });
      },
      then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) => Promise.resolve(response).then(resolve, reject),
    };
  }
  return {
    from: () => chainNode(),
    rpc: () => Promise.resolve(rpcResponse ?? response),
  } as unknown as JobOrderQueryTableClient;
}

describe("getJobOrder", () => {
  test("returns null (never an error) when no such row exists or RLS excludes it", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const jobOrder = await getJobOrder(client, JOB_ORDER_ID);
    assert.equal(jobOrder, null);
  });

  test("maps a masked row", async () => {
    const client = fakeTableClient({ data: MASKED_ROW, error: null });
    const jobOrder = await getJobOrder(client, JOB_ORDER_ID);
    assert.equal(jobOrder?.revenueMasked, true);
    assert.equal(jobOrder?.revenueSnapshot, null);
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getJobOrder(client, JOB_ORDER_ID),
      (err: unknown) => err instanceof JobOrderQueryError,
    );
  });
});

describe("getJobOrderForHandoff", () => {
  test("returns null (never an error) when no Job Order has been converted yet", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const jobOrder = await getJobOrderForHandoff(client, HANDOFF_ID);
    assert.equal(jobOrder, null);
  });

  test("maps a row", async () => {
    const client = fakeTableClient({ data: MASKED_ROW, error: null });
    const jobOrder = await getJobOrderForHandoff(client, HANDOFF_ID);
    assert.equal(jobOrder?.sourceHandoffId, HANDOFF_ID);
  });
});

describe("listJobOrders", () => {
  test("bounds the query to one 50-row default page, ordered by created_at descending", async () => {
    const ranges: [number, number][] = [];
    const client = fakeTableClient({ data: [MASKED_ROW], error: null, count: 1 }, undefined, (from, to) => ranges.push([from, to]));
    const result = await listJobOrders(client, { tenantId: TENANT_ID, page: 1 });
    assert.deepEqual(ranges[0], [0, 49]);
    assert.equal(result.jobOrders.length, 1);
    assert.equal(result.jobOrders[0]?.status, "draft");
    assert.equal(result.totalCount, 1);
    assert.equal(result.page, 1);
    assert.equal(result.pageSize, 50);
  });

  test("advances the page offset correctly for page 2 and clamps an oversized pageSize", async () => {
    const ranges: [number, number][] = [];
    const client = fakeTableClient({ data: [], error: null, count: 0 }, undefined, (from, to) => ranges.push([from, to]));
    await listJobOrders(client, { tenantId: TENANT_ID, page: 2, pageSize: 500 });
    assert.deepEqual(ranges[0], [100, 199]);
  });
});

describe("getJobOrderConversionReadiness", () => {
  test("maps a ready-with-no-blockers row", async () => {
    const client = fakeTableClient(
      { data: null, error: null },
      { data: { ready: true, blocking_reasons: [], existing_job_order_id: null }, error: null },
    );
    const readiness = await getJobOrderConversionReadiness(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(readiness.ready, true);
    assert.deepEqual(readiness.blockingReasons, []);
  });

  test("maps an already_converted row carrying the existing Job Order id", async () => {
    const client = fakeTableClient(
      { data: null, error: null },
      { data: { ready: false, blocking_reasons: ["already_converted"], existing_job_order_id: JOB_ORDER_ID }, error: null },
    );
    const readiness = await getJobOrderConversionReadiness(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(readiness.ready, false);
    assert.deepEqual(readiness.blockingReasons, ["already_converted"]);
    assert.equal(readiness.existingJobOrderId, JOB_ORDER_ID);
  });

  test("wraps an rpc error", async () => {
    const client = fakeTableClient({ data: null, error: null }, { data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getJobOrderConversionReadiness(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof JobOrderQueryError,
    );
  });
});
