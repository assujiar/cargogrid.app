import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getDispatchReadiness, listDispatchReadyQueue, BasicDispatchQueryError, type BasicDispatchQueryClient } from "./basic-dispatch.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "523e4567-e89b-12d3-a456-426614174000";
const SHIPPER_ID = "623e4567-e89b-12d3-a456-426614174000";

const BASE_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-0001",
  idempotency_key: "idem-1",
  status: "assigned",
  held_from_status: null,
  shipper_account_id: SHIPPER_ID,
  consignee_snapshot: {},
  notify_party_snapshot: null,
  cargo_service_snapshot: {},
  service_type: "FCL",
  mode: "sea",
  origin: "Jakarta",
  destination: "Singapore",
  planned_pickup_at: "2026-07-28T00:00:00.000Z",
  planned_delivery_at: null,
  basis_quantity: null,
  basis_weight_kg: null,
  basis_volume_cbm: null,
  allocated_quantity: null,
  allocated_weight_kg: null,
  allocated_volume_cbm: null,
  split_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
  is_ready: true,
  blockers: [],
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): BasicDispatchQueryClient {
  return { rpc: () => Promise.resolve(response), from: () => ({}) } as unknown as BasicDispatchQueryClient;
}

describe("getDispatchReadiness", () => {
  test("maps a ready single row", async () => {
    const client = fakeRpcClient({ data: [{ is_ready: true, blockers: [] }], error: null });
    const readiness = await getDispatchReadiness(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(readiness.isReady, true);
  });

  test("maps a blocked row with its exact blockers", async () => {
    const client = fakeRpcClient({ data: [{ is_ready: false, blockers: [{ code: "missing_schedule", detail: null }] }], error: null });
    const readiness = await getDispatchReadiness(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(readiness.isReady, false);
    assert.equal(readiness.blockers[0]?.code, "missing_schedule");
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
    await assert.rejects(
      () => getDispatchReadiness(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof BasicDispatchQueryError,
    );
  });
});

/**
 * CG-AUDIT-2026-09-02 F5: listDispatchReadyQueue now issues two separate queries -- a
 * plain HEAD count against `shipment_orders` (awaited directly, no `.range()` call), and
 * the enriched data page against `dispatch_ready_queue` (resolved via `.range()`, exactly
 * as before). This mock routes by table name: the `shipment_orders` chain is itself
 * thenable at every step (simulating a real supabase-js query builder, which resolves on
 * `await` without needing a terminal method call) and answers with `countResponse`; the
 * `dispatch_ready_queue` chain resolves via `.range()` exactly as the single-query mock
 * used to, answering with `dataResponse`.
 */
function fakeTableClient(
  countResponse: { count: number | null; error: { message: string } | null },
  dataResponse: { data: unknown; error: { message: string } | null },
  captureRange?: (from: number, to: number) => void,
): BasicDispatchQueryClient {
  function dataChain(): unknown {
    return {
      select: () => dataChain(),
      eq: () => dataChain(),
      order: () => dataChain(),
      range: (from: number, to: number) => {
        captureRange?.(from, to);
        return Promise.resolve(dataResponse);
      },
    };
  }
  function countChain(): PromiseLike<unknown> {
    return {
      select: () => countChain(),
      eq: () => countChain(),
      then: (onFulfilled: (value: unknown) => unknown) => Promise.resolve(countResponse).then(onFulfilled),
    } as unknown as PromiseLike<unknown>;
  }
  return {
    from: (table: string) => (table === "shipment_orders" ? countChain() : dataChain()),
    rpc: () => Promise.resolve(dataResponse),
  } as unknown as BasicDispatchQueryClient;
}

describe("listDispatchReadyQueue", () => {
  test("bounds the query to one 50-row default page and maps every row", async () => {
    const ranges: [number, number][] = [];
    const client = fakeTableClient({ count: 1, error: null }, { data: [BASE_ROW], error: null }, (from, to) => ranges.push([from, to]));
    const result = await listDispatchReadyQueue(client, { tenantId: TENANT_ID, page: 1 });
    assert.deepEqual(ranges[0], [0, 49]);
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0]?.isReady, true);
    assert.equal(result.totalCount, 1);
    assert.equal(result.page, 1);
    assert.equal(result.pageSize, 50);
  });

  test("advances the page offset correctly for page 2 and clamps an oversized pageSize", async () => {
    const ranges: [number, number][] = [];
    const client = fakeTableClient({ count: 0, error: null }, { data: [], error: null }, (from, to) => ranges.push([from, to]));
    await listDispatchReadyQueue(client, { tenantId: TENANT_ID, page: 2, pageSize: 500 });
    assert.deepEqual(ranges[0], [100, 199]);
  });

  test("wraps an error from the count query", async () => {
    const client = fakeTableClient({ count: null, error: { message: "boom" } }, { data: [], error: null });
    await assert.rejects(
      () => listDispatchReadyQueue(client, { tenantId: TENANT_ID, page: 1 }),
      (err: unknown) => err instanceof BasicDispatchQueryError,
    );
  });

  test("wraps an error from the data query", async () => {
    const client = fakeTableClient({ count: 0, error: null }, { data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listDispatchReadyQueue(client, { tenantId: TENANT_ID, page: 1 }),
      (err: unknown) => err instanceof BasicDispatchQueryError,
    );
  });
});
