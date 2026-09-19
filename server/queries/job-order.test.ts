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

function fakeRpcClient(
  responses: Record<string, { data: unknown; error: { message: string } | null }>,
  capture?: { calls: { fn: string; args: Record<string, unknown> }[] },
): JobOrderQueryTableClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture?.calls.push({ fn, args });
      return responses[fn] ?? { data: null, error: { message: `no mock response for ${fn}` } };
    },
  } as unknown as JobOrderQueryTableClient;
}

describe("getJobOrder", () => {
  test("returns null (never an error) when no such row exists or the caller's record scope excludes it", async () => {
    const client = fakeRpcClient({ get_job_order: { data: [], error: null } });
    const jobOrder = await getJobOrder(client, JOB_ORDER_ID, ACTOR_ID);
    assert.equal(jobOrder, null);
  });

  test("maps a masked row", async () => {
    const client = fakeRpcClient({ get_job_order: { data: [MASKED_ROW], error: null } });
    const jobOrder = await getJobOrder(client, JOB_ORDER_ID, ACTOR_ID);
    assert.equal(jobOrder?.revenueMasked, true);
    assert.equal(jobOrder?.revenueSnapshot, null);
  });

  test("wraps a query error", async () => {
    const client = fakeRpcClient({ get_job_order: { data: null, error: { message: "boom" } } });
    await assert.rejects(
      () => getJobOrder(client, JOB_ORDER_ID, ACTOR_ID),
      (err: unknown) => err instanceof JobOrderQueryError,
    );
  });

  test("calls get_job_order with the job order id and actor id", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ get_job_order: { data: [MASKED_ROW], error: null } }, capture);
    await getJobOrder(client, JOB_ORDER_ID, ACTOR_ID);
    assert.deepEqual(capture.calls[0], { fn: "get_job_order", args: { p_job_order_id: JOB_ORDER_ID, p_actor_auth_user_id: ACTOR_ID } });
  });
});

describe("getJobOrderForHandoff", () => {
  test("returns null (never an error) when no Job Order has been converted yet", async () => {
    const client = fakeRpcClient({ get_job_order_for_handoff: { data: [], error: null } });
    const jobOrder = await getJobOrderForHandoff(client, HANDOFF_ID, ACTOR_ID);
    assert.equal(jobOrder, null);
  });

  test("maps a row", async () => {
    const client = fakeRpcClient({ get_job_order_for_handoff: { data: [MASKED_ROW], error: null } });
    const jobOrder = await getJobOrderForHandoff(client, HANDOFF_ID, ACTOR_ID);
    assert.equal(jobOrder?.sourceHandoffId, HANDOFF_ID);
  });

  test("wraps an ambiguous_context error the same way as any other query error", async () => {
    const client = fakeRpcClient({ get_job_order_for_handoff: { data: null, error: { message: "ambiguous_context: source_handoff_id matches 2 job orders" } } });
    await assert.rejects(
      () => getJobOrderForHandoff(client, HANDOFF_ID, ACTOR_ID),
      (err: unknown) => err instanceof JobOrderQueryError,
    );
  });
});

describe("listJobOrders", () => {
  test("passes the default page/pageSize and reads total_count off row 0", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ list_job_orders: { data: [{ ...MASKED_ROW, total_count: 1 }], error: null } }, capture);
    const result = await listJobOrders(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 });
    assert.equal(capture.calls[0]?.args.p_page, 1);
    assert.equal(capture.calls[0]?.args.p_page_size, 50);
    assert.equal(capture.calls[0]?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(result.jobOrders.length, 1);
    assert.equal(result.jobOrders[0]?.status, "draft");
    assert.equal(result.totalCount, 1);
    assert.equal(result.page, 1);
    assert.equal(result.pageSize, 50);
  });

  test("clamps an oversized pageSize and advances p_page for page 2", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ list_job_orders: { data: [], error: null } }, capture);
    await listJobOrders(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 2, pageSize: 500 });
    assert.equal(capture.calls[0]?.args.p_page, 2);
    assert.equal(capture.calls[0]?.args.p_page_size, 100);
  });

  test("returns zero total_count, not an error, for a tenant with zero visible job orders", async () => {
    const client = fakeRpcClient({ list_job_orders: { data: [], error: null } });
    const result = await listJobOrders(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 });
    assert.deepEqual(result.jobOrders, []);
    assert.equal(result.totalCount, 0);
  });
});

describe("getJobOrderConversionReadiness", () => {
  test("maps a ready-with-no-blockers row", async () => {
    const client = fakeRpcClient({
      get_job_order_conversion_readiness: { data: { ready: true, blocking_reasons: [], existing_job_order_id: null }, error: null },
    });
    const readiness = await getJobOrderConversionReadiness(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(readiness.ready, true);
    assert.deepEqual(readiness.blockingReasons, []);
  });

  test("maps an already_converted row carrying the existing Job Order id", async () => {
    const client = fakeRpcClient({
      get_job_order_conversion_readiness: { data: { ready: false, blocking_reasons: ["already_converted"], existing_job_order_id: JOB_ORDER_ID }, error: null },
    });
    const readiness = await getJobOrderConversionReadiness(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(readiness.ready, false);
    assert.deepEqual(readiness.blockingReasons, ["already_converted"]);
    assert.equal(readiness.existingJobOrderId, JOB_ORDER_ID);
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ get_job_order_conversion_readiness: { data: null, error: { message: "boom" } } });
    await assert.rejects(
      () => getJobOrderConversionReadiness(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof JobOrderQueryError,
    );
  });
});
