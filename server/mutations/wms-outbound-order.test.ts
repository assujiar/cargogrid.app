import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  prepareWmsOutboundFromShipment,
  createManualWmsOutboundOrder,
  addWmsOutboundOrderLine,
  addWmsOutboundOrderLines,
  confirmWmsOutboundOrder,
  cancelWmsOutboundOrder,
  WmsOutboundOrderMutationError,
  type WmsOutboundOrderMutationRpcClient,
} from "./wms-outbound-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "823e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "923e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsOutboundOrderMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsOutboundOrderMutationRpcClient;
  return { client, calls };
}

const ORDER_ROW = {
  id: ORDER_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  owner_account_id: ACCOUNT_ID,
  outbound_number: "WMSOUT-2026-000001",
  source_type: "shipment_order",
  source_shipment_order_id: SHIPMENT_ID,
  source_reason: null,
  idempotency_key: null,
  requested_ship_date: null,
  status: "draft",
  cancelled_reason: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const LINE_ROW = {
  id: LINE_ID,
  tenant_id: TENANT_ID,
  outbound_order_id: ORDER_ID,
  line_number: 1,
  item_master_id: ITEM_ID,
  requested_uom_code: "PCS",
  requested_quantity: "10",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  notes: null,
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("prepareWmsOutboundFromShipment", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [ORDER_ROW], error: null });
    const order = await prepareWmsOutboundFromShipment(client, {
      tenantId: TENANT_ID,
      shipmentOrderId: SHIPMENT_ID,
      warehouseId: WAREHOUSE_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(order.sourceShipmentOrderId, SHIPMENT_ID);
    assert.equal(calls[0]?.fn, "prepare_wms_outbound_from_shipment");
  });

  test("classifies source_not_confirmed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "source_not_confirmed: shipment order x is draft (must be confirmed)" } });
    await assert.rejects(
      () => prepareWmsOutboundFromShipment(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, warehouseId: WAREHOUSE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundOrderMutationError && err.code === "source_not_confirmed",
    );
  });
});

describe("createManualWmsOutboundOrder", () => {
  test("classifies invalid_reason", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_reason: a source reason is required" } });
    await assert.rejects(
      () =>
        createManualWmsOutboundOrder(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          ownerAccountId: ACCOUNT_ID,
          sourceReason: "x",
          idempotencyKey: "idem-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsOutboundOrderMutationError && err.code === "invalid_reason",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        createManualWmsOutboundOrder(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          ownerAccountId: ACCOUNT_ID,
          sourceReason: "x",
          idempotencyKey: "idem-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsOutboundOrderMutationError && err.code === "mutation_failed",
    );
  });
});

describe("addWmsOutboundOrderLine", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [LINE_ROW], error: null });
    const line = await addWmsOutboundOrderLine(client, {
      outboundOrderId: ORDER_ID,
      itemMasterId: ITEM_ID,
      requestedUomCode: "PCS",
      requestedQuantity: 10,
      notes: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(line.requestedQuantity, 10);
    assert.equal(calls[0]?.fn, "add_wms_outbound_order_line");
  });

  test("classifies item_not_eligible", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "item_not_eligible: x is not owned by the same account" } });
    await assert.rejects(
      () =>
        addWmsOutboundOrderLine(client, {
          outboundOrderId: ORDER_ID,
          itemMasterId: ITEM_ID,
          requestedUomCode: "PCS",
          requestedQuantity: 10,
          notes: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsOutboundOrderMutationError && err.code === "item_not_eligible",
    );
  });
});

describe("addWmsOutboundOrderLines", () => {
  test("maps each element to the RPC's own snake_case shape", async () => {
    const { client, calls } = fakeRpcClient({ data: [LINE_ROW], error: null });
    const lines = await addWmsOutboundOrderLines(client, {
      outboundOrderId: ORDER_ID,
      lines: [{ itemMasterId: ITEM_ID, requestedUomCode: "PCS", requestedQuantity: 10, notes: "bulk" }],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(lines.length, 1);
    const sentLines = calls[0]?.args.p_lines as Record<string, unknown>[];
    assert.equal(sentLines[0]?.item_master_id, ITEM_ID);
    assert.equal(sentLines[0]?.requested_uom_code, "PCS");
  });
});

describe("confirmWmsOutboundOrder", () => {
  test("classifies outbound_not_ready", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "outbound_not_ready: x is not ready to confirm" } });
    await assert.rejects(
      () => confirmWmsOutboundOrder(client, { outboundOrderId: ORDER_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsOutboundOrderMutationError && err.code === "outbound_not_ready",
    );
  });
});

describe("cancelWmsOutboundOrder", () => {
  test("sends a null reason through unchanged (no-op path)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ORDER_ROW, status: "cancelled", cancelled_reason: "x" }], error: null });
    const order = await cancelWmsOutboundOrder(client, { outboundOrderId: ORDER_ID, reason: null, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(order.status, "cancelled");
    assert.equal(calls[0]?.args.p_reason, null);
  });
});
