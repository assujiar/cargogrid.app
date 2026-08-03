import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWmsInboundOrder,
  parseWmsInboundOrderLine,
  parseWmsInboundReadiness,
  CreateManualWmsInboundInputSchema,
  AddWmsInboundOrderLinesInputSchema,
  WmsInboundOrderSchema,
} from "./wms-inbound.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("parseWmsInboundOrder", () => {
  test("maps a shipment-order-sourced draft row", () => {
    const order = parseWmsInboundOrder({
      id: ORDER_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: ACCOUNT_ID,
      inbound_number: "WMSIN-2026-000001",
      source_type: "shipment_order",
      source_shipment_order_id: "923e4567-e89b-12d3-a456-426614174000",
      source_reason: null,
      idempotency_key: null,
      expected_date: null,
      appointment_window_start: null,
      appointment_window_end: null,
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
      WmsInboundOrderSchema.parse({
        id: ORDER_ID,
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        ownerAccountId: ACCOUNT_ID,
        inboundNumber: "WMSIN-2026-000001",
        sourceType: "manual",
        sourceShipmentOrderId: null,
        sourceReason: "test",
        idempotencyKey: "idem-1",
        expectedDate: null,
        appointmentWindowStart: null,
        appointmentWindowEnd: null,
        status: "received",
        cancelledReason: null,
        recordVersion: 1,
        createdBy: null,
        createdAt: "2026-08-03T00:00:00.000Z",
        updatedAt: "2026-08-03T00:00:00.000Z",
      }),
    );
  });
});

describe("parseWmsInboundOrderLine", () => {
  test("maps a line with control-flag snapshots", () => {
    const line = parseWmsInboundOrderLine({
      id: LINE_ID,
      tenant_id: TENANT_ID,
      inbound_order_id: ORDER_ID,
      line_number: 1,
      item_master_id: ITEM_ID,
      expected_uom_code: "PCS",
      expected_quantity: "10",
      lot_controlled: true,
      serial_controlled: false,
      expiry_controlled: true,
      notes: null,
      record_version: 1,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(line.expectedQuantity, 10);
    assert.equal(line.lotControlled, true);
    assert.equal(line.expiryControlled, true);
  });
});

describe("parseWmsInboundReadiness", () => {
  test("maps a ready readiness row", () => {
    const readiness = parseWmsInboundReadiness({
      has_lines: true,
      warehouse_active: true,
      owner_active: true,
      invalid_line_count: 0,
      ready: true,
    });
    assert.equal(readiness.ready, true);
    assert.equal(readiness.invalidLineCount, 0);
  });
});

describe("CreateManualWmsInboundInputSchema", () => {
  test("requires a non-empty sourceReason and idempotencyKey", () => {
    assert.throws(() =>
      CreateManualWmsInboundInputSchema.parse({
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
});

describe("AddWmsInboundOrderLinesInputSchema", () => {
  test("rejects an empty lines array", () => {
    assert.throws(() =>
      AddWmsInboundOrderLinesInputSchema.parse({
        inboundOrderId: ORDER_ID,
        lines: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts up to 200 lines and rejects 201", () => {
    const line = { itemMasterId: ITEM_ID, expectedUomCode: "PCS", expectedQuantity: 1 };
    const parsed = AddWmsInboundOrderLinesInputSchema.parse({
      inboundOrderId: ORDER_ID,
      lines: Array.from({ length: 200 }, () => line),
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.lines.length, 200);
    assert.throws(() =>
      AddWmsInboundOrderLinesInputSchema.parse({
        inboundOrderId: ORDER_ID,
        lines: Array.from({ length: 201 }, () => line),
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
