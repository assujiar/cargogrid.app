import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getCustomerPortalOutboundOrder,
  listCustomerPortalOutboundOrders,
  listCustomerPortalOutboundOrderLines,
  getCustomerPortalInboundOrder,
  listCustomerPortalInboundOrders,
  listCustomerPortalInboundOrderLines,
  CustomerPortalWarehouseOrderQueryError,
  type CustomerPortalWarehouseOrderQueryClient,
} from "./customer-portal-warehouse-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const ORDER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "923e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "a23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalWarehouseOrderQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalWarehouseOrderQueryClient;
  return { client, calls };
}

const ORDER_ROW = {
  id: ORDER_ID,
  warehouse_id: WAREHOUSE_ID,
  owner_account_id: OWNER_ID,
  outbound_number: "WMSOUT-2026-000001",
  source_type: "manual",
  requested_ship_date: "2026-09-01",
  status: "confirmed",
  cancelled_reason: null,
  record_version: 1,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("getCustomerPortalOutboundOrder", () => {
  test("maps the RPC's own single row and passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [ORDER_ROW], error: null });
    const result = await getCustomerPortalOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID);
    assert.equal(result.status, "confirmed");
    assert.deepEqual(calls[0], {
      fn: "get_customer_portal_outbound_order",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_outbound_order_id: ORDER_ID },
    });
  });

  test("propagates record_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted outbound order exists for x" } });
    await assert.rejects(
      () => getCustomerPortalOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalWarehouseOrderQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("throws when the RPC returns no row at all", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getCustomerPortalOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID));
  });

  test("on record_not_found, also calls the durable denial-audit RPC with resource_type=outbound_order", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted outbound order exists for x" } });
    await assert.rejects(() => getCustomerPortalOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID));
    assert.equal(calls.length, 2);
    assert.deepEqual(calls[1], {
      fn: "record_customer_inventory_access_denial",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_resource_type: "outbound_order", p_resource_id: ORDER_ID },
    });
  });

  test("does NOT call the denial-audit RPC on a successful read", async () => {
    const { client, calls } = fakeRpcClient({ data: [ORDER_ROW], error: null });
    await getCustomerPortalOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID);
    assert.equal(calls.length, 1);
  });

  test("does NOT call the denial-audit RPC for a non-record_not_found error (e.g. actor_identity_mismatch)", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "actor_identity_mismatch: session does not match claimed actor" } });
    await assert.rejects(() => getCustomerPortalOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID));
    assert.equal(calls.length, 1);
  });

  test("a failing denial-audit call never masks the original record_not_found error", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        if (fn === "record_customer_inventory_access_denial") {
          throw new Error("network blip");
        }
        return { data: null, error: { message: "record_not_found: no permitted outbound order exists for x" } };
      },
    } as unknown as CustomerPortalWarehouseOrderQueryClient;
    await assert.rejects(
      () => getCustomerPortalOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalWarehouseOrderQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
    assert.equal(calls.length, 2);
  });
});

describe("listCustomerPortalOutboundOrders", () => {
  test("defaults filters to null and limit to 50, forwards cursor params", async () => {
    const { client, calls } = fakeRpcClient({ data: [ORDER_ROW], error: null });
    const result = await listCustomerPortalOutboundOrders(client, TENANT_ID, ACTOR_ID, { cursorUpdatedAt: "2026-08-01T00:00:00.000Z", cursorId: ORDER_ID });
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_warehouse_id: null,
      p_status_filter: null,
      p_cursor_updated_at: "2026-08-01T00:00:00.000Z",
      p_cursor_id: ORDER_ID,
      p_limit: 50,
    });
  });

  test("forwards warehouseId/statusFilter and a custom limit", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalOutboundOrders(client, TENANT_ID, ACTOR_ID, { warehouseId: WAREHOUSE_ID, statusFilter: "confirmed", limit: 10 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_warehouse_id: WAREHOUSE_ID,
      p_status_filter: "confirmed",
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 10,
    });
  });

  test("returns an empty array when the RPC returns null data", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalOutboundOrders(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });

  test("propagates a non-record_not_found RPC error (e.g. invalid_cursor)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied" } });
    await assert.rejects(() => listCustomerPortalOutboundOrders(client, TENANT_ID, ACTOR_ID, { cursorId: ORDER_ID }));
  });
});

describe("listCustomerPortalOutboundOrderLines", () => {
  test("takes no tenantId -- mirrors the RPC's own tenant-id-less signature", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: LINE_ID,
          outbound_order_id: ORDER_ID,
          line_number: 1,
          item_master_id: ITEM_ID,
          requested_uom_code: "PCS",
          requested_quantity: "5",
          lot_controlled: false,
          serial_controlled: false,
          expiry_controlled: false,
          record_version: 1,
          updated_at: "2026-08-17T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await listCustomerPortalOutboundOrderLines(client, ACTOR_ID, ORDER_ID);
    assert.equal(result.length, 1);
    assert.equal(result[0]?.requestedQuantity, 5);
    assert.deepEqual(calls[0]?.args, { p_outbound_order_id: ORDER_ID, p_actor_auth_user_id: ACTOR_ID });
  });

  test("returns an empty array when the RPC returns null data", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalOutboundOrderLines(client, ACTOR_ID, ORDER_ID);
    assert.deepEqual(result, []);
  });

  test("propagates record_not_found with .code set (order missing or forbidden)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted outbound order exists for x" } });
    await assert.rejects(
      () => listCustomerPortalOutboundOrderLines(client, ACTOR_ID, ORDER_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalWarehouseOrderQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });
});

