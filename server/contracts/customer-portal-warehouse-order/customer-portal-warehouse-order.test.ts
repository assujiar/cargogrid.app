import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerWarehouseOrder,
  parseCustomerWarehouseOrderLine,
  CustomerWarehouseOrderCursorSchema,
  CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS,
} from "./customer-portal-warehouse-order.ts";

const ORDER_ID = "123e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "223e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "423e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseCustomerWarehouseOrder", () => {
  test("maps a full order row", () => {
    const row = parseCustomerWarehouseOrder({
      id: ORDER_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: OWNER_ID,
      outbound_number: "WMSOUT-2026-000001",
      source_type: "manual",
      requested_ship_date: "2026-09-01",
      status: "confirmed",
      cancelled_reason: null,
      record_version: 2,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(row.status, "confirmed");
    assert.equal(row.outboundNumber, "WMSOUT-2026-000001");
    assert.equal(row.cancelledReason, null);
  });

  test("maps a cancelled order with its own cancelled_reason", () => {
    const row = parseCustomerWarehouseOrder({
      id: ORDER_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: OWNER_ID,
      outbound_number: "WMSOUT-2026-000002",
      source_type: "shipment_order",
      requested_ship_date: null,
      status: "cancelled",
      cancelled_reason: "customer requested cancellation",
      record_version: 3,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(row.status, "cancelled");
    assert.equal(row.cancelledReason, "customer requested cancellation");
    assert.equal(row.requestedShipDate, null);
  });

  test("rejects a row with an unrecognized status (never invent a status the source data does not carry)", () => {
    assert.throws(() =>
      parseCustomerWarehouseOrder({
        id: ORDER_ID,
        warehouse_id: WAREHOUSE_ID,
        owner_account_id: OWNER_ID,
        outbound_number: "WMSOUT-2026-000003",
        source_type: "manual",
        requested_ship_date: null,
        status: "shipped",
        cancelled_reason: null,
        record_version: 1,
        created_at: "2026-08-01T00:00:00.000Z",
        updated_at: "2026-08-17T00:00:00.000Z",
      }),
    );
  });
});

describe("CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS", () => {
  test("covers exactly the three real database status values, no more, no less", () => {
    assert.deepEqual(Object.keys(CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS).sort(), ["cancelled", "confirmed", "draft"]);
  });
});

describe("parseCustomerWarehouseOrderLine", () => {
  test("maps a full line row and coerces requested_quantity to a number", () => {
    const row = parseCustomerWarehouseOrderLine({
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
    });
    assert.equal(row.requestedQuantity, 5);
    assert.equal(row.lineNumber, 1);
  });

  test("rejects a row missing a required field", () => {
    assert.throws(() =>
      parseCustomerWarehouseOrderLine({
        id: LINE_ID,
        outbound_order_id: ORDER_ID,
        line_number: 1,
        item_master_id: ITEM_ID,
        requested_uom_code: "PCS",
        // requested_quantity omitted -- required, not defaulted.
        lot_controlled: false,
        serial_controlled: false,
        expiry_controlled: false,
        record_version: 1,
        updated_at: "2026-08-17T00:00:00.000Z",
      }),
    );
  });

  test("never carries a notes field even if the raw row leaks one (parse function only reads a fixed field set)", () => {
    const row = parseCustomerWarehouseOrderLine({
      id: LINE_ID,
      outbound_order_id: ORDER_ID,
      line_number: 1,
      item_master_id: ITEM_ID,
      requested_uom_code: "PCS",
      requested_quantity: 5,
      lot_controlled: false,
      serial_controlled: false,
      expiry_controlled: false,
      record_version: 1,
      updated_at: "2026-08-17T00:00:00.000Z",
      notes: "internal staff note -- must never surface",
    });
    assert.equal((row as Record<string, unknown>).notes, undefined);
  });
});

describe("CustomerWarehouseOrderCursorSchema", () => {
  test("accepts both cursor fields omitted (first page)", () => {
    assert.doesNotThrow(() => CustomerWarehouseOrderCursorSchema.parse({}));
  });

  test("accepts both cursor fields supplied together", () => {
    assert.doesNotThrow(() => CustomerWarehouseOrderCursorSchema.parse({ cursorUpdatedAt: "2026-08-17T00:00:00.000Z", cursorId: ORDER_ID }));
  });

  test("rejects cursorId supplied without cursorUpdatedAt (a half-cursor must fail loud, not silently return an empty page)", () => {
    assert.throws(() => CustomerWarehouseOrderCursorSchema.parse({ cursorId: ORDER_ID }));
  });
});
