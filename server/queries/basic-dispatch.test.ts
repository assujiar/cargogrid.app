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
  leg_network_status: null,
  is_ready: true,
  blockers: [],
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): BasicDispatchQueryClient {
  return { rpc: () => Promise.resolve(response) } as unknown as BasicDispatchQueryClient;
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
 * CG-AUDIT-2026-09-02 O1 cluster 3 batch 1: listDispatchReadyQueue issues two separate
 * RPC calls -- count_dispatch_ready_shipment_orders (a bare scalar) and
 * list_dispatch_ready_queue (a row set) -- preserving F5's own count/data split intent.
 * This mock routes by function name.
 */
function fakeRpcRoutedClient(
  countResponse: { data: unknown; error: { message: string } | null },
  dataResponse: { data: unknown; error: { message: string } | null },
  captureArgs?: (fn: string, args: Record<string, unknown>) => void,
): BasicDispatchQueryClient {
  return {
    rpc: (fn: string, args: Record<string, unknown>) => {
      captureArgs?.(fn, args);
      return Promise.resolve(fn === "count_dispatch_ready_shipment_orders" ? countResponse : dataResponse);
    },
  } as unknown as BasicDispatchQueryClient;
}

describe("listDispatchReadyQueue", () => {
  test("passes the default page/pageSize through and maps every row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcRoutedClient({ data: 1, error: null }, { data: [BASE_ROW], error: null }, (fn, args) => calls.push({ fn, args }));
    const result = await listDispatchReadyQueue(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 });
    const listCall = calls.find((c) => c.fn === "list_dispatch_ready_queue");
    assert.equal(listCall?.args.p_page, 1);
    assert.equal(listCall?.args.p_page_size, 50);
    assert.equal(listCall?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0]?.isReady, true);
    assert.equal(result.totalCount, 1);
    assert.equal(result.page, 1);
    assert.equal(result.pageSize, 50);
  });

  test("clamps an oversized pageSize and advances page 2's p_page", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcRoutedClient({ data: 0, error: null }, { data: [], error: null }, (fn, args) => calls.push({ fn, args }));
    await listDispatchReadyQueue(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 2, pageSize: 500 });
    const listCall = calls.find((c) => c.fn === "list_dispatch_ready_queue");
    assert.equal(listCall?.args.p_page, 2);
    assert.equal(listCall?.args.p_page_size, 100);
  });

  test("wraps an error from the count RPC", async () => {
    const client = fakeRpcRoutedClient({ data: null, error: { message: "boom" } }, { data: [], error: null });
    await assert.rejects(
      () => listDispatchReadyQueue(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 }),
      (err: unknown) => err instanceof BasicDispatchQueryError,
    );
  });

  test("wraps an error from the data RPC", async () => {
    const client = fakeRpcRoutedClient({ data: 0, error: null }, { data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listDispatchReadyQueue(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 }),
      (err: unknown) => err instanceof BasicDispatchQueryError,
    );
  });
});
