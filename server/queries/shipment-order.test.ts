import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getShipmentOrder,
  listShipmentOrdersForJobOrder,
  listShipmentOrders,
  getJobShipmentAllocationBalance,
  ShipmentOrderQueryError,
  type ShipmentOrderQueryTableClient,
} from "./shipment-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const BASE_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  idempotency_key: "idem-1",
  status: "draft",
  shipper_account_id: ACCOUNT_ID,
  consignee_snapshot: { legal_name: "Acme Shipping Co" },
  notify_party_snapshot: null,
  cargo_service_snapshot: { service_type: "ocean_freight" },
  service_type: "ocean_freight",
  mode: "sea",
  origin: "Jakarta",
  destination: "Surabaya",
  planned_pickup_at: null,
  planned_delivery_at: null,
  basis_quantity: 15,
  basis_weight_kg: 1500,
  basis_volume_cbm: 30,
  allocated_quantity: 10,
  allocated_weight_kg: 1000,
  allocated_volume_cbm: 20,
  split_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

function fakeRpcClient(
  response: { data: unknown; error: { message: string } | null },
  capture?: (fn: string, args: Record<string, unknown>) => void,
): ShipmentOrderQueryTableClient {
  return {
    from: () => {
      throw new Error("not used in this fake");
    },
    rpc: (fn: string, args: Record<string, unknown>) => {
      capture?.(fn, args);
      return Promise.resolve(response);
    },
  } as unknown as ShipmentOrderQueryTableClient;
}

describe("getShipmentOrder", () => {
  test("returns null (never an error) when no such row exists or RLS excludes it", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const shipment = await getShipmentOrder(client, SHIPMENT_ID);
    assert.equal(shipment, null);
  });

  test("maps a row", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient({ data: [BASE_ROW], error: null }, (fn, args) => {
      capturedFn = fn;
      capturedArgs = args;
    });
    const shipment = await getShipmentOrder(client, SHIPMENT_ID);
    assert.equal(capturedFn, "get_shipment_order");
    assert.equal(capturedArgs?.p_shipment_order_id, SHIPMENT_ID);
    assert.equal(shipment?.mode, "sea");
    assert.equal(shipment?.basisQuantity, 15);
  });

  test("wraps a query error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getShipmentOrder(client, SHIPMENT_ID),
      (err: unknown) => err instanceof ShipmentOrderQueryError,
    );
  });
});

describe("listShipmentOrdersForJobOrder", () => {
  test("maps rows", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient({ data: [BASE_ROW], error: null }, (fn, args) => {
      capturedFn = fn;
      capturedArgs = args;
    });
    const shipments = await listShipmentOrdersForJobOrder(client, JOB_ORDER_ID);
    assert.equal(capturedFn, "list_shipment_orders_for_job_order");
    assert.equal(capturedArgs?.p_job_order_id, JOB_ORDER_ID);
    assert.equal(shipments.length, 1);
    assert.equal(shipments[0]?.jobOrderId, JOB_ORDER_ID);
  });
});

describe("listShipmentOrders", () => {
  test("passes page 1 with the default pageSize (50) to the RPC and maps total_count off the row", async () => {
    let capturedFn: string | undefined;
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient({ data: [{ ...BASE_ROW, total_count: 1 }], error: null }, (fn, args) => {
      capturedFn = fn;
      capturedArgs = args;
    });
    const result = await listShipmentOrders(client, { tenantId: TENANT_ID, page: 1 });
    assert.equal(capturedFn, "list_shipment_orders");
    assert.deepEqual(capturedArgs, { p_tenant_id: TENANT_ID, p_page: 1, p_page_size: 50 });
    assert.equal(result.shipmentOrders.length, 1);
    assert.equal(result.totalCount, 1);
    assert.equal(result.page, 1);
    assert.equal(result.pageSize, 50);
  });

  test("clamps an oversized pageSize and passes page 2 to the RPC", async () => {
    let capturedArgs: Record<string, unknown> | undefined;
    const client = fakeRpcClient({ data: [], error: null }, (_fn, args) => {
      capturedArgs = args;
    });
    const result = await listShipmentOrders(client, { tenantId: TENANT_ID, page: 2, pageSize: 500 });
    assert.deepEqual(capturedArgs, { p_tenant_id: TENANT_ID, p_page: 2, p_page_size: 100 });
    assert.equal(result.shipmentOrders.length, 0);
    assert.equal(result.totalCount, 0);
  });
});

describe("getJobShipmentAllocationBalance", () => {
  test("maps a null-basis row (advisory-only) distinct from a zero basis", async () => {
    const client = fakeRpcClient({
      data: {
        basis_quantity: null,
        basis_weight_kg: null,
        basis_volume_cbm: null,
        allocated_quantity: 0,
        allocated_weight_kg: 0,
        allocated_volume_cbm: 0,
        remaining_quantity: null,
        remaining_weight_kg: null,
        remaining_volume_cbm: null,
      },
      error: null,
    });
    const balance = await getJobShipmentAllocationBalance(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(balance.basisQuantity, null);
    assert.equal(balance.allocatedQuantity, 0);
  });

  test("maps a real established basis with remaining headroom", async () => {
    const client = fakeRpcClient({
      data: {
        basis_quantity: 15,
        basis_weight_kg: 1500,
        basis_volume_cbm: 30,
        allocated_quantity: 13,
        allocated_weight_kg: 1300,
        allocated_volume_cbm: 26,
        remaining_quantity: 2,
        remaining_weight_kg: 200,
        remaining_volume_cbm: 4,
      },
      error: null,
    });
    const balance = await getJobShipmentAllocationBalance(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(balance.remainingQuantity, 2);
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getJobShipmentAllocationBalance(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof ShipmentOrderQueryError,
    );
  });
});
