import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWmsReceiptSession,
  parseWmsReceiptLine,
  StartWmsReceiptSessionInputSchema,
  RecordWmsReceiptLineCountInputSchema,
  ResolveWmsReceiptHoldInputSchema,
  WmsReceiptSessionSchema,
} from "./wms-receiving.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const INBOUND_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const SESSION_ID = "623e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "723e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "823e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "923e4567-e89b-12d3-a456-426614174000";
const INBOUND_LINE_ID = "a23e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "b23e4567-e89b-12d3-a456-426614174000";

describe("parseWmsReceiptSession", () => {
  test("maps an in_progress session row", () => {
    const session = parseWmsReceiptSession({
      id: SESSION_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      inbound_order_id: INBOUND_ORDER_ID,
      receiving_location_id: LOCATION_ID,
      idempotency_key: "idem-1",
      status: "in_progress",
      cancelled_reason: null,
      started_by: "rep",
      started_at: "2026-08-03T00:00:00.000Z",
      completed_at: null,
      record_version: 1,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(session.status, "in_progress");
    assert.equal(session.completedAt, null);
  });

  test("rejects an invalid status via the schema", () => {
    assert.throws(() =>
      WmsReceiptSessionSchema.parse({
        id: SESSION_ID,
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        inboundOrderId: INBOUND_ORDER_ID,
        receivingLocationId: LOCATION_ID,
        idempotencyKey: "idem-1",
        status: "received",
        cancelledReason: null,
        startedBy: null,
        startedAt: "2026-08-03T00:00:00.000Z",
        completedAt: null,
        recordVersion: 1,
        createdAt: "2026-08-03T00:00:00.000Z",
        updatedAt: "2026-08-03T00:00:00.000Z",
      }),
    );
  });
});

describe("parseWmsReceiptLine", () => {
  test("maps a fully accepted line and derives the equation fields", () => {
    const line = parseWmsReceiptLine({
      id: LINE_ID,
      tenant_id: TENANT_ID,
      receipt_session_id: SESSION_ID,
      inbound_order_line_id: INBOUND_LINE_ID,
      line_number: 1,
      item_master_id: ITEM_ID,
      owner_account_id: OWNER_ID,
      expected_uom_code: "PCS",
      expected_quantity: "10",
      lot_controlled: false,
      serial_controlled: false,
      expiry_controlled: false,
      counted_uom_code: "PCS",
      counted_quantity: "10",
      accepted_quantity: "10",
      damaged_quantity: "0",
      held_quantity: "0",
      rejected_quantity: "0",
      over_quantity: "0",
      short_quantity: "0",
      lot_number: null,
      serial_number: null,
      expiry_date: null,
      condition_notes: null,
      status: "committed",
      over_approved: false,
      over_approved_reason: null,
      over_approved_by: null,
      over_approved_at: null,
      hold_resolved: false,
      hold_resolution: null,
      hold_resolved_reason: null,
      hold_resolved_by: null,
      hold_resolved_at: null,
      resolution_movement_id: null,
      movement_id: "c23e4567-e89b-12d3-a456-426614174000",
      record_version: 2,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(line.acceptedQuantity, 10);
    assert.equal(line.overQuantity, 0);
    assert.equal(line.status, "committed");
    assert.equal(line.movementId, "c23e4567-e89b-12d3-a456-426614174000");
  });
});

describe("StartWmsReceiptSessionInputSchema", () => {
  test("requires a non-empty idempotencyKey", () => {
    assert.throws(() =>
      StartWmsReceiptSessionInputSchema.parse({
        inboundOrderId: INBOUND_ORDER_ID,
        receivingLocationId: LOCATION_ID,
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("RecordWmsReceiptLineCountInputSchema", () => {
  test("rejects a negative quantity", () => {
    assert.throws(() =>
      RecordWmsReceiptLineCountInputSchema.parse({
        lineId: LINE_ID,
        uomCode: null,
        countedQuantity: -1,
        acceptedQuantity: 0,
        damagedQuantity: 0,
        heldQuantity: 0,
        rejectedQuantity: 0,
        lotNumber: null,
        serialNumber: null,
        expiryDate: null,
        conditionNotes: null,
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts an all-zero (fully short) count", () => {
    const parsed = RecordWmsReceiptLineCountInputSchema.parse({
      lineId: LINE_ID,
      uomCode: null,
      countedQuantity: 0,
      acceptedQuantity: 0,
      damagedQuantity: 0,
      heldQuantity: 0,
      rejectedQuantity: 0,
      lotNumber: null,
      serialNumber: null,
      expiryDate: null,
      conditionNotes: "nothing arrived",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.countedQuantity, 0);
  });
});

describe("ResolveWmsReceiptHoldInputSchema", () => {
  test("rejects an unrecognized resolution", () => {
    assert.throws(() =>
      ResolveWmsReceiptHoldInputSchema.parse({
        lineId: LINE_ID,
        resolution: "scrap",
        reason: "x",
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("requires a non-empty reason", () => {
    assert.throws(() =>
      ResolveWmsReceiptHoldInputSchema.parse({
        lineId: LINE_ID,
        resolution: "release_to_stock",
        reason: "",
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
