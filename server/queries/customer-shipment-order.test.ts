import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomerShipmentOrder, listCustomerShipmentOrders, listCustomerShipmentOrderChangeRequests, CustomerShipmentOrderQueryError, type CustomerShipmentOrderQueryClient } from "./customer-shipment-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "723e4567-e89b-12d3-a456-426614174000";

const SHIPMENT_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  status: "confirmed",
  shipper_account_id: ACCOUNT_ID,
  consignee_snapshot: {},
  notify_party_snapshot: null,
  cargo_service_snapshot: {},
  service_type: "ocean_freight",
  mode: "sea",
  origin: "Jakarta",
  destination: "Surabaya",
  planned_pickup_at: null,
  planned_delivery_at: null,
  allocated_quantity: null,
  allocated_weight_kg: null,
  allocated_volume_cbm: null,
  record_version: 1,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
};

const CHANGE_REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  shipment_order_id: SHIPMENT_ID,
  requested_by_auth_user_id: ACTOR_ID,
  request_type: "other",
  details: "Please call ahead",
  status: "submitted",
  idempotency_key: null,
  record_version: 1,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  staff_response: null,
  staff_responded_by: null,
  staff_responded_at: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerShipmentOrderQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerShipmentOrderQueryClient;
  return { client, calls };
}

describe("getCustomerShipmentOrder", () => {
  test("maps the returned row and passes exact param names in the given order", async () => {
    const { client, calls } = fakeRpcClient({ data: [SHIPMENT_ROW], error: null });
    const result = await getCustomerShipmentOrder(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID);
    assert.equal(result.id, SHIPMENT_ID);
    assert.deepEqual(calls[0], {
      fn: "get_customer_shipment_order",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_shipment_order_id: SHIPMENT_ID },
    });
  });

  test("classifies record_not_found (anti-enumeration -- same code for nonexistent and out-of-scope)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted shipment order exists for x" } });
    await assert.rejects(
      () => getCustomerShipmentOrder(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentOrderQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as query_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => getCustomerShipmentOrder(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentOrderQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });
});

describe("listCustomerShipmentOrders", () => {
  test("defaults cursor to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [SHIPMENT_ROW], error: null });
    const result = await listCustomerShipmentOrders(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: null,
      p_status: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("forwards account/status filters and cursor overrides", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerShipmentOrders(client, TENANT_ID, ACTOR_ID, { accountId: ACCOUNT_ID, status: "confirmed", cursorUpdatedAt: "2026-08-16T00:00:00.000Z", cursorId: SHIPMENT_ID, limit: 10 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: ACCOUNT_ID,
      p_status: "confirmed",
      p_cursor_updated_at: "2026-08-16T00:00:00.000Z",
      p_cursor_id: SHIPMENT_ID,
      p_limit: 10,
    });
  });

  test("returns an empty array (never throws) for a deny-by-default response", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerShipmentOrders(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});

describe("listCustomerShipmentOrderChangeRequests", () => {
  test("defaults shipmentOrderId/cursor to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [CHANGE_REQUEST_ROW], error: null });
    const result = await listCustomerShipmentOrderChangeRequests(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.equal(result[0]?.status, "submitted");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_shipment_order_id: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("forwards a shipmentOrderId filter", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerShipmentOrderChangeRequests(client, TENANT_ID, ACTOR_ID, { shipmentOrderId: SHIPMENT_ID });
    assert.equal(calls[0]?.args.p_shipment_order_id, SHIPMENT_ID);
  });

  test("returns an empty array (never throws) for a deny-by-default response", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerShipmentOrderChangeRequests(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});
