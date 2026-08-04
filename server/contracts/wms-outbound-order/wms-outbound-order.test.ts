import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWmsOutboundOrder,
  parseWmsOutboundOrderLine,
  parseWmsOutboundReadiness,
  CreateManualWmsOutboundOrderInputSchema,
  AddWmsOutboundOrderLinesInputSchema,
  WmsOutboundOrderSchema,
} from "./wms-outbound-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("parseWmsOutboundOrder", () => {
  test("maps a shipment-order-sourced draft row", () => {
    const order = parseWmsOutboundOrder({
      id: ORDER_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: ACCOUNT_ID,
      outbound_number: "WMSOUT-2026-000001",
      source_type: "shipment_order",
      source_shipment_order_id: "923e4567-e89b-12d3-a456-426614174000",
      source_reason: null,
      idempotency_key: null,
      requested_ship_date: null,
      status: "draft",
      cancelled_reason: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(order.sourceType, "shipment_order");
    assert.equal(order.status, "draft");
    assert.equal(order.sourceReason, null);
  });

  test("rejects an invalid status via the schema", () => {
    assert.throws(() =>
      WmsOutboundOrderSchema.parse({
        id: ORDER_ID,
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        ownerAccountId: ACCOUNT_ID,
        outboundNumber: "WMSOUT-2026-000001",
        sourceType: "manual",
        sourceShipmentOrderId: null,
        sourceReason: "test",
        idempotencyKey: "idem-1",
        requestedShipDate: null,
        status: "shipped",
        cancelledReason: null,
        recordVersion: 1,
        createdBy: null,
        createdAt: "2026-08-03T00:00:00.000Z",
        updatedAt: "2026-08-03T00:00:00.000Z",
      }),
    );
  });
});

describe("parseWmsOutboundOrderLine", () => {
  test("maps a line with control-flag snapshots", () => {
    const line = parseWmsOutboundOrderLine({
      id: LINE_ID,
      tenant_id: TENANT_ID,
      outbound_order_id: ORDER_ID,
      line_number: 1,
      item_master_id: ITEM_ID,
      requested_uom_code: "PCS",
      requested_quantity: "10",
      lot_controlled: true,
      serial_controlled: false,
      expiry_controlled: true,
      notes: null,
      record_version: 1,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(line.requestedQuantity, 10);
    assert.equal(line.lotControlled, true);
    assert.equal(line.expiryControlled, true);
  });
});

describe("parseWmsOutboundReadiness", () => {
  test("maps a ready readiness row", () => {
    const readiness = parseWmsOutboundReadiness({
      has_lines: true,
      warehouse_active: true,
      owner_active: true,
      source_shipment_valid: true,
      invalid_line_count: 0,
      ready: true,
    });
    assert.equal(readiness.ready, true);
    assert.equal(readiness.sourceShipmentValid, true);
    assert.equal(readiness.invalidLineCount, 0);
  });

  test("maps a not-ready row when the source shipment is no longer confirmed", () => {
    const readiness = parseWmsOutboundReadiness({
      has_lines: true,
      warehouse_active: true,
      owner_active: true,
      source_shipment_valid: false,
      invalid_line_count: 0,
      ready: false,
    });
    assert.equal(readiness.ready, false);
    assert.equal(readiness.sourceShipmentValid, false);
  });
});

describe("CreateManualWmsOutboundOrderInputSchema", () => {
  test("requires a non-empty sourceReason and idempotencyKey", () => {
    assert.throws(() =>
      CreateManualWmsOutboundOrderInputSchema.parse({
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        ownerAccountId: ACCOUNT_ID,
        sourceReason: "",
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts an optional requestedShipDate", () => {
    const parsed = CreateManualWmsOutboundOrderInputSchema.parse({
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      ownerAccountId: ACCOUNT_ID,
      sourceReason: "no shipment yet",
      idempotencyKey: "idem-1",
      requestedShipDate: "2026-08-10",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.requestedShipDate, "2026-08-10");
  });
});

describe("AddWmsOutboundOrderLinesInputSchema", () => {
  test("rejects an empty lines array", () => {
    assert.throws(() =>
      AddWmsOutboundOrderLinesInputSchema.parse({
        outboundOrderId: ORDER_ID,
        lines: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts up to 200 lines and rejects 201", () => {
    const line = { itemMasterId: ITEM_ID, requestedUomCode: "PCS", requestedQuantity: 1 };
    const parsed = AddWmsOutboundOrderLinesInputSchema.parse({
      outboundOrderId: ORDER_ID,
      lines: Array.from({ length: 200 }, () => line),
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.lines.length, 200);
    assert.throws(() =>
      AddWmsOutboundOrderLinesInputSchema.parse({
        outboundOrderId: ORDER_ID,
        lines: Array.from({ length: 201 }, () => line),
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
