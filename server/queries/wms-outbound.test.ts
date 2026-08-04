import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getWmsOutboundShipment,
  listWmsOutboundShipments,
  listWmsShipmentPackages,
  listWmsShipmentIssueLines,
  getWmsBillingEligibilityEvent,
  listWmsBillingEligibilityEvents,
  WmsOutboundQueryError,
  type WmsOutboundQueryClient,
} from "./wms-outbound.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OUTBOUND_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsOutboundQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsOutboundQueryClient;
  return { client, calls };
}

const SHIPMENT_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  outbound_order_id: OUTBOUND_ORDER_ID,
  owner_account_id: OWNER_ID,
  shipment_number: "WMSSHIP-2026-000001",
  idempotency_key: "idem-ship-1",
  status: "staging",
  dock_location_id: null,
  vehicle_ref: null,
  loaded_at: null,
  loaded_by_auth_user_id: null,
  loaded_by_label: null,
  load_movement_id: null,
  custody_confirmed_by_label: null,
  custody_confirmed_reason: null,
  custody_confirmed_at: null,
  shipped_at: null,
  shipped_by_auth_user_id: null,
  shipped_by_label: null,
  consumption_movement_id: null,
  is_partial_fulfillment: false,
  partial_fulfillment_reason: null,
  cancelled_at: null,
  cancelled_by_auth_user_id: null,
  cancelled_by_label: null,
  cancelled_reason: null,
  record_version: 1,
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

describe("getWmsOutboundShipment", () => {
  test("parses the single-row response", async () => {
    const { client, calls } = fakeRpcClient({ data: [SHIPMENT_ROW], error: null });
    const shipment = await getWmsOutboundShipment(client, SHIPMENT_ID, ACTOR_ID);
    assert.equal(shipment.id, SHIPMENT_ID);
    assert.equal(calls[0]?.fn, "get_wms_outbound_shipment");
    assert.deepEqual(calls[0]?.args, { p_shipment_id: SHIPMENT_ID, p_actor_auth_user_id: ACTOR_ID });
  });

  test("throws WmsOutboundQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: nope" } });
    await assert.rejects(() => getWmsOutboundShipment(client, SHIPMENT_ID, ACTOR_ID), WmsOutboundQueryError);
  });

  test("throws WmsOutboundQueryError when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getWmsOutboundShipment(client, SHIPMENT_ID, ACTOR_ID), WmsOutboundQueryError);
  });
});

describe("listWmsOutboundShipments", () => {
  test("defaults p_limit to 50 and passes null filters when omitted", async () => {
    const { client, calls } = fakeRpcClient({ data: [SHIPMENT_ROW], error: null });
    const rows = await listWmsOutboundShipments(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_outbound_order_id: null,
      p_warehouse_id: null,
      p_owner_account_id: null,
      p_status_filter: null,
      p_limit: 50,
    });
  });

  test("passes explicit filters through", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWmsOutboundShipments(client, TENANT_ID, ACTOR_ID, { outboundOrderId: OUTBOUND_ORDER_ID, statusFilter: "shipped", limit: 10 });
    assert.equal(calls[0]?.args.p_outbound_order_id, OUTBOUND_ORDER_ID);
    assert.equal(calls[0]?.args.p_status_filter, "shipped");
    assert.equal(calls[0]?.args.p_limit, 10);
  });

  test("returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listWmsOutboundShipments(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

const PACKAGE_ID = "923e4567-e89b-12d3-a456-426614174000";
const PACKAGE_LINE_ID = "a23e4567-e89b-12d3-a456-426614174000";
const PICK_TASK_ID = "b23e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "c23e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "d23e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "e23e4567-e89b-12d3-a456-426614174000";

describe("listWmsShipmentPackages", () => {
  test("maps membership rows", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ id: PACKAGE_ID, tenant_id: TENANT_ID, shipment_id: SHIPMENT_ID, package_id: PACKAGE_ID, idempotency_key: "idem-1", added_at: "2026-08-04T00:00:00.000Z", added_by_auth_user_id: null, added_by_label: null }],
      error: null,
    });
    const rows = await listWmsShipmentPackages(client, SHIPMENT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.packageId, PACKAGE_ID);
    assert.equal(calls[0]?.fn, "list_wms_shipment_packages");
  });
});

describe("listWmsShipmentIssueLines", () => {
  test("maps traceability rows", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          id: PACKAGE_LINE_ID,
          tenant_id: TENANT_ID,
          shipment_id: SHIPMENT_ID,
          package_id: PACKAGE_ID,
          package_line_id: PACKAGE_LINE_ID,
          pick_task_id: PICK_TASK_ID,
          reservation_id: RESERVATION_ID,
          item_master_id: ITEM_ID,
          owner_account_id: OWNER_ID,
          uom_code: "PCS",
          lot_number: null,
          serial_number: null,
          expiry_date: null,
          quantity: "30",
          movement_id: MOVEMENT_ID,
          created_at: "2026-08-04T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listWmsShipmentIssueLines(client, SHIPMENT_ID, ACTOR_ID);
    assert.equal(rows[0]?.reservationId, RESERVATION_ID);
    assert.equal(rows[0]?.quantity, 30);
  });
});

describe("getWmsBillingEligibilityEvent / listWmsBillingEligibilityEvents", () => {
  const EVENT_ROW = {
    id: EVENT_ID,
    tenant_id: TENANT_ID,
    warehouse_id: WAREHOUSE_ID,
    owner_account_id: OWNER_ID,
    outbound_order_id: OUTBOUND_ORDER_ID,
    shipment_id: SHIPMENT_ID,
    idempotency_key: "idem-ship-1",
    package_count: 1,
    line_count: 1,
    total_quantity: "30",
    weight_by_uom: { KG: 5 },
    shipped_at: "2026-08-04T02:00:00.000Z",
    created_at: "2026-08-04T02:00:00.000Z",
  };

  test("getWmsBillingEligibilityEvent parses the single-row response", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    const event = await getWmsBillingEligibilityEvent(client, EVENT_ID, ACTOR_ID);
    assert.equal(event.id, EVENT_ID);
    assert.deepEqual(event.weightByUom, { KG: 5 });
    assert.equal(calls[0]?.fn, "get_wms_billing_eligibility_event");
  });

  test("listWmsBillingEligibilityEvents is bounded and filterable", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    const rows = await listWmsBillingEligibilityEvents(client, TENANT_ID, ACTOR_ID, { ownerAccountId: OWNER_ID, limit: 25 });
    assert.equal(rows.length, 1);
    assert.equal(calls[0]?.args.p_owner_account_id, OWNER_ID);
    assert.equal(calls[0]?.args.p_limit, 25);
  });

  test("throws WmsOutboundQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: nope" } });
    await assert.rejects(() => getWmsBillingEligibilityEvent(client, EVENT_ID, ACTOR_ID), WmsOutboundQueryError);
  });
});