// ---------------------------------------------------------------------------
// Inbound half (ISS-2026-120).
// ---------------------------------------------------------------------------

const INBOUND_ORDER_ROW = {
  id: ORDER_ID,
  warehouse_id: WAREHOUSE_ID,
  owner_account_id: OWNER_ID,
  inbound_number: "WMSIN-2026-000001",
  source_type: "manual",
  expected_date: "2026-09-04",
  appointment_window_start: "2026-09-04T02:00:00.000Z",
  appointment_window_end: "2026-09-04T05:00:00.000Z",
  status: "scheduled",
  cancelled_reason: null,
  record_version: 2,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("getCustomerPortalInboundOrder", () => {
  test("maps the RPC's own single row, including the two inbound-only projections", async () => {
    const { client, calls } = fakeRpcClient({ data: [INBOUND_ORDER_ROW], error: null });
    const result = await getCustomerPortalInboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID);
    assert.equal(result.status, "scheduled");
    assert.equal(result.inboundNumber, "WMSIN-2026-000001");
    assert.equal(result.appointmentWindowStart, "2026-09-04T02:00:00.000Z");
    assert.equal(result.appointmentWindowEnd, "2026-09-04T05:00:00.000Z");
    assert.equal(result.expectedDate, "2026-09-04");
    assert.deepEqual(calls[0], {
      fn: "get_customer_portal_inbound_order",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_inbound_order_id: ORDER_ID },
    });
  });

  test("an unscheduled inbound order degrades its window to null rather than rejecting the row", async () => {
    const { client } = fakeRpcClient({
      data: [{ ...INBOUND_ORDER_ROW, status: "draft", expected_date: null, appointment_window_start: null, appointment_window_end: null }],
      error: null,
    });
    const result = await getCustomerPortalInboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID);
    assert.equal(result.status, "draft");
    assert.equal(result.expectedDate, null);
    assert.equal(result.appointmentWindowStart, null);
    assert.equal(result.appointmentWindowEnd, null);
  });

  test("propagates record_not_found with .code set, and records the denial under its own resource_type", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted inbound order exists for x" } });
    await assert.rejects(
      () => getCustomerPortalInboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID),
      (error: unknown) => error instanceof CustomerPortalWarehouseOrderQueryError && error.code === "record_not_found",
    );
    // The denial audit must be a second, separate call -- an audit insert cannot
    // survive the RAISE inside the RPC's own transaction.
    assert.equal(calls.length, 2);
    assert.equal(calls[1]?.fn, "record_customer_inventory_access_denial");
    assert.equal(calls[1]?.args["p_resource_type"], "inbound_order");
  });
});

describe("listCustomerPortalInboundOrders", () => {
  test("passes every filter and cursor param under its exact RPC name", async () => {
    const { client, calls } = fakeRpcClient({ data: [INBOUND_ORDER_ROW], error: null });
    const rows = await listCustomerPortalInboundOrders(client, TENANT_ID, ACTOR_ID, {
      warehouseId: WAREHOUSE_ID,
      statusFilter: "scheduled",
      cursorUpdatedAt: "2026-08-16T00:00:00.000Z",
      cursorId: LINE_ID,
      limit: 25,
    });
    assert.equal(rows.length, 1);
    assert.deepEqual(calls[0], {
      fn: "list_customer_portal_inbound_orders",
      args: {
        p_tenant_id: TENANT_ID,
        p_actor_auth_user_id: ACTOR_ID,
        p_warehouse_id: WAREHOUSE_ID,
        p_status_filter: "scheduled",
        p_cursor_updated_at: "2026-08-16T00:00:00.000Z",
        p_cursor_id: LINE_ID,
        p_limit: 25,
      },
    });
  });

  test("a null result is an empty list, never a throw", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    assert.deepEqual(await listCustomerPortalInboundOrders(client, TENANT_ID, ACTOR_ID), []);
  });

  test("wraps an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_cursor: p_cursor_updated_at is required" } });
    await assert.rejects(
      () => listCustomerPortalInboundOrders(client, TENANT_ID, ACTOR_ID),
      (error: unknown) => error instanceof CustomerPortalWarehouseOrderQueryError && error.code === "invalid_cursor",
    );
  });
});

describe("listCustomerPortalInboundOrderLines", () => {
  test("passes the RPC's own tenant-id-less signature and maps the expected-quantity shape", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: LINE_ID,
          inbound_order_id: ORDER_ID,
          line_number: 1,
          item_master_id: ITEM_ID,
          expected_uom_code: "PCS",
          expected_quantity: "9.000",
          lot_controlled: false,
          serial_controlled: false,
          expiry_controlled: false,
          record_version: 1,
          updated_at: "2026-08-17T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const lines = await listCustomerPortalInboundOrderLines(client, ACTOR_ID, ORDER_ID);
    assert.equal(lines.length, 1);
    // numeric arrives from PostgREST as a string; the contract coerces it.
    assert.equal(lines[0]?.expectedQuantity, 9);
    assert.deepEqual(calls[0], {
      fn: "list_customer_portal_inbound_order_lines",
      args: { p_inbound_order_id: ORDER_ID, p_actor_auth_user_id: ACTOR_ID },
    });
  });
});
